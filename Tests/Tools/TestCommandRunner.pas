unit TestCommandRunner;

interface

uses
  System.SysUtils,
  Tools.CommandRunner, Core.AgentState,
  PiMonoTestFramework;

procedure RegisterCommandRunnerTests;

implementation

type
  TTestCommandRunner = class
  public
    // EscapeShellPath
    procedure Test_EscapeSafePath;
    procedure Test_EscapePathWithSpaces;
    procedure Test_EscapePathWithParens;
    procedure Test_EscapePathWithAmpersand;
    procedure Test_EscapeEmptyString;
    procedure Test_EscapePathAlreadyQuoted;
    procedure Test_EscapePathWithHash;
    procedure Test_EscapeNormalFilePath;

    // RunCommand
    procedure Test_RunCommand_Echo;
    procedure Test_RunCommand_ExitCode;
    procedure Test_RunCommand_Stderr;
    procedure Test_RunCommand_NonExistent;
    procedure Test_RunCommand_WorkingDir;
    procedure Test_RunCommand_Abort;
    procedure Test_RunCommand_Timeout;
  end;

{ TTestCommandRunner }

{ EscapeShellPath }

procedure TTestCommandRunner.Test_EscapeSafePath;
begin
  var R := EscapeShellPath('C:\Users\test\file.txt');
  Assert(R = 'C:\Users\test\file.txt', 'Safe path should not be quoted');
end;

procedure TTestCommandRunner.Test_EscapePathWithSpaces;
begin
  var R := EscapeShellPath('C:\Program Files\app\test.exe');
  Assert(R[1] = '"', 'Path with spaces should be quoted');
  Assert(R.EndsWith('"'), 'Path with spaces should end with quote');
end;

procedure TTestCommandRunner.Test_EscapePathWithParens;
begin
  var R := EscapeShellPath('C:\Program Files (x86)\app\test.exe');
  Assert(R[1] = '"', 'Path with parens should be quoted');
end;

procedure TTestCommandRunner.Test_EscapePathWithAmpersand;
begin
  var R := EscapeShellPath('C:\test&run\file.txt');
  Assert(R[1] = '"', 'Path with ampersand should be quoted');
end;

procedure TTestCommandRunner.Test_EscapeEmptyString;
begin
  var R := EscapeShellPath('');
  Assert(R = '', 'Empty string should return empty');
end;

procedure TTestCommandRunner.Test_EscapePathAlreadyQuoted;
begin
  var R := EscapeShellPath('"C:\test\file.txt"');
  // Internal quotes should be escaped and outer quotes added
  Assert(Pos('\"', R) > 0, 'Internal quotes should be escaped');
end;

procedure TTestCommandRunner.Test_EscapePathWithHash;
begin
  var R := EscapeShellPath('C:\test#dir\file.txt');
  Assert(R[1] = '"', 'Path with hash should be quoted');
end;

procedure TTestCommandRunner.Test_EscapeNormalFilePath;
begin
  var R := EscapeShellPath('output.txt');
  Assert(R = 'output.txt', 'Simple filename should not be quoted');
end;

{ RunCommand }

procedure TTestCommandRunner.Test_RunCommand_Echo;
var
  Output: string;
  ExitCode: Integer;
  Ok: Boolean;
begin
  Ok := RunCommand('echo hello world', '', 5000,
    function: Boolean begin Result := False; end, Output, ExitCode);
  Assert(Ok, 'Echo should succeed');
  Assert(ExitCode = 0, 'Exit code should be 0');
  Assert(Pos('hello world', Output) > 0, 'Output should contain text');
end;

procedure TTestCommandRunner.Test_RunCommand_ExitCode;
var
  Output: string;
  ExitCode: Integer;
  Ok: Boolean;
begin
  Ok := RunCommand('exit /b 42', '', 5000,
    function: Boolean begin Result := False; end, Output, ExitCode);
  Assert(Ok, 'Should complete');
  Assert(ExitCode = 42, 'Exit code should be 42');
end;

procedure TTestCommandRunner.Test_RunCommand_Stderr;
var
  Output: string;
  ExitCode: Integer;
  Ok: Boolean;
begin
  // Write to stderr
  Ok := RunCommand('echo error 1>&2', '', 5000,
    function: Boolean begin Result := False; end, Output, ExitCode);
  Assert(Ok, 'Should complete');
  Assert(Pos('error', Output) > 0, 'Stderr should be captured');
end;

procedure TTestCommandRunner.Test_RunCommand_NonExistent;
var
  Output: string;
  ExitCode: Integer;
  Ok: Boolean;
begin
  Ok := RunCommand('nonexistent_command_xyz_12345', '', 5000,
    function: Boolean begin Result := False; end, Output, ExitCode);
  // Should fail but not crash
  Assert(not Ok or (ExitCode <> 0), 'Non-existent command should fail');
end;

procedure TTestCommandRunner.Test_RunCommand_WorkingDir;
var
  Output: string;
  ExitCode: Integer;
  Ok: Boolean;
  TmpDir: string;
begin
  TmpDir := System.SysUtils.GetEnvironmentVariable('TEMP');
  if TmpDir = '' then TmpDir := 'C:\Temp';
  Ok := RunCommand('cd', TmpDir, 5000,
    function: Boolean begin Result := False; end, Output, ExitCode);
  Assert(Ok, 'Should complete');
  // Output should contain the working directory
  Assert(Pos(TmpDir, Output) > 0, 'Working dir should match, got: ' + Output);
end;

procedure TTestCommandRunner.Test_RunCommand_Abort;
var
  Output: string;
  ExitCode: Integer;
  PollCount: Integer;
begin
  PollCount := 0;
  // Abort after a few polls by returning True from callback
  RunCommand('ping -n 10 127.0.0.1', '', 15000,
    function: Boolean
    begin
      Inc(PollCount);
      Result := PollCount > 3; // Abort after 3 polls
    end, Output, ExitCode);
  Assert(PollCount > 0, 'Should have polled at least once before abort');
end;

procedure TTestCommandRunner.Test_RunCommand_Timeout;
var
  Output: string;
  ExitCode: Integer;
  Ok: Boolean;
begin
  // Very short timeout with a long command
  Ok := RunCommand('ping -n 30 127.0.0.1', '', 100,
    function: Boolean begin Result := False; end, Output, ExitCode);
  Assert(not Ok, 'Should timeout');
  Assert(ExitCode = -1, 'Exit code should be -1 on timeout');
end;

{ Registration }

procedure RegisterCommandRunnerTests;
var
  T: TTestCommandRunner;
begin
  T := TTestCommandRunner.Create;
  try
    GRunner.RunTest('CmdRunner: Escape safe path', T.Test_EscapeSafePath);
    GRunner.RunTest('CmdRunner: Escape path with spaces', T.Test_EscapePathWithSpaces);
    GRunner.RunTest('CmdRunner: Escape path with parens', T.Test_EscapePathWithParens);
    GRunner.RunTest('CmdRunner: Escape path with ampersand', T.Test_EscapePathWithAmpersand);
    GRunner.RunTest('CmdRunner: Escape empty string', T.Test_EscapeEmptyString);
    GRunner.RunTest('CmdRunner: Escape path already quoted', T.Test_EscapePathAlreadyQuoted);
    GRunner.RunTest('CmdRunner: Escape path with hash', T.Test_EscapePathWithHash);
    GRunner.RunTest('CmdRunner: Escape normal filepath', T.Test_EscapeNormalFilePath);
    GRunner.RunTest('CmdRunner: Echo command', T.Test_RunCommand_Echo);
    GRunner.RunTest('CmdRunner: Exit code', T.Test_RunCommand_ExitCode);
    GRunner.RunTest('CmdRunner: Stderr capture', T.Test_RunCommand_Stderr);
    GRunner.RunTest('CmdRunner: Non-existent command', T.Test_RunCommand_NonExistent);
    GRunner.RunTest('CmdRunner: Working directory', T.Test_RunCommand_WorkingDir);
    GRunner.RunTest('CmdRunner: Abort', T.Test_RunCommand_Abort);
    GRunner.RunTest('CmdRunner: Timeout', T.Test_RunCommand_Timeout);
  finally
    T.Free;
  end;
end;

end.
