unit Tools.GitTool;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Math,
  Core.Messages, Core.AgentState, Tools.ITool, Tools.CommandRunner,
  Utils.JsonHelper;

type
  TGitStatusTool = class(TBaseTool)
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

  TGitDiffTool = class(TBaseTool)
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

  TGitLogTool = class(TBaseTool)
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

  TGitBlameTool = class(TBaseTool)
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

/// <summary>Create all four git tools.</summary>
function CreateGitTools(const AWorkingDir: string): TArray<IAgentTool>;

implementation

function CreateGitTools(const AWorkingDir: string): TArray<IAgentTool>;
begin
  SetLength(Result, 4);
  Result[0] := TGitStatusTool.Create(AWorkingDir);
  Result[1] := TGitDiffTool.Create(AWorkingDir);
  Result[2] := TGitLogTool.Create(AWorkingDir);
  Result[3] := TGitBlameTool.Create(AWorkingDir);
end;

// --- TGitStatusTool ---

constructor TGitStatusTool.Create(const AWorkingDir: string);
begin
  inherited Create(AWorkingDir);
end;

function TGitStatusTool.GetName: string;
begin
  Result := 'git_status';
end;

function TGitStatusTool.GetLabel: string;
begin
  Result := 'Git Status';
end;

function TGitStatusTool.GetDescription: string;
begin
  Result := 'Show the working tree status. Displays tracked, untracked, modified, and staged files.';
end;

function TGitStatusTool.GetParameterSchema: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  var Props := TJSONObject.Create;
  Props.AddPair('path', BuildStringParam('path', 'Optional subdirectory path to check status for'));
  Result.AddPair('properties', Props);
  var Req := TJSONArray.Create;
  Result.AddPair('required', Req);
end;

function TGitStatusTool.Execute(const AToolCallId: string;
  AParams: TJSONObject; AIsAborted: TAbortedCallback): TToolResult;
var
  SubPath, Cmd, Output: string;
  ExitCode: Integer;
  List: TContentBlockList;
begin
  SubPath := JsonGetStr(AParams, 'path', '');
  Cmd := 'git --no-pager status --porcelain';
  if SubPath <> '' then
    Cmd := Cmd + ' -- ' + EscapeShellPath(SubPath);

  RunCommand(Cmd, FWorkingDir, 15000, AIsAborted, Output, ExitCode);

  if ExitCode <> 0 then
    Exit(TToolResult.CreateError('git status failed (exit code ' + IntToStr(ExitCode) + '): ' + Output));

  List := TContentBlockList.Create;
  List.Add(TTextContent.Create(Output));
  Result := TToolResult.Create(List, False);
end;

// --- TGitDiffTool ---

constructor TGitDiffTool.Create(const AWorkingDir: string);
begin
  inherited Create(AWorkingDir);
end;

function TGitDiffTool.GetName: string;
begin
  Result := 'git_diff';
end;

function TGitDiffTool.GetLabel: string;
begin
  Result := 'Git Diff';
end;

function TGitDiffTool.GetDescription: string;
begin
  Result := 'Show changes between commits, commit and working tree, etc. Displays file diffs.';
end;

function TGitDiffTool.GetParameterSchema: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  var Props := TJSONObject.Create;
  Props.AddPair('path', BuildStringParam('path', 'File or directory path to diff'));
  Props.AddPair('staged', BuildBooleanParam('staged', 'If true, show staged changes (--cached)'));
  Result.AddPair('properties', Props);
  var Req := TJSONArray.Create;
  Req.Add('path');
  Result.AddPair('required', Req);
end;

function TGitDiffTool.Execute(const AToolCallId: string;
  AParams: TJSONObject; AIsAborted: TAbortedCallback): TToolResult;
var
  FilePath, Cmd, Output: string;
  Staged: Boolean;
  ExitCode: Integer;
  List: TContentBlockList;
begin
  FilePath := JsonGetStr(AParams, 'path', '');
  if FilePath = '' then
    Exit(TToolResult.CreateError('path parameter is required'));

  Staged := JsonGetBool(AParams, 'staged', False);
  Cmd := 'git --no-pager diff';
  if Staged then
    Cmd := Cmd + ' --cached';
  Cmd := Cmd + ' -- ' + EscapeShellPath(FilePath);

  RunCommand(Cmd, FWorkingDir, 20000, AIsAborted, Output, ExitCode);

  if ExitCode <> 0 then
    Exit(TToolResult.CreateError('git diff failed (exit code ' + IntToStr(ExitCode) + '): ' + Output));

  // Truncate if too large
  if Length(Output) > 50000 then
    Output := Copy(Output, 1, 50000) + #10'... [truncated]';

  List := TContentBlockList.Create;
  List.Add(TTextContent.Create(Output));
  Result := TToolResult.Create(List, False);
end;

// --- TGitLogTool ---

constructor TGitLogTool.Create(const AWorkingDir: string);
begin
  inherited Create(AWorkingDir);
end;

function TGitLogTool.GetName: string;
begin
  Result := 'git_log';
end;

function TGitLogTool.GetLabel: string;
begin
  Result := 'Git Log';
end;

function TGitLogTool.GetDescription: string;
begin
  Result := 'Show commit logs. Displays recent commit history for a file or the repository.';
end;

function TGitLogTool.GetParameterSchema: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  var Props := TJSONObject.Create;
  Props.AddPair('path', BuildStringParam('path', 'Optional file path to show log for'));
  Props.AddPair('count', BuildIntegerParam('count', 'Number of commits to show (default 10)'));
  Result.AddPair('properties', Props);
  var Req := TJSONArray.Create;
  Result.AddPair('required', Req);
end;

function TGitLogTool.Execute(const AToolCallId: string;
  AParams: TJSONObject; AIsAborted: TAbortedCallback): TToolResult;
var
  FilePath, Cmd, Output: string;
  Count: Integer;
  ExitCode: Integer;
  List: TContentBlockList;
begin
  FilePath := JsonGetStr(AParams, 'path', '');
  Count := JsonGetInt(AParams, 'count', 10);
  if Count < 1 then Count := 1;
  if Count > 100 then Count := 100;

  Cmd := 'git --no-pager log --oneline -n ' + IntToStr(Count);
  if FilePath <> '' then
    Cmd := Cmd + ' -- ' + EscapeShellPath(FilePath);

  RunCommand(Cmd, FWorkingDir, 15000, AIsAborted, Output, ExitCode);

  if ExitCode <> 0 then
    Exit(TToolResult.CreateError('git log failed (exit code ' + IntToStr(ExitCode) + '): ' + Output));

  List := TContentBlockList.Create;
  List.Add(TTextContent.Create(Output));
  Result := TToolResult.Create(List, False);
end;

// --- TGitBlameTool ---

constructor TGitBlameTool.Create(const AWorkingDir: string);
begin
  inherited Create(AWorkingDir);
end;

function TGitBlameTool.GetName: string;
begin
  Result := 'git_blame';
end;

function TGitBlameTool.GetLabel: string;
begin
  Result := 'Git Blame';
end;

function TGitBlameTool.GetDescription: string;
begin
  Result := 'Show what revision and author last modified each line of a file.';
end;

function TGitBlameTool.GetParameterSchema: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  var Props := TJSONObject.Create;
  Props.AddPair('path', BuildStringParam('path', 'File path to blame'));
  Props.AddPair('startLine', BuildIntegerParam('startLine', 'Optional start line number'));
  Props.AddPair('endLine', BuildIntegerParam('endLine', 'Optional end line number'));
  Result.AddPair('properties', Props);
  var Req := TJSONArray.Create;
  Req.Add('path');
  Result.AddPair('required', Req);
end;

function TGitBlameTool.Execute(const AToolCallId: string;
  AParams: TJSONObject; AIsAborted: TAbortedCallback): TToolResult;
var
  FilePath, Cmd, Output: string;
  StartLine, EndLine: Integer;
  ExitCode: Integer;
  List: TContentBlockList;
begin
  FilePath := JsonGetStr(AParams, 'path', '');
  if FilePath = '' then
    Exit(TToolResult.CreateError('path parameter is required'));

  StartLine := JsonGetInt(AParams, 'startLine', 0);
  EndLine := JsonGetInt(AParams, 'endLine', 0);

  Cmd := 'git --no-pager blame';
  if (StartLine > 0) and (EndLine >= StartLine) then
    Cmd := Cmd + ' -L ' + IntToStr(StartLine) + ',' + IntToStr(EndLine);
  Cmd := Cmd + ' -- ' + EscapeShellPath(FilePath);

  RunCommand(Cmd, FWorkingDir, 20000, AIsAborted, Output, ExitCode);

  if ExitCode <> 0 then
    Exit(TToolResult.CreateError('git blame failed (exit code ' + IntToStr(ExitCode) + '): ' + Output));

  // Truncate if too large
  if Length(Output) > 50000 then
    Output := Copy(Output, 1, 50000) + #10'... [truncated]';

  List := TContentBlockList.Create;
  List.Add(TTextContent.Create(Output));
  Result := TToolResult.Create(List, False);
end;

end.
