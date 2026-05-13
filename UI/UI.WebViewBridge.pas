unit UI.WebViewBridge;

{ Central message routing between WebView2 JS frontend and Delphi backend.
  Replaces TAgentEventBridge + TChatRenderer + TSettingsForm.

  Communication:
    JS -> Delphi:  window.chrome.webview.postMessage(json) -> HandleWebMessage
    Delphi -> JS:  PostToJS(json) -> window.chrome.webview message event
}

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.StrUtils, System.IOUtils,
  System.Generics.Collections,
  Vcl.Dialogs, Vcl.Forms,
  Core.Messages, Core.Events, Core.Agent, Core.AgentState,
  Core.SessionManager, Core.UndoLog,
  AI.IModel, AI.CustomAPIAdapter, AI.ModelConfig,
  Settings.Config, Settings.SettingsManager, Settings.SkillStore,
  Tools.FileTools, Tools.ToolRegistry, Tools.ITool, Tools.BashTool, Tools.GitTool,
  Utils.Logger, Utils.Localization,
  App.Main;

type
  TPostJSEvent = procedure(const AJson: string) of object;
  TExecuteScriptEvent = procedure(const AScript: string) of object;
  TNotifyPopupEvent = procedure(const ASessionId: string) of object;
  TWebActionHandler = reference to procedure(AJson: TJSONObject);

  TWebViewBridge = class
  private
    FAgent: TAgent;
    FLogger: TLogger;
    FSettingsManager: TSettingsManager;
    FSessionManager: TSessionManager;
    FUndoLog: TUndoLog;
    FSubscriptionId: Integer;
    FDestroying: Boolean;
    FOnPostJS: TPostJSEvent;  // callback to post JSON to WebView
    FOnExecuteScript: TExecuteScriptEvent;  // callback to run JS directly
    FOnOpenPopup: TNotifyPopupEvent;  // callback to open popup window
    FActionHandlers: TDictionary<string, TWebActionHandler>;

    // Session override for popup windows (bypasses FSessionManager.GetCurrentSession)
    FSessionOverride: TSession;

    // Pending tool confirmation
    FPendingConfirmCallId: string;

    function GetActiveSession: TSession;

    // --- JS -> Delphi handlers ---
    procedure HandleSendMessage(AJson: TJSONObject);
    procedure HandleNewSession(AJson: TJSONObject);
    procedure HandleLoadSession(AJson: TJSONObject);
    procedure HandleDeleteSession(AJson: TJSONObject);
    procedure HandleRenameSession(AJson: TJSONObject);
    procedure HandleAbort(AJson: TJSONObject);
    procedure HandleGetConfig(AJson: TJSONObject);
    procedure HandleSaveSettings(AJson: TJSONObject);
    procedure HandleConfirmTool(AJson: TJSONObject);
    procedure HandleExportSession(AJson: TJSONObject);
    procedure HandleBranchSession(AJson: TJSONObject);
    procedure HandleUndo(AJson: TJSONObject);
    procedure HandleChangeModel(AJson: TJSONObject);
    procedure HandleBrowseDirectory(AJson: TJSONObject);
    procedure HandleOpenSessionPopup(AJson: TJSONObject);
    procedure HandleTestConnection(AJson: TJSONObject);
    procedure HandleSaveOnboarding(AJson: TJSONObject);
    procedure HandleUpdateProfiles(AJson: TJSONObject);
    procedure HandleUpdateSkills(AJson: TJSONObject);

    // --- Agent event handler (replaces TAgentEventBridge) ---
    procedure OnAgentEvent(AEvent: TAgentEvent);
    procedure HandleAgentStart;
    procedure HandleAgentEnd(AEvent: TAgentEndEvent);
    procedure HandleMessageEnd(AEvent: TMessageEndEvent);
    procedure HandleToolStart(AEvent: TToolExecutionStartEvent);
    procedure HandleToolEnd(AEvent: TToolExecutionEndEvent);
    procedure HandleToolConfirm(AEvent: TToolConfirmationRequestEvent);

    // --- Serialization ---
    function SerializeSessionList: string;
    function SerializeMessage(AMessage: TAgentMessage): TJSONObject;
    function SerializeConfig: string;
    function SerializeThemeColors: string;
    function SerializeProfiles: TJSONArray;
    function SerializeSkills: TJSONArray;
    function BuildLocalizationJson: string;

    // --- Posting helpers (protected for testability) ---
    procedure RegisterActionHandlers;
  protected
    procedure PostToJS(const AJson: string);
    procedure PostEvent(const AEventName: string; AData: TJSONObject = nil); overload;
    procedure PostEvent(const AEventName, AKey, AValue: string); overload;
  public
    constructor Create(AAgent: TAgent; ALogger: TLogger;
      ASettingsManager: TSettingsManager; ASessionManager: TSessionManager;
      AUndoLog: TUndoLog);
    destructor Destroy; override;

    procedure Subscribe;
    procedure Unsubscribe;

    /// Called by MainForm when a web message arrives from JS
    procedure HandleWebMessage(const AMessage: string);

    /// Called by Forms to process raw WebView2 WebMessageAsJson (unwraps JSON string, handles page_ready)
    procedure HandleRawWebMessage(const ARawJson: string);

    /// Called by MainForm after browser is ready, sends all initial state
    procedure SendInitialState;

    /// Set the callback that posts JSON into the WebView
    property OnPostJS: TPostJSEvent read FOnPostJS write FOnPostJS;
    /// Set the callback that executes JS directly in the WebView
    property OnExecuteScript: TExecuteScriptEvent read FOnExecuteScript write FOnExecuteScript;
    /// Set the callback to open a popup window (called from main form)
    property OnOpenPopup: TNotifyPopupEvent read FOnOpenPopup write FOnOpenPopup;
    /// Override session for popup windows (bypasses FSessionManager.GetCurrentSession)
    property SessionOverride: TSession read FSessionOverride write FSessionOverride;
    property Destroying: Boolean read FDestroying write FDestroying;
  end;

implementation

{ TWebViewBridge }

constructor TWebViewBridge.Create(AAgent: TAgent; ALogger: TLogger;
  ASettingsManager: TSettingsManager; ASessionManager: TSessionManager;
  AUndoLog: TUndoLog);
begin
  inherited Create;
  FAgent := AAgent;
  FLogger := ALogger;
  FSettingsManager := ASettingsManager;
  FSessionManager := ASessionManager;
  FUndoLog := AUndoLog;
  FSubscriptionId := -1;
  FDestroying := False;
  FOnPostJS := nil;
  FOnOpenPopup := nil;
  FSessionOverride := nil;
  FPendingConfirmCallId := '';
  FActionHandlers := TDictionary<string, TWebActionHandler>.Create;
  RegisterActionHandlers;
end;

function TWebViewBridge.GetActiveSession: TSession;
begin
  if FSessionOverride <> nil then
    Result := FSessionOverride
  else
    Result := FSessionManager.GetCurrentSession;
end;

destructor TWebViewBridge.Destroy;
begin
  Unsubscribe;
  FActionHandlers.Free;
  inherited;
end;

procedure TWebViewBridge.Subscribe;
begin
  if FSubscriptionId < 0 then
    FSubscriptionId := FAgent.Subscribe(OnAgentEvent);
end;

procedure TWebViewBridge.Unsubscribe;
begin
  if FSubscriptionId >= 0 then
  begin
    FAgent.Unsubscribe(FSubscriptionId);
    FSubscriptionId := -1;
  end;
end;

{ ---- Raw WebView2 Message Processing ---- }

procedure TWebViewBridge.HandleRawWebMessage(const ARawJson: string);
var
  Msg: string;
begin
  Msg := ARawJson;
  if Msg = '' then Exit;

  // WebMessageAsJson returns the message as a JSON-encoded string.
  // For a string message, it looks like: "{\"action\":\"page_ready\"}"
  // We need to parse it as a JSON string first to unescape it.
  if (Length(Msg) > 1) and (Msg[1] = '"') then
  begin
    var Parsed := TJSONObject.ParseJSONValue(Msg);
    if Parsed <> nil then
    try
      Msg := Parsed.Value;
    finally
      Parsed.Free;
    end
    else
    begin
      if Assigned(FLogger) then
        FLogger.Warn('HandleRawWebMessage: failed to parse outer JSON string');
      Exit;
    end;
  end;

  // Parse the inner JSON
  try
    var Json := TJSONObject.ParseJSONValue(Msg) as TJSONObject;
    if Json <> nil then
    try
      var Action: string;
      if Json.TryGetValue<string>('action', Action) then
      begin
        if Action = 'page_ready' then
        begin
          SendInitialState;
          Exit;
        end;
        HandleWebMessage(Msg);
      end;
    finally
      Json.Free;
    end;
  except
    on E: Exception do
      if Assigned(FLogger) then
        FLogger.Error('HandleRawWebMessage: parse error: ' + E.Message);
  end;
end;

{ ---- Posting Helpers ---- }

procedure TWebViewBridge.PostToJS(const AJson: string);
begin
  if Assigned(FOnPostJS) and not FDestroying then
    FOnPostJS(AJson);
end;

procedure TWebViewBridge.PostEvent(const AEventName: string; AData: TJSONObject);
{ Posts an event to the WebView JS frontend.
  AData ownership is TAKEN by this method — it will be freed after posting.
  Pass nil to create an empty payload. }
begin
  if AData = nil then
    AData := TJSONObject.Create;
  AData.AddPair('event', AEventName);
  PostToJS(AData.ToJSON);
  AData.Free;
end;

procedure TWebViewBridge.PostEvent(const AEventName, AKey, AValue: string);
var
  Json: TJSONObject;
begin
  Json := TJSONObject.Create;
  Json.AddPair('event', AEventName);
  Json.AddPair(AKey, AValue);
  PostToJS(Json.ToJSON);
  Json.Free;
end;

{ ---- JS -> Delphi Message Dispatch ---- }

procedure TWebViewBridge.RegisterActionHandlers;
begin
  FActionHandlers.Add('send_message', HandleSendMessage);
  FActionHandlers.Add('new_session', HandleNewSession);
  FActionHandlers.Add('load_session', HandleLoadSession);
  FActionHandlers.Add('delete_session', HandleDeleteSession);
  FActionHandlers.Add('rename_session', HandleRenameSession);
  FActionHandlers.Add('abort', HandleAbort);
  FActionHandlers.Add('get_config', HandleGetConfig);
  FActionHandlers.Add('save_settings', HandleSaveSettings);
  FActionHandlers.Add('confirm_tool', HandleConfirmTool);
  FActionHandlers.Add('export_session', HandleExportSession);
  FActionHandlers.Add('branch_session', HandleBranchSession);
  FActionHandlers.Add('undo', HandleUndo);
  FActionHandlers.Add('change_model', HandleChangeModel);
  FActionHandlers.Add('browse_directory', HandleBrowseDirectory);
  FActionHandlers.Add('open_session_popup', HandleOpenSessionPopup);
  FActionHandlers.Add('test_connection', HandleTestConnection);
  FActionHandlers.Add('save_onboarding', HandleSaveOnboarding);
  FActionHandlers.Add('update_profiles', HandleUpdateProfiles);
  FActionHandlers.Add('update_skills', HandleUpdateSkills);
end;

procedure TWebViewBridge.HandleWebMessage(const AMessage: string);
var
  Json: TJSONObject;
  Action: string;
  Handler: TWebActionHandler;
begin
  Json := TJSONObject.ParseJSONValue(AMessage) as TJSONObject;
  if Json = nil then Exit;
  try
    if not Json.TryGetValue<string>('action', Action) then Exit;
    FLogger.Info('WebViewBridge: JS action=' + Action);

    try
      if FActionHandlers.TryGetValue(Action, Handler) then
        Handler(Json)
      else
        FLogger.Warn('WebViewBridge: unknown action: ' + Action);
    except
      on E: Exception do
      begin
        FLogger.Error('WebViewBridge: Handler FAILED for action=' + Action + ': ' + E.Message);
      end;
    end;
  finally
    Json.Free;
  end;
end;

{ ---- JS Action Handlers ---- }

procedure TWebViewBridge.HandleSendMessage(AJson: TJSONObject);
var
  Content: string;
  Config: TPiMonoConfig;
  Profile: TModelProfile;
  ErrorMsg: string;
  ImagesArr: TJSONArray;
  Blocks: TContentBlockList;
  Msg: TUserMessage;
begin
  if not AJson.TryGetValue<string>('content', Content) then Exit;

  // Check if there are images attached
  ImagesArr := AJson.FindValue('images') as TJSONArray;
  if (Content.Trim = '') and ((ImagesArr = nil) or (ImagesArr.Count = 0)) then Exit;

  // Pre-flight validation: check API configuration
  Config := FSettingsManager.Config;
  Profile := Config.GetActiveProfile;

  if Profile.ApiKey = '' then
    ErrorMsg := L('error.noApiKey')
  else if Profile.Endpoint = '' then
    ErrorMsg := L('error.noEndpoint')
  else if Profile.ModelName = '' then
    ErrorMsg := L('error.noModel');

  if ErrorMsg <> '' then
  begin
    FLogger.Warn('HandleSendMessage: validation failed: ' + ErrorMsg);
    var Json := TJSONObject.Create;
    Json.AddPair('event', 'agent_error');
    Json.AddPair('message', ErrorMsg);
    PostToJS(Json.ToJSON);
    Json.Free;
    Exit;
  end;

  // If images are present, create structured message with content blocks
  if (ImagesArr <> nil) and (ImagesArr.Count > 0) then
  begin
    Blocks := TContentBlockList.Create;
    try
      // Add text block first
      if Content.Trim <> '' then
        Blocks.Add(TTextContent.Create(Content));

      // Add image blocks
      for var i := 0 to ImagesArr.Count - 1 do
      begin
        var DataUrl := ImagesArr.Items[i].Value;
        // Parse data URL: data:image/png;base64,<data>
        var MimeStr := 'image/png';
        var Base64Data := DataUrl;
        var SepPos := DataUrl.IndexOf(';base64,');
        if SepPos > 0 then
        begin
          MimeStr := DataUrl.Substring(5, SepPos - 5); // skip "data:"
          Base64Data := DataUrl.Substring(SepPos + 8);  // skip ";base64,"
        end;
        Blocks.Add(TImageContent.Create(Base64Data, MimeStr));
      end;

      Msg := TUserMessage.Create(Blocks);
      try
        FAgent.Prompt(Msg);
      finally
        Msg.Free;
      end;
    finally
      Blocks.Free;
    end;
  end
  else
  begin
    // Plain text message
    FAgent.Prompt(Content);
  end;
end;

procedure TWebViewBridge.HandleNewSession(AJson: TJSONObject);
var
  Session: TSession;
begin
  Session := FSessionManager.CreateSession(
    L('session.prefix') + FormatDateTime('yyyy-mm-dd hh:nn', Now));
  FAgent.Reset;
  FSessionManager.SetCurrentSession(Session);
  PostToJS(SerializeSessionList);
  // Send updated session list and clear chat
  var Json := TJSONObject.Create;
  Json.AddPair('event', 'new_session_created');
  Json.AddPair('sessionId', Session.Id);
  Json.AddPair('sessionName', Session.Name);
  PostToJS(Json.ToJSON);
  Json.Free;
end;

procedure TWebViewBridge.HandleLoadSession(AJson: TJSONObject);
var
  SessionId: string;
  Session: TSession;
  OldSession: TSession;
  i: Integer;
begin
  if not AJson.TryGetValue<string>('sessionId', SessionId) then Exit;

  // Save current session before switching (sync agent messages to session)
  OldSession := GetActiveSession;
  if (OldSession <> nil) and (FAgent.GetState.Messages.Count > 0) then
  begin
    OldSession.Messages.Clear;
    for i := 0 to FAgent.GetState.Messages.Count - 1 do
      OldSession.Messages.Add(FAgent.GetState.Messages[i].Clone);
    FSessionManager.SaveSession(OldSession);
    FLogger.Info('HandleLoadSession: saved previous session ' + OldSession.Id +
      ' with ' + IntToStr(OldSession.Messages.Count) + ' messages');
  end;

  Session := FSessionManager.LoadSession(SessionId);
  if Session = nil then Exit;
  FSessionManager.SetCurrentSession(Session);

  // Reset agent and replay messages (clone to avoid shared ownership with session)
  FAgent.Reset;
  for i := 0 to Session.Messages.Count - 1 do
    FAgent.AppendMessage(Session.Messages[i].Clone);

  // Send session data to JS
  var Json := TJSONObject.Create;
  Json.AddPair('event', 'session_loaded');
  Json.AddPair('sessionId', Session.Id);
  Json.AddPair('sessionName', Session.Name);

  var MsgArr := TJSONArray.Create;
  for i := 0 to Session.Messages.Count - 1 do
    MsgArr.AddElement(SerializeMessage(Session.Messages[i]));
  Json.AddPair('messages', MsgArr);

  PostToJS(Json.ToJSON);
  Json.Free;
end;

procedure TWebViewBridge.HandleDeleteSession(AJson: TJSONObject);
var
  SessionId: string;
begin
  if not AJson.TryGetValue<string>('sessionId', SessionId) then Exit;
  FSessionManager.DeleteSession(SessionId);
  // Send updated session list
  PostToJS(SerializeSessionList);
end;

procedure TWebViewBridge.HandleRenameSession(AJson: TJSONObject);
var
  SessionId, NewName: string;
begin
  if not AJson.TryGetValue<string>('sessionId', SessionId) then Exit;
  if not AJson.TryGetValue<string>('newName', NewName) then Exit;
  FSessionManager.RenameSession(SessionId, NewName);
  PostToJS(SerializeSessionList);
end;

procedure TWebViewBridge.HandleAbort(AJson: TJSONObject);
begin
  FAgent.Abort;
  FPendingConfirmCallId := '';
end;

procedure TWebViewBridge.HandleGetConfig(AJson: TJSONObject);
begin
  PostToJS(SerializeConfig);
end;

procedure TWebViewBridge.HandleSaveSettings(AJson: TJSONObject);
var
  SettingsObj: TJSONObject;
  Config: TPiMonoConfig;
begin
  SettingsObj := AJson.FindValue('settings') as TJSONObject;
  if SettingsObj = nil then
    Exit;

  Config := FSettingsManager.Config;

  // API
  var Val: string;
  var IntVal: Integer;
  var DblVal: Double;
  var BoolVal: Boolean;

  if SettingsObj.TryGetValue<string>('apiEndpoint', Val) then
    FSettingsManager.UpdateApiEndpoint(Val);
  if SettingsObj.TryGetValue<string>('apiKey', Val) then
    FSettingsManager.UpdateApiKey(Val);
  if SettingsObj.TryGetValue<string>('modelsEndpoint', Val) then
    FSettingsManager.UpdateModelsEndpoint(Val);
  if SettingsObj.TryGetValue<Boolean>('streaming', BoolVal) then
    FSettingsManager.UpdateStreaming(BoolVal);
  if SettingsObj.TryGetValue<Integer>('timeout', IntVal) then
    FSettingsManager.UpdateTimeout(IntVal);
  if SettingsObj.TryGetValue<Integer>('retryCount', IntVal) then
    FSettingsManager.UpdateRetryCount(IntVal);

  // Model
  if SettingsObj.TryGetValue<string>('modelName', Val) then
    FSettingsManager.UpdateModelName(Val);
  if SettingsObj.TryGetValue<Integer>('maxTokens', IntVal) then
    FSettingsManager.UpdateMaxTokens(IntVal);
  if SettingsObj.TryGetValue<Double>('temperature', DblVal) then
    FSettingsManager.UpdateTemperature(DblVal);
  if SettingsObj.TryGetValue<Double>('topP', DblVal) then
    FSettingsManager.UpdateTopP(DblVal);
  if SettingsObj.TryGetValue<string>('thinkingLevel', Val) then
    FSettingsManager.UpdateThinkingLevel(StringToThinkingLevel(Val));

  // UI
  if SettingsObj.TryGetValue<string>('theme', Val) then
    FSettingsManager.UpdateTheme(Val);
  if SettingsObj.TryGetValue<Integer>('fontSize', IntVal) then
    FSettingsManager.UpdateFontSize(IntVal);
  if SettingsObj.TryGetValue<string>('fontFamily', Val) then
    FSettingsManager.UpdateFontFamily(Val);
  if SettingsObj.TryGetValue<string>('language', Val) then
  begin
    FSettingsManager.UpdateLanguage(Val);
    SetLanguage(LangFromCode(Val));  // switch runtime language for localization
  end;

  // Paths
  if SettingsObj.TryGetValue<string>('workingDir', Val) then
    FSettingsManager.UpdateWorkingDirectory(Val);
  if SettingsObj.TryGetValue<string>('backupDir', Val) then
    FSettingsManager.UpdateBackupDirectory(Val);

  FSettingsManager.SaveGlobal;

  // Update agent runtime from active profile (TopP, ThinkingLevel, etc.)
  var ActiveProfile := FSettingsManager.Config.GetActiveProfile;
  var AgentModelConfig := TModelConfig.GetDefault;
  AgentModelConfig.Name := ActiveProfile.ModelName;
  AgentModelConfig.MaxTokens := ActiveProfile.MaxTokens;
  AgentModelConfig.Temperature := ActiveProfile.Temperature;
  AgentModelConfig.TopP := ActiveProfile.TopP;
  FAgent.SetModel(AgentModelConfig);
  FAgent.SetThinkingLevel(ActiveProfile.ThinkingLevel);

  FLogger.Info('HandleSaveSettings: saved. theme=' + FSettingsManager.Config.UI.Theme +
    ' lang=' + FSettingsManager.Config.UI.Language);

  PostEvent('settings_saved');

  // Re-apply runtime changes: theme colors and localization
  PostToJS(SerializeThemeColors);
  PostToJS(BuildLocalizationJson);

  // Use ExecuteScript to apply theme via themeManager
  var ThemeVal := FSettingsManager.Config.UI.Theme;
  FLogger.Info('HandleSaveSettings: ExecuteScript setting theme=' + ThemeVal);
  if Assigned(FOnExecuteScript) then
    FOnExecuteScript('if(typeof themeManager!=="undefined")themeManager.apply("' + ThemeVal + '")');

  // Send targeted updates (profiles, fonts, model) — NOT full SendInitialState
  // which would reload all sessions/messages and trigger onboarding
  var ApplyJson := TJSONObject.Create;
  try
    ApplyJson.AddPair('event', 'settings_applied');
    ApplyJson.AddPair('theme', ThemeVal);
    ApplyJson.AddPair('language', FSettingsManager.Config.UI.Language);
    ApplyJson.AddPair('fontSize', TJSONNumber.Create(FSettingsManager.Config.UI.FontSize));
    ApplyJson.AddPair('fontFamily', FSettingsManager.Config.UI.FontFamily);
    ApplyJson.AddPair('activeModelName', FSettingsManager.Config.GetActiveProfile.DisplayName);
    ApplyJson.AddPair('activeModelId', FSettingsManager.Config.ActiveModelId);
    ApplyJson.AddPair('profiles', SerializeProfiles);
    PostToJS(ApplyJson.ToJSON);
  finally
    ApplyJson.Free;
  end;
end;

procedure TWebViewBridge.HandleConfirmTool(AJson: TJSONObject);
var
  CallId: string;
  Approved: Boolean;
begin
  if not AJson.TryGetValue<string>('callId', CallId) then Exit;
  if not AJson.TryGetValue<Boolean>('approved', Approved) then Exit;
  if CallId = FPendingConfirmCallId then
  begin
    FPendingConfirmCallId := '';
    FAgent.ConfirmToolExecution(Approved);
  end;
end;

procedure TWebViewBridge.HandleExportSession(AJson: TJSONObject);

  function HtmlEscape(const S: string): string;
  begin
    Result := S;
    Result := StringReplace(Result, '&', '&amp;', [rfReplaceAll]);
    Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
    Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
    Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
    Result := StringReplace(Result, '''', '&#39;', [rfReplaceAll]);
  end;

  function GetText(Content: TContentBlockList): string;
  var
    j: Integer;
  begin
    Result := '';
    for j := 0 to Content.Count - 1 do
      if Content[j] is TTextContent then
        Result := Result + TTextContent(Content[j]).Text;
  end;

var
  Session: TSession;
  SaveDlg: TSaveDialog;
  i: Integer;
  Sl: TStringList;
  Html: string;
  EscapedName: string;
begin
  Session := GetActiveSession;
  if Session = nil then Exit;

  SaveDlg := TSaveDialog.Create(nil);
  try
    SaveDlg.DefaultExt := '.html';
    SaveDlg.Filter := 'HTML files (*.html)|*.html|All files (*.*)|*.*';
    SaveDlg.FileName := Session.Name + '.html';
    if not SaveDlg.Execute then Exit;

    EscapedName := HtmlEscape(Session.Name);

    // Build simple HTML export
    Html := '<!DOCTYPE html><html><head><meta charset="utf-8"><title>' +
      EscapedName + '</title>' +
      '<style>body{font-family:sans-serif;max-width:860px;margin:40px auto;background:#1a1b1e;color:#f0f0f0}' +
      '.user{background:#1e3a5f;padding:12px;border-radius:14px;margin:8px 0}' +
      '.assistant{background:#2e2e2e;padding:12px;border-radius:14px;margin:8px 0}' +
      '.tool{background:#3a3a1a;padding:12px;border-radius:14px;margin:8px 0}' +
      'pre{background:#1a1b22;padding:12px;border-radius:8px;overflow-x:auto}</style></head><body>';
    Html := Html + '<h1>' + EscapedName + '</h1>';

    for i := 0 to Session.Messages.Count - 1 do
    begin
      var Msg := Session.Messages[i];
      var RoleClass := 'assistant';
      var Text := '';
      if Msg is TUserMessage then
      begin
        RoleClass := 'user';
        Text := TUserMessage(Msg).Content;
      end
      else if Msg is TAssistantMessage then
      begin
        RoleClass := 'assistant';
        Text := GetText(TAssistantMessage(Msg).Content);
      end
      else if Msg is TToolResultMessage then
      begin
        RoleClass := 'tool';
        Text := GetText(TToolResultMessage(Msg).Content);
      end;
      Html := Html + '<div class="' + RoleClass + '"><b>' +
        HtmlEscape(MessageRoleToString(Msg.Role)) + '</b><br>' +
        StringReplace(HtmlEscape(Text), #10, '<br>', [rfReplaceAll]) + '</div>';
    end;
    Html := Html + '</body></html>';

    Sl := TStringList.Create;
    try
      Sl.Text := Html;
      Sl.SaveToFile(SaveDlg.FileName, TEncoding.UTF8);
    finally
      Sl.Free;
    end;

    PostEvent('export_done', 'path', SaveDlg.FileName);
  finally
    SaveDlg.Free;
  end;
end;

procedure TWebViewBridge.HandleBranchSession(AJson: TJSONObject);
var
  Current: TSession;
  Branched: TSession;
begin
  Current := GetActiveSession;
  if Current = nil then Exit;
  Branched := Current.BranchFrom(Current.GetMessageCount);
  if Branched = nil then Exit;
  FSessionManager.SaveSession(Branched);
  FSessionManager.SetCurrentSession(Branched);

  // Reset agent with branched messages (clone to avoid shared ownership)
  FAgent.Reset;
  for var i := 0 to Branched.Messages.Count - 1 do
    FAgent.AppendMessage(Branched.Messages[i].Clone);

  // Send updated state
  var Json := TJSONObject.Create;
  Json.AddPair('event', 'session_loaded');
  Json.AddPair('sessionId', Branched.Id);
  Json.AddPair('sessionName', Branched.Name);
  var MsgArr := TJSONArray.Create;
  for var i := 0 to Branched.Messages.Count - 1 do
    MsgArr.AddElement(SerializeMessage(Branched.Messages[i]));
  Json.AddPair('messages', MsgArr);
  PostToJS(Json.ToJSON);
  Json.Free;

  PostToJS(SerializeSessionList);
end;

procedure TWebViewBridge.HandleUndo(AJson: TJSONObject);
begin
  FUndoLog.UndoLast;
end;

procedure TWebViewBridge.HandleChangeModel(AJson: TJSONObject);
var
  ProfileId: string;
  Config: TPiMonoConfig;
  Profile: TModelProfile;
  ModelInfo: TModelInfo;
  NewAdapter: TCustomAPIAdapter;
  ModelConfig: TModelConfig;
begin
  if not AJson.TryGetValue<string>('profileId', ProfileId) then Exit;
  Config := FSettingsManager.Config;
  if ProfileId = Config.ActiveModelId then Exit;
  Config.ActiveModelId := ProfileId;
  FSettingsManager.UpdateConfig(Config);

  // Reconnect model
  Profile := Config.GetActiveProfile;
  ModelInfo := TModelInfo.Create(
    Profile.ModelName, Profile.ModelName, 'internal', Profile.Endpoint);
  NewAdapter := TCustomAPIAdapter.Create(
    ModelInfo, Profile.ApiKey, FLogger,
    Config.Api.RetryCount, 2000, Config.Api.Timeout);
  FAgent.SetModelRef(NewAdapter);

  // Apply profile model settings
  ModelConfig := TModelConfig.GetDefault;
  ModelConfig.Name := Profile.ModelName;
  ModelConfig.MaxTokens := Profile.MaxTokens;
  ModelConfig.Temperature := Profile.Temperature;
  ModelConfig.TopP := Profile.TopP;
  FAgent.SetModel(ModelConfig);
  FAgent.SetThinkingLevel(Profile.ThinkingLevel);

  FAgent.SetCompactionSettings(
    Config.Session.CompactionEnabled, Config.Session.ReserveTokens,
    Config.Session.KeepRecentTokens, 128000);

  PostEvent('model_changed', 'name', Profile.DisplayName);
end;

procedure TWebViewBridge.HandleBrowseDirectory(AJson: TJSONObject);
var
  Field: string;
  Dlg: TFileOpenDialog;
begin
  if not AJson.TryGetValue<string>('field', Field) then Exit;

  Dlg := TFileOpenDialog.Create(nil);
  try
    Dlg.Options := [fdoPickFolders];
    if Dlg.Execute then
    begin
      var Json := TJSONObject.Create;
      Json.AddPair('event', 'browse_result');
      Json.AddPair('field', Field);
      Json.AddPair('path', Dlg.FileName);
      PostToJS(Json.ToJSON);
      Json.Free;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TWebViewBridge.HandleOpenSessionPopup(AJson: TJSONObject);
var
  SessionId: string;
begin
  if not AJson.TryGetValue<string>('sessionId', SessionId) then Exit;
  if not Assigned(FOnOpenPopup) then Exit;
  FOnOpenPopup(SessionId);
end;

procedure TWebViewBridge.HandleTestConnection(AJson: TJSONObject);
var
  Endpoint, ApiKey: string;
begin
  if not AJson.TryGetValue<string>('endpoint', Endpoint) then Exit;
  if not AJson.TryGetValue<string>('apiKey', ApiKey) then Exit;

  FLogger.Info('HandleTestConnection: endpoint=' + Endpoint + ' apiKeyLen=' + IntToStr(Length(ApiKey)));

  // Run HTTP call in background thread to avoid blocking the UI.
  // Capture FDestroying by value (Boolean) — checked before accessing Self.
  TThread.CreateAnonymousThread(
    procedure
    var
      Adapter: TCustomAPIAdapter;
      ModelList: TModelList;
      ModelArr: TJSONArray;
      i: Integer;
      Success: Boolean;
      ErrMsg, ModelsJson: string;
      WasDestroying: Boolean;
    begin
      Success := False;
      ErrMsg := '';
      ModelsJson := '[]';
      WasDestroying := FDestroying;

      if WasDestroying then Exit;

      try
        var Info := TModelInfo.Create('test', 'test', 'internal', Endpoint);
        Adapter := TCustomAPIAdapter.Create(Info, ApiKey, FLogger, 1, 5000, 10000);
        try
          ModelList := Adapter.GetModels;
          try
            Success := True;
            ModelArr := TJSONArray.Create;
            for i := 0 to ModelList.Count - 1 do
              ModelArr.Add(ModelList[i].Id);
            ModelsJson := ModelArr.ToJSON;
            ModelArr.Free;
          finally
            ModelList.Free;
          end;
        finally
          Adapter.Free;
        end;
      except
        on E: Exception do
          ErrMsg := E.Message;
      end;

      // Post result back to main thread -> WebView2
      TThread.Queue(nil,
        procedure
        var
          Json: TJSONObject;
          Script: string;
        begin
          if FDestroying then Exit;

          // Send via event system
          Json := TJSONObject.Create;
          Json.AddPair('event', 'test_connection_result');
          Json.AddPair('success', TJSONBool.Create(Success));
          if Success then
            Json.AddPair('models', TJSONObject.ParseJSONValue(ModelsJson) as TJSONArray)
          else
            Json.AddPair('error', ErrMsg);
          PostToJS(Json.ToJSON);
          Json.Free;

          // Also inject directly via ExecuteScript (bypasses JS caching issues)
          if Assigned(FOnExecuteScript) then
          begin
            if Success then
              Script := 'if(typeof onboarding!=="undefined" && onboarding.testing===true){onboarding.fetchedModels=' + ModelsJson +
                ';onboarding.testResult={success:true};onboarding.testing=false;onboarding.render();}'
            else
              Script := 'if(typeof onboarding!=="undefined" && onboarding.testing===true){onboarding.testResult={success:false,error:"' +
                ErrMsg.Replace('''', '''''''') + '"};onboarding.testing=false;onboarding.render();}';
            FOnExecuteScript(Script);
          end;
        end);
    end).Start;
end;

procedure TWebViewBridge.HandleSaveOnboarding(AJson: TJSONObject);
var
  Provider, ApiKey, Endpoint, ModelName: string;
  Profile: TModelProfile;
  Profiles: TArray<TModelProfile>;
  Config: TPiMonoConfig;
  ModelInfo: TModelInfo;
  NewAdapter: TCustomAPIAdapter;
begin
  if not AJson.TryGetValue<string>('provider', Provider) then Provider := 'openai';
  if not AJson.TryGetValue<string>('apiKey', ApiKey) then Exit;
  if not AJson.TryGetValue<string>('endpoint', Endpoint) then Exit;
  if not AJson.TryGetValue<string>('modelName', ModelName) then Exit;

  // Update global API settings
  FSettingsManager.UpdateApiEndpoint(Endpoint);
  FSettingsManager.UpdateApiKey(ApiKey);
  FSettingsManager.UpdateModelName(ModelName);

  // Update or create the default profile
  Profile := TModelProfile.Create('default', Provider, Endpoint, ApiKey, ModelName);
  SetLength(Profiles, 1);
  Profiles[0] := Profile;
  FSettingsManager.UpdateModelProfiles(Profiles, 'default');

  FSettingsManager.SaveGlobal;

  FLogger.Info('HandleSaveOnboarding: saved. provider=' + Provider +
    ' endpoint=' + Endpoint + ' model=' + ModelName);

  // Reconnect model with new settings (same pattern as HandleChangeModel)
  Config := FSettingsManager.Config;
  Profile := Config.GetActiveProfile;
  ModelInfo := TModelInfo.Create(
    Profile.ModelName, Profile.ModelName, 'internal', Profile.Endpoint);
  NewAdapter := TCustomAPIAdapter.Create(
    ModelInfo, Profile.ApiKey, FLogger,
    Config.Api.RetryCount, 2000, Config.Api.Timeout);
  FAgent.SetModelRef(NewAdapter);
  FAgent.SetCompactionSettings(
    Config.Session.CompactionEnabled, Config.Session.ReserveTokens,
    Config.Session.KeepRecentTokens, 128000);

  FLogger.Info('HandleSaveOnboarding: model reconnected to ' + Profile.ModelName);

  PostEvent('onboarding_complete');

  // Send full initial state to refresh UI (profiles, theme, isConfigured, etc.)
  SendInitialState;
end;

procedure TWebViewBridge.HandleUpdateProfiles(AJson: TJSONObject);
var
  ProfilesArr: TJSONArray;
  Profiles: TArray<TModelProfile>;
  i: Integer;
  Obj: TJSONObject;
  ActiveId: string;
begin
  ProfilesArr := AJson.FindValue('profiles') as TJSONArray;
  if ProfilesArr = nil then Exit;

  SetLength(Profiles, ProfilesArr.Count);
  for i := 0 to ProfilesArr.Count - 1 do
  begin
    Obj := ProfilesArr.Items[i] as TJSONObject;
    var TopP: Double := 1.0;
    var TL: TThinkingLevel := tlOff;
    if Obj.TryGetValue<Double>('topP', TopP) then ;
    var TLStr: string := '';
    if Obj.TryGetValue<string>('thinkingLevel', TLStr) then
      TL := StringToThinkingLevel(TLStr);
    Profiles[i] := TModelProfile.Create(
      Obj.GetValue<string>('id'),
      Obj.GetValue<string>('displayName'),
      Obj.GetValue<string>('endpoint'),
      Obj.GetValue<string>('apiKey'),
      Obj.GetValue<string>('modelName'),
      Obj.GetValue<Integer>('maxTokens'),
      Obj.GetValue<Double>('temperature'),
      TopP,
      TL
    );
  end;

  if not AJson.TryGetValue<string>('activeId', ActiveId) then
    ActiveId := FSettingsManager.Config.ActiveModelId;

  FSettingsManager.UpdateModelProfiles(Profiles, ActiveId);
  FSettingsManager.SaveGlobal;
  FLogger.Info('HandleUpdateProfiles: saved ' + IntToStr(Length(Profiles)) + ' profiles');

  // Send updated config back
  PostToJS(SerializeConfig);
  PostEvent('settings_saved');
end;

procedure TWebViewBridge.HandleUpdateSkills(AJson: TJSONObject);
var
  SkillsArr: TJSONArray;
  Skills: TArray<TSkillDef>;
  i: Integer;
  Obj: TJSONObject;
begin
  SkillsArr := AJson.FindValue('skills') as TJSONArray;
  if SkillsArr = nil then Exit;

  SetLength(Skills, SkillsArr.Count);
  for i := 0 to SkillsArr.Count - 1 do
  begin
    Obj := SkillsArr.Items[i] as TJSONObject;
    Skills[i] := TSkillDef.Create(
      Obj.GetValue<string>('id'),
      Obj.GetValue<string>('name'),
      Obj.GetValue<string>('description'),
      Obj.GetValue<string>('content', ''),
      Obj.GetValue<string>('references', ''),
      Obj.GetValue<string>('examples', '')
    );
  end;

  FSettingsManager.UpdateSkillPool(Skills);
  FSettingsManager.SaveGlobal;
  FLogger.Info('HandleUpdateSkills: saved ' + IntToStr(Length(Skills)) + ' skills');

  PostToJS(SerializeConfig);
  PostEvent('settings_saved');
end;

{ ---- Agent Event Handlers (replaces TAgentEventBridge) ---- }

procedure TWebViewBridge.OnAgentEvent(AEvent: TAgentEvent);
var
  CapturedEvent: TAgentEvent;
begin
  if FDestroying then Exit;

  // Capture event into local variable to avoid anonymous method capturing var param
  CapturedEvent := AEvent;

  // Use Synchronize (synchronous) instead of Queue (async) to prevent
  // use-after-free: DispatchEvent frees the event after all handlers return,
  // but Queue is async so the anonymous method may run after the event is freed.
  // Synchronize blocks until the main thread processes the event, keeping it alive.
  TThread.Synchronize(nil,
    procedure
    begin
      if FDestroying then Exit;
      try
        case CapturedEvent.EventType of
          aetAgentStart: HandleAgentStart;
          aetAgentEnd: HandleAgentEnd(CapturedEvent as TAgentEndEvent);
          aetMessageUpdate:
            begin
              // TStreamDeltaEvent and TMessageUpdateEvent both return aetMessageUpdate.
              // Handle TStreamDeltaEvent first (newer, simpler path).
              if CapturedEvent is TStreamDeltaEvent then
              begin
                var SDE := CapturedEvent as TStreamDeltaEvent;
                var Json := TJSONObject.Create;
                Json.AddPair('event', 'stream_delta');
                case SDE.DeltaType of
                  sdtText: Json.AddPair('type', 'text');
                  sdtThinking: Json.AddPair('type', 'thinking');
                  sdtToolCall: Json.AddPair('type', 'toolcall');
                end;
                Json.AddPair('content', SDE.DeltaText);
                PostToJS(Json.ToJSON);
                Json.Free;
              end
              else if CapturedEvent is TMessageUpdateEvent then
              begin
                var MsgEvent := CapturedEvent as TMessageUpdateEvent;
                if MsgEvent.AssistantMessageEvent <> nil then
                begin
                  case MsgEvent.AssistantMessageEvent.EventType of
                    ametTextDelta:
                      begin
                        var TDE := MsgEvent.AssistantMessageEvent as TTextDeltaEvent;
                        var Json := TJSONObject.Create;
                        Json.AddPair('event', 'stream_delta');
                        Json.AddPair('type', 'text');
                        Json.AddPair('content', TDE.Delta);
                        PostToJS(Json.ToJSON);
                        Json.Free;
                      end;
                    ametThinkingDelta:
                      begin
                        var TDE := MsgEvent.AssistantMessageEvent as TThinkingDeltaEvent;
                        var Json := TJSONObject.Create;
                        Json.AddPair('event', 'stream_delta');
                        Json.AddPair('type', 'thinking');
                        Json.AddPair('content', TDE.Delta);
                        PostToJS(Json.ToJSON);
                        Json.Free;
                      end;
                    ametToolCallDelta:
                      begin
                        var TDE := MsgEvent.AssistantMessageEvent as TToolCallDeltaEvent;
                        var Json := TJSONObject.Create;
                        Json.AddPair('event', 'stream_delta');
                        Json.AddPair('type', 'toolcall');
                        Json.AddPair('content', TDE.Delta);
                        PostToJS(Json.ToJSON);
                        Json.Free;
                      end;
                  end;
                end;
              end;
            end;
          aetMessageEnd: HandleMessageEnd(CapturedEvent as TMessageEndEvent);
          aetToolExecutionStart: HandleToolStart(CapturedEvent as TToolExecutionStartEvent);
          aetToolExecutionEnd: HandleToolEnd(CapturedEvent as TToolExecutionEndEvent);
          aetToolConfirmationRequest: HandleToolConfirm(CapturedEvent as TToolConfirmationRequestEvent);
          aetError:
            begin
              var ErrEvent := CapturedEvent as TAgentErrorEvent;
              var Json := TJSONObject.Create;
              Json.AddPair('event', 'agent_error');
              Json.AddPair('message', ErrEvent.ErrorMessage);
              PostToJS(Json.ToJSON);
              Json.Free;
            end;
        end;
      except
        on E: Exception do
          FLogger.Error('WebViewBridge.OnAgentEvent: ' + E.Message);
      end;
    end);
end;

procedure TWebViewBridge.HandleAgentStart;
begin
  PostEvent('agent_start');
end;

procedure TWebViewBridge.HandleAgentEnd(AEvent: TAgentEndEvent);
var
  Session: TSession;
  i: Integer;
begin
  PostEvent('agent_end');

  // Sync agent messages back to session (agent owns its own copies since we Clone)
  Session := GetActiveSession;
  if Session <> nil then
  begin
    // Replace session messages with clones of agent's messages
    Session.Messages.Clear;
    for i := 0 to FAgent.GetState.Messages.Count - 1 do
      Session.Messages.Add(FAgent.GetState.Messages[i].Clone);

    FSessionManager.SaveSession(Session);
    FLogger.Info('HandleAgentEnd: session saved with ' + IntToStr(Session.Messages.Count) + ' messages');
  end;

  // Send updated session list (session name may have changed)
  PostToJS(SerializeSessionList);
end;

procedure TWebViewBridge.HandleMessageEnd(AEvent: TMessageEndEvent);
var
  Json: TJSONObject;
begin
  Json := TJSONObject.Create;
  Json.AddPair('event', 'message_end');
  Json.AddPair('message', SerializeMessage(AEvent.Message));
  PostToJS(Json.ToJSON);
  Json.Free;
end;

procedure TWebViewBridge.HandleToolStart(AEvent: TToolExecutionStartEvent);
var
  Json: TJSONObject;
begin
  Json := TJSONObject.Create;
  Json.AddPair('event', 'tool_start');
  Json.AddPair('callId', AEvent.ToolCallId);
  Json.AddPair('name', AEvent.ToolName);
  if AEvent.Args <> nil then
    Json.AddPair('args', AEvent.Args.Clone as TJSONObject)
  else
    Json.AddPair('args', TJSONObject.Create);
  PostToJS(Json.ToJSON);
  Json.Free;
end;

procedure TWebViewBridge.HandleToolEnd(AEvent: TToolExecutionEndEvent);
var
  Json: TJSONObject;
begin
  Json := TJSONObject.Create;
  Json.AddPair('event', 'tool_end');
  Json.AddPair('callId', AEvent.ToolCallId);
  Json.AddPair('name', AEvent.ToolName);
  Json.AddPair('result', AEvent.Result);
  Json.AddPair('error', TJSONBool.Create(AEvent.IsError));
  PostToJS(Json.ToJSON);
  Json.Free;
end;

procedure TWebViewBridge.HandleToolConfirm(AEvent: TToolConfirmationRequestEvent);
var
  Json: TJSONObject;
begin
  FPendingConfirmCallId := AEvent.ToolCallId;
  Json := TJSONObject.Create;
  Json.AddPair('event', 'tool_confirm');
  Json.AddPair('callId', AEvent.ToolCallId);
  Json.AddPair('name', AEvent.ToolName);
  Json.AddPair('filePath', AEvent.FilePath);
  Json.AddPair('diff', AEvent.DiffPreview);
  if AEvent.Args <> nil then
    Json.AddPair('args', AEvent.Args.Clone as TJSONObject)
  else
    Json.AddPair('args', TJSONObject.Create);
  PostToJS(Json.ToJSON);
  Json.Free;
end;

{ ---- Serialization ---- }

function TWebViewBridge.SerializeMessage(AMessage: TAgentMessage): TJSONObject;
begin
  Result := AMessage.ToJson;
end;

function TWebViewBridge.SerializeSessionList: string;
var
  Json, SessionObj: TJSONObject;
  Arr: TJSONArray;
  Sessions: TArray<TSessionInfo>;
  S: TSessionInfo;
begin
  Json := TJSONObject.Create;
  Json.AddPair('event', 'session_list');
  Arr := TJSONArray.Create;
  Sessions := FSessionManager.ListSessions;
  for S in Sessions do
  begin
    SessionObj := TJSONObject.Create;
    SessionObj.AddPair('id', S.Id);
    SessionObj.AddPair('name', S.Name);
    SessionObj.AddPair('messageCount', TJSONNumber.Create(S.MessageCount));
    SessionObj.AddPair('parentId', S.ParentId);
    SessionObj.AddPair('branchPoint', TJSONNumber.Create(S.BranchPoint));
    Arr.AddElement(SessionObj);
  end;
  Json.AddPair('sessions', Arr);

  // Include current session id
  var Current := GetActiveSession;
  if Current <> nil then
    Json.AddPair('currentSessionId', Current.Id);

  Result := Json.ToJSON;
  Json.Free;
end;

function TWebViewBridge.SerializeConfig: string;
var
  Config: TPiMonoConfig;
  Json: TJSONObject;
  Profile: TModelProfile;
begin
  Config := FSettingsManager.Config;
  Json := TJSONObject.Create;
  Json.AddPair('event', 'config_data');

  // API
  Json.AddPair('apiEndpoint', Config.Api.Endpoint);
  Json.AddPair('apiKey', Config.Api.ApiKey);
  Json.AddPair('modelsEndpoint', Config.Api.ModelsEndpoint);
  Json.AddPair('streaming', TJSONBool.Create(Config.Api.EnableStreaming));
  Json.AddPair('timeout', TJSONNumber.Create(Config.Api.Timeout));
  Json.AddPair('retryCount', TJSONNumber.Create(Config.Api.RetryCount));

  // Model
  Profile := Config.GetActiveProfile;
  Json.AddPair('modelName', Profile.ModelName);
  Json.AddPair('maxTokens', TJSONNumber.Create(Profile.MaxTokens));
  Json.AddPair('temperature', TJSONNumber.Create(Profile.Temperature));
  Json.AddPair('topP', TJSONNumber.Create(Profile.TopP));
  Json.AddPair('thinkingLevel', ThinkingLevelToString(Profile.ThinkingLevel));

  // UI
  Json.AddPair('theme', Config.UI.Theme);
  Json.AddPair('fontSize', TJSONNumber.Create(Config.UI.FontSize));
  Json.AddPair('fontFamily', Config.UI.FontFamily);
  Json.AddPair('language', Config.UI.Language);

  // Paths
  Json.AddPair('workingDir', Config.Directories.Working);
  Json.AddPair('backupDir', Config.Directories.Backup);

  // Profiles (direct array, no double-serialization)
  Json.AddPair('profiles', SerializeProfiles);

  // Search
  Json.AddPair('searchEnabled', TJSONBool.Create(Config.Search.Enabled));
  Json.AddPair('searchProvider', SearchProviderToString(Config.Search.Provider));
  Json.AddPair('searchApiKey', Config.Search.ApiKey);
  Json.AddPair('searchCustomId', Config.Search.CustomId);
  Json.AddPair('searchMaxResults', TJSONNumber.Create(Config.Search.MaxResults));
  Json.AddPair('searchTimeout', TJSONNumber.Create(Config.Search.Timeout));
  Json.AddPair('searchEnableFetch', TJSONBool.Create(Config.Search.EnableFetch));
  Json.AddPair('searchFetchMaxLength', TJSONNumber.Create(Config.Search.FetchMaxLength));

  // Skills (direct array, no double-serialization)
  Json.AddPair('skills', SerializeSkills);

  Result := Json.ToJSON;
  Json.Free;
end;

function TWebViewBridge.SerializeThemeColors: string;
begin
  // Theme colors are now defined purely in CSS (themes.css).
  // This method is kept as a no-op for backward compatibility.
  var Json := TJSONObject.Create;
  Json.AddPair('event', 'theme_colors');
  Result := Json.ToJSON;
  Json.Free;
end;

function TWebViewBridge.SerializeProfiles: TJSONArray;
var
  Config: TPiMonoConfig;
  Obj: TJSONObject;
  P: TModelProfile;
begin
  Config := FSettingsManager.Config;
  Result := TJSONArray.Create;
  for P in Config.ModelProfiles do
  begin
    Obj := TJSONObject.Create;
    Obj.AddPair('id', P.Id);
    Obj.AddPair('displayName', P.DisplayName);
    Obj.AddPair('endpoint', P.Endpoint);
    Obj.AddPair('apiKey', P.ApiKey);
    Obj.AddPair('modelName', P.ModelName);
    Obj.AddPair('maxTokens', TJSONNumber.Create(P.MaxTokens));
    Obj.AddPair('temperature', TJSONNumber.Create(P.Temperature));
    Obj.AddPair('topP', TJSONNumber.Create(P.TopP));
    Obj.AddPair('thinkingLevel', ThinkingLevelToString(P.ThinkingLevel));
    Result.AddElement(Obj);
  end;
end;

function TWebViewBridge.SerializeSkills: TJSONArray;
var
  Config: TPiMonoConfig;
  Obj: TJSONObject;
  S: TSkillDef;
begin
  Config := FSettingsManager.Config;
  Result := TJSONArray.Create;
  for S in Config.SkillPool do
  begin
    Obj := TJSONObject.Create;
    Obj.AddPair('id', S.Id);
    Obj.AddPair('name', S.DisplayName);
    Obj.AddPair('description', S.Description);
    Obj.AddPair('content', S.Content);
    Result.AddElement(Obj);
  end;
end;

{ ---- BuildLocalizationJson ---- }

function TWebViewBridge.BuildLocalizationJson: string;
var
  Json: TJSONObject;
begin
  Json := TJSONObject.Create;
  try
    Json.AddPair('event', 'localization');

    // --- Status bar ---
    Json.AddPair('status.ready', L('status.ready'));
    Json.AddPair('status.readyBranch', L('status.readyBranch'));
    Json.AddPair('status.executingTool', L('status.executingTool'));
    Json.AddPair('status.toolFailedShort', L('status.toolFailedShort'));
    Json.AddPair('status.toolDoneShort', L('status.toolDoneShort'));
    Json.AddPair('status.error', L('status.error'));

    // --- Sidebar ---
    Json.AddPair('sidebar.newChat', L('sidebar.newChat'));
    Json.AddPair('sidebar.empty', L('sidebar.empty'));

    // --- Welcome screen ---
    Json.AddPair('welcome.title', L('welcome.title'));
    Json.AddPair('welcome.subtitle', L('welcome.subtitle'));
    Json.AddPair('welcome.examples', L('welcome.examples'));
    Json.AddPair('welcome.suggest1', L('welcome.suggest1'));
    Json.AddPair('welcome.suggest2', L('welcome.suggest2'));
    Json.AddPair('welcome.suggest3', L('welcome.suggest3'));
    Json.AddPair('welcome.suggest4', L('welcome.suggest4'));

    // --- Chat ---
    Json.AddPair('chat.placeholder', L('chat.placeholder'));
    Json.AddPair('chat.codeCopy', L('chat.codeCopy'));
    Json.AddPair('chat.codeCopied', L('chat.codeCopied'));
    Json.AddPair('chat.copyMsg', L('chat.copyMsg'));
    Json.AddPair('chat.copyMsgDone', L('chat.copyMsgDone'));
    Json.AddPair('chat.thinking', L('chat.thinking'));
    Json.AddPair('chat.you', L('chat.you'));
    Json.AddPair('chat.assistant', L('chat.assistant'));

    // --- Messages ---
    Json.AddPair('settings.activeModel', L('settings.activeModel'));
    Json.AddPair('msg.exportedTo', L('msg.exportedTo'));
    Json.AddPair('error.noApiKey', L('error.noApiKey'));
    Json.AddPair('error.noEndpoint', L('error.noEndpoint'));
    Json.AddPair('error.noModel', L('error.noModel'));

    // --- Settings: tabs ---
    Json.AddPair('settings.title', L('settings.title'));
    Json.AddPair('settings.tabApi', L('settings.tabApi'));
    Json.AddPair('settings.tabModel', L('settings.tabModel'));
    Json.AddPair('settings.tabUI', L('settings.tabUI'));
    Json.AddPair('settings.tabPaths', L('settings.tabPaths'));
    Json.AddPair('settings.tabProfiles', L('settings.tabProfiles'));
    Json.AddPair('settings.tabSearch', L('settings.tabSearch'));
    Json.AddPair('settings.tabSkills', L('settings.tabSkills'));

    // --- Settings: API ---
    Json.AddPair('settings.apiEndpoint', L('settings.apiEndpoint'));
    Json.AddPair('settings.apiKey', L('settings.apiKey'));
    Json.AddPair('settings.modelsEndpoint', L('settings.modelsEndpoint'));
    Json.AddPair('settings.streaming', L('settings.streaming'));
    Json.AddPair('settings.timeout', L('settings.timeout'));
    Json.AddPair('settings.retryCount', L('settings.retryCount'));

    // --- Settings: Model ---
    Json.AddPair('settings.modelName', L('settings.modelName'));
    Json.AddPair('settings.maxTokens', L('settings.maxTokens'));
    Json.AddPair('settings.temperature', L('settings.temperature'));
    Json.AddPair('settings.topP', L('settings.topP'));
    Json.AddPair('settings.thinkingLevel', L('settings.thinkingLevel'));
    Json.AddPair('settings.topPHint', L('settings.topPHint'));
    Json.AddPair('settings.thinkingHint', L('settings.thinkingHint'));

    // --- Settings: UI ---
    Json.AddPair('settings.theme', L('settings.theme'));
    Json.AddPair('settings.fontSize', L('settings.fontSize'));
    Json.AddPair('settings.fontFamily', L('settings.fontFamily'));
    Json.AddPair('settings.language', L('settings.language'));
    Json.AddPair('settings.langEn', L('settings.langEn'));
    Json.AddPair('settings.langZh', L('settings.langZh'));

    // --- Settings: Paths ---
    Json.AddPair('settings.workingDir', L('settings.workingDir'));
    Json.AddPair('settings.backupDir', L('settings.backupDir'));
    Json.AddPair('settings.browse', L('settings.browse'));

    // --- Settings: Buttons ---
    Json.AddPair('settings.save', L('settings.save'));
    Json.AddPair('settings.cancel', L('settings.cancel'));

    // --- Settings: Profiles ---
    Json.AddPair('settings.addProfile', L('settings.addProfile'));
    Json.AddPair('settings.deleteProfile', L('settings.deleteProfile'));
    Json.AddPair('settings.setActive', L('settings.setActive'));
    Json.AddPair('settings.profileDisplayName', L('settings.profileDisplayName'));
    Json.AddPair('settings.profileEndpoint', L('settings.profileEndpoint'));
    Json.AddPair('settings.profileApiKey', L('settings.profileApiKey'));
    Json.AddPair('settings.profileModelName', L('settings.profileModelName'));
    Json.AddPair('settings.profileMaxTokens', L('settings.profileMaxTokens'));
    Json.AddPair('settings.profileTemperature', L('settings.profileTemperature'));

    // --- Settings: Search ---
    Json.AddPair('settings.searchEnabled', L('settings.searchEnabled'));
    Json.AddPair('settings.searchProvider', L('settings.searchProvider'));
    Json.AddPair('settings.searchApiKey', L('settings.searchApiKey'));
    Json.AddPair('settings.searchCustomId', L('settings.searchCustomId'));
    Json.AddPair('settings.searchMaxResults', L('settings.searchMaxResults'));
    Json.AddPair('settings.searchTimeout', L('settings.searchTimeout'));

    // --- Settings: Skills ---
    Json.AddPair('settings.skillNew', L('settings.skillNew'));
    Json.AddPair('settings.skillDelete', L('settings.skillDelete'));

    // --- Buttons ---
    Json.AddPair('btn.approve', L('btn.approve'));
    Json.AddPair('btn.reject', L('btn.reject'));
    Json.AddPair('btn.newchat', L('btn.newchat'));
    Json.AddPair('btn.stop', L('btn.stop'));
    Json.AddPair('btn.send', L('btn.send'));

    // --- Session ---
    Json.AddPair('session.prefix', L('session.prefix'));
    Json.AddPair('msg.selectRename', L('msg.selectRename'));
    Json.AddPair('msg.renameTitle', L('msg.renameTitle'));
    Json.AddPair('msg.deleteConfirm', L('msg.deleteConfirm'));
    Json.AddPair('btn.settings', L('btn.settings'));

    // --- Context Menu ---
    Json.AddPair('context.rename', L('context.rename'));
    Json.AddPair('context.delete', L('context.delete'));

    // --- Skill Panel ---
    Json.AddPair('skills.label', L('skills.label'));
    Json.AddPair('sidebar.noSkillDetail', L('sidebar.noSkillDetail'));

    Result := Json.ToJSON;
  finally
    Json.Free;
  end;
end;

{ ---- SendInitialState ---- }

procedure TWebViewBridge.SendInitialState;
var
  Json: TJSONObject;
  ProfilesArr, SkillsArr: TJSONArray;
  Configured: Boolean;
begin
  FLogger.Info('SendInitialState: BEGIN');

  // CRITICAL: Apply saved language before building any localized strings
  SetLanguage(LangFromCode(FSettingsManager.Config.UI.Language));

  Configured := FSettingsManager.IsConfigured;

  Json := TJSONObject.Create;
  try
    Json.AddPair('event', 'initial_state');

    // Popup window flag (for hiding sidebar in popup)
    Json.AddPair('isPopupWindow', TJSONBool.Create(FSessionOverride <> nil));

    // Onboarding: check if API is configured
    FLogger.Info('SendInitialState: IsConfigured=' + BoolToStr(Configured, True));
    var Profile := FSettingsManager.Config.GetActiveProfile;
    FLogger.Info('SendInitialState: Profile.ApiKey=' + IntToStr(Length(Profile.ApiKey)) +
      ' chars, Endpoint=' + IntToStr(Length(Profile.Endpoint)) +
      ' chars, ModelName=' + IntToStr(Length(Profile.ModelName)) + ' chars');
    FLogger.Info('SendInitialState: ActiveModelId=' + FSettingsManager.Config.ActiveModelId +
      ' ProfileCount=' + IntToStr(Length(FSettingsManager.Config.ModelProfiles)));
    Json.AddPair('isConfigured', TJSONBool.Create(Configured));

    // Theme
    Json.AddPair('theme', FSettingsManager.Config.UI.Theme);
    Json.AddPair('language', FSettingsManager.Config.UI.Language);
    Json.AddPair('fontSize', TJSONNumber.Create(FSettingsManager.Config.UI.FontSize));
    Json.AddPair('fontFamily', FSettingsManager.Config.UI.FontFamily);
    FLogger.Info('SendInitialState: theme=' + FSettingsManager.Config.UI.Theme +
      ' lang=' + FSettingsManager.Config.UI.Language);

    // Git branch
    var Branch := DetectGitBranch(FSettingsManager.Config.Directories.Working);
    if Branch <> '' then
      Json.AddPair('gitBranch', Branch);
    FLogger.Info('SendInitialState: branch=' + Branch);

    // Model (Profile already declared above)
    Json.AddPair('activeModelName', Profile.DisplayName);
    Json.AddPair('activeModelId', FSettingsManager.Config.ActiveModelId);
    FLogger.Info('SendInitialState: model=' + Profile.DisplayName);

    // Profiles list (direct array)
    ProfilesArr := SerializeProfiles;
    FLogger.Info('SendInitialState: profiles count=' + IntToStr(ProfilesArr.Count));
    Json.AddPair('profiles', ProfilesArr);

    // Skills (direct array)
    SkillsArr := SerializeSkills;
    FLogger.Info('SendInitialState: skills count=' + IntToStr(SkillsArr.Count));
    Json.AddPair('skills', SkillsArr);

    // Send localization BEFORE initial_state so L() calls in JS work correctly
    FLogger.Info('SendInitialState: sending localization (BEFORE initial_state)');
    PostToJS(BuildLocalizationJson);

    FLogger.Info('SendInitialState: posting initial_state event');
    PostToJS(Json.ToJSON);
  finally
    Json.Free;
  end;

  // Send session list
  FLogger.Info('SendInitialState: sending session list');
  PostToJS(SerializeSessionList);

  // Send current session messages
  var Current := GetActiveSession;
  if (Current <> nil) and (Current.Messages.Count > 0) then
  begin
    FLogger.Info('SendInitialState: loading session ' + Current.Id + ' with ' + IntToStr(Current.Messages.Count) + ' messages');
    var SJson := TJSONObject.Create;
    try
      SJson.AddPair('event', 'session_loaded');
      SJson.AddPair('sessionId', Current.Id);
      SJson.AddPair('sessionName', Current.Name);
      var MsgArr := TJSONArray.Create;
      for var i := 0 to Current.Messages.Count - 1 do
        MsgArr.AddElement(SerializeMessage(Current.Messages[i]));
      SJson.AddPair('messages', MsgArr);
      PostToJS(SJson.ToJSON);
    finally
      SJson.Free;
    end;
  end
  else
  begin
    FLogger.Info('SendInitialState: no current session, sending show_welcome');
    PostEvent('show_welcome');
  end;

  // Send theme colors
  FLogger.Info('SendInitialState: sending theme colors');
  PostToJS(SerializeThemeColors);

  FLogger.Info('SendInitialState: END - all data sent');

  // Trigger onboarding directly via ExecuteScript if not configured
  // This bypasses the event system to avoid any JS caching issues
  if not Configured then
  begin
    FLogger.Info('SendInitialState: triggering onboarding via ExecuteScript');
    if Assigned(FOnExecuteScript) then
      FOnExecuteScript(
        'setTimeout(function(){' +
        '  try {' +
        '    if (typeof onboarding !== "undefined") { onboarding.start(); }' +
        '    else { window.chrome.webview.postMessage(JSON.stringify({action:"diag",error:"onboarding undefined"})); }' +
        '  } catch(e) {' +
        '    window.chrome.webview.postMessage(JSON.stringify({action:"diag",error:"onboarding start failed: " + e.message}));' +
        '  }' +
        '}, 600);'
      );
  end;
end;

end.
