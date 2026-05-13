unit Settings.SettingsManager;

interface

uses
  System.SysUtils, System.JSON, System.IOUtils, System.Classes,
  System.SyncObjs,
  Settings.Config, Settings.SkillStore, Utils.Logger;

type
  TSettingsManager = class
  private
    FGlobalConfigPath: string;
    FProjectConfigPath: string;
    FMergedConfig: TPiMonoConfig;
    FGlobalConfig: TPiMonoConfig;
    FProjectConfig: TPiMonoConfig;
    FLogger: TLogger;
    FProjectDir: string;
    FLock: TCriticalSection;

    class function GetGlobalConfigDir: string; static;
    procedure LoadGlobal;
    procedure LoadProject(const AProjectDir: string);
    procedure MergeConfigs;
  public
    constructor Create(ALogger: TLogger = nil);
    destructor Destroy; override;

    procedure Initialize(const AProjectDir: string = '');
    procedure SaveGlobal;
    procedure SaveProject(const AProjectDir: string);
    function GetConfig: TPiMonoConfig;

    procedure UpdateApiEndpoint(const AValue: string);
    procedure UpdateApiKey(const AValue: string);
    procedure UpdateModelName(const AValue: string);
    procedure UpdateTemperature(AValue: Double);
    procedure UpdateMaxTokens(AValue: Integer);
    procedure UpdateTopP(AValue: Double);
    procedure UpdateFrequencyPenalty(AValue: Double);
    procedure UpdatePresencePenalty(AValue: Double);
    procedure UpdateTheme(const AValue: string);
    procedure UpdateWorkingDirectory(const AValue: string);
    procedure UpdateLanguage(const AValue: string);
    procedure UpdateModelsEndpoint(const AValue: string);
    procedure UpdateStreaming(AValue: Boolean);
    procedure UpdateTimeout(AValue: Integer);
    procedure UpdateRetryCount(AValue: Integer);
    procedure UpdateFontSize(AValue: Integer);
    procedure UpdateFontFamily(const AValue: string);
    procedure UpdateBackupDirectory(const AValue: string);
    procedure UpdateThinkingLevel(AValue: TThinkingLevel);
    procedure UpdateModelProfiles(const AProfiles: TArray<TModelProfile>; const AActiveId: string);
    procedure UpdateSearchConfig(AConfig: TSearchConfig);
    procedure UpdateSkillPool(const ASkills: TArray<TSkillDef>);
    procedure UpdateConfig(const AConfig: TPiMonoConfig);

    /// Check if the active profile has all required fields (ApiKey, Endpoint, ModelName)
    function IsConfigured: Boolean;

    property Config: TPiMonoConfig read FMergedConfig;
    property GlobalConfig: TPiMonoConfig read FGlobalConfig;
    property ProjectConfig: TPiMonoConfig read FProjectConfig;
  end;

implementation

{ TSettingsManager }

constructor TSettingsManager.Create(ALogger: TLogger);
begin
  inherited Create;
  FLogger := ALogger;
  FGlobalConfig := TPiMonoConfig.GetDefault;
  FProjectConfig := TPiMonoConfig.GetDefault;
  FMergedConfig := TPiMonoConfig.GetDefault;
  FGlobalConfigPath := '';
  FProjectConfigPath := '';
  FProjectDir := '';
  FLock := TCriticalSection.Create;
end;

destructor TSettingsManager.Destroy;
begin
  FLock.Free;
  inherited;
end;

class function TSettingsManager.GetGlobalConfigDir: string;
begin
  Result := IncludeTrailingPathDelimiter(
    GetEnvironmentVariable('APPDATA')) + 'PiMono';
end;

procedure TSettingsManager.Initialize(const AProjectDir: string);
begin
  FProjectDir := AProjectDir;
  FGlobalConfigPath := IncludeTrailingPathDelimiter(GetGlobalConfigDir) + 'settings.json';

  if AProjectDir <> '' then
    FProjectConfigPath := IncludeTrailingPathDelimiter(AProjectDir) + '.pimonorc'
  else
    FProjectConfigPath := '';

  LoadGlobal;
  LoadProject(AProjectDir);
  MergeConfigs;

  // Load skills from file store (seeds defaults on first run)
  SeedDefaults;
  FMergedConfig.SkillPool := LoadSkillPool;
end;

procedure TSettingsManager.LoadGlobal;
var
  Json: TJSONObject;
  Content: string;
begin
  FGlobalConfig := TPiMonoConfig.GetDefault;

  if not FileExists(FGlobalConfigPath) then
  begin
    if Assigned(FLogger) then
      FLogger.Debug('Global config not found, using defaults: ' + FGlobalConfigPath);
    Exit;
  end;

  try
    Content := TFile.ReadAllText(FGlobalConfigPath, TEncoding.UTF8);

    // Strip UTF-8 BOM if present — TFile.ReadAllText may not always remove it,
    // and TJSONObject.ParseJSONValue returns nil when content starts with #$FEFF.
    if (Length(Content) > 0) and (Content[1] = #$FEFF) then
      Delete(Content, 1, 1);

    Json := TJSONObject.ParseJSONValue(Content) as TJSONObject;
    try
      if Json <> nil then
      begin
        FGlobalConfig := TPiMonoConfig.FromJson(Json);
        if Assigned(FLogger) then
          FLogger.Info('LoadGlobal: OK. endpoint=' + FGlobalConfig.Api.Endpoint +
            ' apiKeyLen=' + IntToStr(Length(FGlobalConfig.Api.ApiKey)) +
            ' model=' + FGlobalConfig.Model.Name +
            ' profiles=' + IntToStr(Length(FGlobalConfig.ModelProfiles)));
      end
      else
        if Assigned(FLogger) then
          FLogger.Error('LoadGlobal: ParseJSONValue returned nil for ' + FGlobalConfigPath);
    finally
      Json.Free;
    end;
  except
    on E: Exception do
      if Assigned(FLogger) then
        FLogger.LogException(E, 'Failed to load global config');
  end;
end;

procedure TSettingsManager.LoadProject(const AProjectDir: string);
var
  Json: TJSONObject;
  Content: string;
  Path: string;
begin
  FProjectConfig := TPiMonoConfig.GetDefault;

  if AProjectDir = '' then
    Exit;

  Path := IncludeTrailingPathDelimiter(AProjectDir) + '.pimonorc';
  FProjectConfigPath := Path;

  if not FileExists(Path) then
  begin
    // Also check .pi/settings.json
    Path := IncludeTrailingPathDelimiter(AProjectDir) + '.pi\settings.json';
    if not FileExists(Path) then
    begin
      if Assigned(FLogger) then
        FLogger.Debug('Project config not found: ' + FProjectConfigPath);
      Exit;
    end;
    FProjectConfigPath := Path;
  end;

  try
    Content := TFile.ReadAllText(Path, TEncoding.UTF8);

    // Strip UTF-8 BOM if present (same fix as LoadGlobal)
    if (Length(Content) > 0) and (Content[1] = #$FEFF) then
      Delete(Content, 1, 1);

    Json := TJSONObject.ParseJSONValue(Content) as TJSONObject;
    try
      if Json <> nil then
        FProjectConfig := TPiMonoConfig.FromJson(Json);
    finally
      Json.Free;
    end;
  except
    on E: Exception do
      if Assigned(FLogger) then
        FLogger.LogException(E, 'Failed to load project config');
  end;
end;

procedure TSettingsManager.MergeConfigs;
var
  Def: TPiMonoConfig;
begin
  // Start from global config, overlay project config for non-default values
  FMergedConfig := FGlobalConfig;
  Def := TPiMonoConfig.GetDefault;

  // Project Api overrides
  if FProjectConfig.Api.Endpoint <> Def.Api.Endpoint then
    FMergedConfig.Api.Endpoint := FProjectConfig.Api.Endpoint;
  if FProjectConfig.Api.ApiKey <> Def.Api.ApiKey then
    FMergedConfig.Api.ApiKey := FProjectConfig.Api.ApiKey;
  if FProjectConfig.Api.ModelsEndpoint <> Def.Api.ModelsEndpoint then
    FMergedConfig.Api.ModelsEndpoint := FProjectConfig.Api.ModelsEndpoint;
  if FProjectConfig.Api.Timeout <> Def.Api.Timeout then
    FMergedConfig.Api.Timeout := FProjectConfig.Api.Timeout;
  if FProjectConfig.Api.RetryCount <> Def.Api.RetryCount then
    FMergedConfig.Api.RetryCount := FProjectConfig.Api.RetryCount;
  if FProjectConfig.Api.RetryDelay <> Def.Api.RetryDelay then
    FMergedConfig.Api.RetryDelay := FProjectConfig.Api.RetryDelay;
  if FProjectConfig.Api.EnableStreaming <> Def.Api.EnableStreaming then
    FMergedConfig.Api.EnableStreaming := FProjectConfig.Api.EnableStreaming;

  // Project Model overrides
  if FProjectConfig.Model.Name <> Def.Model.Name then
    FMergedConfig.Model.Name := FProjectConfig.Model.Name;
  if FProjectConfig.Model.MaxTokens <> Def.Model.MaxTokens then
    FMergedConfig.Model.MaxTokens := FProjectConfig.Model.MaxTokens;
  if Abs(FProjectConfig.Model.Temperature - Def.Model.Temperature) > 0.001 then
    FMergedConfig.Model.Temperature := FProjectConfig.Model.Temperature;
  if Abs(FProjectConfig.Model.TopP - Def.Model.TopP) > 0.001 then
    FMergedConfig.Model.TopP := FProjectConfig.Model.TopP;
  if Abs(FProjectConfig.Model.FrequencyPenalty - Def.Model.FrequencyPenalty) > 0.001 then
    FMergedConfig.Model.FrequencyPenalty := FProjectConfig.Model.FrequencyPenalty;
  if Abs(FProjectConfig.Model.PresencePenalty - Def.Model.PresencePenalty) > 0.001 then
    FMergedConfig.Model.PresencePenalty := FProjectConfig.Model.PresencePenalty;

  // Project Directories overrides
  if FProjectConfig.Directories.Working <> Def.Directories.Working then
    FMergedConfig.Directories.Working := FProjectConfig.Directories.Working;
  if FProjectConfig.Directories.Backup <> Def.Directories.Backup then
    FMergedConfig.Directories.Backup := FProjectConfig.Directories.Backup;
  if FProjectConfig.Directories.Cache <> Def.Directories.Cache then
    FMergedConfig.Directories.Cache := FProjectConfig.Directories.Cache;
  if FProjectConfig.Directories.Logs <> Def.Directories.Logs then
    FMergedConfig.Directories.Logs := FProjectConfig.Directories.Logs;

  // Project UI overrides
  if FProjectConfig.UI.Theme <> Def.UI.Theme then
    FMergedConfig.UI.Theme := FProjectConfig.UI.Theme;
  if FProjectConfig.UI.FontSize <> Def.UI.FontSize then
    FMergedConfig.UI.FontSize := FProjectConfig.UI.FontSize;
  if FProjectConfig.UI.FontFamily <> Def.UI.FontFamily then
    FMergedConfig.UI.FontFamily := FProjectConfig.UI.FontFamily;
  if FProjectConfig.UI.WindowWidth <> Def.UI.WindowWidth then
    FMergedConfig.UI.WindowWidth := FProjectConfig.UI.WindowWidth;
  if FProjectConfig.UI.WindowHeight <> Def.UI.WindowHeight then
    FMergedConfig.UI.WindowHeight := FProjectConfig.UI.WindowHeight;
  if FProjectConfig.UI.Language <> Def.UI.Language then
    FMergedConfig.UI.Language := FProjectConfig.UI.Language;

  // Project Session overrides
  if FProjectConfig.Session.AutoSave <> Def.Session.AutoSave then
    FMergedConfig.Session.AutoSave := FProjectConfig.Session.AutoSave;
  if FProjectConfig.Session.AutoSaveInterval <> Def.Session.AutoSaveInterval then
    FMergedConfig.Session.AutoSaveInterval := FProjectConfig.Session.AutoSaveInterval;
  if FProjectConfig.Session.MaxSessions <> Def.Session.MaxSessions then
    FMergedConfig.Session.MaxSessions := FProjectConfig.Session.MaxSessions;
  if FProjectConfig.Session.DefaultThinkingLevel <> Def.Session.DefaultThinkingLevel then
    FMergedConfig.Session.DefaultThinkingLevel := FProjectConfig.Session.DefaultThinkingLevel;
  if FProjectConfig.Session.CompactionEnabled <> Def.Session.CompactionEnabled then
    FMergedConfig.Session.CompactionEnabled := FProjectConfig.Session.CompactionEnabled;
  if FProjectConfig.Session.ReserveTokens <> Def.Session.ReserveTokens then
    FMergedConfig.Session.ReserveTokens := FProjectConfig.Session.ReserveTokens;
  if FProjectConfig.Session.KeepRecentTokens <> Def.Session.KeepRecentTokens then
    FMergedConfig.Session.KeepRecentTokens := FProjectConfig.Session.KeepRecentTokens;

  // Project Logging overrides
  if FProjectConfig.Logging.Level <> Def.Logging.Level then
    FMergedConfig.Logging.Level := FProjectConfig.Logging.Level;
  if FProjectConfig.Logging.MaxFileSize <> Def.Logging.MaxFileSize then
    FMergedConfig.Logging.MaxFileSize := FProjectConfig.Logging.MaxFileSize;
  if FProjectConfig.Logging.MaxFiles <> Def.Logging.MaxFiles then
    FMergedConfig.Logging.MaxFiles := FProjectConfig.Logging.MaxFiles;

  // Project ModelProfiles and ActiveModelId overrides
  if Length(FProjectConfig.ModelProfiles) > 0 then
    FMergedConfig.ModelProfiles := Copy(FProjectConfig.ModelProfiles);
  if FProjectConfig.ActiveModelId <> Def.ActiveModelId then
    FMergedConfig.ActiveModelId := FProjectConfig.ActiveModelId;

  // Project Permission overrides
  if FProjectConfig.Permissions.ReadPerm.Enabled <> Def.Permissions.ReadPerm.Enabled then
    FMergedConfig.Permissions.ReadPerm := FProjectConfig.Permissions.ReadPerm;
  if FProjectConfig.Permissions.WritePerm.Enabled <> Def.Permissions.WritePerm.Enabled then
    FMergedConfig.Permissions.WritePerm := FProjectConfig.Permissions.WritePerm;
  if FProjectConfig.Permissions.EditPerm.Enabled <> Def.Permissions.EditPerm.Enabled then
    FMergedConfig.Permissions.EditPerm := FProjectConfig.Permissions.EditPerm;
  if FProjectConfig.Permissions.BashPerm.Enabled <> Def.Permissions.BashPerm.Enabled then
    FMergedConfig.Permissions.BashPerm := FProjectConfig.Permissions.BashPerm;
  if FProjectConfig.Permissions.GitPerm.Enabled <> Def.Permissions.GitPerm.Enabled then
    FMergedConfig.Permissions.GitPerm := FProjectConfig.Permissions.GitPerm;
  if FProjectConfig.Permissions.SearchPerm.Enabled <> Def.Permissions.SearchPerm.Enabled then
    FMergedConfig.Permissions.SearchPerm := FProjectConfig.Permissions.SearchPerm;

  // Project Search overrides
  if FProjectConfig.Search.Provider <> Def.Search.Provider then
    FMergedConfig.Search.Provider := FProjectConfig.Search.Provider;
  if FProjectConfig.Search.Enabled <> Def.Search.Enabled then
    FMergedConfig.Search.Enabled := FProjectConfig.Search.Enabled;
  if FProjectConfig.Search.ApiKey <> Def.Search.ApiKey then
    FMergedConfig.Search.ApiKey := FProjectConfig.Search.ApiKey;
  if FProjectConfig.Search.CustomId <> Def.Search.CustomId then
    FMergedConfig.Search.CustomId := FProjectConfig.Search.CustomId;
  if FProjectConfig.Search.MaxResults <> Def.Search.MaxResults then
    FMergedConfig.Search.MaxResults := FProjectConfig.Search.MaxResults;
  if FProjectConfig.Search.EnableFetch <> Def.Search.EnableFetch then
    FMergedConfig.Search.EnableFetch := FProjectConfig.Search.EnableFetch;
  if FProjectConfig.Search.FetchMaxLength <> Def.Search.FetchMaxLength then
    FMergedConfig.Search.FetchMaxLength := FProjectConfig.Search.FetchMaxLength;
  if FProjectConfig.Search.Timeout <> Def.Search.Timeout then
    FMergedConfig.Search.Timeout := FProjectConfig.Search.Timeout;
end;

procedure TSettingsManager.SaveGlobal;
var
  Json: TJSONObject;
  Bytes: TBytes;
  Dir: string;
  ConfigSnapshot: TPiMonoConfig;
begin
  FLock.Enter;
  try
    ConfigSnapshot := FGlobalConfig;
  finally
    FLock.Leave;
  end;

  Dir := ExtractFileDir(FGlobalConfigPath);
  if not DirectoryExists(Dir) then
    ForceDirectories(Dir);

  Json := ConfigSnapshot.ToJson;
  try
    // Use WriteAllBytes (no BOM) instead of WriteAllText (adds BOM).
    // BOM causes LoadGlobal JSON parsing to fail on some Delphi versions.
    Bytes := TEncoding.UTF8.GetBytes(Json.Format(2));
    TFile.WriteAllBytes(FGlobalConfigPath, Bytes);
  finally
    Json.Free;
  end;

  if Assigned(FLogger) then
    FLogger.Info('Global settings saved: ' + FGlobalConfigPath);
end;

procedure TSettingsManager.SaveProject(const AProjectDir: string);
var
  Json: TJSONObject;
  Bytes: TBytes;
  Path, Dir: string;
begin
  Path := IncludeTrailingPathDelimiter(AProjectDir) + '.pimonorc';
  Dir := ExtractFileDir(Path);
  if not DirectoryExists(Dir) then
    ForceDirectories(Dir);

  Json := FProjectConfig.ToJson;
  try
    // Use WriteAllBytes (no BOM) to match LoadGlobal BOM-stripping fix
    Bytes := TEncoding.UTF8.GetBytes(Json.Format(2));
    TFile.WriteAllBytes(Path, Bytes);
  finally
    Json.Free;
  end;

  if Assigned(FLogger) then
    FLogger.Info('Project settings saved: ' + Path);
end;

function TSettingsManager.GetConfig: TPiMonoConfig;
begin
  FLock.Enter;
  try
    Result := FMergedConfig;
  finally
    FLock.Leave;
  end;
end;

procedure TSettingsManager.UpdateApiEndpoint(const AValue: string);
begin
  FLock.Enter;
  try
    FGlobalConfig.Api.Endpoint := AValue;
    FMergedConfig.Api.Endpoint := AValue;
  finally
    FLock.Leave;
  end;
end;

procedure TSettingsManager.UpdateApiKey(const AValue: string);
begin
  FLock.Enter;
  try
    FGlobalConfig.Api.ApiKey := AValue;
    FMergedConfig.Api.ApiKey := AValue;
  finally
    FLock.Leave;
  end;
end;

procedure TSettingsManager.UpdateModelName(const AValue: string);
begin
  FLock.Enter;
  try
    FGlobalConfig.Model.Name := AValue;
    FMergedConfig.Model.Name := AValue;
  finally
    FLock.Leave;
  end;
end;

procedure TSettingsManager.UpdateTemperature(AValue: Double);
begin
  FLock.Enter;
  try
    FGlobalConfig.Model.Temperature := AValue;
    FMergedConfig.Model.Temperature := AValue;
  finally
    FLock.Leave;
  end;
end;

procedure TSettingsManager.UpdateMaxTokens(AValue: Integer);
begin
  FLock.Enter;
  try
    FGlobalConfig.Model.MaxTokens := AValue;
    FMergedConfig.Model.MaxTokens := AValue;
  finally
    FLock.Leave;
  end;
end;

procedure TSettingsManager.UpdateTopP(AValue: Double);
begin
  FLock.Enter;
  try
    FGlobalConfig.Model.TopP := AValue;
    FMergedConfig.Model.TopP := AValue;
  finally
    FLock.Leave;
  end;
end;

procedure TSettingsManager.UpdateFrequencyPenalty(AValue: Double);
begin
  FLock.Enter;
  try
    FGlobalConfig.Model.FrequencyPenalty := AValue;
    FMergedConfig.Model.FrequencyPenalty := AValue;
  finally
    FLock.Leave;
  end;
end;

procedure TSettingsManager.UpdatePresencePenalty(AValue: Double);
begin
  FLock.Enter;
  try
    FGlobalConfig.Model.PresencePenalty := AValue;
    FMergedConfig.Model.PresencePenalty := AValue;
  finally
    FLock.Leave;
  end;
end;

procedure TSettingsManager.UpdateTheme(const AValue: string);
var
  Normalized: string;
begin
  // Normalize to lowercase hyphenated form (matches JS theme IDs)
  Normalized := AValue.ToLower.Trim.Replace(' ', '-');
  FLock.Enter;
  try
    FGlobalConfig.UI.Theme := Normalized;
    FMergedConfig.UI.Theme := Normalized;
  finally
    FLock.Leave;
  end;
end;

procedure TSettingsManager.UpdateWorkingDirectory(const AValue: string);
begin
  FLock.Enter;
  try
    FGlobalConfig.Directories.Working := AValue;
    FMergedConfig.Directories.Working := AValue;
  finally
    FLock.Leave;
  end;
end;

procedure TSettingsManager.UpdateLanguage(const AValue: string);
begin
  FLock.Enter;
  try
    FGlobalConfig.UI.Language := AValue;
    FMergedConfig.UI.Language := AValue;
  finally
    FLock.Leave;
  end;
end;

procedure TSettingsManager.UpdateModelsEndpoint(const AValue: string);
begin
  FLock.Enter;
  try
    FGlobalConfig.Api.ModelsEndpoint := AValue;
    FMergedConfig.Api.ModelsEndpoint := AValue;
  finally
    FLock.Leave;
  end;
end;

procedure TSettingsManager.UpdateStreaming(AValue: Boolean);
begin
  FLock.Enter;
  try
    FGlobalConfig.Api.EnableStreaming := AValue;
    FMergedConfig.Api.EnableStreaming := AValue;
  finally
    FLock.Leave;
  end;
end;

procedure TSettingsManager.UpdateTimeout(AValue: Integer);
begin
  FLock.Enter;
  try
    FGlobalConfig.Api.Timeout := AValue;
    FMergedConfig.Api.Timeout := AValue;
  finally
    FLock.Leave;
  end;
end;

procedure TSettingsManager.UpdateRetryCount(AValue: Integer);
begin
  FLock.Enter;
  try
    FGlobalConfig.Api.RetryCount := AValue;
    FMergedConfig.Api.RetryCount := AValue;
  finally
    FLock.Leave;
  end;
end;

procedure TSettingsManager.UpdateFontSize(AValue: Integer);
begin
  FLock.Enter;
  try
    FGlobalConfig.UI.FontSize := AValue;
    FMergedConfig.UI.FontSize := AValue;
  finally
    FLock.Leave;
  end;
end;

procedure TSettingsManager.UpdateFontFamily(const AValue: string);
begin
  FLock.Enter;
  try
    FGlobalConfig.UI.FontFamily := AValue;
    FMergedConfig.UI.FontFamily := AValue;
  finally
    FLock.Leave;
  end;
end;

procedure TSettingsManager.UpdateBackupDirectory(const AValue: string);
begin
  FLock.Enter;
  try
    FGlobalConfig.Directories.Backup := AValue;
    FMergedConfig.Directories.Backup := AValue;
  finally
    FLock.Leave;
  end;
end;

procedure TSettingsManager.UpdateThinkingLevel(AValue: TThinkingLevel);
begin
  FLock.Enter;
  try
    FGlobalConfig.Session.DefaultThinkingLevel := AValue;
    FMergedConfig.Session.DefaultThinkingLevel := AValue;
  finally
    FLock.Leave;
  end;
end;

procedure TSettingsManager.UpdateModelProfiles(const AProfiles: TArray<TModelProfile>;
  const AActiveId: string);
begin
  FLock.Enter;
  try
    FGlobalConfig.ModelProfiles := Copy(AProfiles);
    FGlobalConfig.ActiveModelId := AActiveId;
    FMergedConfig.ModelProfiles := Copy(AProfiles);
    FMergedConfig.ActiveModelId := AActiveId;
  finally
    FLock.Leave;
  end;
end;

procedure TSettingsManager.UpdateSearchConfig(AConfig: TSearchConfig);
begin
  FLock.Enter;
  try
    FGlobalConfig.Search := AConfig;
    FMergedConfig.Search := AConfig;
  finally
    FLock.Leave;
  end;
end;

procedure TSettingsManager.UpdateSkillPool(const ASkills: TArray<TSkillDef>);
var
  Existing: TArray<TSkillDef>;
  i: Integer;
  Found: Boolean;
begin
  // Determine which skills were deleted
  Existing := FMergedConfig.SkillPool;
  for i := 0 to High(Existing) do
  begin
    Found := False;
    for var j := 0 to High(ASkills) do
    begin
      if ASkills[j].Id = Existing[i].Id then
      begin
        Found := True;
        Break;
      end;
    end;
    if not Found then
      DeleteSkill(Existing[i].Id);
  end;

  // Save all current skills
  for i := 0 to High(ASkills) do
    SaveSkill(ASkills[i]);

  FMergedConfig.SkillPool := Copy(ASkills);
end;

procedure TSettingsManager.UpdateConfig(const AConfig: TPiMonoConfig);
begin
  FLock.Enter;
  try
    FMergedConfig := AConfig;
    FGlobalConfig := AConfig;  // Copy all fields to global config
  finally
    FLock.Leave;
  end;
  SaveGlobal;
end;

function TSettingsManager.IsConfigured: Boolean;
var
  Profile: TModelProfile;
begin
  Profile := FMergedConfig.GetActiveProfile;
  Result := (Profile.ApiKey <> '') and (Profile.Endpoint <> '') and (Profile.ModelName <> '');
end;

end.
