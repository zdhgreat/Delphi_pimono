unit UI.MainForm;

{ TMainForm - Thin VCL shell hosting WebView2 browser.
  All UI rendering is done by HTML/CSS/JS in the WebView.
  Core logic (Agent, Session, Tools, Settings) is unchanged. }

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes, System.JSON, System.DateUtils, System.IOUtils,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.ExtCtrls,
  Core.Messages, Core.Events, Core.Agent, Core.AgentState,
  Core.SessionManager, Core.UndoLog, Core.AgentFactory,
  AI.IModel, AI.CustomAPIAdapter, AI.ModelConfig,
  Settings.Config, Settings.SettingsManager,
  Utils.Logger, Utils.Localization, Utils.JsonHelper,
  App.Main,
  UI.WebViewBridge,
  UI.SessionChatForm,
  uWVBrowser, uWVWindowParent, uWVTypes, uWVLoader,
  uWVTypeLibrary, uWVCoreWebView2Args;

type
  TMainForm = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    FWVBrowser: TWVBrowser;
    FWVWindowParent: TWVWindowParent;
    FWebViewBridge: TWebViewBridge;
    FBrowserReady: Boolean;

    // Core services (same as before)
    FAgent: TAgent;
    FLogger: TLogger;
    FSettingsManager: TSettingsManager;
    FSessionManager: TSessionManager;
    FModelAdapter: TCustomAPIAdapter;
    FUndoLog: TUndoLog;

    FDestroying: Boolean;
    FInitTimer: TTimer;
    FTimerTickCount: Integer;
    FPopupWindows: TList;
    FPageReadyProcessed: Boolean;

    // Native loading overlay (separate form, sits on top of WebView2 HWND)
    FLoadingForm: TForm;
    FLoadingAnimTimer: TTimer;
    FLoadingDots: Integer;
    FLoadingCaption: string;

    procedure InitializeAgent;
    procedure OpenSessionPopup(const ASessionId: string);
    procedure PopupWindowClosed(Sender: TObject; var Action: TCloseAction);
    procedure BrowserCreated(Sender: TObject);
    procedure BrowserWebMessageReceived(Sender: TObject;
      const aWebView: ICoreWebView2;
      const aArgs: ICoreWebView2WebMessageReceivedEventArgs);
    procedure InitTimerTick(Sender: TObject);
    procedure DoPostJS(const AJson: string);
    procedure DoExecuteScript(const AScript: string);
    procedure LoadingPaintHandler(Sender: TObject);
    procedure LoadingAnimTimerTick(Sender: TObject);
    procedure HideLoadingOverlay;
  public
    property Agent: TAgent read FAgent;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

procedure TMainForm.FormCreate(Sender: TObject);
begin
  OutputDebugString('[PiMono] FormCreate: ENTRY');
  FDestroying := False;
  FBrowserReady := False;
  FPageReadyProcessed := False;
  FTimerTickCount := 0;
  FPopupWindows := TList.Create;

  // Core initialization (unchanged)
  OutputDebugString('[PiMono] FormCreate: InitializeApp');
  InitializeApp;
  OutputDebugString('[PiMono] FormCreate: Logger init');
  TLoggerFactory.Initialize(
    IncludeTrailingPathDelimiter(GetEnvironmentVariable('LOCALAPPDATA')) + 'PiMono\Logs');
  FLogger := TLoggerFactory.GetLogger;
  FLogger.Info('PiMono Agent starting (WebView2 UI)...');

  OutputDebugString('[PiMono] FormCreate: SettingsManager init');
  FSettingsManager := TSettingsManager.Create(FLogger);
  FSettingsManager.Initialize(GetCurrentDir);
  SetLanguage(LangFromCode(FSettingsManager.Config.UI.Language));

  OutputDebugString('[PiMono] FormCreate: SessionManager init');
  FSessionManager := TSessionManager.Create(FLogger);
  FUndoLog := TUndoLog.Create(
    GetEnvironmentVariable('LOCALAPPDATA') + '\PiMono\Cache', 100);

  // Ensure a session exists
  var Sessions := FSessionManager.ListSessions;
  if Length(Sessions) = 0 then
    FSessionManager.CreateSession(
      L('session.prefix') + FormatDateTime('yyyy-mm-dd hh:nn', Now));

  OutputDebugString('[PiMono] FormCreate: Creating WebView2 host');
  // Create WebView2 host
  FWVWindowParent := TWVWindowParent.Create(Self);
  FWVWindowParent.Parent := Self;
  FWVWindowParent.Align := alClient;
  FWVWindowParent.Visible := True;

  FWVBrowser := TWVBrowser.Create(Self);
  FWVBrowser.DefaultURL := '';
  FWVBrowser.DefaultBackgroundColor := TColor($1A1B1E);  // dark background, avoids white flash
  FWVWindowParent.Browser := FWVBrowser;
  FWVBrowser.OnAfterCreated := BrowserCreated;
  FWVBrowser.OnWebMessageReceived := BrowserWebMessageReceived;

  OutputDebugString('[PiMono] FormCreate: Creating loading overlay');
  // Create a separate borderless form as loading overlay.
  // This sits ON TOP of WebView2's native HWND (unlike VCL TPaintBox).
  FLoadingForm := TForm.Create(Self);
  FLoadingForm.BorderStyle := bsNone;
  FLoadingForm.Color := $1A1B1E;
  FLoadingForm.Position := poDesigned;
  FLoadingForm.OnPaint := LoadingPaintHandler;
  FLoadingDots := 0;
  FLoadingCaption := 'Loading';

  FLoadingAnimTimer := TTimer.Create(Self);
  FLoadingAnimTimer.Interval := 400;
  FLoadingAnimTimer.OnTimer := LoadingAnimTimerTick;
  FLoadingAnimTimer.Enabled := True;

  OutputDebugString('[PiMono] FormCreate: InitializeAgent');
  // Initialize agent (must be before bridge creation)
  InitializeAgent;

  OutputDebugString('[PiMono] FormCreate: Creating bridge');
  // Create bridge
  FWebViewBridge := TWebViewBridge.Create(
    FAgent, FLogger, FSettingsManager, FSessionManager, FUndoLog);
  FWebViewBridge.OnPostJS := DoPostJS;
  FWebViewBridge.OnExecuteScript := DoExecuteScript;
  FWebViewBridge.OnOpenPopup := OpenSessionPopup;
  FWebViewBridge.Subscribe;

  // Color the form background while WebView loads
  Self.Color := $1A1B1E;

  OutputDebugString('[PiMono] FormCreate: DONE');
  FLogger.Info('PiMono Agent initialized');
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  FDestroying := True;
  FWebViewBridge.Destroying := True;

  // Close all popup windows
  for var i := FPopupWindows.Count - 1 downto 0 do
    TSessionChatForm(FPopupWindows[i]).Close;
  FPopupWindows.Free;

  if FInitTimer <> nil then
  begin
    FInitTimer.Enabled := False;
    FreeAndNil(FInitTimer);
  end;

  if FAgent <> nil then
  begin
    FAgent.Abort;
    // Use WaitForIdle instead of busy-wait loop to avoid blocking the main thread
    FAgent.WaitForIdle(5000);
  end;

  FreeAndNil(FWebViewBridge);
  FreeAndNil(FAgent);
  FModelAdapter := nil;
  FreeAndNil(FSessionManager);
  FreeAndNil(FUndoLog);
  FreeAndNil(FSettingsManager);
  FinalizeApp;
end;

procedure TMainForm.FormShow(Sender: TObject);
begin
  FLogger.Info('FormShow: GlobalWebView2Loader.Initialized=' + BoolToStr(GlobalWebView2Loader.Initialized, True));

  // Make loading overlay a CHILD of the main form — uses client coordinates (0,0)
  // instead of screen coordinates, eliminating DPI/scale positioning issues.
  if FLoadingForm <> nil then
  begin
    FLoadingForm.Parent := Self;
    FLoadingForm.SetBounds(0, 0, Self.ClientWidth, Self.ClientHeight);
    FLoadingForm.Show;
    // Place above all child windows (including WebView2's HWND)
    SetWindowPos(FLoadingForm.Handle, HWND_TOP,
      0, 0, Self.ClientWidth, Self.ClientHeight,
      SWP_NOACTIVATE);
  end;

  if GlobalWebView2Loader = nil then
    FLogger.Error('FormShow: GlobalWebView2Loader is NIL!')
  else if GlobalWebView2Loader.Initialized then
  begin
    FLogger.Info('FormShow: Creating browser immediately');
    FWVBrowser.CreateBrowser(FWVWindowParent.Handle);
  end
  else
  begin
    FLogger.Info('FormShow: WebView2 loader not ready, starting poll timer');
    FInitTimer := TTimer.Create(Self);
    FInitTimer.Interval := 200;
    FInitTimer.OnTimer := InitTimerTick;
    FInitTimer.Enabled := True;
  end;
end;

procedure TMainForm.InitTimerTick(Sender: TObject);
begin
  Inc(FTimerTickCount);
  if GlobalWebView2Loader.Initialized then
  begin
    FInitTimer.Enabled := False;
    FreeAndNil(FInitTimer);
    FLogger.Info('InitTimerTick: Loader ready after ' + IntToStr(FTimerTickCount) + ' ticks, creating browser');
    FWVBrowser.CreateBrowser(FWVWindowParent.Handle);
  end
  else if FTimerTickCount >= 50 then  // 10 seconds timeout
  begin
    FInitTimer.Enabled := False;
    FreeAndNil(FInitTimer);
    FLogger.Error('InitTimerTick: WebView2 loader FAILED to initialize after 10s. WebView2 Runtime may not be installed.');
  end;
end;

procedure TMainForm.DoPostJS(const AJson: string);
begin
  if not FBrowserReady then
  begin
    FLogger.Warn('DoPostJS: SKIPPED - browser not ready');
    Exit;
  end;
  if FWVBrowser = nil then
  begin
    FLogger.Warn('DoPostJS: SKIPPED - FWVBrowser is nil');
    Exit;
  end;
  // Use ExecuteScript + __dispatchBridgeEvent instead of PostWebMessageAsJson.
  // PostWebMessageAsJson was silently dropping messages at runtime; ExecuteScript
  // has proven reliable for delivering events to the JS bridge.
  FWVBrowser.ExecuteScript(
    'if(typeof __dispatchBridgeEvent==="function")__dispatchBridgeEvent(' + AJson + ')');
end;

procedure TMainForm.DoExecuteScript(const AScript: string);
begin
  if not FBrowserReady or (FWVBrowser = nil) then Exit;
  FWVBrowser.ExecuteScript(AScript);
end;

procedure TMainForm.BrowserCreated(Sender: TObject);
var
  WebUIFolder: string;
begin
  OutputDebugString('[PiMono] BrowserCreated: ENTRY');
  FBrowserReady := True;

  // NOTE: Do NOT hide loading overlay here!
  // WebView2 hasn't loaded HTML yet — it would show a white screen.
  // The overlay is hidden in BrowserWebMessageReceived when page_ready arrives.

  // CRITICAL: Set WebView2 controller bounds to match parent control.
  // Without this, the controller has zero-sized bounds (0,0,0,0) and renders nothing.
  // All WebView4Delphi demos call UpdateSize in OnAfterCreated.
  FWVWindowParent.UpdateSize;

  FLogger.Info('BrowserCreated: WebView2 browser created successfully');

  // Clear WebView2 disk cache to prevent stale CSS/JS from being served.
  // Virtual host mapping files can be cached aggressively by WebView2.
  try
    FWVBrowser.CallDevToolsProtocolMethod('Network.clearBrowserCache', '{}');
    FLogger.Info('BrowserCreated: cleared WebView2 browser cache');
  except
    on E: Exception do
      FLogger.Warn('BrowserCreated: cache clear failed: ' + E.Message);
  end;

  // Use virtual host mapping instead of file:/// for reliable local file serving
  WebUIFolder := ExtractFilePath(Application.ExeName) + 'WebUI';
  FLogger.Info('BrowserCreated: Looking for WebUI at: ' + WebUIFolder);
  if DirectoryExists(WebUIFolder) then
  begin
    FWVBrowser.SetVirtualHostNameToFolderMapping(
      'pimono.local', WebUIFolder, COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_ALLOW);
    FLogger.Info('BrowserCreated: Navigating to https://pimono.local/index.html');

    FWVBrowser.Navigate('https://pimono.local/index.html?t=' + IntToStr(DateTimeToUnix(Now, False)));
    OutputDebugString('[PiMono] BrowserCreated: Navigate called, DONE');
  end
  else
  begin
    FLogger.Error('BrowserCreated: WebUI folder NOT FOUND at: ' + WebUIFolder);
    FWVBrowser.NavigateToString(
      '<html><body style="background:#1a1b1e;color:#f0f0f0;font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh">' +
      '<h2>PiMono Agent</h2><p style="color:#999">WebUI folder not found at: ' + WebUIFolder + '</p></body></html>');
  end;
end;

procedure TMainForm.BrowserWebMessageReceived(Sender: TObject;
  const aWebView: ICoreWebView2;
  const aArgs: ICoreWebView2WebMessageReceivedEventArgs);
var
  TempData: TCoreWebView2WebMessageReceivedEventArgs;
  Msg: string;
begin
  TempData := TCoreWebView2WebMessageReceivedEventArgs.Create(aArgs);
  try
    Msg := TempData.WebMessageAsJson;
    if Msg = '' then Exit;

    FLogger.Debug('WebMsgRecv: raw=' + Copy(Msg, 1, 200));

    // Unwrap JSON string encoding
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
        FLogger.Warn('WebMsgRecv: failed to parse outer JSON string');
        Exit;
      end;
    end;

    // Check for page_ready signal (handled locally for loading overlay)
    try
      var Json := TJSONObject.ParseJSONValue(Msg) as TJSONObject;
      if Json <> nil then
      try
        var Action: string;
        if Json.TryGetValue<string>('action', Action) then
        begin
          if Action = 'page_ready' then
          begin
            if FPageReadyProcessed then Exit;
            FPageReadyProcessed := True;
            HideLoadingOverlay;
            FWebViewBridge.SendInitialState;
            Exit;
          end;
          FWebViewBridge.HandleWebMessage(Msg);
        end;
      finally
        Json.Free;
      end;
    except
      on E: Exception do
        FLogger.Error('WebMsgRecv: ' + E.Message);
    end;
  finally
    TempData.Free;
  end;
end;

procedure TMainForm.InitializeAgent;
begin
  FAgent := TAgentFactory.CreateAgent(FLogger, FSettingsManager, FUndoLog);
  TAgentFactory.ConnectModel(FAgent, FSettingsManager, FLogger, FModelAdapter);
end;

procedure TMainForm.OpenSessionPopup(const ASessionId: string);
var
  Popup: TSessionChatForm;
  i: Integer;
begin
  // Check if popup already exists for this session
  for i := 0 to FPopupWindows.Count - 1 do
  begin
    if TSessionChatForm(FPopupWindows[i]).SessionId = ASessionId then
    begin
      TSessionChatForm(FPopupWindows[i]).BringToFront;
      Exit;
    end;
  end;

  // Limit max popup windows
  if FPopupWindows.Count >= 5 then
  begin
    FLogger.Warn('OpenSessionPopup: max popup limit (5) reached');
    Exit;
  end;

  FLogger.Info('OpenSessionPopup: creating popup for session ' + ASessionId);
  Popup := TSessionChatForm.Create(
    Self, ASessionId, FLogger, FSettingsManager, FSessionManager, FUndoLog);
  Popup.OnClose := PopupWindowClosed;
  Popup.Show;
  FPopupWindows.Add(Popup);
end;

procedure TMainForm.PopupWindowClosed(Sender: TObject; var Action: TCloseAction);
begin
  if Sender <> nil then
  begin
    FPopupWindows.Remove(Sender);
    FLogger.Info('PopupWindowClosed: remaining popups=' + IntToStr(FPopupWindows.Count));
  end;
end;

procedure TMainForm.LoadingPaintHandler(Sender: TObject);
var
  CX, CY, R: Integer;
  Canvas: TCanvas;
begin
  Canvas := FLoadingForm.Canvas;
  CX := FLoadingForm.ClientWidth div 2;
  CY := FLoadingForm.ClientHeight div 2;

  // Dark background
  Canvas.Brush.Color := $1A1B1E;
  Canvas.FillRect(FLoadingForm.ClientRect);

  // Logo square border (cyan)
  Canvas.Pen.Color := $00F0FF;
  Canvas.Pen.Width := 2;
  Canvas.Brush.Style := bsClear;
  R := 28;
  Canvas.Rectangle(CX - R, CY - R - 10, CX + R, CY + R - 10);

  // "P" letter inside square
  Canvas.Font.Name := 'Consolas';
  Canvas.Font.Size := 28;
  Canvas.Font.Color := $00F0FF;
  Canvas.Font.Style := [fsBold];
  Canvas.TextOut(CX - Canvas.TextWidth('P') div 2, CY - R - 4, 'P');

  // Loading text with animated dots below
  Canvas.Font.Size := 11;
  Canvas.Font.Color := $6A6A4A;
  Canvas.Font.Style := [];
  Canvas.TextOut(CX - Canvas.TextWidth(FLoadingCaption) div 2, CY + R + 10, FLoadingCaption);
end;

procedure TMainForm.LoadingAnimTimerTick(Sender: TObject);
begin
  Inc(FLoadingDots);
  if FLoadingDots > 3 then FLoadingDots := 0;
  FLoadingCaption := 'Loading' + StringOfChar('.', FLoadingDots);
  if FLoadingForm <> nil then
    FLoadingForm.Repaint;
end;

procedure TMainForm.HideLoadingOverlay;
begin
  if FLoadingAnimTimer <> nil then
  begin
    FLoadingAnimTimer.Enabled := False;
    FreeAndNil(FLoadingAnimTimer);
  end;
  if FLoadingForm <> nil then
  begin
    FLoadingForm.Close;
    FreeAndNil(FLoadingForm);
  end;
end;

initialization
  // Clear WebView2 disk cache to prevent stale CSS/JS from being served.
  // Default cache location when UserDataFolder is empty: <exe_dir>\<exename>.WebView2\EBWebView\Cache
  begin
    var LCacheDir := ExtractFilePath(ParamStr(0)) + ChangeFileExt(ExtractFileName(ParamStr(0)), '') +
                     '.WebView2\EBWebView\Cache';
    if DirectoryExists(LCacheDir) then
      try TDirectory.Delete(LCacheDir, True); except end;
  end;

  // Create and start the global WebView2 loader
  OutputDebugString('[PiMono] initialization: Creating GlobalWebView2Loader');
  GlobalWebView2Loader := TWVLoader.Create(nil);
  GlobalWebView2Loader.UserDataFolder := '';
  GlobalWebView2Loader.BrowserExecPath := ''; // empty = use evergreen runtime
  GlobalWebView2Loader.AllowFileAccessFromFiles := True;  // allow CSS/JS loading from file:/// protocol
  OutputDebugString('[PiMono] initialization: Calling StartWebView2');
  GlobalWebView2Loader.StartWebView2;
  OutputDebugString('[PiMono] initialization: StartWebView2 returned');

finalization
  // WebView4Delphi handles GlobalWebView2Loader destruction automatically

end.
