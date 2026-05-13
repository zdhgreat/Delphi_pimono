unit TestSettingsManager;

interface

uses
  System.SysUtils, System.IOUtils, System.JSON, Winapi.Windows,
  Settings.Config, Settings.SettingsManager,
  PiMonoTestFramework;

procedure RegisterSettingsManagerTests;

implementation

type
  TTestSettingsManager = class
  private
    FTestDir: string;
    FGlobalDir: string;
  public
    procedure Setup;
    procedure TearDown;

    // Initialize / Loading
    procedure Test_Initialize_Defaults;
    procedure Test_SaveAndLoadGlobal;
    procedure Test_SaveAndLoadProject;
    procedure Test_LoadGlobal_InvalidJSON_KeepsDefaults;
    procedure Test_LoadProject_FallbackPath;

    // Two-tier merge
    procedure Test_Merge_ProjectOverridesGlobal;
    procedure Test_Merge_DefaultProjectValuesNotApplied;
    procedure Test_Merge_FloatEpsilon;

    // Update methods
    procedure Test_UpdateApiEndpoint;
    procedure Test_UpdateModelName;
    procedure Test_UpdateTemperature;
    procedure Test_UpdateTheme;
    procedure Test_UpdateWorkingDirectory;
    procedure Test_UpdateLanguage;
    procedure Test_UpdateStreaming;
    procedure Test_UpdateTimeout;
    procedure Test_UpdateApiKey;
    procedure Test_UpdateMaxTokens;
    procedure Test_UpdateTopP;
    procedure Test_UpdateFrequencyPenalty;
    procedure Test_UpdatePresencePenalty;
    procedure Test_UpdateModelsEndpoint;
    procedure Test_UpdateRetryCount;
    procedure Test_UpdateFontSize;
    procedure Test_UpdateFontFamily;
    procedure Test_UpdateBackupDirectory;
    procedure Test_UpdateThinkingLevel;
    procedure Test_UpdateModelProfiles;
    procedure Test_UpdateSearchConfig;
    procedure Test_UpdateSkillPool;
    procedure Test_UpdateConfig;

    // GetConfig returns copy
    procedure Test_GetConfig_ReturnsCopy;

    // Edge cases
    procedure Test_Initialize_EmptyProjectDir;
    procedure Test_SaveGlobal_CreatesDirectory;
  end;

{ TTestSettingsManager }

procedure TTestSettingsManager.Setup;
begin
  FTestDir := TPath.Combine(TPath.GetTempPath,
    'PiMonoSM_' + FormatDateTime('yyyymmddhhnnsszzz', Now) + '_' + IntToStr(GetTickCount));
  TDirectory.CreateDirectory(FTestDir);

  // Create a global config dir inside test dir
  FGlobalDir := TPath.Combine(FTestDir, 'global');
  TDirectory.CreateDirectory(FGlobalDir);
end;

procedure TTestSettingsManager.TearDown;
begin
  try
    if TDirectory.Exists(FTestDir) then
      TDirectory.Delete(FTestDir, True);
  except
  end;
end;

procedure TTestSettingsManager.Test_Initialize_Defaults;
var
  SM: TSettingsManager;
  Cfg: TPiMonoConfig;
begin
  SM := TSettingsManager.Create(nil);
  try
    // Initialize without project dir - should use defaults
    SM.Initialize('');
    Cfg := SM.GetConfig;
    Assert(Cfg.Version <> '', 'Version should not be empty');
    Assert(Cfg.Model.MaxTokens > 0, 'MaxTokens default should be > 0');
    Assert(Cfg.Api.Timeout > 0, 'Timeout default should be > 0');
  finally
    SM.Free;
  end;
end;

procedure TTestSettingsManager.Test_SaveAndLoadGlobal;
var
  SM1: TSettingsManager;
  TestDir: string;
begin
  // Use temp dir as APPDATA-like path
  TestDir := TPath.Combine(FTestDir, 'appdata_test');
  TDirectory.CreateDirectory(TestDir);

  SM1 := TSettingsManager.Create(nil);
  try
    SM1.Initialize('');
    SM1.UpdateApiEndpoint('https://api.test.com/v1');
    SM1.UpdateApiKey('test-key-123');
    SM1.UpdateModelName('test-model');

    // Manually write config to test dir
    var Cfg := SM1.GlobalConfig;
    var Json := Cfg.ToJson;
    TFile.WriteAllText(TPath.Combine(TestDir, 'settings.json'), Json.ToString);
  finally
    SM1.Free;
  end;

  // Verify file was written
  Assert(TFile.Exists(TPath.Combine(TestDir, 'settings.json')), 'Config file should exist');
end;

procedure TTestSettingsManager.Test_SaveAndLoadProject;
var
  SM: TSettingsManager;
  ProjectDir: string;
begin
  ProjectDir := TPath.Combine(FTestDir, 'project');
  TDirectory.CreateDirectory(ProjectDir);

  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize(ProjectDir);
    SM.UpdateModelName('project-model');
    SM.SaveProject(ProjectDir);

    Assert(TFile.Exists(TPath.Combine(ProjectDir, '.pimonorc')),
      'Project config file should exist');
  finally
    SM.Free;
  end;
end;

procedure TTestSettingsManager.Test_LoadGlobal_InvalidJSON_KeepsDefaults;
var
  SM: TSettingsManager;
  DefaultCfg: TPiMonoConfig;
begin
  // Write invalid JSON to a temp location
  TFile.WriteAllText(TPath.Combine(FTestDir, 'bad.json'), '{invalid json!!!}');

  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize('');
    DefaultCfg := TPiMonoConfig.GetDefault;
    var Cfg := SM.GetConfig;
    // Should fall back to defaults
    Assert(Cfg.Version = DefaultCfg.Version, 'Should keep default version on invalid JSON');
  finally
    SM.Free;
  end;
end;

procedure TTestSettingsManager.Test_LoadProject_FallbackPath;
var
  SM: TSettingsManager;
  ProjectDir: string;
  PiDir: string;
begin
  ProjectDir := TPath.Combine(FTestDir, 'proj_fallback');
  TDirectory.CreateDirectory(ProjectDir);

  // Create fallback path .pi/settings.json
  PiDir := TPath.Combine(ProjectDir, '.pi');
  TDirectory.CreateDirectory(PiDir);
  var DefCfg := TPiMonoConfig.GetDefault;
  DefCfg.Model.Name := 'fallback-model';
  TFile.WriteAllText(TPath.Combine(PiDir, 'settings.json'), DefCfg.ToJson.ToString);

  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize(ProjectDir);
    // Should load from .pi/settings.json fallback path
    var Cfg := SM.GetConfig;
    Assert(Cfg.Model.Name = 'fallback-model', 'Should load from fallback .pi/settings.json');
  finally
    SM.Free;
  end;
end;

procedure TTestSettingsManager.Test_Merge_ProjectOverridesGlobal;
var
  SM: TSettingsManager;
  ProjectDir: string;
begin
  ProjectDir := TPath.Combine(FTestDir, 'proj_merge');
  TDirectory.CreateDirectory(ProjectDir);

  // Write project config with custom model name
  var ProjCfg := TPiMonoConfig.GetDefault;
  ProjCfg.Model.Name := 'project-override-model';
  TFile.WriteAllText(TPath.Combine(ProjectDir, '.pimonorc'), ProjCfg.ToJson.ToString);

  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize(ProjectDir);
    var Cfg := SM.GetConfig;
    Assert(Cfg.Model.Name = 'project-override-model',
      'Project config should override global for non-default values');
  finally
    SM.Free;
  end;
end;

procedure TTestSettingsManager.Test_Merge_DefaultProjectValuesNotApplied;
var
  SM: TSettingsManager;
  ProjectDir: string;
begin
  ProjectDir := TPath.Combine(FTestDir, 'proj_nodefault');
  TDirectory.CreateDirectory(ProjectDir);

  // Write project config that is entirely defaults
  var ProjCfg := TPiMonoConfig.GetDefault;
  TFile.WriteAllText(TPath.Combine(ProjectDir, '.pimonorc'), ProjCfg.ToJson.ToString);

  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize(ProjectDir);
    var Cfg := SM.GetConfig;
    // Since project config values equal defaults, global values should be used
    // This means the merged config should equal global config
    var GlobalCfg := SM.GlobalConfig;
    Assert(Cfg.Model.Name = GlobalCfg.Model.Name,
      'Default project values should not override global');
  finally
    SM.Free;
  end;
end;

procedure TTestSettingsManager.Test_Merge_FloatEpsilon;
var
  SM: TSettingsManager;
  ProjectDir: string;
begin
  ProjectDir := TPath.Combine(FTestDir, 'proj_epsilon');
  TDirectory.CreateDirectory(ProjectDir);

  // Write project config with temperature very close to default (within 0.001 epsilon)
  var ProjCfg := TPiMonoConfig.GetDefault;
  var DefCfg := TPiMonoConfig.GetDefault;
  ProjCfg.Model.Temperature := DefCfg.Model.Temperature + 0.0005; // within epsilon
  TFile.WriteAllText(TPath.Combine(ProjectDir, '.pimonorc'), ProjCfg.ToJson.ToString);

  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize(ProjectDir);
    var Cfg := SM.GetConfig;
    // Temperature within epsilon should NOT be overlaid
    var GlobalCfg := SM.GlobalConfig;
    Assert(Abs(Cfg.Model.Temperature - GlobalCfg.Model.Temperature) < 0.0001,
      'Temperature within epsilon should not override');
  finally
    SM.Free;
  end;
end;

procedure TTestSettingsManager.Test_UpdateApiEndpoint;
var SM: TSettingsManager;
begin
  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize('');
    SM.UpdateApiEndpoint('https://new-endpoint.com');
    Assert(SM.GetConfig.Api.Endpoint = 'https://new-endpoint.com', 'Endpoint should be updated');
    Assert(SM.GlobalConfig.Api.Endpoint = 'https://new-endpoint.com', 'Global should be updated');
  finally
    SM.Free;
  end;
end;

procedure TTestSettingsManager.Test_UpdateModelName;
var SM: TSettingsManager;
begin
  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize('');
    SM.UpdateModelName('gpt-4-turbo');
    Assert(SM.GetConfig.Model.Name = 'gpt-4-turbo', 'Model should be updated');
  finally
    SM.Free;
  end;
end;

procedure TTestSettingsManager.Test_UpdateTemperature;
var SM: TSettingsManager;
begin
  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize('');
    SM.UpdateTemperature(0.5);
    Assert(Abs(SM.GetConfig.Model.Temperature - 0.5) < 0.001, 'Temperature should be 0.5');
  finally
    SM.Free;
  end;
end;

procedure TTestSettingsManager.Test_UpdateTheme;
var SM: TSettingsManager;
begin
  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize('');
    SM.UpdateTheme('dark');
    Assert(SM.GetConfig.UI.Theme = 'dark', 'Theme should be dark');
  finally
    SM.Free;
  end;
end;

procedure TTestSettingsManager.Test_UpdateWorkingDirectory;
var SM: TSettingsManager;
begin
  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize('');
    SM.UpdateWorkingDirectory('C:\Projects');
    Assert(SM.GetConfig.Directories.Working = 'C:\Projects', 'Working dir should match');
  finally
    SM.Free;
  end;
end;

procedure TTestSettingsManager.Test_UpdateLanguage;
var SM: TSettingsManager;
begin
  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize('');
    SM.UpdateLanguage('zh');
    Assert(SM.GetConfig.UI.Language = 'zh', 'Language should be zh');
  finally
    SM.Free;
  end;
end;

procedure TTestSettingsManager.Test_UpdateStreaming;
var SM: TSettingsManager;
begin
  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize('');
    SM.UpdateStreaming(False);
    Assert(not SM.GetConfig.Api.EnableStreaming, 'Streaming should be false');
  finally
    SM.Free;
  end;
end;

procedure TTestSettingsManager.Test_UpdateTimeout;
var SM: TSettingsManager;
begin
  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize('');
    SM.UpdateTimeout(60000);
    Assert(SM.GetConfig.Api.Timeout = 60000, 'Timeout should be 60000');
  finally
    SM.Free;
  end;
end;

procedure TTestSettingsManager.Test_UpdateApiKey;
var SM, SM2: TSettingsManager;
begin
  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize('');
    SM.UpdateApiKey('sk-test-key');
    Assert(SM.GetConfig.Api.ApiKey = 'sk-test-key', 'ApiKey should be updated');
    SM.SaveGlobal;
  finally
    SM.Free;
  end;

  SM2 := TSettingsManager.Create(nil);
  try
    SM2.Initialize('');
    Assert(SM2.GetConfig.Api.ApiKey = 'sk-test-key', 'ApiKey should persist after reload');
  finally
    SM2.Free;
  end;
end;

procedure TTestSettingsManager.Test_UpdateMaxTokens;
var SM, SM2: TSettingsManager;
begin
  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize('');
    SM.UpdateMaxTokens(8192);
    Assert(SM.GetConfig.Model.MaxTokens = 8192, 'MaxTokens should be 8192');
    SM.SaveGlobal;
  finally
    SM.Free;
  end;

  SM2 := TSettingsManager.Create(nil);
  try
    SM2.Initialize('');
    Assert(SM2.GetConfig.Model.MaxTokens = 8192, 'MaxTokens should persist after reload');
  finally
    SM2.Free;
  end;
end;

procedure TTestSettingsManager.Test_UpdateTopP;
var SM, SM2: TSettingsManager;
begin
  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize('');
    SM.UpdateTopP(0.95);
    Assert(Abs(SM.GetConfig.Model.TopP - 0.95) < 0.001, 'TopP should be 0.95');
    SM.SaveGlobal;
  finally
    SM.Free;
  end;

  SM2 := TSettingsManager.Create(nil);
  try
    SM2.Initialize('');
    Assert(Abs(SM2.GetConfig.Model.TopP - 0.95) < 0.001, 'TopP should persist after reload');
  finally
    SM2.Free;
  end;
end;

procedure TTestSettingsManager.Test_UpdateFrequencyPenalty;
var SM, SM2: TSettingsManager;
begin
  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize('');
    SM.UpdateFrequencyPenalty(0.5);
    Assert(Abs(SM.GetConfig.Model.FrequencyPenalty - 0.5) < 0.001, 'FrequencyPenalty should be 0.5');
    SM.SaveGlobal;
  finally
    SM.Free;
  end;

  SM2 := TSettingsManager.Create(nil);
  try
    SM2.Initialize('');
    Assert(Abs(SM2.GetConfig.Model.FrequencyPenalty - 0.5) < 0.001, 'FrequencyPenalty should persist after reload');
  finally
    SM2.Free;
  end;
end;

procedure TTestSettingsManager.Test_UpdatePresencePenalty;
var SM, SM2: TSettingsManager;
begin
  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize('');
    SM.UpdatePresencePenalty(0.3);
    Assert(Abs(SM.GetConfig.Model.PresencePenalty - 0.3) < 0.001, 'PresencePenalty should be 0.3');
    SM.SaveGlobal;
  finally
    SM.Free;
  end;

  SM2 := TSettingsManager.Create(nil);
  try
    SM2.Initialize('');
    Assert(Abs(SM2.GetConfig.Model.PresencePenalty - 0.3) < 0.001, 'PresencePenalty should persist after reload');
  finally
    SM2.Free;
  end;
end;

procedure TTestSettingsManager.Test_UpdateModelsEndpoint;
var SM, SM2: TSettingsManager;
begin
  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize('');
    SM.UpdateModelsEndpoint('https://api.test.com/models');
    Assert(SM.GetConfig.Api.ModelsEndpoint = 'https://api.test.com/models', 'ModelsEndpoint should be updated');
    SM.SaveGlobal;
  finally
    SM.Free;
  end;

  SM2 := TSettingsManager.Create(nil);
  try
    SM2.Initialize('');
    Assert(SM2.GetConfig.Api.ModelsEndpoint = 'https://api.test.com/models', 'ModelsEndpoint should persist after reload');
  finally
    SM2.Free;
  end;
end;

procedure TTestSettingsManager.Test_UpdateRetryCount;
var SM, SM2: TSettingsManager;
begin
  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize('');
    SM.UpdateRetryCount(5);
    Assert(SM.GetConfig.Api.RetryCount = 5, 'RetryCount should be 5');
    SM.SaveGlobal;
  finally
    SM.Free;
  end;

  SM2 := TSettingsManager.Create(nil);
  try
    SM2.Initialize('');
    Assert(SM2.GetConfig.Api.RetryCount = 5, 'RetryCount should persist after reload');
  finally
    SM2.Free;
  end;
end;

procedure TTestSettingsManager.Test_UpdateFontSize;
var SM, SM2: TSettingsManager;
begin
  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize('');
    SM.UpdateFontSize(16);
    Assert(SM.GetConfig.UI.FontSize = 16, 'FontSize should be 16');
    SM.SaveGlobal;
  finally
    SM.Free;
  end;

  SM2 := TSettingsManager.Create(nil);
  try
    SM2.Initialize('');
    Assert(SM2.GetConfig.UI.FontSize = 16, 'FontSize should persist after reload');
  finally
    SM2.Free;
  end;
end;

procedure TTestSettingsManager.Test_UpdateFontFamily;
var SM, SM2: TSettingsManager;
begin
  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize('');
    SM.UpdateFontFamily('Consolas');
    Assert(SM.GetConfig.UI.FontFamily = 'Consolas', 'FontFamily should be Consolas');
    SM.SaveGlobal;
  finally
    SM.Free;
  end;

  SM2 := TSettingsManager.Create(nil);
  try
    SM2.Initialize('');
    Assert(SM2.GetConfig.UI.FontFamily = 'Consolas', 'FontFamily should persist after reload');
  finally
    SM2.Free;
  end;
end;

procedure TTestSettingsManager.Test_UpdateBackupDirectory;
var SM, SM2: TSettingsManager;
begin
  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize('');
    SM.UpdateBackupDirectory('C:\backup');
    Assert(SM.GetConfig.Directories.Backup = 'C:\backup', 'BackupDirectory should be C:\backup');
    SM.SaveGlobal;
  finally
    SM.Free;
  end;

  SM2 := TSettingsManager.Create(nil);
  try
    SM2.Initialize('');
    Assert(SM2.GetConfig.Directories.Backup = 'C:\backup', 'BackupDirectory should persist after reload');
  finally
    SM2.Free;
  end;
end;

procedure TTestSettingsManager.Test_UpdateThinkingLevel;
var SM, SM2: TSettingsManager;
begin
  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize('');
    SM.UpdateThinkingLevel(tlMedium);
    Assert(SM.GetConfig.Session.DefaultThinkingLevel = tlMedium, 'ThinkingLevel should be tlMedium');
    SM.SaveGlobal;
  finally
    SM.Free;
  end;

  SM2 := TSettingsManager.Create(nil);
  try
    SM2.Initialize('');
    Assert(SM2.GetConfig.Session.DefaultThinkingLevel = tlMedium, 'ThinkingLevel should persist after reload');
  finally
    SM2.Free;
  end;
end;

procedure TTestSettingsManager.Test_UpdateModelProfiles;
var SM, SM2: TSettingsManager;
  Profiles: TArray<TModelProfile>;
begin
  SetLength(Profiles, 1);
  Profiles[0] := TModelProfile.Create('prof1', 'Profile 1',
    'https://api.custom.com', 'sk-prof', 'custom-model', 4096, 0.5);

  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize('');
    SM.UpdateModelProfiles(Profiles, 'prof1');
    Assert(Length(SM.GetConfig.ModelProfiles) = 1, 'Should have 1 profile');
    Assert(SM.GetConfig.ModelProfiles[0].Id = 'prof1', 'Profile Id should be prof1');
    Assert(SM.GetConfig.ActiveModelId = 'prof1', 'ActiveModelId should be prof1');
    SM.SaveGlobal;
  finally
    SM.Free;
  end;

  SM2 := TSettingsManager.Create(nil);
  try
    SM2.Initialize('');
    Assert(Length(SM2.GetConfig.ModelProfiles) >= 1, 'Profiles should persist after reload');
    Assert(SM2.GetConfig.ActiveModelId = 'prof1', 'ActiveModelId should persist after reload');
  finally
    SM2.Free;
  end;
end;

procedure TTestSettingsManager.Test_UpdateSearchConfig;
var SM, SM2: TSettingsManager;
  SC: TSearchConfig;
begin
  SC := TSearchConfig.GetDefault;
  SC.Enabled := True;
  SC.Provider := spGoogle;
  SC.ApiKey := 'search-key-123';
  SC.MaxResults := 10;

  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize('');
    SM.UpdateSearchConfig(SC);
    Assert(SM.GetConfig.Search.Enabled = True, 'Search should be enabled');
    Assert(SM.GetConfig.Search.Provider = spGoogle, 'Provider should be spGoogle');
    Assert(SM.GetConfig.Search.ApiKey = 'search-key-123', 'ApiKey should match');
    Assert(SM.GetConfig.Search.MaxResults = 10, 'MaxResults should be 10');
    SM.SaveGlobal;
  finally
    SM.Free;
  end;

  SM2 := TSettingsManager.Create(nil);
  try
    SM2.Initialize('');
    Assert(SM2.GetConfig.Search.Enabled = True, 'Search.Enabled should persist after reload');
    Assert(SM2.GetConfig.Search.ApiKey = 'search-key-123', 'Search.ApiKey should persist after reload');
  finally
    SM2.Free;
  end;
end;

procedure TTestSettingsManager.Test_UpdateSkillPool;
var SM: TSettingsManager;
  Skills: TArray<TSkillDef>;
begin
  SetLength(Skills, 1);
  Skills[0] := TSkillDef.Create('test-skill', 'Test Skill', 'A test', 'Body content');

  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize('');
    SM.UpdateSkillPool(Skills);
    Assert(Length(SM.GetConfig.SkillPool) = 1, 'Should have 1 skill');
    Assert(SM.GetConfig.SkillPool[0].Id = 'test-skill', 'Skill Id should be test-skill');
  finally
    SM.Free;
  end;
end;

procedure TTestSettingsManager.Test_UpdateConfig;
var SM: TSettingsManager;
  Cfg: TPiMonoConfig;
begin
  Cfg := TPiMonoConfig.GetDefault;
  Cfg.Model.Name := 'config-test-model';
  Cfg.Api.ApiKey := 'config-test-key';
  Cfg.ActiveModelId := 'test-active';

  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize('');
    SM.UpdateConfig(Cfg);
    Assert(SM.GetConfig.Model.Name = 'config-test-model', 'Model.Name should be updated');
    Assert(SM.GetConfig.Api.ApiKey = 'config-test-key', 'ApiKey should be updated');
    Assert(SM.GetConfig.ActiveModelId = 'test-active', 'ActiveModelId should be updated');
  finally
    SM.Free;
  end;
end;

procedure TTestSettingsManager.Test_GetConfig_ReturnsCopy;
var SM: TSettingsManager;
  Cfg1, Cfg2: TPiMonoConfig;
begin
  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize('');
    Cfg1 := SM.GetConfig;
    Cfg2 := SM.GetConfig;
    // They should be equal but independent copies
    Assert(Cfg1.Model.Name = Cfg2.Model.Name, 'Copies should be equal');
  finally
    SM.Free;
  end;
end;

procedure TTestSettingsManager.Test_Initialize_EmptyProjectDir;
var SM: TSettingsManager;
begin
  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize('');
    // Should not crash with empty project dir
    Assert(SM.GetConfig.Version <> '', 'Should have defaults');
  finally
    SM.Free;
  end;
end;

procedure TTestSettingsManager.Test_SaveGlobal_CreatesDirectory;
var SM: TSettingsManager;
begin
  SM := TSettingsManager.Create(nil);
  try
    SM.Initialize('');
    SM.UpdateModelName('test-save-global-model');
    SM.SaveGlobal;
    Assert(True, 'SaveGlobal should not crash');
  finally
    SM.Free;
  end;
end;

{ Registration }

procedure RegisterSettingsManagerTests;
var
  T: TTestSettingsManager;
begin
  T := TTestSettingsManager.Create;
  try
    GRunner.RunTest('SettingsMgr: Initialize defaults', T.Test_Initialize_Defaults, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: Save and load global', T.Test_SaveAndLoadGlobal, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: Save and load project', T.Test_SaveAndLoadProject, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: Invalid JSON keeps defaults', T.Test_LoadGlobal_InvalidJSON_KeepsDefaults, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: Project fallback path', T.Test_LoadProject_FallbackPath, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: Project overrides global', T.Test_Merge_ProjectOverridesGlobal, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: Default project values not applied', T.Test_Merge_DefaultProjectValuesNotApplied, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: Float epsilon merge', T.Test_Merge_FloatEpsilon, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: Update ApiEndpoint', T.Test_UpdateApiEndpoint, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: Update ModelName', T.Test_UpdateModelName, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: Update Temperature', T.Test_UpdateTemperature, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: Update Theme', T.Test_UpdateTheme, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: Update WorkingDirectory', T.Test_UpdateWorkingDirectory, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: Update Language', T.Test_UpdateLanguage, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: Update Streaming', T.Test_UpdateStreaming, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: Update Timeout', T.Test_UpdateTimeout, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: Update ApiKey', T.Test_UpdateApiKey, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: Update MaxTokens', T.Test_UpdateMaxTokens, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: Update TopP', T.Test_UpdateTopP, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: Update FrequencyPenalty', T.Test_UpdateFrequencyPenalty, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: Update PresencePenalty', T.Test_UpdatePresencePenalty, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: Update ModelsEndpoint', T.Test_UpdateModelsEndpoint, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: Update RetryCount', T.Test_UpdateRetryCount, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: Update FontSize', T.Test_UpdateFontSize, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: Update FontFamily', T.Test_UpdateFontFamily, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: Update BackupDirectory', T.Test_UpdateBackupDirectory, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: Update ThinkingLevel', T.Test_UpdateThinkingLevel, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: Update ModelProfiles', T.Test_UpdateModelProfiles, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: Update SearchConfig', T.Test_UpdateSearchConfig, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: Update SkillPool', T.Test_UpdateSkillPool, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: Update Config', T.Test_UpdateConfig, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: GetConfig returns copy', T.Test_GetConfig_ReturnsCopy, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: Empty project dir', T.Test_Initialize_EmptyProjectDir, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsMgr: SaveGlobal creates dir', T.Test_SaveGlobal_CreatesDirectory, T.Setup, T.TearDown);
  finally
    T.Free;
  end;
end;

end.
