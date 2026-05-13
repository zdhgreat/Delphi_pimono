unit Core.UndoLog;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections,
  System.SyncObjs, System.IOUtils, System.DateUtils;

type
  TUndoEntry = record
    Id: Integer;
    Timestamp: TDateTime;
    FilePath: string;
    Operation: string;  // 'write' or 'edit'
    OldContent: string;
    ToolCallId: string;
  end;

  TUndoLog = class
  private
    FEntries: TList<TUndoEntry>;
    FFilePath: string;
    FMaxEntries: Integer;
    FNextId: Integer;
    FLock: TCriticalSection;
    procedure EnsureDir;
    procedure LoadFromFile;
    procedure SaveToFile;
    procedure AppendEntry(const AEntry: TUndoEntry);
    procedure TrimToMax;
  public
    constructor Create(const ADirectory: string; AMaxEntries: Integer = 100);
    destructor Destroy; override;
    function RecordOperation(const AFilePath, AOperation, AOldContent,
      AToolCallId: string): Integer;
    function UndoLast: Boolean;
    function GetLastEntry: TUndoEntry;
    function GetEntryCount: Integer;
    procedure Clear;
    property FilePath: string read FFilePath;
  end;

implementation

{ TUndoLog }

constructor TUndoLog.Create(const ADirectory: string; AMaxEntries: Integer);
begin
  inherited Create;
  FEntries := TList<TUndoEntry>.Create;
  FLock := TCriticalSection.Create;
  FMaxEntries := AMaxEntries;
  FNextId := 1;
  FFilePath := TPath.Combine(ADirectory, 'undo_log.jsonl');
  EnsureDir;
  LoadFromFile;
end;

destructor TUndoLog.Destroy;
begin
  FLock.Free;
  FEntries.Free;
  inherited;
end;

procedure TUndoLog.EnsureDir;
var
  Dir: string;
begin
  Dir := ExtractFilePath(FFilePath);
  if (Dir <> '') and not TDirectory.Exists(Dir) then
    TDirectory.CreateDirectory(Dir);
end;

procedure TUndoLog.LoadFromFile;
var
  Lines: TArray<string>;
  i: Integer;
  Entry: TUndoEntry;
begin
  if not TFile.Exists(FFilePath) then Exit;

  FLock.Enter;
  try
    try
      Lines := TFile.ReadAllLines(FFilePath, TEncoding.UTF8);
      for i := 0 to High(Lines) do
      begin
        if Trim(Lines[i]) = '' then Continue;
        try
          var Json := TJSONObject.ParseJSONValue(Lines[i]) as TJSONObject;
          if Json = nil then Continue;
          try
            Entry := Default(TUndoEntry);
            Entry.Id := Json.GetValue<Integer>('id');
            Entry.Timestamp := Iso8601ToDate(Json.GetValue<string>('ts'), False);
            Entry.FilePath := Json.GetValue<string>('path');
            Entry.Operation := Json.GetValue<string>('op');
            Entry.OldContent := Json.GetValue<string>('old', '');
            Entry.ToolCallId := Json.GetValue<string>('tcid', '');
            FEntries.Add(Entry);
            if Entry.Id >= FNextId then
              FNextId := Entry.Id + 1;
          finally
            Json.Free;
          end;
        except
          // Skip malformed lines
        end;
      end;
    except
      // File read error - start fresh
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TUndoLog.SaveToFile;
var
  SB: TStringBuilder;
  Entry: TUndoEntry;
begin
  SB := TStringBuilder.Create;
  try
    for var i := 0 to FEntries.Count - 1 do
    begin
      Entry := FEntries[i];
      var Json := TJSONObject.Create;
      try
        Json.AddPair('id', TJSONNumber.Create(Entry.Id));
        Json.AddPair('ts', DateToISO8601(Entry.Timestamp, False));
        Json.AddPair('path', Entry.FilePath);
        Json.AddPair('op', Entry.Operation);
        Json.AddPair('old', Entry.OldContent);
        Json.AddPair('tcid', Entry.ToolCallId);
        SB.AppendLine(Json.ToJSON);
      finally
        Json.Free;
      end;
    end;
    try
      TFile.WriteAllText(FFilePath, SB.ToString, TEncoding.UTF8);
    except
      on E: Exception do
        ;  // Log not available here — silently continue (undo log is best-effort)
    end;
  finally
    SB.Free;
  end;
end;

procedure TUndoLog.AppendEntry(const AEntry: TUndoEntry);
var
  Json: TJSONObject;
  Line: string;
begin
  Json := TJSONObject.Create;
  try
    Json.AddPair('id', TJSONNumber.Create(AEntry.Id));
    Json.AddPair('ts', DateToISO8601(AEntry.Timestamp, False));
    Json.AddPair('path', AEntry.FilePath);
    Json.AddPair('op', AEntry.Operation);
    Json.AddPair('old', AEntry.OldContent);
    Json.AddPair('tcid', AEntry.ToolCallId);
    Line := Json.ToJSON;
  finally
    Json.Free;
  end;
  try
    TFile.AppendAllText(FFilePath, Line + #10, TEncoding.UTF8);
  except
    on E: Exception do
      ;  // Append is best-effort — entry is still in memory
  end;
end;

procedure TUndoLog.TrimToMax;
begin
  while FEntries.Count > FMaxEntries do
    FEntries.Delete(0);
end;

function TUndoLog.RecordOperation(const AFilePath, AOperation, AOldContent,
  AToolCallId: string): Integer;
var
  Entry: TUndoEntry;
begin
  FLock.Enter;
  try
    Entry := Default(TUndoEntry);
    Entry.Id := FNextId;
    Inc(FNextId);
    Entry.Timestamp := Now;
    Entry.FilePath := AFilePath;
    Entry.Operation := AOperation;
    Entry.OldContent := AOldContent;
    Entry.ToolCallId := AToolCallId;
    FEntries.Add(Entry);
    var CountBefore := FEntries.Count - 1;
    TrimToMax;
    if FEntries.Count <= CountBefore then
      // Entries were trimmed - need full rewrite
      SaveToFile
    else
      AppendEntry(Entry);
    Result := Entry.Id;
  finally
    FLock.Leave;
  end;
end;

function TUndoLog.UndoLast: Boolean;
var
  Entry: TUndoEntry;
  Dir: string;
begin
  FLock.Enter;
  try
    if FEntries.Count = 0 then Exit(False);

    Entry := FEntries.Last;

    // Restore old content
    try
      if Entry.Operation = 'create' then
      begin
        // File was created new - delete it
        if TFile.Exists(Entry.FilePath) then
          TFile.Delete(Entry.FilePath);
      end
      else
      begin
        // Restore original content (even if empty)
        Dir := ExtractFilePath(Entry.FilePath);
        if (Dir <> '') and not TDirectory.Exists(Dir) then
          TDirectory.CreateDirectory(Dir);
        TFile.WriteAllText(Entry.FilePath, Entry.OldContent, TEncoding.UTF8);
      end;

      // Remove the entry
      FEntries.Delete(FEntries.Count - 1);
      SaveToFile;
      Result := True;
    except
      Result := False;
    end;
  finally
    FLock.Leave;
  end;
end;

function TUndoLog.GetLastEntry: TUndoEntry;
begin
  FLock.Enter;
  try
    if FEntries.Count = 0 then
      Result := Default(TUndoEntry)
    else
      Result := FEntries.Last;
  finally
    FLock.Leave;
  end;
end;

function TUndoLog.GetEntryCount: Integer;
begin
  FLock.Enter;
  try
    Result := FEntries.Count;
  finally
    FLock.Leave;
  end;
end;

procedure TUndoLog.Clear;
begin
  FLock.Enter;
  try
    FEntries.Clear;
    SaveToFile;
  finally
    FLock.Leave;
  end;
end;

end.
