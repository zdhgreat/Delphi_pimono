unit TestSessionManager;

interface

uses
  System.SysUtils, System.JSON, System.IOUtils, Winapi.Windows,
  Core.Messages, Core.SessionManager,
  PiMonoTestFramework;

procedure RegisterSessionManagerTests;

implementation

type
  TTestSessionManager = class
  private
    FTestDir: string;
    FManager: TSessionManager;
  public
    procedure Setup;
    procedure TearDown;

    procedure Test_CreateSession;
    procedure Test_CreateSession_WithCustomName;
    procedure Test_SaveAndLoadSession;
    procedure Test_DeleteSession;
    procedure Test_ListSessions;
    procedure Test_SessionExists;
    procedure Test_RenameSession;
    procedure Test_AddUserMessage_Persisted;
    procedure Test_AddAssistantMessage_Persisted;
    procedure Test_AddToolResultMessage_Persisted;
    procedure Test_MultipleMessages_AppendWrite;
    procedure Test_LargeSession_RoundTrip;
    procedure Test_BranchFrom;
    procedure Test_BranchPreservesSystemPrompt;
    procedure Test_BranchPointCorrect;
    procedure Test_DeleteCurrentSession;
    procedure Test_DeleteNonExistentSession;
    procedure Test_LoadNonExistentSession;
    procedure Test_EmptySession_RoundTrip;
    procedure Test_SessionWithThinkingContent;
    procedure Test_SessionWithToolCalls;
    procedure Test_SetAndGetCurrentSession;
    procedure Test_MixedMessageTypesRoundtrip;
  end;

{ TTestSessionManager }

procedure TTestSessionManager.Setup;
begin
  FTestDir := TPath.Combine(TPath.GetTempPath,
    'PiMonoSession_' + FormatDateTime('yyyymmddhhnnsszzz', Now) + '_' + IntToStr(GetTickCount));
  TDirectory.CreateDirectory(FTestDir);
  FManager := TSessionManager.Create(nil, FTestDir);
end;

procedure TTestSessionManager.TearDown;
begin
  FManager.Free;
  try
    if TDirectory.Exists(FTestDir) then
      TDirectory.Delete(FTestDir, True);
  except
  end;
end;

procedure TTestSessionManager.Test_CreateSession;
var
  Session: TSession;
begin
  Session := FManager.CreateSession('Test Session');
  Assert(Session <> nil, 'Session should not be nil');
  Assert(Session.Id <> '', 'Session ID should not be empty');
  Assert(Session.Name = 'Test Session', 'Session name should match');
  Assert(Session.GetMessageCount = 0, 'New session should have 0 messages');
end;

procedure TTestSessionManager.Test_CreateSession_WithCustomName;
var
  Session: TSession;
begin
  Session := FManager.CreateSession('My Custom Name');
  Assert(Session.Name = 'My Custom Name', 'Name should be My Custom Name');
end;

procedure TTestSessionManager.Test_SaveAndLoadSession;
var
  Session, Loaded: TSession;
begin
  Session := FManager.CreateSession('Save/Load Test');
  try
    Session.AddMessage(TUserMessage.Create('Hello'));
    Session.AddMessage(TAssistantMessage.Create);
    TAssistantMessage(Session.Messages.Last).Content.Add(TTextContent.Create('Hi there!'));
    FManager.SaveSession(Session);

    Assert(TFile.Exists(Session.FilePath), 'Session file should exist after save');

    Loaded := FManager.LoadSession(Session.Id);
    Session := nil;
    try
      Assert(Loaded <> nil, 'Loaded session should not be nil');
      Assert(Loaded.GetMessageCount = 2, 'Should have 2 messages');
    finally
      Loaded.Free;
    end;
  finally
    Session.Free;
  end;
end;

procedure TTestSessionManager.Test_DeleteSession;
var
  Session: TSession;
  Id: string;
begin
  Session := FManager.CreateSession('To Delete');
  try
    Id := Session.Id;
    FManager.SaveSession(Session);
    Assert(FManager.SessionExists(Id), 'Session should exist before delete');

    FManager.DeleteSession(Id);
    Session := nil;
    Assert(not FManager.SessionExists(Id), 'Session should not exist after delete');
  finally
    Session.Free;
  end;
end;

procedure TTestSessionManager.Test_ListSessions;
var
  Sessions: TArray<TSessionInfo>;
begin
  FManager.CreateSession('Session A');
  FManager.CreateSession('Session B');
  FManager.CreateSession('Session C');

  Sessions := FManager.ListSessions;
  Assert(Length(Sessions) >= 0, 'ListSessions should not crash');
end;

procedure TTestSessionManager.Test_SessionExists;
var
  Session: TSession;
  Id: string;
begin
  Session := FManager.CreateSession('Exists Test');
  Id := Session.Id;
  Assert(not FManager.SessionExists(Id), 'Unsaved session should not exist on disk');
  FManager.SaveSession(Session);
  Assert(FManager.SessionExists(Id), 'Saved session should exist on disk');
end;

procedure TTestSessionManager.Test_RenameSession;
var
  Session: TSession;
  Id: string;
begin
  Session := FManager.CreateSession('Original Name');
  try
    Id := Session.Id;
    FManager.SaveSession(Session);
    Assert(FManager.RenameSession(Id, 'Renamed'), 'Rename should succeed');

    var Loaded := FManager.LoadSession(Id);
    Session := nil;
    try
      Assert(Loaded.Name = 'Renamed', 'Name should be updated');
    finally
      Loaded.Free;
    end;
  finally
    Session.Free;
  end;
end;

procedure TTestSessionManager.Test_AddUserMessage_Persisted;
var
  Session, Loaded: TSession;
begin
  Session := FManager.CreateSession('UserMsg Test');
  try
    Session.AddMessage(TUserMessage.Create('Test message content'));
    FManager.SaveSession(Session);

    Loaded := FManager.LoadSession(Session.Id);
    Session := nil;
    try
      Assert(Loaded.GetMessageCount = 1, 'Should have 1 message');
      Assert(Loaded.Messages[0].Role = mrUser, 'First message should be user');
      Assert(TUserMessage(Loaded.Messages[0]).Content = 'Test message content', 'Content should match');
    finally
      Loaded.Free;
    end;
  finally
    Session.Free;
  end;
end;

procedure TTestSessionManager.Test_AddAssistantMessage_Persisted;
var
  Session, Loaded: TSession;
  AsstMsg: TAssistantMessage;
begin
  Session := FManager.CreateSession('AsstMsg Test');
  try
    AsstMsg := TAssistantMessage.Create;
    AsstMsg.Content.Add(TTextContent.Create('Assistant reply'));
    AsstMsg.Model := 'test-model';
    AsstMsg.StopReason := srStop;
    Session.AddMessage(AsstMsg);
    FManager.SaveSession(Session);

    Loaded := FManager.LoadSession(Session.Id);
    Session := nil;
    try
      Assert(Loaded.GetMessageCount = 1, 'Should have 1 message');
      Assert(Loaded.Messages[0].Role = mrAssistant, 'Should be assistant');
      Assert(TAssistantMessage(Loaded.Messages[0]).Model = 'test-model', 'Model should match');
    finally
      Loaded.Free;
    end;
  finally
    Session.Free;
  end;
end;

procedure TTestSessionManager.Test_AddToolResultMessage_Persisted;
var
  Session, Loaded: TSession;
  Content: TContentBlockList;
begin
  Session := FManager.CreateSession('ToolResult Test');
  try
    Content := TContentBlockList.Create;
    Content.Add(TTextContent.Create('File contents here'));
    Session.AddMessage(TToolResultMessage.Create('call_1', 'read_file', Content, False));
    FManager.SaveSession(Session);

    Loaded := FManager.LoadSession(Session.Id);
    Session := nil;
    try
      Assert(Loaded.GetMessageCount = 1, 'Should have 1 message');
      Assert(Loaded.Messages[0].Role = mrToolResult, 'Should be tool result');
      Assert(TToolResultMessage(Loaded.Messages[0]).ToolCallId = 'call_1', 'ToolCallId should match');
      Assert(TToolResultMessage(Loaded.Messages[0]).ToolName = 'read_file', 'ToolName should match');
    finally
      Loaded.Free;
    end;
  finally
    Session.Free;
  end;
end;

procedure TTestSessionManager.Test_MultipleMessages_AppendWrite;
var
  Session, Loaded: TSession;
  i: Integer;
begin
  Session := FManager.CreateSession('Append Test');
  try
    Session.AddMessage(TUserMessage.Create('Msg 1'));
    FManager.SaveSession(Session);

    Session.AddMessage(TUserMessage.Create('Msg 2'));
    Session.AddMessage(TUserMessage.Create('Msg 3'));
    FManager.SaveSession(Session);

    Loaded := FManager.LoadSession(Session.Id);
    Session := nil;
    try
      Assert(Loaded.GetMessageCount = 3, 'Should have 3 messages, got ' + IntToStr(Loaded.GetMessageCount));
      for i := 0 to 2 do
        Assert(TUserMessage(Loaded.Messages[i]).Content = 'Msg ' + IntToStr(i + 1),
          'Message ' + IntToStr(i + 1) + ' content mismatch');
    finally
      Loaded.Free;
    end;
  finally
    Session.Free;
  end;
end;

procedure TTestSessionManager.Test_LargeSession_RoundTrip;
var
  Session, Loaded: TSession;
  i: Integer;
begin
  Session := FManager.CreateSession('Large Session');
  try
    for i := 1 to 50 do
    begin
      Session.AddMessage(TUserMessage.Create('User message ' + IntToStr(i)));
      var Asst := TAssistantMessage.Create;
      Asst.Content.Add(TTextContent.Create('Reply ' + IntToStr(i)));
      Session.AddMessage(Asst);
    end;
    FManager.SaveSession(Session);

    Loaded := FManager.LoadSession(Session.Id);
    Session := nil;
    try
      Assert(Loaded.GetMessageCount = 100, 'Should have 100 messages, got ' + IntToStr(Loaded.GetMessageCount));
    finally
      Loaded.Free;
    end;
  finally
    Session.Free;
  end;
end;

procedure TTestSessionManager.Test_BranchFrom;
var
  Session, Branch: TSession;
begin
  Session := FManager.CreateSession('Branch Source');
  try
    Session.AddMessage(TUserMessage.Create('Msg 1'));
    var A := TAssistantMessage.Create;
    A.Content.Add(TTextContent.Create('Reply 1'));
    Session.AddMessage(A);
    Session.AddMessage(TUserMessage.Create('Msg 2'));
    A := TAssistantMessage.Create;
    A.Content.Add(TTextContent.Create('Reply 2'));
    Session.AddMessage(A);

    Branch := Session.BranchFrom(1);
    try
      Assert(Branch <> nil, 'Branch should not be nil');
      Assert(Branch.ParentId = Session.Id, 'ParentId should be source session');
      Assert(Branch.BranchPoint = 1, 'BranchPoint should be 1');
      Assert(Branch.GetMessageCount = 2, 'Branch should have 2 messages');
    finally
      Branch.Free;
    end;
  finally
    Session.Free;
  end;
end;

procedure TTestSessionManager.Test_BranchPreservesSystemPrompt;
var
  Session, Branch: TSession;
begin
  Session := FManager.CreateSession('Branch Prompt Test');
  try
    Session.SystemPrompt := 'You are a helpful coding assistant.';
    Session.AddMessage(TUserMessage.Create('Hello'));

    Branch := Session.BranchFrom(0);
    try
      Assert(Branch.SystemPrompt = 'You are a helpful coding assistant.', 'SystemPrompt should be preserved');
    finally
      Branch.Free;
    end;
  finally
    Session.Free;
  end;
end;

procedure TTestSessionManager.Test_BranchPointCorrect;
var
  Session, Branch: TSession;
begin
  Session := FManager.CreateSession('BranchPoint Test');
  try
    Session.AddMessage(TUserMessage.Create('A'));
    Session.AddMessage(TUserMessage.Create('B'));
    Session.AddMessage(TUserMessage.Create('C'));
    Session.AddMessage(TUserMessage.Create('D'));

    Branch := Session.BranchFrom(2);
    try
      Assert(Branch.GetMessageCount = 3, 'Branch should have messages 0..2');
    finally
      Branch.Free;
    end;
  finally
    Session.Free;
  end;
end;

procedure TTestSessionManager.Test_DeleteCurrentSession;
var
  Session: TSession;
begin
  Session := FManager.CreateSession('Current Delete');
  try
    FManager.SetCurrentSession(Session);
    FManager.SaveSession(Session);
    FManager.DeleteSession(Session.Id);
    Session := nil;
    Assert(FManager.GetCurrentSession = nil, 'Current session should be nil after delete');
  finally
    Session.Free;
  end;
end;

procedure TTestSessionManager.Test_DeleteNonExistentSession;
begin
  FManager.DeleteSession('nonexistent_id_12345');
  Assert(True, 'DeleteNonExistent should not crash');
end;

procedure TTestSessionManager.Test_LoadNonExistentSession;
var
  Loaded: TSession;
begin
  Loaded := FManager.LoadSession('nonexistent_id_12345');
  Assert(Loaded = nil, 'LoadNonExistent should return nil');
end;

procedure TTestSessionManager.Test_EmptySession_RoundTrip;
var
  Session, Loaded: TSession;
begin
  Session := FManager.CreateSession('Empty');
  try
    FManager.SaveSession(Session);

    Loaded := FManager.LoadSession(Session.Id);
    Session := nil;
    try
      Assert(Loaded <> nil, 'Should load empty session');
      Assert(Loaded.GetMessageCount = 0, 'Empty session should have 0 messages');
    finally
      Loaded.Free;
    end;
  finally
    Session.Free;
  end;
end;

procedure TTestSessionManager.Test_SessionWithThinkingContent;
var
  Session, Loaded: TSession;
  Asst: TAssistantMessage;
begin
  Session := FManager.CreateSession('Thinking Test');
  try
    Asst := TAssistantMessage.Create;
    Asst.Content.Add(TThinkingContent.Create('Let me think about this...'));
    Asst.Content.Add(TTextContent.Create('Here is my answer.'));
    Session.AddMessage(Asst);
    FManager.SaveSession(Session);

    Loaded := FManager.LoadSession(Session.Id);
    Session := nil;
    try
      Assert(Loaded.GetMessageCount = 1, 'Should have 1 message');
      Assert(TAssistantMessage(Loaded.Messages[0]).Content.Count = 2, 'Should have 2 content blocks');
    finally
      Loaded.Free;
    end;
  finally
    Session.Free;
  end;
end;

procedure TTestSessionManager.Test_SessionWithToolCalls;
var
  Session, Loaded: TSession;
  Asst: TAssistantMessage;
  Calls: TArray<TToolCall>;
begin
  Session := FManager.CreateSession('ToolCall Test');
  try
    Asst := TAssistantMessage.Create;
    Asst.Content.Add(TTextContent.Create('Let me read that file.'));
    Asst.Content.Add(TToolCall.Create('call_1', 'read_file',
      TJSONObject.ParseJSONValue('{"path":"test.txt"}') as TJSONObject));
    Asst.StopReason := srToolUse;
    Session.AddMessage(Asst);
    FManager.SaveSession(Session);

    Loaded := FManager.LoadSession(Session.Id);
    Session := nil;
    try
      Assert(Loaded.GetMessageCount = 1, 'Should have 1 message');
      Calls := TAssistantMessage(Loaded.Messages[0]).Content.FindToolCalls;
      Assert(Length(Calls) = 1, 'Should have 1 tool call');
      Assert(Calls[0].Id = 'call_1', 'Tool call ID should match');
      Assert(Calls[0].Name = 'read_file', 'Tool call name should match');
    finally
      Loaded.Free;
    end;
  finally
    Session.Free;
  end;
end;

procedure TTestSessionManager.Test_SetAndGetCurrentSession;
var
  Session2: TSession;
  Id1: string;
begin
  // Create first session, save it, then create second
  var TempSession := FManager.CreateSession('Session 1');
  Id1 := TempSession.Id;
  FManager.SaveSession(TempSession);
  // TempSession freed internally by next CreateSession (FCurrentSession)

  Session2 := FManager.CreateSession('Session 2');
  FManager.SetCurrentSession(Session2);
  Assert(FManager.GetCurrentSession = Session2, 'Current should be Session 2');

  // Load first session and set as current
  var Loaded1 := FManager.LoadSession(Id1);
  Assert(Loaded1 <> nil, 'Should load session 1');
  FManager.SetCurrentSession(Loaded1);
  Assert(FManager.GetCurrentSession = Loaded1, 'Current should be Loaded1');
  Assert(FManager.GetCurrentSession.Name = 'Session 1', 'Name should be Session 1');
end;

procedure TTestSessionManager.Test_MixedMessageTypesRoundtrip;
var
  Session, Loaded: TSession;
  Asst: TAssistantMessage;
  Content: TContentBlockList;
begin
  Session := FManager.CreateSession('Mixed Messages');
  try
    Session.AddMessage(TUserMessage.Create('Hello'));

    Asst := TAssistantMessage.Create;
    Asst.Content.Add(TTextContent.Create('Hi there!'));
    Asst.Model := 'test-model';
    Session.AddMessage(Asst);

    Content := TContentBlockList.Create;
    Content.Add(TTextContent.Create('File contents'));
    Session.AddMessage(TToolResultMessage.Create('call_1', 'read_file', Content, False));

    FManager.SaveSession(Session);

    Loaded := FManager.LoadSession(Session.Id);
    Session := nil;
    try
      Assert(Loaded.GetMessageCount = 3, 'Should have 3 messages, got ' + IntToStr(Loaded.GetMessageCount));
      Assert(Loaded.Messages[0].Role = mrUser, 'First should be user');
      Assert(Loaded.Messages[1].Role = mrAssistant, 'Second should be assistant');
      Assert(Loaded.Messages[2].Role = mrToolResult, 'Third should be tool result');
      Assert(TUserMessage(Loaded.Messages[0]).Content = 'Hello', 'User content should match');
      Assert(TToolResultMessage(Loaded.Messages[2]).ToolCallId = 'call_1', 'ToolCallId should match');
    finally
      Loaded.Free;
    end;
  finally
    Session.Free;
  end;
end;

{ Registration }

procedure RegisterSessionManagerTests;
var
  T: TTestSessionManager;
begin
  T := TTestSessionManager.Create;
  try
    GRunner.RunTest('Session: Create session', T.Test_CreateSession, T.Setup, T.TearDown);
    GRunner.RunTest('Session: Create with custom name', T.Test_CreateSession_WithCustomName, T.Setup, T.TearDown);
    GRunner.RunTest('Session: Save and load', T.Test_SaveAndLoadSession, T.Setup, T.TearDown);
    GRunner.RunTest('Session: Delete', T.Test_DeleteSession, T.Setup, T.TearDown);
    GRunner.RunTest('Session: List sessions', T.Test_ListSessions, T.Setup, T.TearDown);
    GRunner.RunTest('Session: SessionExists', T.Test_SessionExists, T.Setup, T.TearDown);
    GRunner.RunTest('Session: Rename', T.Test_RenameSession, T.Setup, T.TearDown);
    GRunner.RunTest('Session: User message persisted', T.Test_AddUserMessage_Persisted, T.Setup, T.TearDown);
    GRunner.RunTest('Session: Assistant message persisted', T.Test_AddAssistantMessage_Persisted, T.Setup, T.TearDown);
    GRunner.RunTest('Session: ToolResult message persisted', T.Test_AddToolResultMessage_Persisted, T.Setup, T.TearDown);
    GRunner.RunTest('Session: Multiple messages append', T.Test_MultipleMessages_AppendWrite, T.Setup, T.TearDown);
    GRunner.RunTest('Session: Large session roundtrip (100 msgs)', T.Test_LargeSession_RoundTrip, T.Setup, T.TearDown);
    GRunner.RunTest('Session: Branch from index', T.Test_BranchFrom, T.Setup, T.TearDown);
    GRunner.RunTest('Session: Branch preserves SystemPrompt', T.Test_BranchPreservesSystemPrompt, T.Setup, T.TearDown);
    GRunner.RunTest('Session: Branch point correct', T.Test_BranchPointCorrect, T.Setup, T.TearDown);
    GRunner.RunTest('Session: Delete current session', T.Test_DeleteCurrentSession, T.Setup, T.TearDown);
    GRunner.RunTest('Session: Delete nonexistent', T.Test_DeleteNonExistentSession, T.Setup, T.TearDown);
    GRunner.RunTest('Session: Load nonexistent', T.Test_LoadNonExistentSession, T.Setup, T.TearDown);
    GRunner.RunTest('Session: Empty session roundtrip', T.Test_EmptySession_RoundTrip, T.Setup, T.TearDown);
    GRunner.RunTest('Session: Thinking content persisted', T.Test_SessionWithThinkingContent, T.Setup, T.TearDown);
    GRunner.RunTest('Session: Tool calls persisted', T.Test_SessionWithToolCalls, T.Setup, T.TearDown);
    GRunner.RunTest('Session: Set and get current session', T.Test_SetAndGetCurrentSession, T.Setup, T.TearDown);
    GRunner.RunTest('Session: Mixed message types roundtrip', T.Test_MixedMessageTypesRoundtrip, T.Setup, T.TearDown);
  finally
    T.Free;
  end;
end;

end.
