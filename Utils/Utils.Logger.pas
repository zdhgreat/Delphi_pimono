unit Utils.Logger;

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.IOUtils,
  System.DateUtils, System.Generics.Collections, System.Types,
  Winapi.Windows;

type
  TLogLevel = (
    llTrace = 0,
    llDebug = 10,
    llInfo  = 20,
    llWarn  = 30,
    llError = 40,
    llFatal = 50
  );

  TLogger = class
  private
    FMinLevel: TLogLevel;
    FLogPath: string;
    FMaxFileSize: Int64;
    FMaxFiles: Integer;
    FLock: TObject;
    FCurrentStream: TStreamWriter;
    FCurrentFileStream: TFileStream;
    FCurrentFileSize: Int64;

    procedure EnsureStream;
    procedure RotateIfNeeded;
    function LevelToString(ALevel: TLogLevel): string;
    function LogFileName: string;
  public
    constructor Create(const ALogPath: string;
      AMinLevel: TLogLevel = llInfo;
      AMaxFileSize: Int64 = 10485760;  // 10 MB
      AMaxFiles: Integer = 30);
    destructor Destroy; override;

    procedure Log(ALevel: TLogLevel; const AMessage: string); overload;
    procedure Log(ALevel: TLogLevel; const AFormat: string;
      const Args: array of const); overload;
    procedure Trace(const AMessage: string);
    procedure Debug(const AMessage: string);
    procedure Info(const AMessage: string);
    procedure Warn(const AMessage: string);
    procedure Error(const AMessage: string);
    procedure Fatal(const AMessage: string);
    procedure LogException(E: Exception; const AContext: string = '');

    property MinLevel: TLogLevel read FMinLevel write FMinLevel;
    property LogPath: string read FLogPath;
  end;

  TLoggerFactory = class sealed
  private
    class var FInstance: TLogger;
    class var FLock: TObject;
  public
    class function GetLogger: TLogger;
    class procedure Initialize(const ALogPath: string;
      AMinLevel: TLogLevel = llInfo);
    class procedure Finalize;
  end;

implementation

{ TLogger }

constructor TLogger.Create(const ALogPath: string;
  AMinLevel: TLogLevel; AMaxFileSize: Int64; AMaxFiles: Integer);
begin
  inherited Create;
  FLogPath := ALogPath;
  FMinLevel := AMinLevel;
  FMaxFileSize := AMaxFileSize;
  FMaxFiles := AMaxFiles;
  FLock := TObject.Create;
  FCurrentStream := nil;
  FCurrentFileSize := 0;
end;

destructor TLogger.Destroy;
begin
  TMonitor.Enter(FLock);
  try
    if Assigned(FCurrentStream) then
    begin
      FCurrentStream.Free;
      FCurrentStream := nil;
    end;
    if Assigned(FCurrentFileStream) then
    begin
      FCurrentFileStream.Free;
      FCurrentFileStream := nil;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  FLock.Free;
  inherited;
end;

procedure TLogger.EnsureStream;
var
  Dir: string;
begin
  if Assigned(FCurrentStream) then
    Exit;

  Dir := ExtractFilePath(LogFileName);
  if not DirectoryExists(Dir) then
    ForceDirectories(Dir);

  if FileExists(LogFileName) then
  begin
    FCurrentFileStream := TFileStream.Create(LogFileName, fmOpenReadWrite or fmShareDenyNone);
    FCurrentStream := TStreamWriter.Create(FCurrentFileStream, TEncoding.UTF8);
    FCurrentStream.BaseStream.Seek(0, soEnd);
    FCurrentFileSize := FCurrentStream.BaseStream.Size;
  end
  else
  begin
    FCurrentFileStream := TFileStream.Create(LogFileName, fmCreate or fmShareDenyNone);
    FCurrentStream := TStreamWriter.Create(FCurrentFileStream, TEncoding.UTF8);
    FCurrentFileSize := 0;
  end;
  FCurrentStream.AutoFlush := True;
end;

function TLogger.LogFileName: string;
begin
  Result := IncludeTrailingPathDelimiter(FLogPath) +
    'PiMono_' + FormatDateTime('yyyymmdd', Date) + '.log';
end;

procedure TLogger.RotateIfNeeded;
var
  RotatedName: string;
  Files: TStringDynArray;
  FileList: TList<string>;
  i: Integer;
begin
  if FCurrentFileSize < FMaxFileSize then
    Exit;

  FCurrentStream.Free;
  FCurrentStream := nil;
  FreeAndNil(FCurrentFileStream);
  FCurrentFileSize := 0;

  RotatedName := IncludeTrailingPathDelimiter(FLogPath) +
    'PiMono_' + FormatDateTime('yyyymmdd_hhnnss', Now) + '.log';
  RenameFile(LogFileName, RotatedName);

  // Clean up old rotated files
  Files := TDirectory.GetFiles(FLogPath, 'PiMono_*.log');
  if Length(Files) > FMaxFiles then
  begin
    FileList := TList<string>.Create;
    try
      for i := 0 to High(Files) do
        FileList.Add(Files[i]);
      FileList.Sort;

      while FileList.Count > FMaxFiles do
      begin
        System.SysUtils.DeleteFile(FileList[0]);
        FileList.Delete(0);
      end;
    finally
      FileList.Free;
    end;
  end;
end;

function TLogger.LevelToString(ALevel: TLogLevel): string;
begin
  case ALevel of
    llTrace: Result := 'TRACE';
    llDebug: Result := 'DEBUG';
    llInfo:  Result := 'INFO';
    llWarn:  Result := 'WARN';
    llError: Result := 'ERROR';
    llFatal: Result := 'FATAL';
  else
    Result := 'UNKNOWN';
  end;
end;

procedure TLogger.Log(ALevel: TLogLevel; const AMessage: string);
var
  Line: string;
begin
  if Ord(ALevel) < Ord(FMinLevel) then
    Exit;

  TMonitor.Enter(FLock);
  try
    EnsureStream;
    Line := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + ' [' +
      LevelToString(ALevel) + '] ' + AMessage;
    FCurrentStream.WriteLine(Line);
    FCurrentFileSize := FCurrentFileSize + Length(TEncoding.UTF8.GetBytes(Line)) + 2;
    RotateIfNeeded;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TLogger.Log(ALevel: TLogLevel; const AFormat: string;
  const Args: array of const);
begin
  Log(ALevel, Format(AFormat, Args));
end;

procedure TLogger.Trace(const AMessage: string);
begin
  Log(llTrace, AMessage);
end;

procedure TLogger.Debug(const AMessage: string);
begin
  Log(llDebug, AMessage);
end;

procedure TLogger.Info(const AMessage: string);
begin
  Log(llInfo, AMessage);
end;

procedure TLogger.Warn(const AMessage: string);
begin
  Log(llWarn, AMessage);
end;

procedure TLogger.Error(const AMessage: string);
begin
  Log(llError, AMessage);
end;

procedure TLogger.Fatal(const AMessage: string);
begin
  Log(llFatal, AMessage);
end;

procedure TLogger.LogException(E: Exception; const AContext: string);
begin
  if AContext <> '' then
    Log(llError, '%s: %s - %s', [AContext, E.ClassName, E.Message])
  else
    Log(llError, '%s: %s', [E.ClassName, E.Message]);
end;

{ TLoggerFactory }

class function TLoggerFactory.GetLogger: TLogger;
begin
  if not Assigned(FInstance) then
  begin
    TMonitor.Enter(FLock);
    try
      if not Assigned(FInstance) then
        Initialize(IncludeTrailingPathDelimiter(
          GetEnvironmentVariable('LOCALAPPDATA')) + 'PiMono\Logs');
    finally
      TMonitor.Exit(FLock);
    end;
  end;
  Result := FInstance;
end;

class procedure TLoggerFactory.Initialize(const ALogPath: string;
  AMinLevel: TLogLevel);
begin
  FInstance.Free;
  FInstance := TLogger.Create(ALogPath, AMinLevel);
end;

class procedure TLoggerFactory.Finalize;
begin
  FInstance.Free;
  FInstance := nil;
end;

initialization
  TLoggerFactory.FLock := TObject.Create;

finalization
  TLoggerFactory.Finalize;
  TLoggerFactory.FLock.Free;
  TLoggerFactory.FLock := nil;

end.
