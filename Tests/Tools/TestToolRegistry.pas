unit TestToolRegistry;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.SyncObjs,
  Tools.ITool, Tools.ToolRegistry, Core.AgentState, Core.Messages,
  PiMonoTestFramework;

type
  // Concrete test tool for registry testing
  TTestTool = class(TBaseTool)
  private
    FName: string;
  protected
    function GetName: string; override;
    function GetLabel: string; override;
    function GetDescription: string; override;
  public
    constructor Create(const AWorkingDir, AName: string); reintroduce;
    function Execute(const AToolCallId: string; AParams: TJSONObject;
      AIsAborted: TAbortedCallback): TToolResult; override;
  end;

  TTestToolRegistryClass = class
  private
    FRegistry: TToolRegistry;
  public
    procedure Setup;
    procedure TearDown;

    procedure RegisterAndGet;
    procedure RegisterMultiple;
    procedure GetNonExistent;
    procedure Remove;
    procedure RemoveNonExistent;
    procedure GetAllTools;
    procedure CaseInsensitive;
    procedure Clear;
    procedure Count;
    procedure RegisterDuplicate;
    procedure ThreadSafety;
    procedure GetAllToolNames;
    procedure HasTool_True;
    procedure HasTool_False;
  end;

procedure RegisterToolRegistryTests;

implementation

{ TTestTool }

constructor TTestTool.Create(const AWorkingDir, AName: string);
begin
  inherited Create(AWorkingDir);
  FName := AName;
end;

function TTestTool.GetName: string;
begin
  Result := FName;
end;

function TTestTool.GetLabel: string;
begin
  Result := FName + ' label';
end;

function TTestTool.GetDescription: string;
begin
  Result := FName + ' description';
end;

function TTestTool.Execute(const AToolCallId: string; AParams: TJSONObject;
  AIsAborted: TAbortedCallback): TToolResult;
begin
  Result := TToolResult.CreateText(FName + ' executed');
end;

{ TTestToolRegistryClass }

procedure TTestToolRegistryClass.Setup;
begin
  FRegistry := TToolRegistry.Create;
end;

procedure TTestToolRegistryClass.TearDown;
begin
  FRegistry.Free;
end;

procedure TTestToolRegistryClass.RegisterAndGet;
var
  Tool: IAgentTool;
  Found: IAgentTool;
begin
  Tool := TTestTool.Create('C:\temp', 'my_tool');
  FRegistry.RegisterTool(Tool);

  Found := FRegistry.GetTool('my_tool');
  Assert(Found <> nil, 'GetTool should find registered tool');
  Assert('my_tool' = Found.GetName, 'Tool name should match');
end;

procedure TTestToolRegistryClass.RegisterMultiple;
var
  i: Integer;
begin
  for i := 1 to 5 do
    FRegistry.RegisterTool(TTestTool.Create('C:\temp', 'tool_' + IntToStr(i)));
  Assert(5 = FRegistry.Count, 'Count should be 5 after registering 5 tools');
end;

procedure TTestToolRegistryClass.GetNonExistent;
begin
  Assert(FRegistry.GetTool('nonexistent') = nil, 'GetTool should return nil for unknown tool');
end;

procedure TTestToolRegistryClass.Remove;
var
  Found: IAgentTool;
begin
  FRegistry.RegisterTool(TTestTool.Create('C:\temp', 'removable'));
  Found := FRegistry.GetTool('removable');
  Assert(Found <> nil, 'Tool should exist before removal');

  FRegistry.UnregisterTool('removable');
  Found := FRegistry.GetTool('removable');
  Assert(Found = nil, 'Tool should be gone after removal');
end;

procedure TTestToolRegistryClass.RemoveNonExistent;
begin
  // Should not crash
  FRegistry.UnregisterTool('nothing');
  Assert(True, 'No crash on removing non-existent tool');
end;

procedure TTestToolRegistryClass.GetAllTools;
var
  Arr: TArray<IAgentTool>;
begin
  FRegistry.RegisterTool(TTestTool.Create('C:\temp', 'a'));
  FRegistry.RegisterTool(TTestTool.Create('C:\temp', 'b'));
  Arr := FRegistry.GetAllTools;
  Assert(2 = Length(Arr), 'GetAllTools should return 2 tools');
end;

procedure TTestToolRegistryClass.CaseInsensitive;
var
  Found1, Found2, Found3: IAgentTool;
begin
  FRegistry.RegisterTool(TTestTool.Create('C:\temp', 'MyTool'));
  Found1 := FRegistry.GetTool('mytool');
  Found2 := FRegistry.GetTool('MYTOOL');
  Found3 := FRegistry.GetTool('MyTool');
  Assert(Found1 <> nil, 'Should find tool with lowercase name');
  Assert(Found2 <> nil, 'Should find tool with uppercase name');
  Assert(Found3 <> nil, 'Should find tool with original case');
end;

procedure TTestToolRegistryClass.Clear;
begin
  FRegistry.RegisterTool(TTestTool.Create('C:\temp', 'a'));
  FRegistry.RegisterTool(TTestTool.Create('C:\temp', 'b'));
  FRegistry.Clear;
  Assert(0 = FRegistry.Count, 'Count should be 0 after Clear');
end;

procedure TTestToolRegistryClass.Count;
begin
  Assert(0 = FRegistry.Count, 'Count should start at 0');
  FRegistry.RegisterTool(TTestTool.Create('C:\temp', 'a'));
  Assert(1 = FRegistry.Count, 'Count should be 1 after one registration');
  FRegistry.RegisterTool(TTestTool.Create('C:\temp', 'b'));
  Assert(2 = FRegistry.Count, 'Count should be 2 after two registrations');
end;

procedure TTestToolRegistryClass.RegisterDuplicate;
begin
  FRegistry.RegisterTool(TTestTool.Create('C:\temp', 'dup'));
  FRegistry.RegisterTool(TTestTool.Create('C:\temp', 'dup'));
  // Should have only one (overwrite)
  Assert(1 = FRegistry.Count, 'Duplicate registration should overwrite, count=1');
end;

procedure TTestToolRegistryClass.ThreadSafety;
var
  Threads: array[0..3] of TThread;
  i: Integer;
begin
  // Register tools from multiple threads
  for i := 0 to 3 do
  begin
    Threads[i] := TThread.CreateAnonymousThread(
      procedure
      var
        TIdx: Integer;
        Tid: NativeUInt;
      begin
        Tid := TThread.CurrentThread.ThreadID;
        for TIdx := 1 to 10 do
          FRegistry.RegisterTool(TTestTool.Create('C:\temp',
            'thread_tool_' + IntToStr(Tid) + '_' + IntToStr(TIdx)));
      end);
    Threads[i].FreeOnTerminate := False;
  end;

  for i := 0 to 3 do Threads[i].Start;
  for i := 0 to 3 do Threads[i].WaitFor;
  for i := 0 to 3 do Threads[i].Free;

  Assert(40 = FRegistry.Count, 'All 40 tools should be registered');
end;

procedure TTestToolRegistryClass.GetAllToolNames;
var
  Names: TArray<string>;
begin
  FRegistry.RegisterTool(TTestTool.Create('C:\temp', 'alpha'));
  FRegistry.RegisterTool(TTestTool.Create('C:\temp', 'beta'));
  FRegistry.RegisterTool(TTestTool.Create('C:\temp', 'gamma'));
  Names := FRegistry.GetAllToolNames;
  Assert(3 = Length(Names), 'GetAllToolNames should return 3 names');
end;

procedure TTestToolRegistryClass.HasTool_True;
begin
  FRegistry.RegisterTool(TTestTool.Create('C:\temp', 'my_tool'));
  Assert(FRegistry.HasTool('my_tool'), 'HasTool should return True for registered tool');
end;

procedure TTestToolRegistryClass.HasTool_False;
begin
  Assert(not FRegistry.HasTool('nonexistent'), 'HasTool should return False for unregistered tool');
end;

{ === Registration === }

procedure RegisterToolRegistryTests;
var
  T: TTestToolRegistryClass;
begin
  T := TTestToolRegistryClass.Create;
  try
    GRunner.RunTest('ToolRegistry.RegisterAndGet', T.RegisterAndGet, T.Setup, T.TearDown);
    GRunner.RunTest('ToolRegistry.RegisterMultiple', T.RegisterMultiple, T.Setup, T.TearDown);
    GRunner.RunTest('ToolRegistry.GetNonExistent', T.GetNonExistent, T.Setup, T.TearDown);
    GRunner.RunTest('ToolRegistry.Remove', T.Remove, T.Setup, T.TearDown);
    GRunner.RunTest('ToolRegistry.RemoveNonExistent', T.RemoveNonExistent, T.Setup, T.TearDown);
    GRunner.RunTest('ToolRegistry.GetAllTools', T.GetAllTools, T.Setup, T.TearDown);
    GRunner.RunTest('ToolRegistry.CaseInsensitive', T.CaseInsensitive, T.Setup, T.TearDown);
    GRunner.RunTest('ToolRegistry.Clear', T.Clear, T.Setup, T.TearDown);
    GRunner.RunTest('ToolRegistry.Count', T.Count, T.Setup, T.TearDown);
    GRunner.RunTest('ToolRegistry.RegisterDuplicate', T.RegisterDuplicate, T.Setup, T.TearDown);
    GRunner.RunTest('ToolRegistry.ThreadSafety', T.ThreadSafety, T.Setup, T.TearDown);
    GRunner.RunTest('ToolRegistry.GetAllToolNames', T.GetAllToolNames, T.Setup, T.TearDown);
    GRunner.RunTest('ToolRegistry.HasTool_True', T.HasTool_True, T.Setup, T.TearDown);
    GRunner.RunTest('ToolRegistry.HasTool_False', T.HasTool_False, T.Setup, T.TearDown);
  finally
    T.Free;
  end;
end;

end.
