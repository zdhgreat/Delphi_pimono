unit TestGitTool;

interface

uses
  System.SysUtils, System.JSON, System.IOUtils, Winapi.Windows,
  Core.Messages, Core.AgentState, Tools.GitTool, Tools.CommandRunner,
  PiMonoTestFramework;

procedure RegisterGitToolTests;

implementation

type
  TTestGitTool = class
  private
    FWorkDir: string;
    FGitDir: string;
    procedure InitGitRepo;
  public
    procedure Setup;
    procedure TearDown;

    // Factory
    procedure Test_CreateGitTools_Returns4;

    // TGitStatusTool
    procedure Test_Status_NoPath;
    procedure Test_Status_WithSubPath;
    procedure Test_Status_NonGitRepo;

    // TGitDiffTool
    procedure Test_Diff_EmptyPath_Error;
    procedure Test_Diff_WithFile;
    procedure Test_Diff_StagedFlag;
    procedure Test_Diff_NonGitRepo;

    // TGitLogTool
    procedure Test_Log_DefaultCount;
    procedure Test_Log_WithFile;
    procedure Test_Log_CustomCount;
    procedure Test_Log_NonGitRepo;

    // TGitBlameTool
    procedure Test_Blame_EmptyPath_Error;
    procedure Test_Blame_WithFile;
    procedure Test_Blame_WithLineRange;
    procedure Test_Blame_NonGitRepo;

    // Schema
    procedure Test_StatusSchema;
    procedure Test_DiffSchema;
    procedure Test_LogSchema;
    procedure Test_BlameSchema;
  end;

{ TTestGitTool }

procedure TTestGitTool.Setup;
begin
  FWorkDir := TPath.Combine(TPath.GetTempPath,
    'PiMonoGit_' + FormatDateTime('yyyymmddhhnnsszzz', Now) + '_' + IntToStr(GetTickCount));
  TDirectory.CreateDirectory(FWorkDir);
  FGitDir := '';
end;

procedure TTestGitTool.TearDown;
begin
  try
    if TDirectory.Exists(FWorkDir) then
      TDirectory.Delete(FWorkDir, True);
  except
  end;
end;

procedure TTestGitTool.InitGitRepo;
var
  Output: string;
  ExitCode: Integer;
begin
  RunCommand('git init', FWorkDir, 10000,
    function: Boolean begin Result := False; end, Output, ExitCode);
  RunCommand('git config user.email "test@test.com"', FWorkDir, 5000,
    function: Boolean begin Result := False; end, Output, ExitCode);
  RunCommand('git config user.name "Test"', FWorkDir, 5000,
    function: Boolean begin Result := False; end, Output, ExitCode);
  FGitDir := TPath.Combine(FWorkDir, '.git');
end;

{ Factory }

procedure TTestGitTool.Test_CreateGitTools_Returns4;
var
  Tools: TArray<IAgentTool>;
begin
  Tools := CreateGitTools(FWorkDir);
  Assert(Length(Tools) = 4, 'Should return 4 tools');
  Assert(Tools[0].GetName = 'git_status', 'First should be git_status');
  Assert(Tools[1].GetName = 'git_diff', 'Second should be git_diff');
  Assert(Tools[2].GetName = 'git_log', 'Third should be git_log');
  Assert(Tools[3].GetName = 'git_blame', 'Fourth should be git_blame');
end;

{ Status }

procedure TTestGitTool.Test_Status_NoPath;
var
  Tools: TArray<IAgentTool>;
  Params: TJSONObject;
  R: TToolResult;
begin
  InitGitRepo;
  Tools := CreateGitTools(FWorkDir);
  Params := TJSONObject.Create;
  try
    R := Tools[0].Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'Status on valid repo should succeed');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestGitTool.Test_Status_WithSubPath;
var
  Tools: TArray<IAgentTool>;
  Params: TJSONObject;
  R: TToolResult;
  SubDir: string;
begin
  InitGitRepo;
  SubDir := TPath.Combine(FWorkDir, 'src');
  TDirectory.CreateDirectory(SubDir);

  Tools := CreateGitTools(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'src');
    R := Tools[0].Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      // Status on subdirectory should work
      Assert(not R.IsError, 'Status on subdir should succeed');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestGitTool.Test_Status_NonGitRepo;
var
  Tools: TArray<IAgentTool>;
  Params: TJSONObject;
  R: TToolResult;
  EmptyDir: string;
begin
  EmptyDir := TPath.Combine(FWorkDir, 'nogit');
  TDirectory.CreateDirectory(EmptyDir);

  Tools := CreateGitTools(EmptyDir);
  Params := TJSONObject.Create;
  try
    R := Tools[0].Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      // Should return error since no git repo
      Assert(R.IsError, 'Status on non-git dir should error');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

{ Diff }

procedure TTestGitTool.Test_Diff_EmptyPath_Error;
var
  Tools: TArray<IAgentTool>;
  Params: TJSONObject;
  R: TToolResult;
begin
  Tools := CreateGitTools(FWorkDir);
  Params := TJSONObject.Create;
  try
    R := Tools[1].Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(R.IsError, 'Diff without path should error');
      Assert(Pos('path', (R.Content[0] as TTextContent).Text) > 0, 'Should mention path');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestGitTool.Test_Diff_WithFile;
var
  Tools: TArray<IAgentTool>;
  Params: TJSONObject;
  R: TToolResult;
begin
  InitGitRepo;
  // Create and commit a file, then modify it
  TFile.WriteAllText(TPath.Combine(FWorkDir, 'test.txt'), 'original');
  var Output: string; var ExitCode: Integer;
  RunCommand('git add .', FWorkDir, 5000,
    function: Boolean begin Result := False; end, Output, ExitCode);
  RunCommand('git commit -m "init"', FWorkDir, 5000,
    function: Boolean begin Result := False; end, Output, ExitCode);
  TFile.WriteAllText(TPath.Combine(FWorkDir, 'test.txt'), 'modified');

  Tools := CreateGitTools(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'test.txt');
    R := Tools[1].Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'Diff on modified file should succeed');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestGitTool.Test_Diff_StagedFlag;
var
  Tools: TArray<IAgentTool>;
  Params: TJSONObject;
  R: TToolResult;
begin
  InitGitRepo;
  TFile.WriteAllText(TPath.Combine(FWorkDir, 'test.txt'), 'original');
  var Output: string; var ExitCode: Integer;
  RunCommand('git add .', FWorkDir, 5000,
    function: Boolean begin Result := False; end, Output, ExitCode);
  RunCommand('git commit -m "init"', FWorkDir, 5000,
    function: Boolean begin Result := False; end, Output, ExitCode);
  TFile.WriteAllText(TPath.Combine(FWorkDir, 'test.txt'), 'staged content');
  RunCommand('git add .', FWorkDir, 5000,
    function: Boolean begin Result := False; end, Output, ExitCode);

  Tools := CreateGitTools(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'test.txt');
    Params.AddPair('staged', TJSONBool.Create(True));
    R := Tools[1].Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'Staged diff should succeed');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestGitTool.Test_Diff_NonGitRepo;
var
  Tools: TArray<IAgentTool>;
  Params: TJSONObject;
  R: TToolResult;
  EmptyDir: string;
begin
  EmptyDir := TPath.Combine(FWorkDir, 'nogit');
  TDirectory.CreateDirectory(EmptyDir);

  Tools := CreateGitTools(EmptyDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'test.txt');
    R := Tools[1].Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(R.IsError, 'Diff on non-git dir should error');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

{ Log }

procedure TTestGitTool.Test_Log_DefaultCount;
var
  Tools: TArray<IAgentTool>;
  Params: TJSONObject;
  R: TToolResult;
begin
  InitGitRepo;
  // Create a commit
  TFile.WriteAllText(TPath.Combine(FWorkDir, 'test.txt'), 'content');
  var Output: string; var ExitCode: Integer;
  RunCommand('git add .', FWorkDir, 5000,
    function: Boolean begin Result := False; end, Output, ExitCode);
  RunCommand('git commit -m "first commit"', FWorkDir, 5000,
    function: Boolean begin Result := False; end, Output, ExitCode);

  Tools := CreateGitTools(FWorkDir);
  Params := TJSONObject.Create;
  try
    R := Tools[2].Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'Log should succeed');
      var Text := (R.Content[0] as TTextContent).Text;
      Assert(Pos('first commit', Text) > 0, 'Should contain commit message');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestGitTool.Test_Log_WithFile;
var
  Tools: TArray<IAgentTool>;
  Params: TJSONObject;
  R: TToolResult;
begin
  InitGitRepo;
  TFile.WriteAllText(TPath.Combine(FWorkDir, 'test.txt'), 'content');
  var Output: string; var ExitCode: Integer;
  RunCommand('git add .', FWorkDir, 5000,
    function: Boolean begin Result := False; end, Output, ExitCode);
  RunCommand('git commit -m "add test"', FWorkDir, 5000,
    function: Boolean begin Result := False; end, Output, ExitCode);

  Tools := CreateGitTools(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'test.txt');
    R := Tools[2].Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'Log with file should succeed');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestGitTool.Test_Log_CustomCount;
var
  Tools: TArray<IAgentTool>;
  Params: TJSONObject;
  R: TToolResult;
  i: Integer;
begin
  InitGitRepo;
  // Create 5 commits
  for i := 1 to 5 do
  begin
    TFile.WriteAllText(TPath.Combine(FWorkDir, 'file' + IntToStr(i) + '.txt'), 'c' + IntToStr(i));
    var Output: string; var ExitCode: Integer;
    RunCommand('git add .', FWorkDir, 5000,
      function: Boolean begin Result := False; end, Output, ExitCode);
    RunCommand('git commit -m "commit ' + IntToStr(i) + '"', FWorkDir, 5000,
      function: Boolean begin Result := False; end, Output, ExitCode);
  end;

  Tools := CreateGitTools(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('count', TJSONNumber.Create(3));
    R := Tools[2].Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'Log with count should succeed');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestGitTool.Test_Log_NonGitRepo;
var
  Tools: TArray<IAgentTool>;
  Params: TJSONObject;
  R: TToolResult;
  EmptyDir: string;
begin
  EmptyDir := TPath.Combine(FWorkDir, 'nogit');
  TDirectory.CreateDirectory(EmptyDir);

  Tools := CreateGitTools(EmptyDir);
  Params := TJSONObject.Create;
  try
    R := Tools[2].Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(R.IsError, 'Log on non-git dir should error');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

{ Blame }

procedure TTestGitTool.Test_Blame_EmptyPath_Error;
var
  Tools: TArray<IAgentTool>;
  Params: TJSONObject;
  R: TToolResult;
begin
  Tools := CreateGitTools(FWorkDir);
  Params := TJSONObject.Create;
  try
    R := Tools[3].Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(R.IsError, 'Blame without path should error');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestGitTool.Test_Blame_WithFile;
var
  Tools: TArray<IAgentTool>;
  Params: TJSONObject;
  R: TToolResult;
begin
  InitGitRepo;
  TFile.WriteAllText(TPath.Combine(FWorkDir, 'test.txt'), 'line1'#10'line2'#10'line3');
  var Output: string; var ExitCode: Integer;
  RunCommand('git add .', FWorkDir, 5000,
    function: Boolean begin Result := False; end, Output, ExitCode);
  RunCommand('git commit -m "init"', FWorkDir, 5000,
    function: Boolean begin Result := False; end, Output, ExitCode);

  Tools := CreateGitTools(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'test.txt');
    R := Tools[3].Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'Blame on committed file should succeed');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestGitTool.Test_Blame_WithLineRange;
var
  Tools: TArray<IAgentTool>;
  Params: TJSONObject;
  R: TToolResult;
begin
  InitGitRepo;
  TFile.WriteAllText(TPath.Combine(FWorkDir, 'test.txt'), 'line1'#10'line2'#10'line3'#10'line4'#10'line5');
  var Output: string; var ExitCode: Integer;
  RunCommand('git add .', FWorkDir, 5000,
    function: Boolean begin Result := False; end, Output, ExitCode);
  RunCommand('git commit -m "init"', FWorkDir, 5000,
    function: Boolean begin Result := False; end, Output, ExitCode);

  Tools := CreateGitTools(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'test.txt');
    Params.AddPair('startLine', TJSONNumber.Create(2));
    Params.AddPair('endLine', TJSONNumber.Create(4));
    R := Tools[3].Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'Blame with line range should succeed');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestGitTool.Test_Blame_NonGitRepo;
var
  Tools: TArray<IAgentTool>;
  Params: TJSONObject;
  R: TToolResult;
  EmptyDir: string;
begin
  EmptyDir := TPath.Combine(FWorkDir, 'nogit');
  TDirectory.CreateDirectory(EmptyDir);

  Tools := CreateGitTools(EmptyDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'test.txt');
    R := Tools[3].Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(R.IsError, 'Blame on non-git dir should error');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

{ Schemas }

procedure TTestGitTool.Test_StatusSchema;
var
  Tools: TArray<IAgentTool>;
  Schema: TJSONObject;
begin
  Tools := CreateGitTools(FWorkDir);
  Schema := Tools[0].GetParameterSchema;
  try
    Assert(Schema <> nil, 'Schema should not be nil');
    Assert(Pos('properties', Schema.ToJSON) > 0, 'Schema should have properties');
  finally
    Schema.Free;
  end;
end;

procedure TTestGitTool.Test_DiffSchema;
var
  Tools: TArray<IAgentTool>;
  Schema: TJSONObject;
begin
  Tools := CreateGitTools(FWorkDir);
  Schema := Tools[1].GetParameterSchema;
  try
    Assert(Schema <> nil, 'Schema should not be nil');
    var Json := Schema.ToJSON;
    Assert(Pos('path', Json) > 0, 'Schema should have path param');
    Assert(Pos('staged', Json) > 0, 'Schema should have staged param');
  finally
    Schema.Free;
  end;
end;

procedure TTestGitTool.Test_LogSchema;
var
  Tools: TArray<IAgentTool>;
  Schema: TJSONObject;
begin
  Tools := CreateGitTools(FWorkDir);
  Schema := Tools[2].GetParameterSchema;
  try
    Assert(Schema <> nil, 'Schema should not be nil');
    var Json := Schema.ToJSON;
    Assert(Pos('path', Json) > 0, 'Schema should have path param');
    Assert(Pos('count', Json) > 0, 'Schema should have count param');
  finally
    Schema.Free;
  end;
end;

procedure TTestGitTool.Test_BlameSchema;
var
  Tools: TArray<IAgentTool>;
  Schema: TJSONObject;
begin
  Tools := CreateGitTools(FWorkDir);
  Schema := Tools[3].GetParameterSchema;
  try
    Assert(Schema <> nil, 'Schema should not be nil');
    var Json := Schema.ToJSON;
    Assert(Pos('path', Json) > 0, 'Schema should have path param');
    Assert(Pos('startLine', Json) > 0, 'Schema should have startLine param');
    Assert(Pos('endLine', Json) > 0, 'Schema should have endLine param');
  finally
    Schema.Free;
  end;
end;

{ Registration }

procedure RegisterGitToolTests;
var
  T: TTestGitTool;
begin
  T := TTestGitTool.Create;
  try
    GRunner.RunTest('Git: CreateGitTools returns 4', T.Test_CreateGitTools_Returns4, T.Setup, T.TearDown);
    GRunner.RunTest('Git: Status no path', T.Test_Status_NoPath, T.Setup, T.TearDown);
    GRunner.RunTest('Git: Status with subpath', T.Test_Status_WithSubPath, T.Setup, T.TearDown);
    GRunner.RunTest('Git: Status non-git repo', T.Test_Status_NonGitRepo, T.Setup, T.TearDown);
    GRunner.RunTest('Git: Diff empty path error', T.Test_Diff_EmptyPath_Error, T.Setup, T.TearDown);
    GRunner.RunTest('Git: Diff with file', T.Test_Diff_WithFile, T.Setup, T.TearDown);
    GRunner.RunTest('Git: Diff staged flag', T.Test_Diff_StagedFlag, T.Setup, T.TearDown);
    GRunner.RunTest('Git: Diff non-git repo', T.Test_Diff_NonGitRepo, T.Setup, T.TearDown);
    GRunner.RunTest('Git: Log default count', T.Test_Log_DefaultCount, T.Setup, T.TearDown);
    GRunner.RunTest('Git: Log with file', T.Test_Log_WithFile, T.Setup, T.TearDown);
    GRunner.RunTest('Git: Log custom count', T.Test_Log_CustomCount, T.Setup, T.TearDown);
    GRunner.RunTest('Git: Log non-git repo', T.Test_Log_NonGitRepo, T.Setup, T.TearDown);
    GRunner.RunTest('Git: Blame empty path error', T.Test_Blame_EmptyPath_Error, T.Setup, T.TearDown);
    GRunner.RunTest('Git: Blame with file', T.Test_Blame_WithFile, T.Setup, T.TearDown);
    GRunner.RunTest('Git: Blame with line range', T.Test_Blame_WithLineRange, T.Setup, T.TearDown);
    GRunner.RunTest('Git: Blame non-git repo', T.Test_Blame_NonGitRepo, T.Setup, T.TearDown);
    GRunner.RunTest('Git: Status schema', T.Test_StatusSchema, T.Setup, T.TearDown);
    GRunner.RunTest('Git: Diff schema', T.Test_DiffSchema, T.Setup, T.TearDown);
    GRunner.RunTest('Git: Log schema', T.Test_LogSchema, T.Setup, T.TearDown);
    GRunner.RunTest('Git: Blame schema', T.Test_BlameSchema, T.Setup, T.TearDown);
  finally
    T.Free;
  end;
end;

end.
