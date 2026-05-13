unit UI.SessionChatForm;

{ TSessionChatForm - Popup chat window for a specific session.
  Each popup has its own TAgent + TWebViewBridge + TModelAdapter,
  sharing TSessionManager, TSettingsManager, FLogger, FUndoLog from main form.
  Similar to WeChat's independent chat windows. }

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes, System.JSON, System.DateUtils,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.ExtCtrls,
  Core.Messages, Core.Events, Core.Agent, Core.AgentState,
  Core.SessionManager, Core.UndoLog, Core.AgentFactory,
  AI.IModel, AI.CustomAPIAdapter, AI.ModelConfig,
  Settings.Config, Settings.SettingsManager,
  Utils.Logger, Utils.Localization, Utils.JsonHelper,
  UI.WebViewBridge,
  uWVBrowser, uWVWindowParent, uWVTypes, uWVLoader,
  uWVTypeLibrary, uWVCoreWebView2Args;

type
  TSessionChatForm = class(TForm)
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormShow(Sender: TObject);
  private
    // WebView2 (independent instance)
    FWVBrowser: TWVBrowser;
    FWVWindowParent: TWVWindowParent;

    // Independent Agent + Bridge + Model
    FAgent: TAgent;
    FWebViewBridge: TWebViewBridge;
    FModelAdapter: TCustomAPIAdapter;

    // Shared services (references, not owned)
    FLogger: TLogger;
    FSettingsManager: TSettingsManager;
    FSessionManager: TSessionManager;
    FUndoLog: TUndoLog;

    // Independent session
    FSession: TSession;
    FSessionId: string;

    FBrowserReady: Boolean;
    FDestroying: Boolean;

    procedure BrowserCreated(Sender: TObject);
    procedure BrowserWebMessageReceived(Sender: TObject;
      const aWebView: ICoreWebView2;
      const aArgs: ICoreWebView2WebMessageReceivedEventArgs);
    procedure DoPostJS(const AJson: string);
    procedure DoExecuteScript(const AScript: string);
    procedure InitializeAgent;

    procedure WMMove(var aMessage: TWMMove); message WM_MOVE;
    procedure WMMoving(var aMessage: TMessage); message WM_MOVING;
  public
    constructor Create(AOwner: TComponent; const ASessionId: string;
      ALogger: TLogger; ASettingsManager: TSettingsManager;
      ASessionManager: TSessionManager; AUndoLog: TUndoLog); reintroduce;
    destructor Destroy; override;

    property SessionId: string read FSessionId;
  end;

implementation

{$R *.dfm}

constructor TSessionChatForm.Create(AOwner: TComponent; const ASessionId: string;
  ALogger: TLogger; ASettingsManager: TSettingsManager;
  ASessionManager: TSessionManager; AUndoLog: TUndoLog);
begin
  inherited Create(AOwner);
  FSessionId := ASessionId;
  FLogger := ALogger;
  FSettingsManager := ASettingsManager;
  FSessionManager := ASessionManager;
  FUndoLog := AUndoLog;
  FBrowserReady := False;
  FDestroying := False;
  FAgent := nil;
  FWebViewBridge := nil;
  FModelAdapter := nil;
  FSession := nil;
  FWVBrowser := nil;
  FWVWindowParent := nil;
end;

destructor TSessionChatForm.Destroy;
begin
  inherited;
end;

procedure TSessionChatForm.FormShow(Sender: TObject);
begin
  // Window sizing
  Width := 900;
  Height := 700;
  Position := poDefault;
  Color := $1A1B1E;

  // Load session data
  FSession := FSessionManager.LoadSessionById(FSessionId);
  if FSession = nil then
  begin
    FLogger.Error('SessionChatForm: failed to load session ' + FSessionId);
    Exit;
  end;
  Caption := FSession.Name + ' - PiMono';

  // Create WebView2 host
  FWVWindowParent := TWVWindowParent.Create(Self);
  FWVWindowParent.Parent := Self;
  FWVWindowParent.Align := alClient;
  FWVWindowParent.Visible := True;

  FWVBrowser := TWVBrowser.Create(Self);
  FWVBrowser.DefaultURL := '';
  FWVBrowser.DefaultBackgroundColor := TColor($1A1B1E);
  FWVWindowParent.Browser := FWVBrowser;
  FWVBrowser.OnAfterCreated := BrowserCreated;
  FWVBrowser.OnWebMessageReceived := BrowserWebMessageReceived;

  // Initialize independent Agent
  InitializeAgent;

  // Create Bridge with session override
  FWebViewBridge := TWebViewBridge.Create(
    FAgent, FLogger, FSettingsManager, FSessionManager, FUndoLog);
  FWebViewBridge.SessionOverride := FSession;
  FWebViewBridge.OnPostJS := DoPostJS;
  FWebViewBridge.OnExecuteScript := DoExecuteScript;
  FWebViewBridge.OnOpenPopup := nil;  // Popups don't spawn further popups
  FWebViewBridge.Subscribe;

  // Replay session messages into Agent (clone to avoid shared ownership)
  FAgent.Reset;
  for var i := 0 to FSession.Messages.Count - 1 do
    FAgent.AppendMessage(FSession.Messages[i].Clone);

  // Create browser (async)
  if GlobalWebView2Loader.Initialized then
    FWVBrowser.CreateBrowser(FWVWindowParent.Handle)
  else
    FLogger.Error('SessionChatForm: WebView2 loader not ready');
end;

procedure TSessionChatForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  FDestroying := True;

  if FWebViewBridge <> nil then
    FWebViewBridge.Destroying := True;

  // Save session to disk
  if (FSession <> nil) and (FAgent <> nil) then
  begin
    try
      FSessionManager.SaveSession(FSession);
    except
      on E: Exception do
        FLogger.Error('SessionChatForm: save failed: ' + E.Message);
    end;
  end;

  // Abort agent and wait
  if FAgent <> nil then
  begin
    FAgent.Abort;
    // Use WaitForIdle instead of busy-wait loop to avoid blocking the main thread
    FAgent.WaitForIdle(5000);
  end;

  // Cleanup (order matters)
  FreeAndNil(FWebViewBridge);
  FreeAndNil(FAgent);
  FModelAdapter := nil;
  FreeAndNil(FSession);

  Action := caFree;
end;

procedure TSessionChatForm.BrowserCreated(Sender: TObject);
var
  WebUIFolder: string;
begin
  FBrowserReady := True;
  FWVWindowParent.UpdateSize;

  FLogger.Info('SessionChatForm: browser created for session ' + FSessionId);

  // Clear WebView2 cache to prevent stale CSS/JS
  try
    FWVBrowser.CallDevToolsProtocolMethod('Network.clearBrowserCache', '{}');
  except
  end;

  // Set virtual host mapping (each TWVBrowser needs its own call)
  WebUIFolder := ExtractFilePath(Application.ExeName) + 'WebUI';
  if DirectoryExists(WebUIFolder) then
  begin
    FWVBrowser.SetVirtualHostNameToFolderMapping(
      'pimono.local', WebUIFolder, COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_ALLOW);
    FWVBrowser.Navigate('https://pimono.local/index.html?t=' + IntToStr(DateTimeToUnix(Now, False)));
  end
  else
  begin
    FLogger.Error('SessionChatForm: WebUI folder not found');
    FWVBrowser.NavigateToString(
      '<html><body style="background:#1a1b1e;color:#f0f0f0;font-family:sans-serif">' +
      '<p>WebUI folder not found</p></body></html>');
  end;
end;

procedure TSessionChatForm.BrowserWebMessageReceived(Sender: TObject;
  const aWebView: ICoreWebView2;
  const aArgs: ICoreWebView2WebMessageReceivedEventArgs);
var
  TempData: TCoreWebView2WebMessageReceivedEventArgs;
begin
  TempData := TCoreWebView2WebMessageReceivedEventArgs.Create(aArgs);
  try
    FWebViewBridge.HandleRawWebMessage(TempData.WebMessageAsJson);
  finally
    TempData.Free;
  end;
end;

procedure TSessionChatForm.DoPostJS(const AJson: string);
begin
  if not FBrowserReady or (FWVBrowser = nil) then Exit;
  FWVBrowser.PostWebMessageAsJson(AJson);
end;

procedure TSessionChatForm.DoExecuteScript(const AScript: string);
begin
  if not FBrowserReady or (FWVBrowser = nil) then Exit;
  FWVBrowser.ExecuteScript(AScript);
end;

procedure TSessionChatForm.InitializeAgent;
begin
  FAgent := TAgentFactory.CreateAgent(FLogger, FSettingsManager, FUndoLog);
  TAgentFactory.ConnectModel(FAgent, FSettingsManager, FLogger, FModelAdapter);
end;

procedure TSessionChatForm.WMMove(var aMessage: TWMMove);
begin
  inherited;
  if FWVBrowser <> nil then
    FWVBrowser.NotifyParentWindowPositionChanged;
end;

procedure TSessionChatForm.WMMoving(var aMessage: TMessage);
begin
  inherited;
  if FWVBrowser <> nil then
    FWVBrowser.NotifyParentWindowPositionChanged;
end;

end.
