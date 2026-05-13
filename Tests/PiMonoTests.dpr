program PiMonoTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Winapi.Windows,

  // Test framework (self-contained, no DUnitX dependency)
  PiMonoTestFramework in 'PiMonoTestFramework.pas',

  // Source units under test
  Core.Messages in '..\Core\Core.Messages.pas',
  Core.AgentState in '..\Core\Core.AgentState.pas',
  Core.Events in '..\Core\Core.Events.pas',
  Core.UndoLog in '..\Core\Core.UndoLog.pas',
  Core.SessionManager in '..\Core\Core.SessionManager.pas',
  Core.Compaction in '..\Core\Core.Compaction.pas',
  Core.ToolResultSlim in '..\Core\Core.ToolResultSlim.pas',
  Core.Agent in '..\Core\Core.Agent.pas',
  App.Main in '..\Core\App.Main.pas',
  Settings.Config in '..\Settings\Settings.Config.pas',
  Settings.SettingsManager in '..\Settings\Settings.SettingsManager.pas',
  Settings.SkillStore in '..\Settings\Settings.SkillStore.pas',
  Tools.ITool in '..\Tools\Tools.ITool.pas',
  Tools.ToolRegistry in '..\Tools\Tools.ToolRegistry.pas',
  Tools.FileTools in '..\Tools\Tools.FileTools.pas',
  Tools.BashTool in '..\Tools\Tools.BashTool.pas',
  Tools.CommandRunner in '..\Tools\Tools.CommandRunner.pas',
  Tools.GitTool in '..\Tools\Tools.GitTool.pas',
  Tools.WebSearchTool in '..\Tools\Tools.WebSearchTool.pas',
  AI.IModel in '..\AI\AI.IModel.pas',
  AI.CustomAPIAdapter in '..\AI\AI.CustomAPIAdapter.pas',
  AI.ModelConfig in '..\AI\AI.ModelConfig.pas',
  Utils.JsonHelper in '..\Utils\Utils.JsonHelper.pas',
  Utils.Localization in '..\Utils\Utils.Localization.pas',
  Utils.Logger in '..\Utils\Utils.Logger.pas',
  Utils.TokenEstimator in '..\Utils\Utils.TokenEstimator.pas',
  Utils.Markdown in '..\Utils\Utils.Markdown.pas',

  // Source units for UI/HGM/Utils tests
  UI.Spacing in '..\UI\UI.Spacing.pas',
  UI.ThemeManager in '..\UI\UI.ThemeManager.pas',
  HGM.Common.Utils in '..\HGM\HGM.Common.Utils.pas',
  HGM.Utils.Color in '..\HGM\HGM.Utils.Color.pas',
  Utils.SvgIcons in '..\Utils\Utils.SvgIcons.pas',
  Utils.SkiaDraw in '..\Utils\Utils.SkiaDraw.pas',
  UI.WebViewBridge in '..\UI\UI.WebViewBridge.pas',

  // Mocks
  MockModel in 'Mocks\MockModel.pas',

  // Test units
  TestSecurity in 'Tools\TestSecurity.pas',
  TestSSEStream in 'AI\TestSSEStream.pas',
  TestMessages in 'Core\TestMessages.pas',
  TestUndoLog in 'Core\TestUndoLog.pas',
  TestEvents in 'Core\TestEvents.pas',
  TestSessionManager in 'Core\TestSessionManager.pas',
  TestCompactionAndSlim in 'Core\TestCompactionAndSlim.pas',
  TestFileTools in 'Tools\TestFileTools.pas',
  TestToolRegistry in 'Tools\TestToolRegistry.pas',
  TestWebSearchTool in 'Tools\TestWebSearchTool.pas',
  TestCommandRunner in 'Tools\TestCommandRunner.pas',
  TestConfig in 'Settings\TestConfig.pas',
  TestSettingsManager in 'Settings\TestSettingsManager.pas',
  TestSkillStore in 'Settings\TestSkillStore.pas',
  TestHelpers in 'Utils\TestHelpers.pas',
  TestMarkdown in 'Utils\TestMarkdown.pas',
  TestUtilsLogger in 'Utils\TestUtilsLogger.pas',
  TestAgent in 'Core\TestAgent.pas',
  TestGitTool in 'Core\TestGitTool.pas',
  TestAppMain in 'Core\TestAppMain.pas',
  TestModelConfig in 'AI\TestModelConfig.pas',

  // New test units
  TestSpacing in 'UI\TestSpacing.pas',
  TestThemeManager in 'UI\TestThemeManager.pas',
  TestHGMUtils in 'HGM\TestHGMUtils.pas',
  TestHGMColor in 'HGM\TestHGMColor.pas',
  TestSvgIcons in 'Utils\TestSvgIcons.pas',
  TestSkiaDraw in 'Utils\TestSkiaDraw.pas',
  TestWebViewBridgeInteraction in 'UI\TestWebViewBridgeInteraction.pas';

procedure Main;
begin
  Writeln('=== PiMono Test Suite ===');
  Writeln;

  // Register and run all tests from each unit
  RegisterSecurityTests;
  RegisterMessageTests;
  RegisterUndoLogTests;
  RegisterEventTests;
  RegisterSessionManagerTests;
  RegisterCompactionAndSlimTests;
  RegisterFileToolsTests;
  RegisterToolRegistryTests;
  RegisterWebSearchToolTests;
  RegisterCommandRunnerTests;
  RegisterConfigTests;
  RegisterSettingsManagerTests;
  RegisterSkillStoreTests;
  RegisterHelperTests;
  RegisterMarkdownTests;
  RegisterUtilsLoggerTests;
  RegisterAgentTests;
  RegisterGitToolTests;
  RegisterAppMainTests;
  RegisterModelConfigTests;
  RegisterSSEStreamTests;

  // New test registrations
  RegisterSpacingTests;
  RegisterThemeManagerTests;
  RegisterHGMUtilsTests;
  RegisterHGMColorTests;
  RegisterSvgIconsTests;
  RegisterSkiaDrawTests;

  // Interaction tests
  RegisterWebViewBridgeInteractionTests;

  // Print results
  GRunner.PrintResults;

  if GRunner.AllPassed then
    Writeln('ALL TESTS PASSED!')
  else
    Writeln('SOME TESTS FAILED!');

  {$IFNDEF CI}
  Writeln;
  Write('Press Enter to quit...');
  Readln;
  {$ENDIF}

  if not GRunner.AllPassed then
    ExitCode := 1;
end;

begin
  try
    Main;
  except
    on E: Exception do
    begin
      Writeln('FATAL: ', E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
end.
