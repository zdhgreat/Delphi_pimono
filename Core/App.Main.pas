unit App.Main;

interface

uses
  System.SysUtils, System.IOUtils,
  Settings.Config, Settings.SkillStore,
  Utils.Logger;

procedure InitializeApp;
procedure FinalizeApp;
function LoadProjectContext(const AWorkingDir: string): string;
function DetectGitBranch(const AWorkingDir: string): string;
function LoadSkillFile(const ASkillName: string): string;

implementation

var
  FAppInitialized: Boolean = False;

  function StripFrontmatter(const AContent: string): string;
  var
    EndPos: Integer;
  begin
    Result := AContent;
    if Result.StartsWith('---') then
    begin
      EndPos := Pos('---', Result, 4);
      if EndPos > 0 then
        Result := Copy(Result, EndPos + 3, MaxInt).Trim;
    end;
  end;

procedure InitializeApp;
var
  LogDir, ConfigDir, SessionDir: string;
  DefaultConfig: TPiMonoConfig;
  ConfigFile: string;
begin
  if FAppInitialized then
    Exit;

  // Ensure core directories exist
  LogDir := IncludeTrailingPathDelimiter(GetEnvironmentVariable('LOCALAPPDATA')) + 'PiMono\Logs';
  ConfigDir := IncludeTrailingPathDelimiter(GetEnvironmentVariable('APPDATA')) + 'PiMono';
  SessionDir := IncludeTrailingPathDelimiter(GetEnvironmentVariable('APPDATA')) + 'PiMono\sessions';

  if not DirectoryExists(LogDir) then
    ForceDirectories(LogDir);
  if not DirectoryExists(ConfigDir) then
    ForceDirectories(ConfigDir);
  if not DirectoryExists(SessionDir) then
    ForceDirectories(SessionDir);

  // Seed default global config if none exists
  ConfigFile := ConfigDir + 'settings.json';
  if not FileExists(ConfigFile) then
  begin
    DefaultConfig := TPiMonoConfig.GetDefault;
    var Json := DefaultConfig.ToJson;
    try
      TFile.WriteAllText(ConfigFile, Json.Format(2), TEncoding.UTF8);
    finally
      Json.Free;
    end;
  end;

  FAppInitialized := True;
end;

procedure FinalizeApp;
begin
  // Flush logger if needed
  TLoggerFactory.Finalize;
  FAppInitialized := False;
end;

function LoadProjectContext(const AWorkingDir: string): string;
var
  Files: TArray<string>;
  i: Integer;
  Content: string;
begin
  Result := '';

  // Look for context files in priority order
  Files := TArray<string>.Create(
    'AGENTS.md', 'CLAUDE.md', '.agents', '.claude',
    '.pi\instructions.md', '.pi\context.md');

  for i := 0 to High(Files) do
  begin
    var Path := IncludeTrailingPathDelimiter(AWorkingDir) + Files[i];
    if FileExists(Path) then
    begin
      try
        Content := TFile.ReadAllText(Path, TEncoding.UTF8).Trim;
        if Content <> '' then
        begin
          if Result <> '' then
            Result := Result + #10#10;
          Result := Result + '--- ' + ExtractFileName(Path) + ' ---' + #10 + Content;
        end;
      except
        on E: Exception do
          ;  // Skip unreadable context files silently (logger may not be initialized yet)
      end;
    end;
  end;
end;

function DetectGitBranch(const AWorkingDir: string): string;
var
  HeadPath, Content: string;
  RefPath: string;
begin
  Result := '';
  HeadPath := IncludeTrailingPathDelimiter(AWorkingDir) + '.git\HEAD';
  if not FileExists(HeadPath) then
    Exit;
  try
    Content := TFile.ReadAllText(HeadPath, TEncoding.UTF8).Trim;
    // Format: "ref: refs/heads/branch-name"
    if Content.StartsWith('ref: ') then
    begin
      RefPath := Content.Substring(5);  // Remove "ref: "
      Result := RefPath.Substring(RefPath.LastIndexOf('/') + 1);
    end
    else
      // Detached HEAD - show short hash
      Result := Copy(Content, 1, 7);
  except
    Result := '';
  end;
end;

function LoadSkillFile(const ASkillName: string): string;
var
  WorkDir, SkillsDir, SkillPath, Dir: string;
  Content, Refs, Exs: string;
begin
  Result := '';

  // Validate skill name to prevent path traversal
  if (ASkillName = '') or (Pos('..', ASkillName) > 0) or
     (Pos('\', ASkillName) > 0) or (Pos('/', ASkillName) > 0) or
     (Pos('%', ASkillName) > 0) or  // Block URL-encoded traversal
     (Pos(#0, ASkillName) > 0) then  // Block null byte injection
    Exit('');

  WorkDir := GetCurrentDir;
  SkillsDir := IncludeTrailingPathDelimiter(WorkDir) + '.pi\skills';

  // 1. Try project-local: .pi\skills\<name>  (directory-based)
  SkillPath := IncludeTrailingPathDelimiter(SkillsDir) + ASkillName + '\SKILL.md';
  if FileExists(SkillPath) then
  begin
    try
      Content := StripFrontmatter(TFile.ReadAllText(SkillPath, TEncoding.UTF8).Trim);
      Result := Content;
      Dir := IncludeTrailingPathDelimiter(SkillsDir) + ASkillName;
      Refs := ReadSubDirDocs(Dir, 'references');
      Exs := ReadSubDirDocs(Dir, 'examples');
      if Refs <> '' then Result := Result + #10#10 + '--- References ---' + #10 + Refs;
      if Exs <> '' then Result := Result + #10#10 + '--- Examples ---' + #10 + Exs;
      Exit;
    except
      Result := '';
    end;
  end;

  // 2. Try project-local: .pi\skills\<name>.md (legacy flat file)
  SkillPath := IncludeTrailingPathDelimiter(SkillsDir) + ASkillName + '.md';
  if FileExists(SkillPath) then
  begin
    try
      Result := TFile.ReadAllText(SkillPath, TEncoding.UTF8).Trim;
    except
      Result := '';
    end;
    Exit;
  end;

  // 3. Try global skill store: %APPDATA%\PiMono\skills\<name>\
  if FileExists(SkillFilePath(ASkillName)) then
  begin
    try
      Content := StripFrontmatter(TFile.ReadAllText(SkillFilePath(ASkillName), TEncoding.UTF8).Trim);
      Result := Content;
      Dir := SkillDirPath(ASkillName);
      Refs := ReadSubDirDocs(Dir, 'references');
      Exs := ReadSubDirDocs(Dir, 'examples');
      if Refs <> '' then Result := Result + #10#10 + '--- References ---' + #10 + Refs;
      if Exs <> '' then Result := Result + #10#10 + '--- Examples ---' + #10 + Exs;
    except
      Result := '';
    end;
  end;
end;

end.
