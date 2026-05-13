unit Tools.CommandRunner;

interface

uses
  System.SysUtils, System.Classes, System.Math, System.SyncObjs,
  Winapi.Windows,
  Core.AgentState;

/// <summary>
/// Run a command via cmd.exe with stdout/stderr capture.
/// Returns True if the process completed (even with non-zero exit code).
/// Returns False if the process failed to start or timed out.
/// </summary>
function RunCommand(const ACommand: string; const AWorkingDir: string;
  ATimeoutMs: Integer; AIsAborted: TAbortedCallback;
  out AOutput: string; out AExitCode: Integer): Boolean;

/// <summary>
/// Escape a file path for safe use in cmd.exe command lines.
/// Wraps in double quotes if the path contains any unsafe characters.
/// </summary>
function EscapeShellPath(const APath: string): string;

implementation

var
  CachedOemEncoding: TEncoding = nil;
  OemEncodingLock: TCriticalSection = nil;

function GetCachedOemEncoding: TEncoding;
begin
  if CachedOemEncoding = nil then
  begin
    if OemEncodingLock = nil then
      OemEncodingLock := TCriticalSection.Create;
    OemEncodingLock.Enter;
    try
      if CachedOemEncoding = nil then
        CachedOemEncoding := TEncoding.GetEncoding(GetOEMCP);
    finally
      OemEncodingLock.Leave;
    end;
  end;
  Result := CachedOemEncoding;
end;

function EscapeShellPath(const APath: string): string;
const
  // Only truly safe characters that need no quoting
  SafeChars = ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.', '/', '\', ':', '@', '+', '=', '~'];
var
  i: Integer;
begin
  for i := 1 to Length(APath) do
    if not CharInSet(APath[i], SafeChars) then
    begin
      // Contains unsafe chars - wrap in double quotes and escape any internal quotes
      Result := '"' + StringReplace(APath, '"', '\"', [rfReplaceAll]) + '"';
      Exit;
    end;
  Result := APath;
end;

function RunCommand(const ACommand: string; const AWorkingDir: string;
  ATimeoutMs: Integer; AIsAborted: TAbortedCallback;
  out AOutput: string; out AExitCode: Integer): Boolean;

  procedure ReadAvailablePipe(APipe: THandle; AMemo: TStringBuilder);
  var
    Buf: TArray<Byte>;
    BytesRead, BytesAvail: Cardinal;
    Bytes: TBytes;
    Str: string;
  begin
    SetLength(Buf, 4096);
    while PeekNamedPipe(APipe, nil, 0, nil, @BytesAvail, nil) and (BytesAvail > 0) do
    begin
      BytesRead := 0;
      if not ReadFile(APipe, Buf[0], Min(BytesAvail, Length(Buf)), BytesRead, nil) then
        Break;
      if BytesRead = 0 then Break;
      SetLength(Bytes, BytesRead);
      Move(Buf[0], Bytes[0], BytesRead);
      try
        // cmd.exe output is typically in the system's OEM code page (e.g. CP936 on Chinese Windows).
        // Try OEM first, then ANSI as fallback. UTF-8 is unlikely unless chcp 65001 was set.
        Str := GetCachedOemEncoding.GetString(Bytes);
      except
        try
          Str := TEncoding.ANSI.GetString(Bytes);
        except
          // Last resort: strip bytes that cannot be decoded
          Str := '';
          for var BIdx := 0 to Length(Bytes) - 1 do
            if (Bytes[BIdx] >= 32) and (Bytes[BIdx] < 128) then
              Str := Str + Chr(Bytes[BIdx])
            else if Bytes[BIdx] = 13 then
              Str := Str + #13
            else if Bytes[BIdx] = 10 then
              Str := Str + #10;
        end;
      end;
      AMemo.Append(Str);
    end;
  end;

var
  SA: TSecurityAttributes;
  SI: TStartupInfo;
  PI: TProcessInformation;
  StdOutPipeRead, StdOutPipeWrite: THandle;
  StdErrPipeRead, StdErrPipeWrite: THandle;
  CmdLine: string;
  WorkDirPtr: PChar;
  WaitResult: Cardinal;
  StartTime: Cardinal;
  TimedOut, Aborted: Boolean;
  ExitCode: Cardinal;
  OutputBuilder: TStringBuilder;
begin
  Result := False;
  AOutput := '';
  AExitCode := -1;

  FillChar(SA, SizeOf(SA), 0);
  SA.nLength := SizeOf(SA);
  SA.bInheritHandle := True;
  SA.lpSecurityDescriptor := nil;

  if not CreatePipe(StdOutPipeRead, StdOutPipeWrite, @SA, 65536) then
  begin
    AOutput := 'Failed to create stdout pipe';
    Exit;
  end;

  if not CreatePipe(StdErrPipeRead, StdErrPipeWrite, @SA, 65536) then
  begin
    CloseHandle(StdOutPipeRead);
    CloseHandle(StdOutPipeWrite);
    AOutput := 'Failed to create stderr pipe';
    Exit;
  end;

  SetHandleInformation(StdOutPipeRead, HANDLE_FLAG_INHERIT, 0);
  SetHandleInformation(StdErrPipeRead, HANDLE_FLAG_INHERIT, 0);

  FillChar(SI, SizeOf(SI), 0);
  SI.cb := SizeOf(SI);
  SI.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
  SI.wShowWindow := SW_HIDE;
  SI.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
  SI.hStdOutput := StdOutPipeWrite;
  SI.hStdError := StdErrPipeWrite;

  // Build command line: wrap in outer quotes for cmd.exe /C.
  // cmd.exe /C "..." strips the outer quotes and executes the inner string.
  // Inner quotes (e.g. for -m "commit msg") pass through correctly.
  CmdLine := 'cmd.exe /C "' + ACommand + '"';
  UniqueString(CmdLine);

  if AWorkingDir <> '' then
    WorkDirPtr := PChar(AWorkingDir)
  else
    WorkDirPtr := nil;

  PI := Default(TProcessInformation);

  if not CreateProcessW(nil, PChar(CmdLine), nil, nil, True,
    CREATE_NO_WINDOW, nil, WorkDirPtr, SI, PI) then
  begin
    CloseHandle(StdOutPipeRead);
    CloseHandle(StdOutPipeWrite);
    CloseHandle(StdErrPipeRead);
    CloseHandle(StdErrPipeWrite);
    AOutput := 'Failed to run command: ' + SysErrorMessage(GetLastError);
    Exit;
  end;

  CloseHandle(StdOutPipeWrite);
  CloseHandle(StdErrPipeWrite);

  OutputBuilder := TStringBuilder.Create;
  try
    StartTime := GetTickCount;
    TimedOut := False;
    Aborted := False;

    while True do
    begin
      ReadAvailablePipe(StdOutPipeRead, OutputBuilder);
      ReadAvailablePipe(StdErrPipeRead, OutputBuilder);

      WaitResult := WaitForSingleObject(PI.hProcess, 50);
      if WaitResult = WAIT_OBJECT_0 then
      begin
        ReadAvailablePipe(StdOutPipeRead, OutputBuilder);
        ReadAvailablePipe(StdErrPipeRead, OutputBuilder);
        Break;
      end;

      if (GetTickCount - StartTime) > Cardinal(ATimeoutMs) then
      begin
        TimedOut := True;
        Break;
      end;

      if Assigned(AIsAborted) and AIsAborted then
      begin
        Aborted := True;
        Break;
      end;
    end;

    AOutput := OutputBuilder.ToString;

    if TimedOut then
    begin
      TerminateProcess(PI.hProcess, 1);
      AOutput := AOutput + #10'[Command timed out after ' +
        IntToStr(ATimeoutMs div 1000) + ' seconds]';
      AExitCode := -1;
    end
    else if Aborted then
    begin
      TerminateProcess(PI.hProcess, 2);
      AOutput := AOutput + #10'[Command aborted by user]';
      AExitCode := -1;
    end
    else
    begin
      if GetExitCodeProcess(PI.hProcess, ExitCode) then
        AExitCode := ExitCode
      else
        AExitCode := -1;
      Result := True;
    end;
  finally
    OutputBuilder.Free;
    CloseHandle(StdOutPipeRead);
    CloseHandle(StdErrPipeRead);
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread);
  end;
end;

initialization

finalization
  CachedOemEncoding.Free;
  CachedOemEncoding := nil;
  OemEncodingLock.Free;
  OemEncodingLock := nil;

end.
