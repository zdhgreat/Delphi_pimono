unit TestMessages;

interface

uses
  System.SysUtils, System.JSON,
  Core.Messages, Utils.JsonHelper;

procedure RegisterMessageTests;

implementation

uses
  PiMonoTestFramework;

type
  TTestContentBlock = class
  public
    procedure Test_TextContent_Create;
    procedure Test_TextContent_Clone;
    procedure Test_TextContent_ToJson;
    procedure Test_ThinkingContent_Create;
    procedure Test_ThinkingContent_Clone;
    procedure Test_ImageContent_ToJson;
    procedure Test_ToolCall_Create;
    procedure Test_ToolCall_Clone_Independence;
    procedure Test_ToolCall_ToJson;
  end;

  TTestContentBlockList = class
  public
    procedure Test_Add_ThreeItems;
    procedure Test_Clear_FreesItems;
    procedure Test_Clone_DeepCopy;
    procedure Test_FindToolCalls_Mixed;
    procedure Test_FindToolCalls_None;
    procedure Test_ToJson_FromJson_RoundTrip;
    procedure Test_FromJson_Nil;
  end;

  TTestMessages = class
  public
    procedure Test_UserMessage_Text;
    procedure Test_UserMessage_StructuredContent;
    procedure Test_UserMessage_CompactionSummary;
    procedure Test_UserMessage_ToJson_FromJson;
    procedure Test_AssistantMessage_WithToolCalls;
    procedure Test_AssistantMessage_ToJson_FromJson;
    procedure Test_AssistantMessage_Usage;
    procedure Test_ToolResultMessage_Create;
    procedure Test_ToolResultMessage_ToJson_FromJson;
    procedure Test_ToolResultMessage_IsError;
    procedure Test_CostInfo_Empty;
    procedure Test_Usage_Empty;
    procedure Test_ImageContent_Clone;
  end;

  TTestMessageList = class
  public
    procedure Test_Add_And_Count;
    procedure Test_Clear_FreesAll;
    procedure Test_Clone_DeepCopy;
    procedure Test_Clone_ModifyOriginal;
    procedure Test_ExtractAll_OwnershipTransfer;
    procedure Test_Delete_Middle;
    procedure Test_Delete_OutOfRange;
    procedure Test_Last_Empty;
    procedure Test_ToArray_SharedRefs;
  end;

  TTestMessageRoleHelpers = class
  public
    procedure Test_MessageRoleToString;
    procedure Test_StopReasonRoundTrip;
    procedure Test_StringToStopReason_Unknown;
  end;

{ TTestContentBlock }

procedure TTestContentBlock.Test_TextContent_Create;
var
  Block: TTextContent;
begin
  Block := TTextContent.Create('Hello');
  try
    Assert(Block.Text = 'Hello', 'Text should be Hello');
    Assert(Block.ContentType = cbtText, 'ContentType should be cbtText');
  finally
    Block.Free;
  end;
end;

procedure TTestContentBlock.Test_TextContent_Clone;
var
  Block, Clone: TContentBlock;
begin
  Block := TTextContent.Create('Test');
  try
    Clone := Block.Clone;
    try
      Assert(TTextContent(Clone).Text = 'Test', 'Cloned text should match');
    finally
      Clone.Free;
    end;
  finally
    Block.Free;
  end;
end;

procedure TTestContentBlock.Test_TextContent_ToJson;
var
  Block: TTextContent;
  Json: TJSONObject;
begin
  Block := TTextContent.Create('Hello World');
  try
    Json := Block.ToJson;
    try
      Assert(JsonGetStr(Json, 'type', '') = 'text', 'type should be text');
      Assert(JsonGetStr(Json, 'text', '') = 'Hello World', 'text should match');
    finally
      Json.Free;
    end;
  finally
    Block.Free;
  end;
end;

procedure TTestContentBlock.Test_ThinkingContent_Create;
var
  Block: TThinkingContent;
begin
  Block := TThinkingContent.Create('Thinking...');
  try
    Assert(Block.Thinking = 'Thinking...', 'Thinking should match');
    Assert(Block.ContentType = cbtThinking, 'ContentType should be cbtThinking');
  finally
    Block.Free;
  end;
end;

procedure TTestContentBlock.Test_ThinkingContent_Clone;
var
  Block, Clone: TContentBlock;
begin
  Block := TThinkingContent.Create('Deep thought');
  try
    Clone := Block.Clone;
    try
      Assert(TThinkingContent(Clone).Thinking = 'Deep thought', 'Cloned thinking should match');
    finally
      Clone.Free;
    end;
  finally
    Block.Free;
  end;
end;

procedure TTestContentBlock.Test_ImageContent_ToJson;
var
  Block: TImageContent;
  Json: TJSONObject;
begin
  Block := TImageContent.Create('base64data', 'image/png');
  try
    Json := Block.ToJson;
    try
      Assert(JsonGetStr(Json, 'type', '') = 'image', 'type should be image');
      Assert(JsonGetStr(Json, 'data', '') = 'base64data', 'data should match');
      Assert(JsonGetStr(Json, 'mimeType', '') = 'image/png', 'mimeType should match');
    finally
      Json.Free;
    end;
  finally
    Block.Free;
  end;
end;

procedure TTestContentBlock.Test_ToolCall_Create;
var
  Args: TJSONObject;
  TC: TToolCall;
begin
  Args := TJSONObject.Create;
  Args.AddPair('path', 'test.txt');
  TC := TToolCall.Create('call_123', 'read_file', Args);
  try
    Assert(TC.Id = 'call_123', 'Id should match');
    Assert(TC.Name = 'read_file', 'Name should match');
    Assert(TC.Arguments <> nil, 'Arguments should not be nil');
    Assert(JsonGetStr(TC.Arguments, 'path', '') = 'test.txt', 'Arguments path should match');
  finally
    TC.Free;
  end;
end;

procedure TTestContentBlock.Test_ToolCall_Clone_Independence;
var
  Original, Clone: TContentBlock;
  TC: TToolCall;
  DummyVal: TJSONValue;
begin
  Original := TToolCall.Create('id1', 'tool1',
    TJSONObject.ParseJSONValue('{"key":"val"}') as TJSONObject);
  try
    Clone := Original.Clone;
    try
      TC := TToolCall(Clone);
      Assert(TC.Id = 'id1', 'Cloned id should match');
      Assert(TC.Name = 'tool1', 'Cloned name should match');
      // Modify original arguments
      TToolCall(Original).Arguments.AddPair('extra', 'value');
      // Clone should NOT have the new key
      Assert(not TC.Arguments.TryGetValue('extra', DummyVal),
        'Clone should be independent from original');
    finally
      Clone.Free;
    end;
  finally
    Original.Free;
  end;
end;

procedure TTestContentBlock.Test_ToolCall_ToJson;
var
  TC: TToolCall;
  Json: TJSONObject;
begin
  TC := TToolCall.Create('call_1', 'bash',
    TJSONObject.ParseJSONValue('{"command":"dir"}') as TJSONObject);
  try
    Json := TC.ToJson;
    try
      Assert(JsonGetStr(Json, 'type', '') = 'toolCall', 'type should be toolCall');
      Assert(JsonGetStr(Json, 'id', '') = 'call_1', 'id should match');
      Assert(JsonGetStr(Json, 'name', '') = 'bash', 'name should match');
    finally
      Json.Free;
    end;
  finally
    TC.Free;
  end;
end;

{ TTestContentBlockList }

procedure TTestContentBlockList.Test_Add_ThreeItems;
var
  List: TContentBlockList;
begin
  List := TContentBlockList.Create;
  try
    List.Add(TTextContent.Create('A'));
    List.Add(TTextContent.Create('B'));
    List.Add(TThinkingContent.Create('C'));
    Assert(List.Count = 3, 'Count should be 3');
    Assert(List[0].ContentType = cbtText, 'First item should be text');
    Assert(List[2].ContentType = cbtThinking, 'Third item should be thinking');
  finally
    List.Free;
  end;
end;

procedure TTestContentBlockList.Test_Clear_FreesItems;
var
  List: TContentBlockList;
begin
  List := TContentBlockList.Create;
  try
    List.Add(TTextContent.Create('X'));
    List.Add(TTextContent.Create('Y'));
    List.Clear;
    Assert(List.Count = 0, 'Count should be 0 after clear');
  finally
    List.Free;
  end;
end;

procedure TTestContentBlockList.Test_Clone_DeepCopy;
var
  List, Clone: TContentBlockList;
begin
  List := TContentBlockList.Create;
  try
    List.Add(TTextContent.Create('Original'));
    Clone := List.Clone;
    try
      Assert(Clone.Count = 1, 'Clone count should be 1');
      // Modify clone text
      TTextContent(Clone[0]).Text := 'Modified';
      // Original should be unchanged
      Assert(TTextContent(List[0]).Text = 'Original', 'Original should be unchanged');
      Assert(TTextContent(Clone[0]).Text = 'Modified', 'Clone should be modified');
    finally
      Clone.Free;
    end;
  finally
    List.Free;
  end;
end;

procedure TTestContentBlockList.Test_FindToolCalls_Mixed;
var
  List: TContentBlockList;
  Calls: TArray<TToolCall>;
begin
  List := TContentBlockList.Create;
  try
    List.Add(TTextContent.Create('Hello'));
    List.Add(TToolCall.Create('id1', 'tool1', TJSONObject.Create));
    List.Add(TTextContent.Create('World'));
    List.Add(TToolCall.Create('id2', 'tool2', TJSONObject.Create));
    Calls := List.FindToolCalls;
    Assert(Length(Calls) = 2, 'Should find 2 tool calls');
    Assert(Calls[0].Id = 'id1', 'First call id should match');
    Assert(Calls[1].Id = 'id2', 'Second call id should match');
  finally
    List.Free;
  end;
end;

procedure TTestContentBlockList.Test_FindToolCalls_None;
var
  List: TContentBlockList;
  Calls: TArray<TToolCall>;
begin
  List := TContentBlockList.Create;
  try
    List.Add(TTextContent.Create('No tools'));
    Calls := List.FindToolCalls;
    Assert(Length(Calls) = 0, 'Should find 0 tool calls');
  finally
    List.Free;
  end;
end;

procedure TTestContentBlockList.Test_ToJson_FromJson_RoundTrip;
var
  List, Restored: TContentBlockList;
  Json: TJSONArray;
begin
  List := TContentBlockList.Create;
  try
    List.Add(TTextContent.Create('Hello'));
    List.Add(TThinkingContent.Create('Hmm'));
    List.Add(TToolCall.Create('tc1', 'read',
      TJSONObject.ParseJSONValue('{"path":"a.txt"}') as TJSONObject));

    Json := List.ToJson;
    try
      Restored := TContentBlockList.FromJson(Json);
      try
        Assert(Restored.Count = 3, 'Restored count should be 3');
        Assert(Restored[0].ContentType = cbtText, 'First should be text');
        Assert(Restored[1].ContentType = cbtThinking, 'Second should be thinking');
        Assert(Restored[2].ContentType = cbtToolCall, 'Third should be toolCall');
        Assert(TTextContent(Restored[0]).Text = 'Hello', 'Text should match');
        Assert(TThinkingContent(Restored[1]).Thinking = 'Hmm', 'Thinking should match');
        Assert(TToolCall(Restored[2]).Id = 'tc1', 'ToolCall id should match');
      finally
        Restored.Free;
      end;
    finally
      Json.Free;
    end;
  finally
    List.Free;
  end;
end;

procedure TTestContentBlockList.Test_FromJson_Nil;
var
  List: TContentBlockList;
begin
  List := TContentBlockList.FromJson(nil);
  try
    Assert(List.Count = 0, 'Count should be 0 for nil input');
  finally
    List.Free;
  end;
end;

{ TTestMessages }

procedure TTestMessages.Test_UserMessage_Text;
var
  Msg: TUserMessage;
begin
  Msg := TUserMessage.Create('Hello agent');
  try
    Assert(Msg.Role = mrUser, 'Role should be mrUser');
    Assert(Msg.Content = 'Hello agent', 'Content should match');
    Assert(not Msg.HasStructuredContent, 'Should not have structured content');
    Assert(not Msg.IsCompactionSummary, 'Should not be compaction summary');
  finally
    Msg.Free;
  end;
end;

procedure TTestMessages.Test_UserMessage_StructuredContent;
var
  Blocks: TContentBlockList;
  Msg: TUserMessage;
begin
  Blocks := TContentBlockList.Create;
  Blocks.Add(TTextContent.Create('Part 1'));
  Blocks.Add(TTextContent.Create('Part 2'));
  Msg := TUserMessage.Create(Blocks);
  try
    Assert(Msg.HasStructuredContent, 'Should have structured content');
    Assert(Msg.ContentBlocks.Count = 2, 'Should have 2 blocks');
  finally
    Msg.Free;
  end;
end;

procedure TTestMessages.Test_UserMessage_CompactionSummary;
var
  Msg: TUserMessage;
begin
  Msg := TUserMessage.Create('Summary of conversation');
  try
    Msg.IsCompactionSummary := True;
    Assert(Msg.IsCompactionSummary, 'Should be compaction summary');
  finally
    Msg.Free;
  end;
end;

procedure TTestMessages.Test_UserMessage_ToJson_FromJson;
var
  Msg, Restored: TAgentMessage;
  Json: TJSONObject;
begin
  Msg := TUserMessage.Create('Test message');
  try
    TUserMessage(Msg).IsCompactionSummary := True;
    Json := Msg.ToJson;
    try
      Restored := TAgentMessage.FromJson(Json);
      try
        Assert(Restored <> nil, 'Restored should not be nil');
        Assert(Restored.Role = mrUser, 'Role should be mrUser');
        Assert(TUserMessage(Restored).Content = 'Test message', 'Content should match');
        Assert(TUserMessage(Restored).IsCompactionSummary, 'Should be compaction summary');
      finally
        Restored.Free;
      end;
    finally
      Json.Free;
    end;
  finally
    Msg.Free;
  end;
end;

procedure TTestMessages.Test_AssistantMessage_WithToolCalls;
var
  Msg: TAssistantMessage;
  Calls: TArray<TToolCall>;
begin
  Msg := TAssistantMessage.Create;
  try
    Msg.Content.Add(TTextContent.Create('Let me read that file.'));
    Msg.Content.Add(TToolCall.Create('call_1', 'read_file',
      TJSONObject.ParseJSONValue('{"path":"test.txt"}') as TJSONObject));
    Msg.StopReason := srToolUse;

    Calls := Msg.Content.FindToolCalls;
    Assert(Length(Calls) = 1, 'Should find 1 tool call');
    Assert(Calls[0].Id = 'call_1', 'Tool call id should match');
    Assert(Calls[0].Name = 'read_file', 'Tool call name should match');
  finally
    Msg.Free;
  end;
end;

procedure TTestMessages.Test_AssistantMessage_ToJson_FromJson;
var
  Msg: TAssistantMessage;
  Restored: TAgentMessage;
  Json: TJSONObject;
  U: TUsage;
begin
  Msg := TAssistantMessage.Create;
  try
    Msg.Content.Add(TTextContent.Create('Response text'));
    Msg.Api := 'custom';
    Msg.Provider := 'test';
    Msg.Model := 'gpt-4';
    Msg.StopReason := srStop;
    U := Default(TUsage);
    U.Input := 100;
    U.Output := 50;
    U.TotalTokens := 150;
    Msg.Usage := U;

    Json := Msg.ToJson;
    try
      Restored := TAgentMessage.FromJson(Json);
      try
        Assert(Restored.Role = mrAssistant, 'Role should be mrAssistant');
        Assert(TAssistantMessage(Restored).Api = 'custom', 'Api should match');
        Assert(TAssistantMessage(Restored).Model = 'gpt-4', 'Model should match');
        Assert(TAssistantMessage(Restored).StopReason = srStop, 'StopReason should match');
      finally
        Restored.Free;
      end;
    finally
      Json.Free;
    end;
  finally
    Msg.Free;
  end;
end;

procedure TTestMessages.Test_AssistantMessage_Usage;
var
  Msg: TAssistantMessage;
  Json, UsageJson: TJSONObject;
  U: TUsage;
begin
  Msg := TAssistantMessage.Create;
  try
    U := Default(TUsage);
    U.Input := 500;
    U.Output := 200;
    U.TotalTokens := 700;
    U.Cost.Input := 0.01;
    U.Cost.Output := 0.02;
    U.Cost.Total := 0.03;
    Msg.Usage := U;

    Json := Msg.ToJson;
    try
      UsageJson := Json.FindValue('usage') as TJSONObject;
      Assert(UsageJson <> nil, 'Usage JSON should not be nil');
      Assert(JsonGetInt(UsageJson, 'input', 0) = 500, 'Input should be 500');
      Assert(JsonGetInt(UsageJson, 'output', 0) = 200, 'Output should be 200');
      Assert(JsonGetInt(UsageJson, 'totalTokens', 0) = 700, 'TotalTokens should be 700');
    finally
      Json.Free;
    end;
  finally
    Msg.Free;
  end;
end;

procedure TTestMessages.Test_ToolResultMessage_Create;
var
  Content: TContentBlockList;
  Msg: TToolResultMessage;
begin
  Content := TContentBlockList.Create;
  Content.Add(TTextContent.Create('File contents here'));
  Msg := TToolResultMessage.Create('call_1', 'read_file', Content, False);
  try
    Assert(Msg.ToolCallId = 'call_1', 'ToolCallId should match');
    Assert(Msg.ToolName = 'read_file', 'ToolName should match');
    Assert(not Msg.IsError, 'Should not be error');
    Assert(Msg.Content.Count = 1, 'Content count should be 1');
  finally
    Msg.Free;
  end;
end;

procedure TTestMessages.Test_ToolResultMessage_ToJson_FromJson;
var
  Content: TContentBlockList;
  Msg, Restored: TAgentMessage;
  Json: TJSONObject;
begin
  Content := TContentBlockList.Create;
  Content.Add(TTextContent.Create('Error: not found'));
  Msg := TToolResultMessage.Create('call_2', 'read_file', Content, True);
  try
    Json := Msg.ToJson;
    try
      Restored := TAgentMessage.FromJson(Json);
      try
        Assert(Restored.Role = mrToolResult, 'Role should be mrToolResult');
        Assert(TToolResultMessage(Restored).ToolCallId = 'call_2', 'ToolCallId should match');
        Assert(TToolResultMessage(Restored).ToolName = 'read_file', 'ToolName should match');
        Assert(TToolResultMessage(Restored).IsError, 'Should be error');
      finally
        Restored.Free;
      end;
    finally
      Json.Free;
    end;
  finally
    Msg.Free;
  end;
end;

procedure TTestMessages.Test_ToolResultMessage_IsError;
var
  Content: TContentBlockList;
  Msg: TToolResultMessage;
begin
  Content := TContentBlockList.Create;
  Content.Add(TTextContent.Create('Error: permission denied'));
  Msg := TToolResultMessage.Create('call_3', 'bash', Content, True);
  try
    Assert(Msg.IsError, 'Should be error');
  finally
    Msg.Free;
  end;
end;

procedure TTestMessages.Test_CostInfo_Empty;
var
  Cost: TCostInfo;
begin
  Cost := TCostInfo.Empty;
  Assert(Cost.Input = 0, 'Input should be 0');
  Assert(Cost.Output = 0, 'Output should be 0');
  Assert(Cost.CacheRead = 0, 'CacheRead should be 0');
  Assert(Cost.CacheWrite = 0, 'CacheWrite should be 0');
end;

procedure TTestMessages.Test_Usage_Empty;
var
  U: TUsage;
begin
  U := TUsage.Empty;
  Assert(U.Input = 0, 'Input should be 0');
  Assert(U.Output = 0, 'Output should be 0');
  Assert(U.TotalTokens = 0, 'TotalTokens should be 0');
  Assert(U.Cost.Input = 0, 'Cost.Input should be 0');
  Assert(U.Cost.Output = 0, 'Cost.Output should be 0');
end;

procedure TTestMessages.Test_ImageContent_Clone;
var
  Block, Cloned: TContentBlock;
begin
  Block := TImageContent.Create('base64abc', 'image/png');
  try
    Cloned := Block.Clone;
    try
      Assert(TImageContent(Cloned).Data = 'base64abc', 'Cloned data should match');
      Assert(TImageContent(Cloned).MimeType = 'image/png', 'Cloned mimeType should match');
      // Modify clone, verify original is unchanged
      TImageContent(Cloned).Data := 'modified';
      Assert(TImageContent(Block).Data = 'base64abc', 'Original data should be unchanged');
      Assert(TImageContent(Cloned).Data = 'modified', 'Clone should be modified');
    finally
      Cloned.Free;
    end;
  finally
    Block.Free;
  end;
end;

{ TTestMessageList }

procedure TTestMessageList.Test_Add_And_Count;
var
  List: TAgentMessageList;
begin
  List := TAgentMessageList.Create;
  try
    List.Add(TUserMessage.Create('Msg 1'));
    List.Add(TUserMessage.Create('Msg 2'));
    List.Add(TUserMessage.Create('Msg 3'));
    Assert(List.Count = 3, 'Count should be 3');
  finally
    List.Free;
  end;
end;

procedure TTestMessageList.Test_Clear_FreesAll;
var
  List: TAgentMessageList;
begin
  List := TAgentMessageList.Create;
  try
    List.Add(TUserMessage.Create('Msg 1'));
    List.Add(TUserMessage.Create('Msg 2'));
    List.Clear;
    Assert(List.Count = 0, 'Count should be 0 after clear');
  finally
    List.Free;
  end;
end;

procedure TTestMessageList.Test_Clone_DeepCopy;
var
  List, Clone: TAgentMessageList;
begin
  List := TAgentMessageList.Create;
  try
    List.Add(TUserMessage.Create('Original'));
    Clone := List.Clone;
    try
      Assert(Clone.Count = 1, 'Clone count should be 1');
      // Verify independence: original count unchanged
      Assert(List.Count = 1, 'Original count should still be 1');
    finally
      Clone.Free;
    end;
  finally
    List.Free;
  end;
end;

procedure TTestMessageList.Test_Clone_ModifyOriginal;
var
  List, Clone: TAgentMessageList;
begin
  List := TAgentMessageList.Create;
  try
    List.Add(TUserMessage.Create('Keep'));
    Clone := List.Clone;
    try
      // Add to original after clone
      List.Add(TUserMessage.Create('New'));
      Assert(Clone.Count = 1, 'Clone should not see new items');
      Assert(List.Count = 2, 'Original should have new items');
    finally
      Clone.Free;
    end;
  finally
    List.Free;
  end;
end;

procedure TTestMessageList.Test_ExtractAll_OwnershipTransfer;
var
  List: TAgentMessageList;
  Arr: TArray<TAgentMessage>;
begin
  List := TAgentMessageList.Create;
  try
    List.Add(TUserMessage.Create('Msg 1'));
    List.Add(TUserMessage.Create('Msg 2'));
    Arr := List.ExtractAll;
    try
      Assert(Length(Arr) = 2, 'Extracted array should have 2 items');
      Assert(List.Count = 0, 'List should be empty after ExtractAll');
      // We now own the messages, must free them
    finally
      Arr[0].Free;
      Arr[1].Free;
    end;
  finally
    List.Free;
  end;
end;

procedure TTestMessageList.Test_Delete_Middle;
var
  List: TAgentMessageList;
begin
  List := TAgentMessageList.Create;
  try
    List.Add(TUserMessage.Create('A'));
    List.Add(TUserMessage.Create('B'));
    List.Add(TUserMessage.Create('C'));
    List.Delete(1); // Delete 'B'
    Assert(List.Count = 2, 'Count should be 2 after delete');
    Assert(TUserMessage(List[0]).Content = 'A', 'First should be A');
    Assert(TUserMessage(List[1]).Content = 'C', 'Second should be C');
  finally
    List.Free;
  end;
end;

procedure TTestMessageList.Test_Delete_OutOfRange;
var
  List: TAgentMessageList;
  Raised: Boolean;
begin
  List := TAgentMessageList.Create;
  try
    List.Add(TUserMessage.Create('A'));
    Raised := False;
    try
      List.Delete(5);
    except
      on E: EArgumentOutOfRangeException do
        Raised := True;
    end;
    Assert(Raised, 'Should raise EArgumentOutOfRangeException');
  finally
    List.Free;
  end;
end;

procedure TTestMessageList.Test_Last_Empty;
var
  List: TAgentMessageList;
begin
  List := TAgentMessageList.Create;
  try
    Assert(List.Last = nil, 'Last should be nil for empty list');
  finally
    List.Free;
  end;
end;

procedure TTestMessageList.Test_ToArray_SharedRefs;
var
  List: TAgentMessageList;
  Arr: TArray<TAgentMessage>;
begin
  List := TAgentMessageList.Create;
  try
    List.Add(TUserMessage.Create('X'));
    Arr := List.ToArray;
    Assert(Length(Arr) = 1, 'Array length should be 1');
    Assert(Arr[0] <> nil, 'Array element should not be nil');
    // Do NOT free Arr[0] - shared refs
  finally
    List.Free;
  end;
end;

{ TTestMessageRoleHelpers }

procedure TTestMessageRoleHelpers.Test_MessageRoleToString;
begin
  Assert(MessageRoleToString(mrUser) = 'user', 'mrUser should be user');
  Assert(MessageRoleToString(mrAssistant) = 'assistant', 'mrAssistant should be assistant');
  Assert(MessageRoleToString(mrToolResult) = 'toolResult', 'mrToolResult should be toolResult');
end;

procedure TTestMessageRoleHelpers.Test_StopReasonRoundTrip;
var
  Reasons: array[0..4] of TStopReason;
  i: Integer;
begin
  Reasons[0] := srStop;
  Reasons[1] := srLength;
  Reasons[2] := srToolUse;
  Reasons[3] := srError;
  Reasons[4] := srAborted;
  for i := 0 to High(Reasons) do
    Assert(Ord(Reasons[i]) = Ord(StringToStopReason(StopReasonToString(Reasons[i]))),
      'StopReason roundtrip failed at index ' + IntToStr(i));
end;

procedure TTestMessageRoleHelpers.Test_StringToStopReason_Unknown;
begin
  Assert(StringToStopReason('unknown_value') = srStop,
    'Unknown stop reason should default to srStop');
end;

{ Registration }

procedure RegisterMessageTests;
var
  CB: TTestContentBlock;
  CBL: TTestContentBlockList;
  Msg: TTestMessages;
  ML: TTestMessageList;
  RH: TTestMessageRoleHelpers;
begin
  CB := TTestContentBlock.Create;
  CBL := TTestContentBlockList.Create;
  Msg := TTestMessages.Create;
  ML := TTestMessageList.Create;
  RH := TTestMessageRoleHelpers.Create;
  try
    GRunner.RunTest('ContentBlock.TextContent_Create', CB.Test_TextContent_Create);
    GRunner.RunTest('ContentBlock.TextContent_Clone', CB.Test_TextContent_Clone);
    GRunner.RunTest('ContentBlock.TextContent_ToJson', CB.Test_TextContent_ToJson);
    GRunner.RunTest('ContentBlock.ThinkingContent_Create', CB.Test_ThinkingContent_Create);
    GRunner.RunTest('ContentBlock.ThinkingContent_Clone', CB.Test_ThinkingContent_Clone);
    GRunner.RunTest('ContentBlock.ImageContent_ToJson', CB.Test_ImageContent_ToJson);
    GRunner.RunTest('ContentBlock.ToolCall_Create', CB.Test_ToolCall_Create);
    GRunner.RunTest('ContentBlock.ToolCall_Clone_Independence', CB.Test_ToolCall_Clone_Independence);
    GRunner.RunTest('ContentBlock.ToolCall_ToJson', CB.Test_ToolCall_ToJson);

    GRunner.RunTest('ContentBlockList.Add_ThreeItems', CBL.Test_Add_ThreeItems);
    GRunner.RunTest('ContentBlockList.Clear_FreesItems', CBL.Test_Clear_FreesItems);
    GRunner.RunTest('ContentBlockList.Clone_DeepCopy', CBL.Test_Clone_DeepCopy);
    GRunner.RunTest('ContentBlockList.FindToolCalls_Mixed', CBL.Test_FindToolCalls_Mixed);
    GRunner.RunTest('ContentBlockList.FindToolCalls_None', CBL.Test_FindToolCalls_None);
    GRunner.RunTest('ContentBlockList.ToJson_FromJson_RoundTrip', CBL.Test_ToJson_FromJson_RoundTrip);
    GRunner.RunTest('ContentBlockList.FromJson_Nil', CBL.Test_FromJson_Nil);

    GRunner.RunTest('Messages.UserMessage_Text', Msg.Test_UserMessage_Text);
    GRunner.RunTest('Messages.UserMessage_StructuredContent', Msg.Test_UserMessage_StructuredContent);
    GRunner.RunTest('Messages.UserMessage_CompactionSummary', Msg.Test_UserMessage_CompactionSummary);
    GRunner.RunTest('Messages.UserMessage_ToJson_FromJson', Msg.Test_UserMessage_ToJson_FromJson);
    GRunner.RunTest('Messages.AssistantMessage_WithToolCalls', Msg.Test_AssistantMessage_WithToolCalls);
    GRunner.RunTest('Messages.AssistantMessage_ToJson_FromJson', Msg.Test_AssistantMessage_ToJson_FromJson);
    GRunner.RunTest('Messages.AssistantMessage_Usage', Msg.Test_AssistantMessage_Usage);
    GRunner.RunTest('Messages.ToolResultMessage_Create', Msg.Test_ToolResultMessage_Create);
    GRunner.RunTest('Messages.ToolResultMessage_ToJson_FromJson', Msg.Test_ToolResultMessage_ToJson_FromJson);
    GRunner.RunTest('Messages.ToolResultMessage_IsError', Msg.Test_ToolResultMessage_IsError);
    GRunner.RunTest('Messages.CostInfo_Empty', Msg.Test_CostInfo_Empty);
    GRunner.RunTest('Messages.Usage_Empty', Msg.Test_Usage_Empty);
    GRunner.RunTest('Messages.ImageContent_Clone', Msg.Test_ImageContent_Clone);

    GRunner.RunTest('MessageList.Add_And_Count', ML.Test_Add_And_Count);
    GRunner.RunTest('MessageList.Clear_FreesAll', ML.Test_Clear_FreesAll);
    GRunner.RunTest('MessageList.Clone_DeepCopy', ML.Test_Clone_DeepCopy);
    GRunner.RunTest('MessageList.Clone_ModifyOriginal', ML.Test_Clone_ModifyOriginal);
    GRunner.RunTest('MessageList.ExtractAll_OwnershipTransfer', ML.Test_ExtractAll_OwnershipTransfer);
    GRunner.RunTest('MessageList.Delete_Middle', ML.Test_Delete_Middle);
    GRunner.RunTest('MessageList.Delete_OutOfRange', ML.Test_Delete_OutOfRange);
    GRunner.RunTest('MessageList.Last_Empty', ML.Test_Last_Empty);
    GRunner.RunTest('MessageList.ToArray_SharedRefs', ML.Test_ToArray_SharedRefs);

    GRunner.RunTest('MessageRoleHelpers.MessageRoleToString', RH.Test_MessageRoleToString);
    GRunner.RunTest('MessageRoleHelpers.StopReasonRoundTrip', RH.Test_StopReasonRoundTrip);
    GRunner.RunTest('MessageRoleHelpers.StringToStopReason_Unknown', RH.Test_StringToStopReason_Unknown);
  finally
    CB.Free;
    CBL.Free;
    Msg.Free;
    ML.Free;
    RH.Free;
  end;
end;

end.
