unit Core.SessionManager;

interface

uses
  System.SysUtils, System.JSON, System.IOUtils, System.Classes,
  System.Generics.Collections, System.Generics.Defaults,
  System.DateUtils, System.Math, System.SyncObjs,
  Core.Messages, Utils.Logger, Utils.JsonHelper;

type
  TSession = class
  private
    FId: string;
    FName: string;
    FCreatedAt: TDateTime;
    FUpdatedAt: TDateTime;
    FMessages: TAgentMessageList;
    FSystemPrompt: string;
    FFilePath: string;
    FSavedCount: Integer;     // How many messages already written to disk
    FParentId: string;        // Parent session ID (for branches)
    FBranchPoint: Integer;    // Message index where branch diverged (-1 if not a branch)
    FNeedFullWrite: Boolean;  // True after compaction/rename — rewrite entire file
    FHeaderDirty: Boolean;    // True when header needs timestamp update
    FSkills: TArray<string>;  // Bound skill IDs from the public pool

    function HeaderToJson: TJSONObject;
    class function HeaderFromJson(AJson: TJSONObject; out AId, AName, AParentId: string;
      out ACreatedAt, AUpdatedAt: TDateTime; out ASystemPrompt: string;
      out ABranchPoint: Integer; out ASkills: TArray<string>): Boolean; static;
  public
    constructor Create(const AId: string = '');
    destructor Destroy; override;

    function ToJson: TJSONObject;
    class function FromJson(AJson: TJSONObject): TSession; static;

    procedure AddMessage(AMessage: TAgentMessage);
    function GetMessageCount: Integer;
    function BranchFrom(AMessageIndex: Integer): TSession;

    property Id: string read FId;
    property Name: string read FName write FName;
    property CreatedAt: TDateTime read FCreatedAt;
    property UpdatedAt: TDateTime read FUpdatedAt;
    property Messages: TAgentMessageList read FMessages;
    property SystemPrompt: string read FSystemPrompt write FSystemPrompt;
    property FilePath: string read FFilePath write FFilePath;
    property ParentId: string read FParentId;
    property BranchPoint: Integer read FBranchPoint;
    property SavedCount: Integer read FSavedCount write FSavedCount;
    property NeedFullWrite: Boolean read FNeedFullWrite write FNeedFullWrite;
    property Skills: TArray<string> read FSkills write FSkills;
  end;

  TSessionInfo = record
    Id: string;
    Name: string;
    CreatedAt: TDateTime;
    UpdatedAt: TDateTime;
    MessageCount: Integer;
    ParentId: string;
    BranchPoint: Integer;
    function DisplayName: string;
    function IsBranch: Boolean;
  end;

  TSessionManager = class
  private
    FSessionDir: string;
    FCurrentSession: TSession;
    FLogger: TLogger;
    FAutoSave: Boolean;
    FAutoSaveInterval: Integer;
    FMaxSessions: Integer;
    FLock: TObject;  // Reentrant lock via TMonitor

    function GenerateId: string;
    function GetSessionPath(const AId: string): string;
    function GetLegacyPath(const AId: string): string;
    function DoLoadSessionById(const AId: string): TSession;
    procedure MigrateLegacySession(const AJsonPath: string);
    procedure MigrateLegacySessions;
    procedure UpdateHeaderTimestamp(ASession: TSession);
  public
    constructor Create(ALogger: TLogger = nil;
      const ASessionDir: string = '');
    destructor Destroy; override;

    function CreateSession(const AName: string = ''): TSession;
    function LoadSession(const AId: string): TSession;
    function LoadSessionById(const AId: string): TSession;
    procedure SaveSession(ASession: TSession);
    procedure DeleteSession(const AId: string);
    function ListSessions: TArray<TSessionInfo>;
    function RenameSession(const AId, ANewName: string): Boolean;
    function SessionExists(const AId: string): Boolean;

    procedure SetCurrentSession(ASession: TSession);
    function GetCurrentSession: TSession;
    procedure SaveCurrent;

    property CurrentSession: TSession read GetCurrentSession;
    property SessionDir: string read FSessionDir;
    property AutoSave: Boolean read FAutoSave write FAutoSave;
  end;

implementation

{ TSession }

constructor TSession.Create(const AId: string);
var
  GUID: TGUID;
begin
  inherited Create;
  if AId <> '' then
    FId := AId
  else
  begin
    CreateGUID(GUID);
    FId := Format('%.8x%.4x%.4x%.2x%.2x%.2x%.2x%.2x%.2x%.2x%.2x',
      [GUID.D1, GUID.D2, GUID.D3,
       GUID.D4[0], GUID.D4[1], GUID.D4[2], GUID.D4[3],
       GUID.D4[4], GUID.D4[5], GUID.D4[6], GUID.D4[7]]);
  end;
  FName := 'New Session';
  FCreatedAt := Now;
  FUpdatedAt := Now;
  FMessages := TAgentMessageList.Create;
  FSystemPrompt := '';
  FFilePath := '';
  FSavedCount := 0;
  FParentId := '';
  FBranchPoint := -1;
  FNeedFullWrite := False;
  FHeaderDirty := False;
  FSkills := nil;
end;

destructor TSession.Destroy;
begin
  FMessages.Free;
  inherited;
end;

function TSession.HeaderToJson: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'header');
  Result.AddPair('id', FId);
  Result.AddPair('name', FName);
  Result.AddPair('createdAt', TJSONNumber.Create(DateTimeToUnix(FCreatedAt, False)));
  Result.AddPair('updatedAt', TJSONNumber.Create(DateTimeToUnix(FUpdatedAt, False)));
  Result.AddPair('systemPrompt', FSystemPrompt);
  Result.AddPair('messageCount', TJSONNumber.Create(FMessages.Count));
  if FParentId <> '' then
  begin
    Result.AddPair('parentId', FParentId);
    Result.AddPair('branchPoint', TJSONNumber.Create(FBranchPoint));
  end;

  // Skills
  if Length(FSkills) > 0 then
  begin
    var SkillsArr := TJSONArray.Create;
    for var si := 0 to High(FSkills) do
      SkillsArr.Add(FSkills[si]);
    Result.AddPair('skills', SkillsArr);
  end;
end;

class function TSession.HeaderFromJson(AJson: TJSONObject;
  out AId, AName, AParentId: string;
  out ACreatedAt, AUpdatedAt: TDateTime; out ASystemPrompt: string;
  out ABranchPoint: Integer; out ASkills: TArray<string>): Boolean;
var
  SkillsArr: TJSONArray;
  i: Integer;
begin
  Result := False;
  ASkills := nil;
  if JsonGetStr(AJson, 'type', '') <> 'header' then
    Exit;
  AId := JsonGetStr(AJson, 'id', '');
  AName := JsonGetStr(AJson, 'name', 'Untitled');
  ACreatedAt := UnixToDateTime(JsonGetInt64(AJson, 'createdAt', 0), False);
  AUpdatedAt := UnixToDateTime(JsonGetInt64(AJson, 'updatedAt', 0), False);
  ASystemPrompt := JsonGetStr(AJson, 'systemPrompt', '');
  AParentId := JsonGetStr(AJson, 'parentId', '');
  ABranchPoint := JsonGetInt(AJson, 'branchPoint', -1);

  // Parse skills array
  SkillsArr := AJson.GetValue('skills') as TJSONArray;
  if SkillsArr <> nil then
  begin
    SetLength(ASkills, SkillsArr.Count);
    for i := 0 to SkillsArr.Count - 1 do
      ASkills[i] := SkillsArr.Items[i].Value;
  end;

  Result := True;
end;

function TSession.ToJson: TJSONObject;
var
  MsgArr: TJSONArray;
  i: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', FId);
  Result.AddPair('name', FName);
  Result.AddPair('createdAt', TJSONNumber.Create(DateTimeToUnix(FCreatedAt, False)));
  Result.AddPair('updatedAt', TJSONNumber.Create(DateTimeToUnix(FUpdatedAt, False)));
  Result.AddPair('systemPrompt', FSystemPrompt);

  // Skills
  if Length(FSkills) > 0 then
  begin
    var SkillsArr := TJSONArray.Create;
    for i := 0 to High(FSkills) do
      SkillsArr.Add(FSkills[i]);
    Result.AddPair('skills', SkillsArr);
  end;

  MsgArr := TJSONArray.Create;
  for i := 0 to FMessages.Count - 1 do
    MsgArr.AddElement(FMessages[i].ToJson);
  Result.AddPair('messages', MsgArr);
end;

class function TSession.FromJson(AJson: TJSONObject): TSession;
var
  Id, Name: string;
  MsgArr: TJSONArray;
  i: Integer;
  Msg: TAgentMessage;
begin
  Id := JsonGetStr(AJson, 'id', '');
  Name := JsonGetStr(AJson, 'name', 'Untitled');

  Result := TSession.Create(Id);
  Result.FName := Name;
  Result.FCreatedAt := UnixToDateTime(JsonGetInt64(AJson, 'createdAt', 0), False);
  Result.FUpdatedAt := UnixToDateTime(JsonGetInt64(AJson, 'updatedAt', 0), False);
  Result.FSystemPrompt := JsonGetStr(AJson, 'systemPrompt', '');

  // Parse skills
  var SkillsArr := AJson.GetValue('skills') as TJSONArray;
  if SkillsArr <> nil then
  begin
    SetLength(Result.FSkills, SkillsArr.Count);
    for i := 0 to SkillsArr.Count - 1 do
      Result.FSkills[i] := SkillsArr.Items[i].Value;
  end;

  MsgArr := AJson.GetValue('messages') as TJSONArray;
  if MsgArr <> nil then
  begin
    for i := 0 to MsgArr.Count - 1 do
    begin
      var MsgObj := MsgArr.Items[i] as TJSONObject;
      Msg := TAgentMessage.FromJson(MsgObj);
      if Msg <> nil then
        Result.FMessages.Add(Msg);
    end;
  end;
end;

procedure TSession.AddMessage(AMessage: TAgentMessage);
begin
  FMessages.Add(AMessage);
  FUpdatedAt := Now;
end;

function TSession.GetMessageCount: Integer;
begin
  Result := FMessages.Count;
end;

function TSession.BranchFrom(AMessageIndex: Integer): TSession;
var
  i: Integer;
begin
  Result := TSession.Create;
  Result.FName := FName + ' (branch)';
  Result.FSystemPrompt := FSystemPrompt;
  Result.FParentId := FId;
  Result.FBranchPoint := Min(AMessageIndex, FMessages.Count - 1);
  Result.FSkills := Copy(FSkills);

  for i := 0 to Result.FBranchPoint do
    Result.FMessages.Add(FMessages[i].Clone);
end;

{ TSessionInfo }

function TSessionInfo.DisplayName: string;
var
  BranchMark: string;
begin
  BranchMark := '';
  if IsBranch then
    BranchMark := ' [B]';

  if Name <> '' then
    Result := Format('%s%s (%s)', [Name, BranchMark, FormatDateTime('mm-dd hh:nn', UpdatedAt)])
  else
    Result := Format('Session %s%s (%s)', [Copy(Id, 1, 8), BranchMark, FormatDateTime('mm-dd hh:nn', UpdatedAt)]);
end;

function TSessionInfo.IsBranch: Boolean;
begin
  Result := ParentId <> '';
end;

{ TSessionManager }

constructor TSessionManager.Create(ALogger: TLogger;
  const ASessionDir: string);
begin
  inherited Create;
  FLogger := ALogger;
  FAutoSave := True;
  FAutoSaveInterval := 300;
  FMaxSessions := 100;
  FCurrentSession := nil;
  FLock := TObject.Create;  // TMonitor is reentrant

  if ASessionDir <> '' then
    FSessionDir := ASessionDir
  else
    FSessionDir := IncludeTrailingPathDelimiter(
      GetEnvironmentVariable('APPDATA')) + 'PiMono\sessions';

  if not DirectoryExists(FSessionDir) then
    ForceDirectories(FSessionDir);

  // Auto-migrate legacy .json sessions to .jsonl
  MigrateLegacySessions;
end;

destructor TSessionManager.Destroy;
begin
  if (FAutoSave) and (FCurrentSession <> nil) then
  begin
    if FCurrentSession.FHeaderDirty then
      UpdateHeaderTimestamp(FCurrentSession);
    SaveCurrent;
  end;
  FreeAndNil(FCurrentSession);
  FreeAndNil(FLock);  // TMonitor cleanup
  inherited;
end;

function TSessionManager.GenerateId: string;
var
  GUID: TGUID;
begin
  CreateGUID(GUID);
  Result := Format('%.8x%.4x%.4x%.2x%.2x%.2x%.2x%.2x%.2x%.2x%.2x',
    [GUID.D1, GUID.D2, GUID.D3,
     GUID.D4[0], GUID.D4[1], GUID.D4[2], GUID.D4[3],
     GUID.D4[4], GUID.D4[5], GUID.D4[6], GUID.D4[7]]);
end;

function TSessionManager.GetSessionPath(const AId: string): string;
begin
  Result := IncludeTrailingPathDelimiter(FSessionDir) + AId + '.jsonl';
end;

function TSessionManager.GetLegacyPath(const AId: string): string;
begin
  Result := IncludeTrailingPathDelimiter(FSessionDir) + AId + '.json';
end;

procedure TSessionManager.MigrateLegacySession(const AJsonPath: string);
var
  Content: string;
  Json: TJSONObject;
  Session: TSession;
  Path: string;
begin
  try
    Content := TFile.ReadAllText(AJsonPath, TEncoding.UTF8);
    Json := TJSONObject.ParseJSONValue(Content) as TJSONObject;
    if Json = nil then
      Exit;
    try
      Session := TSession.FromJson(Json);
      Path := GetSessionPath(Session.Id);
      Session.FilePath := Path;
      // Write as JSONL (full write)
      Session.NeedFullWrite := True;
      SaveSession(Session);
      // Delete old .json file
      TFile.Delete(AJsonPath);
      Session.Free;
      if Assigned(FLogger) then
        FLogger.Info('Migrated session: ' + ExtractFileName(AJsonPath) + ' -> .jsonl');
    finally
      Json.Free;
    end;
  except
    on E: Exception do
      if Assigned(FLogger) then
        FLogger.LogException(E, 'Failed to migrate session: ' + AJsonPath);
  end;
end;

procedure TSessionManager.MigrateLegacySessions;
var
  Files: TArray<string>;
  i: Integer;
begin
  if not DirectoryExists(FSessionDir) then
    Exit;
  Files := TDirectory.GetFiles(FSessionDir, '*.json');
  for i := 0 to High(Files) do
    MigrateLegacySession(Files[i]);
end;

function TSessionManager.CreateSession(const AName: string): TSession;
begin
  TMonitor.Enter(FLock);
  try
    // Auto-save current session
    if FAutoSave and (FCurrentSession <> nil) then
    begin
      if FCurrentSession.FHeaderDirty then
        UpdateHeaderTimestamp(FCurrentSession);
      SaveCurrent;
    end;

    FreeAndNil(FCurrentSession);

    Result := TSession.Create(GenerateId);
    if AName <> '' then
      Result.FName := AName
    else
      Result.FName := 'Session ' + FormatDateTime('yyyy-mm-dd hh:nn', Now);

    Result.FFilePath := GetSessionPath(Result.Id);
    FCurrentSession := Result;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TSessionManager.LoadSession(const AId: string): TSession;
var
  OldSession: TSession;
begin
  TMonitor.Enter(FLock);
  try
    Result := DoLoadSessionById(AId);

    // Swap current session — set new session first, then save old one
    if Result <> nil then
    begin
      OldSession := FCurrentSession;
      FCurrentSession := Result;
      if FAutoSave and (OldSession <> nil) then
      begin
        // Flush pending header update before saving
        if OldSession.FHeaderDirty then
          UpdateHeaderTimestamp(OldSession);
        SaveSession(OldSession);
      end;
      OldSession.Free;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TSessionManager.LoadSessionById(const AId: string): TSession;
begin
  // Like LoadSession but does NOT modify FCurrentSession.
  // Caller owns the returned TSession lifetime.
  TMonitor.Enter(FLock);
  try
    Result := DoLoadSessionById(AId);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TSessionManager.DoLoadSessionById(const AId: string): TSession;
var
  Path: string;
  Lines: TArray<string>;
  i, MsgCount: Integer;
  Json: TJSONObject;
  Id, Name, ParentId, SystemPrompt: string;
  CreatedAt, UpdatedAt: TDateTime;
  BranchPoint: Integer;
  Skills: TArray<string>;
  Msg: TAgentMessage;
begin
  Result := nil;
  Path := GetSessionPath(AId);

  if not FileExists(Path) then
  begin
    // Try legacy .json path
    var LegacyPath := GetLegacyPath(AId);
    if FileExists(LegacyPath) then
    begin
      MigrateLegacySession(LegacyPath);
      Path := GetSessionPath(AId);
    end;

    if not FileExists(Path) then
    begin
      if Assigned(FLogger) then
        FLogger.Warn('Session file not found: ' + AId);
      Exit;
    end;
  end;

  try
    Lines := TFile.ReadAllLines(Path, TEncoding.UTF8);
    if Length(Lines) = 0 then
      Exit;

    // First line is the header
    Json := TJSONObject.ParseJSONValue(Lines[0]) as TJSONObject;
    if Json = nil then
      Exit;
    try
      if not TSession.HeaderFromJson(Json, Id, Name, ParentId,
        CreatedAt, UpdatedAt, SystemPrompt, BranchPoint, Skills) then
        Exit;
    finally
      Json.Free;
    end;

    Result := TSession.Create(Id);
    Result.FName := Name;
    Result.FCreatedAt := CreatedAt;
    Result.FUpdatedAt := UpdatedAt;
    Result.FSystemPrompt := SystemPrompt;
    Result.FParentId := ParentId;
    Result.FBranchPoint := BranchPoint;
    Result.FSkills := Skills;
    Result.FFilePath := Path;

    // Remaining lines are messages
    MsgCount := 0;
    for i := 1 to High(Lines) do
    begin
      if Lines[i].Trim = '' then
        Continue;
      Json := TJSONObject.ParseJSONValue(Lines[i]) as TJSONObject;
      if Json = nil then
        Continue;
      try
        // Skip non-message lines (e.g., header duplicates)
        if JsonGetStr(Json, 'type', '') = 'header' then
          Continue;
        Msg := TAgentMessage.FromJson(Json);
        if Msg <> nil then
        begin
          Result.FMessages.Add(Msg);
          Inc(MsgCount);
        end;
      finally
        Json.Free;
      end;
    end;

    Result.FSavedCount := MsgCount;
  except
    on E: Exception do
    begin
      if Assigned(FLogger) then
        FLogger.LogException(E, 'Failed to load session');
      FreeAndNil(Result);
    end;
  end;
end;

procedure TSessionManager.DeleteSession(const AId: string);
var
  Path: string;
begin
  TMonitor.Enter(FLock);
  try
    Path := GetSessionPath(AId);
    if FileExists(Path) then
    begin
      TFile.Delete(Path);
      if Assigned(FLogger) then
        FLogger.Info('Session deleted: ' + AId);
    end;

    if (FCurrentSession <> nil) and (FCurrentSession.Id = AId) then
      FreeAndNil(FCurrentSession);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TSessionManager.SaveSession(ASession: TSession);
var
  Dir: string;
  Writer: TStreamWriter;
  Json: TJSONObject;
  i: Integer;
begin
  if ASession = nil then
    Exit;

  TMonitor.Enter(FLock);
  try
  ASession.FFilePath := GetSessionPath(ASession.Id);
  ASession.FUpdatedAt := Now;

  Dir := ExtractFileDir(ASession.FilePath);
  if not DirectoryExists(Dir) then
    ForceDirectories(Dir);

  if ASession.NeedFullWrite or (ASession.SavedCount = 0) or
     (ASession.SavedCount > ASession.Messages.Count) then
  begin
    // Full write: header + all messages
    Writer := TStreamWriter.Create(ASession.FilePath, False, TEncoding.UTF8);
    try
      // Header line
      Json := ASession.HeaderToJson;
      try
        Writer.WriteLine(Json.ToJSON);
      finally
        Json.Free;
      end;

      // Message lines
      for i := 0 to ASession.Messages.Count - 1 do
      begin
        Json := ASession.Messages[i].ToJson;
        try
          Writer.WriteLine(Json.ToJSON);
        finally
          Json.Free;
        end;
      end;
    finally
      Writer.Free;
    end;

    ASession.SavedCount := ASession.Messages.Count;
    ASession.NeedFullWrite := False;
    ASession.FHeaderDirty := False;
  end
  else
  begin
    // Append-only: write only new messages since last save
    Writer := TStreamWriter.Create(ASession.FilePath, True, TEncoding.UTF8);
    try
      // Update header's updatedAt by rewriting the first line
      // For append-only, we also update the header separately
      for i := ASession.SavedCount to ASession.Messages.Count - 1 do
      begin
        Json := ASession.Messages[i].ToJson;
        try
          Writer.WriteLine(Json.ToJSON);
        finally
          Json.Free;
        end;
      end;
    finally
      Writer.Free;
    end;

    ASession.SavedCount := ASession.Messages.Count;

    // Mark header as needing update (deferred — updated on next full write or session switch)
    ASession.FHeaderDirty := True;
  end;

  if Assigned(FLogger) then
    FLogger.Debug('Session saved: ' + ASession.Id);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TSessionManager.UpdateHeaderTimestamp(ASession: TSession);
var
  Reader: TStreamReader;
  Writer: TStreamWriter;
  TmpPath: string;
  FirstLine, Line: string;
  Json: TJSONObject;
begin
  // Efficiently update only the header line without loading entire file into memory.
  // Uses a temp-file-then-rename approach to avoid data loss on failure.
  if not FileExists(ASession.FilePath) then
    Exit;

  try
    // Read only the first line
    Reader := TStreamReader.Create(ASession.FilePath, TEncoding.UTF8);
    try
      FirstLine := Reader.ReadLine;
    finally
      Reader.Free;
    end;
    if FirstLine = '' then
      Exit;

    // Update header fields
    Json := TJSONObject.ParseJSONValue(FirstLine) as TJSONObject;
    if Json = nil then
      Exit;
    try
      Json.RemovePair('updatedAt');
      Json.AddPair('updatedAt', TJSONNumber.Create(DateTimeToUnix(ASession.UpdatedAt, False)));
      Json.RemovePair('messageCount');
      Json.AddPair('messageCount', TJSONNumber.Create(ASession.Messages.Count));
      FirstLine := Json.ToJSON;
    finally
      Json.Free;
    end;

    // Write updated header + copy remaining lines via temp file
    TmpPath := ASession.FilePath + '.tmp';
    Reader := TStreamReader.Create(ASession.FilePath, TEncoding.UTF8);
    Writer := TStreamWriter.Create(TmpPath, False, TEncoding.UTF8);
    try
      // Skip old header line
      Reader.ReadLine;
      // Write new header
      Writer.WriteLine(FirstLine);
      // Copy remaining lines
      while not Reader.EndOfStream do
      begin
        Line := Reader.ReadLine;
        Writer.WriteLine(Line);
      end;
    finally
      Writer.Free;
      Reader.Free;
    end;

    // Replace original with temp file
    TFile.Delete(ASession.FilePath);
    TFile.Move(TmpPath, ASession.FilePath);
  except
    on E: Exception do
    begin
      // Clean up temp file on failure
      if FileExists(ASession.FilePath + '.tmp') then
        TFile.Delete(ASession.FilePath + '.tmp');
      if Assigned(FLogger) then
        FLogger.LogException(E, 'Failed to update session header');
    end;
  end;
end;

function TSessionManager.ListSessions: TArray<TSessionInfo>;
var
  Files: TArray<string>;
  i: Integer;
  Json: TJSONObject;
  Reader: TStreamReader;
  FirstLine: string;
  Id, Name, ParentId, SystemPrompt: string;
  CreatedAt, UpdatedAt: TDateTime;
  BranchPoint: Integer;
  Skills: TArray<string>;
begin
  Result := nil;
  if not DirectoryExists(FSessionDir) then
    Exit;

  // Read .jsonl files
  Files := TDirectory.GetFiles(FSessionDir, '*.jsonl');
  SetLength(Result, Length(Files));

  var Count := 0;
  for i := 0 to High(Files) do
  begin
    try
      // Only read the first line (header) — avoid loading entire file
      Reader := TStreamReader.Create(Files[i], TEncoding.UTF8);
      try
        FirstLine := Reader.ReadLine;
      finally
        Reader.Free;
      end;
      if FirstLine = '' then
        Continue;

      Json := TJSONObject.ParseJSONValue(FirstLine) as TJSONObject;
      if Json = nil then
        Continue;
      try
        if not TSession.HeaderFromJson(Json, Id, Name, ParentId,
          CreatedAt, UpdatedAt, SystemPrompt, BranchPoint, Skills) then
          Continue;

        Result[Count].Id := Id;
        Result[Count].Name := Name;
        Result[Count].CreatedAt := CreatedAt;
        Result[Count].UpdatedAt := UpdatedAt;
        Result[Count].MessageCount := JsonGetInt(Json, 'messageCount', 0);
        Result[Count].ParentId := ParentId;
        Result[Count].BranchPoint := BranchPoint;
        Inc(Count);
      finally
        Json.Free;
      end;
    except
      // Skip invalid session files
    end;
  end;

  SetLength(Result, Count);

  // Sort by updatedAt descending (most recent first)
  TArray.Sort<TSessionInfo>(Result,
    TComparer<TSessionInfo>.Construct(
      function(const A, B: TSessionInfo): Integer
      begin
        if A.UpdatedAt > B.UpdatedAt then
          Result := -1
        else if A.UpdatedAt < B.UpdatedAt then
          Result := 1
        else
          Result := 0;
      end));
end;

function TSessionManager.RenameSession(const AId, ANewName: string): Boolean;
var
  Session: TSession;
begin
  Result := False;
  // Use LoadSessionById to avoid changing FCurrentSession as a side effect
  Session := LoadSessionById(AId);
  if Session = nil then
    Exit;
  Session.Name := ANewName;
  Session.NeedFullWrite := True;  // Force full rewrite for name change
  SaveSession(Session);
  Session.Free;
  Result := True;
end;

function TSessionManager.SessionExists(const AId: string): Boolean;
begin
  Result := FileExists(GetSessionPath(AId)) or FileExists(GetLegacyPath(AId));
end;

procedure TSessionManager.SetCurrentSession(ASession: TSession);
begin
  TMonitor.Enter(FLock);
  try
    if FAutoSave and (FCurrentSession <> nil) then
    begin
      if FCurrentSession.FHeaderDirty then
        UpdateHeaderTimestamp(FCurrentSession);
      SaveCurrent;
    end;
    FCurrentSession := ASession;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TSessionManager.GetCurrentSession: TSession;
begin
  Result := FCurrentSession;
end;

procedure TSessionManager.SaveCurrent;
begin
  if FCurrentSession <> nil then
    SaveSession(FCurrentSession);
end;

end.
