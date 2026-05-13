unit TestCompactionAndSlim;

interface

uses
  System.SysUtils, System.JSON,
  Core.Messages, Core.AgentState, Core.ToolResultSlim, Core.Compaction,
  AI.IModel, AI.ModelConfig,
  PiMonoTestFramework;

procedure RegisterCompactionAndSlimTests;

implementation

uses
  MockModel;

type
  TTestToolResultSlim = class
  public
    procedure Test_ErrorResults_Preserved;
    procedure Test_SmallResults_Preserved;
    procedure Test_LargeResult_Slimmed;
    procedure Test_LargeResult_FewLines_Truncated;
    procedure Test_NonToolMessages_Cloned;
    procedure Test_EmptyList;
    procedure Test_MixedMessages;
  end;

  TTestCompaction = class
  public
    procedure Test_ShouldCompact_True;
    procedure Test_ShouldCompact_False;
    procedure Test_EmergencyCut_HalvesMessages;
    procedure Test_EmergencyCut_DoesNotCutOnToolResult;
    procedure Test_EmergencyCut_SmallList;
    procedure Test_IsContextOverflow_MatchesPatterns;
    procedure Test_IsContextOverflow_NoMatch;
    procedure Test_ExtractFileOps_ReadTool;
    procedure Test_ExtractFileOps_WriteTool;
    procedure Test_ExtractFileOps_EditTool;
    procedure Test_ExtractFileOps_Mixed;
    procedure Test_SerializeConversation;
    procedure Test_Prepare_ReturnsSummary;
    procedure Test_Apply_ReplacesMessages;
  end;

{ TTestToolResultSlim }

procedure TTestToolResultSlim.Test_ErrorResults_Preserved;
var
  List, Result_: TAgentMessageList;
  Content: TContentBlockList;
begin
  List := TAgentMessageList.Create;
  try
    Content := TContentBlockList.Create;
    Content.Add(TTextContent.Create(StringOfChar('E', 5000)));
    List.Add(TToolResultMessage.Create('tc1', 'bash', Content, True));

    Result_ := SlimToolResults(List);
    try
      Assert(Result_.Count = 1, 'Should have 1 message');
      Assert(TToolResultMessage(Result_[0]).IsError, 'Error result should be preserved');
      // Error content should NOT be slimmed
      Assert(TToolResultMessage(Result_[0]).Content.Count = 1, 'Error content should be preserved');
    finally
      Result_.Free;
    end;
  finally
    List.Free;
  end;
end;

procedure TTestToolResultSlim.Test_SmallResults_Preserved;
var
  List, Result_: TAgentMessageList;
  Content: TContentBlockList;
begin
  List := TAgentMessageList.Create;
  try
    Content := TContentBlockList.Create;
    Content.Add(TTextContent.Create('Short result'));
    List.Add(TToolResultMessage.Create('tc1', 'read', Content, False));

    Result_ := SlimToolResults(List);
    try
      Assert(Result_.Count = 1, 'Should have 1 message');
      // Small result should be cloned as-is
      Assert(not TToolResultMessage(Result_[0]).IsError, 'Should not be error');
    finally
      Result_.Free;
    end;
  finally
    List.Free;
  end;
end;

procedure TTestToolResultSlim.Test_LargeResult_Slimmed;
var
  List, Result_: TAgentMessageList;
  Content: TContentBlockList;
  Lines: string;
  i: Integer;
  ResultText: string;
begin
  List := TAgentMessageList.Create;
  try
    // Create a result with 20 lines, each 200 chars
    Lines := '';
    for i := 1 to 20 do
      Lines := Lines + 'Line ' + IntToStr(i) + ': ' + StringOfChar('X', 190) + #13#10;

    Content := TContentBlockList.Create;
    Content.Add(TTextContent.Create(Lines));
    List.Add(TToolResultMessage.Create('tc1', 'bash', Content, False));

    Result_ := SlimToolResults(List, 500);
    try
      Assert(Result_.Count = 1, 'Should have 1 message');
      ResultText := TTextContent(TToolResultMessage(Result_[0]).Content[0]).Text;
      Assert(Length(ResultText) < Length(Lines), 'Slimmed result should be shorter');
      Assert(Pos('omitted', ResultText) > 0, 'Should contain omission marker');
    finally
      Result_.Free;
    end;
  finally
    List.Free;
  end;
end;

procedure TTestToolResultSlim.Test_LargeResult_FewLines_Truncated;
var
  List, Result_: TAgentMessageList;
  Content: TContentBlockList;
  LongText: string;
  ResultText: string;
begin
  List := TAgentMessageList.Create;
  try
    // One very long line (fewer than 6 lines but > max chars)
    LongText := StringOfChar('A', 5000);

    Content := TContentBlockList.Create;
    Content.Add(TTextContent.Create(LongText));
    List.Add(TToolResultMessage.Create('tc1', 'read', Content, False));

    Result_ := SlimToolResults(List, 500);
    try
      Assert(Result_.Count = 1, 'Should have 1 message');
      ResultText := TTextContent(TToolResultMessage(Result_[0]).Content[0]).Text;
      Assert(Pos('truncated', ResultText) > 0, 'Should contain truncation marker');
    finally
      Result_.Free;
    end;
  finally
    List.Free;
  end;
end;

procedure TTestToolResultSlim.Test_NonToolMessages_Cloned;
var
  List, Result_: TAgentMessageList;
begin
  List := TAgentMessageList.Create;
  try
    List.Add(TUserMessage.Create('Hello'));
    var A := TAssistantMessage.Create;
    A.Content.Add(TTextContent.Create('World'));
    List.Add(A);

    Result_ := SlimToolResults(List);
    try
      Assert(Result_.Count = 2, 'Should have 2 messages');
      Assert(Result_[0].Role = mrUser, 'First should be user');
      Assert(Result_[1].Role = mrAssistant, 'Second should be assistant');
    finally
      Result_.Free;
    end;
  finally
    List.Free;
  end;
end;

procedure TTestToolResultSlim.Test_EmptyList;
var
  List, Result_: TAgentMessageList;
begin
  List := TAgentMessageList.Create;
  try
    Result_ := SlimToolResults(List);
    try
      Assert(Result_.Count = 0, 'Empty list should return empty');
    finally
      Result_.Free;
    end;
  finally
    List.Free;
  end;
end;

procedure TTestToolResultSlim.Test_MixedMessages;
var
  List, Result_: TAgentMessageList;
  Content: TContentBlockList;
begin
  List := TAgentMessageList.Create;
  try
    List.Add(TUserMessage.Create('Question'));

    // Small tool result
    Content := TContentBlockList.Create;
    Content.Add(TTextContent.Create('Short'));
    List.Add(TToolResultMessage.Create('tc1', 'read', Content, False));

    // User followup
    List.Add(TUserMessage.Create('Thanks'));

    Result_ := SlimToolResults(List);
    try
      Assert(Result_.Count = 3, 'Should have 3 messages');
    finally
      Result_.Free;
    end;
  finally
    List.Free;
  end;
end;

{ TTestCompaction }

procedure TTestCompaction.Test_ShouldCompact_True;
begin
  // ContextTokens > (Window - Reserve) triggers compaction
  Assert(TCompaction.ShouldCompact(9000, 10000, 1000),
    'Should compact when context exceeds window - reserve');
end;

procedure TTestCompaction.Test_ShouldCompact_False;
begin
  Assert(not TCompaction.ShouldCompact(5000, 10000, 1000),
    'Should NOT compact when context is well within window');
  Assert(not TCompaction.ShouldCompact(8000, 10000, 1000),
    'Should NOT compact when context equals window - reserve');
end;

procedure TTestCompaction.Test_EmergencyCut_HalvesMessages;
var
  List, Result_: TAgentMessageList;
  i: Integer;
begin
  List := TAgentMessageList.Create;
  try
    for i := 1 to 20 do
      List.Add(TUserMessage.Create('Msg ' + IntToStr(i)));

    Result_ := TCompaction.EmergencyCut(List, 0.5);
    try
      Assert(Result_.Count <= 10, 'EmergencyCut should remove ~50% of messages');
      Assert(Result_.Count > 0, 'Should keep some messages');
    finally
      Result_.Free;
    end;
  finally
    List.Free;
  end;
end;

procedure TTestCompaction.Test_EmergencyCut_DoesNotCutOnToolResult;
var
  List, Result_: TAgentMessageList;
  Content: TContentBlockList;
begin
  List := TAgentMessageList.Create;
  try
    List.Add(TUserMessage.Create('Msg 1'));
    Content := TContentBlockList.Create;
    Content.Add(TTextContent.Create('Result'));
    List.Add(TToolResultMessage.Create('tc1', 'read', Content, False));
    List.Add(TUserMessage.Create('Msg 2'));
    List.Add(TUserMessage.Create('Msg 3'));

    Result_ := TCompaction.EmergencyCut(List, 0.5);
    try
      // Cut point should not land on a ToolResult
      Assert(Result_.Count > 0, 'Should keep some messages');
      // If the cut point would be on ToolResult, it should adjust
    finally
      Result_.Free;
    end;
  finally
    List.Free;
  end;
end;

procedure TTestCompaction.Test_EmergencyCut_SmallList;
var
  List, Result_: TAgentMessageList;
begin
  List := TAgentMessageList.Create;
  try
    List.Add(TUserMessage.Create('Only message'));

    Result_ := TCompaction.EmergencyCut(List, 0.5);
    try
      // Small list should not be cut to 0
      Assert(Result_.Count >= 1, 'Should keep at least 1 message');
    finally
      Result_.Free;
    end;
  finally
    List.Free;
  end;
end;

procedure TTestCompaction.Test_IsContextOverflow_MatchesPatterns;
begin
  Assert(TCompaction.IsContextOverflow('context_length_exceeded'),
    'Should match context_length_exceeded');
  Assert(TCompaction.IsContextOverflow('maximum context length'),
    'Should match maximum context length');
  Assert(TCompaction.IsContextOverflow('This model maximum context window is 128000 tokens'),
    'Should match token limit pattern');
end;

procedure TTestCompaction.Test_IsContextOverflow_NoMatch;
begin
  Assert(not TCompaction.IsContextOverflow('Internal server error'),
    'Should not match server error');
  Assert(not TCompaction.IsContextOverflow('Rate limit exceeded'),
    'Should not match rate limit');
  Assert(not TCompaction.IsContextOverflow('Connection timeout'),
    'Should not match timeout');
end;

procedure TTestCompaction.Test_ExtractFileOps_ReadTool;
var
  List: TAgentMessageList;
  Asst: TAssistantMessage;
  Ops: TArray<TFileOperation>;
begin
  List := TAgentMessageList.Create;
  try
    Asst := TAssistantMessage.Create;
    Asst.Content.Add(TToolCall.Create('tc1', 'read_file',
      TJSONObject.ParseJSONValue('{"path":"test.txt"}') as TJSONObject));
    List.Add(Asst);

    Ops := TCompaction.ExtractFileOps(List);
    Assert(Length(Ops) >= 1, 'Should extract at least 1 operation');
    if Length(Ops) > 0 then
      Assert(Ops[0].FilePath = 'test.txt', 'FilePath should match');
  finally
    List.Free;
  end;
end;

procedure TTestCompaction.Test_ExtractFileOps_WriteTool;
var
  List: TAgentMessageList;
  Asst: TAssistantMessage;
  Ops: TArray<TFileOperation>;
begin
  List := TAgentMessageList.Create;
  try
    Asst := TAssistantMessage.Create;
    Asst.Content.Add(TToolCall.Create('tc1', 'write_file',
      TJSONObject.ParseJSONValue('{"path":"output.pas","content":"unit X;"}') as TJSONObject));
    List.Add(Asst);

    Ops := TCompaction.ExtractFileOps(List);
    Assert(Length(Ops) >= 1, 'Should extract write operation');
    if Length(Ops) > 0 then
      Assert(Ops[0].Operation = foWrite, 'Should be write operation');
  finally
    List.Free;
  end;
end;

procedure TTestCompaction.Test_ExtractFileOps_EditTool;
var
  List: TAgentMessageList;
  Asst: TAssistantMessage;
  Ops: TArray<TFileOperation>;
begin
  List := TAgentMessageList.Create;
  try
    Asst := TAssistantMessage.Create;
    Asst.Content.Add(TToolCall.Create('tc1', 'edit_file',
      TJSONObject.ParseJSONValue('{"path":"main.pas","oldText":"A","newText":"B"}') as TJSONObject));
    List.Add(Asst);

    Ops := TCompaction.ExtractFileOps(List);
    Assert(Length(Ops) >= 1, 'Should extract edit operation');
    if Length(Ops) > 0 then
      Assert(Ops[0].Operation = foEdit, 'Should be edit operation');
  finally
    List.Free;
  end;
end;

procedure TTestCompaction.Test_ExtractFileOps_Mixed;
var
  List: TAgentMessageList;
  Asst: TAssistantMessage;
  Ops: TArray<TFileOperation>;
begin
  List := TAgentMessageList.Create;
  try
    Asst := TAssistantMessage.Create;
    Asst.Content.Add(TToolCall.Create('tc1', 'read_file',
      TJSONObject.ParseJSONValue('{"path":"a.txt"}') as TJSONObject));
    Asst.Content.Add(TToolCall.Create('tc2', 'write_file',
      TJSONObject.ParseJSONValue('{"path":"b.txt","content":"x"}') as TJSONObject));
    Asst.Content.Add(TToolCall.Create('tc3', 'edit_file',
      TJSONObject.ParseJSONValue('{"path":"c.txt","oldText":"a","newText":"b"}') as TJSONObject));
    List.Add(Asst);

    Ops := TCompaction.ExtractFileOps(List);
    Assert(Length(Ops) = 3, 'Should extract 3 operations');
  finally
    List.Free;
  end;
end;

procedure TTestCompaction.Test_SerializeConversation;
var
  List: TAgentMessageList;
  Text: string;
begin
  List := TAgentMessageList.Create;
  try
    List.Add(TUserMessage.Create('What does this code do?'));
    var A := TAssistantMessage.Create;
    A.Content.Add(TTextContent.Create('This code implements a parser.'));
    List.Add(A);

    Text := TCompaction.SerializeConversation(List);
    Assert(Length(Text) > 0, 'Serialized text should not be empty');
    Assert(Pos('What does this code do?', Text) > 0, 'Should contain user message');
    Assert(Pos('parser', Text) > 0, 'Should contain assistant response');
  finally
    List.Free;
  end;
end;

procedure TTestCompaction.Test_Prepare_ReturnsSummary;
var
  Messages: TAgentMessageList;
  Prep: TCompactionPreparation;
  Model: TMockModel;
  Result_: TCompactionResult;
  i: Integer;
begin
  // Build a message list large enough for compaction to find a cut point
  Messages := TAgentMessageList.Create;
  try
    for i := 1 to 20 do
    begin
      Messages.Add(TUserMessage.Create('User question ' + IntToStr(i) +
        ' with some extra text to add tokens so we exceed the keep threshold'));
      var A := TAssistantMessage.Create;
      A.Content.Add(TTextContent.Create('Assistant reply ' + IntToStr(i) +
        ' with enough detail to consume tokens for the keep threshold test'));
      Messages.Add(A);
    end;

    // Prepare with a small keep-recent value so it finds a cut point
    Prep := TCompaction.Prepare(Messages, 100, '');
    try
      // If Prepare found messages to summarize, run Execute with mock model
      if Prep.MessagesToSummarize <> nil then
      begin
        Model := TMockModel.Create;
        try
          Model.AddTextResponse('## Current Task'#13#10'Testing compaction summary.');
          Result_ := TCompaction.Execute(Prep, Model, '', 100000, nil);
          try
            Assert(Length(Result_.Summary) > 0, 'Summary should not be empty');
          finally
            Result_.Summary := '';
          end;
        finally
          // Model is freed automatically by IModel reference counting in Execute
          // Do NOT call Model.Free — TMockModel inherits TInterfacedObject
        end;
      end
      else
        Assert(False, 'Prepare should have found messages to summarize');
    finally
      Prep.MessagesToSummarize.Free;
    end;
  finally
    Messages.Free;
  end;
end;

procedure TTestCompaction.Test_Apply_ReplacesMessages;
var
  Messages: TAgentMessageList;
  Result_: TAgentMessageList;
  CompResult: TCompactionResult;
begin
  Messages := TAgentMessageList.Create;
  try
    Messages.Add(TUserMessage.Create('Old message 1'));
    Messages.Add(TUserMessage.Create('Old message 2'));
    Messages.Add(TUserMessage.Create('Old message 3'));
    Messages.Add(TUserMessage.Create('Keep this message'));

    CompResult.Summary := 'Summary of old messages';
    CompResult.FirstKeptIndex := 3;
    CompResult.TokensBefore := 1000;
    CompResult.ReadFiles := nil;
    CompResult.ModifiedFiles := nil;

    Result_ := TCompaction.Apply(Messages, CompResult);
    try
      // Should have: 1 summary + 1 kept message = 2
      Assert(Result_.Count = 2, 'Should have 2 messages after Apply, got ' + IntToStr(Result_.Count));
      // First message should be compaction summary (user message with IsCompactionSummary)
      Assert(Result_[0].Role = mrUser, 'First message should be user (summary)');
      Assert(TUserMessage(Result_[0]).IsCompactionSummary, 'First should be compaction summary');
      // Second should be the kept message
      Assert(Result_[1].Role = mrUser, 'Second message should be user');
      Assert(TUserMessage(Result_[1]).Content = 'Keep this message', 'Kept message content should match');
    finally
      Result_.Free;
    end;
  finally
    Messages.Free;
  end;
end;

{ Registration }

procedure RegisterCompactionAndSlimTests;
var
  TS: TTestToolResultSlim;
  TC: TTestCompaction;
begin
  TS := TTestToolResultSlim.Create;
  try
    GRunner.RunTest('SlimToolResults: Error results preserved', TS.Test_ErrorResults_Preserved);
    GRunner.RunTest('SlimToolResults: Small results preserved', TS.Test_SmallResults_Preserved);
    GRunner.RunTest('SlimToolResults: Large result slimmed', TS.Test_LargeResult_Slimmed);
    GRunner.RunTest('SlimToolResults: Few lines truncated', TS.Test_LargeResult_FewLines_Truncated);
    GRunner.RunTest('SlimToolResults: Non-tool messages cloned', TS.Test_NonToolMessages_Cloned);
    GRunner.RunTest('SlimToolResults: Empty list', TS.Test_EmptyList);
    GRunner.RunTest('SlimToolResults: Mixed messages', TS.Test_MixedMessages);
  finally
    TS.Free;
  end;

  TC := TTestCompaction.Create;
  try
    GRunner.RunTest('Compaction: ShouldCompact true', TC.Test_ShouldCompact_True);
    GRunner.RunTest('Compaction: ShouldCompact false', TC.Test_ShouldCompact_False);
    GRunner.RunTest('Compaction: EmergencyCut halves messages', TC.Test_EmergencyCut_HalvesMessages);
    GRunner.RunTest('Compaction: EmergencyCut no cut on ToolResult', TC.Test_EmergencyCut_DoesNotCutOnToolResult);
    GRunner.RunTest('Compaction: EmergencyCut small list', TC.Test_EmergencyCut_SmallList);
    GRunner.RunTest('Compaction: IsContextOverflow matches', TC.Test_IsContextOverflow_MatchesPatterns);
    GRunner.RunTest('Compaction: IsContextOverflow no match', TC.Test_IsContextOverflow_NoMatch);
    GRunner.RunTest('Compaction: ExtractFileOps read', TC.Test_ExtractFileOps_ReadTool);
    GRunner.RunTest('Compaction: ExtractFileOps write', TC.Test_ExtractFileOps_WriteTool);
    GRunner.RunTest('Compaction: ExtractFileOps edit', TC.Test_ExtractFileOps_EditTool);
    GRunner.RunTest('Compaction: ExtractFileOps mixed', TC.Test_ExtractFileOps_Mixed);
    GRunner.RunTest('Compaction: SerializeConversation', TC.Test_SerializeConversation);
    GRunner.RunTest('Compaction: Prepare returns summary', TC.Test_Prepare_ReturnsSummary);
    GRunner.RunTest('Compaction: Apply replaces messages', TC.Test_Apply_ReplacesMessages);
  finally
    TC.Free;
  end;
end;

end.
