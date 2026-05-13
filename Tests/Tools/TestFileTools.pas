unit TestFileTools;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.IOUtils, Winapi.Windows,
  Tools.ITool, Tools.FileTools, Core.AgentState, Core.Messages, Core.UndoLog,
  PiMonoTestFramework;

type
  TTestReadFileTool = class
  private
    FWorkDir: string;
  public
    procedure Setup;
    procedure TearDown;
    procedure ReadNormalFile;
    procedure ReadEmptyFile;
    procedure ReadNonExistent;
    procedure ReadWithOffset;
    procedure ReadWithLimit;
    procedure ReadUnicodeContent;
    procedure ReadOutsideWorkDir;
    procedure ReadTruncation2000Lines;
  end;

  TTestWriteFileTool = class
  private
    FWorkDir: string;
    FUndoLog: TUndoLog;
  public
    procedure Setup;
    procedure TearDown;
    procedure WriteNewFile;
    procedure OverwriteExisting;
    procedure CreateParentDirectories;
    procedure WriteEmptyContent;
    procedure WriteOutsideWorkDir;
    procedure UndoLogRecorded;
    procedure WriteWithExistingUndoLog;
  end;

  TTestEditFileTool = class
  private
    FWorkDir: string;
    FUndoLog: TUndoLog;
  public
    procedure Setup;
    procedure TearDown;
    procedure ExactMatch;
    procedure OldTextNotFound;
    procedure OldTextMultipleMatches;
    procedure EmptyOldText;
    procedure FuzzyMatch_WhitespaceDiff;
    procedure EditNonExistentFile;
    procedure EditOutsideWorkDir;
    procedure UndoLogRecorded;
    procedure UnicodeContent;
    procedure LargeReplacement;
  end;

procedure RegisterFileToolsTests;

implementation

{ === TTestReadFileTool === }

procedure TTestReadFileTool.Setup;
begin
  FWorkDir := TPath.Combine(TPath.GetTempPath, 'PiMonoRead_' + FormatDateTime('yyyymmddhhnnsszzz', Now) + '_' + IntToStr(GetTickCount));
  TDirectory.CreateDirectory(FWorkDir);
end;

procedure TTestReadFileTool.TearDown;
begin
  try
    if TDirectory.Exists(FWorkDir) then
      TDirectory.Delete(FWorkDir, True);
  except
  end;
end;

procedure TTestReadFileTool.ReadNormalFile;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
begin
  TFile.WriteAllText(TPath.Combine(FWorkDir, 'test.txt'), 'Hello World');

  Tool := CreateReadTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'test.txt');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'ReadNormalFile should succeed');
      Assert(R.Content.Count > 0, 'Should have content');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestReadFileTool.ReadEmptyFile;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
begin
  TFile.WriteAllText(TPath.Combine(FWorkDir, 'empty.txt'), '');

  Tool := CreateReadTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'empty.txt');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'ReadEmptyFile should succeed');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestReadFileTool.ReadNonExistent;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
begin
  Tool := CreateReadTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'missing.txt');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(R.IsError, 'ReadNonExistent should fail');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestReadFileTool.ReadWithOffset;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
  Lines: TArray<string>;
  i: Integer;
begin
  SetLength(Lines, 10);
  for i := 0 to 9 do
    Lines[i] := 'Line ' + IntToStr(i + 1);
  TFile.WriteAllLines(TPath.Combine(FWorkDir, 'lines.txt'), Lines);

  Tool := CreateReadTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'lines.txt');
    Params.AddPair('offset', TJSONNumber.Create(5));
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'ReadWithOffset should succeed');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestReadFileTool.ReadWithLimit;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
  Lines: TArray<string>;
  i: Integer;
begin
  SetLength(Lines, 20);
  for i := 0 to 19 do
    Lines[i] := 'Line ' + IntToStr(i + 1);
  TFile.WriteAllLines(TPath.Combine(FWorkDir, 'long.txt'), Lines);

  Tool := CreateReadTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'long.txt');
    Params.AddPair('limit', TJSONNumber.Create(5));
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'ReadWithLimit should succeed');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestReadFileTool.ReadUnicodeContent;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
begin
  TFile.WriteAllText(TPath.Combine(FWorkDir, 'unicode.txt'),
    'Hello '#20320#22909' '#1055#1088#1080#1074#1077#1090' '#12371#12435#12395#12385#12399,
    TEncoding.UTF8);

  Tool := CreateReadTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'unicode.txt');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'ReadUnicodeContent should succeed');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestReadFileTool.ReadOutsideWorkDir;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
begin
  Tool := CreateReadTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'C:\Windows\win.ini');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(R.IsError, 'Should not read outside work dir');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestReadFileTool.ReadTruncation2000Lines;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
  Lines: TArray<string>;
  i: Integer;
begin
  SetLength(Lines, 3000);
  for i := 0 to 2999 do
    Lines[i] := 'Line ' + IntToStr(i + 1);
  TFile.WriteAllLines(TPath.Combine(FWorkDir, 'huge.txt'), Lines);

  Tool := CreateReadTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'huge.txt');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'ReadTruncation2000Lines should succeed');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

{ === TTestWriteFileTool === }

procedure TTestWriteFileTool.Setup;
begin
  FWorkDir := TPath.Combine(TPath.GetTempPath, 'PiMonoWrite_' + FormatDateTime('yyyymmddhhnnsszzz', Now) + '_' + IntToStr(GetTickCount));
  TDirectory.CreateDirectory(FWorkDir);
  FUndoLog := TUndoLog.Create(FWorkDir);
end;

procedure TTestWriteFileTool.TearDown;
begin
  FUndoLog.Free;
  try
    if TDirectory.Exists(FWorkDir) then
      TDirectory.Delete(FWorkDir, True);
  except
  end;
end;

procedure TTestWriteFileTool.WriteNewFile;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
begin
  Tool := CreateWriteTool(FWorkDir);
  (Tool as TBaseTool).UndoLog := FUndoLog;
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'new.txt');
    Params.AddPair('content', 'New file content');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'WriteNewFile should succeed');
      Assert(TFile.Exists(TPath.Combine(FWorkDir, 'new.txt')), 'File should exist');
      Assert('New file content' = TFile.ReadAllText(TPath.Combine(FWorkDir, 'new.txt')),
        'Content should match');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestWriteFileTool.OverwriteExisting;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
  FilePath: string;
begin
  FilePath := TPath.Combine(FWorkDir, 'existing.txt');
  TFile.WriteAllText(FilePath, 'Old content');

  Tool := CreateWriteTool(FWorkDir);
  (Tool as TBaseTool).UndoLog := FUndoLog;
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'existing.txt');
    Params.AddPair('content', 'New content');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'OverwriteExisting should succeed');
      Assert('New content' = TFile.ReadAllText(FilePath), 'Content should be overwritten');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestWriteFileTool.CreateParentDirectories;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
begin
  Tool := CreateWriteTool(FWorkDir);
  (Tool as TBaseTool).UndoLog := FUndoLog;
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'a\b\c\deep.txt');
    Params.AddPair('content', 'Deep file');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'CreateParentDirectories should succeed');
      Assert(TFile.Exists(TPath.Combine(FWorkDir, 'a\b\c\deep.txt')),
        'Deep file should exist');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestWriteFileTool.WriteEmptyContent;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
  FilePath: string;
begin
  Tool := CreateWriteTool(FWorkDir);
  (Tool as TBaseTool).UndoLog := FUndoLog;
  FilePath := TPath.Combine(FWorkDir, 'empty.txt');
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'empty.txt');
    Params.AddPair('content', '');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'WriteEmptyContent should succeed');
      Assert(TFile.Exists(FilePath), 'Empty file should exist');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestWriteFileTool.WriteOutsideWorkDir;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
begin
  Tool := CreateWriteTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'C:\Windows\Temp\pimono_hack.txt');
    Params.AddPair('content', 'should fail');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(R.IsError, 'WriteOutsideWorkDir should fail');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestWriteFileTool.UndoLogRecorded;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
begin
  Tool := CreateWriteTool(FWorkDir);
  (Tool as TBaseTool).UndoLog := FUndoLog;
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'tracked.txt');
    Params.AddPair('content', 'content');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'UndoLogRecorded write should succeed');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
  Assert(FUndoLog.GetEntryCount > 0, 'UndoLog should have an entry');
end;

procedure TTestWriteFileTool.WriteWithExistingUndoLog;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
begin
  // Write first file
  Tool := CreateWriteTool(FWorkDir);
  (Tool as TBaseTool).UndoLog := FUndoLog;
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'file1.txt');
    Params.AddPair('content', 'content1');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    R.ReleaseContent;
  finally
    Params.Free;
  end;

  // Write second file
  Tool := CreateWriteTool(FWorkDir);
  (Tool as TBaseTool).UndoLog := FUndoLog;
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'file2.txt');
    Params.AddPair('content', 'content2');
    R := Tool.Execute('tc2', Params, function: Boolean begin Result := False; end);
    R.ReleaseContent;
  finally
    Params.Free;
  end;

  Assert(2 = FUndoLog.GetEntryCount, 'UndoLog should have 2 entries');
end;

{ === TTestEditFileTool === }

procedure TTestEditFileTool.Setup;
begin
  FWorkDir := TPath.Combine(TPath.GetTempPath, 'PiMonoEdit_' + FormatDateTime('yyyymmddhhnnsszzz', Now) + '_' + IntToStr(GetTickCount));
  TDirectory.CreateDirectory(FWorkDir);
  FUndoLog := TUndoLog.Create(FWorkDir);
end;

procedure TTestEditFileTool.TearDown;
begin
  FUndoLog.Free;
  try
    if TDirectory.Exists(FWorkDir) then
      TDirectory.Delete(FWorkDir, True);
  except
  end;
end;

procedure TTestEditFileTool.ExactMatch;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
  FilePath: string;
begin
  FilePath := TPath.Combine(FWorkDir, 'edit.txt');
  TFile.WriteAllText(FilePath, 'Hello World');

  Tool := CreateEditTool(FWorkDir);
  (Tool as TBaseTool).UndoLog := FUndoLog;
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'edit.txt');
    Params.AddPair('oldText', 'World');
    Params.AddPair('newText', 'PiMono');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'ExactMatch should succeed');
      Assert('Hello PiMono' = TFile.ReadAllText(FilePath), 'Text should be replaced');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestEditFileTool.OldTextNotFound;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
begin
  TFile.WriteAllText(TPath.Combine(FWorkDir, 'edit.txt'), 'Hello World');

  Tool := CreateEditTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'edit.txt');
    Params.AddPair('oldText', 'NotPresent');
    Params.AddPair('newText', 'Replacement');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(R.IsError, 'Should error when oldText not found');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestEditFileTool.OldTextMultipleMatches;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
begin
  TFile.WriteAllText(TPath.Combine(FWorkDir, 'edit.txt'), 'abc abc abc');

  Tool := CreateEditTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'edit.txt');
    Params.AddPair('oldText', 'abc');
    Params.AddPair('newText', 'xyz');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(R.IsError, 'Should error when multiple matches found');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestEditFileTool.EmptyOldText;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
begin
  TFile.WriteAllText(TPath.Combine(FWorkDir, 'edit.txt'), 'content');

  Tool := CreateEditTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'edit.txt');
    Params.AddPair('oldText', '');
    Params.AddPair('newText', 'xyz');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(R.IsError, 'Should error when oldText is empty');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestEditFileTool.FuzzyMatch_WhitespaceDiff;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
  FilePath: string;
begin
  FilePath := TPath.Combine(FWorkDir, 'fuzzy.txt');
  TFile.WriteAllText(FilePath, 'function test(  ):'#13#10'  return true'#13#10'end');

  Tool := CreateEditTool(FWorkDir);
  (Tool as TBaseTool).UndoLog := FUndoLog;
  Params := TJSONObject.Create;
  try
    // oldText has different whitespace than file content
    Params.AddPair('path', 'fuzzy.txt');
    Params.AddPair('oldText', 'function test()'#10'  return true'#10'end');
    Params.AddPair('newText', 'function test()'#10'  return false'#10'end');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      // Fuzzy matching should succeed
      Assert(not R.IsError, 'Fuzzy match should succeed with whitespace diff');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestEditFileTool.EditNonExistentFile;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
begin
  Tool := CreateEditTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'missing.txt');
    Params.AddPair('oldText', 'something');
    Params.AddPair('newText', 'other');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(R.IsError, 'EditNonExistentFile should fail');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestEditFileTool.EditOutsideWorkDir;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
begin
  Tool := CreateEditTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'C:\Windows\Temp\test.txt');
    Params.AddPair('oldText', 'a');
    Params.AddPair('newText', 'b');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(R.IsError, 'Should block edit outside work dir');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestEditFileTool.UndoLogRecorded;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
  Entry: TUndoEntry;
begin
  TFile.WriteAllText(TPath.Combine(FWorkDir, 'edit.txt'), 'original');

  Tool := CreateEditTool(FWorkDir);
  (Tool as TBaseTool).UndoLog := FUndoLog;
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'edit.txt');
    Params.AddPair('oldText', 'original');
    Params.AddPair('newText', 'modified');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    R.ReleaseContent;
  finally
    Params.Free;
  end;

  Assert(FUndoLog.GetEntryCount > 0, 'UndoLog should record edit');
  Entry := FUndoLog.GetLastEntry;
  Assert('original' = Entry.OldContent, 'UndoLog should store original content');
end;

procedure TTestEditFileTool.UnicodeContent;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
  FilePath: string;
begin
  FilePath := TPath.Combine(FWorkDir, 'unicode.txt');
  TFile.WriteAllText(FilePath, #20320#22909#19990#30028, TEncoding.UTF8);

  Tool := CreateEditTool(FWorkDir);
  (Tool as TBaseTool).UndoLog := FUndoLog;
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'unicode.txt');
    Params.AddPair('oldText', #20320#22909);
    Params.AddPair('newText', #20877#35265);
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'UnicodeContent edit should succeed');
      Assert(#20877#35265#19990#30028 = TFile.ReadAllText(FilePath, TEncoding.UTF8),
        'Unicode content should be replaced');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestEditFileTool.LargeReplacement;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
  FilePath, LargeOld, LargeNew: string;
begin
  FilePath := TPath.Combine(FWorkDir, 'large.txt');
  LargeOld := StringOfChar('A', 10000);
  LargeNew := StringOfChar('B', 10000);
  TFile.WriteAllText(FilePath, LargeOld + '_TAIL');

  Tool := CreateEditTool(FWorkDir);
  (Tool as TBaseTool).UndoLog := FUndoLog;
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'large.txt');
    Params.AddPair('oldText', LargeOld);
    Params.AddPair('newText', LargeNew);
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'LargeReplacement should succeed');
      Assert(LargeNew + '_TAIL' = TFile.ReadAllText(FilePath),
        'Large replacement content should match');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

{ === TTestLsTool === }

type
  TTestLsTool = class
  private
    FWorkDir: string;
  public
    procedure Setup;
    procedure TearDown;
    procedure Ls_NormalDir;
    procedure Ls_EmptyDir;
    procedure Ls_SubDirectory;
  end;

procedure TTestLsTool.Setup;
begin
  FWorkDir := TPath.Combine(TPath.GetTempPath, 'PiMonoLs_' + FormatDateTime('yyyymmddhhnnsszzz', Now) + '_' + IntToStr(GetTickCount));
  TDirectory.CreateDirectory(FWorkDir);
end;

procedure TTestLsTool.TearDown;
begin
  try
    if TDirectory.Exists(FWorkDir) then
      TDirectory.Delete(FWorkDir, True);
  except
  end;
end;

procedure TTestLsTool.Ls_NormalDir;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
begin
  TFile.WriteAllText(TPath.Combine(FWorkDir, 'file1.txt'), 'a');
  TFile.WriteAllText(TPath.Combine(FWorkDir, 'file2.pas'), 'b');
  TDirectory.CreateDirectory(TPath.Combine(FWorkDir, 'subdir'));

  Tool := CreateLsTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', '.');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'Ls should succeed');
      var Text := (R.Content[0] as TTextContent).Text;
      Assert(Pos('file1.txt', Text) > 0, 'Should list file1.txt');
      Assert(Pos('file2.pas', Text) > 0, 'Should list file2.pas');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestLsTool.Ls_EmptyDir;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
begin
  Tool := CreateLsTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'Ls on empty dir should succeed');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestLsTool.Ls_SubDirectory;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
  SubDir: string;
begin
  SubDir := TPath.Combine(FWorkDir, 'child');
  TDirectory.CreateDirectory(SubDir);
  TFile.WriteAllText(TPath.Combine(SubDir, 'nested.txt'), 'x');

  Tool := CreateLsTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'child');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'Ls on subdir should succeed');
      Assert(Pos('nested.txt', (R.Content[0] as TTextContent).Text) > 0, 'Should list nested.txt');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

{ === TTestFindTool === }

type
  TTestFindTool = class
  private
    FWorkDir: string;
  public
    procedure Setup;
    procedure TearDown;
    procedure Find_ByPattern;
    procedure Find_NoMatch;
    procedure Find_Recursive;
  end;

procedure TTestFindTool.Setup;
begin
  FWorkDir := TPath.Combine(TPath.GetTempPath, 'PiMonoFind_' + FormatDateTime('yyyymmddhhnnsszzz', Now) + '_' + IntToStr(GetTickCount));
  TDirectory.CreateDirectory(FWorkDir);
end;

procedure TTestFindTool.TearDown;
begin
  try
    if TDirectory.Exists(FWorkDir) then
      TDirectory.Delete(FWorkDir, True);
  except
  end;
end;

procedure TTestFindTool.Find_ByPattern;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
begin
  TFile.WriteAllText(TPath.Combine(FWorkDir, 'test.pas'), 'code');
  TFile.WriteAllText(TPath.Combine(FWorkDir, 'test.txt'), 'text');

  Tool := CreateFindTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('pattern', '*.pas');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'Find should succeed');
      Assert(Pos('test.pas', (R.Content[0] as TTextContent).Text) > 0, 'Should find .pas file');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestFindTool.Find_NoMatch;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
begin
  Tool := CreateFindTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('pattern', '*.xyz');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'Find no match should not error');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestFindTool.Find_Recursive;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
  SubDir: string;
begin
  SubDir := TPath.Combine(FWorkDir, 'src');
  TDirectory.CreateDirectory(SubDir);
  TFile.WriteAllText(TPath.Combine(SubDir, 'deep.pas'), 'code');

  Tool := CreateFindTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('pattern', '*.pas');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'Recursive find should succeed');
      Assert(Pos('deep.pas', (R.Content[0] as TTextContent).Text) > 0, 'Should find file in subdir');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

{ === TTestGrepTool === }

type
  TTestGrepTool = class
  private
    FWorkDir: string;
  public
    procedure Setup;
    procedure TearDown;
    procedure Grep_MatchFound;
    procedure Grep_NoMatch;
    procedure Grep_CaseInsensitive;
  end;

procedure TTestGrepTool.Setup;
begin
  FWorkDir := TPath.Combine(TPath.GetTempPath, 'PiMonoGrep_' + FormatDateTime('yyyymmddhhnnsszzz', Now) + '_' + IntToStr(GetTickCount));
  TDirectory.CreateDirectory(FWorkDir);
end;

procedure TTestGrepTool.TearDown;
begin
  try
    if TDirectory.Exists(FWorkDir) then
      TDirectory.Delete(FWorkDir, True);
  except
  end;
end;

procedure TTestGrepTool.Grep_MatchFound;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
begin
  TFile.WriteAllText(TPath.Combine(FWorkDir, 'code.pas'), 'procedure HelloWorld;'#10'begin'#10'  WriteLn(''Hello'');'#10'end;');

  Tool := CreateGrepTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('pattern', 'HelloWorld');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'Grep should succeed');
      Assert(Pos('HelloWorld', (R.Content[0] as TTextContent).Text) > 0, 'Should find match');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestGrepTool.Grep_NoMatch;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
begin
  TFile.WriteAllText(TPath.Combine(FWorkDir, 'code.pas'), 'no match here');

  Tool := CreateGrepTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('pattern', 'NONEXISTENT_PATTERN_XYZ');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'Grep no match should not error');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestGrepTool.Grep_CaseInsensitive;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
begin
  TFile.WriteAllText(TPath.Combine(FWorkDir, 'code.pas'), 'PROCEDURE TEST;');

  Tool := CreateGrepTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('pattern', 'procedure');
    Params.AddPair('ignoreCase', TJSONBool.Create(True));
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'Case insensitive grep should succeed');
      Assert(Pos('TEST', (R.Content[0] as TTextContent).Text) > 0, 'Should find match ignoring case');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

{ === Registration === }

procedure RegisterFileToolsTests;
var
  T1: TTestReadFileTool;
  T2: TTestWriteFileTool;
  T3: TTestEditFileTool;
begin
  T1 := TTestReadFileTool.Create;
  try
    GRunner.RunTest('ReadFile.ReadNormalFile', T1.ReadNormalFile, T1.Setup, T1.TearDown);
    GRunner.RunTest('ReadFile.ReadEmptyFile', T1.ReadEmptyFile, T1.Setup, T1.TearDown);
    GRunner.RunTest('ReadFile.ReadNonExistent', T1.ReadNonExistent, T1.Setup, T1.TearDown);
    GRunner.RunTest('ReadFile.ReadWithOffset', T1.ReadWithOffset, T1.Setup, T1.TearDown);
    GRunner.RunTest('ReadFile.ReadWithLimit', T1.ReadWithLimit, T1.Setup, T1.TearDown);
    GRunner.RunTest('ReadFile.ReadUnicodeContent', T1.ReadUnicodeContent, T1.Setup, T1.TearDown);
    GRunner.RunTest('ReadFile.ReadOutsideWorkDir', T1.ReadOutsideWorkDir, T1.Setup, T1.TearDown);
    GRunner.RunTest('ReadFile.ReadTruncation2000Lines', T1.ReadTruncation2000Lines, T1.Setup, T1.TearDown);
  finally
    T1.Free;
  end;

  T2 := TTestWriteFileTool.Create;
  try
    GRunner.RunTest('WriteFile.WriteNewFile', T2.WriteNewFile, T2.Setup, T2.TearDown);
    GRunner.RunTest('WriteFile.OverwriteExisting', T2.OverwriteExisting, T2.Setup, T2.TearDown);
    GRunner.RunTest('WriteFile.CreateParentDirectories', T2.CreateParentDirectories, T2.Setup, T2.TearDown);
    GRunner.RunTest('WriteFile.WriteEmptyContent', T2.WriteEmptyContent, T2.Setup, T2.TearDown);
    GRunner.RunTest('WriteFile.WriteOutsideWorkDir', T2.WriteOutsideWorkDir, T2.Setup, T2.TearDown);
    GRunner.RunTest('WriteFile.UndoLogRecorded', T2.UndoLogRecorded, T2.Setup, T2.TearDown);
    GRunner.RunTest('WriteFile.WriteWithExistingUndoLog', T2.WriteWithExistingUndoLog, T2.Setup, T2.TearDown);
  finally
    T2.Free;
  end;

  T3 := TTestEditFileTool.Create;
  try
    GRunner.RunTest('EditFile.ExactMatch', T3.ExactMatch, T3.Setup, T3.TearDown);
    GRunner.RunTest('EditFile.OldTextNotFound', T3.OldTextNotFound, T3.Setup, T3.TearDown);
    GRunner.RunTest('EditFile.OldTextMultipleMatches', T3.OldTextMultipleMatches, T3.Setup, T3.TearDown);
    GRunner.RunTest('EditFile.EmptyOldText', T3.EmptyOldText, T3.Setup, T3.TearDown);
    GRunner.RunTest('EditFile.FuzzyMatch_WhitespaceDiff', T3.FuzzyMatch_WhitespaceDiff, T3.Setup, T3.TearDown);
    GRunner.RunTest('EditFile.EditNonExistentFile', T3.EditNonExistentFile, T3.Setup, T3.TearDown);
    GRunner.RunTest('EditFile.EditOutsideWorkDir', T3.EditOutsideWorkDir, T3.Setup, T3.TearDown);
    GRunner.RunTest('EditFile.UndoLogRecorded', T3.UndoLogRecorded, T3.Setup, T3.TearDown);
    GRunner.RunTest('EditFile.UnicodeContent', T3.UnicodeContent, T3.Setup, T3.TearDown);
    GRunner.RunTest('EditFile.LargeReplacement', T3.LargeReplacement, T3.Setup, T3.TearDown);
  finally
    T3.Free;
  end;

  var T4 := TTestLsTool.Create;
  try
    GRunner.RunTest('LsTool: Normal dir', T4.Ls_NormalDir, T4.Setup, T4.TearDown);
    GRunner.RunTest('LsTool: Empty dir', T4.Ls_EmptyDir, T4.Setup, T4.TearDown);
    GRunner.RunTest('LsTool: Subdirectory', T4.Ls_SubDirectory, T4.Setup, T4.TearDown);
  finally
    T4.Free;
  end;

  var T5 := TTestFindTool.Create;
  try
    GRunner.RunTest('FindTool: By pattern', T5.Find_ByPattern, T5.Setup, T5.TearDown);
    GRunner.RunTest('FindTool: No match', T5.Find_NoMatch, T5.Setup, T5.TearDown);
    GRunner.RunTest('FindTool: Recursive', T5.Find_Recursive, T5.Setup, T5.TearDown);
  finally
    T5.Free;
  end;

  var T6 := TTestGrepTool.Create;
  try
    GRunner.RunTest('GrepTool: Match found', T6.Grep_MatchFound, T6.Setup, T6.TearDown);
    GRunner.RunTest('GrepTool: No match', T6.Grep_NoMatch, T6.Setup, T6.TearDown);
    GRunner.RunTest('GrepTool: Case insensitive', T6.Grep_CaseInsensitive, T6.Setup, T6.TearDown);
  finally
    T6.Free;
  end;
end;

end.
