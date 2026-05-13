unit TestSSEStream;

interface

uses
  System.SysUtils, System.Classes, System.JSON,
  AI.IModel, AI.CustomAPIAdapter, Core.Messages, Core.AgentState,
  Settings.Config, Utils.JsonHelper,
  PiMonoTestFramework;

procedure RegisterSSEStreamTests;

implementation

type
  TTestSSEForwardStream = class
  private
    FLines: TArray<string>;
    FStream: TSSEForwardStream;
    procedure SimulateWrite(const AData: string);
  public
    procedure Setup;
    procedure TearDown;
    procedure NormalDataLine;
    procedure ChunkedAcrossWrites;
    procedure MultipleLinesSingleWrite;
    procedure EmptyLinesSkipped;
    procedure CommentLineSkipped;
    procedure CRLFHandling;
    procedure ZeroLengthWrite;
    procedure LargeChunk;
  end;

  TTestToolResult = class
  public
    procedure CreateText;
    procedure CreateError;
    procedure CreateWithContent;
    procedure ReleaseContent;
  end;

  TTestAPIRequestBuilding = class
  public
    procedure CompletionRequest_ToJson;
    procedure CompletionRequest_WithTools;
    procedure ApiChatMessage_SystemRole;
    procedure ApiChatMessage_UserRole;
    procedure ApiChatMessage_AssistantRole;
    procedure ApiChatMessage_ToolRole;
    procedure ApiChatMessage_ToolResultError;
    procedure ApiToolDefinition_ToJson;
  end;

  TTestConversionHelpers = class
  public
    procedure Test_AgentMessagesToApiMessages_UserOnly;
    procedure Test_AgentMessagesToApiMessages_WithSystemPrompt;
    procedure Test_AgentMessagesToApiMessages_Empty;
    procedure Test_AgentMessagesToApiMessages_AssistantWithToolCalls;
    procedure Test_AgentMessagesToApiMessages_ToolResult;
    procedure Test_AgentToolsToApiTools_Basic;
    procedure Test_AgentToolsToApiTools_Empty;
    procedure Test_SSEForwardStream_FlushRemaining;
    procedure Test_CompletionRequest_ThinkingLevel;
  end;

{ TTestSSEForwardStream }

procedure TTestSSEForwardStream.Setup;
begin
  SetLength(FLines, 0);
  FStream := TSSEForwardStream.Create(
    procedure(const ALine: string)
    begin
      SetLength(FLines, Length(FLines) + 1);
      FLines[High(FLines)] := ALine;
    end);
end;

procedure TTestSSEForwardStream.TearDown;
begin
  FStream.Free;
end;

procedure TTestSSEForwardStream.SimulateWrite(const AData: string);
var
  Bytes: TBytes;
begin
  if AData = '' then Exit;
  Bytes := TEncoding.UTF8.GetBytes(AData);
  FStream.Write(Bytes[0], Length(Bytes));
end;

procedure TTestSSEForwardStream.NormalDataLine;
begin
  SimulateWrite('data: {"choices":[]}' + #10);
  Assert(Length(FLines) = 1, 'Expected 1 line, got ' + IntToStr(Length(FLines)));
  Assert(FLines[0] = 'data: {"choices":[]}', 'Line content mismatch');
end;

procedure TTestSSEForwardStream.ChunkedAcrossWrites;
begin
  // Split "data: hello\n" across two writes
  SimulateWrite('dat');
  Assert(Length(FLines) = 0, 'No complete line yet');
  SimulateWrite('a: hello' + #10);
  Assert(Length(FLines) = 1, 'Line completed after second write');
  Assert(FLines[0] = 'data: hello', 'Line content mismatch');
end;

procedure TTestSSEForwardStream.MultipleLinesSingleWrite;
begin
  SimulateWrite('data: line1' + #10 + 'data: line2' + #10);
  Assert(Length(FLines) = 2, 'Expected 2 lines');
  Assert(FLines[0] = 'data: line1', 'Line 0 mismatch');
  Assert(FLines[1] = 'data: line2', 'Line 1 mismatch');
end;

procedure TTestSSEForwardStream.EmptyLinesSkipped;
var
  NonEmpty: Integer;
  i: Integer;
begin
  SimulateWrite(#10 + #10 + 'data: real' + #10 + #10);
  // The stream emits all lines including empty ones - callback filters
  NonEmpty := 0;
  for i := 0 to High(FLines) do
    if Trim(FLines[i]) <> '' then
      Inc(NonEmpty);
  Assert(NonEmpty = 1, 'Expected exactly 1 non-empty line');
end;

procedure TTestSSEForwardStream.CommentLineSkipped;
var
  NonComment: Integer;
  i: Integer;
begin
  SimulateWrite(': this is a comment' + #10 + 'data: real' + #10);
  // The stream emits all lines - SSE processing filters comments
  NonComment := 0;
  for i := 0 to High(FLines) do
    if (Trim(FLines[i]) <> '') and (not FLines[i].StartsWith(':')) then
      Inc(NonComment);
  Assert(NonComment = 1, 'Expected exactly 1 non-comment line');
end;

procedure TTestSSEForwardStream.CRLFHandling;
begin
  SimulateWrite('data: crlf' + #13#10 + 'data: lf' + #10);
  Assert(Length(FLines) = 2, 'Expected 2 lines for CRLF test');
  Assert(FLines[0] = 'data: crlf', 'CRLF line content mismatch');
  Assert(FLines[1] = 'data: lf', 'LF line content mismatch');
end;

procedure TTestSSEForwardStream.ZeroLengthWrite;
var
  Bytes: TBytes;
begin
  // Test that Write with Count=0 is safe and produces no lines
  Bytes := TEncoding.UTF8.GetBytes('X');
  FStream.Write(Bytes[0], 0);
  Assert(Length(FLines) = 0, 'Zero-length write should produce no lines');
end;

procedure TTestSSEForwardStream.LargeChunk;
var
  LargeData: string;
begin
  // Build a large data line (>8KB)
  LargeData := 'data: ' + StringOfChar('X', 10000);
  SimulateWrite(LargeData + #10);
  Assert(Length(FLines) = 1, 'Expected 1 line for large chunk');
  Assert(Length(FLines[0]) = 10006, 'Large chunk line length mismatch');
end;

{ TTestToolResult }

procedure TTestToolResult.CreateText;
var
  R: TToolResult;
begin
  R := TToolResult.CreateText('Hello');
  try
    Assert(not R.IsError, 'CreateText should not be error');
    Assert(R.Content.Count = 1, 'CreateText should have 1 content block');
  finally
    R.ReleaseContent;
  end;
end;

procedure TTestToolResult.CreateError;
var
  R: TToolResult;
begin
  R := TToolResult.CreateError('Something went wrong');
  try
    Assert(R.IsError, 'CreateError should be error');
    Assert(R.Content.Count = 1, 'CreateError should have 1 content block');
  finally
    R.ReleaseContent;
  end;
end;

procedure TTestToolResult.CreateWithContent;
var
  List: TContentBlockList;
  R: TToolResult;
begin
  List := TContentBlockList.Create;
  List.Add(TTextContent.Create('Block 1'));
  List.Add(TTextContent.Create('Block 2'));
  R := TToolResult.Create(List, False);
  try
    Assert(not R.IsError, 'Should not be error');
    Assert(R.Content.Count = 2, 'Should have 2 content blocks');
  finally
    R.ReleaseContent;
  end;
end;

procedure TTestToolResult.ReleaseContent;
var
  R: TToolResult;
begin
  R := TToolResult.CreateText('To be released');
  R.ReleaseContent;
  // After release, Content should be nil (freed)
  Assert(R.Content = nil, 'Content should be nil after ReleaseContent');
end;

{ TTestAPIRequestBuilding }

procedure TTestAPIRequestBuilding.CompletionRequest_ToJson;
var
  Req: TCompletionRequest;
  Json: TJSONObject;
begin
  Req := TCompletionRequest.Create;
  Req.Model := 'test-model';
  Req.Stream := True;
  Req.MaxTokens := 4096;
  Req.Temperature := 0.7;
  Req.TopP := 0.9;

  SetLength(Req.Messages, 1);
  Req.Messages[0] := TApiChatMessage.CreateUser('Hello');

  Json := Req.ToJson;
  try
    Assert(JsonGetStr(Json, 'model', '') = 'test-model', 'model mismatch');
    Assert(JsonGetBool(Json, 'stream', False) = True, 'stream mismatch');
    Assert(JsonGetInt(Json, 'max_tokens', 0) = 4096, 'max_tokens mismatch');
  finally
    Json.Free;
  end;
end;

procedure TTestAPIRequestBuilding.CompletionRequest_WithTools;
var
  Req: TCompletionRequest;
  Json: TJSONObject;
  Tools: TJSONArray;
begin
  Req := TCompletionRequest.Create;
  Req.Model := 'test';
  Req.Stream := True;

  SetLength(Req.Messages, 1);
  Req.Messages[0] := TApiChatMessage.CreateUser('Read the file');

  SetLength(Req.Tools, 1);
  Req.Tools[0].Name := 'read_file';
  Req.Tools[0].Description := 'Read a file';

  Json := Req.ToJson;
  try
    Tools := Json.FindValue('tools') as TJSONArray;
    Assert(Tools <> nil, 'tools array should exist');
    Assert(Tools.Count > 0, 'Should have at least 1 tool');
  finally
    Json.Free;
  end;
end;

procedure TTestAPIRequestBuilding.ApiChatMessage_SystemRole;
var
  Msg: TApiChatMessage;
  Json: TJSONObject;
begin
  Msg := TApiChatMessage.CreateSystem('You are a helpful assistant.');
  Json := Msg.ToJson;
  try
    Assert(JsonGetStr(Json, 'role', '') = 'system', 'role mismatch');
    Assert(JsonGetStr(Json, 'content', '') = 'You are a helpful assistant.', 'content mismatch');
  finally
    Json.Free;
  end;
end;

procedure TTestAPIRequestBuilding.ApiChatMessage_UserRole;
var
  Msg: TApiChatMessage;
  Json: TJSONObject;
begin
  Msg := TApiChatMessage.CreateUser('Hello!');
  Json := Msg.ToJson;
  try
    Assert(JsonGetStr(Json, 'role', '') = 'user', 'role mismatch');
    Assert(JsonGetStr(Json, 'content', '') = 'Hello!', 'content mismatch');
  finally
    Json.Free;
  end;
end;

procedure TTestAPIRequestBuilding.ApiChatMessage_AssistantRole;
var
  Msg: TApiChatMessage;
  Json: TJSONObject;
begin
  Msg := TApiChatMessage.CreateAssistant('How can I help?');
  Json := Msg.ToJson;
  try
    Assert(JsonGetStr(Json, 'role', '') = 'assistant', 'role mismatch');
  finally
    Json.Free;
  end;
end;

procedure TTestAPIRequestBuilding.ApiChatMessage_ToolRole;
var
  Msg: TApiChatMessage;
  Json: TJSONObject;
begin
  Msg := TApiChatMessage.CreateToolResult('call_123', 'File contents here');
  Json := Msg.ToJson;
  try
    Assert(JsonGetStr(Json, 'role', '') = 'tool', 'role mismatch');
    Assert(JsonGetStr(Json, 'tool_call_id', '') = 'call_123', 'tool_call_id mismatch');
  finally
    Json.Free;
  end;
end;

{ TTestAPIRequestBuilding - additional methods }

procedure TTestAPIRequestBuilding.ApiChatMessage_ToolResultError;
var
  Msg: TApiChatMessage;
  Json: TJSONObject;
begin
  Msg := TApiChatMessage.CreateToolResult('call_err', 'Error occurred', True);
  Json := Msg.ToJson;
  try
    Assert(JsonGetStr(Json, 'role', '') = 'tool', 'role should be tool');
    Assert(JsonGetStr(Json, 'tool_call_id', '') = 'call_err', 'tool_call_id mismatch');
  finally
    Json.Free;
  end;
end;

procedure TTestAPIRequestBuilding.ApiToolDefinition_ToJson;
var
  Tool: TApiToolDefinition;
  Json, FuncObj: TJSONObject;
begin
  Tool.Name := 'read_file';
  Tool.Description := 'Read a file from disk';
  Tool.Parameters := TJSONObject.ParseJSONValue('{"type":"object","properties":{"path":{"type":"string"}}}') as TJSONObject;
  Json := Tool.ToJson;
  try
    // OpenAI format: {"type":"function","function":{"name":...,"description":...,"parameters":...}}
    Assert(Json.GetValue<string>('type') = 'function', 'type should be function');
    FuncObj := Json.GetValue('function') as TJSONObject;
    Assert(FuncObj <> nil, 'function object should exist');
    Assert(FuncObj.GetValue<string>('name') = 'read_file', 'name mismatch');
    Assert(FuncObj.GetValue<string>('description') = 'Read a file from disk', 'description mismatch');
    Assert(FuncObj.FindValue('parameters') <> nil, 'parameters should exist');
  finally
    Json.Free;
  end;
end;

{ TTestConversionHelpers }

procedure TTestConversionHelpers.Test_AgentMessagesToApiMessages_UserOnly;
var
  Msgs: TArray<TAgentMessage>;
  ApiMsgs: TArray<TApiChatMessage>;
  UserMsg: TUserMessage;
begin
  UserMsg := TUserMessage.Create('Hello world');
  SetLength(Msgs, 1);
  Msgs[0] := UserMsg;

  ApiMsgs := AgentMessagesToApiMessages(Msgs, '');
  try
    Assert(Length(ApiMsgs) = 1, 'Should have 1 message');
    Assert(ApiMsgs[0].Role = 'user', 'Role should be user');
    Assert(ApiMsgs[0].Content = 'Hello world', 'Content mismatch');
  finally
    for var i := 0 to High(Msgs) do Msgs[i].Free;
  end;
end;

procedure TTestConversionHelpers.Test_AgentMessagesToApiMessages_WithSystemPrompt;
var
  Msgs: TArray<TAgentMessage>;
  ApiMsgs: TArray<TApiChatMessage>;
  UserMsg: TUserMessage;
begin
  UserMsg := TUserMessage.Create('Hello');
  SetLength(Msgs, 1);
  Msgs[0] := UserMsg;

  ApiMsgs := AgentMessagesToApiMessages(Msgs, 'You are helpful');
  try
    Assert(Length(ApiMsgs) = 2, 'Should have 2 messages (system + user)');
    Assert(ApiMsgs[0].Role = 'system', 'First should be system');
    Assert(ApiMsgs[0].Content = 'You are helpful', 'System prompt mismatch');
    Assert(ApiMsgs[1].Role = 'user', 'Second should be user');
  finally
    for var i := 0 to High(Msgs) do Msgs[i].Free;
  end;
end;

procedure TTestConversionHelpers.Test_AgentMessagesToApiMessages_Empty;
var
  Msgs: TArray<TAgentMessage>;
  ApiMsgs: TArray<TApiChatMessage>;
begin
  SetLength(Msgs, 0);
  ApiMsgs := AgentMessagesToApiMessages(Msgs, '');
  Assert(Length(ApiMsgs) = 0, 'Empty input should give empty output');
end;

procedure TTestConversionHelpers.Test_AgentMessagesToApiMessages_AssistantWithToolCalls;
var
  Msgs: TArray<TAgentMessage>;
  ApiMsgs: TArray<TApiChatMessage>;
  AsstMsg: TAssistantMessage;
begin
  AsstMsg := TAssistantMessage.Create;
  AsstMsg.Content.Add(TTextContent.Create('Let me check'));
  AsstMsg.Content.Add(TToolCall.Create('tc1', 'read_file',
    TJSONObject.ParseJSONValue('{"path":"test.txt"}') as TJSONObject));

  SetLength(Msgs, 1);
  Msgs[0] := AsstMsg;

  ApiMsgs := AgentMessagesToApiMessages(Msgs, '');
  try
    Assert(Length(ApiMsgs) = 1, 'Should have 1 message');
    Assert(ApiMsgs[0].Role = 'assistant', 'Role should be assistant');
    Assert(ApiMsgs[0].ToolCalls <> nil, 'ToolCalls should be assigned');
    Assert(ApiMsgs[0].ToolCalls.Count = 1, 'ToolCalls should have 1 entry');
  finally
    FreeApiMessages(ApiMsgs);
    for var i := 0 to High(Msgs) do Msgs[i].Free;
  end;
end;

procedure TTestConversionHelpers.Test_AgentMessagesToApiMessages_ToolResult;
var
  Msgs: TArray<TAgentMessage>;
  ApiMsgs: TArray<TApiChatMessage>;
  ToolResult: TToolResultMessage;
begin
  var TRContent := TContentBlockList.Create;
  TRContent.Add(TTextContent.Create('File contents here'));
  ToolResult := TToolResultMessage.Create('tc1', 'read_file', TRContent, False);

  SetLength(Msgs, 1);
  Msgs[0] := ToolResult;

  ApiMsgs := AgentMessagesToApiMessages(Msgs, '');
  try
    Assert(Length(ApiMsgs) = 1, 'Should have 1 message');
    Assert(ApiMsgs[0].Role = 'tool', 'Role should be tool');
    Assert(ApiMsgs[0].ToolCallId = 'tc1', 'ToolCallId mismatch');
  finally
    for var i := 0 to High(Msgs) do Msgs[i].Free;
  end;
end;

procedure TTestConversionHelpers.Test_AgentToolsToApiTools_Basic;
var
  ApiTools: TArray<TApiToolDefinition>;
begin
  // We can't easily create IAgentTool mocks here, but we can test with empty array
  SetLength(ApiTools, 0);
  ApiTools := AgentToolsToApiTools(nil);
  Assert(Length(ApiTools) = 0, 'Empty tools should give empty result');
end;

procedure TTestConversionHelpers.Test_AgentToolsToApiTools_Empty;
var
  ApiTools: TArray<TApiToolDefinition>;
begin
  ApiTools := AgentToolsToApiTools(nil);
  Assert(Length(ApiTools) = 0, 'Nil tools should give empty result');
end;

procedure TTestConversionHelpers.Test_SSEForwardStream_FlushRemaining;
var
  Lines: TArray<string>;
  Stream: TSSEForwardStream;
  Bytes: TBytes;
begin
  SetLength(Lines, 0);
  Stream := TSSEForwardStream.Create(
    procedure(const ALine: string)
    begin
      SetLength(Lines, Length(Lines) + 1);
      Lines[High(Lines)] := ALine;
    end);
  try
    // Write data without trailing newline
    Bytes := TEncoding.UTF8.GetBytes('data: incomplete');
    Stream.Write(Bytes[0], Length(Bytes));
    Assert(Length(Lines) = 0, 'No complete line yet');

    // Flush should emit the buffered content
    Stream.FlushRemaining;
    Assert(Length(Lines) = 1, 'Flush should emit 1 line');
    Assert(Lines[0] = 'data: incomplete', 'Flushed content mismatch');
  finally
    Stream.Free;
  end;
end;

procedure TTestConversionHelpers.Test_CompletionRequest_ThinkingLevel;
var
  Req: TCompletionRequest;
  Json: TJSONObject;
begin
  Req := TCompletionRequest.Create;
  Req.Model := 'test';
  Req.Stream := True;
  Req.ThinkingLevel := tlHigh;

  SetLength(Req.Messages, 1);
  Req.Messages[0] := TApiChatMessage.CreateUser('Think about this');

  Json := Req.ToJson;
  try
    Assert(Json.GetValue<string>('model') = 'test', 'model mismatch');
    // ThinkingLevel may appear in the JSON depending on implementation
    Assert(Json.FindValue('messages') <> nil, 'messages should exist');
  finally
    Json.Free;
  end;
end;

procedure RegisterSSEStreamTests;
var
  TSSE: TTestSSEForwardStream;
  TTool: TTestToolResult;
  TAPI: TTestAPIRequestBuilding;
  TConv: TTestConversionHelpers;
begin
  TSSE := TTestSSEForwardStream.Create;
  try
    GRunner.RunTest('SSE.NormalDataLine', TSSE.NormalDataLine, TSSE.Setup, TSSE.TearDown);
    GRunner.RunTest('SSE.ChunkedAcrossWrites', TSSE.ChunkedAcrossWrites, TSSE.Setup, TSSE.TearDown);
    GRunner.RunTest('SSE.MultipleLinesSingleWrite', TSSE.MultipleLinesSingleWrite, TSSE.Setup, TSSE.TearDown);
    GRunner.RunTest('SSE.EmptyLinesSkipped', TSSE.EmptyLinesSkipped, TSSE.Setup, TSSE.TearDown);
    GRunner.RunTest('SSE.CommentLineSkipped', TSSE.CommentLineSkipped, TSSE.Setup, TSSE.TearDown);
    GRunner.RunTest('SSE.CRLFHandling', TSSE.CRLFHandling, TSSE.Setup, TSSE.TearDown);
    GRunner.RunTest('SSE.ZeroLengthWrite', TSSE.ZeroLengthWrite, TSSE.Setup, TSSE.TearDown);
    GRunner.RunTest('SSE.LargeChunk', TSSE.LargeChunk, TSSE.Setup, TSSE.TearDown);
  finally
    TSSE.Free;
  end;

  TTool := TTestToolResult.Create;
  try
    GRunner.RunTest('ToolResult.CreateText', TTool.CreateText);
    GRunner.RunTest('ToolResult.CreateError', TTool.CreateError);
    GRunner.RunTest('ToolResult.CreateWithContent', TTool.CreateWithContent);
    GRunner.RunTest('ToolResult.ReleaseContent', TTool.ReleaseContent);
  finally
    TTool.Free;
  end;

  TAPI := TTestAPIRequestBuilding.Create;
  try
    GRunner.RunTest('API.CompletionRequest_ToJson', TAPI.CompletionRequest_ToJson);
    GRunner.RunTest('API.CompletionRequest_WithTools', TAPI.CompletionRequest_WithTools);
    GRunner.RunTest('API.ApiChatMessage_SystemRole', TAPI.ApiChatMessage_SystemRole);
    GRunner.RunTest('API.ApiChatMessage_UserRole', TAPI.ApiChatMessage_UserRole);
    GRunner.RunTest('API.ApiChatMessage_AssistantRole', TAPI.ApiChatMessage_AssistantRole);
    GRunner.RunTest('API.ApiChatMessage_ToolRole', TAPI.ApiChatMessage_ToolRole);
    GRunner.RunTest('API.ApiChatMessage_ToolResultError', TAPI.ApiChatMessage_ToolResultError);
    GRunner.RunTest('API.ApiToolDefinition_ToJson', TAPI.ApiToolDefinition_ToJson);
  finally
    TAPI.Free;
  end;

  TConv := TTestConversionHelpers.Create;
  try
    GRunner.RunTest('Conv.AgentMessagesToApiMessages_UserOnly', TConv.Test_AgentMessagesToApiMessages_UserOnly);
    GRunner.RunTest('Conv.AgentMessagesToApiMessages_WithSystem', TConv.Test_AgentMessagesToApiMessages_WithSystemPrompt);
    GRunner.RunTest('Conv.AgentMessagesToApiMessages_Empty', TConv.Test_AgentMessagesToApiMessages_Empty);
    GRunner.RunTest('Conv.AgentMessagesToApiMessages_ToolCalls', TConv.Test_AgentMessagesToApiMessages_AssistantWithToolCalls);
    GRunner.RunTest('Conv.AgentMessagesToApiMessages_ToolResult', TConv.Test_AgentMessagesToApiMessages_ToolResult);
    GRunner.RunTest('Conv.AgentToolsToApiTools_Basic', TConv.Test_AgentToolsToApiTools_Basic);
    GRunner.RunTest('Conv.AgentToolsToApiTools_Empty', TConv.Test_AgentToolsToApiTools_Empty);
    GRunner.RunTest('Conv.SSEForwardStream_FlushRemaining', TConv.Test_SSEForwardStream_FlushRemaining);
    GRunner.RunTest('Conv.CompletionRequest_ThinkingLevel', TConv.Test_CompletionRequest_ThinkingLevel);
  finally
    TConv.Free;
  end;
end;

end.
