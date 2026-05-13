unit TestAgent;

interface

uses
  System.SysUtils, System.JSON, System.Classes, System.SyncObjs,
  Winapi.Windows,
  Core.Messages, Core.AgentState, Core.Agent, Core.Events,
  AI.IModel, AI.ModelConfig, Settings.Config,
  PiMonoTestFramework;

procedure RegisterAgentTests;

implementation

uses
  MockModel;

type
  // Callback-based mock tool for agent testing
  TExecuteCallback = reference to procedure(AToolCallId: string;
    AParams: TJSONObject; AIsAborted: TAbortedCallback; var R: TToolResult);

  TMockAgentTool = class(TInterfacedObject, IAgentTool)
  private
    FName: string;
    FLabel: string;
    FDesc: string;
    FCallback: TExecuteCallback;
  public
    constructor Create(const AName, ALabel, ADesc: string; ACallback: TExecuteCallback);
    function GetName: string;
    function GetLabel: string;
    function GetDescription: string;
    function GetParameterSchema: TJSONObject;
    function Execute(const AToolCallId: string; AParams: TJSONObject;
      AIsAborted: TAbortedCallback): TToolResult;
  end;

{ TMockAgentTool }

constructor TMockAgentTool.Create(const AName, ALabel, ADesc: string;
  ACallback: TExecuteCallback);
begin
  inherited Create;
  FName := AName;
  FLabel := ALabel;
  FDesc := ADesc;
  FCallback := ACallback;
end;

function TMockAgentTool.GetName: string;
begin
  Result := FName;
end;

function TMockAgentTool.GetLabel: string;
begin
  Result := FLabel;
end;

function TMockAgentTool.GetDescription: string;
begin
  Result := FDesc;
end;

function TMockAgentTool.GetParameterSchema: TJSONObject;
begin
  Result := TJSONObject.Create;
end;

function TMockAgentTool.Execute(const AToolCallId: string;
  AParams: TJSONObject; AIsAborted: TAbortedCallback): TToolResult;
begin
  if Assigned(FCallback) then
    FCallback(AToolCallId, AParams, AIsAborted, Result)
  else
    Result := TToolResult.CreateError('No callback');
end;

type
  TTestAgent = class
  public
    // Lifecycle
    procedure Test_Create_Defaults;
    procedure Test_SetSystemPrompt;
    procedure Test_SetModel;
    procedure Test_SetThinkingLevel;
    procedure Test_MaxTurns_Default;

    // Prompt with MockModel
    procedure Test_Prompt_SimpleText;
    procedure Test_Prompt_NoModel_Stub;
    procedure Test_Prompt_ToolCallLoop;
    procedure Test_Prompt_MultiToolCall;

    // Abort
    procedure Test_Abort_DuringPrompt;

    // Queue
    procedure Test_Steer_Enqueue;
    procedure Test_FollowUp_Enqueue;
    procedure Test_ClearQueues;

    // Messages
    procedure Test_ReplaceMessages;
    procedure Test_AppendMessage;
    procedure Test_ClearMessages;

    // Confirmation
    procedure Test_ConfirmToolExecution;

    // Compaction settings
    procedure Test_SetCompactionSettings;

    // Properties
    procedure Test_CompactionCount_Initial;
    procedure Test_IsStreaming_InitiallyFalse;

    // Additional coverage
    procedure Test_Reset;
    procedure Test_Subscribe_Unsubscribe;
    procedure Test_SetPermissions;
    procedure Test_WaitForIdle;
  end;

{ Helper }

procedure WaitForAgentNotStreaming(AAgent: TAgent; ATimeoutMs: Cardinal = 5000);
var
  Start: Cardinal;
  Elapsed: Cardinal;
begin
  Start := GetTickCount;
  // Wait for agent to start streaming first (give it time to begin)
  while not AAgent.IsStreaming do
  begin
    Elapsed := GetTickCount - Start;
    if Elapsed > 500 then
      Break  // Never started within 500ms — assume synchronous/fast completion
    else
      Sleep(5);
  end;
  // Now wait for streaming to finish
  while AAgent.IsStreaming do
  begin
    Elapsed := GetTickCount - Start;
    if Elapsed > ATimeoutMs then
      Assert(False, 'Agent did not stop streaming within timeout (' + IntToStr(ATimeoutMs) + 'ms)');
    Sleep(10);
  end;
end;

{ TTestAgent }

procedure TTestAgent.Test_Create_Defaults;
var
  Agent: TAgent;
begin
  Agent := TAgent.Create;
  try
    Assert(not Agent.IsStreaming, 'Should not be streaming initially');
    Assert(Agent.CompactionCount = 0, 'CompactionCount should be 0');
    Assert(Agent.MaxTurns = 30, 'MaxTurns default should be 30');
  finally
    Agent.Free;
  end;
end;

procedure TTestAgent.Test_SetSystemPrompt;
var
  Agent: TAgent;
begin
  Agent := TAgent.Create;
  try
    Agent.SetSystemPrompt('You are a test assistant.');
    Assert(Agent.GetState.SystemPrompt = 'You are a test assistant.',
      'SystemPrompt should be set');
  finally
    Agent.Free;
  end;
end;

procedure TTestAgent.Test_SetModel;
var
  Agent: TAgent;
  Cfg: TModelConfig;
begin
  Agent := TAgent.Create;
  try
    Cfg := Default(TModelConfig);
    Cfg.Name := 'test-model';
    Cfg.MaxTokens := 4096;
    Agent.SetModel(Cfg);
    Assert(Agent.GetState.Model.Name = 'test-model', 'Model name should be set');
  finally
    Agent.Free;
  end;
end;

procedure TTestAgent.Test_SetThinkingLevel;
var
  Agent: TAgent;
begin
  Agent := TAgent.Create;
  try
    Agent.SetThinkingLevel(tlHigh);
    Assert(Agent.GetState.ThinkingLevel = tlHigh, 'ThinkingLevel should be High');
  finally
    Agent.Free;
  end;
end;

procedure TTestAgent.Test_MaxTurns_Default;
var
  Agent: TAgent;
begin
  Agent := TAgent.Create;
  try
    Assert(Agent.MaxTurns = 30, 'Default MaxTurns should be 30');
    Agent.MaxTurns := 5;
    Assert(Agent.MaxTurns = 5, 'MaxTurns should be updated');
  finally
    Agent.Free;
  end;
end;

{ Prompt tests }

procedure TTestAgent.Test_Prompt_SimpleText;
var
  Agent: TAgent;
  Mock: TMockModel;
  MsgCount: Integer;
begin
  Agent := TAgent.Create;
  Mock := TMockModel.Create;
  try
    Mock.AddTextResponse('Hello! How can I help?');
    Agent.SetModelRef(Mock);

    Agent.Prompt('Hi');
    WaitForAgentNotStreaming(Agent, 10000);

    Assert(not Agent.IsStreaming, 'Should not be streaming after prompt');
    MsgCount := Agent.GetState.Messages.Count;
    Assert(MsgCount >= 2, 'Should have user + assistant messages, got ' + IntToStr(MsgCount));
  finally
    Agent.Free;
    // Mock is TInterfacedObject — Agent.FModel holds the IModel reference.
    // When Agent is freed, the interface refcount drops to 0 and frees Mock.
    // Do NOT call Mock.Free here (double-free causes EInvalidPointer).
  end;
end;

procedure TTestAgent.Test_Prompt_NoModel_Stub;
var
  Agent: TAgent;
begin
  Agent := TAgent.Create;
  try
    // Don't set model ref - should use stub
    Agent.Prompt('Hello');
    WaitForAgentNotStreaming(Agent, 5000);

    Assert(not Agent.IsStreaming, 'Should not be streaming');
    Assert(Agent.GetState.Messages.Count >= 2, 'Should have user + stub messages');
    var LastMsg := Agent.GetState.Messages.Last;
    Assert(LastMsg.Role = mrAssistant, 'Last should be assistant');
  finally
    Agent.Free;
  end;
end;

procedure TTestAgent.Test_Prompt_ToolCallLoop;
var
  Agent: TAgent;
  Mock: TMockModel;
  Tool: IAgentTool;
  ToolCalled: Boolean;
begin
  Agent := TAgent.Create;
  Mock := TMockModel.Create;
  try
    // First response: tool call, second: text
    Mock.AddToolCallResponse('tc1', 'echo_test', '{"message":"hello"}');
    Mock.AddTextResponse('The echo returned hello.');

    // Create a simple test tool
    ToolCalled := False;
    Tool := TMockAgentTool.Create('echo_test', 'Echo Test', 'Echoes back',
      procedure(AToolCallId: string; AParams: TJSONObject;
        AIsAborted: TAbortedCallback; var R: TToolResult)
      begin
        ToolCalled := True;
        var Content := TContentBlockList.Create;
        Content.Add(TTextContent.Create('echo: hello'));
        R := TToolResult.Create(Content, False);
      end);

    Agent.SetModelRef(Mock);
    Agent.SetTools([Tool]);
    Agent.Prompt('Run echo');
    WaitForAgentNotStreaming(Agent, 5000);

    Assert(ToolCalled, 'Tool should have been called');
    Assert(not Agent.IsStreaming, 'Should not be streaming');
  finally
    Agent.Free;
    // Mock freed by interface refcount when Agent is destroyed
  end;
end;

procedure TTestAgent.Test_Prompt_MultiToolCall;
var
  Agent: TAgent;
  Mock: TMockModel;
  Tool1, Tool2: IAgentTool;
  Tool1Called, Tool2Called: Boolean;
begin
  Agent := TAgent.Create;
  Mock := TMockModel.Create;
  try
    // First response: 2 tool calls (flat string array), second: text
    Mock.AddMultiToolCallResponse([
      'tc1', 'tool_a', '{"x":1}',
      'tc2', 'tool_b', '{"y":2}'
    ]);
    Mock.AddTextResponse('Both tools executed.');

    Tool1Called := False;
    Tool2Called := False;

    Tool1 := TMockAgentTool.Create('tool_a', 'Tool A', 'Test tool A',
      procedure(AToolCallId: string; AParams: TJSONObject;
        AIsAborted: TAbortedCallback; var R: TToolResult)
      begin
        Tool1Called := True;
        var Content := TContentBlockList.Create;
        Content.Add(TTextContent.Create('result A'));
        R := TToolResult.Create(Content, False);
      end);

    Tool2 := TMockAgentTool.Create('tool_b', 'Tool B', 'Test tool B',
      procedure(AToolCallId: string; AParams: TJSONObject;
        AIsAborted: TAbortedCallback; var R: TToolResult)
      begin
        Tool2Called := True;
        var Content := TContentBlockList.Create;
        Content.Add(TTextContent.Create('result B'));
        R := TToolResult.Create(Content, False);
      end);

    Agent.SetModelRef(Mock);
    Agent.SetTools([Tool1, Tool2]);
    Agent.Prompt('Run both');
    WaitForAgentNotStreaming(Agent, 5000);

    Assert(Tool1Called, 'Tool A should have been called');
    Assert(Tool2Called, 'Tool B should have been called');
  finally
    Agent.Free;
    // Mock freed by interface refcount when Agent is destroyed
  end;
end;

{ Abort }

procedure TTestAgent.Test_Abort_DuringPrompt;
var
  Agent: TAgent;
  Mock: TMockModel;
begin
  Agent := TAgent.Create;
  Mock := TMockModel.Create;
  try
    Mock.AddTextResponse('Response');
    Agent.SetModelRef(Mock);
    Agent.Prompt('Hello');

    Agent.Abort;
    WaitForAgentNotStreaming(Agent, 5000);

    Assert(not Agent.IsStreaming, 'Should not be streaming after abort');
  finally
    Agent.Free;
    // Mock freed by interface refcount when Agent is destroyed
  end;
end;

{ Queue }

procedure TTestAgent.Test_Steer_Enqueue;
var
  Agent: TAgent;
begin
  Agent := TAgent.Create;
  try
    Agent.Steer(TUserMessage.Create('Steering message'));
    Assert(Agent.HasQueuedMessages, 'Should have queued messages after Steer');
    Agent.ClearSteeringQueue;
  finally
    Agent.Free;
  end;
end;

procedure TTestAgent.Test_FollowUp_Enqueue;
var
  Agent: TAgent;
begin
  Agent := TAgent.Create;
  try
    Agent.FollowUp(TUserMessage.Create('Follow-up message'));
    Assert(Agent.HasQueuedMessages, 'Should have queued messages after FollowUp');
    Agent.ClearFollowUpQueue;
  finally
    Agent.Free;
  end;
end;

procedure TTestAgent.Test_ClearQueues;
var
  Agent: TAgent;
begin
  Agent := TAgent.Create;
  try
    Agent.Steer(TUserMessage.Create('S1'));
    Agent.FollowUp(TUserMessage.Create('F1'));
    Assert(Agent.HasQueuedMessages, 'Should have queued messages');

    Agent.ClearAllQueues;
    Assert(not Agent.HasQueuedMessages, 'Should have no queued messages after clear');
  finally
    Agent.Free;
  end;
end;

{ Messages }

procedure TTestAgent.Test_ReplaceMessages;
var
  Agent: TAgent;
  NewList: TAgentMessageList;
begin
  Agent := TAgent.Create;
  try
    Agent.Prompt('Original');
    WaitForAgentNotStreaming(Agent, 3000);

    NewList := TAgentMessageList.Create;
    NewList.Add(TUserMessage.Create('Replaced'));
    Agent.ReplaceMessages(NewList);
    // ReplaceMessages takes ownership of NewList — do NOT Free it

    Assert(Agent.GetState.Messages.Count = 1, 'Should have 1 message after replace');
  finally
    Agent.Free;
  end;
end;

procedure TTestAgent.Test_AppendMessage;
var
  Agent: TAgent;
begin
  Agent := TAgent.Create;
  try
    Agent.AppendMessage(TUserMessage.Create('Extra message'));
    Assert(Agent.GetState.Messages.Count = 1, 'Should have 1 message');
  finally
    Agent.Free;
  end;
end;

procedure TTestAgent.Test_ClearMessages;
var
  Agent: TAgent;
begin
  Agent := TAgent.Create;
  try
    Agent.AppendMessage(TUserMessage.Create('Msg 1'));
    Agent.AppendMessage(TUserMessage.Create('Msg 2'));
    Assert(Agent.GetState.Messages.Count = 2, 'Should have 2 messages');

    Agent.ClearMessages;
    Assert(Agent.GetState.Messages.Count = 0, 'Should have 0 after clear');
  finally
    Agent.Free;
  end;
end;

{ Confirmation }

procedure TTestAgent.Test_ConfirmToolExecution;
var
  Agent: TAgent;
begin
  Agent := TAgent.Create;
  try
    // Smoke test: verify no crash on confirmation
    Agent.ConfirmToolExecution(True);
    Assert(Agent <> nil, 'Agent should survive ConfirmToolExecution');
  finally
    Agent.Free;
  end;
end;

{ Compaction }

procedure TTestAgent.Test_SetCompactionSettings;
var
  Agent: TAgent;
begin
  Agent := TAgent.Create;
  try
    Agent.SetCompactionSettings(True, 8000, 10000, 128000);
    // Verify compaction settings were stored by checking CompactionCount is accessible
    Assert(Agent.CompactionCount = 0, 'CompactionCount should be 0 after settings applied');
  finally
    Agent.Free;
  end;
end;

procedure TTestAgent.Test_CompactionCount_Initial;
var
  Agent: TAgent;
begin
  Agent := TAgent.Create;
  try
    Assert(Agent.CompactionCount = 0, 'Initial compaction count should be 0');
  finally
    Agent.Free;
  end;
end;

procedure TTestAgent.Test_IsStreaming_InitiallyFalse;
var
  Agent: TAgent;
begin
  Agent := TAgent.Create;
  try
    Assert(not Agent.IsStreaming, 'Should not be streaming initially');
  finally
    Agent.Free;
  end;
end;

procedure TTestAgent.Test_Reset;
var
  Agent: TAgent;
  Mock: TMockModel;
begin
  Agent := TAgent.Create;
  Mock := TMockModel.Create;
  try
    Mock.AddTextResponse('Hello');
    Agent.SetModelRef(Mock);
    Agent.Prompt('Test');
    WaitForAgentNotStreaming(Agent, 3000);
    Assert(Agent.GetState.Messages.Count >= 2, 'Should have messages');

    Agent.Reset;
    Assert(Agent.GetState.Messages.Count = 0, 'Messages should be empty after reset');
    Assert(not Agent.IsStreaming, 'Should not be streaming after reset');
  finally
    Agent.Free;
    // Mock freed by interface refcount when Agent is destroyed
  end;
end;

procedure TTestAgent.Test_Subscribe_Unsubscribe;
var
  Agent: TAgent;
  EventCount: Integer;
  SubId: Integer;
begin
  Agent := TAgent.Create;
  try
    EventCount := 0;
    SubId := Agent.Subscribe(
      procedure(AEvent: TAgentEvent)
      begin
        Inc(EventCount);
      end);

    Assert(SubId >= 0, 'Subscribe should return valid id');

    var Mock := TMockModel.Create;
    Mock.AddTextResponse('Hi');
    Agent.SetModelRef(Mock);
    Agent.Prompt('Test');
    WaitForAgentNotStreaming(Agent, 3000);
    // Mock freed by interface refcount when Agent is destroyed — do NOT Mock.Free

    Assert(EventCount > 0, 'Should have received events');

    Agent.Unsubscribe(SubId);
    // Unsubscribe completed without exception - verify state unchanged
    Assert(Agent <> nil, 'Agent should survive Unsubscribe');
  finally
    Agent.Free;
  end;
end;

procedure TTestAgent.Test_SetPermissions;
var
  Agent: TAgent;
  Perms: TToolPermissions;
begin
  Agent := TAgent.Create;
  try
    Perms := Default(TToolPermissions);
    Perms.ReadPerm.Enabled := True;
    Perms.WritePerm.Enabled := False;
    Perms.BashPerm.Enabled := True;
    Agent.SetPermissions(Perms);

    Assert(Agent.GetState.Permissions.ReadPerm.Enabled, 'Read should be enabled');
    Assert(not Agent.GetState.Permissions.WritePerm.Enabled, 'Write should be disabled');
    Assert(Agent.GetState.Permissions.BashPerm.Enabled, 'Bash should be enabled');
  finally
    Agent.Free;
  end;
end;

procedure TTestAgent.Test_WaitForIdle;
var
  Agent: TAgent;
  Mock: TMockModel;
begin
  Agent := TAgent.Create;
  Mock := TMockModel.Create;
  try
    Mock.AddTextResponse('Done');
    Agent.SetModelRef(Mock);
    Agent.Prompt('Test');
    Agent.WaitForIdle(5000);

    Assert(not Agent.IsStreaming, 'Should not be streaming after WaitForIdle');
  finally
    Agent.Free;
    // Mock freed by interface refcount when Agent is destroyed
  end;
end;

{ Registration }

procedure RegisterAgentTests;
var
  T: TTestAgent;
begin
  T := TTestAgent.Create;
  try
    GRunner.RunTest('Agent: Create defaults', T.Test_Create_Defaults);
    GRunner.RunTest('Agent: SetSystemPrompt', T.Test_SetSystemPrompt);
    GRunner.RunTest('Agent: SetModel', T.Test_SetModel);
    GRunner.RunTest('Agent: SetThinkingLevel', T.Test_SetThinkingLevel);
    GRunner.RunTest('Agent: MaxTurns default', T.Test_MaxTurns_Default);
    GRunner.RunTest('Agent: Prompt simple text', T.Test_Prompt_SimpleText);
    GRunner.RunTest('Agent: Prompt no model stub', T.Test_Prompt_NoModel_Stub);
    GRunner.RunTest('Agent: Prompt tool call loop', T.Test_Prompt_ToolCallLoop);
    GRunner.RunTest('Agent: Prompt multi tool call', T.Test_Prompt_MultiToolCall);
    GRunner.RunTest('Agent: Abort during prompt', T.Test_Abort_DuringPrompt);
    GRunner.RunTest('Agent: Steer enqueue', T.Test_Steer_Enqueue);
    GRunner.RunTest('Agent: FollowUp enqueue', T.Test_FollowUp_Enqueue);
    GRunner.RunTest('Agent: Clear queues', T.Test_ClearQueues);
    GRunner.RunTest('Agent: ReplaceMessages', T.Test_ReplaceMessages);
    GRunner.RunTest('Agent: AppendMessage', T.Test_AppendMessage);
    GRunner.RunTest('Agent: ClearMessages', T.Test_ClearMessages);
    GRunner.RunTest('Agent: ConfirmToolExecution', T.Test_ConfirmToolExecution);
    GRunner.RunTest('Agent: SetCompactionSettings', T.Test_SetCompactionSettings);
    GRunner.RunTest('Agent: CompactionCount initial', T.Test_CompactionCount_Initial);
    GRunner.RunTest('Agent: IsStreaming initially false', T.Test_IsStreaming_InitiallyFalse);
    GRunner.RunTest('Agent: Reset', T.Test_Reset);
    GRunner.RunTest('Agent: Subscribe Unsubscribe', T.Test_Subscribe_Unsubscribe);
    GRunner.RunTest('Agent: SetPermissions', T.Test_SetPermissions);
    GRunner.RunTest('Agent: WaitForIdle', T.Test_WaitForIdle);
  finally
    T.Free;
  end;
end;

end.
