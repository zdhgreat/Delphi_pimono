unit AI.IModel;

interface

uses
  System.SysUtils, System.JSON, System.Classes,
  Core.Messages, Core.Events, Core.AgentState, AI.ModelConfig,
  Settings.Config;

type
  // Callback for streaming events from the model
  TStreamEventCallback = reference to procedure(AEvent: TAssistantMessageEvent);

  // Chat message in API format (simplified for OpenAI-compatible APIs)
  TApiChatMessage = record
    Role: string;           // "system", "user", "assistant", "tool"
    Content: string;        // Text content (simplified)
    ToolCallId: string;     // For tool results
    ToolCalls: TJSONArray;  // For assistant messages with tool calls
    Name: string;           // Tool name (for tool results)
    class function CreateSystem(const AContent: string): TApiChatMessage; static;
    class function CreateUser(const AContent: string): TApiChatMessage; static;
    class function CreateAssistant(const AContent: string): TApiChatMessage; static;
    class function CreateToolResult(const AToolCallId, AContent: string;
      AIsError: Boolean = False): TApiChatMessage; static;
    function ToJson: TJSONObject;
  end;

  // Tool definition in API format
  TApiToolDefinition = record
    Name: string;
    Description: string;
    Parameters: TJSONObject;  // JSON Schema
    function ToJson: TJSONObject;
  end;

  // Completion request
  TCompletionRequest = record
    Model: string;
    Messages: TArray<TApiChatMessage>;
    Tools: TArray<TApiToolDefinition>;
    MaxTokens: Integer;
    Temperature: Double;
    TopP: Double;
    FrequencyPenalty: Double;
    PresencePenalty: Double;
    ThinkingLevel: TThinkingLevel;
    Stream: Boolean;
    SystemPrompt: string;
    class function Create: TCompletionRequest; static;
    function ToJson: TJSONObject;
  end;

  // Model interface
  IModel = interface
    ['{B2C3D4E5-F6A7-8901-BCDE-F12345678901}']
    function GetModelInfo: TModelInfo;
    function GetId: string;
    function GetName: string;
    function GetProvider: string;
    function GetBaseUrl: string;

    /// <summary>Stream completion events through the callback</summary>
    procedure Stream(ARequest: TCompletionRequest;
      AOnEvent: TStreamEventCallback;
      AAbortSignal: TAbortController = nil);

    /// <summary>Synchronous completion - returns the full assistant message</summary>
    function Complete(ARequest: TCompletionRequest;
      AAbortSignal: TAbortController = nil): TAssistantMessage;

    /// <summary>Fetch available models from the API server</summary>
    function GetModels: TModelList;

    property ModelInfo: TModelInfo read GetModelInfo;
    property Id: string read GetId;
    property Name: string read GetName;
    property Provider: string read GetProvider;
    property BaseUrl: string read GetBaseUrl;
  end;

// Helper: Convert agent messages to API chat messages
function AgentMessagesToApiMessages(
  const AMessages: TArray<TAgentMessage>;
  const ASystemPrompt: string): TArray<TApiChatMessage>;

// Helper: Convert IAgentTool array to API tool definitions
function AgentToolsToApiTools(
  const ATools: TArray<IAgentTool>): TArray<TApiToolDefinition>;

// Helper: Free owned TJSONArray (ToolCalls) inside TApiChatMessage records
procedure FreeApiMessages(var AMessages: TArray<TApiChatMessage>);

// Helper: Free owned TJSONObject (Parameters) inside TApiToolDefinition records
procedure FreeApiTools(var ATools: TArray<TApiToolDefinition>);

implementation

{ TApiChatMessage }

class function TApiChatMessage.CreateSystem(const AContent: string): TApiChatMessage;
begin
  Result.Role := 'system';
  Result.Content := AContent;
  Result.ToolCallId := '';
  Result.ToolCalls := nil;
  Result.Name := '';
end;

class function TApiChatMessage.CreateUser(const AContent: string): TApiChatMessage;
begin
  Result.Role := 'user';
  Result.Content := AContent;
  Result.ToolCallId := '';
  Result.ToolCalls := nil;
  Result.Name := '';
end;

class function TApiChatMessage.CreateAssistant(const AContent: string): TApiChatMessage;
begin
  Result.Role := 'assistant';
  Result.Content := AContent;
  Result.ToolCallId := '';
  Result.ToolCalls := nil;
  Result.Name := '';
end;

class function TApiChatMessage.CreateToolResult(const AToolCallId,
  AContent: string; AIsError: Boolean): TApiChatMessage;
begin
  Result.Role := 'tool';
  Result.Content := AContent;
  Result.ToolCallId := AToolCallId;
  Result.ToolCalls := nil;
  Result.Name := '';
end;

function TApiChatMessage.ToJson: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('role', Role);

  if Role = 'tool' then
  begin
    Result.AddPair('tool_call_id', ToolCallId);
    Result.AddPair('content', Content);
  end
  else if (Role = 'assistant') and (ToolCalls <> nil) then
  begin
    if Content <> '' then
      Result.AddPair('content', Content)
    else
      Result.AddPair('content', TJSONNull.Create);
    // Clone ToolCalls so the message object is not modified
    Result.AddPair('tool_calls', ToolCalls.Clone as TJSONArray);
  end
  else
  begin
    Result.AddPair('content', Content);
  end;
end;

{ TApiToolDefinition }

function TApiToolDefinition.ToJson: TJSONObject;
var
  FuncObj: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'function');

  FuncObj := TJSONObject.Create;
  FuncObj.AddPair('name', Name);
  FuncObj.AddPair('description', Description);
  if Parameters <> nil then
    FuncObj.AddPair('parameters', TJSONObject(Parameters.Clone))
  else
    FuncObj.AddPair('parameters', TJSONObject.Create);

  Result.AddPair('function', FuncObj);
end;

{ TCompletionRequest }

class function TCompletionRequest.Create: TCompletionRequest;
begin
  Result.Model := '';
  Result.Messages := nil;
  Result.Tools := nil;
  Result.MaxTokens := 4096;
  Result.Temperature := 0.7;
  Result.TopP := 1.0;
  Result.FrequencyPenalty := 0.0;
  Result.PresencePenalty := 0.0;
  Result.ThinkingLevel := tlOff;
  Result.Stream := True;
  Result.SystemPrompt := '';
end;

function TCompletionRequest.ToJson: TJSONObject;
var
  MsgArr, ToolArr: TJSONArray;
  i: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('model', Model);
  Result.AddPair('max_tokens', TJSONNumber.Create(MaxTokens));
  Result.AddPair('temperature', TJSONNumber.Create(Temperature));
  Result.AddPair('stream', TJSONBool.Create(Stream));

  MsgArr := TJSONArray.Create;
  for i := 0 to High(Messages) do
    MsgArr.AddElement(Messages[i].ToJson);
  Result.AddPair('messages', MsgArr);

  if Length(Tools) > 0 then
  begin
    ToolArr := TJSONArray.Create;
    for i := 0 to High(Tools) do
      ToolArr.AddElement(Tools[i].ToJson);
    Result.AddPair('tools', ToolArr);
    Result.AddPair('tool_choice', 'auto');
  end;
end;

{ Helper functions }

function AgentMessagesToApiMessages(
  const AMessages: TArray<TAgentMessage>;
  const ASystemPrompt: string): TArray<TApiChatMessage>;
var
  i, j, Count: Integer;
  Msg: TAgentMessage;
  ApiMsg: TApiChatMessage;
  ToolCalls: TArray<TToolCall>;
  TCArr: TJSONArray;
  TCObj, FnObj: TJSONObject;
  UserMsg: TUserMessage;
  AsstMsg: TAssistantMessage;
  ToolResult: TToolResultMessage;
  SB: TStringBuilder;

  procedure CollectText(ABlocks: TContentBlockList);
  begin
    SB.Clear;
    for var k := 0 to ABlocks.Count - 1 do
      if ABlocks[k].ContentType = cbtText then
        SB.Append(TTextContent(ABlocks[k]).Text);
  end;

begin
  Count := 0;
  if ASystemPrompt <> '' then
    Inc(Count);
  Inc(Count, Length(AMessages));
  SetLength(Result, Count);

  Count := 0;
  SB := TStringBuilder.Create(256);
  try

  // System prompt
  if ASystemPrompt <> '' then
  begin
    Result[Count] := TApiChatMessage.CreateSystem(ASystemPrompt);
    Inc(Count);
  end;

  for i := 0 to High(AMessages) do
  begin
    Msg := AMessages[i];
    case Msg.Role of
      mrUser:
      begin
        UserMsg := TUserMessage(Msg);
        if UserMsg.HasStructuredContent then
        begin
          CollectText(UserMsg.ContentBlocks);
          Result[Count] := TApiChatMessage.CreateUser(SB.ToString);
        end
        else
          Result[Count] := TApiChatMessage.CreateUser(UserMsg.Content);
        Inc(Count);
      end;

      mrAssistant:
      begin
        AsstMsg := TAssistantMessage(Msg);
        ToolCalls := AsstMsg.Content.FindToolCalls;

        if Length(ToolCalls) > 0 then
        begin
          ApiMsg := TApiChatMessage.CreateAssistant('');

          TCArr := TJSONArray.Create;
          for j := 0 to High(ToolCalls) do
          begin
            TCObj := TJSONObject.Create;
            TCObj.AddPair('id', ToolCalls[j].Id);
            TCObj.AddPair('type', 'function');

            FnObj := TJSONObject.Create;
            FnObj.AddPair('name', ToolCalls[j].Name);
            if ToolCalls[j].Arguments <> nil then
              FnObj.AddPair('arguments', ToolCalls[j].Arguments.ToJSON)
            else
              FnObj.AddPair('arguments', '{}');

            TCObj.AddPair('function', FnObj);
            TCArr.AddElement(TCObj);
          end;
          ApiMsg.ToolCalls := TCArr;

          CollectText(AsstMsg.Content);
          ApiMsg.Content := SB.ToString;

          Result[Count] := ApiMsg;
        end
        else
        begin
          CollectText(AsstMsg.Content);
          Result[Count] := TApiChatMessage.CreateAssistant(SB.ToString);
        end;
        Inc(Count);
      end;

      mrToolResult:
      begin
        ToolResult := TToolResultMessage(Msg);
        CollectText(ToolResult.Content);
        Result[Count] := TApiChatMessage.CreateToolResult(
          ToolResult.ToolCallId, SB.ToString, ToolResult.IsError);
        Inc(Count);
      end;
    end;
  end;

  finally
    SB.Free;
  end;

  // Trim to actual count (in case some messages were skipped)
  SetLength(Result, Count);
end;

function AgentToolsToApiTools(
  const ATools: TArray<IAgentTool>): TArray<TApiToolDefinition>;
var
  i: Integer;
begin
  SetLength(Result, Length(ATools));
  for i := 0 to High(ATools) do
  begin
    Result[i].Name := ATools[i].GetName;
    Result[i].Description := ATools[i].GetDescription;
    Result[i].Parameters := ATools[i].GetParameterSchema;
  end;
end;

procedure FreeApiMessages(var AMessages: TArray<TApiChatMessage>);
var
  i: Integer;
begin
  for i := 0 to High(AMessages) do
  begin
    if AMessages[i].ToolCalls <> nil then
    begin
      AMessages[i].ToolCalls.Free;
      AMessages[i].ToolCalls := nil;
    end;
  end;
end;

procedure FreeApiTools(var ATools: TArray<TApiToolDefinition>);
var
  i: Integer;
begin
  for i := 0 to High(ATools) do
  begin
    ATools[i].Parameters.Free;
    ATools[i].Parameters := nil;
  end;
end;

end.
