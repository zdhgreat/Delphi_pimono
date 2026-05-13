unit TestUtilsLogger;

interface

uses
  System.SysUtils, System.IOUtils, System.Classes, Winapi.Windows,
  Utils.Logger,
  PiMonoTestFramework;

procedure RegisterUtilsLoggerTests;

implementation

type
  TTestLogger = class
  private
    FTestDir: string;
    FLogDir: string;
  public
    procedure Setup;
    procedure TearDown;

    // Basic logging
    procedure Test_CreateLogger;
    procedure Test_InfoLog_WritesFile;
    procedure Test_WarnLog_WritesFile;
    procedure Test_ErrorLog_WritesFile;
    procedure Test_FatalLog_WritesFile;

    // Level filtering
    procedure Test_MinLevel_FiltersBelow;
    procedure Test_TraceFiltered_ByDefault;
    procedure Test_DebugFiltered_ByDefault;
    procedure Test_MinLevel_Trace_PassesAll;

    // Convenience methods
    procedure Test_TraceMethod;
    procedure Test_DebugMethod;

    // Format overload
    procedure Test_LogFormat;

    // LogException
    procedure Test_LogException_WithContext;
    procedure Test_LogException_WithoutContext;

    // File rotation
    procedure Test_Rotation_BySize;

    // Properties
    procedure Test_LogPathProperty;
    procedure Test_MinLevelProperty;
  end;

{ TTestLogger }

procedure TTestLogger.Setup;
begin
  FTestDir := TPath.Combine(TPath.GetTempPath,
    'PiMonoLog_' + FormatDateTime('yyyymmddhhnnsszzz', Now) + '_' + IntToStr(GetTickCount));
  FLogDir := TPath.Combine(FTestDir, 'logs');
  TDirectory.CreateDirectory(FLogDir);
end;

procedure TTestLogger.TearDown;
begin
  try
    if TDirectory.Exists(FTestDir) then
      TDirectory.Delete(FTestDir, True);
  except
  end;
end;

procedure TTestLogger.Test_CreateLogger;
var
  L: TLogger;
begin
  L := TLogger.Create(FLogDir);
  try
    Assert(L.LogPath = FLogDir, 'LogPath should match');
    Assert(L.MinLevel = llInfo, 'Default MinLevel should be Info');
  finally
    L.Free;
  end;
end;

procedure TTestLogger.Test_InfoLog_WritesFile;
var
  L: TLogger;
  Files: TArray<string>;
  Content: string;
begin
  L := TLogger.Create(FLogDir, llInfo);
  try
    L.Info('Test info message');
  finally
    L.Free;
  end;

  Files := TDirectory.GetFiles(FLogDir, 'PiMono_*.log');
  Assert(Length(Files) > 0, 'Log file should exist');
  Content := TFile.ReadAllText(Files[0]);
  Assert(Pos('Test info message', Content) > 0, 'Should contain message');
  Assert(Pos('INFO', Content) > 0, 'Should contain level');
end;

procedure TTestLogger.Test_WarnLog_WritesFile;
var
  L: TLogger;
  Files: TArray<string>;
  Content: string;
begin
  L := TLogger.Create(FLogDir, llInfo);
  try
    L.Warn('Test warning message');
  finally
    L.Free;
  end;

  Files := TDirectory.GetFiles(FLogDir, 'PiMono_*.log');
  Assert(Length(Files) > 0, 'Log file should exist');
  Content := TFile.ReadAllText(Files[0]);
  Assert(Pos('Test warning message', Content) > 0, 'Should contain message');
  Assert(Pos('WARN', Content) > 0, 'Should contain level');
end;

procedure TTestLogger.Test_ErrorLog_WritesFile;
var
  L: TLogger;
  Files: TArray<string>;
  Content: string;
begin
  L := TLogger.Create(FLogDir, llInfo);
  try
    L.Error('Test error message');
  finally
    L.Free;
  end;

  Files := TDirectory.GetFiles(FLogDir, 'PiMono_*.log');
  Content := TFile.ReadAllText(Files[0]);
  Assert(Pos('Test error message', Content) > 0, 'Should contain message');
  Assert(Pos('ERROR', Content) > 0, 'Should contain level');
end;

procedure TTestLogger.Test_FatalLog_WritesFile;
var
  L: TLogger;
  Files: TArray<string>;
  Content: string;
begin
  L := TLogger.Create(FLogDir, llInfo);
  try
    L.Fatal('Test fatal message');
  finally
    L.Free;
  end;

  Files := TDirectory.GetFiles(FLogDir, 'PiMono_*.log');
  Content := TFile.ReadAllText(Files[0]);
  Assert(Pos('Test fatal message', Content) > 0, 'Should contain message');
  Assert(Pos('FATAL', Content) > 0, 'Should contain level');
end;

procedure TTestLogger.Test_MinLevel_FiltersBelow;
var
  L: TLogger;
  Files: TArray<string>;
  Content: string;
begin
  L := TLogger.Create(FLogDir, llWarn);
  try
    L.Info('Should be filtered');
    L.Warn('Should appear');
  finally
    L.Free;
  end;

  Files := TDirectory.GetFiles(FLogDir, 'PiMono_*.log');
  Content := TFile.ReadAllText(Files[0]);
  Assert(Pos('Should be filtered', Content) = 0, 'Info should be filtered when MinLevel=Warn');
  Assert(Pos('Should appear', Content) > 0, 'Warn should appear');
end;

procedure TTestLogger.Test_TraceFiltered_ByDefault;
var
  L: TLogger;
  Files: TArray<string>;
  Content: string;
begin
  L := TLogger.Create(FLogDir); // default MinLevel = Info
  try
    L.Trace('Trace message');
  finally
    L.Free;
  end;

  Files := TDirectory.GetFiles(FLogDir, 'PiMono_*.log');
  if Length(Files) > 0 then
  begin
    Content := TFile.ReadAllText(Files[0]);
    Assert(Pos('Trace message', Content) = 0, 'Trace should be filtered at Info level');
  end
  else
    Assert(True, 'No log file created - trace filtered');
end;

procedure TTestLogger.Test_DebugFiltered_ByDefault;
var
  L: TLogger;
  Files: TArray<string>;
  Content: string;
begin
  L := TLogger.Create(FLogDir); // default MinLevel = Info
  try
    L.Debug('Debug message');
  finally
    L.Free;
  end;

  Files := TDirectory.GetFiles(FLogDir, 'PiMono_*.log');
  if Length(Files) > 0 then
  begin
    Content := TFile.ReadAllText(Files[0]);
    Assert(Pos('Debug message', Content) = 0, 'Debug should be filtered at Info level');
  end
  else
    Assert(True, 'No log file created - debug filtered');
end;

procedure TTestLogger.Test_MinLevel_Trace_PassesAll;
var
  L: TLogger;
  Files: TArray<string>;
  Content: string;
begin
  L := TLogger.Create(FLogDir, llTrace);
  try
    L.Trace('Trace msg');
    L.Debug('Debug msg');
    L.Info('Info msg');
    L.Warn('Warn msg');
    L.Error('Error msg');
    L.Fatal('Fatal msg');
  finally
    L.Free;
  end;

  Files := TDirectory.GetFiles(FLogDir, 'PiMono_*.log');
  Content := TFile.ReadAllText(Files[0]);
  Assert(Pos('Trace msg', Content) > 0, 'Trace should appear');
  Assert(Pos('Debug msg', Content) > 0, 'Debug should appear');
  Assert(Pos('Info msg', Content) > 0, 'Info should appear');
  Assert(Pos('Warn msg', Content) > 0, 'Warn should appear');
  Assert(Pos('Error msg', Content) > 0, 'Error should appear');
  Assert(Pos('Fatal msg', Content) > 0, 'Fatal should appear');
end;

procedure TTestLogger.Test_TraceMethod;
var
  L: TLogger;
  Files: TArray<string>;
  Content: string;
begin
  L := TLogger.Create(FLogDir, llTrace);
  try
    L.Trace('Trace test');
  finally
    L.Free;
  end;

  Files := TDirectory.GetFiles(FLogDir, 'PiMono_*.log');
  Content := TFile.ReadAllText(Files[0]);
  Assert(Pos('TRACE', Content) > 0, 'Should contain TRACE level');
end;

procedure TTestLogger.Test_DebugMethod;
var
  L: TLogger;
  Files: TArray<string>;
  Content: string;
begin
  L := TLogger.Create(FLogDir, llDebug);
  try
    L.Debug('Debug test');
  finally
    L.Free;
  end;

  Files := TDirectory.GetFiles(FLogDir, 'PiMono_*.log');
  Content := TFile.ReadAllText(Files[0]);
  Assert(Pos('DEBUG', Content) > 0, 'Should contain DEBUG level');
end;

procedure TTestLogger.Test_LogFormat;
var
  L: TLogger;
  Files: TArray<string>;
  Content: string;
begin
  L := TLogger.Create(FLogDir, llInfo);
  try
    L.Log(llInfo, 'Count: %d, Name: %s', [42, 'test']);
  finally
    L.Free;
  end;

  Files := TDirectory.GetFiles(FLogDir, 'PiMono_*.log');
  Content := TFile.ReadAllText(Files[0]);
  Assert(Pos('Count: 42', Content) > 0, 'Should contain formatted value');
  Assert(Pos('Name: test', Content) > 0, 'Should contain formatted string');
end;

procedure TTestLogger.Test_LogException_WithContext;
var
  L: TLogger;
  Files: TArray<string>;
  Content: string;
begin
  L := TLogger.Create(FLogDir, llInfo);
  try
    try
      raise Exception.Create('Test exception message');
    except
      on E: Exception do
        L.LogException(E, 'TestContext');
    end;
  finally
    L.Free;
  end;

  Files := TDirectory.GetFiles(FLogDir, 'PiMono_*.log');
  Content := TFile.ReadAllText(Files[0]);
  Assert(Pos('TestContext', Content) > 0, 'Should contain context');
  Assert(Pos('Test exception message', Content) > 0, 'Should contain exception message');
end;

procedure TTestLogger.Test_LogException_WithoutContext;
var
  L: TLogger;
  Files: TArray<string>;
  Content: string;
begin
  L := TLogger.Create(FLogDir, llInfo);
  try
    try
      raise Exception.Create('No context error');
    except
      on E: Exception do
        L.LogException(E);
    end;
  finally
    L.Free;
  end;

  Files := TDirectory.GetFiles(FLogDir, 'PiMono_*.log');
  Content := TFile.ReadAllText(Files[0]);
  Assert(Pos('No context error', Content) > 0, 'Should contain exception message');
  Assert(Pos('ERROR', Content) > 0, 'Should be at ERROR level');
end;

procedure TTestLogger.Test_Rotation_BySize;
var
  L: TLogger;
  Files: TArray<string>;
  i: Integer;
begin
  // Create logger with very small max file size to trigger rotation
  L := TLogger.Create(FLogDir, llTrace, 500, 5);
  try
    for i := 1 to 50 do
      L.Info('Line ' + IntToStr(i) + ': ' + StringOfChar('X', 30));
  finally
    L.Free;
  end;

  Files := TDirectory.GetFiles(FLogDir, 'PiMono_*.log');
  Assert(Length(Files) >= 2, 'Should have rotated files, got ' + IntToStr(Length(Files)));
end;

procedure TTestLogger.Test_LogPathProperty;
var
  L: TLogger;
begin
  L := TLogger.Create(FLogDir);
  try
    Assert(L.LogPath = FLogDir, 'LogPath should match constructor param');
  finally
    L.Free;
  end;
end;

procedure TTestLogger.Test_MinLevelProperty;
var
  L: TLogger;
begin
  L := TLogger.Create(FLogDir, llInfo);
  try
    Assert(L.MinLevel = llInfo, 'MinLevel should be Info');
    L.MinLevel := llDebug;
    Assert(L.MinLevel = llDebug, 'MinLevel should be updated');
  finally
    L.Free;
  end;
end;

{ Registration }

procedure RegisterUtilsLoggerTests;
var
  T: TTestLogger;
begin
  T := TTestLogger.Create;
  try
    GRunner.RunTest('Logger: Create logger', T.Test_CreateLogger, T.Setup, T.TearDown);
    GRunner.RunTest('Logger: Info writes file', T.Test_InfoLog_WritesFile, T.Setup, T.TearDown);
    GRunner.RunTest('Logger: Warn writes file', T.Test_WarnLog_WritesFile, T.Setup, T.TearDown);
    GRunner.RunTest('Logger: Error writes file', T.Test_ErrorLog_WritesFile, T.Setup, T.TearDown);
    GRunner.RunTest('Logger: Fatal writes file', T.Test_FatalLog_WritesFile, T.Setup, T.TearDown);
    GRunner.RunTest('Logger: MinLevel filters below', T.Test_MinLevel_FiltersBelow, T.Setup, T.TearDown);
    GRunner.RunTest('Logger: Trace filtered by default', T.Test_TraceFiltered_ByDefault, T.Setup, T.TearDown);
    GRunner.RunTest('Logger: Debug filtered by default', T.Test_DebugFiltered_ByDefault, T.Setup, T.TearDown);
    GRunner.RunTest('Logger: Trace level passes all', T.Test_MinLevel_Trace_PassesAll, T.Setup, T.TearDown);
    GRunner.RunTest('Logger: Trace method', T.Test_TraceMethod, T.Setup, T.TearDown);
    GRunner.RunTest('Logger: Debug method', T.Test_DebugMethod, T.Setup, T.TearDown);
    GRunner.RunTest('Logger: Log format', T.Test_LogFormat, T.Setup, T.TearDown);
    GRunner.RunTest('Logger: LogException with context', T.Test_LogException_WithContext, T.Setup, T.TearDown);
    GRunner.RunTest('Logger: LogException without context', T.Test_LogException_WithoutContext, T.Setup, T.TearDown);
    GRunner.RunTest('Logger: Rotation by size', T.Test_Rotation_BySize, T.Setup, T.TearDown);
    GRunner.RunTest('Logger: LogPath property', T.Test_LogPathProperty, T.Setup, T.TearDown);
    GRunner.RunTest('Logger: MinLevel property', T.Test_MinLevelProperty, T.Setup, T.TearDown);
  finally
    T.Free;
  end;
end;

end.
