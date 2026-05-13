unit TestAppMain;

interface

uses
  System.SysUtils, System.IOUtils, Winapi.Windows,
  Settings.Config,
  PiMonoTestFramework;

procedure RegisterAppMainTests;

implementation

uses
  App.Main;

type
  TTestAppMain = class
  private
    FTestDir: string;
  public
    procedure Setup;
    procedure TearDown;

    // LoadProjectContext
    procedure Test_LoadProjectContext_AGENTS;
    procedure Test_LoadProjectContext_CLAUDE;
    procedure Test_LoadProjectContext_PiContext;
    procedure Test_LoadProjectContext_MultipleFiles;
    procedure Test_LoadProjectContext_NoFiles;
    procedure Test_LoadProjectContext_EmptyDir;

    // DetectGitBranch
    procedure Test_DetectGitBranch_Branch;
    procedure Test_DetectGitBranch_Detached;
    procedure Test_DetectGitBranch_NoGitDir;
    procedure Test_DetectGitBranch_EmptyHead;

    // LoadSkillFile
    procedure Test_LoadSkillFile_NotFound;
  end;

{ TTestAppMain }

procedure TTestAppMain.Setup;
begin
  FTestDir := TPath.Combine(TPath.GetTempPath,
    'PiMonoAppMain_' + FormatDateTime('yyyymmddhhnnsszzz', Now) + '_' + IntToStr(GetTickCount));
  TDirectory.CreateDirectory(FTestDir);
end;

procedure TTestAppMain.TearDown;
begin
  try
    if TDirectory.Exists(FTestDir) then
      TDirectory.Delete(FTestDir, True);
  except
  end;
end;

{ LoadProjectContext }

procedure TTestAppMain.Test_LoadProjectContext_AGENTS;
var
  Result_: string;
begin
  TFile.WriteAllText(TPath.Combine(FTestDir, 'AGENTS.md'), '# Agent Instructions');
  Result_ := LoadProjectContext(FTestDir);
  Assert(Pos('Agent Instructions', Result_) > 0, 'Should contain AGENTS.md content');
  Assert(Pos('AGENTS.md', Result_) > 0, 'Should contain file name separator');
end;

procedure TTestAppMain.Test_LoadProjectContext_CLAUDE;
var
  Result_: string;
begin
  TFile.WriteAllText(TPath.Combine(FTestDir, 'CLAUDE.md'), '# Claude Rules');
  Result_ := LoadProjectContext(FTestDir);
  Assert(Pos('Claude Rules', Result_) > 0, 'Should contain CLAUDE.md content');
end;

procedure TTestAppMain.Test_LoadProjectContext_PiContext;
var
  PiDir: string;
  Result_: string;
begin
  PiDir := TPath.Combine(FTestDir, '.pi');
  TDirectory.CreateDirectory(PiDir);
  TFile.WriteAllText(TPath.Combine(PiDir, 'context.md'), 'Pi context info');
  Result_ := LoadProjectContext(FTestDir);
  Assert(Pos('Pi context info', Result_) > 0, 'Should contain .pi/context.md content');
end;

procedure TTestAppMain.Test_LoadProjectContext_MultipleFiles;
var
  PiDir: string;
  Result_: string;
begin
  TFile.WriteAllText(TPath.Combine(FTestDir, 'AGENTS.md'), 'Agent content');
  TFile.WriteAllText(TPath.Combine(FTestDir, 'CLAUDE.md'), 'Claude content');
  PiDir := TPath.Combine(FTestDir, '.pi');
  TDirectory.CreateDirectory(PiDir);
  TFile.WriteAllText(TPath.Combine(PiDir, 'instructions.md'), 'Pi instructions');

  Result_ := LoadProjectContext(FTestDir);
  Assert(Pos('Agent content', Result_) > 0, 'Should contain AGENTS.md');
  Assert(Pos('Claude content', Result_) > 0, 'Should contain CLAUDE.md');
  Assert(Pos('Pi instructions', Result_) > 0, 'Should contain .pi/instructions.md');
end;

procedure TTestAppMain.Test_LoadProjectContext_NoFiles;
var
  Result_: string;
begin
  Result_ := LoadProjectContext(FTestDir);
  Assert(Result_ = '', 'No context files should return empty');
end;

procedure TTestAppMain.Test_LoadProjectContext_EmptyDir;
var
  EmptyDir: string;
  Result_: string;
begin
  EmptyDir := TPath.Combine(FTestDir, 'empty');
  TDirectory.CreateDirectory(EmptyDir);
  Result_ := LoadProjectContext(EmptyDir);
  Assert(Result_ = '', 'Empty dir should return empty');
end;

{ DetectGitBranch }

procedure TTestAppMain.Test_DetectGitBranch_Branch;
var
  GitDir: string;
  Result_: string;
begin
  GitDir := TPath.Combine(FTestDir, '.git');
  TDirectory.CreateDirectory(GitDir);
  TFile.WriteAllText(TPath.Combine(GitDir, 'HEAD'), 'ref: refs/heads/main');

  Result_ := DetectGitBranch(FTestDir);
  Assert(Result_ = 'main', 'Should detect main branch, got: ' + Result_);
end;

procedure TTestAppMain.Test_DetectGitBranch_Detached;
var
  GitDir: string;
  Result_: string;
begin
  GitDir := TPath.Combine(FTestDir, '.git');
  TDirectory.CreateDirectory(GitDir);
  TFile.WriteAllText(TPath.Combine(GitDir, 'HEAD'), 'a1b2c3d4e5f6789012345678901234567890abcd');

  Result_ := DetectGitBranch(FTestDir);
  Assert(Result_ = 'a1b2c3d', 'Should return short hash for detached HEAD, got: ' + Result_);
end;

procedure TTestAppMain.Test_DetectGitBranch_NoGitDir;
var
  Result_: string;
begin
  Result_ := DetectGitBranch(FTestDir);
  Assert(Result_ = '', 'No .git dir should return empty');
end;

procedure TTestAppMain.Test_DetectGitBranch_EmptyHead;
var
  GitDir: string;
  Result_: string;
begin
  GitDir := TPath.Combine(FTestDir, '.git');
  TDirectory.CreateDirectory(GitDir);
  TFile.WriteAllText(TPath.Combine(GitDir, 'HEAD'), '');

  Result_ := DetectGitBranch(FTestDir);
  Assert(Result_ = '', 'Empty HEAD should return empty');
end;

{ LoadSkillFile }

procedure TTestAppMain.Test_LoadSkillFile_NotFound;
var
  Result_: string;
begin
  Result_ := LoadSkillFile('nonexistent_skill_xyz_12345');
  Assert(Result_ = '', 'Non-existent skill should return empty');
end;

{ Registration }

procedure RegisterAppMainTests;
var
  T: TTestAppMain;
begin
  T := TTestAppMain.Create;
  try
    GRunner.RunTest('AppMain: LoadProjectContext AGENTS.md', T.Test_LoadProjectContext_AGENTS, T.Setup, T.TearDown);
    GRunner.RunTest('AppMain: LoadProjectContext CLAUDE.md', T.Test_LoadProjectContext_CLAUDE, T.Setup, T.TearDown);
    GRunner.RunTest('AppMain: LoadProjectContext .pi/context.md', T.Test_LoadProjectContext_PiContext, T.Setup, T.TearDown);
    GRunner.RunTest('AppMain: LoadProjectContext multiple files', T.Test_LoadProjectContext_MultipleFiles, T.Setup, T.TearDown);
    GRunner.RunTest('AppMain: LoadProjectContext no files', T.Test_LoadProjectContext_NoFiles, T.Setup, T.TearDown);
    GRunner.RunTest('AppMain: LoadProjectContext empty dir', T.Test_LoadProjectContext_EmptyDir, T.Setup, T.TearDown);
    GRunner.RunTest('AppMain: DetectGitBranch branch', T.Test_DetectGitBranch_Branch, T.Setup, T.TearDown);
    GRunner.RunTest('AppMain: DetectGitBranch detached', T.Test_DetectGitBranch_Detached, T.Setup, T.TearDown);
    GRunner.RunTest('AppMain: DetectGitBranch no .git', T.Test_DetectGitBranch_NoGitDir, T.Setup, T.TearDown);
    GRunner.RunTest('AppMain: DetectGitBranch empty HEAD', T.Test_DetectGitBranch_EmptyHead, T.Setup, T.TearDown);
    GRunner.RunTest('AppMain: LoadSkillFile not found', T.Test_LoadSkillFile_NotFound, T.Setup, T.TearDown);
  finally
    T.Free;
  end;
end;

end.
