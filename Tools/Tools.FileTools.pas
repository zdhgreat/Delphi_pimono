unit Tools.FileTools;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON,
  System.RegularExpressions, System.Masks, System.Math,
  Core.Messages, Core.AgentState, Core.UndoLog, Tools.ITool, Utils.JsonHelper;

type
  // --- Read File Tool ---
  TReadFileTool = class(TBaseTool)
  protected
    function GetName: string; override;
    function GetLabel: string; override;
    function GetDescription: string; override;
    function GetParameterSchema: TJSONObject; override;
  public
    constructor Create(const AWorkingDir: string); override;
    function Execute(const AToolCallId: string; AParams: TJSONObject;
      AIsAborted: TAbortedCallback): TToolResult; override;
  end;

  // --- Write File Tool ---
  TWriteFileTool = class(TBaseTool)
  protected
    function GetName: string; override;
    function GetLabel: string; override;
    function GetDescription: string; override;
    function GetParameterSchema: TJSONObject; override;
  public
    constructor Create(const AWorkingDir: string); override;
    function Execute(const AToolCallId: string; AParams: TJSONObject;
      AIsAborted: TAbortedCallback): TToolResult; override;
  end;

  // --- Edit File Tool ---
  TEditFileTool = class(TBaseTool)
  protected
    function GetName: string; override;
    function GetLabel: string; override;
    function GetDescription: string; override;
    function GetParameterSchema: TJSONObject; override;
  public
    constructor Create(const AWorkingDir: string); override;
    function Execute(const AToolCallId: string; AParams: TJSONObject;
      AIsAborted: TAbortedCallback): TToolResult; override;
  end;

  // --- List Directory Tool ---
  TLsTool = class(TBaseTool)
  protected
    function GetName: string; override;
    function GetLabel: string; override;
    function GetDescription: string; override;
    function GetParameterSchema: TJSONObject; override;
  public
    constructor Create(const AWorkingDir: string); override;
    function Execute(const AToolCallId: string; AParams: TJSONObject;
      AIsAborted: TAbortedCallback): TToolResult; override;
  end;

  // --- Find Files Tool ---
  TFindTool = class(TBaseTool)
  protected
    function GetName: string; override;
    function GetLabel: string; override;
    function GetDescription: string; override;
    function GetParameterSchema: TJSONObject; override;
  public
    constructor Create(const AWorkingDir: string); override;
    function Execute(const AToolCallId: string; AParams: TJSONObject;
      AIsAborted: TAbortedCallback): TToolResult; override;
  end;

  // --- Grep Content Tool ---
  TGrepTool = class(TBaseTool)
  protected
    function GetName: string; override;
    function GetLabel: string; override;
    function GetDescription: string; override;
    function GetParameterSchema: TJSONObject; override;
  public
    constructor Create(const AWorkingDir: string); override;
    function Execute(const AToolCallId: string; AParams: TJSONObject;
      AIsAborted: TAbortedCallback): TToolResult; override;
  end;

// Factory functions
function CreateReadTool(const AWorkingDir: string): IAgentTool;
function CreateWriteTool(const AWorkingDir: string): IAgentTool;
function CreateEditTool(const AWorkingDir: string): IAgentTool;
function CreateLsTool(const AWorkingDir: string): IAgentTool;
function CreateFindTool(const AWorkingDir: string): IAgentTool;
function CreateGrepTool(const AWorkingDir: string): IAgentTool;
function CreateAllTools(const AWorkingDir: string): TArray<IAgentTool>;
function CreateReadOnlyTools(const AWorkingDir: string): TArray<IAgentTool>;

// Fuzzy edit matching helpers
function NormalizeText(const AText: string): string;
function EstimateOriginalPos(const AOriginal, ANormalized: string; ANormPos: Integer): Integer;
function FuzzyLineMatch(const AFileContent, AOldText: string): Integer;

// .gitignore support
function LoadGitignorePatterns(const ARootDir: string): TArray<string>;
function IsIgnoredByGitignore(const AFilePath, ARootDir: string;
  const APatterns: TArray<string>): Boolean;

implementation

const
  READ_MAX_LINES = 2000;
  LS_MAX_ENTRIES = 500;
  FIND_MAX_RESULTS = 1000;
  GREP_MAX_MATCHES = 100;
  GREP_MAX_FILE_SIZE = 10485760;  // 10MB
  SLIM_MAX_RESULT_CHARS = 2000;

function FormatFileSize(ABytes: Int64): string; forward;

// --- TReadFileTool ---

constructor TReadFileTool.Create(const AWorkingDir: string);
begin
  inherited Create(AWorkingDir);
end;

function TReadFileTool.GetName: string;
begin
  Result := 'read';
end;

function TReadFileTool.GetLabel: string;
begin
  Result := 'Read File';
end;

function TReadFileTool.GetDescription: string;
begin
  Result := 'Read the contents of a file. Returns file content with line numbers. Supports offset and limit for partial reads.';
end;

function TReadFileTool.GetParameterSchema: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  var Props := TJSONObject.Create;
  Props.AddPair('path', BuildStringParam('path', 'The file path to read'));
  Props.AddPair('offset', BuildIntegerParam('offset', 'Line number to start reading from (1-based)'));
  Props.AddPair('limit', BuildIntegerParam('limit', 'Maximum number of lines to read'));
  Result.AddPair('properties', Props);
  var Req := TJSONArray.Create;
  Req.Add('path');
  Result.AddPair('required', Req);
end;

function TReadFileTool.Execute(const AToolCallId: string;
  AParams: TJSONObject; AIsAborted: TAbortedCallback): TToolResult;
var
  Path: string;
  Offset, Limit, i, LineNum: Integer;
  Lines: TArray<string>;
  SB: TStringBuilder;
  MaxLines: Integer;
  Content: TContentBlockList;
begin
  Path := ResolvePath(JsonGetStr(AParams, 'path', ''));

  if not FileExists(Path) then
    Exit(TToolResult.CreateError('File not found: ' + Path));

  if not IsPathInWorkingDir(Path) then
    Exit(TToolResult.CreateError('Path is outside the working directory: ' + Path));

  if TFile.GetSize(Path) > GREP_MAX_FILE_SIZE then
    Exit(TToolResult.CreateError('File too large to read (max 10MB). Use grep or find to search within it.'));

  Offset := JsonGetInt(AParams, 'offset', 1);
  if Offset < 1 then Offset := 1;
  Limit := JsonGetInt(AParams, 'limit', 0);

  try
    Lines := TFile.ReadAllLines(Path, TEncoding.UTF8);
  except
    on E: Exception do
      Exit(TToolResult.CreateError('Failed to read file: ' + E.Message));
  end;

  MaxLines := READ_MAX_LINES;
  if (Limit > 0) and (Limit < MaxLines) then
    MaxLines := Limit;

  SB := TStringBuilder.Create;
  try
    LineNum := 0;
    for i := Offset - 1 to High(Lines) do
    begin
      if LineNum >= MaxLines then
      begin
        SB.AppendLine(Format('... [%d more lines]', [Length(Lines) - i]));
        Break;
      end;
      if Assigned(AIsAborted) and AIsAborted then
      begin
        SB.AppendLine('[Read aborted]');
        Break;
      end;
      SB.AppendLine(Format('%6d'#9'%s', [i + 1, Lines[i]]));
      Inc(LineNum);
    end;

    if Length(Lines) > MaxLines then
      SB.AppendLine(Format(#10'File has %d total lines. Showing lines %d-%d.',
        [Length(Lines), Offset, Min(Offset + MaxLines - 1, Length(Lines))]));

    Content := TContentBlockList.Create;
    Content.Add(TTextContent.Create(SB.ToString));
    Result := TToolResult.Create(Content, False);
  finally
    SB.Free;
  end;
end;

// --- TWriteFileTool ---

constructor TWriteFileTool.Create(const AWorkingDir: string);
begin
  inherited Create(AWorkingDir);
end;

function TWriteFileTool.GetName: string;
begin
  Result := 'write';
end;

function TWriteFileTool.GetLabel: string;
begin
  Result := 'Write File';
end;

function TWriteFileTool.GetDescription: string;
begin
  Result := 'Write content to a file. Creates the file if it does not exist, overwrites if it does. Creates parent directories as needed.';
end;

function TWriteFileTool.GetParameterSchema: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  var Props := TJSONObject.Create;
  Props.AddPair('path', BuildStringParam('path', 'The file path to write to'));
  Props.AddPair('content', BuildStringParam('content', 'The content to write to the file'));
  Result.AddPair('properties', Props);
  var Req := TJSONArray.Create;
  Req.Add('path');
  Req.Add('content');
  Result.AddPair('required', Req);
end;

function TWriteFileTool.Execute(const AToolCallId: string;
  AParams: TJSONObject; AIsAborted: TAbortedCallback): TToolResult;
var
  Path, Content: string;
  Dir: string;
  Bytes: TBytes;
  List: TContentBlockList;
begin
  Path := ResolvePath(JsonGetStr(AParams, 'path', ''));
  Content := JsonGetStr(AParams, 'content', '');

  if Path = '' then
    Exit(TToolResult.CreateError('Path parameter is required'));

  if not IsPathInWorkingDir(Path) then
    Exit(TToolResult.CreateError('Path is outside the working directory: ' + Path));

  // Create parent directories
  Dir := ExtractFileDir(Path);
  if (Dir <> '') and not DirectoryExists(Dir) then
  begin
    try
      ForceDirectories(Dir);
    except
      on E: Exception do
        Exit(TToolResult.CreateError('Failed to create directory: ' + E.Message));
    end;
  end;

  try
    // Record undo: capture old content before overwriting
    if FUndoLog <> nil then
    begin
      var OldContent := '';
      var FileExisted := TFile.Exists(Path);
      if FileExisted then
      try
        OldContent := TFile.ReadAllText(Path, TEncoding.UTF8);
      except
        OldContent := '';
      end;
      if FileExisted then
        FUndoLog.RecordOperation(Path, 'write', OldContent, AToolCallId)
      else
        FUndoLog.RecordOperation(Path, 'create', '', AToolCallId);
    end;

    Bytes := TEncoding.UTF8.GetBytes(Content);
    TFile.WriteAllBytes(Path, Bytes);
  except
    on E: Exception do
      Exit(TToolResult.CreateError('Failed to write file: ' + E.Message));
  end;

  List := TContentBlockList.Create;
  List.Add(TTextContent.Create(Format(
    'Successfully wrote %d bytes to %s', [Length(Bytes), Path])));
  Result := TToolResult.Create(List, False);
end;

// --- TEditFileTool ---

constructor TEditFileTool.Create(const AWorkingDir: string);
begin
  inherited Create(AWorkingDir);
end;

function TEditFileTool.GetName: string;
begin
  Result := 'edit';
end;

function TEditFileTool.GetLabel: string;
begin
  Result := 'Edit File';
end;

function TEditFileTool.GetDescription: string;
begin
  Result := 'Edit a file by replacing exact text matches. The oldText must be unique in the file. Creates a backup before editing.';
end;

function TEditFileTool.GetParameterSchema: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  var Props := TJSONObject.Create;
  Props.AddPair('path', BuildStringParam('path', 'The file path to edit'));
  Props.AddPair('oldText', BuildStringParam('oldText', 'The text to find and replace (must be unique in the file)'));
  Props.AddPair('newText', BuildStringParam('newText', 'The replacement text'));
  Result.AddPair('properties', Props);
  var Req := TJSONArray.Create;
  Req.Add('path');
  Req.Add('oldText');
  Req.Add('newText');
  Result.AddPair('required', Req);
end;

function TEditFileTool.Execute(const AToolCallId: string;
  AParams: TJSONObject; AIsAborted: TAbortedCallback): TToolResult;
var
  Path, OldText, NewText, FileContent: string;
  Pos1: Integer;
  BackupPath: string;
  List: TContentBlockList;
  Diff: TStringBuilder;
  OldLines, NewLines: TArray<string>;
  i: Integer;
begin
  Path := ResolvePath(JsonGetStr(AParams, 'path', ''));
  OldText := JsonGetStr(AParams, 'oldText', '');
  NewText := JsonGetStr(AParams, 'newText', '');

  if not IsPathInWorkingDir(Path) then
    Exit(TToolResult.CreateError('Path is outside the working directory: ' + Path));

  if not FileExists(Path) then
    Exit(TToolResult.CreateError('File not found: ' + Path));

  if OldText = '' then
    Exit(TToolResult.CreateError('oldText parameter is required'));

  try
    FileContent := TFile.ReadAllText(Path, TEncoding.UTF8);
  except
    on E: Exception do
      Exit(TToolResult.CreateError('Failed to read file: ' + E.Message));
  end;

  // Record undo: capture original content before editing
  var OriginalContent := FileContent;

  // Normalize line endings for matching, remember original style
  var HasCRLF := Pos(#13#10, FileContent) > 0;
  FileContent := StringReplace(FileContent, #13#10, #10, [rfReplaceAll]);
  OldText := StringReplace(OldText, #13#10, #10, [rfReplaceAll]);
  NewText := StringReplace(NewText, #13#10, #10, [rfReplaceAll]);

  // Find old text (exact match first)
  Pos1 := Pos(OldText, FileContent);
  if Pos1 = 0 then
  begin
    // Fuzzy matching: try with normalized whitespace
    var NormFile := NormalizeText(FileContent);
    var NormOld := NormalizeText(OldText);
    Pos1 := Pos(NormOld, NormFile);
    if Pos1 > 0 then
    begin
      // Map normalized position back to original - search nearby
      // Count chars before match in normalized text to estimate original position
      var EstPos := EstimateOriginalPos(FileContent, NormFile, Pos1);
      if EstPos > 0 then
        Pos1 := EstPos
      else
        Pos1 := 0;
    end;

    if Pos1 = 0 then
    begin
      // Line-by-line fuzzy match as last resort
      Pos1 := FuzzyLineMatch(FileContent, OldText);
    end;

    if Pos1 = 0 then
      Exit(TToolResult.CreateError(
        'oldText not found in file (exact and fuzzy match failed). ' +
        'The file content may have changed since the AI last read it.'));
  end;

  // Check uniqueness
  if Pos(OldText, Copy(FileContent, Pos1 + 1, MaxInt)) > 0 then
    Exit(TToolResult.CreateError('oldText found multiple times in file. Please provide more context to make it unique.'));

  // Create backup
  BackupPath := Path + '.bak';
  try
    TFile.Copy(Path, BackupPath, True);
  except
    // Backup failure is not critical
  end;

  // Perform replacement
  Delete(FileContent, Pos1, Length(OldText));
  Insert(NewText, FileContent, Pos1);

  // Restore original line endings
  if HasCRLF then
    FileContent := StringReplace(FileContent, #10, #13#10, [rfReplaceAll]);

  try
    TFile.WriteAllText(Path, FileContent, TEncoding.UTF8);
    // Record undo after successful write
    if FUndoLog <> nil then
      FUndoLog.RecordOperation(Path, 'edit', OriginalContent, AToolCallId);
  except
    on E: Exception do
    begin
      // Restore from backup
      if FileExists(BackupPath) then
        TFile.Copy(BackupPath, Path, True);
      Exit(TToolResult.CreateError('Failed to write edited file: ' + E.Message));
    end;
  end;

  // Build diff summary
  OldLines := OldText.Split([#10]);
  NewLines := NewText.Split([#10]);
  Diff := TStringBuilder.Create;
  try
    Diff.AppendLine(Format('Edited %s: replaced %d lines with %d lines',
      [ExtractFileName(Path), Length(OldLines), Length(NewLines)]));
    Diff.AppendLine;
    Diff.AppendLine('--- old');
    Diff.AppendLine('+++ new');
    for i := 0 to High(OldLines) do
      Diff.AppendLine('- ' + OldLines[i]);
    for i := 0 to High(NewLines) do
      Diff.AppendLine('+ ' + NewLines[i]);

    List := TContentBlockList.Create;
    List.Add(TTextContent.Create(Diff.ToString));
    Result := TToolResult.Create(List, False);
  finally
    Diff.Free;
  end;
end;

// --- TLsTool ---

constructor TLsTool.Create(const AWorkingDir: string);
begin
  inherited Create(AWorkingDir);
end;

function TLsTool.GetName: string;
begin
  Result := 'ls';
end;

function TLsTool.GetLabel: string;
begin
  Result := 'List Directory';
end;

function TLsTool.GetDescription: string;
begin
  Result := 'List files and directories in the specified path. Shows names with size info.';
end;

function TLsTool.GetParameterSchema: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  var Props := TJSONObject.Create;
  Props.AddPair('path', BuildStringParam('path', 'The directory path to list'));
  Result.AddPair('properties', Props);
end;

function TLsTool.Execute(const AToolCallId: string;
  AParams: TJSONObject; AIsAborted: TAbortedCallback): TToolResult;
var
  Path: string;
  Files: TArray<string>;
  Dirs: TArray<string>;
  SB: TStringBuilder;
  i: Integer;
  MaxEntries: Integer;
  List: TContentBlockList;
  SizeStr: string;
begin
  Path := ResolvePath(JsonGetStr(AParams, 'path', '.'));

  if not DirectoryExists(Path) then
    Exit(TToolResult.CreateError('Directory not found: ' + Path));

  if not IsPathInWorkingDir(Path) then
    Exit(TToolResult.CreateError('Path is outside the working directory: ' + Path));

  try
    Dirs := TDirectory.GetDirectories(Path);
    Files := TDirectory.GetFiles(Path);
  except
    on E: Exception do
      Exit(TToolResult.CreateError('Failed to list directory: ' + E.Message));
  end;

  MaxEntries := LS_MAX_ENTRIES;
  SB := TStringBuilder.Create;
  try
    SB.AppendLine(Format('Directory: %s', [Path]));
    SB.AppendLine(Format('Directories: %d, Files: %d', [Length(Dirs), Length(Files)]));
    SB.AppendLine;

    // List directories first
    for i := 0 to Min(High(Dirs), MaxEntries - 1) do
    begin
      if Assigned(AIsAborted) and AIsAborted then Break;
      SB.AppendLine('  ' + ExtractFileName(Dirs[i]) + '/');
    end;

    // List files
    for i := 0 to Min(High(Files), MaxEntries - Length(Dirs) - 1) do
    begin
      if Assigned(AIsAborted) and AIsAborted then Break;
      try
        SizeStr := FormatFileSize(TFile.GetSize(Files[i]));
      except
        SizeStr := '?';
      end;
      SB.AppendLine(Format('  %-40s %s', [ExtractFileName(Files[i]), SizeStr]));
    end;

    if Length(Dirs) + Length(Files) > MaxEntries then
      SB.AppendLine(Format(#10'... showing %d of %d entries',
        [MaxEntries, Length(Dirs) + Length(Files)]));

    List := TContentBlockList.Create;
    List.Add(TTextContent.Create(SB.ToString));
    Result := TToolResult.Create(List, False);
  finally
    SB.Free;
  end;
end;

// --- TFindTool ---

constructor TFindTool.Create(const AWorkingDir: string);
begin
  inherited Create(AWorkingDir);
end;

function TFindTool.GetName: string;
begin
  Result := 'find';
end;

function TFindTool.GetLabel: string;
begin
  Result := 'Find Files';
end;

function TFindTool.GetDescription: string;
begin
  Result := 'Find files by name pattern (glob). Searches recursively. Respects .gitignore.';
end;

function TFindTool.GetParameterSchema: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  var Props := TJSONObject.Create;
  Props.AddPair('pattern', BuildStringParam('pattern', 'File name pattern (glob syntax, e.g. "*.pas", "test*")'));
  Props.AddPair('path', BuildStringParam('path', 'Directory to search in'));
  Props.AddPair('limit', BuildIntegerParam('limit', 'Maximum number of results'));
  Result.AddPair('properties', Props);
  var Req := TJSONArray.Create;
  Req.Add('pattern');
  Result.AddPair('required', Req);
end;

function TFindTool.Execute(const AToolCallId: string;
  AParams: TJSONObject; AIsAborted: TAbortedCallback): TToolResult;
var
  Pattern, Path: string;
  Limit, Count: Integer;
  Files: TArray<string>;
  SB: TStringBuilder;
  i: Integer;
  MaxResults: Integer;
  List: TContentBlockList;
  RelPath: string;
  IgnorePatterns: TArray<string>;
begin
  Pattern := JsonGetStr(AParams, 'pattern', '*');
  Path := ResolvePath(JsonGetStr(AParams, 'path', '.'));
  Limit := JsonGetInt(AParams, 'limit', 0);

  if not DirectoryExists(Path) then
    Exit(TToolResult.CreateError('Directory not found: ' + Path));

  if not IsPathInWorkingDir(Path) then
    Exit(TToolResult.CreateError('Path is outside the working directory: ' + Path));

  MaxResults := FIND_MAX_RESULTS;
  if (Limit > 0) and (Limit < MaxResults) then
    MaxResults := Limit;

  // Load .gitignore patterns
  IgnorePatterns := LoadGitignorePatterns(Path);

  try
    Files := TDirectory.GetFiles(Path, Pattern,
      TSearchOption.soAllDirectories);
  except
    on E: Exception do
      Exit(TToolResult.CreateError('Failed to search: ' + E.Message));
  end;

  SB := TStringBuilder.Create;
  try
    Count := 0;
    for i := 0 to High(Files) do
    begin
      if Count >= MaxResults then
      begin
        SB.AppendLine(Format('... %d more results not shown', [Length(Files) - i]));
        Break;
      end;
      if Assigned(AIsAborted) and AIsAborted then Break;

      // Skip gitignored files
      if IsIgnoredByGitignore(Files[i], Path, IgnorePatterns) then
        Continue;

      // Make path relative
      RelPath := Files[i];
      if RelPath.StartsWith(Path, True) then
        RelPath := RelPath.Substring(Length(Path) + 1);

      SB.AppendLine(RelPath);
      Inc(Count);
    end;

    SB.Insert(0, Format('Found %d files matching "%s":' + #10, [Count, Pattern]));

    List := TContentBlockList.Create;
    List.Add(TTextContent.Create(SB.ToString));
    Result := TToolResult.Create(List, False);
  finally
    SB.Free;
  end;
end;

// --- TGrepTool ---

constructor TGrepTool.Create(const AWorkingDir: string);
begin
  inherited Create(AWorkingDir);
end;

function TGrepTool.GetName: string;
begin
  Result := 'grep';
end;

function TGrepTool.GetLabel: string;
begin
  Result := 'Search Content';
end;

function TGrepTool.GetDescription: string;
begin
  Result := 'Search file contents for a pattern (regex or literal). Returns matching lines with context.';
end;

function TGrepTool.GetParameterSchema: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  var Props := TJSONObject.Create;
  Props.AddPair('pattern', BuildStringParam('pattern', 'The search pattern (regex)'));
  Props.AddPair('path', BuildStringParam('path', 'File or directory to search in'));
  Props.AddPair('glob', BuildStringParam('glob', 'File name filter (e.g. "*.pas")'));
  Props.AddPair('ignoreCase', BuildBooleanParam('ignoreCase', 'Case insensitive search'));
  Props.AddPair('literal', BuildBooleanParam('literal', 'Treat pattern as literal string'));
  Props.AddPair('context', BuildIntegerParam('context', 'Number of context lines around matches'));
  Props.AddPair('limit', BuildIntegerParam('limit', 'Maximum number of matches'));
  Result.AddPair('properties', Props);
  var Req := TJSONArray.Create;
  Req.Add('pattern');
  Result.AddPair('required', Req);
end;

function TGrepTool.Execute(const AToolCallId: string;
  AParams: TJSONObject; AIsAborted: TAbortedCallback): TToolResult;
var
  Pattern, Path, Glob: string;
  IgnoreCase, Literal: Boolean;
  ContextLines, Limit, MatchCount: Integer;
  Files: TArray<string>;
  SB: TStringBuilder;
  i, j: Integer;
  Lines: TArray<string>;
  MaxMatches: Integer;
  List: TContentBlockList;
  RegEx: TRegEx;
  Options: TRegexOptions;
  Matches: TGroupCollection;
  RelPath: string;
  StartLine, EndLine: Integer;
begin
  Pattern := JsonGetStr(AParams, 'pattern', '');
  Path := ResolvePath(JsonGetStr(AParams, 'path', '.'));
  Glob := JsonGetStr(AParams, 'glob', '*');
  IgnoreCase := JsonGetBool(AParams, 'ignoreCase', False);
  Literal := JsonGetBool(AParams, 'literal', True);
  ContextLines := JsonGetInt(AParams, 'context', 2);
  Limit := JsonGetInt(AParams, 'limit', 0);

  if Pattern = '' then
    Exit(TToolResult.CreateError('Pattern parameter is required'));

  if not IsPathInWorkingDir(Path) then
    Exit(TToolResult.CreateError('Path is outside the working directory: ' + Path));

  MaxMatches := GREP_MAX_MATCHES;
  if (Limit > 0) and (Limit < MaxMatches) then
    MaxMatches := Limit;

  // Build regex
  Options := [roCompiled];
  if IgnoreCase then Include(Options, roIgnoreCase);
  if Literal then Pattern := TRegEx.Escape(Pattern);

  try
    RegEx := TRegEx.Create(Pattern, Options);
  except
    on E: Exception do
      Exit(TToolResult.CreateError('Invalid regex pattern: ' + E.Message));
  end;

  // Get files to search
  if FileExists(Path) then
  begin
    SetLength(Files, 1);
    Files[0] := Path;
  end
  else if DirectoryExists(Path) then
  begin
    try
      Files := TDirectory.GetFiles(Path, Glob,
        TSearchOption.soAllDirectories);
    except
      on E: Exception do
        Exit(TToolResult.CreateError('Failed to search directory: ' + E.Message));
    end;
  end
  else
    Exit(TToolResult.CreateError('Path not found: ' + Path));

  SB := TStringBuilder.Create;
  try
    MatchCount := 0;

    for i := 0 to High(Files) do
    begin
      if MatchCount >= MaxMatches then Break;
      if Assigned(AIsAborted) and AIsAborted then Break;

      // Skip binary files and large files
      try
        if TFile.GetSize(Files[i]) > GREP_MAX_FILE_SIZE then Continue;
        Lines := TFile.ReadAllLines(Files[i], TEncoding.UTF8);
      except
        Continue;
      end;

      RelPath := Files[i];
      if RelPath.StartsWith(FWorkingDir, True) then
        RelPath := RelPath.Substring(Length(FWorkingDir) + 1);

      for j := 0 to High(Lines) do
      begin
        if MatchCount >= MaxMatches then Break;

        if RegEx.IsMatch(Lines[j]) then
        begin
          Inc(MatchCount);

          SB.AppendLine(Format('%s:%d: %s', [RelPath, j + 1, Lines[j]]));

          // Show context lines after
          var CtxEnd := Min(j + ContextLines, High(Lines));
          var k: Integer;
          for k := j + 1 to CtxEnd do
            SB.AppendLine(Format('%s:%d:   %s', [RelPath, k + 1, Lines[k]]));

          SB.AppendLine;
        end;
      end;
    end;

    SB.Insert(0, Format('Found %d matches for "%s":' + #10, [MatchCount, Pattern]));

    if MatchCount >= MaxMatches then
      SB.AppendLine(Format('... results limited to %d matches', [MaxMatches]));

    List := TContentBlockList.Create;
    List.Add(TTextContent.Create(SB.ToString));
    Result := TToolResult.Create(List, False);
  finally
    SB.Free;
  end;
end;

// --- Factory Functions ---

function CreateReadTool(const AWorkingDir: string): IAgentTool;
begin
  Result := TReadFileTool.Create(AWorkingDir);
end;

function CreateWriteTool(const AWorkingDir: string): IAgentTool;
begin
  Result := TWriteFileTool.Create(AWorkingDir);
end;

function CreateEditTool(const AWorkingDir: string): IAgentTool;
begin
  Result := TEditFileTool.Create(AWorkingDir);
end;

function CreateLsTool(const AWorkingDir: string): IAgentTool;
begin
  Result := TLsTool.Create(AWorkingDir);
end;

function CreateFindTool(const AWorkingDir: string): IAgentTool;
begin
  Result := TFindTool.Create(AWorkingDir);
end;

function CreateGrepTool(const AWorkingDir: string): IAgentTool;
begin
  Result := TGrepTool.Create(AWorkingDir);
end;

function CreateAllTools(const AWorkingDir: string): TArray<IAgentTool>;
begin
  SetLength(Result, 6);
  Result[0] := CreateReadTool(AWorkingDir);
  Result[1] := CreateWriteTool(AWorkingDir);
  Result[2] := CreateEditTool(AWorkingDir);
  Result[3] := CreateLsTool(AWorkingDir);
  Result[4] := CreateFindTool(AWorkingDir);
  Result[5] := CreateGrepTool(AWorkingDir);
end;

function CreateReadOnlyTools(const AWorkingDir: string): TArray<IAgentTool>;
begin
  SetLength(Result, 3);
  Result[0] := CreateReadTool(AWorkingDir);
  Result[1] := CreateLsTool(AWorkingDir);
  Result[2] := CreateGrepTool(AWorkingDir);
end;

// --- Helper ---

function FormatFileSize(ABytes: Int64): string;
begin
  if ABytes < 1024 then
    Result := Format('%dB', [ABytes])
  else if ABytes < 1048576 then
    Result := Format('%.1fKB', [ABytes / 1024])
  else if ABytes < 1073741824 then
    Result := Format('%.1fMB', [ABytes / 1048576])
  else
    Result := Format('%.1fGB', [ABytes / 1073741824]);
end;

// --- Fuzzy Edit Matching Helpers ---

function NormalizeText(const AText: string): string;
begin
  Result := AText;
  // Normalize line endings to LF
  Result := StringReplace(Result, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #13, #10, [rfReplaceAll]);
  // Collapse multiple blank lines
  while Pos(#10#10#10, Result) > 0 do
    Result := StringReplace(Result, #10#10#10, #10#10, [rfReplaceAll]);
  // Trim trailing whitespace from each line
  var Lines := Result.Split([#10]);
  var SB := TStringBuilder.Create;
  try
    for var i := 0 to High(Lines) do
    begin
      if i > 0 then SB.Append(#10);
      SB.Append(TrimRight(Lines[i]));
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function EstimateOriginalPos(const AOriginal, ANormalized: string; ANormPos: Integer): Integer;
{$WARNINGS OFF}
var
  OrigIdx, NormIdx: Integer;
begin
  // Walk both strings in parallel to find the original position
  OrigIdx := 1;
  NormIdx := 1;
  while (OrigIdx <= Length(AOriginal)) and (NormIdx < ANormPos) do
  begin
    // Skip CR in original (normalized text removed it)
    if AOriginal[OrigIdx] = #13 then
    begin
      Inc(OrigIdx);
      Continue;
    end;
    // Skip trailing whitespace differences
    var OrigCh := AOriginal[OrigIdx];
    var NormCh := #0;
    if NormIdx <= Length(ANormalized) then
      NormCh := ANormalized[NormIdx];
    if (OrigCh = ' ') and (OrigCh <> NormCh) and
       (OrigIdx < Length(AOriginal)) and (AOriginal[OrigIdx + 1] = #10) then
    begin
      Inc(OrigIdx);
      Continue;
    end;
    Inc(OrigIdx);
    Inc(NormIdx);
  end;
  Result := OrigIdx;
end;
{$WARNINGS ON}

function FuzzyLineMatch(const AFileContent, AOldText: string): Integer;
var
  FileLines, OldLines: TArray<string>;
  i, j, MatchStart, Score, BestScore, BestPos: Integer;
begin
  Result := 0;
  FileLines := AFileContent.Split([#10]);
  OldLines := AOldText.Split([#10]);
  if (Length(OldLines) = 0) or (Length(FileLines) < Length(OldLines)) then
    Exit;

  BestScore := 0;
  BestPos := -1;

  for i := 0 to Length(FileLines) - Length(OldLines) do
  begin
    Score := 0;
    for j := 0 to High(OldLines) do
    begin
      if SameText(Trim(FileLines[i + j]), Trim(OldLines[j])) then
        Inc(Score, 2)       // Exact match (case-insensitive, trimmed)
      else if Pos(Trim(OldLines[j]), Trim(FileLines[i + j])) > 0 then
        Inc(Score, 1);      // Partial match
    end;
    // Need at least 70% match quality
    if (Score > BestScore) and (Score >= Length(OldLines) * 2 * 7 div 10) then
    begin
      BestScore := Score;
      BestPos := i;
    end;
  end;

  if BestPos >= 0 then
  begin
    // Convert line index back to char position
    MatchStart := 1;
    for i := 0 to BestPos - 1 do
      MatchStart := MatchStart + Length(FileLines[i]) + 1;
    Result := MatchStart;
  end;
end;

// --- .gitignore Support ---

function LoadGitignorePatterns(const ARootDir: string): TArray<string>;
var
  GitignorePath, Content: string;
  Lines: TArray<string>;
  i, Count: Integer;
begin
  Result := nil;
  GitignorePath := IncludeTrailingPathDelimiter(ARootDir) + '.gitignore';
  if not FileExists(GitignorePath) then
    Exit;

  try
    Content := TFile.ReadAllText(GitignorePath, TEncoding.UTF8);
  except
    Exit;
  end;

  Lines := Content.Split([#10, #13]);
  Count := 0;
  SetLength(Result, Length(Lines));
  for i := 0 to High(Lines) do
  begin
    var Line := Lines[i].Trim;
    // Skip empty lines and comments
    if (Line = '') or Line.StartsWith('#') then
      Continue;
    Result[Count] := Line;
    Inc(Count);
  end;
  SetLength(Result, Count);
end;

function IsIgnoredByGitignore(const AFilePath, ARootDir: string;
  const APatterns: TArray<string>): Boolean;
var
  RelPath: string;
  i: Integer;
  Pattern: string;
  FileName: string;
begin
  Result := False;
  if Length(APatterns) = 0 then
    Exit;

  // Get relative path
  RelPath := AFilePath;
  if RelPath.StartsWith(ARootDir, True) then
    RelPath := RelPath.Substring(Length(IncludeTrailingPathDelimiter(ARootDir)));

  FileName := ExtractFileName(RelPath);

  for i := 0 to High(APatterns) do
  begin
    Pattern := APatterns[i];

    // Negation pattern (un-ignore)
    if Pattern.StartsWith('!') then
    begin
      // Not implementing full negation for simplicity
      Continue;
    end;

    // Directory pattern (ending with /)
    if Pattern.EndsWith('/') then
    begin
      var DirPattern := Copy(Pattern, 1, Length(Pattern) - 1);
      if RelPath.StartsWith(DirPattern, True) or
         RelPath.Contains('/' + DirPattern + '/') or
         RelPath.Contains('\' + DirPattern + '\') then
        Exit(True);
      Continue;
    end;

    // Extension pattern (*.ext)
    if Pattern.StartsWith('*.') then
    begin
      var Ext := Copy(Pattern, 2, MaxInt);
      if FileName.EndsWith(Ext, True) then
        Exit(True);
      Continue;
    end;

    // Exact file/directory name
    if (FileName = Pattern) or
       RelPath.Contains('/' + Pattern + '/') or
       RelPath.Contains('\' + Pattern + '\') then
      Exit(True);

    // Path prefix match
    if RelPath.StartsWith(Pattern, True) then
      Exit(True);
  end;
end;

end.
