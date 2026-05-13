; ============================================================
; PiMono Inno Setup 安装脚本
; 用法: 用 Inno Setup Compiler 打开此文件并编译
; 下载: https://jrsoftware.org/isdl.php
; ============================================================

#define MyAppName "PiMono"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "PiMono"
#define MyAppExeName "PiMono.exe"
#define MyAppDescription "AI Agent Desktop Client"

[Setup]
; 基本信息
AppId={{B8E3F2A1-5D4C-4E7F-9A6B-1C2D3E4F5A6B}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL=https://github.com/pimono
AppSupportURL=https://github.com/pimono
AppUpdatesURL=https://github.com/pimono

; 安装目录
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}

; 输出设置
OutputDir=Output
OutputBaseFilename=PiMono-Setup-{#MyAppVersion}
SetupIconFile=
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern

; 权限 (不需要管理员权限，安装到用户目录即可)
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog

; 界面
UninstallDisplayIcon={app}\{#MyAppExeName}
ArchitecturesAllowed=x86compatible
ArchitecturesInstallIn64BitMode=

; 许可协议 (可选，如果以后有 LICENSE 文件可以取消注释)
; LicenseFile=..\LICENSE

; 安装界面语言
ShowLanguageDialog=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "startmenuicon"; Description: "创建开始菜单快捷方式"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; 主程序
Source: "{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion

; WebView2 加载器 DLL
Source: "WebView2Loader.dll"; DestDir: "{app}"; Flags: ignoreversion

; WebUI 前端资源（整个目录）
Source: "WebUI\*"; DestDir: "{app}\WebUI"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: startmenuicon
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"; Tasks: startmenuicon
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\WebUI"
Type: filesandordirs; Name: "{app}\PiMono.exe.WebView2"
Type: files; Name: "{app}\{#MyAppExeName}"
Type: files; Name: "{app}\WebView2Loader.dll"

; ============================================================
; WebView2 Runtime 自动检测与安装
; ============================================================
[Code]

const
  WebView2BootstrapperUrl = 'https://go.microsoft.com/fwlink/p/?LinkId=2124703';

var
  DownloadPage: TDownloadWizardPage;

// 检查 WebView2 Runtime 是否已安装
function IsWebView2Installed: Boolean;
begin
  Result := RegKeyExists(HKLM, 'SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BEB-27B8B8F1D557}') or
            RegKeyExists(HKLM, 'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BEB-27B8B8F1D557}') or
            RegKeyExists(HKCU, 'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BEB-27B8B8F1D557}');
end;

// 初始化安装向导
procedure InitializeWizard;
begin
  DownloadPage := CreateDownloadPage(SetupMessage(msgWizardPreparing), SetupMessage(msgPreparingDesc), nil);
end;

// 下载并静默安装 WebView2 Runtime
function InstallWebView2: Boolean;
var
  ResultCode: Integer;
begin
  Result := False;

  DownloadPage.Clear;
  DownloadPage.Add(WebView2BootstrapperUrl, 'MicrosoftEdgeWebview2Setup.exe', '');
  DownloadPage.Show;

  try
    try
      DownloadPage.Download;
      Result := True;
    except
      SuppressibleMsgBox(AddPeriod(GetExceptionMessage), mbCriticalError, MB_OK, IDOK);
      Exit;
    end;
  finally
    DownloadPage.Hide;
  end;

  // 运行 WebView2 安装程序（可见模式，由它自己处理下载和安装）
  MsgBox('PiMono 需要 Microsoft Edge WebView2 Runtime。'#13#10#13#10 +
         '点击"确定"开始安装 WebView2 Runtime，'#13#10 +
         '请按照提示完成安装后继续。',
         mbInformation, MB_OK);

  ResultCode := 0;
  if ShellExec('', ExpandConstant('{tmp}\MicrosoftEdgeWebview2Setup.exe'), '/install', '', SW_SHOWNORMAL, ewWaitUntilTerminated, ResultCode) then
  begin
    if ResultCode <> 0 then
    begin
      MsgBox('WebView2 Runtime 安装未成功。'#13#10#13#10 +
             '请稍后手动下载安装:'#13#10 +
             'https://go.microsoft.com/fwlink/p/?LinkId=2124703',
             mbError, MB_OK);
      Result := False;
    end
    else
      Result := True;
  end
  else
  begin
    MsgBox('无法运行 WebView2 Runtime 安装程序。'#13#10#13#10 +
           '请手动下载安装:'#13#10 +
           'https://go.microsoft.com/fwlink/p/?LinkId=2124703',
           mbError, MB_OK);
  end;
end;

// 准备安装阶段检查 WebView2
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
  begin
    if not IsWebView2Installed then
    begin
      InstallWebView2;
    end;
  end;
end;

// 卸载确认
function InitializeUninstall: Boolean;
begin
  Result := True;
  if MsgBox('确定要卸载 PiMono 吗？', mbConfirmation, MB_YESNO) = IDNO then
    Result := False;
end;
