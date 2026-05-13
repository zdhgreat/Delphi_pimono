unit Tools.ToolRegistry;

interface

uses
  System.SysUtils, System.SyncObjs, System.Generics.Collections,
  Core.AgentState;

type
  TToolRegistry = class
  private
    FTools: TDictionary<string, IAgentTool>;
    FToolOrder: TList<string>;
    FLock: TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;

    procedure RegisterTool(ATool: IAgentTool);
    procedure UnregisterTool(const AName: string);
    function GetTool(const AName: string): IAgentTool;
    function GetAllTools: TArray<IAgentTool>;
    function GetAllToolNames: TArray<string>;
    function HasTool(const AName: string): Boolean;
    function Count: Integer;
    procedure Clear;
  end;

implementation

{ TToolRegistry }

constructor TToolRegistry.Create;
begin
  inherited Create;
  FTools := TDictionary<string, IAgentTool>.Create;
  FToolOrder := TList<string>.Create;
  FLock := TCriticalSection.Create;
end;

destructor TToolRegistry.Destroy;
begin
  FLock.Free;
  FToolOrder.Free;
  FTools.Free;
  inherited;
end;

procedure TToolRegistry.RegisterTool(ATool: IAgentTool);
var
  Name: string;
begin
  if ATool = nil then Exit;
  Name := LowerCase(ATool.GetName);
  FLock.Acquire;
  try
    if FTools.ContainsKey(Name) then
      FTools.Remove(Name)
    else
      FToolOrder.Add(Name);
    FTools.Add(Name, ATool);
  finally
    FLock.Release;
  end;
end;

procedure TToolRegistry.UnregisterTool(const AName: string);
var
  Name: string;
  Idx: Integer;
begin
  Name := LowerCase(AName);
  FLock.Acquire;
  try
    FTools.Remove(Name);
    Idx := FToolOrder.IndexOf(Name);
    if Idx >= 0 then
      FToolOrder.Delete(Idx);
  finally
    FLock.Release;
  end;
end;

function TToolRegistry.GetTool(const AName: string): IAgentTool;
begin
  FLock.Acquire;
  try
    if not FTools.TryGetValue(LowerCase(AName), Result) then
      Result := nil;
  finally
    FLock.Release;
  end;
end;

function TToolRegistry.GetAllTools: TArray<IAgentTool>;
var
  i: Integer;
begin
  FLock.Acquire;
  try
    SetLength(Result, FToolOrder.Count);
    for i := 0 to FToolOrder.Count - 1 do
      Result[i] := FTools[FToolOrder[i]];
  finally
    FLock.Release;
  end;
end;

function TToolRegistry.GetAllToolNames: TArray<string>;
begin
  FLock.Acquire;
  try
    Result := FToolOrder.ToArray;
  finally
    FLock.Release;
  end;
end;

function TToolRegistry.HasTool(const AName: string): Boolean;
begin
  FLock.Acquire;
  try
    Result := FTools.ContainsKey(LowerCase(AName));
  finally
    FLock.Release;
  end;
end;

function TToolRegistry.Count: Integer;
begin
  FLock.Acquire;
  try
    Result := FTools.Count;
  finally
    FLock.Release;
  end;
end;

procedure TToolRegistry.Clear;
begin
  FLock.Acquire;
  try
    FTools.Clear;
    FToolOrder.Clear;
  finally
    FLock.Release;
  end;
end;

end.
