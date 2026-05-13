unit Tools.ITool;

interface

uses
  System.SysUtils, System.JSON,
  Core.Messages, Core.AgentState, Core.UndoLog;

type
  // Base tool class - inherit from this for all tools
  TBaseTool = class abstract(TInterfacedObject, IAgentTool)
  protected
    FWorkingDir: string;
    FUndoLog: TUndoLog;
    function GetName: string; virtual; abstract;
    function GetLabel: string; virtual; abstract;
    function GetDescription: string; virtual; abstract;
    function GetParameterSchema: TJSONObject; virtual;
    function ResolvePath(const APath: string): string;
    function IsPathInWorkingDir(const AFullPath: string): Boolean;
    function Execute(const AToolCallId: string; AParams: TJSONObject;
      AIsAborted: TAbortedCallback): TToolResult; virtual; abstract;
  public
    constructor Create(const AWorkingDir: string); virtual;
    property Name: string read GetName;
    property Label_: string read GetLabel;
    property Description: string read GetDescription;
    property UndoLog: TUndoLog read FUndoLog write FUndoLog;
  end;

  // Schema builder helpers
  function BuildStringParam(const AName, ADescription: string): TJSONObject;
  function BuildIntegerParam(const AName, ADescription: string): TJSONObject;
  function BuildBooleanParam(const AName, ADescription: string): TJSONObject;

implementation

{ TBaseTool }

constructor TBaseTool.Create(const AWorkingDir: string);
begin
  inherited Create;
  FWorkingDir := AWorkingDir;
  FUndoLog := nil;
end;

function TBaseTool.GetParameterSchema: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  Result.AddPair('properties', TJSONObject.Create);
end;

function TBaseTool.ResolvePath(const APath: string): string;
begin
  if (Length(APath) > 1) and ((APath[1] = '\') or (APath[2] = ':')) then
    Result := ExpandFileName(APath)
  else if (Length(APath) > 0) and (APath[1] = '~') then
    Result := ExpandFileName(GetEnvironmentVariable('USERPROFILE') + Copy(APath, 2, MaxInt))
  else
    Result := ExpandFileName(IncludeTrailingPathDelimiter(FWorkingDir) + APath);
end;

function TBaseTool.IsPathInWorkingDir(const AFullPath: string): Boolean;
var
  NormPath, NormWork: string;
begin
  // Note: ExpandFileName does NOT resolve symlinks or junctions on Windows.
  // For production-grade security, use GetFinalPathNameByHandle WinAPI to
  // resolve the true path. Current implementation is adequate for typical usage.
  NormPath := LowerCase(ExpandFileName(AFullPath));
  NormWork := LowerCase(IncludeTrailingPathDelimiter(ExpandFileName(FWorkingDir)));
  Result := NormPath.StartsWith(NormWork) or
    (NormPath = NormWork.Remove(NormWork.Length - 1));
  // Also block path traversal attempts containing '..'
  if Result and (Pos('..', NormPath) > 0) then
    Result := False;
end;

{ Schema Helpers }

function BuildStringParam(const AName, ADescription: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'string');
  Result.AddPair('description', ADescription);
end;

function BuildIntegerParam(const AName, ADescription: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'integer');
  Result.AddPair('description', ADescription);
end;

function BuildBooleanParam(const AName, ADescription: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'boolean');
  Result.AddPair('description', ADescription);
end;

end.
