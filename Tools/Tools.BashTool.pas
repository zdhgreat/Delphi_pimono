unit Tools.BashTool;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Math,
  Core.Messages, Core.AgentState, Tools.ITool, Tools.CommandRunner,
  Utils.JsonHelper;

type
  TBashTool = class(TBaseTool)
  private
    FDefaultTimeout: Integer;  // ms
    FBlockedCommands: TArray<string>;
    function IsCommandAllowed(const ACommand: string): Boolean;
  protected
    function GetName: string; override;
    function GetLabel: string; override;
    function GetDescription: string; override;
    function GetParameterSchema: TJSONObject; override;
  public
    constructor Create(const AWorkingDir: string); override;
    function Execute(const AToolCallId: string; AParams: TJSONObject;
      AIsAborted: TAbortedCallback): TToolResult; override;

    property DefaultTimeout: Integer read FDefaultTimeout write FDefaultTimeout;
  end;

function CreateBashTool(const AWorkingDir: string;
  ATimeoutMs: Integer = 30000): IAgentTool;

implementation

const
  BASH_DEFAULT_TIMEOUT_MS = 30000;
  BASH_MAX_OUTPUT_CHARS = 51200;

{ TBashTool }

constructor TBashTool.Create(const AWorkingDir: string);
begin
  inherited Create(AWorkingDir);
  FDefaultTimeout := BASH_DEFAULT_TIMEOUT_MS;

  // Blocked commands (dangerous) - covers common variants and obfuscation attempts
  SetLength(FBlockedCommands, 36);
  FBlockedCommands[0] := 'format';
  FBlockedCommands[1] := 'del /s';
  FBlockedCommands[2] := 'rd /s';
  FBlockedCommands[3] := 'rmdir /s';
  FBlockedCommands[4] := 'shutdown';
  FBlockedCommands[5] := 'powershell';
  FBlockedCommands[6] := 'powershell.exe';
  FBlockedCommands[7] := 'pwsh';
  FBlockedCommands[8] := 'pwsh.exe';
  FBlockedCommands[9] := 'net user';
  FBlockedCommands[10] := 'net localgroup';
  FBlockedCommands[11] := 'reg ';
  FBlockedCommands[12] := 'taskkill';
  FBlockedCommands[13] := 'wmic';
  FBlockedCommands[14] := 'cipher';
  FBlockedCommands[15] := 'diskpart';
  FBlockedCommands[16] := 'fsutil';
  FBlockedCommands[17] := 'netsh';
  FBlockedCommands[18] := 'regedit';
  FBlockedCommands[19] := 'sc ';
  FBlockedCommands[20] := 'icacls';
  FBlockedCommands[21] := 'cmd /c';
  FBlockedCommands[22] := 'cmd.exe /c';
  FBlockedCommands[23] := 'cmd /k';
  FBlockedCommands[24] := 'cmd.exe /k';
  FBlockedCommands[25] := 'cmd.exe';
  FBlockedCommands[26] := 'start ';
  FBlockedCommands[27] := 'bash -c';
  FBlockedCommands[28] := 'wscript';
  FBlockedCommands[29] := 'certutil';
  FBlockedCommands[30] := 'bitsadmin';
  FBlockedCommands[31] := 'mshta';
  FBlockedCommands[32] := 'wsl';
  FBlockedCommands[33] := 'wsl.exe';
  FBlockedCommands[34] := 'cscript';
  FBlockedCommands[35] := 'takeown';
end;

function TBashTool.GetName: string;
begin
  Result := 'bash';
end;

function TBashTool.GetLabel: string;
begin
  Result := 'Execute Command';
end;

function TBashTool.GetDescription: string;
begin
  Result := 'Execute a shell command and return its output. Use for running builds, tests, and other development commands.';
end;

function TBashTool.GetParameterSchema: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  var Props := TJSONObject.Create;
  Props.AddPair('command', BuildStringParam('command', 'The shell command to execute'));
  Props.AddPair('timeout', BuildIntegerParam('timeout', 'Timeout in milliseconds (default 30000)'));
  Result.AddPair('properties', Props);
  var Req := TJSONArray.Create;
  Req.Add('command');
  Result.AddPair('required', Req);
end;

function TBashTool.IsCommandAllowed(const ACommand: string): Boolean;
var
  LowerCmd: string;
  i: Integer;
const
  DangerousExtensions: array[0..4] of string = (
    '.ps1', '.bat', '.cmd', '.vbs', '.vbe');
begin
  Result := True;
  LowerCmd := LowerCase(ACommand);

  // Normalize: remove caret escapes (^) used to obfuscate commands
  LowerCmd := StringReplace(LowerCmd, '^', '', [rfReplaceAll]);
  // Normalize: collapse multiple whitespace into single space
  while Pos('  ', LowerCmd) > 0 do
    LowerCmd := StringReplace(LowerCmd, '  ', ' ', [rfReplaceAll]);
  LowerCmd := StringReplace(LowerCmd, #9, ' ', [rfReplaceAll]);
  // Trim
  LowerCmd := Trim(LowerCmd);

  // Block environment variable expansion obfuscation patterns
  // e.g. %OS:~0,0%powershell or %COMSPEC% /c ...
  if (Pos('%', LowerCmd) > 0) then
  begin
    // Allow simple %VAR% in echo/set commands only
    var HasEnvExpansion := False;
    var P := Pos('%', LowerCmd);
    while P > 0 do
    begin
      var P2 := Pos('%', LowerCmd, P + 1);
      if P2 > P + 1 then
      begin
        // Check if it's a substring expansion like %VAR:~0,0% (obfuscation)
        var VarContent := Copy(LowerCmd, P + 1, P2 - P - 1);
        if (Pos(':~', VarContent) > 0) or (Pos(':\', VarContent) > 0) or
           (Pos(':/', VarContent) > 0) then
          HasEnvExpansion := True;
        P := Pos('%', LowerCmd, P2 + 1);
      end
      else
        P := 0;
    end;
    if HasEnvExpansion then
    begin
      Result := False;
      Exit;
    end;
  end;

  // Check blocked commands
  for i := 0 to High(FBlockedCommands) do
  begin
    if Pos(FBlockedCommands[i], LowerCmd) > 0 then
    begin
      Result := False;
      Exit;
    end;
  end;

  // Block piping to dangerous interpreters
  if (Pos('| powershell', LowerCmd) > 0) or
     (Pos('| cmd', LowerCmd) > 0) or
     (Pos('| pwsh', LowerCmd) > 0) or
     (Pos('| wsl', LowerCmd) > 0) or
     (Pos('| bash', LowerCmd) > 0) then
  begin
    Result := False;
    Exit;
  end;

  // Block redirecting to dangerous script file types
  for i := 0 to High(DangerousExtensions) do
  begin
    if Pos('>' + DangerousExtensions[i], LowerCmd) > 0 then
    begin
      Result := False;
      Exit;
    end;
  end;
end;

function TBashTool.Execute(const AToolCallId: string;
  AParams: TJSONObject; AIsAborted: TAbortedCallback): TToolResult;
var
  Command: string;
  TimeoutMs: Integer;
  Output: string;
  ExitCode: Integer;
  List: TContentBlockList;
  SB: TStringBuilder;
  MaxOutputLen: Integer;
begin
  Command := JsonGetStr(AParams, 'command', '');
  TimeoutMs := JsonGetInt(AParams, 'timeout', FDefaultTimeout);
  if TimeoutMs <= 0 then
    TimeoutMs := FDefaultTimeout;

  if Command = '' then
    Exit(TToolResult.CreateError('Command parameter is required'));

  // Security check
  if not IsCommandAllowed(Command) then
    Exit(TToolResult.CreateError('Command blocked for safety: ' + Command));

  // Execute using shared command runner
  if not RunCommand(Command, FWorkingDir, TimeoutMs, AIsAborted, Output, ExitCode) then
  begin
    List := TContentBlockList.Create;
    List.Add(TTextContent.Create(Output));
    Exit(TToolResult.Create(List, True));
  end;

  // Truncate output if needed
  MaxOutputLen := BASH_MAX_OUTPUT_CHARS;
  if Length(Output) > MaxOutputLen then
    Output := Copy(Output, 1, MaxOutputLen) + #10'... [output truncated]';

  // Format result
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('$ ' + Command);
    SB.AppendLine(Output);
    if ExitCode <> 0 then
      SB.AppendLine(Format('[Exit code: %d]', [ExitCode]));

    List := TContentBlockList.Create;
    List.Add(TTextContent.Create(SB.ToString));
    Result := TToolResult.Create(List, ExitCode <> 0);
  finally
    SB.Free;
  end;
end;

{ Factory }

function CreateBashTool(const AWorkingDir: string;
  ATimeoutMs: Integer): IAgentTool;
var
  Tool: TBashTool;
begin
  Tool := TBashTool.Create(AWorkingDir);
  Tool.DefaultTimeout := ATimeoutMs;
  Result := Tool;
end;

end.
