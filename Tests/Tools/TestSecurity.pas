unit TestSecurity;

interface

uses
  System.SysUtils, System.JSON, System.IOUtils, Winapi.Windows,
  Tools.ITool, Tools.BashTool, Tools.FileTools, Core.AgentState, Core.Messages,
  PiMonoTestFramework;

procedure RegisterSecurityTests;

implementation

type
  TSecurityTests = class
  private
    FWorkDir: string;
  public
    procedure Setup;
    procedure TearDown;

    // Path security tests
    procedure Test_ReadNormalFile_Allowed;
    procedure Test_ReadNonExistentFile_Error;
    procedure Test_ReadParentTraversal_Blocked;
    procedure Test_ReadAbsoluteOutsideWorkDir_Blocked;
    procedure Test_WriteOutsideWorkDir_Blocked;
    procedure Test_EditOutsideWorkDir_Blocked;
    procedure Test_SubDirAllowed;
    procedure Test_DifferentDrive_Blocked;

    // Bash security tests
    procedure Test_BlockedFormat;
    procedure Test_BlockedFormatUpperCase;
    procedure Test_BlockedDelS;
    procedure Test_BlockedShutdown;
    procedure Test_BlockedPowerShell;
    procedure Test_BlockedNetUser;
    procedure Test_BlockedReg;
    procedure Test_BlockedTaskkill;
    procedure Test_BlockedCmdC;
    procedure Test_BlockedCmdExe;
    procedure Test_BlockedDiskpart;
    procedure Test_AllowedEcho;
    procedure Test_AllowedDir;
    procedure Test_PrefixedSpacesBypass;
    procedure Test_CommandConcatenation;

    // Bash behavior tests
    procedure Test_EchoOutput_Captured;
    procedure Test_TypeCommand_Allowed;
    procedure Test_FindStrCommand_Allowed;
    procedure Test_CdCommand_Allowed;
    procedure Test_SetCommand_Allowed;
  end;

{ TSecurityTests }

procedure TSecurityTests.Setup;
begin
  FWorkDir := TPath.Combine(TPath.GetTempPath, 'PiMonoSec_' + FormatDateTime('yyyymmddhhnnss', Now) + '_' + IntToStr(GetTickCount));
  TDirectory.CreateDirectory(FWorkDir);
end;

procedure TSecurityTests.TearDown;
begin
  try
    if TDirectory.Exists(FWorkDir) then
      TDirectory.Delete(FWorkDir, True);
  except
  end;
end;

{ --- Path Security --- }

procedure TSecurityTests.Test_ReadNormalFile_Allowed;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
begin
  TFile.WriteAllText(TPath.Combine(FWorkDir, 'test.txt'), 'hello world');
  Tool := CreateReadTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'test.txt');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'Should not be error');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TSecurityTests.Test_ReadNonExistentFile_Error;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
begin
  Tool := CreateReadTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'nonexistent.txt');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(R.IsError, 'Should be error for non-existent file');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TSecurityTests.Test_ReadParentTraversal_Blocked;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
begin
  Tool := CreateReadTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', '..\..\..\Windows\System32\drivers\etc\hosts');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(R.IsError, 'Parent traversal should be blocked');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TSecurityTests.Test_ReadAbsoluteOutsideWorkDir_Blocked;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
begin
  Tool := CreateReadTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'C:\Windows\System32\drivers\etc\hosts');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(R.IsError, 'Absolute path outside workdir should be blocked');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TSecurityTests.Test_WriteOutsideWorkDir_Blocked;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
begin
  Tool := CreateWriteTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'C:\Windows\Temp\pimono_test.txt');
    Params.AddPair('content', 'should not be written');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(R.IsError, 'Write outside workdir should be blocked');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TSecurityTests.Test_EditOutsideWorkDir_Blocked;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
begin
  Tool := CreateEditTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'C:\Windows\Temp\pimono_test.txt');
    Params.AddPair('oldText', 'a');
    Params.AddPair('newText', 'b');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(R.IsError, 'Edit outside workdir should be blocked');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TSecurityTests.Test_SubDirAllowed;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
  SubDir: string;
begin
  SubDir := TPath.Combine(FWorkDir, 'subdir');
  TDirectory.CreateDirectory(SubDir);
  TFile.WriteAllText(TPath.Combine(SubDir, 'test.txt'), 'sub content');

  Tool := CreateReadTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'subdir\test.txt');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'Subdirectory file should be readable');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TSecurityTests.Test_DifferentDrive_Blocked;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
begin
  Tool := CreateReadTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('path', 'D:\something\test.txt');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      if FWorkDir.StartsWith('C:', True) then
        Assert(R.IsError, 'Different drive should be blocked');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

{ --- Bash Security --- }

procedure TSecurityTests.Test_BlockedFormat;
var Tool: IAgentTool; Params: TJSONObject; R: TToolResult;
begin
  Tool := CreateBashTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('command', 'format C:');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try Assert(R.IsError, 'format should be blocked'); finally R.ReleaseContent; end;
  finally Params.Free; end;
end;

procedure TSecurityTests.Test_BlockedFormatUpperCase;
var Tool: IAgentTool; Params: TJSONObject; R: TToolResult;
begin
  Tool := CreateBashTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('command', 'FORMAT C:');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try Assert(R.IsError, 'FORMAT uppercase should be blocked'); finally R.ReleaseContent; end;
  finally Params.Free; end;
end;

procedure TSecurityTests.Test_BlockedDelS;
var Tool: IAgentTool; Params: TJSONObject; R: TToolResult;
begin
  Tool := CreateBashTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('command', 'del /s C:\*');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try Assert(R.IsError, 'del /s should be blocked'); finally R.ReleaseContent; end;
  finally Params.Free; end;
end;

procedure TSecurityTests.Test_BlockedShutdown;
var Tool: IAgentTool; Params: TJSONObject; R: TToolResult;
begin
  Tool := CreateBashTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('command', 'shutdown /s /t 0');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try Assert(R.IsError, 'shutdown should be blocked'); finally R.ReleaseContent; end;
  finally Params.Free; end;
end;

procedure TSecurityTests.Test_BlockedPowerShell;
var Tool: IAgentTool; Params: TJSONObject; R: TToolResult;
begin
  Tool := CreateBashTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('command', 'powershell -Command "Get-Process"');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try Assert(R.IsError, 'powershell should be blocked'); finally R.ReleaseContent; end;
  finally Params.Free; end;
end;

procedure TSecurityTests.Test_BlockedNetUser;
var Tool: IAgentTool; Params: TJSONObject; R: TToolResult;
begin
  Tool := CreateBashTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('command', 'net user hacker P@ss123 /add');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try Assert(R.IsError, 'net user should be blocked'); finally R.ReleaseContent; end;
  finally Params.Free; end;
end;

procedure TSecurityTests.Test_BlockedReg;
var Tool: IAgentTool; Params: TJSONObject; R: TToolResult;
begin
  Tool := CreateBashTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('command', 'reg add HKLM\SOFTWARE\Test');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try Assert(R.IsError, 'reg should be blocked'); finally R.ReleaseContent; end;
  finally Params.Free; end;
end;

procedure TSecurityTests.Test_BlockedTaskkill;
var Tool: IAgentTool; Params: TJSONObject; R: TToolResult;
begin
  Tool := CreateBashTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('command', 'taskkill /F /IM explorer.exe');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try Assert(R.IsError, 'taskkill should be blocked'); finally R.ReleaseContent; end;
  finally Params.Free; end;
end;

procedure TSecurityTests.Test_BlockedCmdC;
var Tool: IAgentTool; Params: TJSONObject; R: TToolResult;
begin
  Tool := CreateBashTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('command', 'cmd /c echo hello');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try Assert(R.IsError, 'cmd /c should be blocked'); finally R.ReleaseContent; end;
  finally Params.Free; end;
end;

procedure TSecurityTests.Test_BlockedCmdExe;
var Tool: IAgentTool; Params: TJSONObject; R: TToolResult;
begin
  Tool := CreateBashTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('command', 'cmd.exe');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try Assert(R.IsError, 'cmd.exe should be blocked'); finally R.ReleaseContent; end;
  finally Params.Free; end;
end;

procedure TSecurityTests.Test_BlockedDiskpart;
var Tool: IAgentTool; Params: TJSONObject; R: TToolResult;
begin
  Tool := CreateBashTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('command', 'diskpart');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try Assert(R.IsError, 'diskpart should be blocked'); finally R.ReleaseContent; end;
  finally Params.Free; end;
end;

procedure TSecurityTests.Test_AllowedEcho;
var Tool: IAgentTool; Params: TJSONObject; R: TToolResult;
begin
  Tool := CreateBashTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('command', 'echo hello test');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try Assert(not R.IsError, 'echo should be allowed'); finally R.ReleaseContent; end;
  finally Params.Free; end;
end;

procedure TSecurityTests.Test_AllowedDir;
var Tool: IAgentTool; Params: TJSONObject; R: TToolResult;
begin
  Tool := CreateBashTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('command', 'dir');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try Assert(not R.IsError, 'dir should be allowed'); finally R.ReleaseContent; end;
  finally Params.Free; end;
end;

procedure TSecurityTests.Test_PrefixedSpacesBypass;
var Tool: IAgentTool; Params: TJSONObject; R: TToolResult;
begin
  // SEC-B03: Pos('format', '   format c:') = 4 > 0, should be caught
  Tool := CreateBashTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('command', '   format C:');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try Assert(R.IsError, 'format with leading spaces should be blocked'); finally R.ReleaseContent; end;
  finally Params.Free; end;
end;

procedure TSecurityTests.Test_CommandConcatenation;
var Tool: IAgentTool; Params: TJSONObject; R: TToolResult;
begin
  // "echo hello && format C:" - format is substring, should be caught
  Tool := CreateBashTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('command', 'echo hello && format C:');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try Assert(R.IsError, 'concatenated format should be blocked'); finally R.ReleaseContent; end;
  finally Params.Free; end;
end;

{ --- Bash Behavior Tests --- }

procedure TSecurityTests.Test_EchoOutput_Captured;
var Tool: IAgentTool; Params: TJSONObject; R: TToolResult;
begin
  Tool := CreateBashTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('command', 'echo Hello World Test');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'echo should succeed');
      Assert(Pos('Hello World Test', (R.Content[0] as TTextContent).Text) > 0,
        'Should capture echo output');
    finally R.ReleaseContent; end;
  finally Params.Free; end;
end;

procedure TSecurityTests.Test_TypeCommand_Allowed;
var Tool: IAgentTool; Params: TJSONObject; R: TToolResult;
begin
  TFile.WriteAllText(TPath.Combine(FWorkDir, 'testfile.txt'), 'content to type');
  Tool := CreateBashTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('command', 'type testfile.txt');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'type should be allowed');
      Assert(Pos('content to type', (R.Content[0] as TTextContent).Text) > 0,
        'Should capture type output');
    finally R.ReleaseContent; end;
  finally Params.Free; end;
end;

procedure TSecurityTests.Test_FindStrCommand_Allowed;
var Tool: IAgentTool; Params: TJSONObject; R: TToolResult;
begin
  TFile.WriteAllText(TPath.Combine(FWorkDir, 'search.txt'), 'line with PATTERN inside');
  Tool := CreateBashTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('command', 'findstr PATTERN search.txt');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'findstr should be allowed');
    finally R.ReleaseContent; end;
  finally Params.Free; end;
end;

procedure TSecurityTests.Test_CdCommand_Allowed;
var Tool: IAgentTool; Params: TJSONObject; R: TToolResult;
begin
  Tool := CreateBashTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('command', 'cd');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'cd should be allowed');
    finally R.ReleaseContent; end;
  finally Params.Free; end;
end;

procedure TSecurityTests.Test_SetCommand_Allowed;
var Tool: IAgentTool; Params: TJSONObject; R: TToolResult;
begin
  Tool := CreateBashTool(FWorkDir);
  Params := TJSONObject.Create;
  try
    Params.AddPair('command', 'set PIMONO_TEST=hello');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(not R.IsError, 'set should be allowed');
    finally R.ReleaseContent; end;
  finally Params.Free; end;
end;

{ Registration }

procedure RegisterSecurityTests;
var
  T: TSecurityTests;
begin
  T := TSecurityTests.Create;
  try
    // Path security
    GRunner.RunTest('SEC: Read normal file allowed', T.Test_ReadNormalFile_Allowed, T.Setup, T.TearDown);
    GRunner.RunTest('SEC: Read nonexistent file error', T.Test_ReadNonExistentFile_Error, T.Setup, T.TearDown);
    GRunner.RunTest('SEC: Read parent traversal blocked', T.Test_ReadParentTraversal_Blocked, T.Setup, T.TearDown);
    GRunner.RunTest('SEC: Read absolute outside blocked', T.Test_ReadAbsoluteOutsideWorkDir_Blocked, T.Setup, T.TearDown);
    GRunner.RunTest('SEC: Write outside blocked', T.Test_WriteOutsideWorkDir_Blocked, T.Setup, T.TearDown);
    GRunner.RunTest('SEC: Edit outside blocked', T.Test_EditOutsideWorkDir_Blocked, T.Setup, T.TearDown);
    GRunner.RunTest('SEC: Subdirectory allowed', T.Test_SubDirAllowed, T.Setup, T.TearDown);
    GRunner.RunTest('SEC: Different drive blocked', T.Test_DifferentDrive_Blocked, T.Setup, T.TearDown);
    // Bash security
    GRunner.RunTest('SEC: format blocked', T.Test_BlockedFormat, T.Setup, T.TearDown);
    GRunner.RunTest('SEC: FORMAT upper blocked', T.Test_BlockedFormatUpperCase, T.Setup, T.TearDown);
    GRunner.RunTest('SEC: del /s blocked', T.Test_BlockedDelS, T.Setup, T.TearDown);
    GRunner.RunTest('SEC: shutdown blocked', T.Test_BlockedShutdown, T.Setup, T.TearDown);
    GRunner.RunTest('SEC: powershell blocked', T.Test_BlockedPowerShell, T.Setup, T.TearDown);
    GRunner.RunTest('SEC: net user blocked', T.Test_BlockedNetUser, T.Setup, T.TearDown);
    GRunner.RunTest('SEC: reg blocked', T.Test_BlockedReg, T.Setup, T.TearDown);
    GRunner.RunTest('SEC: taskkill blocked', T.Test_BlockedTaskkill, T.Setup, T.TearDown);
    GRunner.RunTest('SEC: cmd /c blocked', T.Test_BlockedCmdC, T.Setup, T.TearDown);
    GRunner.RunTest('SEC: cmd.exe blocked', T.Test_BlockedCmdExe, T.Setup, T.TearDown);
    GRunner.RunTest('SEC: diskpart blocked', T.Test_BlockedDiskpart, T.Setup, T.TearDown);
    GRunner.RunTest('SEC: echo allowed', T.Test_AllowedEcho, T.Setup, T.TearDown);
    GRunner.RunTest('SEC: dir allowed', T.Test_AllowedDir, T.Setup, T.TearDown);
    GRunner.RunTest('SEC: leading spaces bypass test', T.Test_PrefixedSpacesBypass, T.Setup, T.TearDown);
    GRunner.RunTest('SEC: command concatenation', T.Test_CommandConcatenation, T.Setup, T.TearDown);
    // Bash behavior tests
    GRunner.RunTest('SEC: echo output captured', T.Test_EchoOutput_Captured, T.Setup, T.TearDown);
    GRunner.RunTest('SEC: type command allowed', T.Test_TypeCommand_Allowed, T.Setup, T.TearDown);
    GRunner.RunTest('SEC: findstr command allowed', T.Test_FindStrCommand_Allowed, T.Setup, T.TearDown);
    GRunner.RunTest('SEC: cd command allowed', T.Test_CdCommand_Allowed, T.Setup, T.TearDown);
    GRunner.RunTest('SEC: set command allowed', T.Test_SetCommand_Allowed, T.Setup, T.TearDown);
  finally
    T.Free;
  end;
end;

end.
