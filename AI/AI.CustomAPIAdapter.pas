unit AI.CustomAPIAdapter;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.SyncObjs, System.NetEncoding,
  System.Generics.Collections,
  System.Net.HttpClient, System.Net.URLClient, System.NetConsts,
  Winapi.Windows,
  Core.Messages, Core.Events, Core.AgentState,
  AI.ModelConfig, AI.IModel, Settings.Config,
  Utils.Logger, Utils.JsonHelper;

type
  TSSELineCallback = reference to procedure(const ALine: string);

  /// <summary>
  /// Custom TStream that intercepts HTTP response writes and extracts complete
  /// SSE lines in real-time. As THTTPClient receives chunks from the server,
  /// it calls Write() on this stream. We extract complete lines and invoke
  /// the callback for each one, enabling true streaming SSE processing.
  /// </summary>
  TSSEForwardStream = class(TStream)
  private
    // Thread safety: Write() is called from the HTTP receiving thread.
    // FlushRemaining() is called after the HTTP response completes.
    // FLock protects FLineBuffer to prevent race between Write and FlushRemaining.
  private
    FBuffer: string;       // Accumulated unprocessed data
    FProcessed: Integer;   // Index of first unprocessed byte in FBuffer
    FCallback: TSSELineCallback;
    FLock: TObject;
    procedure DoExtractLines;
  public
    constructor Create(ACallback: TSSELineCallback);
    destructor Destroy; override;
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
    /// <summary>Process any remaining buffered data that doesn't end with LF.</summary>
    procedure FlushRemaining;
  end;

  TCustomAPIAdapter = class(TInterfacedObject, IModel)
  private
    FModelInfo: TModelInfo;
    FApiKey: string;
    FLogger: TLogger;
    FMaxRetries: Integer;
    FRetryBaseDelayMs: Integer;
    FTimeout: Integer;

    function BuildRequestJson(ARequest: TCompletionRequest): TJSONObject;
    function BuildUrl: string;
    function ExecuteRequest(ARequest: TCompletionRequest): string;
    procedure ProcessSSELine(const ALine: string;
      AOutput: TAssistantMessage;
      var ACurrentBlockType: string; var ACurrentContentIndex: Integer;
      var ACurrentToolCallId: string; var ACurrentToolCallName: string;
      var APartialArgs: string;
      AOnEvent: TStreamEventCallback; AAbortSignal: TAbortController;
      var ADone: Boolean);
    procedure ProcessChunk(AChunk: TJSONObject; AOutput: TAssistantMessage;
      var ACurrentBlockType: string; var ACurrentContentIndex: Integer;
      var ACurrentToolCallId: string; var ACurrentToolCallName: string;
      var APartialArgs: string;
      AOnEvent: TStreamEventCallback);
    procedure FinishCurrentBlock(var ACurrentBlockType: string;
      ACurrentContentIndex: Integer; AOutput: TAssistantMessage;
      const ACurrentToolCallId, ACurrentToolCallName: string;
      var APartialArgs: string; AOnEvent: TStreamEventCallback);
    function ParsePartialJson(const AJson: string): TJSONObject;
    procedure SleepWithAbort(AMs: Integer; AAbortSignal: TAbortController);

  public
    constructor Create(const AModelInfo: TModelInfo;
      const AApiKey: string = '';
      ALogger: TLogger = nil;
      AMaxRetries: Integer = 3;
      ARetryBaseDelayMs: Integer = 2000;
      ATimeout: Integer = 60000);
    destructor Destroy; override;

    // IModel
    function GetModelInfo: TModelInfo;
    function GetId: string;
    function GetName: string;
    function GetProvider: string;
    function GetBaseUrl: string;

    procedure Stream(ARequest: TCompletionRequest;
      AOnEvent: TStreamEventCallback;
      AAbortSignal: TAbortController = nil);

    function Complete(ARequest: TCompletionRequest;
      AAbortSignal: TAbortController = nil): TAssistantMessage;

    function GetModels: TModelList;
  end;

implementation

{ TSSEForwardStream }

constructor TSSEForwardStream.Create(ACallback: TSSELineCallback);
begin
  inherited Create;
  FCallback := ACallback;
  FBuffer := '';
  FProcessed := 1;
  FLock := TObject.Create;
end;

destructor TSSEForwardStream.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TSSEForwardStream.Read(var Buffer; Count: Longint): Longint;
begin
  Result := 0; // Write-only stream
end;

function TSSEForwardStream.Write(const Buffer; Count: Longint): Longint;
var
  Bytes: TBytes;
  S: string;
begin
  if Count <= 0 then Exit(0);

  // Convert incoming raw bytes to UTF-8 string
  SetLength(Bytes, Count);
  Move(Buffer, Bytes[0], Count);
  S := TEncoding.UTF8.GetString(Bytes);

  TMonitor.Enter(FLock);
  try
    FBuffer := FBuffer + S;
    DoExtractLines;
  finally
    TMonitor.Exit(FLock);
  end;

  Result := Count;
end;

procedure TSSEForwardStream.DoExtractLines;
var
  P, LineStart: Integer;
  Line: string;
begin
  // Extract complete lines (delimited by LF) starting from FProcessed
  while True do
  begin
    P := Pos(#10, FBuffer, FProcessed);
    if P = 0 then
      Break;
    LineStart := FProcessed;
    FProcessed := P + 1;
    Line := Copy(FBuffer, LineStart, P - LineStart);
    // Strip trailing CR if present (CRLF normalization)
    if (Length(Line) > 0) and (Line[Length(Line)] = #13) then
      Line := Copy(Line, 1, Length(Line) - 1);
    if Assigned(FCallback) then
      FCallback(Line);
  end;
  // Compact buffer when all processed data has been consumed
  if FProcessed > 4096 then
  begin
    Delete(FBuffer, 1, FProcessed - 1);
    FProcessed := 1;
  end;
end;

function TSSEForwardStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  Result := 0;
end;

procedure TSSEForwardStream.FlushRemaining;
var
  Remaining: string;
begin
  TMonitor.Enter(FLock);
  try
    Remaining := Copy(FBuffer, FProcessed, MaxInt);
    if Remaining <> '' then
    begin
      FBuffer := '';
      FProcessed := 1;
      if Assigned(FCallback) then
        FCallback(Remaining);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

{ TCustomAPIAdapter }

constructor TCustomAPIAdapter.Create(const AModelInfo: TModelInfo;
  const AApiKey: string; ALogger: TLogger;
  AMaxRetries, ARetryBaseDelayMs, ATimeout: Integer);
begin
  inherited Create;
  FModelInfo := AModelInfo;
  FApiKey := AApiKey;
  FLogger := ALogger;
  FMaxRetries := AMaxRetries;
  FRetryBaseDelayMs := ARetryBaseDelayMs;
  FTimeout := ATimeout;
end;

destructor TCustomAPIAdapter.Destroy;
begin
  inherited;
end;

function TCustomAPIAdapter.GetModelInfo: TModelInfo;
begin
  Result := FModelInfo;
end;

function TCustomAPIAdapter.GetId: string;
begin
  Result := FModelInfo.Id;
end;

function TCustomAPIAdapter.GetName: string;
begin
  Result := FModelInfo.Name;
end;

function TCustomAPIAdapter.GetProvider: string;
begin
  Result := FModelInfo.Provider;
end;

function TCustomAPIAdapter.GetBaseUrl: string;
begin
  Result := FModelInfo.BaseUrl;
end;

function TCustomAPIAdapter.BuildRequestJson(ARequest: TCompletionRequest): TJSONObject;
var
  MsgArr, ToolArr: TJSONArray;
  i: Integer;
  ApiMsg: TApiChatMessage;
begin
  Result := TJSONObject.Create;
  Result.AddPair('model', ARequest.Model);
  Result.AddPair('stream', TJSONBool.Create(ARequest.Stream));
  Result.AddPair('max_tokens', TJSONNumber.Create(ARequest.MaxTokens));
  Result.AddPair('temperature', TJSONNumber.Create(ARequest.Temperature));

  // TopP / FrequencyPenalty / PresencePenalty (only send non-defaults)
  if ARequest.TopP <> 1.0 then
    Result.AddPair('top_p', TJSONNumber.Create(ARequest.TopP));
  if ARequest.FrequencyPenalty <> 0.0 then
    Result.AddPair('frequency_penalty', TJSONNumber.Create(ARequest.FrequencyPenalty));
  if ARequest.PresencePenalty <> 0.0 then
    Result.AddPair('presence_penalty', TJSONNumber.Create(ARequest.PresencePenalty));

  // ThinkingLevel / reasoning (only for reasoning-capable models)
  if (ARequest.ThinkingLevel <> tlOff) and FModelInfo.Reasoning then
    Result.AddPair('reasoning_effort', ThinkingLevelToString(ARequest.ThinkingLevel));

  MsgArr := TJSONArray.Create;

  // System prompt
  if ARequest.SystemPrompt <> '' then
  begin
    ApiMsg := TApiChatMessage.CreateSystem(ARequest.SystemPrompt);
    MsgArr.AddElement(ApiMsg.ToJson);
  end;

  // Messages
  for i := 0 to High(ARequest.Messages) do
    MsgArr.AddElement(ARequest.Messages[i].ToJson);

  Result.AddPair('messages', MsgArr);

  // Tools
  if Length(ARequest.Tools) > 0 then
  begin
    ToolArr := TJSONArray.Create;
    for i := 0 to High(ARequest.Tools) do
      ToolArr.AddElement(ARequest.Tools[i].ToJson);
    Result.AddPair('tools', ToolArr);
    Result.AddPair('tool_choice', 'auto');
  end;
end;

function TCustomAPIAdapter.BuildUrl: string;
begin
  Result := FModelInfo.BaseUrl;
  if Assigned(FLogger) then
    FLogger.Info('[DIAG-BuildUrl] FModelInfo.BaseUrl=' + Result);
  if Result = '' then
    raise Exception.Create('API Endpoint is not configured. Please set the endpoint URL in Settings.');
  if (Result <> '') and (Result[Length(Result)] <> '/') then
    Result := Result + '/';
  if not Result.EndsWith('/completions') and not Result.EndsWith('/chat/completions') then
    Result := Result + 'chat/completions';
end;

function TCustomAPIAdapter.ExecuteRequest(ARequest: TCompletionRequest): string;
var
  HTTP: THTTPClient;
  RequestBody: TStringStream;
  ResponseBody: TStringStream;
  RequestJson: TJSONObject;
  Url: string;
begin
  HTTP := THTTPClient.Create;
  RequestBody := TStringStream.Create('', TEncoding.UTF8);
  ResponseBody := TStringStream.Create('', TEncoding.UTF8);
  try
    HTTP.ContentType := 'application/json';
    HTTP.Accept := 'application/json';
    HTTP.ConnectionTimeout := 30000;
    HTTP.ResponseTimeout := FTimeout;

    if FApiKey <> '' then
      HTTP.CustomHeaders['Authorization'] := 'Bearer ' + FApiKey;

    RequestJson := BuildRequestJson(ARequest);
    try
      RequestBody.WriteString(RequestJson.ToJSON);
    finally
      RequestJson.Free;
    end;
    RequestBody.Position := 0;

    Url := BuildUrl;

    if Assigned(FLogger) then
      FLogger.Debug('API request to: ' + Url);

    var HTTPResp := HTTP.Post(Url, RequestBody, ResponseBody);

    if (HTTPResp <> nil) and (HTTPResp.StatusCode <> 200) then
    begin
      var ErrorMsg := Format('HTTP %d: %s', [HTTPResp.StatusCode, HTTPResp.StatusText]);
      var RespBody := HTTPResp.ContentAsString(TEncoding.UTF8);
      if RespBody <> '' then
      begin
        var ErrJson := TJSONObject.ParseJSONValue(RespBody);
        if ErrJson <> nil then
        try
          var ErrObj := ErrJson.FindValue('error');
          if ErrObj <> nil then
            ErrorMsg := ErrorMsg + ' - ' + ErrObj.GetValue<string>('message', '');
        finally
          ErrJson.Free;
        end
        else if Length(RespBody) > 200 then
          ErrorMsg := ErrorMsg + ' - ' + Copy(RespBody, 1, 200)
        else
          ErrorMsg := ErrorMsg + ' - ' + RespBody;
      end;
      raise Exception.Create(ErrorMsg);
    end;

    Result := ResponseBody.DataString;
  finally
    ResponseBody.Free;
    RequestBody.Free;
    HTTP.Free;
  end;
end;

procedure TCustomAPIAdapter.Stream(ARequest: TCompletionRequest;
  AOnEvent: TStreamEventCallback; AAbortSignal: TAbortController);
var
  HTTP: THTTPClient;
  RequestBody: TStringStream;
  RequestJson: TJSONObject;
  Url: string;
  RetryCount: Integer;
  SSEStream: TSSEForwardStream;
  Output: TAssistantMessage;
  CurrentBlockType: string;
  CurrentContentIndex: Integer;
  CurrentToolCallId: string;
  CurrentToolCallName: string;
  PartialArgs: string;
  Done: Boolean;
  HTTPResp: IHTTPResponse;
begin
  RetryCount := 0;

  while RetryCount <= FMaxRetries do
  begin
    if (AAbortSignal <> nil) and AAbortSignal.IsAborted then
      Exit;

    // Initialize SSE state for this attempt
    Output := TAssistantMessage.Create;
    Output.Api := FModelInfo.Api;
    Output.Provider := FModelInfo.Provider;
    Output.Model := FModelInfo.Id;
    CurrentBlockType := '';
    CurrentContentIndex := -1;
    CurrentToolCallId := '';
    CurrentToolCallName := '';
    PartialArgs := '';
    Done := False;

    // Emit start event
    AOnEvent(TStartEvent.Create(Output.Clone as TAssistantMessage));

    HTTP := THTTPClient.Create;
    RequestBody := TStringStream.Create('', TEncoding.UTF8);
    try
      try
        HTTP.ContentType := 'application/json';
        HTTP.Accept := 'text/event-stream';
        HTTP.ConnectionTimeout := 30000;
        HTTP.ResponseTimeout := FTimeout;

        if FApiKey <> '' then
          HTTP.CustomHeaders['Authorization'] := 'Bearer ' + FApiKey;

        RequestJson := BuildRequestJson(ARequest);
        try
          RequestBody.WriteString(RequestJson.ToJSON);
        finally
          RequestJson.Free;
        end;
        RequestBody.Position := 0;

        Url := BuildUrl;

        if Assigned(FLogger) then
          FLogger.Info('API streaming request to: ' + Url + ' model=' + ARequest.Model);

        // Create SSE forwarding stream: HTTP response chunks are written here
        // in real-time. Each complete SSE line triggers ProcessSSELine immediately.
        SSEStream := TSSEForwardStream.Create(
          procedure(const ALine: string)
          var
            TrimmedLine: string;
          begin
            if not Done then
            begin
              // Log non-SSE lines (error responses from API are plain JSON, not SSE)
              TrimmedLine := ALine.Trim;
              if (TrimmedLine <> '') and not TrimmedLine.StartsWith('data:') and
                 not TrimmedLine.StartsWith(':') and Assigned(FLogger) then
                FLogger.Error('API non-SSE response line: ' + TrimmedLine);
              ProcessSSELine(ALine, Output, CurrentBlockType, CurrentContentIndex,
                CurrentToolCallId, CurrentToolCallName, PartialArgs,
                AOnEvent, AAbortSignal, Done);
            end;
          end);

        // HTTP.Post blocks until the entire response is received, BUT it calls
        // SSEStream.Write for each chunk as it arrives from the server.
        // This means SSE events are processed and callbacks fired in real-time
        // during the Post call, giving us true streaming behavior.
        try
          HTTPResp := HTTP.Post(Url, RequestBody, SSEStream);
          SSEStream.FlushRemaining;
        finally
          SSEStream.Free;
        end;

        // Check HTTP status — non-200 means the response body is likely an error JSON,
        // not SSE events. Done would be False because no SSE lines were parsed.
        if (HTTPResp <> nil) and (HTTPResp.StatusCode <> 200) then
        begin
          var ErrorDetail := '';
          // Try to read error body from response stream
          var RespBody := HTTPResp.ContentAsString(TEncoding.UTF8);
          if (RespBody <> '') then
          begin
            // Try to extract error message from JSON response
            var ErrJson := TJSONObject.ParseJSONValue(RespBody);
            if ErrJson <> nil then
            try
              var ErrObj := ErrJson.FindValue('error');
              if ErrObj <> nil then
                ErrorDetail := ErrObj.GetValue<string>('message', '')
              else
                ErrorDetail := Copy(RespBody, 1, 200);
            finally
              ErrJson.Free;
            end
            else
              ErrorDetail := Copy(RespBody, 1, 200);
          end;

          if ErrorDetail <> '' then
            ErrorDetail := ' - ' + ErrorDetail;

          // Friendly messages for common HTTP errors
          var FriendlyMsg := '';
          case HTTPResp.StatusCode of
            401: FriendlyMsg := 'Authentication failed. Please check your API Key.';
            403: FriendlyMsg := 'Access denied. Please check your API permissions.';
            404: FriendlyMsg := 'API endpoint not found. Please check your Endpoint URL.';
            429: FriendlyMsg := 'Rate limit exceeded. Please wait and try again.';
            500..599: FriendlyMsg := 'API server error. Please try again later.';
          end;

          var FullMsg := Format('HTTP %d: %s%s', [HTTPResp.StatusCode, HTTPResp.StatusText, ErrorDetail]);
          if FriendlyMsg <> '' then
            FullMsg := FriendlyMsg + ' (' + FullMsg + ')';

          if Assigned(FLogger) then
            FLogger.Error('API error: ' + FullMsg);
          raise Exception.Create(FullMsg);
        end;

        if Assigned(FLogger) then
          FLogger.Info('API streaming completed, Done=' + BoolToStr(Done, True));

        // If stream ended without [DONE], finish up
        if not Done then
        begin
          FinishCurrentBlock(CurrentBlockType, CurrentContentIndex,
            Output, CurrentToolCallId, CurrentToolCallName, PartialArgs, AOnEvent);
          // Transfer ownership of Output to TDoneEvent
          AOnEvent(TDoneEvent.Create(Output.StopReason, Output));
          Output := nil;  // Ownership transferred, don't free below
        end
        else
        begin
          // Done was signaled via [DONE] SSE — Output was already transferred
          // inside ProcessSSELine -> TDoneEvent. Release our local reference.
          Output := nil;
        end;

        Exit; // Success

      except
        on E: Exception do
        begin
          // Free Output only if ownership was NOT transferred to DoneEvent/ErrorEvent
          // (Done=True means ProcessSSELine already sent TDoneEvent which owns Output)
          if (not Done) and (Output <> nil) then
            FreeAndNil(Output);

          Inc(RetryCount);
          if Assigned(FLogger) then
            FLogger.Error(Format('API request error (attempt %d): %s', [RetryCount, E.Message]));
          if RetryCount > FMaxRetries then
          begin
            var ErrMsg := TAssistantMessage.Create;
            ErrMsg.StopReason := srError;
            ErrMsg.ErrorMessage := E.Message;
            ErrMsg.Content.Add(TTextContent.Create('Error: ' + E.Message));
            AOnEvent(TErrorEvent.Create(srError, ErrMsg));
            if Assigned(FLogger) then
              FLogger.Log(llError, 'API request failed after %d retries: %s', [RetryCount, E.Message]);
          end
          else
          begin
            if Assigned(FLogger) then
              FLogger.Log(llWarn, 'API request failed (attempt %d/%d): %s', [RetryCount, FMaxRetries + 1, E.Message]);
            SleepWithAbort(FRetryBaseDelayMs * RetryCount, AAbortSignal);
          end;
        end;
      end;
    finally
      RequestBody.Free;
      HTTP.Free;
    end;
  end;
end;

function TCustomAPIAdapter.Complete(ARequest: TCompletionRequest;
  AAbortSignal: TAbortController): TAssistantMessage;
var
  Response: string;
  Json, ChoiceObj, MsgObj, TCObj, FnObj: TJSONObject;
  Choices, ToolCallsArr: TJSONArray;
  ContentStr: string;
  i: Integer;
  TCId, TCName, TCArgs: string;
  ParsedArgs: TJSONObject;
begin
  ARequest.Stream := False;
  Response := ExecuteRequest(ARequest);

  // Parse as regular JSON (non-streaming response)
  Json := TJSONObject.ParseJSONValue(Response) as TJSONObject;
  if Json = nil then
  begin
    Result := TAssistantMessage.Create;
    Result.StopReason := srError;
    Result.ErrorMessage := 'No response received (invalid JSON)';
    Exit;
  end;

  try
    Choices := Json.GetValue('choices') as TJSONArray;
    if (Choices = nil) or (Choices.Count = 0) then
    begin
      Result := TAssistantMessage.Create;
      Result.StopReason := srError;
      Result.ErrorMessage := 'No choices in response';
      Exit;
    end;

    ChoiceObj := Choices.Items[0] as TJSONObject;
    Result := TAssistantMessage.Create;
    Result.Api := FModelInfo.Api;
    Result.Provider := FModelInfo.Provider;
    Result.Model := FModelInfo.Id;
    Result.StopReason := StringToStopReason(JsonGetStr(ChoiceObj, 'finish_reason', 'stop'));

    MsgObj := ChoiceObj.GetValue('message') as TJSONObject;
    if MsgObj <> nil then
    begin
      ContentStr := JsonGetStr(MsgObj, 'content', '');
      if ContentStr <> '' then
        Result.Content.Add(TTextContent.Create(ContentStr));

      // Parse tool_calls if present
      ToolCallsArr := MsgObj.GetValue('tool_calls') as TJSONArray;
      if ToolCallsArr <> nil then
      begin
        for i := 0 to ToolCallsArr.Count - 1 do
        begin
          TCObj := ToolCallsArr.Items[i] as TJSONObject;
          if TCObj = nil then Continue;
          TCId := JsonGetStr(TCObj, 'id', '');
          FnObj := TCObj.GetValue('function') as TJSONObject;
          if FnObj <> nil then
          begin
            TCName := JsonGetStr(FnObj, 'name', '');
            TCArgs := JsonGetStr(FnObj, 'arguments', '');
          end
          else
          begin
            TCName := '';
            TCArgs := '';
          end;
          ParsedArgs := ParsePartialJson(TCArgs);
          Result.Content.Add(TToolCall.Create(TCId, TCName, ParsedArgs));
        end;
      end;
    end;
  finally
    Json.Free;
  end;
end;

function TCustomAPIAdapter.GetModels: TModelList;
var
  HTTP: THTTPClient;
  ResponseBody: TStringStream;
  Json: TJSONObject;
  DataVal: TJSONArray;
  i: Integer;
  ModelInfo: TModelInfo;
  Url: string;
begin
  Result := TModelList.Create;
  HTTP := THTTPClient.Create;
  ResponseBody := TStringStream.Create('', TEncoding.UTF8);
  try
    // Set timeouts to prevent indefinite blocking
    HTTP.ConnectionTimeout := FTimeout;
    HTTP.ResponseTimeout := FTimeout;

    // Set auth header
    if FApiKey <> '' then
      HTTP.CustomHeaders['Authorization'] := 'Bearer ' + FApiKey;

    // Build models URL
    Url := FModelInfo.BaseUrl;
    if (Url <> '') and (Url[Length(Url)] <> '/') then
      Url := Url + '/';
    Url := StringReplace(Url, '/chat/completions', '', [rfIgnoreCase]);
    Url := StringReplace(Url, '/v1/completions', '/v1/models', [rfIgnoreCase]);
    Url := StringReplace(Url, '/completions', '/models', [rfIgnoreCase]);
    if not Url.EndsWith('/models') then
    begin
      // Endpoint may already contain /v1/ (e.g. "https://api.openai.com/v1/")
      // Avoid duplicating /v1/ — just append "models"
      if Url.EndsWith('/v1/') then
        Url := Url + 'models'
      else
        Url := Url + 'v1/models';
    end;

    try
      var HTTPResp := HTTP.Get(Url, ResponseBody);

      // Check HTTP status
      if (HTTPResp.StatusCode < 200) or (HTTPResp.StatusCode >= 300) then
        raise Exception.Create('HTTP ' + IntToStr(HTTPResp.StatusCode) + ': ' +
          Copy(ResponseBody.DataString, 1, 200));

      Json := TJSONObject.ParseJSONValue(ResponseBody.DataString) as TJSONObject;
      if Json <> nil then
      try
        DataVal := Json.GetValue('data') as TJSONArray;
        if DataVal <> nil then
        begin
          for i := 0 to DataVal.Count - 1 do
          begin
            ModelInfo := JsonToModelInfo(DataVal.Items[i] as TJSONObject);
            Result.Add(ModelInfo);
          end;
        end;
      finally
        Json.Free;
      end;
    except
      on E: Exception do
      begin
        if Assigned(FLogger) then
          FLogger.LogException(E, 'Failed to fetch models from ' + Url);
        raise;  // Re-raise so caller can report the error
      end;
    end;
  finally
    ResponseBody.Free;
    HTTP.Free;
  end;
end;

// --- SSE Line Processing ---

procedure TCustomAPIAdapter.ProcessSSELine(const ALine: string;
  AOutput: TAssistantMessage;
  var ACurrentBlockType: string; var ACurrentContentIndex: Integer;
  var ACurrentToolCallId: string; var ACurrentToolCallName: string;
  var APartialArgs: string;
  AOnEvent: TStreamEventCallback; AAbortSignal: TAbortController;
  var ADone: Boolean);
var
  Line, DataStr: string;
  Chunk: TJSONObject;
begin
  // Check abort signal
  if (AAbortSignal <> nil) and AAbortSignal.IsAborted then
  begin
    AOutput.StopReason := srAborted;
    AOutput.ErrorMessage := 'Request aborted';
    AOnEvent(TErrorEvent.Create(srAborted, AOutput));
    ADone := True;
    Exit;
  end;

  Line := ALine.Trim;

  // Skip empty lines and SSE comments
  if (Line = '') or Line.StartsWith(':') then
    Exit;

  // Parse SSE data lines
  if Line.StartsWith('data: ') or Line.StartsWith('data:') then
  begin
    if Line.StartsWith('data: ') then
      DataStr := Copy(Line, 7, MaxInt)
    else
      DataStr := Copy(Line, 6, MaxInt);

    DataStr := DataStr.Trim;

    // Check for stream end
    if DataStr = '[DONE]' then
    begin
      FinishCurrentBlock(ACurrentBlockType, ACurrentContentIndex,
        AOutput, ACurrentToolCallId, ACurrentToolCallName, APartialArgs, AOnEvent);
      AOnEvent(TDoneEvent.Create(AOutput.StopReason, AOutput));
      ADone := True;
      Exit;
    end;

    // Parse JSON chunk
    Chunk := TJSONObject.ParseJSONValue(DataStr) as TJSONObject;
    if Chunk <> nil then
    try
      try
        ProcessChunk(Chunk, AOutput, ACurrentBlockType, ACurrentContentIndex,
          ACurrentToolCallId, ACurrentToolCallName, APartialArgs, AOnEvent);
      except
        on E: Exception do
        begin
          if Assigned(FLogger) then
            FLogger.Debug('Failed to process SSE chunk: ' + E.Message + ' -- ' + DataStr);
        end;
      end;
    finally
      Chunk.Free;
    end;
  end;
end;

procedure TCustomAPIAdapter.ProcessChunk(AChunk: TJSONObject;
  AOutput: TAssistantMessage;
  var ACurrentBlockType: string; var ACurrentContentIndex: Integer;
  var ACurrentToolCallId: string; var ACurrentToolCallName: string;
  var APartialArgs: string;
  AOnEvent: TStreamEventCallback);
var
  Choices: TJSONArray;
  Choice: TJSONObject;
  Delta: TJSONObject;
  Content, Reasoning: string;
  ToolCallsArr: TJSONArray;
  TCObj, FnObj: TJSONObject;
  TCId, TCName, TCArgs: string;
  FinishReason: string;
  UsageObj: TJSONObject;
  i: Integer;
begin
  // Extract usage if present
  UsageObj := AChunk.GetValue('usage') as TJSONObject;
  if UsageObj <> nil then
  begin
    var U := AOutput.Usage;
    U.Input := JsonGetInt(UsageObj, 'prompt_tokens', 0);
    U.Output := JsonGetInt(UsageObj, 'completion_tokens', 0);
    U.TotalTokens := JsonGetInt(UsageObj, 'total_tokens', 0);
    AOutput.Usage := U;
  end;

  // Process choices
  Choices := AChunk.GetValue('choices') as TJSONArray;
  if (Choices = nil) or (Choices.Count = 0) then
    Exit;

  Choice := Choices.Items[0] as TJSONObject;
  if Choice = nil then
    Exit;

  // Check finish reason
  FinishReason := JsonGetStr(Choice, 'finish_reason', '');
  if FinishReason <> '' then
    AOutput.StopReason := StringToStopReason(FinishReason);

  // Get delta
  Delta := Choice.GetValue('delta') as TJSONObject;
  if Delta = nil then
    Exit;

  // Process text content
  Content := JsonGetStr(Delta, 'content', '');
  if Content <> '' then
  begin
    if ACurrentBlockType <> 'text' then
    begin
      FinishCurrentBlock(ACurrentBlockType, ACurrentContentIndex,
        AOutput, ACurrentToolCallId, ACurrentToolCallName, APartialArgs, AOnEvent);
      ACurrentBlockType := 'text';
      Inc(ACurrentContentIndex);
    end;

    AOutput.Content.Add(TTextContent.Create(Content));
    AOnEvent(TTextDeltaEvent.Create(ACurrentContentIndex, Content, nil));
  end;

  // Process reasoning/thinking content
  Reasoning := JsonGetStr(Delta, 'reasoning_content', '');
  if Reasoning = '' then
    Reasoning := JsonGetStr(Delta, 'reasoning', '');
  if Reasoning <> '' then
  begin
    if ACurrentBlockType <> 'thinking' then
    begin
      FinishCurrentBlock(ACurrentBlockType, ACurrentContentIndex,
        AOutput, ACurrentToolCallId, ACurrentToolCallName, APartialArgs, AOnEvent);
      ACurrentBlockType := 'thinking';
      Inc(ACurrentContentIndex);
    end;

    AOutput.Content.Add(TThinkingContent.Create(Reasoning));
    AOnEvent(TThinkingDeltaEvent.Create(ACurrentContentIndex, Reasoning, nil));
  end;

  // Process tool calls
  ToolCallsArr := Delta.GetValue('tool_calls') as TJSONArray;
  if ToolCallsArr <> nil then
  begin
    for i := 0 to ToolCallsArr.Count - 1 do
    begin
      TCObj := ToolCallsArr.Items[i] as TJSONObject;
      if TCObj = nil then Continue;

      TCId := JsonGetStr(TCObj, 'id', '');
      FnObj := TCObj.GetValue('function') as TJSONObject;

      if FnObj <> nil then
      begin
        TCName := JsonGetStr(FnObj, 'name', '');
        TCArgs := JsonGetStr(FnObj, 'arguments', '');
      end
      else
      begin
        TCName := '';
        TCArgs := '';
      end;

      // New tool call (has id)
      if TCId <> '' then
      begin
        if ACurrentBlockType <> 'toolcall' then
        begin
          FinishCurrentBlock(ACurrentBlockType, ACurrentContentIndex,
            AOutput, ACurrentToolCallId, ACurrentToolCallName, APartialArgs, AOnEvent);
          Inc(ACurrentContentIndex);
        end
        else if ACurrentToolCallId <> TCId then
        begin
          FinishCurrentBlock(ACurrentBlockType, ACurrentContentIndex,
            AOutput, ACurrentToolCallId, ACurrentToolCallName, APartialArgs, AOnEvent);
          Inc(ACurrentContentIndex);
        end;

        ACurrentBlockType := 'toolcall';
        ACurrentToolCallId := TCId;
        ACurrentToolCallName := TCName;
        APartialArgs := '';
      end;

      // Accumulate arguments
      if TCArgs <> '' then
      begin
        APartialArgs := APartialArgs + TCArgs;
        ACurrentBlockType := 'toolcall';
      end;

      AOnEvent(TToolCallDeltaEvent.Create(ACurrentContentIndex, TCArgs, nil));
    end;
  end;
end;

procedure TCustomAPIAdapter.FinishCurrentBlock(var ACurrentBlockType: string;
  ACurrentContentIndex: Integer; AOutput: TAssistantMessage;
  const ACurrentToolCallId, ACurrentToolCallName: string;
  var APartialArgs: string; AOnEvent: TStreamEventCallback);
var
  Args: TJSONObject;
  TC: TToolCall;
begin
  if ACurrentBlockType = '' then
    Exit;

  if ACurrentBlockType = 'toolcall' then
  begin
    Args := ParsePartialJson(APartialArgs);
    TC := TToolCall.Create(ACurrentToolCallId, ACurrentToolCallName, Args);
    AOutput.Content.Add(TC);
  end;

  ACurrentBlockType := '';
  APartialArgs := '';
end;

function TCustomAPIAdapter.ParsePartialJson(const AJson: string): TJSONObject;
begin
  if AJson = '' then
  begin
    Result := TJSONObject.Create;
    Exit;
  end;

  try
    Result := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
    if Result = nil then
    begin
      if Assigned(FLogger) then
        FLogger.Debug('ParsePartialJson: failed to parse (nil result): ' + Copy(AJson, 1, 200));
      Result := TJSONObject.Create;
    end;
  except
    on E: Exception do
    begin
      if Assigned(FLogger) then
        FLogger.Debug('ParsePartialJson: exception: ' + E.Message + ' -- ' + Copy(AJson, 1, 200));
      Result := TJSONObject.Create;
    end;
  end;
end;

procedure TCustomAPIAdapter.SleepWithAbort(AMs: Integer;
  AAbortSignal: TAbortController);
var
  Start: Cardinal;
begin
  Start := GetTickCount;
  while True do
  begin
    if (AAbortSignal <> nil) and AAbortSignal.IsAborted then
      Exit;
    if (GetTickCount - Start) >= Cardinal(AMs) then
      Exit;
    Sleep(100);
  end;
end;

end.
