program PiMono;

{$R *.res}

uses
  Winapi.Windows,
  Vcl.Forms,
  App.Main in 'Core\App.Main.pas',
  Core.Agent in 'Core\Core.Agent.pas',
  Core.AgentState in 'Core\Core.AgentState.pas',
  Core.AgentFactory in 'Core\Core.AgentFactory.pas',
  Core.SessionManager in 'Core\Core.SessionManager.pas',
  Core.Messages in 'Core\Core.Messages.pas',
  Core.Events in 'Core\Core.Events.pas',
  AI.IModel in 'AI\AI.IModel.pas',
  AI.CustomAPIAdapter in 'AI\AI.CustomAPIAdapter.pas',
  AI.ModelConfig in 'AI\AI.ModelConfig.pas',
  Tools.ITool in 'Tools\Tools.ITool.pas',
  Tools.ToolRegistry in 'Tools\Tools.ToolRegistry.pas',
  Tools.FileTools in 'Tools\Tools.FileTools.pas',
  Tools.BashTool in 'Tools\Tools.BashTool.pas',
  Tools.GitTool in 'Tools\Tools.GitTool.pas',
  Tools.WebSearchTool in 'Tools\Tools.WebSearchTool.pas',
  Tools.CommandRunner in 'Tools\Tools.CommandRunner.pas',
  Core.UndoLog in 'Core\Core.UndoLog.pas',
  Utils.Markdown in 'Utils\Utils.Markdown.pas',
  Settings.Config in 'Settings\Settings.Config.pas',
  Settings.SettingsManager in 'Settings\Settings.SettingsManager.pas',
  Settings.SkillStore in 'Settings\Settings.SkillStore.pas',
  UI.MainForm in 'UI\UI.MainForm.pas' {MainForm},
  Utils.Logger in 'Utils\Utils.Logger.pas',
  Utils.JsonHelper in 'Utils\Utils.JsonHelper.pas',
  Utils.Localization in 'Utils\Utils.Localization.pas',
  Utils.TokenEstimator in 'Utils\Utils.TokenEstimator.pas',
  Core.ToolResultSlim in 'Core\Core.ToolResultSlim.pas',
  Core.Compaction in 'Core\Core.Compaction.pas',
  UI.WebViewBridge in 'UI\UI.WebViewBridge.pas',
  UI.SessionChatForm in 'UI\UI.SessionChatForm.pas' {SessionChatForm};

begin
  OutputDebugString(PChar('[PiMono] dpr: Application.Initialize START'));
  Application.Initialize;
  OutputDebugString(PChar('[PiMono] dpr: Application.CreateForm START'));
  Application.MainFormOnTaskbar := True;
  Application.Title := 'PiMono Agent';
  Application.CreateForm(TMainForm, MainForm);
  OutputDebugString(PChar('[PiMono] dpr: Application.CreateForm DONE'));
  Application.Run;
end.
