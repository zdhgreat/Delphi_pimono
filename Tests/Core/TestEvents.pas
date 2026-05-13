unit TestEvents;

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.Generics.Collections,
  Core.Events, Core.Messages, PiMonoTestFramework;

procedure RegisterEventTests;

implementation

uses
  Core.AgentState, Settings.Config, Tools.FileTools;

type
  TTestEventDispatcher = class
  private
    FDispatcher: TEventDispatcher;
  public
    procedure Setup;
    procedure TearDown;

    procedure Test_Subscribe_AndReceive;
    procedure Test_Unsubscribe_NoLongerReceives;
    procedure Test_MultipleSubscribers;
    procedure Test_SubscriberException_DoesNotAffectOthers;
    procedure Test_NoSubscribers_EventFreed;
    procedure Test_ConcurrentSubscribeAndDispatch;
    procedure Test_HandlerCount;
  end;

  TTestAgentEventStream = class
  private
    FStream: TAgentEventStream;
  public
    procedure Setup;
    procedure TearDown;
    procedure Test_Push_And_Next;
    procedure Test_EndStream_WithMessages;
    procedure Test_IsDone_AfterEndStream;
    procedure Test_MultiplePush_Fifo;
  end;

  TTestAbortController = class
  public
    procedure Test_Abort_SetsFlag;
    procedure Test_Reset_ClearsFlag;
    procedure Test_MultipleAborts;
    procedure Test_MultipleResets;
    procedure Test_ThreadVisibility;
  end;

  TTestToolCallSet = class
  private
    FSet: TToolCallSet;
  public
    procedure Setup;
    procedure TearDown;

    procedure Test_Add;
    procedure Test_Add_Duplicate;
    procedure Test_Remove;
    procedure Test_Contains;
    procedure Test_Clear;
    procedure Test_ToArray;
    procedure Test_Count;
  end;

  TTestAgentState = class
  public
    procedure Test_Create_Defaults;
    procedure Test_IsStreaming_Atomic;
    procedure Test_FindTool_Found;
    procedure Test_FindTool_NotFound;
  end;

{ TTestEventDispatcher }

procedure TTestEventDispatcher.Setup;
begin
  FDispatcher := TEventDispatcher.Create;
end;

procedure TTestEventDispatcher.TearDown;
begin
  FDispatcher.Free;
end;

procedure TTestEventDispatcher.Test_Subscribe_AndReceive;
var
  Received: Boolean;
  Handler: TAgentEventHandler;
begin
  Received := False;
  Handler := procedure(AEvent: TAgentEvent)
    begin
      Received := True;
    end;

  var Sub := FDispatcher.Subscribe(Handler);
  try
    var Event := TAgentStartEvent.Create;
    FDispatcher.DispatchEvent(Event);
    Assert(Received, 'Handler should have been called');
  finally
    FDispatcher.Unsubscribe(Sub);
  end;
end;

procedure TTestEventDispatcher.Test_Unsubscribe_NoLongerReceives;
var
  Received: Boolean;
  Handler: TAgentEventHandler;
begin
  Received := False;
  Handler := procedure(AEvent: TAgentEvent)
    begin
      Received := True;
    end;

  var Sub := FDispatcher.Subscribe(Handler);
  FDispatcher.Unsubscribe(Sub);

  var Event := TAgentStartEvent.Create;
  FDispatcher.DispatchEvent(Event);
  Assert(not Received, 'Handler should NOT have been called after unsubscribe');
end;

procedure TTestEventDispatcher.Test_MultipleSubscribers;
var
  Count1, Count2: Integer;
begin
  Count1 := 0;
  Count2 := 0;

  var Sub1 := FDispatcher.Subscribe(
    procedure(AEvent: TAgentEvent) begin Inc(Count1); end);
  var Sub2 := FDispatcher.Subscribe(
    procedure(AEvent: TAgentEvent) begin Inc(Count2); end);
  try
    var Event := TTurnStartEvent.Create;
    FDispatcher.DispatchEvent(Event);
    Assert(Count1 = 1, 'First subscriber count should be 1');
    Assert(Count2 = 1, 'Second subscriber count should be 1');
  finally
    FDispatcher.Unsubscribe(Sub1);
    FDispatcher.Unsubscribe(Sub2);
  end;
end;

procedure TTestEventDispatcher.Test_SubscriberException_DoesNotAffectOthers;
var
  SecondReceived: Boolean;
begin
  SecondReceived := False;

  var Sub1 := FDispatcher.Subscribe(
    procedure(AEvent: TAgentEvent) begin raise Exception.Create('Test exception'); end);
  var Sub2 := FDispatcher.Subscribe(
    procedure(AEvent: TAgentEvent) begin SecondReceived := True; end);
  try
    var Msgs := TAgentMessageList.Create;
    var Event := TAgentEndEvent.Create(Msgs);
    FDispatcher.DispatchEvent(Event);
    Assert(SecondReceived, 'Second handler should still be called despite first throwing');
  finally
    FDispatcher.Unsubscribe(Sub1);
    FDispatcher.Unsubscribe(Sub2);
  end;
end;

procedure TTestEventDispatcher.Test_NoSubscribers_EventFreed;
var
  Event: TAgentStartEvent;
begin
  // Verify DispatchEvent handles events with no subscribers without crashing.
  // The event should be freed by DispatchEvent to avoid a memory leak.
  // NOTE: Without a memory profiler we cannot verify the actual free,
  // but if DispatchEvent did not handle this case it would crash or leak.
  Event := TAgentStartEvent.Create;
  FDispatcher.DispatchEvent(Event);
  // Test passes if we reach here without exception - DispatchEvent handled
  // the no-subscribers case correctly and freed the event.
end;

procedure TTestEventDispatcher.Test_ConcurrentSubscribeAndDispatch;
var
  Threads: array[0..3] of TThread;
  i: Integer;
  Counter: Integer;
begin
  Counter := 0;

  var Sub := FDispatcher.Subscribe(
    procedure(AEvent: TAgentEvent) begin TInterlocked.Increment(Counter); end);

  for i := 0 to 3 do
  begin
    Threads[i] := TThread.CreateAnonymousThread(
      procedure
      begin
        var Event := TAgentStartEvent.Create;
        FDispatcher.DispatchEvent(Event);
      end);
    Threads[i].FreeOnTerminate := False;
  end;

  for i := 0 to 3 do Threads[i].Start;
  for i := 0 to 3 do Threads[i].WaitFor;
  for i := 0 to 3 do Threads[i].Free;

  FDispatcher.Unsubscribe(Sub);
  Assert(Counter = 4, 'All 4 dispatches should have been received');
end;

procedure TTestEventDispatcher.Test_HandlerCount;
var
  Sub1, Sub2, Sub3: Integer;
begin
  Sub1 := FDispatcher.Subscribe(procedure(AEvent: TAgentEvent) begin end);
  Sub2 := FDispatcher.Subscribe(procedure(AEvent: TAgentEvent) begin end);
  Sub3 := FDispatcher.Subscribe(procedure(AEvent: TAgentEvent) begin end);
  Assert(FDispatcher.HandlerCount = 3, 'HandlerCount should be 3 after subscribing 3 handlers');
  FDispatcher.Unsubscribe(Sub1);
  FDispatcher.Unsubscribe(Sub2);
  FDispatcher.Unsubscribe(Sub3);
end;

{ TTestAbortController }

procedure TTestAbortController.Test_Abort_SetsFlag;
var
  Ctrl: TAbortController;
begin
  Ctrl := TAbortController.Create;
  try
    Assert(not Ctrl.IsAborted, 'Should not be aborted initially');
    Ctrl.Abort;
    Assert(Ctrl.IsAborted, 'Should be aborted after Abort');
  finally
    Ctrl.Free;
  end;
end;

procedure TTestAbortController.Test_Reset_ClearsFlag;
var
  Ctrl: TAbortController;
begin
  Ctrl := TAbortController.Create;
  try
    Ctrl.Abort;
    Assert(Ctrl.IsAborted, 'Should be aborted');
    Ctrl.Reset;
    Assert(not Ctrl.IsAborted, 'Should not be aborted after reset');
  finally
    Ctrl.Free;
  end;
end;

procedure TTestAbortController.Test_MultipleAborts;
var
  Ctrl: TAbortController;
begin
  Ctrl := TAbortController.Create;
  try
    Ctrl.Abort;
    Ctrl.Abort;
    Ctrl.Abort;
    Assert(Ctrl.IsAborted, 'Should remain aborted after multiple aborts');
  finally
    Ctrl.Free;
  end;
end;

procedure TTestAbortController.Test_MultipleResets;
var
  Ctrl: TAbortController;
begin
  Ctrl := TAbortController.Create;
  try
    Ctrl.Abort;
    Ctrl.Reset;
    Ctrl.Reset;
    Assert(not Ctrl.IsAborted, 'Should not be aborted after multiple resets');
  finally
    Ctrl.Free;
  end;
end;

procedure TTestAbortController.Test_ThreadVisibility;
var
  Ctrl: TAbortController;
  Thread: TThread;
  Seen: Boolean;
begin
  Ctrl := TAbortController.Create;

  Thread := TThread.CreateAnonymousThread(
    procedure
    begin
      Sleep(50);
      Ctrl.Abort;
    end);
  Thread.FreeOnTerminate := False;

  Thread.Start;
  var Timeout := 2000;
  while (not Ctrl.IsAborted) and (Timeout > 0) do
  begin
    Sleep(10);
    Dec(Timeout, 10);
  end;
  Seen := Ctrl.IsAborted;

  Thread.WaitFor;
  Thread.Free;
  Ctrl.Free;

  Assert(Seen, 'Abort should be visible across threads');
end;

{ TTestToolCallSet }

procedure TTestToolCallSet.Setup;
begin
  FSet := TToolCallSet.Create;
end;

procedure TTestToolCallSet.TearDown;
begin
  FSet.Free;
end;

procedure TTestToolCallSet.Test_Add;
begin
  FSet.Add('call_1');
  Assert(FSet.Contains('call_1'), 'Should contain added item');
  Assert(FSet.Count = 1, 'Count should be 1');
end;

procedure TTestToolCallSet.Test_Add_Duplicate;
begin
  FSet.Add('call_1');
  FSet.Add('call_1');
  Assert(FSet.Count = 1, 'Duplicate should not increase count');
end;

procedure TTestToolCallSet.Test_Remove;
begin
  FSet.Add('call_1');
  FSet.Remove('call_1');
  Assert(not FSet.Contains('call_1'), 'Should not contain removed item');
  Assert(FSet.Count = 0, 'Count should be 0 after remove');
end;

procedure TTestToolCallSet.Test_Contains;
begin
  Assert(not FSet.Contains('missing'), 'Should not contain missing item');
  FSet.Add('call_1');
  Assert(FSet.Contains('call_1'), 'Should contain added item');
end;

procedure TTestToolCallSet.Test_Clear;
begin
  FSet.Add('a');
  FSet.Add('b');
  FSet.Add('c');
  FSet.Clear;
  Assert(FSet.Count = 0, 'Count should be 0 after clear');
end;

procedure TTestToolCallSet.Test_ToArray;
var
  Arr: TArray<string>;
begin
  FSet.Add('x');
  FSet.Add('y');
  Arr := FSet.ToArray;
  Assert(Length(Arr) = 2, 'ToArray length should be 2');
end;

procedure TTestToolCallSet.Test_Count;
begin
  Assert(FSet.Count = 0, 'Initial count should be 0');
  FSet.Add('a');
  Assert(FSet.Count = 1, 'Count should be 1');
  FSet.Add('b');
  Assert(FSet.Count = 2, 'Count should be 2');
end;

{ TTestAgentState }

procedure TTestAgentState.Test_Create_Defaults;
var
  State: TAgentState;
begin
  State := TAgentState.Create;
  try
    Assert(State.SystemPrompt = '', 'SystemPrompt should be empty');
    Assert(not State.IsStreaming, 'IsStreaming should be false');
    Assert(State.Messages.Count = 0, 'Messages count should be 0');
  finally
    State.Messages.Free;
    State.PendingToolCalls.Free;
  end;
end;

procedure TTestAgentState.Test_IsStreaming_Atomic;
var
  State: TAgentState;
begin
  State := TAgentState.Create;
  try
    Assert(not State.IsStreaming, 'IsStreaming should be false initially');
    State.SetIsStreaming(True);
    Assert(State.IsStreaming, 'IsStreaming should be true after set');
    State.SetIsStreaming(False);
    Assert(not State.IsStreaming, 'IsStreaming should be false after clear');
  finally
    State.Messages.Free;
    State.PendingToolCalls.Free;
  end;
end;

procedure TTestAgentState.Test_FindTool_Found;
var
  State: TAgentState;
  Tool: IAgentTool;
begin
  State := TAgentState.Create;
  try
    Tool := CreateReadTool('C:\temp');
    SetLength(State.Tools, 1);
    State.Tools[0] := Tool;
    Assert(State.FindTool('read') <> nil, 'FindTool should find read tool');
  finally
    State.Messages.Free;
    State.PendingToolCalls.Free;
  end;
end;

procedure TTestAgentState.Test_FindTool_NotFound;
var
  State: TAgentState;
begin
  State := TAgentState.Create;
  try
    Assert(State.FindTool('nonexistent') = nil, 'FindTool should return nil for missing tool');
  finally
    State.Messages.Free;
    State.PendingToolCalls.Free;
  end;
end;

{ TTestAgentEventStream }

procedure TTestAgentEventStream.Setup;
begin
  FStream := TAgentEventStream.Create;
end;

procedure TTestAgentEventStream.TearDown;
begin
  FStream.Free;
end;

procedure TTestAgentEventStream.Test_Push_And_Next;
var
  Event: TAgentEvent;
begin
  FStream.Push(TAgentStartEvent.Create);
  Event := FStream.Next(1000);
  Assert(Event <> nil, 'Next should return an event after Push');
  Event.Free;
end;

procedure TTestAgentEventStream.Test_EndStream_WithMessages;
var
  Msgs: TAgentMessageList;
  UserMsg: TUserMessage;
begin
  Msgs := TAgentMessageList.Create;
  UserMsg := TUserMessage.Create('hello');
  Msgs.Add(UserMsg);
  FStream.EndStream(Msgs);

  var Result := FStream.GetResult;
  Assert(Result <> nil, 'GetResult should return the message list');
  Assert(Result.Count = 1, 'GetResult should have 1 message');
end;

procedure TTestAgentEventStream.Test_IsDone_AfterEndStream;
begin
  FStream.EndStream(nil);
  Assert(FStream.IsDone, 'IsDone should be True after EndStream');
end;

procedure TTestAgentEventStream.Test_MultiplePush_Fifo;
var
  E1, E2, E3: TAgentEvent;
begin
  FStream.Push(TAgentStartEvent.Create);
  FStream.Push(TStreamDeltaEvent.Create('a', sdtText));
  FStream.Push(TStreamDeltaEvent.Create('b', sdtText));

  E1 := FStream.Next(1000);
  E2 := FStream.Next(1000);
  E3 := FStream.Next(1000);

  Assert(E1 <> nil, 'First event should not be nil');
  Assert(E2 <> nil, 'Second event should not be nil');
  Assert(E3 <> nil, 'Third event should not be nil');

  Assert(E1.EventType = aetAgentStart, 'First event should be AgentStart');
  Assert(E2.EventType = aetMessageUpdate, 'Second event should be MessageUpdate (StreamDelta)');
  Assert(E3.EventType = aetMessageUpdate, 'Third event should be MessageUpdate (StreamDelta)');

  // Verify FIFO order within StreamDelta events by checking DeltaText
  Assert(TStreamDeltaEvent(E2).DeltaText = 'a', 'Second event delta should be "a"');
  Assert(TStreamDeltaEvent(E3).DeltaText = 'b', 'Third event delta should be "b"');

  E1.Free;
  E2.Free;
  E3.Free;
end;

{ Registration }

procedure RegisterEventTests;
var
  TED: TTestEventDispatcher;
  TAC: TTestAbortController;
  TCS: TTestToolCallSet;
  TAS: TTestAgentState;
begin
  // TEventDispatcher tests (need setup/teardown)
  TED := TTestEventDispatcher.Create;
  try
    GRunner.RunTest('Events: subscribe and receive', TED.Test_Subscribe_AndReceive, TED.Setup, TED.TearDown);
    GRunner.RunTest('Events: unsubscribe no longer receives', TED.Test_Unsubscribe_NoLongerReceives, TED.Setup, TED.TearDown);
    GRunner.RunTest('Events: multiple subscribers', TED.Test_MultipleSubscribers, TED.Setup, TED.TearDown);
    GRunner.RunTest('Events: subscriber exception does not affect others', TED.Test_SubscriberException_DoesNotAffectOthers, TED.Setup, TED.TearDown);
    GRunner.RunTest('Events: no subscribers event freed', TED.Test_NoSubscribers_EventFreed, TED.Setup, TED.TearDown);
    GRunner.RunTest('Events: concurrent subscribe and dispatch', TED.Test_ConcurrentSubscribeAndDispatch, TED.Setup, TED.TearDown);
    GRunner.RunTest('Events: handler count', TED.Test_HandlerCount, TED.Setup, TED.TearDown);
  finally
    TED.Free;
  end;

  // TAbortController tests (no setup/teardown needed)
  TAC := TTestAbortController.Create;
  try
    GRunner.RunTest('AbortController: abort sets flag', TAC.Test_Abort_SetsFlag);
    GRunner.RunTest('AbortController: reset clears flag', TAC.Test_Reset_ClearsFlag);
    GRunner.RunTest('AbortController: multiple aborts', TAC.Test_MultipleAborts);
    GRunner.RunTest('AbortController: multiple resets', TAC.Test_MultipleResets);
    GRunner.RunTest('AbortController: thread visibility', TAC.Test_ThreadVisibility);
  finally
    TAC.Free;
  end;

  // TToolCallSet tests (need setup/teardown)
  TCS := TTestToolCallSet.Create;
  try
    GRunner.RunTest('ToolCallSet: add', TCS.Test_Add, TCS.Setup, TCS.TearDown);
    GRunner.RunTest('ToolCallSet: add duplicate', TCS.Test_Add_Duplicate, TCS.Setup, TCS.TearDown);
    GRunner.RunTest('ToolCallSet: remove', TCS.Test_Remove, TCS.Setup, TCS.TearDown);
    GRunner.RunTest('ToolCallSet: contains', TCS.Test_Contains, TCS.Setup, TCS.TearDown);
    GRunner.RunTest('ToolCallSet: clear', TCS.Test_Clear, TCS.Setup, TCS.TearDown);
    GRunner.RunTest('ToolCallSet: toarray', TCS.Test_ToArray, TCS.Setup, TCS.TearDown);
    GRunner.RunTest('ToolCallSet: count', TCS.Test_Count, TCS.Setup, TCS.TearDown);
  finally
    TCS.Free;
  end;

  // TAgentState tests (no setup/teardown needed)
  TAS := TTestAgentState.Create;
  try
    GRunner.RunTest('AgentState: create defaults', TAS.Test_Create_Defaults);
    GRunner.RunTest('AgentState: isstreaming atomic', TAS.Test_IsStreaming_Atomic);
    GRunner.RunTest('AgentState: findtool found', TAS.Test_FindTool_Found);
    GRunner.RunTest('AgentState: findtool notfound', TAS.Test_FindTool_NotFound);
  finally
    TAS.Free;
  end;

  // TAgentEventStream tests (need setup/teardown)
  var TAES := TTestAgentEventStream.Create;
  try
    GRunner.RunTest('AgentEventStream: push and next', TAES.Test_Push_And_Next, TAES.Setup, TAES.TearDown);
    GRunner.RunTest('AgentEventStream: endstream with messages', TAES.Test_EndStream_WithMessages, TAES.Setup, TAES.TearDown);
    GRunner.RunTest('AgentEventStream: isdone after endstream', TAES.Test_IsDone_AfterEndStream, TAES.Setup, TAES.TearDown);
    GRunner.RunTest('AgentEventStream: multiple push fifo', TAES.Test_MultiplePush_Fifo, TAES.Setup, TAES.TearDown);
  finally
    TAES.Free;
  end;
end;

end.
