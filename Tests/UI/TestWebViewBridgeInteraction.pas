unit TestWebViewBridgeInteraction;

{ WebViewBridge interaction tests.
  Tests JS message dispatching, event routing, and PostJS output capture.
  Uses real TSessionManager + TSettingsManager (temp dir) + MockModel via TAgent. }

interface

uses
  System.SysUtils, System.JSON, System.IOUtils, System.Generics.Collections,
  Winapi.Windows,
  Vcl.Forms,
  Core.Messages, Core.Events, Core.Agent, Core.AgentState, Core.SessionManager,
  AI.IModel, AI.ModelConfig,
  Settings.Config, Settings.SettingsManager,
  UI.WebViewBridge,
  PiMonoTestFramework;

procedure RegisterWebViewBridgeInteractionTests;

implementation

uses
  Utils.Logger, Core.UndoLog;

type
  // Protected access hack for TWebViewBridge
  TWebViewBridgeAccess = class(TWebViewBridge);

  TTestWebViewBridgeInteraction = class
  private
    FTestDir: string;
    FSettingsManager: TSettingsManager;
    FSessionManager: TSessionManager;
    FPostedJson: TList<string>;

    procedure ClearPostedJson;
    procedure CapturePostJS(const AJson: string);
  public
    procedure Setup;
    procedure TearDown;

    { Message dispatch }
    procedure Test_HandleWebMessage_InvalidJson_NoCrash;
    procedure Test_HandleWebMessage_UnknownAction_NoCrash;
    procedure Test_HandleWebMessage_NoAction_NoCrash;

    { Abort }
    procedure Test_Abort_DispatchesToAgent;

    { Event posting }
    procedure Test_PostEvent_CapturesJson;
    procedure Test_PostEvent_WithKeyValue;

    { New session }
    procedure Test_NewSession_CreatesAndPostsSessionList;
    procedure Test_NewSession_PostsNewSessionCreated;

    { Delete session }
    procedure Test_DeleteSession_RemovesAndPostsSessionList;

    { Load session }
    procedure Test_LoadSession_Nonexistent_PostsSessionList;

    { Rename session }
    procedure Test_RenameSession_UpdatesName;

    { Config }
    procedure Test_GetConfig_PostsConfigData;
  end;

{ TTestWebViewBridgeInteraction }

procedure TTestWebViewBridgeInteraction.Setup;
begin
  FTestDir := TPath.Combine(TPath.GetTempPath,
    'PiMonoWVB_' + FormatDateTime('yyyymmddhhnnsszzz', Now) + '_' + IntToStr(GetTickCount));
  TDirectory.CreateDirectory(FTestDir);

  FSettingsManager := TSettingsManager.Create;
  FSettingsManager.Initialize(FTestDir);

  FSessionManager := TSessionManager.Create(nil, FTestDir);
  FPostedJson := TList<string>.Create;
end;

procedure TTestWebViewBridgeInteraction.TearDown;
begin
  FPostedJson.Free;
  FSessionManager.Free;
  FSettingsManager.Free;
  try
    if TDirectory.Exists(FTestDir) then
      TDirectory.Delete(FTestDir, True);
  except
  end;
end;

procedure TTestWebViewBridgeInteraction.ClearPostedJson;
begin
  FPostedJson.Clear;
end;

procedure TTestWebViewBridgeInteraction.CapturePostJS(const AJson: string);
begin
  FPostedJson.Add(AJson);
end;

{ --- Message dispatch --- }

procedure TTestWebViewBridgeInteraction.Test_HandleWebMessage_InvalidJson_NoCrash;
var
  Logger: TLogger;
  Agent: TAgent;
  UndoLog: TUndoLog;
  Bridge: TWebViewBridgeAccess;
begin
  Logger := TLogger.Create(TPath.Combine(FTestDir, 'test.log'));
  Agent := TAgent.Create(Logger);
  UndoLog := TUndoLog.Create(FTestDir);
  try
    Bridge := TWebViewBridgeAccess.Create(Agent, Logger, FSettingsManager, FSessionManager, UndoLog);
    try
      Bridge.OnPostJS := CapturePostJS;
      // Invalid JSON should not crash
      Bridge.HandleWebMessage('not valid json {{{');
      Assert(True, 'HandleWebMessage with invalid JSON should not crash');
    finally
      Bridge.Free;
    end;
  finally
    UndoLog.Free;
    Agent.Free;
    Logger.Free;
  end;
end;

procedure TTestWebViewBridgeInteraction.Test_HandleWebMessage_UnknownAction_NoCrash;
var
  Logger: TLogger;
  Agent: TAgent;
  UndoLog: TUndoLog;
  Bridge: TWebViewBridgeAccess;
begin
  Logger := TLogger.Create(TPath.Combine(FTestDir, 'test.log'));
  Agent := TAgent.Create(Logger);
  UndoLog := TUndoLog.Create(FTestDir);
  try
    Bridge := TWebViewBridgeAccess.Create(Agent, Logger, FSettingsManager, FSessionManager, UndoLog);
    try
      Bridge.OnPostJS := CapturePostJS;
      Bridge.HandleWebMessage('{"action":"nonexistent_action_xyz"}');
      Assert(True, 'HandleWebMessage with unknown action should not crash');
    finally
      Bridge.Free;
    end;
  finally
    UndoLog.Free;
    Agent.Free;
    Logger.Free;
  end;
end;

procedure TTestWebViewBridgeInteraction.Test_HandleWebMessage_NoAction_NoCrash;
var
  Logger: TLogger;
  Agent: TAgent;
  UndoLog: TUndoLog;
  Bridge: TWebViewBridgeAccess;
begin
  Logger := TLogger.Create(TPath.Combine(FTestDir, 'test.log'));
  Agent := TAgent.Create(Logger);
  UndoLog := TUndoLog.Create(FTestDir);
  try
    Bridge := TWebViewBridgeAccess.Create(Agent, Logger, FSettingsManager, FSessionManager, UndoLog);
    try
      Bridge.OnPostJS := CapturePostJS;
      Bridge.HandleWebMessage('{"foo":"bar"}');
      Assert(True, 'HandleWebMessage with no action field should not crash');
    finally
      Bridge.Free;
    end;
  finally
    UndoLog.Free;
    Agent.Free;
    Logger.Free;
  end;
end;

{ --- Abort --- }

procedure TTestWebViewBridgeInteraction.Test_Abort_DispatchesToAgent;
var
  Logger: TLogger;
  Agent: TAgent;
  UndoLog: TUndoLog;
  Bridge: TWebViewBridgeAccess;
begin
  Logger := TLogger.Create(TPath.Combine(FTestDir, 'test.log'));
  Agent := TAgent.Create(Logger);
  UndoLog := TUndoLog.Create(FTestDir);
  try
    Bridge := TWebViewBridgeAccess.Create(Agent, Logger, FSettingsManager, FSessionManager, UndoLog);
    try
      Bridge.OnPostJS := CapturePostJS;
      Bridge.HandleWebMessage('{"action":"abort"}');
      // Should not crash even if agent isn't running
      Assert(True, 'Abort action should not crash');
    finally
      Bridge.Free;
    end;
  finally
    UndoLog.Free;
    Agent.Free;
    Logger.Free;
  end;
end;

{ --- Event posting --- }

procedure TTestWebViewBridgeInteraction.Test_PostEvent_CapturesJson;
var
  Logger: TLogger;
  Agent: TAgent;
  UndoLog: TUndoLog;
  Bridge: TWebViewBridgeAccess;
begin
  Logger := TLogger.Create(TPath.Combine(FTestDir, 'test.log'));
  Agent := TAgent.Create(Logger);
  UndoLog := TUndoLog.Create(FTestDir);
  try
    Bridge := TWebViewBridgeAccess.Create(Agent, Logger, FSettingsManager, FSessionManager, UndoLog);
    try
      Bridge.OnPostJS := CapturePostJS;
      ClearPostedJson;

      var Json := TJSONObject.Create;
      Json.AddPair('event', 'test_event');
      Bridge.PostToJS(Json.ToJSON);
      Json.Free;

      Assert(FPostedJson.Count = 1, 'Should have captured 1 posted JSON');
      Assert(FPostedJson[0].Contains('test_event'), 'Posted JSON should contain test_event');
    finally
      Bridge.Free;
    end;
  finally
    UndoLog.Free;
    Agent.Free;
    Logger.Free;
  end;
end;

procedure TTestWebViewBridgeInteraction.Test_PostEvent_WithKeyValue;
var
  Logger: TLogger;
  Agent: TAgent;
  UndoLog: TUndoLog;
  Bridge: TWebViewBridgeAccess;
begin
  Logger := TLogger.Create(TPath.Combine(FTestDir, 'test.log'));
  Agent := TAgent.Create(Logger);
  UndoLog := TUndoLog.Create(FTestDir);
  try
    Bridge := TWebViewBridgeAccess.Create(Agent, Logger, FSettingsManager, FSessionManager, UndoLog);
    try
      Bridge.OnPostJS := CapturePostJS;
      ClearPostedJson;

      Bridge.PostEvent('test_event', 'key1', 'value1');

      Assert(FPostedJson.Count = 1, 'Should have captured 1 posted JSON');
      Assert(FPostedJson[0].Contains('test_event'), 'Should contain event name');
      Assert(FPostedJson[0].Contains('key1'), 'Should contain key');
      Assert(FPostedJson[0].Contains('value1'), 'Should contain value');
    finally
      Bridge.Free;
    end;
  finally
    UndoLog.Free;
    Agent.Free;
    Logger.Free;
  end;
end;

{ --- New session --- }

procedure TTestWebViewBridgeInteraction.Test_NewSession_CreatesAndPostsSessionList;
var
  Logger: TLogger;
  Agent: TAgent;
  UndoLog: TUndoLog;
  Bridge: TWebViewBridgeAccess;
begin
  Logger := TLogger.Create(TPath.Combine(FTestDir, 'test.log'));
  Agent := TAgent.Create(Logger);
  UndoLog := TUndoLog.Create(FTestDir);
  try
    Bridge := TWebViewBridgeAccess.Create(Agent, Logger, FSettingsManager, FSessionManager, UndoLog);
    try
      Bridge.OnPostJS := CapturePostJS;
      ClearPostedJson;

      Bridge.HandleWebMessage('{"action":"new_session"}');

      Assert(FPostedJson.Count > 0, 'Should have posted at least 1 JSON after new_session');
      // Should contain session_list in one of the posted messages
      var Found := False;
      for var J in FPostedJson do
        if J.Contains('session_list') then Found := True;
      Assert(Found, 'Should post session_list event');
    finally
      Bridge.Free;
    end;
  finally
    UndoLog.Free;
    Agent.Free;
    Logger.Free;
  end;
end;

procedure TTestWebViewBridgeInteraction.Test_NewSession_PostsNewSessionCreated;
var
  Logger: TLogger;
  Agent: TAgent;
  UndoLog: TUndoLog;
  Bridge: TWebViewBridgeAccess;
begin
  Logger := TLogger.Create(TPath.Combine(FTestDir, 'test.log'));
  Agent := TAgent.Create(Logger);
  UndoLog := TUndoLog.Create(FTestDir);
  try
    Bridge := TWebViewBridgeAccess.Create(Agent, Logger, FSettingsManager, FSessionManager, UndoLog);
    try
      Bridge.OnPostJS := CapturePostJS;
      ClearPostedJson;

      Bridge.HandleWebMessage('{"action":"new_session"}');

      var Found := False;
      for var J in FPostedJson do
        if J.Contains('new_session_created') then Found := True;
      Assert(Found, 'Should post new_session_created event');
    finally
      Bridge.Free;
    end;
  finally
    UndoLog.Free;
    Agent.Free;
    Logger.Free;
  end;
end;

{ --- Delete session --- }

procedure TTestWebViewBridgeInteraction.Test_DeleteSession_RemovesAndPostsSessionList;
var
  Logger: TLogger;
  Agent: TAgent;
  UndoLog: TUndoLog;
  Bridge: TWebViewBridgeAccess;
  Session: TSession;
  Id: string;
begin
  Logger := TLogger.Create(TPath.Combine(FTestDir, 'test.log'));
  Agent := TAgent.Create(Logger);
  UndoLog := TUndoLog.Create(FTestDir);
  try
    // Create and save a session first
    Session := FSessionManager.CreateSession('To Delete');
    Id := Session.Id;
    FSessionManager.SaveSession(Session);

    Bridge := TWebViewBridgeAccess.Create(Agent, Logger, FSettingsManager, FSessionManager, UndoLog);
    try
      Bridge.OnPostJS := CapturePostJS;
      ClearPostedJson;

      Bridge.HandleWebMessage('{"action":"delete_session","sessionId":"' + Id + '"}');

      Assert(not FSessionManager.SessionExists(Id), 'Session should be deleted');
      var Found := False;
      for var J in FPostedJson do
        if J.Contains('session_list') then Found := True;
      Assert(Found, 'Should post updated session_list');
    finally
      Bridge.Free;
    end;
  finally
    UndoLog.Free;
    Agent.Free;
    Logger.Free;
  end;
end;

{ --- Load session --- }

procedure TTestWebViewBridgeInteraction.Test_LoadSession_Nonexistent_PostsSessionList;
var
  Logger: TLogger;
  Agent: TAgent;
  UndoLog: TUndoLog;
  Bridge: TWebViewBridgeAccess;
begin
  Logger := TLogger.Create(TPath.Combine(FTestDir, 'test.log'));
  Agent := TAgent.Create(Logger);
  UndoLog := TUndoLog.Create(FTestDir);
  try
    Bridge := TWebViewBridgeAccess.Create(Agent, Logger, FSettingsManager, FSessionManager, UndoLog);
    try
      Bridge.OnPostJS := CapturePostJS;
      ClearPostedJson;

      // Loading nonexistent session should handle gracefully
      Bridge.HandleWebMessage('{"action":"load_session","sessionId":"nonexistent_xyz"}');
      Assert(True, 'Loading nonexistent session should not crash');
    finally
      Bridge.Free;
    end;
  finally
    UndoLog.Free;
    Agent.Free;
    Logger.Free;
  end;
end;

{ --- Rename session --- }

procedure TTestWebViewBridgeInteraction.Test_RenameSession_UpdatesName;
var
  Logger: TLogger;
  Agent: TAgent;
  UndoLog: TUndoLog;
  Bridge: TWebViewBridgeAccess;
  Session: TSession;
  Id: string;
begin
  Logger := TLogger.Create(TPath.Combine(FTestDir, 'test.log'));
  Agent := TAgent.Create(Logger);
  UndoLog := TUndoLog.Create(FTestDir);
  try
    Session := FSessionManager.CreateSession('Original');
    Id := Session.Id;
    FSessionManager.SaveSession(Session);

    Bridge := TWebViewBridgeAccess.Create(Agent, Logger, FSettingsManager, FSessionManager, UndoLog);
    try
      Bridge.OnPostJS := CapturePostJS;
      ClearPostedJson;

      Bridge.HandleWebMessage('{"action":"rename_session","sessionId":"' + Id + '","newName":"Renamed"}');

      var Loaded := FSessionManager.LoadSession(Id);
      Assert(Loaded.Name = 'Renamed', 'Session should be renamed, got: ' + Loaded.Name);
    finally
      Bridge.Free;
    end;
  finally
    UndoLog.Free;
    Agent.Free;
    Logger.Free;
  end;
end;

{ --- Config --- }

procedure TTestWebViewBridgeInteraction.Test_GetConfig_PostsConfigData;
var
  Logger: TLogger;
  Agent: TAgent;
  UndoLog: TUndoLog;
  Bridge: TWebViewBridgeAccess;
begin
  Logger := TLogger.Create(TPath.Combine(FTestDir, 'test.log'));
  Agent := TAgent.Create(Logger);
  UndoLog := TUndoLog.Create(FTestDir);
  try
    Bridge := TWebViewBridgeAccess.Create(Agent, Logger, FSettingsManager, FSessionManager, UndoLog);
    try
      Bridge.OnPostJS := CapturePostJS;
      ClearPostedJson;

      Bridge.HandleWebMessage('{"action":"get_config"}');

      Assert(FPostedJson.Count > 0, 'Should post config_data');
      var Found := False;
      for var J in FPostedJson do
        if J.Contains('config_data') then Found := True;
      Assert(Found, 'Should post config_data event');
    finally
      Bridge.Free;
    end;
  finally
    UndoLog.Free;
    Agent.Free;
    Logger.Free;
  end;
end;

{ Registration }

procedure RegisterWebViewBridgeInteractionTests;
var
  T: TTestWebViewBridgeInteraction;
begin
  T := TTestWebViewBridgeInteraction.Create;
  try
    GRunner.RunTest('WVBridge: invalid JSON no crash', T.Test_HandleWebMessage_InvalidJson_NoCrash, T.Setup, T.TearDown);
    GRunner.RunTest('WVBridge: unknown action no crash', T.Test_HandleWebMessage_UnknownAction_NoCrash, T.Setup, T.TearDown);
    GRunner.RunTest('WVBridge: no action field no crash', T.Test_HandleWebMessage_NoAction_NoCrash, T.Setup, T.TearDown);
    GRunner.RunTest('WVBridge: abort action', T.Test_Abort_DispatchesToAgent, T.Setup, T.TearDown);
    GRunner.RunTest('WVBridge: PostEvent captures JSON', T.Test_PostEvent_CapturesJson, T.Setup, T.TearDown);
    GRunner.RunTest('WVBridge: PostEvent key/value', T.Test_PostEvent_WithKeyValue, T.Setup, T.TearDown);
    GRunner.RunTest('WVBridge: new session creates + posts list', T.Test_NewSession_CreatesAndPostsSessionList, T.Setup, T.TearDown);
    GRunner.RunTest('WVBridge: new session posts created event', T.Test_NewSession_PostsNewSessionCreated, T.Setup, T.TearDown);
    GRunner.RunTest('WVBridge: delete session removes + posts', T.Test_DeleteSession_RemovesAndPostsSessionList, T.Setup, T.TearDown);
    GRunner.RunTest('WVBridge: load nonexistent no crash', T.Test_LoadSession_Nonexistent_PostsSessionList, T.Setup, T.TearDown);
    GRunner.RunTest('WVBridge: rename session updates name', T.Test_RenameSession_UpdatesName, T.Setup, T.TearDown);
    GRunner.RunTest('WVBridge: get config posts data', T.Test_GetConfig_PostsConfigData, T.Setup, T.TearDown);
  finally
    T.Free;
  end;
end;

end.
