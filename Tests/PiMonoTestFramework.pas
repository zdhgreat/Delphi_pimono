unit PiMonoTestFramework;

// Lightweight self-contained test framework - no external dependencies
// Outputs results to both console and log file

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections;

type
  TTestMethod = procedure of object;

  TTestResult = record
    TestName: string;
    Passed: Boolean;
    ErrorMsg: string;
    DurationMs: Integer;
  end;

  TTestRunner = class
  private
    FResults: TList<TTestResult>;
    FPassCount: Integer;
    FFailCount: Integer;
    FErrorCount: Integer;
    FLogFile: TStringList;
    FLogPath: string;
    FStartTime: TDateTime;
    procedure AddResult(const AName: string; APassed: Boolean; const AError: string; ADuration: Integer);
    procedure Log(const ALine: string);
  public
    constructor Create;
    destructor Destroy; override;
    procedure RunTest(const AName: string; AMethod: TTestMethod;
      ASetup: TTestMethod = nil; ATearDown: TTestMethod = nil);
    procedure PrintResults;
    function AllPassed: Boolean;
    function TotalTests: Integer;
    property PassCount: Integer read FPassCount;
    property FailCount: Integer read FFailCount;
    property ErrorCount: Integer read FErrorCount;
    property LogPath: string read FLogPath;
  end;

var
  GRunner: TTestRunner;

implementation

uses
  Winapi.Windows;

{ TTestRunner }

constructor TTestRunner.Create;
var
  LogDir: string;
begin
  inherited Create;
  FResults := TList<TTestResult>.Create;
  FLogFile := TStringList.Create;
  FStartTime := Now;

  // Log file: same dir as exe, named with timestamp
  LogDir := ExtractFilePath(ParamStr(0));
  if LogDir = '' then
    LogDir := TPath.GetDirectoryName(ParamStr(0));
  if LogDir = '' then
    LogDir := TPath.GetTempPath;

  FLogPath := TPath.Combine(LogDir,
    'PiMonoTests_' + FormatDateTime('yyyyMM_dd_hhnnss', FStartTime) + '.log');
end;

destructor TTestRunner.Destroy;
begin
  FResults.Free;
  FLogFile.Free;
  inherited;
end;

procedure TTestRunner.Log(const ALine: string);
begin
  FLogFile.Add(ALine);
end;

procedure TTestRunner.AddResult(const AName: string; APassed: Boolean;
  const AError: string; ADuration: Integer);
var
  R: TTestResult;
begin
  R.TestName := AName;
  R.Passed := APassed;
  R.ErrorMsg := AError;
  R.DurationMs := ADuration;
  FResults.Add(R);
  if APassed then
    Inc(FPassCount)
  else
    Inc(FFailCount);
end;

procedure TTestRunner.RunTest(const AName: string; AMethod: TTestMethod;
  ASetup: TTestMethod; ATearDown: TTestMethod);
var
  StartTick: Cardinal;
  ExMsg: string;
  SetupOk: Boolean;
  Status: string;
  SavedName: string;
begin
  // Copy AName early so it survives even if test corrupts memory
  SavedName := AName;
  Write('  [RUN ] ', SavedName, ' ... ');

  StartTick := GetTickCount;
  SetupOk := True;

  try
    // Setup phase
    if Assigned(ASetup) then
    begin
      try
        ASetup;
      except
        on E: Exception do
        begin
          AddResult(SavedName, False, 'Setup failed: ' + E.Message, GetTickCount - StartTick);
          Status := 'FAIL (setup)';
          Writeln(Status);
          Log('[FAIL] ' + SavedName + ' [setup] (' + IntToStr(GetTickCount - StartTick) + 'ms)');
          Log('       ' + E.ClassName + ': ' + E.Message);
          Inc(FErrorCount);
          SetupOk := False;
        end;
      end;
    end;

    // Test phase (only if setup succeeded)
    if SetupOk then
    begin
      try
        AMethod;
        AddResult(SavedName, True, '', GetTickCount - StartTick);
        Status := 'OK';
        Writeln(Status);
        Log('[PASS] ' + SavedName + ' (' + IntToStr(GetTickCount - StartTick) + 'ms)');
      except
        on E: Exception do
        begin
          ExMsg := E.ClassName + ': ' + E.Message;
          AddResult(SavedName, False, ExMsg, GetTickCount - StartTick);
          Inc(FErrorCount);
          Status := 'FAIL';
          Writeln(Status);
          Writeln('        ', ExMsg);
          Log('[FAIL] ' + SavedName + ' (' + IntToStr(GetTickCount - StartTick) + 'ms)');
          Log('       ' + ExMsg);
        end;
      end;
    end;
  finally
    // Teardown phase - always called, even after setup failure
    if Assigned(ATearDown) then
    try
      ATearDown;
    except
    end;
  end;
end;

procedure TTestRunner.PrintResults;
var
  i: Integer;
  Summary: string;
  Duration: string;
begin
  Duration := FormatDateTime('hh:nn:ss', Now - FStartTime);
  Summary := Format('  RESULTS: %d tests, %d passed, %d failed',
    [TotalTests, FPassCount, FFailCount]);
  if FErrorCount > 0 then
    Summary := Summary + Format(', %d errors', [FErrorCount]);
  Summary := Summary + Format(' (elapsed: %s)', [Duration]);

  // Console output
  Writeln;
  Writeln('================================================');
  Writeln(Summary);
  Writeln('================================================');

  if FFailCount > 0 then
  begin
    Writeln;
    Writeln('FAILED TESTS:');
    for i := 0 to FResults.Count - 1 do
    begin
      if not FResults[i].Passed then
        Writeln('  [FAIL] ', FResults[i].TestName, ' - ', FResults[i].ErrorMsg);
    end;
  end;

  // Log file output
  Log('');
  Log('================================================');
  Log('  PiMono Test Results');
  Log('  Date: ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', FStartTime));
  Log('  Duration: ' + Duration);
  Log('  ' + Summary);
  Log('================================================');
  Log('');

  if FFailCount > 0 then
  begin
    Log('FAILED TESTS:');
    for i := 0 to FResults.Count - 1 do
    begin
      if not FResults[i].Passed then
        Log('  [FAIL] ' + FResults[i].TestName + ' - ' + FResults[i].ErrorMsg);
    end;
    Log('');
  end;

  // Detail section - all tests with timing
  Log('DETAILED RESULTS:');
  Log(Format('%-4s %-50s %6s %s', ['OK?', 'Test Name', 'Time', 'Error']));
  Log(StringOfChar('-', 90));
  for i := 0 to FResults.Count - 1 do
  begin
    if FResults[i].Passed then
      Log(Format('PASS %-50s %4dms', [FResults[i].TestName, FResults[i].DurationMs]))
    else
      Log(Format('FAIL %-50s %4dms  %s', [FResults[i].TestName, FResults[i].DurationMs, FResults[i].ErrorMsg]));
  end;

  Log('');
  Log(StringOfChar('=', 90));
  Log(Summary);
  Log('');

  // Write log file
  try
    FLogFile.SaveToFile(FLogPath, TEncoding.UTF8);
    Writeln;
    Writeln('  Log saved to: ', FLogPath);
  except
    on E: Exception do
      Writeln('  WARNING: Could not save log file: ', E.Message);
  end;
end;

function TTestRunner.AllPassed: Boolean;
begin
  Result := FFailCount = 0;
end;

function TTestRunner.TotalTests: Integer;
begin
  Result := FResults.Count;
end;

initialization
  GRunner := TTestRunner.Create;

finalization
  GRunner.Free;

end.
