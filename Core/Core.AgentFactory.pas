unit Core.AgentFactory;

{ TAgentFactory - Shared factory for creating and configuring TAgent instances.
  Eliminates code duplication between TMainForm and TSessionChatForm. }

interface

uses
  System.SysUtils,
  Core.Agent, Core.AgentState, Core.UndoLog,
  AI.IModel, AI.CustomAPIAdapter, AI.ModelConfig,
  Settings.Config, Settings.SettingsManager,
  Tools.FileTools, Tools.ToolRegistry, Tools.ITool, Tools.BashTool, Tools.GitTool,
  Utils.Logger,
  App.Main;

type
  TAgentFactory = class
  public
    class function CreateAgent(ALogger: TLogger;
      ASettingsManager: TSettingsManager; AUndoLog: TUndoLog): TAgent;
    class procedure ConnectModel(AAgent: TAgent;
      ASettingsManager: TSettingsManager; ALogger: TLogger;
      out AModelAdapter: TCustomAPIAdapter);
    class procedure BuildSystemPrompt(AAgent: TAgent;
      ASettingsManager: TSettingsManager);
  end;

implementation

{ TAgentFactory }

class function TAgentFactory.CreateAgent(ALogger: TLogger;
  ASettingsManager: TSettingsManager; AUndoLog: TUndoLog): TAgent;
var
  WorkingDir: string;
  Tools: TArray<IAgentTool>;
  GitTools: TArray<IAgentTool>;
  gi, ti: Integer;
begin
  Result := TAgent.Create(ALogger);

  WorkingDir := ASettingsManager.Config.Directories.Working;
  if WorkingDir = '' then
    WorkingDir := GetCurrentDir;

  BuildSystemPrompt(Result, ASettingsManager);

  Tools := CreateAllTools(WorkingDir);
  SetLength(Tools, Length(Tools) + 1);
  Tools[High(Tools)] := CreateBashTool(WorkingDir);
  GitTools := CreateGitTools(WorkingDir);
  SetLength(Tools, Length(Tools) + Length(GitTools));
  for gi := 0 to High(GitTools) do
    Tools[Length(Tools) - Length(GitTools) + gi] := GitTools[gi];
  for ti := 0 to High(Tools) do
    if (Tools[ti] as TInterfacedObject) is TBaseTool then
      TBaseTool(Tools[ti] as TInterfacedObject).UndoLog := AUndoLog;
  Result.SetTools(Tools);
  Result.SetPermissions(ASettingsManager.Config.Permissions);
end;

class procedure TAgentFactory.ConnectModel(AAgent: TAgent;
  ASettingsManager: TSettingsManager; ALogger: TLogger;
  out AModelAdapter: TCustomAPIAdapter);
var
  Config: TPiMonoConfig;
  Profile: TModelProfile;
  ModelInfo: TModelInfo;
  ModelConfig: TModelConfig;
begin
  Config := ASettingsManager.Config;
  Profile := Config.GetActiveProfile;

  ModelInfo := TModelInfo.Create(
    Profile.ModelName, Profile.ModelName, 'internal', Profile.Endpoint);

  AModelAdapter := TCustomAPIAdapter.Create(
    ModelInfo, Profile.ApiKey, ALogger,
    Config.Api.RetryCount, 2000, Config.Api.Timeout);
  AAgent.SetModelRef(AModelAdapter);

  // Apply profile model settings (TopP, Temperature, MaxTokens)
  ModelConfig := TModelConfig.GetDefault;
  ModelConfig.Name := Profile.ModelName;
  ModelConfig.MaxTokens := Profile.MaxTokens;
  ModelConfig.Temperature := Profile.Temperature;
  ModelConfig.TopP := Profile.TopP;
  AAgent.SetModel(ModelConfig);

  // Apply profile thinking level
  AAgent.SetThinkingLevel(Profile.ThinkingLevel);

  AAgent.SetCompactionSettings(
    Config.Session.CompactionEnabled, Config.Session.ReserveTokens,
    Config.Session.KeepRecentTokens, 128000);
end;

class procedure TAgentFactory.BuildSystemPrompt(AAgent: TAgent;
  ASettingsManager: TSettingsManager);
var
  WorkingDir, Branch, Context: string;
  SB: TStringBuilder;
begin
  WorkingDir := ASettingsManager.Config.Directories.Working;
  if WorkingDir = '' then
    WorkingDir := GetCurrentDir;

  Context := LoadProjectContext(WorkingDir);
  Branch := DetectGitBranch(WorkingDir);

  SB := TStringBuilder.Create;
  try
    SB.AppendLine('You are PiMono Agent, an AI coding assistant.');
    SB.AppendLine('You help users with coding tasks, file operations, and software development.');
    if Branch <> '' then
      SB.AppendLine('Current git branch: ' + Branch);
    SB.AppendLine('Working directory: ' + WorkingDir);
    if Context <> '' then
    begin
      SB.AppendLine('');
      SB.AppendLine('--- Project Context ---');
      SB.AppendLine(Context);
    end;
    AAgent.SetSystemPrompt(SB.ToString);
  finally
    SB.Free;
  end;
end;

end.
