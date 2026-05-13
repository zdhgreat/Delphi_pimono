unit Settings.Config;

interface

uses
  System.SysUtils, System.JSON, System.Generics.Collections,
  System.NetEncoding,
  Utils.JsonHelper;

type
  TThinkingLevel = (
    tlOff,
    tlMinimal,
    tlLow,
    tlMedium,
    tlHigh,
    tlXHigh
  );

  TToolPermission = record
    Enabled: Boolean;
    AllowedPaths: TArray<string>;
    RequireConfirmation: Boolean;
    MaxFileSize: Int64;
    class function Create(AEnabled: Boolean;
      const APaths: TArray<string> = nil;
      ARequireConfirmation: Boolean = False;
      AMaxFileSize: Int64 = 10485760): TToolPermission; static;
  end;

  TSearchProvider = (
    spNone,
    spGoogle,
    spDuckDuckGo,
    spSearXNG,
    spBrave,
    spSerper,
    spTavily,
    spYouCom,
    spExa,
    spFirecrawl,
    spLinkup,
    spPerplexity,
    spMoonshot
  );

  TSkillDef = record
    Id: string;
    DisplayName: string;
    Description: string;
    Content: string;
    References: string;   // Concatenated reference docs
    Examples: string;     // Concatenated example docs
    class function Create(const AId, ADisplayName, ADescription, AContent: string;
      const AReferences: string = ''; const AExamples: string = ''): TSkillDef; static;
  end;

  TSearchConfig = record
    Enabled: Boolean;
    Provider: TSearchProvider;
    ApiKey: string;
    CustomId: string;
    MaxResults: Integer;
    EnableFetch: Boolean;
    FetchMaxLength: Integer;
    Timeout: Integer;
    class function GetDefault: TSearchConfig; static;
  end;

  TToolPermissions = record
    ReadPerm: TToolPermission;
    WritePerm: TToolPermission;
    EditPerm: TToolPermission;
    BashPerm: TToolPermission;
    GitPerm: TToolPermission;
    SearchPerm: TToolPermission;
  end;

  TApiConfig = record
    Endpoint: string;
    ApiKey: string;
    ModelsEndpoint: string;
    Timeout: Integer;
    RetryCount: Integer;
    RetryDelay: Integer;
    EnableStreaming: Boolean;
    class function GetDefault: TApiConfig; static;
  end;

  TModelConfig = record
    Name: string;
    MaxTokens: Integer;
    Temperature: Double;
    TopP: Double;
    FrequencyPenalty: Double;
    PresencePenalty: Double;
    class function GetDefault: TModelConfig; static;
  end;

  TDirectoriesConfig = record
    Working: string;
    Backup: string;
    Cache: string;
    Logs: string;
    class function GetDefault: TDirectoriesConfig; static;
  end;

  TUIConfig = record
    Theme: string;
    FontSize: Integer;
    FontFamily: string;
    WindowWidth: Integer;
    WindowHeight: Integer;
    Language: string;
    class function GetDefault: TUIConfig; static;
  end;

  TSessionConfig = record
    AutoSave: Boolean;
    AutoSaveInterval: Integer;
    MaxSessions: Integer;
    DefaultThinkingLevel: TThinkingLevel;
    CompactionEnabled: Boolean;
    ReserveTokens: Integer;
    KeepRecentTokens: Integer;
    class function GetDefault: TSessionConfig; static;
  end;

  TLoggingConfig = record
    Level: string;
    MaxFileSize: Int64;
    MaxFiles: Integer;
    class function GetDefault: TLoggingConfig; static;
  end;

  TModelProfile = record
    Id: string;
    DisplayName: string;
    Endpoint: string;
    ApiKey: string;
    ModelName: string;
    MaxTokens: Integer;
    Temperature: Double;
    TopP: Double;
    ThinkingLevel: TThinkingLevel;
    class function Create(const AId, ADisplayName, AEndpoint, AApiKey,
      AModelName: string; AMaxTokens: Integer = 8192;
      ATemperature: Double = 0.7; ATopP: Double = 1.0;
      AThinkingLevel: TThinkingLevel = tlOff): TModelProfile; static;
  end;

  TPiMonoConfig = record
    Version: string;
    Api: TApiConfig;
    Model: TModelConfig;
    Directories: TDirectoriesConfig;
    UI: TUIConfig;
    Permissions: TToolPermissions;
    Session: TSessionConfig;
    Logging: TLoggingConfig;
    Search: TSearchConfig;
    ModelProfiles: TArray<TModelProfile>;
    SkillPool: TArray<TSkillDef>;
    ActiveModelId: string;
    class function GetDefault: TPiMonoConfig; static;
    function ToJson: TJSONObject;
    class function FromJson(AJson: TJSONObject): TPiMonoConfig; static;
    function GetActiveProfile: TModelProfile;
    function FindProfileById(const AId: string): TModelProfile;
  end;

function ThinkingLevelToString(ALevel: TThinkingLevel): string;
function StringToThinkingLevel(const AValue: string): TThinkingLevel;

function SearchProviderToString(AProvider: TSearchProvider): string;
function StringToSearchProvider(const AValue: string): TSearchProvider;

implementation

{ API Key encoding - Base64 to prevent plaintext exposure in config files.
  NOT encryption - provides obscurity only. Keys are decodable.
  Backward compatible: detects unencoded keys (no '==' suffix and short length). }

function EncodeKey(const AKey: string): string;
var
  Bytes: TBytes;
begin
  if AKey = '' then
    Exit('');
  Bytes := TEncoding.UTF8.GetBytes(AKey);
  Result := TNetEncoding.Base64.EncodeBytesToString(Bytes);
end;

function DecodeKey(const AEncoded: string): string;
var
  Bytes: TBytes;
begin
  if AEncoded = '' then
    Exit('');
  // Backward compatibility: if it doesn't look like Base64, treat as plaintext
  // Base64 encoded keys are always longer than original and end with padding
  if (Length(AEncoded) < 20) or
     (AEncoded.Contains(' ') or AEncoded.Contains('|')) then
    Exit(AEncoded);
  try
    Bytes := TNetEncoding.Base64.DecodeStringToBytes(AEncoded);
    Result := TEncoding.UTF8.GetString(Bytes);
    // Validate: decoded key should be reasonable length
    if (Length(Result) < 8) or (Length(Result) > 512) then
      Result := AEncoded;  // Probably wasn't encoded, return as-is
  except
    Result := AEncoded;  // Not valid Base64, return as-is (backward compat)
  end;
end;

{ TSkillDef }

class function TSkillDef.Create(const AId, ADisplayName, ADescription, AContent: string;
  const AReferences: string; const AExamples: string): TSkillDef;
begin
  Result.Id := AId;
  Result.DisplayName := ADisplayName;
  Result.Description := ADescription;
  Result.Content := AContent;
  Result.References := AReferences;
  Result.Examples := AExamples;
end;

{ TSearchConfig }

class function TSearchConfig.GetDefault: TSearchConfig;
begin
  Result.Enabled := False;
  Result.Provider := spNone;
  Result.ApiKey := '';
  Result.CustomId := '';
  Result.MaxResults := 5;
  Result.EnableFetch := True;
  Result.FetchMaxLength := 5000;
  Result.Timeout := 15000;
end;

{ TToolPermission }

class function TToolPermission.Create(AEnabled: Boolean;
  const APaths: TArray<string>; ARequireConfirmation: Boolean;
  AMaxFileSize: Int64): TToolPermission;
begin
  Result.Enabled := AEnabled;
  Result.AllowedPaths := APaths;
  Result.RequireConfirmation := ARequireConfirmation;
  Result.MaxFileSize := AMaxFileSize;
end;

{ TApiConfig }

class function TApiConfig.GetDefault: TApiConfig;
begin
  Result.Endpoint := 'https://api.openai.com/v1/';
  Result.ApiKey := '';
  Result.ModelsEndpoint := '';
  Result.Timeout := 60000;
  Result.RetryCount := 3;
  Result.RetryDelay := 1000;
  Result.EnableStreaming := True;
end;

{ TModelConfig }

class function TModelConfig.GetDefault: TModelConfig;
begin
  Result.Name := '';
  Result.MaxTokens := 8192;
  Result.Temperature := 0.7;
  Result.TopP := 1.0;
  Result.FrequencyPenalty := 0.0;
  Result.PresencePenalty := 0.0;
end;

{ TDirectoriesConfig }

class function TDirectoriesConfig.GetDefault: TDirectoriesConfig;
var
  Home: string;
begin
  Home := GetEnvironmentVariable('USERPROFILE');
  Result.Working := Home + '\Projects';
  Result.Backup := Home + '\Backups\PiMono';
  Result.Cache := GetEnvironmentVariable('LOCALAPPDATA') + '\PiMono\Cache';
  Result.Logs := GetEnvironmentVariable('LOCALAPPDATA') + '\PiMono\Logs';
end;

{ TUIConfig }

class function TUIConfig.GetDefault: TUIConfig;
begin
  Result.Theme := 'cyberpunk-neon';
  Result.FontSize := 12;
  Result.FontFamily := 'Microsoft YaHei';
  Result.WindowWidth := 1200;
  Result.WindowHeight := 800;
  Result.Language := 'en';
end;

{ TSessionConfig }

class function TSessionConfig.GetDefault: TSessionConfig;
begin
  Result.AutoSave := True;
  Result.AutoSaveInterval := 300;
  Result.MaxSessions := 100;
  Result.DefaultThinkingLevel := tlMedium;
  Result.CompactionEnabled := True;
  Result.ReserveTokens := 16384;
  Result.KeepRecentTokens := 20000;
end;

{ TLoggingConfig }

class function TLoggingConfig.GetDefault: TLoggingConfig;
begin
  Result.Level := 'INFO';
  Result.MaxFileSize := 10485760;  // 10 MB
  Result.MaxFiles := 30;
end;

{ TModelProfile }

class function TModelProfile.Create(const AId, ADisplayName, AEndpoint, AApiKey,
  AModelName: string; AMaxTokens: Integer; ATemperature: Double;
  ATopP: Double; AThinkingLevel: TThinkingLevel): TModelProfile;
begin
  Result.Id := AId;
  Result.DisplayName := ADisplayName;
  Result.Endpoint := AEndpoint;
  Result.ApiKey := AApiKey;
  Result.ModelName := AModelName;
  Result.MaxTokens := AMaxTokens;
  Result.Temperature := ATemperature;
  Result.TopP := ATopP;
  Result.ThinkingLevel := AThinkingLevel;
end;

{ TPiMonoConfig }

class function TPiMonoConfig.GetDefault: TPiMonoConfig;
begin
  Result.Version := '1.0';
  Result.Api := TApiConfig.GetDefault;
  Result.Model := TModelConfig.GetDefault;
  Result.Directories := TDirectoriesConfig.GetDefault;
  Result.UI := TUIConfig.GetDefault;
  Result.Session := TSessionConfig.GetDefault;
  Result.Logging := TLoggingConfig.GetDefault;
  Result.Search := TSearchConfig.GetDefault;

  // Default permissions
  Result.Permissions.ReadPerm := TToolPermission.Create(True, nil, False, 10485760);
  Result.Permissions.WritePerm := TToolPermission.Create(True, nil, True);
  Result.Permissions.EditPerm := TToolPermission.Create(True, nil, True);
  Result.Permissions.BashPerm := TToolPermission.Create(False);
  Result.Permissions.GitPerm := TToolPermission.Create(True, nil, False);
  Result.Permissions.SearchPerm := TToolPermission.Create(True, nil, False);

  // Default model profile: leave empty.
  // GetActiveProfile has a fallback that creates a profile from Api.Endpoint
  // when no profiles exist. This prevents MergeConfigs from incorrectly
  // overriding loaded global profiles with uninitialized defaults.
  Result.ActiveModelId := 'default';
  Result.ModelProfiles := nil;

  // Skill pool is loaded from files at runtime (see Settings.SkillStore)
  Result.SkillPool := nil;
end;

function TPiMonoConfig.ToJson: TJSONObject;

  function PathsToJson(const APaths: TArray<string>): TJSONArray;
  var
    i: Integer;
  begin
    Result := TJSONArray.Create;
    for i := 0 to High(APaths) do
      Result.Add(APaths[i]);
  end;

  function PermToJson(const AP: TToolPermission): TJSONObject;
  begin
    Result := TJSONObject.Create;
    Result.AddPair('enabled', TJSONBool.Create(AP.Enabled));
    Result.AddPair('allowedPaths', PathsToJson(AP.AllowedPaths));
    Result.AddPair('requireConfirmation', TJSONBool.Create(AP.RequireConfirmation));
    Result.AddPair('maxFileSize', TJSONNumber.Create(AP.MaxFileSize));
  end;

var
  ApiObj, ModelObj, DirObj, UIObj, PermObj, SessObj, LogObj: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('version', Version);

  // Api
  ApiObj := TJSONObject.Create;
  ApiObj.AddPair('endpoint', Api.Endpoint);
  ApiObj.AddPair('apiKey', EncodeKey(Api.ApiKey));
  ApiObj.AddPair('modelsEndpoint', Api.ModelsEndpoint);
  ApiObj.AddPair('timeout', TJSONNumber.Create(Api.Timeout));
  ApiObj.AddPair('retryCount', TJSONNumber.Create(Api.RetryCount));
  ApiObj.AddPair('retryDelay', TJSONNumber.Create(Api.RetryDelay));
  ApiObj.AddPair('enableStreaming', TJSONBool.Create(Api.EnableStreaming));
  Result.AddPair('api', ApiObj);

  // Model
  ModelObj := TJSONObject.Create;
  ModelObj.AddPair('name', Model.Name);
  ModelObj.AddPair('maxTokens', TJSONNumber.Create(Model.MaxTokens));
  ModelObj.AddPair('temperature', TJSONNumber.Create(Model.Temperature));
  ModelObj.AddPair('topP', TJSONNumber.Create(Model.TopP));
  ModelObj.AddPair('frequencyPenalty', TJSONNumber.Create(Model.FrequencyPenalty));
  ModelObj.AddPair('presencePenalty', TJSONNumber.Create(Model.PresencePenalty));
  Result.AddPair('model', ModelObj);

  // Directories
  DirObj := TJSONObject.Create;
  DirObj.AddPair('working', Directories.Working);
  DirObj.AddPair('backup', Directories.Backup);
  DirObj.AddPair('cache', Directories.Cache);
  DirObj.AddPair('logs', Directories.Logs);
  Result.AddPair('directories', DirObj);

  // UI
  UIObj := TJSONObject.Create;
  UIObj.AddPair('theme', UI.Theme);
  UIObj.AddPair('fontSize', TJSONNumber.Create(UI.FontSize));
  UIObj.AddPair('fontFamily', UI.FontFamily);
  UIObj.AddPair('windowWidth', TJSONNumber.Create(UI.WindowWidth));
  UIObj.AddPair('windowHeight', TJSONNumber.Create(UI.WindowHeight));
  UIObj.AddPair('language', UI.Language);
  Result.AddPair('ui', UIObj);

  // Permissions
  PermObj := TJSONObject.Create;
  PermObj.AddPair('read', PermToJson(Permissions.ReadPerm));
  PermObj.AddPair('write', PermToJson(Permissions.WritePerm));
  PermObj.AddPair('edit', PermToJson(Permissions.EditPerm));
  PermObj.AddPair('bash', PermToJson(Permissions.BashPerm));
  PermObj.AddPair('git', PermToJson(Permissions.GitPerm));
  PermObj.AddPair('search', PermToJson(Permissions.SearchPerm));
  Result.AddPair('permissions', PermObj);

  // Session
  SessObj := TJSONObject.Create;
  SessObj.AddPair('autoSave', TJSONBool.Create(Session.AutoSave));
  SessObj.AddPair('autoSaveInterval', TJSONNumber.Create(Session.AutoSaveInterval));
  SessObj.AddPair('maxSessions', TJSONNumber.Create(Session.MaxSessions));
  SessObj.AddPair('defaultThinkingLevel', ThinkingLevelToString(Session.DefaultThinkingLevel));
  SessObj.AddPair('compactionEnabled', TJSONBool.Create(Session.CompactionEnabled));
  SessObj.AddPair('reserveTokens', TJSONNumber.Create(Session.ReserveTokens));
  SessObj.AddPair('keepRecentTokens', TJSONNumber.Create(Session.KeepRecentTokens));
  Result.AddPair('session', SessObj);

  // Logging
  LogObj := TJSONObject.Create;
  LogObj.AddPair('level', Logging.Level);
  LogObj.AddPair('maxFileSize', TJSONNumber.Create(Logging.MaxFileSize));
  LogObj.AddPair('maxFiles', TJSONNumber.Create(Logging.MaxFiles));
  Result.AddPair('logging', LogObj);

  // Search
  var SearchObj := TJSONObject.Create;
  SearchObj.AddPair('enabled', TJSONBool.Create(Search.Enabled));
  SearchObj.AddPair('provider', SearchProviderToString(Search.Provider));
  SearchObj.AddPair('apiKey', EncodeKey(Search.ApiKey));
  SearchObj.AddPair('customId', Search.CustomId);
  SearchObj.AddPair('maxResults', TJSONNumber.Create(Search.MaxResults));
  SearchObj.AddPair('enableFetch', TJSONBool.Create(Search.EnableFetch));
  SearchObj.AddPair('fetchMaxLength', TJSONNumber.Create(Search.FetchMaxLength));
  SearchObj.AddPair('timeout', TJSONNumber.Create(Search.Timeout));
  Result.AddPair('search', SearchObj);

  // Model profiles
  Result.AddPair('activeModelId', ActiveModelId);
  var ProfilesArr := TJSONArray.Create;
  for var pi := 0 to High(ModelProfiles) do
  begin
    var PO := TJSONObject.Create;
    PO.AddPair('id', ModelProfiles[pi].Id);
    PO.AddPair('displayName', ModelProfiles[pi].DisplayName);
    PO.AddPair('endpoint', ModelProfiles[pi].Endpoint);
    PO.AddPair('apiKey', EncodeKey(ModelProfiles[pi].ApiKey));
    PO.AddPair('modelName', ModelProfiles[pi].ModelName);
    PO.AddPair('maxTokens', TJSONNumber.Create(ModelProfiles[pi].MaxTokens));
    PO.AddPair('temperature', TJSONNumber.Create(ModelProfiles[pi].Temperature));
    PO.AddPair('topP', TJSONNumber.Create(ModelProfiles[pi].TopP));
    PO.AddPair('thinkingLevel', ThinkingLevelToString(ModelProfiles[pi].ThinkingLevel));
    ProfilesArr.Add(PO);
  end;
  Result.AddPair('modelProfiles', ProfilesArr);
end;

class function TPiMonoConfig.FromJson(AJson: TJSONObject): TPiMonoConfig;

  procedure ParsePaths(Arr: TJSONArray; out APaths: TArray<string>);
  var
    i: Integer;
  begin
    if Arr = nil then
    begin
      APaths := nil;
      Exit;
    end;
    SetLength(APaths, Arr.Count);
    for i := 0 to Arr.Count - 1 do
      APaths[i] := Arr.Items[i].Value;
  end;

  procedure ParsePerm(PObj: TJSONObject; out AP: TToolPermission);
  var
    PathsArr: TJSONArray;
  begin
    AP.Enabled := JsonGetBool(PObj, 'enabled', True);
    PathsArr := PObj.GetValue('allowedPaths') as TJSONArray;
    ParsePaths(PathsArr, AP.AllowedPaths);
    AP.RequireConfirmation := JsonGetBool(PObj, 'requireConfirmation', False);
    AP.MaxFileSize := JsonGetInt64(PObj, 'maxFileSize', 10485760);
  end;

var
  Obj, PermObj: TJSONObject;
begin
  Result := TPiMonoConfig.GetDefault;
  if AJson = nil then
    Exit;

  Result.Version := JsonGetStr(AJson, 'version', '1.0');

  // Api
  if AJson.TryGetValue('api', Obj) then
  begin
    Result.Api.Endpoint := JsonGetStr(Obj, 'endpoint', Result.Api.Endpoint);
    Result.Api.ApiKey := DecodeKey(JsonGetStr(Obj, 'apiKey', ''));
    Result.Api.ModelsEndpoint := JsonGetStr(Obj, 'modelsEndpoint', Result.Api.ModelsEndpoint);
    Result.Api.Timeout := JsonGetInt(Obj, 'timeout', Result.Api.Timeout);
    Result.Api.RetryCount := JsonGetInt(Obj, 'retryCount', Result.Api.RetryCount);
    Result.Api.RetryDelay := JsonGetInt(Obj, 'retryDelay', Result.Api.RetryDelay);
    Result.Api.EnableStreaming := JsonGetBool(Obj, 'enableStreaming', Result.Api.EnableStreaming);
  end;

  // Model
  if AJson.TryGetValue('model', Obj) then
  begin
    Result.Model.Name := JsonGetStr(Obj, 'name', Result.Model.Name);
    Result.Model.MaxTokens := JsonGetInt(Obj, 'maxTokens', Result.Model.MaxTokens);
    Result.Model.Temperature := JsonGetDbl(Obj, 'temperature', Result.Model.Temperature);
    Result.Model.TopP := JsonGetDbl(Obj, 'topP', Result.Model.TopP);
    Result.Model.FrequencyPenalty := JsonGetDbl(Obj, 'frequencyPenalty', Result.Model.FrequencyPenalty);
    Result.Model.PresencePenalty := JsonGetDbl(Obj, 'presencePenalty', Result.Model.PresencePenalty);
  end;

  // Directories
  if AJson.TryGetValue('directories', Obj) then
  begin
    Result.Directories.Working := JsonGetStr(Obj, 'working', Result.Directories.Working);
    Result.Directories.Backup := JsonGetStr(Obj, 'backup', Result.Directories.Backup);
    Result.Directories.Cache := JsonGetStr(Obj, 'cache', Result.Directories.Cache);
    Result.Directories.Logs := JsonGetStr(Obj, 'logs', Result.Directories.Logs);
  end;

  // UI
  if AJson.TryGetValue('ui', Obj) then
  begin
    Result.UI.Theme := JsonGetStr(Obj, 'theme', Result.UI.Theme);
    Result.UI.FontSize := JsonGetInt(Obj, 'fontSize', Result.UI.FontSize);
    Result.UI.FontFamily := JsonGetStr(Obj, 'fontFamily', Result.UI.FontFamily);
    Result.UI.WindowWidth := JsonGetInt(Obj, 'windowWidth', Result.UI.WindowWidth);
    Result.UI.WindowHeight := JsonGetInt(Obj, 'windowHeight', Result.UI.WindowHeight);
    Result.UI.Language := JsonGetStr(Obj, 'language', Result.UI.Language);
  end;

  // Permissions
  if AJson.TryGetValue('permissions', Obj) then
  begin
    if Obj.TryGetValue('read', PermObj) then ParsePerm(PermObj, Result.Permissions.ReadPerm);
    if Obj.TryGetValue('write', PermObj) then ParsePerm(PermObj, Result.Permissions.WritePerm);
    if Obj.TryGetValue('edit', PermObj) then ParsePerm(PermObj, Result.Permissions.EditPerm);
    if Obj.TryGetValue('bash', PermObj) then ParsePerm(PermObj, Result.Permissions.BashPerm);
    if Obj.TryGetValue('git', PermObj) then ParsePerm(PermObj, Result.Permissions.GitPerm);
    if Obj.TryGetValue('search', PermObj) then ParsePerm(PermObj, Result.Permissions.SearchPerm);
  end;

  // Search
  if AJson.TryGetValue('search', Obj) then
  begin
    Result.Search.Enabled := JsonGetBool(Obj, 'enabled', Result.Search.Enabled);
    Result.Search.Provider := StringToSearchProvider(JsonGetStr(Obj, 'provider', 'none'));
    Result.Search.ApiKey := DecodeKey(JsonGetStr(Obj, 'apiKey', ''));
    Result.Search.CustomId := JsonGetStr(Obj, 'customId', Result.Search.CustomId);
    Result.Search.MaxResults := JsonGetInt(Obj, 'maxResults', Result.Search.MaxResults);
    Result.Search.EnableFetch := JsonGetBool(Obj, 'enableFetch', Result.Search.EnableFetch);
    Result.Search.FetchMaxLength := JsonGetInt(Obj, 'fetchMaxLength', Result.Search.FetchMaxLength);
    Result.Search.Timeout := JsonGetInt(Obj, 'timeout', Result.Search.Timeout);
  end;

  // Session
  if AJson.TryGetValue('session', Obj) then
  begin
    Result.Session.AutoSave := JsonGetBool(Obj, 'autoSave', Result.Session.AutoSave);
    Result.Session.AutoSaveInterval := JsonGetInt(Obj, 'autoSaveInterval', Result.Session.AutoSaveInterval);
    Result.Session.MaxSessions := JsonGetInt(Obj, 'maxSessions', Result.Session.MaxSessions);
    Result.Session.DefaultThinkingLevel := StringToThinkingLevel(
      JsonGetStr(Obj, 'defaultThinkingLevel', 'medium'));
    Result.Session.CompactionEnabled := JsonGetBool(Obj, 'compactionEnabled', Result.Session.CompactionEnabled);
    Result.Session.ReserveTokens := JsonGetInt(Obj, 'reserveTokens', Result.Session.ReserveTokens);
    Result.Session.KeepRecentTokens := JsonGetInt(Obj, 'keepRecentTokens', Result.Session.KeepRecentTokens);
  end;

  // Logging
  if AJson.TryGetValue('logging', Obj) then
  begin
    Result.Logging.Level := JsonGetStr(Obj, 'level', Result.Logging.Level);
    Result.Logging.MaxFileSize := JsonGetInt64(Obj, 'maxFileSize', Result.Logging.MaxFileSize);
    Result.Logging.MaxFiles := JsonGetInt(Obj, 'maxFiles', Result.Logging.MaxFiles);
  end;

  // Model profiles
  Result.ActiveModelId := JsonGetStr(AJson, 'activeModelId', Result.ActiveModelId);
  var ProfilesVal: TJSONValue;
  if AJson.TryGetValue('modelProfiles', ProfilesVal) and (ProfilesVal is TJSONArray) then
  begin
    var ProfilesArr := TJSONArray(ProfilesVal);
    SetLength(Result.ModelProfiles, ProfilesArr.Count);
    for var pi := 0 to ProfilesArr.Count - 1 do
    begin
      var PO := ProfilesArr.Items[pi] as TJSONObject;
      Result.ModelProfiles[pi].Id := JsonGetStr(PO, 'id', 'profile_' + IntToStr(pi));
      Result.ModelProfiles[pi].DisplayName := JsonGetStr(PO, 'displayName', 'Profile ' + IntToStr(pi + 1));
      Result.ModelProfiles[pi].Endpoint := JsonGetStr(PO, 'endpoint', Result.Api.Endpoint);
      Result.ModelProfiles[pi].ApiKey := DecodeKey(JsonGetStr(PO, 'apiKey', ''));
      Result.ModelProfiles[pi].ModelName := JsonGetStr(PO, 'modelName', Result.Model.Name);
      Result.ModelProfiles[pi].MaxTokens := JsonGetInt(PO, 'maxTokens', Result.Model.MaxTokens);
      Result.ModelProfiles[pi].Temperature := JsonGetDbl(PO, 'temperature', Result.Model.Temperature);
      Result.ModelProfiles[pi].TopP := JsonGetDbl(PO, 'topP', Result.Model.TopP);
      Result.ModelProfiles[pi].ThinkingLevel := StringToThinkingLevel(
        JsonGetStr(PO, 'thinkingLevel', ThinkingLevelToString(Result.Session.DefaultThinkingLevel)));
    end;
  end;

end;

function TPiMonoConfig.GetActiveProfile: TModelProfile;
begin
  Result := FindProfileById(ActiveModelId);
  if Result.Id = '' then
  begin
    // Fallback to first profile or default
    if Length(ModelProfiles) > 0 then
      Result := ModelProfiles[0]
    else
      Result := TModelProfile.Create('default', 'Default',
        Api.Endpoint, Api.ApiKey, Model.Name, Model.MaxTokens, Model.Temperature,
        Model.TopP, Session.DefaultThinkingLevel);
  end;
  // If profile has empty fields, fall back to global config
  if Result.ApiKey = '' then
    Result.ApiKey := Api.ApiKey;
  if Result.Endpoint = '' then
    Result.Endpoint := Api.Endpoint;
  if Result.ModelName = '' then
    Result.ModelName := Model.Name;
  if Result.TopP = 0 then
    Result.TopP := Model.TopP;
  if Result.ThinkingLevel = tlOff then
    Result.ThinkingLevel := Session.DefaultThinkingLevel;
end;

function TPiMonoConfig.FindProfileById(const AId: string): TModelProfile;
var
  i: Integer;
begin
  Result := Default(TModelProfile);
  for i := 0 to High(ModelProfiles) do
    if ModelProfiles[i].Id = AId then
    begin
      Result := ModelProfiles[i];
      Exit;
    end;
end;

{ Helpers }

function ThinkingLevelToString(ALevel: TThinkingLevel): string;
begin
  case ALevel of
    tlOff:     Result := 'off';
    tlMinimal: Result := 'minimal';
    tlLow:     Result := 'low';
    tlMedium:  Result := 'medium';
    tlHigh:    Result := 'high';
    tlXHigh:   Result := 'xhigh';
  else
    Result := 'medium';
  end;
end;

function StringToThinkingLevel(const AValue: string): TThinkingLevel;
begin
  if AValue = 'off' then Result := tlOff
  else if AValue = 'minimal' then Result := tlMinimal
  else if AValue = 'low' then Result := tlLow
  else if AValue = 'medium' then Result := tlMedium
  else if AValue = 'high' then Result := tlHigh
  else if AValue = 'xhigh' then Result := tlXHigh
  else Result := tlMedium;
end;

function SearchProviderToString(AProvider: TSearchProvider): string;
begin
  case AProvider of
    spNone:        Result := 'none';
    spGoogle:      Result := 'google';
    spDuckDuckGo:  Result := 'duckduckgo';
    spSearXNG:     Result := 'searxng';
    spBrave:       Result := 'brave';
    spSerper:      Result := 'serper';
    spTavily:      Result := 'tavily';
    spYouCom:      Result := 'youcom';
    spExa:         Result := 'exa';
    spFirecrawl:   Result := 'firecrawl';
    spLinkup:      Result := 'linkup';
    spPerplexity:  Result := 'perplexity';
    spMoonshot:    Result := 'moonshot';
  else
    Result := 'none';
  end;
end;

function StringToSearchProvider(const AValue: string): TSearchProvider;
begin
  if AValue = 'google' then Result := spGoogle
  else if AValue = 'duckduckgo' then Result := spDuckDuckGo
  else if AValue = 'searxng' then Result := spSearXNG
  else if AValue = 'brave' then Result := spBrave
  else if AValue = 'serper' then Result := spSerper
  else if AValue = 'tavily' then Result := spTavily
  else if AValue = 'youcom' then Result := spYouCom
  else if AValue = 'exa' then Result := spExa
  else if AValue = 'firecrawl' then Result := spFirecrawl
  else if AValue = 'linkup' then Result := spLinkup
  else if AValue = 'perplexity' then Result := spPerplexity
  else if AValue = 'moonshot' then Result := spMoonshot
  else Result := spNone;
end;

end.
