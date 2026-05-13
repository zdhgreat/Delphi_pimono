unit TestConfig;

interface

uses
  System.SysUtils, System.JSON,
  Settings.Config, Utils.JsonHelper,
  PiMonoTestFramework;

procedure RegisterConfigTests;

implementation

type
  TTestConfig = class
  public
    procedure DefaultConfig_ToJson_FromJson_RoundTrip;
    procedure ApiConfig_Defaults;
    procedure ModelConfig_Defaults;
    procedure UIConfig_Defaults;
    procedure SessionConfig_Defaults;
    procedure LoggingConfig_Defaults;
    procedure SearchConfig_Defaults;
    procedure ThinkingLevel_RoundTrip;
    procedure SearchProvider_RoundTrip;
    procedure ModelProfiles_Serialization;
    procedure SkillPool_Serialization;
    procedure GetActiveProfile_Default;
    procedure GetActiveProfile_Specific;
    procedure FindProfileById_Exists;
    procedure FindProfileById_Missing;
    procedure MissingFields_UseDefaults;
    procedure InvalidJson_NoCrash;
    procedure ToolPermissions_Defaults;
    procedure EmptyConfig_UsesDefaults;
    procedure DirectoriesConfig_Defaults;
  end;

{ TTestConfig }

procedure TTestConfig.DefaultConfig_ToJson_FromJson_RoundTrip;
var
  Config, Restored: TPiMonoConfig;
  Json: TJSONObject;
begin
  Config := TPiMonoConfig.GetDefault;
  Json := Config.ToJson;
  try
    Restored := TPiMonoConfig.FromJson(Json);
    Assert(Config.Version = Restored.Version, 'Version mismatch');
    Assert(Config.Api.Endpoint = Restored.Api.Endpoint, 'Api.Endpoint mismatch');
    Assert(Config.Model.Name = Restored.Model.Name, 'Model.Name mismatch');
    Assert(Abs(Config.Model.Temperature - Restored.Model.Temperature) < 0.001, 'Model.Temperature mismatch');
    Assert(Abs(Config.Model.TopP - Restored.Model.TopP) < 0.001, 'Model.TopP mismatch');
    Assert(Config.UI.Theme = Restored.UI.Theme, 'UI.Theme mismatch');
    Assert(Config.UI.FontSize = Restored.UI.FontSize, 'UI.FontSize mismatch');
    Assert(Config.Session.AutoSave = Restored.Session.AutoSave, 'Session.AutoSave mismatch');
  finally
    Json.Free;
  end;
end;

procedure TTestConfig.ApiConfig_Defaults;
var
  Config: TApiConfig;
begin
  Config := TApiConfig.GetDefault;
  Assert(Config.Endpoint <> '', 'Endpoint should not be empty');
  Assert(Config.Timeout > 0, 'Timeout should be positive');
  Assert(Config.RetryCount > 0, 'RetryCount should be positive');
  Assert(Config.EnableStreaming, 'EnableStreaming should be True by default');
end;

procedure TTestConfig.ModelConfig_Defaults;
var
  Config: TModelConfig;
begin
  Config := TModelConfig.GetDefault;
  Assert(Config.MaxTokens > 0, 'MaxTokens should be positive');
  Assert(Config.Temperature > 0, 'Temperature should be positive');
  Assert(Config.Temperature <= 2.0, 'Temperature should be <= 2.0');
  Assert((Config.TopP >= 0) and (Config.TopP <= 1.0), 'TopP should be in [0, 1]');
end;

procedure TTestConfig.UIConfig_Defaults;
var
  Config: TUIConfig;
begin
  Config := TUIConfig.GetDefault;
  Assert(Config.FontSize > 0, 'FontSize should be positive');
  Assert(Config.WindowWidth > 0, 'WindowWidth should be positive');
  Assert(Config.WindowHeight > 0, 'WindowHeight should be positive');
end;

procedure TTestConfig.SessionConfig_Defaults;
var
  Config: TSessionConfig;
begin
  Config := TSessionConfig.GetDefault;
  Assert(Config.AutoSave, 'AutoSave should be True');
  Assert(Config.MaxSessions > 0, 'MaxSessions should be positive');
  Assert(Config.ReserveTokens > 0, 'ReserveTokens should be positive');
end;

procedure TTestConfig.LoggingConfig_Defaults;
var
  Config: TLoggingConfig;
begin
  Config := TLoggingConfig.GetDefault;
  Assert(Config.Level <> '', 'Level should not be empty');
  Assert(Config.MaxFileSize > 0, 'MaxFileSize should be positive');
  Assert(Config.MaxFiles > 0, 'MaxFiles should be positive');
end;

procedure TTestConfig.SearchConfig_Defaults;
var
  Config: TSearchConfig;
begin
  Config := TSearchConfig.GetDefault;
  Assert(not Config.Enabled, 'Search should be disabled by default');
  Assert(Ord(Config.Provider) = Ord(spNone), 'Provider should be spNone');
  Assert(Config.MaxResults = 5, 'MaxResults should be 5');
end;

procedure TTestConfig.ThinkingLevel_RoundTrip;
var
  Levels: array[0..5] of TThinkingLevel;
  i: Integer;
begin
  Levels[0] := tlOff;
  Levels[1] := tlMinimal;
  Levels[2] := tlLow;
  Levels[3] := tlMedium;
  Levels[4] := tlHigh;
  Levels[5] := tlXHigh;
  for i := 0 to High(Levels) do
    Assert(Ord(Levels[i]) = Ord(StringToThinkingLevel(ThinkingLevelToString(Levels[i]))),
      'ThinkingLevel roundtrip failed for index ' + IntToStr(i));
end;

procedure TTestConfig.SearchProvider_RoundTrip;
var
  Providers: array[0..12] of TSearchProvider;
  i: Integer;
begin
  Providers[0] := spNone;
  Providers[1] := spGoogle;
  Providers[2] := spDuckDuckGo;
  Providers[3] := spSearXNG;
  Providers[4] := spBrave;
  Providers[5] := spSerper;
  Providers[6] := spTavily;
  Providers[7] := spYouCom;
  Providers[8] := spExa;
  Providers[9] := spFirecrawl;
  Providers[10] := spLinkup;
  Providers[11] := spPerplexity;
  Providers[12] := spMoonshot;
  for i := 0 to High(Providers) do
    Assert(Ord(Providers[i]) = Ord(StringToSearchProvider(SearchProviderToString(Providers[i]))),
      'SearchProvider roundtrip failed for index ' + IntToStr(i));
end;

procedure TTestConfig.ModelProfiles_Serialization;
var
  Config, Restored: TPiMonoConfig;
  Json: TJSONObject;
begin
  Config := TPiMonoConfig.GetDefault;
  SetLength(Config.ModelProfiles, 2);
  Config.ModelProfiles[0] := TModelProfile.Create('p1', 'Profile 1',
    'http://api1.example.com', 'key1', 'model-1', 4096, 0.5);
  Config.ModelProfiles[1] := TModelProfile.Create('p2', 'Profile 2',
    'http://api2.example.com', 'key2', 'model-2', 8192, 0.8);
  Config.ActiveModelId := 'p1';

  Json := Config.ToJson;
  try
    Restored := TPiMonoConfig.FromJson(Json);
    Assert(Length(Restored.ModelProfiles) = 2, 'Should have 2 profiles');
    Assert(Restored.ModelProfiles[0].Id = 'p1', 'Profile 0 Id mismatch');
    Assert(Restored.ModelProfiles[0].DisplayName = 'Profile 1', 'Profile 0 DisplayName mismatch');
    Assert(Restored.ModelProfiles[1].ModelName = 'model-2', 'Profile 1 ModelName mismatch');
    Assert(Restored.ActiveModelId = 'p1', 'ActiveModelId mismatch');
  finally
    Json.Free;
  end;
end;

procedure TTestConfig.SkillPool_Serialization;
var
  Config, Restored: TPiMonoConfig;
  Json: TJSONObject;
begin
  Config := TPiMonoConfig.GetDefault;
  SetLength(Config.SkillPool, 1);
  Config.SkillPool[0] := TSkillDef.Create('skill1', 'Test Skill',
    'A test skill', 'skill content here', 'ref data', 'example data');

  Json := Config.ToJson;
  try
    Restored := TPiMonoConfig.FromJson(Json);
    // SkillPool is intentionally not persisted in ToJson/FromJson
    Assert(Length(Restored.SkillPool) = 0, 'SkillPool should be empty after roundtrip (not serialized)');
  finally
    Json.Free;
  end;
end;

procedure TTestConfig.GetActiveProfile_Default;
var
  Config: TPiMonoConfig;
  Profile: TModelProfile;
begin
  Config := TPiMonoConfig.GetDefault;
  Config.ActiveModelId := '';
  Profile := Config.GetActiveProfile;
  // Should fall back to global config values
  Assert(Config.Model.Name = Profile.ModelName,
    'Default profile ModelName should match global config');
end;

procedure TTestConfig.GetActiveProfile_Specific;
var
  Config: TPiMonoConfig;
  Profile: TModelProfile;
begin
  Config := TPiMonoConfig.GetDefault;
  SetLength(Config.ModelProfiles, 1);
  Config.ModelProfiles[0] := TModelProfile.Create('myid', 'My Profile',
    'http://custom.api', 'mykey', 'custom-model', 4096, 0.3);
  Config.ActiveModelId := 'myid';

  Profile := Config.GetActiveProfile;
  Assert(Profile.ModelName = 'custom-model', 'ModelName mismatch');
  Assert(Profile.Endpoint = 'http://custom.api', 'Endpoint mismatch');
  Assert(Abs(Profile.Temperature - 0.3) < 0.001, 'Temperature mismatch');
end;

procedure TTestConfig.FindProfileById_Exists;
var
  Config: TPiMonoConfig;
begin
  Config := TPiMonoConfig.GetDefault;
  SetLength(Config.ModelProfiles, 1);
  Config.ModelProfiles[0] := TModelProfile.Create('abc', 'Test', '', '', 'm1');
  Assert(Config.FindProfileById('abc').Id = 'abc', 'Should find profile by id');
end;

procedure TTestConfig.FindProfileById_Missing;
var
  Config: TPiMonoConfig;
begin
  Config := TPiMonoConfig.GetDefault;
  Assert(Config.FindProfileById('nonexistent').Id = '', 'Missing profile should return empty Id');
end;

procedure TTestConfig.MissingFields_UseDefaults;
var
  Json: TJSONObject;
  Config: TPiMonoConfig;
begin
  // Minimal JSON - most fields missing
  Json := TJSONObject.ParseJSONValue('{"version":"6.0"}') as TJSONObject;
  try
    Config := TPiMonoConfig.FromJson(Json);
    Assert(Config.Model.MaxTokens > 0, 'MaxTokens should use default');
    Assert(Config.Api.Timeout > 0, 'Timeout should use default');
  finally
    Json.Free;
  end;
end;

procedure TTestConfig.InvalidJson_NoCrash;
var
  Json: TJSONObject;
  Config: TPiMonoConfig;
begin
  // Completely invalid structure - endpoint is number instead of string
  Json := TJSONObject.ParseJSONValue('{"api":{"endpoint":123}}') as TJSONObject;
  try
    Config := TPiMonoConfig.FromJson(Json);
    // Should not crash and should use default endpoint
    Assert(Config.Api.Endpoint <> '', 'Default config should have non-empty endpoint');
  finally
    Json.Free;
  end;
end;

procedure TTestConfig.ToolPermissions_Defaults;
var
  Config: TPiMonoConfig;
begin
  Config := TPiMonoConfig.GetDefault;
  Assert(Config.Permissions.ReadPerm.Enabled, 'Read should be enabled by default');
  Assert(Config.Permissions.WritePerm.Enabled, 'Write should be enabled by default');
  Assert(Config.Permissions.WritePerm.RequireConfirmation, 'Write should require confirmation');
  Assert(Config.Permissions.EditPerm.RequireConfirmation, 'Edit should require confirmation');
  Assert(not Config.Permissions.BashPerm.Enabled, 'Bash should be disabled by default');
end;

procedure TTestConfig.EmptyConfig_UsesDefaults;
var
  Json: TJSONObject;
  Config: TPiMonoConfig;
begin
  Json := TJSONObject.Create;
  try
    Config := TPiMonoConfig.FromJson(Json);
    // Default version is '1.0' in GetDefault, FromJson uses '1.0' as default
    Assert(Config.Version <> '', 'Version should not be empty');
    Assert(Config.Session.AutoSave, 'AutoSave should default to True');
  finally
    Json.Free;
  end;
end;

procedure TTestConfig.DirectoriesConfig_Defaults;
var
  Dir: TDirectoriesConfig;
begin
  Dir := TDirectoriesConfig.GetDefault;
  Assert(Dir.Working <> '', 'Working should not be empty');
  Assert(Dir.Backup <> '', 'Backup should not be empty');
  Assert(Dir.Cache <> '', 'Cache should not be empty');
  Assert(Dir.Logs <> '', 'Logs should not be empty');
  Assert(Pos('Projects', Dir.Working) > 0, 'Working should contain Projects');
  Assert(Pos('PiMono', Dir.Backup) > 0, 'Backup should contain PiMono');
  Assert(Pos('PiMono', Dir.Cache) > 0, 'Cache should contain PiMono');
  Assert(Pos('PiMono', Dir.Logs) > 0, 'Logs should contain PiMono');
end;

procedure RegisterConfigTests;
var
  T: TTestConfig;
begin
  T := TTestConfig.Create;
  try
    GRunner.RunTest('Config.DefaultConfig_ToJson_FromJson_RoundTrip', T.DefaultConfig_ToJson_FromJson_RoundTrip);
    GRunner.RunTest('Config.ApiConfig_Defaults', T.ApiConfig_Defaults);
    GRunner.RunTest('Config.ModelConfig_Defaults', T.ModelConfig_Defaults);
    GRunner.RunTest('Config.UIConfig_Defaults', T.UIConfig_Defaults);
    GRunner.RunTest('Config.SessionConfig_Defaults', T.SessionConfig_Defaults);
    GRunner.RunTest('Config.LoggingConfig_Defaults', T.LoggingConfig_Defaults);
    GRunner.RunTest('Config.SearchConfig_Defaults', T.SearchConfig_Defaults);
    GRunner.RunTest('Config.ThinkingLevel_RoundTrip', T.ThinkingLevel_RoundTrip);
    GRunner.RunTest('Config.SearchProvider_RoundTrip', T.SearchProvider_RoundTrip);
    GRunner.RunTest('Config.ModelProfiles_Serialization', T.ModelProfiles_Serialization);
    GRunner.RunTest('Config.SkillPool_Serialization', T.SkillPool_Serialization);
    GRunner.RunTest('Config.GetActiveProfile_Default', T.GetActiveProfile_Default);
    GRunner.RunTest('Config.GetActiveProfile_Specific', T.GetActiveProfile_Specific);
    GRunner.RunTest('Config.FindProfileById_Exists', T.FindProfileById_Exists);
    GRunner.RunTest('Config.FindProfileById_Missing', T.FindProfileById_Missing);
    GRunner.RunTest('Config.MissingFields_UseDefaults', T.MissingFields_UseDefaults);
    GRunner.RunTest('Config.InvalidJson_NoCrash', T.InvalidJson_NoCrash);
    GRunner.RunTest('Config.ToolPermissions_Defaults', T.ToolPermissions_Defaults);
    GRunner.RunTest('Config.EmptyConfig_UsesDefaults', T.EmptyConfig_UsesDefaults);
    GRunner.RunTest('Config.DirectoriesConfig_Defaults', T.DirectoriesConfig_Defaults);
  finally
    T.Free;
  end;
end;

end.
