unit TestUndoLog;

interface

uses
  System.SysUtils, System.IOUtils,
  Core.UndoLog, Winapi.Windows;

procedure RegisterUndoLogTests;

implementation

uses
  PiMonoTestFramework;

type
  TTestUndoLog = class
  private
    FTestDir: string;
    FUndoLog: TUndoLog;
  public
    procedure Setup;
    procedure TearDown;

    procedure Test_RecordWrite;
    procedure Test_RecordEdit;
    procedure Test_RecordCreate;
    procedure Test_UndoWrite_RestoresContent;
    procedure Test_UndoEdit_RestoresContent;
    procedure Test_UndoCreate_DeletesFile;
    procedure Test_UndoLast_Empty_ReturnsFalse;
    procedure Test_MultipleUndos_LIFO;
    procedure Test_MaxEntries_FIFO;
    procedure Test_GetEntryCount;
    procedure Test_GetLastEntry;
    procedure Test_Clear;
    procedure Test_Persistence_AcrossInstances;
    procedure Test_CorruptedJsonl_SkipBadLines;
    procedure Test_UndoRestoresDeletedDirectory;
  end;

{ TTestUndoLog }

procedure TTestUndoLog.Setup;
begin
  FTestDir := TPath.Combine(TPath.GetTempPath, 'PiMonoUndo_' + FormatDateTime('yyyymmddhhnnsszzz', Now) + '_' + IntToStr(GetTickCount));
  TDirectory.CreateDirectory(FTestDir);
  FUndoLog := TUndoLog.Create(FTestDir, 5); // Small max for testing FIFO
end;

procedure TTestUndoLog.TearDown;
begin
  FUndoLog.Free;
  try
    if TDirectory.Exists(FTestDir) then
      TDirectory.Delete(FTestDir, True);
  except
  end;
end;

procedure TTestUndoLog.Test_RecordWrite;
var
  Id: Integer;
begin
  Id := FUndoLog.RecordOperation('C:\test.txt', 'write', 'old content', 'tc1');
  Assert(Id > 0, 'Id should be positive');
  Assert(FUndoLog.GetEntryCount = 1, 'Entry count should be 1');
end;

procedure TTestUndoLog.Test_RecordEdit;
var
  Entry: TUndoEntry;
begin
  FUndoLog.RecordOperation('C:\test.txt', 'edit', 'old text', 'tc2');
  Assert(FUndoLog.GetEntryCount = 1, 'Entry count should be 1');

  Entry := FUndoLog.GetLastEntry;
  Assert(Entry.Operation = 'edit', 'Operation should be edit');
  Assert(Entry.OldContent = 'old text', 'OldContent should match');
end;

procedure TTestUndoLog.Test_RecordCreate;
var
  Entry: TUndoEntry;
begin
  FUndoLog.RecordOperation('C:\newfile.txt', 'create', '', 'tc3');
  Assert(FUndoLog.GetEntryCount = 1, 'Entry count should be 1');

  Entry := FUndoLog.GetLastEntry;
  Assert(Entry.Operation = 'create', 'Operation should be create');
end;

procedure TTestUndoLog.Test_UndoWrite_RestoresContent;
var
  FilePath: string;
begin
  FilePath := TPath.Combine(FTestDir, 'write_test.txt');

  // Create file with original content
  TFile.WriteAllText(FilePath, 'original');

  // Record a write operation with the old content
  FUndoLog.RecordOperation(FilePath, 'write', 'original', 'tc1');

  // Overwrite the file
  TFile.WriteAllText(FilePath, 'new content');
  Assert(TFile.ReadAllText(FilePath) = 'new content', 'File should have new content');

  // Undo should restore original
  Assert(FUndoLog.UndoLast, 'UndoLast should return True');
  Assert(TFile.ReadAllText(FilePath) = 'original', 'File should be restored to original');
  Assert(FUndoLog.GetEntryCount = 0, 'Entry count should be 0 after undo');
end;

procedure TTestUndoLog.Test_UndoEdit_RestoresContent;
var
  FilePath: string;
begin
  FilePath := TPath.Combine(FTestDir, 'edit_test.txt');

  // Create file with original content
  TFile.WriteAllText(FilePath, 'original text');

  // Record an edit operation
  FUndoLog.RecordOperation(FilePath, 'edit', 'original text', 'tc1');

  // Modify the file
  TFile.WriteAllText(FilePath, 'modified text');

  // Undo should restore original
  Assert(FUndoLog.UndoLast, 'UndoLast should return True');
  Assert(TFile.ReadAllText(FilePath) = 'original text', 'File should be restored to original text');
end;

procedure TTestUndoLog.Test_UndoCreate_DeletesFile;
var
  FilePath: string;
begin
  FilePath := TPath.Combine(FTestDir, 'new_file.txt');

  // Create a new file
  TFile.WriteAllText(FilePath, 'new content');

  // Record a create operation
  FUndoLog.RecordOperation(FilePath, 'create', '', 'tc1');

  Assert(TFile.Exists(FilePath), 'File should exist before undo');

  // Undo should delete the file
  Assert(FUndoLog.UndoLast, 'UndoLast should return True');
  Assert(not TFile.Exists(FilePath), 'File should be deleted after undo create');
end;

procedure TTestUndoLog.Test_UndoLast_Empty_ReturnsFalse;
begin
  Assert(not FUndoLog.UndoLast, 'Should return False when no entries');
end;

procedure TTestUndoLog.Test_MultipleUndos_LIFO;
var
  FilePath1, FilePath2: string;
begin
  FilePath1 := TPath.Combine(FTestDir, 'file1.txt');
  FilePath2 := TPath.Combine(FTestDir, 'file2.txt');

  TFile.WriteAllText(FilePath1, 'v1');
  TFile.WriteAllText(FilePath2, 'v2');

  FUndoLog.RecordOperation(FilePath1, 'write', 'v1', 'tc1');
  TFile.WriteAllText(FilePath1, 'v1-modified');

  FUndoLog.RecordOperation(FilePath2, 'write', 'v2', 'tc2');
  TFile.WriteAllText(FilePath2, 'v2-modified');

  Assert(FUndoLog.GetEntryCount = 2, 'Entry count should be 2');

  // Undo file2 first (LIFO)
  Assert(FUndoLog.UndoLast, 'UndoLast should return True');
  Assert(TFile.ReadAllText(FilePath2) = 'v2', 'File2 should be restored to v2');

  // Undo file1
  Assert(FUndoLog.UndoLast, 'UndoLast should return True');
  Assert(TFile.ReadAllText(FilePath1) = 'v1', 'File1 should be restored to v1');

  Assert(FUndoLog.GetEntryCount = 0, 'Entry count should be 0 after all undos');
end;

procedure TTestUndoLog.Test_MaxEntries_FIFO;
var
  i: Integer;
  Entry: TUndoEntry;
begin
  // MaxEntries is 5 (set in Setup)
  for i := 1 to 8 do
    FUndoLog.RecordOperation('C:\file' + IntToStr(i) + '.txt', 'write', 'old' + IntToStr(i), 'tc');

  // Should have trimmed to 5
  Assert(FUndoLog.GetEntryCount = 5, 'Should be trimmed to max entries');

  // Last entry should be file8
  Entry := FUndoLog.GetLastEntry;
  Assert(Entry.FilePath = 'C:\file8.txt', 'Last entry should be file8');
end;

procedure TTestUndoLog.Test_GetEntryCount;
begin
  Assert(FUndoLog.GetEntryCount = 0, 'Should start at 0');
  FUndoLog.RecordOperation('a.txt', 'write', 'old', 'tc');
  Assert(FUndoLog.GetEntryCount = 1, 'Should be 1 after one record');
  FUndoLog.RecordOperation('b.txt', 'write', 'old', 'tc');
  Assert(FUndoLog.GetEntryCount = 2, 'Should be 2 after two records');
end;

procedure TTestUndoLog.Test_GetLastEntry;
var
  Entry: TUndoEntry;
begin
  FUndoLog.RecordOperation('first.txt', 'write', 'old1', 'tc1');
  FUndoLog.RecordOperation('second.txt', 'edit', 'old2', 'tc2');

  Entry := FUndoLog.GetLastEntry;
  Assert(Entry.FilePath = 'second.txt', 'FilePath should be second.txt');
  Assert(Entry.Operation = 'edit', 'Operation should be edit');
  Assert(Entry.ToolCallId = 'tc2', 'ToolCallId should be tc2');
end;

procedure TTestUndoLog.Test_Clear;
begin
  FUndoLog.RecordOperation('a.txt', 'write', 'old', 'tc');
  FUndoLog.RecordOperation('b.txt', 'write', 'old', 'tc');
  FUndoLog.Clear;
  Assert(FUndoLog.GetEntryCount = 0, 'Entry count should be 0 after clear');
end;

procedure TTestUndoLog.Test_Persistence_AcrossInstances;
var
  Log2: TUndoLog;
  Entry: TUndoEntry;
begin
  FUndoLog.RecordOperation('persist.txt', 'write', 'persisted_content', 'tc1');
  FUndoLog.Free;

  // Create new instance pointing to same directory
  Log2 := TUndoLog.Create(FTestDir, 100);
  try
    Assert(Log2.GetEntryCount = 1, 'Should load 1 entry from file');
    Entry := Log2.GetLastEntry;
    Assert(Entry.FilePath = 'persist.txt', 'FilePath should be persist.txt');
    Assert(Entry.OldContent = 'persisted_content', 'OldContent should match');
  finally
    FUndoLog := nil; // Prevent double-free in TearDown
    Log2.Free;
  end;
end;

procedure TTestUndoLog.Test_CorruptedJsonl_SkipBadLines;
var
  LogPath: string;
  Log2: TUndoLog;
begin
  // Write a corrupted JSONL file
  LogPath := TPath.Combine(FTestDir, 'undo_log.jsonl');
  FUndoLog.Free;
  TFile.WriteAllText(LogPath,
    '{"id":1,"ts":"2026-01-01T00:00:00.000Z","path":"ok.txt","op":"write","old":"ok","tcid":"tc1"}' + #10 +
    'CORRUPTED LINE' + #10 +
    '{"id":2,"ts":"2026-01-01T00:00:00.000Z","path":"ok2.txt","op":"edit","old":"ok2","tcid":"tc2"}' + #10,
    TEncoding.UTF8);

  Log2 := TUndoLog.Create(FTestDir, 100);
  try
    Assert(Log2.GetEntryCount = 2, 'Should skip corrupted line and load 2 entries');
  finally
    FUndoLog := nil;
    Log2.Free;
  end;
end;

procedure TTestUndoLog.Test_UndoRestoresDeletedDirectory;
var
  SubDir, FilePath: string;
begin
  SubDir := TPath.Combine(FTestDir, 'subdir');
  TDirectory.CreateDirectory(SubDir);
  FilePath := TPath.Combine(SubDir, 'file.txt');
  TFile.WriteAllText(FilePath, 'content');

  FUndoLog.RecordOperation(FilePath, 'write', 'content', 'tc1');
  TFile.Delete(FilePath);
  TDirectory.Delete(SubDir);

  // Undo should recreate directory and file
  Assert(FUndoLog.UndoLast, 'UndoLast should return True');
  Assert(TFile.Exists(FilePath), 'File should exist after undo');
  Assert(TFile.ReadAllText(FilePath) = 'content', 'File content should be restored');
end;

{ Registration }

procedure RegisterUndoLogTests;
var
  T: TTestUndoLog;
begin
  T := TTestUndoLog.Create;
  try
    GRunner.RunTest('UndoLog.RecordWrite', T.Test_RecordWrite, T.Setup, T.TearDown);
    GRunner.RunTest('UndoLog.RecordEdit', T.Test_RecordEdit, T.Setup, T.TearDown);
    GRunner.RunTest('UndoLog.RecordCreate', T.Test_RecordCreate, T.Setup, T.TearDown);
    GRunner.RunTest('UndoLog.UndoWrite_RestoresContent', T.Test_UndoWrite_RestoresContent, T.Setup, T.TearDown);
    GRunner.RunTest('UndoLog.UndoEdit_RestoresContent', T.Test_UndoEdit_RestoresContent, T.Setup, T.TearDown);
    GRunner.RunTest('UndoLog.UndoCreate_DeletesFile', T.Test_UndoCreate_DeletesFile, T.Setup, T.TearDown);
    GRunner.RunTest('UndoLog.UndoLast_Empty_ReturnsFalse', T.Test_UndoLast_Empty_ReturnsFalse, T.Setup, T.TearDown);
    GRunner.RunTest('UndoLog.MultipleUndos_LIFO', T.Test_MultipleUndos_LIFO, T.Setup, T.TearDown);
    GRunner.RunTest('UndoLog.MaxEntries_FIFO', T.Test_MaxEntries_FIFO, T.Setup, T.TearDown);
    GRunner.RunTest('UndoLog.GetEntryCount', T.Test_GetEntryCount, T.Setup, T.TearDown);
    GRunner.RunTest('UndoLog.GetLastEntry', T.Test_GetLastEntry, T.Setup, T.TearDown);
    GRunner.RunTest('UndoLog.Clear', T.Test_Clear, T.Setup, T.TearDown);
    GRunner.RunTest('UndoLog.Persistence_AcrossInstances', T.Test_Persistence_AcrossInstances, T.Setup, T.TearDown);
    GRunner.RunTest('UndoLog.CorruptedJsonl_SkipBadLines', T.Test_CorruptedJsonl_SkipBadLines, T.Setup, T.TearDown);
    GRunner.RunTest('UndoLog.UndoRestoresDeletedDirectory', T.Test_UndoRestoresDeletedDirectory, T.Setup, T.TearDown);
  finally
    T.Free;
  end;
end;

end.
