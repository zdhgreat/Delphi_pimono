unit Core.Agent;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.SyncObjs,
  System.Generics.Collections, System.Math,
  Core.Messages, Core.Events, Core.AgentState, Settings.Config,
  AI.IModel, AI.ModelConfig,
  Utils.Logger, Utils.TokenEstimator, Utils.JsonHelper,
  Core.ToolResultSlim, Core.Compaction;

type
  TAgent = class
  private
    FState: TAgentState;
    FEventDispatcher: TEventDispatcher;
    FAbortController: TAbortController;
    FSteeringQueue: TAgentMessageList;
    FFollowUpQueue: TAgentMessageList;
    FLogger: TLogger;
    FIdleEvent: TEvent;
    FConfirmationEvent: TEvent;
    FConfirmationResult: Boolean;
    FModel: IModel;
    FCompactionCount: Integer;
    FMaxCompactionRetries: Integer;
    FLastSummary: string;
    FCompactionEnabled: Boolean;
    FReserveTokens: Integer;
    FKeepRecentTokens: Integer;
    FContextWindow: Integer;
    FMaxTurns: Integer;
    FTurnCount: Integer;
    FStateLock: TObject;

    function DefaultConvertToLlm(
      AMessages: TArray<TAgentMessage>): TArray<TAgentMessage>;

    procedure DoPrompt(const AMessages: TArray<TAgentMessage>);
    function BuildCompletionRequest: TCompletionRequest;
    procedure ProcessStreamCallback(AEvent: TAssistantMessageEvent;
      var AStreamingAssistant: TAssistantMessage;
      var AOverflowRetry: Boolean);
    procedure ExecuteToolCalls(const AToolCalls: TArray<TToolCall>;
      out AToolResults: TArray<TToolResultMessage>);
    procedure RunInBackground(const AMessages: TArray<TAgentMessage>);
    procedure EmitAgentStart;
    procedure EmitAgentEnd;
    procedure EmitTurnStart;
    procedure EmitTurnEnd(AMessage: TAssistantMessage;
      const AToolResults: TArray<TToolResultMessage>);
    procedure EmitMessageStart(AMessage: TAgentMessage);
    procedure EmitMessageEnd(AMessage: TAgentMessage);

    function CheckAndCompact: Boolean;
    class function GetPermissionForToolName(const AToolName: string;
      const APerms: TToolPermissions): TToolPermission; static;

  public
    procedure SetCompactionSettings(AEnabled: Boolean;
      AReserveTokens, AKeepRecentTokens, AContextWindow: Integer);
    constructor Create(ALogger: TLogger = nil); overload;
    constructor Create(const AInitialState: TAgentState;
      ALogger: TLogger = nil); overload;
    destructor Destroy; override;

    // Subscription
    function Subscribe(AHandler: TAgentEventHandler): Integer;
    procedure Unsubscribe(AId: Integer);

    // State accessors
    function GetState: TAgentState;
    function GetIsStreaming: Boolean;
    procedure SetSystemPrompt(const AValue: string);
    procedure SetModel(const AModel: TModelConfig);
    procedure SetThinkingLevel(ALevel: TThinkingLevel);
    procedure SetTools(const ATools: TArray<IAgentTool>);
    procedure SetPermissions(const APerms: TToolPermissions);
    procedure SetModelRef(AModel: IModel);
    procedure ReplaceMessages(AMessages: TAgentMessageList);
    procedure AppendMessage(AMessage: TAgentMessage);
    procedure ClearMessages;

    // Queuing
    procedure Steer(AMessage: TAgentMessage);
    procedure FollowUp(AMessage: TAgentMessage);
    procedure ClearSteeringQueue;
    procedure ClearFollowUpQueue;
    procedure ClearAllQueues;
    function HasQueuedMessages: Boolean;

    // Main entry points
    procedure Prompt(const AText: string); overload;
    procedure Prompt(AMessage: TAgentMessage); overload;
    procedure Prompt(const AMessages: TArray<TAgentMessage>); overload;
    procedure Continue_;

    // Abort
    procedure Abort;
    procedure WaitForIdle(ATimeoutMs: Cardinal = INFINITE);
    procedure Reset;

    // Confirmation
    procedure ConfirmToolExecution(AApproved: Boolean);

    // Properties
    property State: TAgentState read GetState;
    property IsStreaming: Boolean read GetIsStreaming;
    property Logger: TLogger read FLogger;
    property ModelRef: IModel read FModel;
    property CompactionCount: Integer read FCompactionCount;
    property LastSummary: string read FLastSummary;
    property MaxTurns: Integer read FMaxTurns write FMaxTurns;
  end;

implementation

{$WARN IMPLICIT_STRING_CAST OFF}

const
  DEFAULT_MAX_TURNS = 30;
  DEFAULT_COMPACTION_RESERVE_TOKENS = 16384;
  DEFAULT_COMPACTION_KEEP_RECENT_TOKENS = 20000;
  DEFAULT_CONTEXT_WINDOW = 128000;
  DEFAULT_COMPACTION_MAX_RETRIES = 1;

{ TAgent }

constructor TAgent.Create(ALogger: TLogger);
begin
  inherited Create;
  FLogger := ALogger;
  FState := TAgentState.Create;
  FEventDispatcher := TEventDispatcher.Create;
  FAbortController := TAbortController.Create;
  FSteeringQueue := TAgentMessageList.Create;
  FFollowUpQueue := TAgentMessageList.Create;
  FIdleEvent := TEvent.Create(nil, True, True, '');  // Initially idle
  FConfirmationEvent := TEvent.Create(nil, True, False, '');
  FConfirmationResult := False;
  FCompactionCount := 0;
  FMaxCompactionRetries := DEFAULT_COMPACTION_MAX_RETRIES;
  FLastSummary := '';
  FCompactionEnabled := True;
  FReserveTokens := DEFAULT_COMPACTION_RESERVE_TOKENS;
  FKeepRecentTokens := DEFAULT_COMPACTION_KEEP_RECENT_TOKENS;
  FContextWindow := DEFAULT_CONTEXT_WINDOW;
  FMaxTurns := DEFAULT_MAX_TURNS;
  FTurnCount := 0;
  FStateLock := TObject.Create;
end;

constructor TAgent.Create(const AInitialState: TAgentState;
  ALogger: TLogger);
begin
  Create(ALogger);
  // Copy state values
  FState.SystemPrompt := AInitialState.SystemPrompt;
  FState.Model := AInitialState.Model;
  FState.ThinkingLevel := AInitialState.ThinkingLevel;
  FState.Tools := Copy(AInitialState.Tools);
  if AInitialState.Messages <> nil then
  begin
    FState.Messages.Free;
    FState.Messages := AInitialState.Messages.Clone;
  end;
end;

destructor TAgent.Destroy;
begin
  if FState.IsStreaming then
  begin
    FAbortController.Abort;
    FConfirmationEvent.SetEvent;
  end;
  WaitForIdle(5000);

  FreeAndNil(FState.Messages);
  FreeAndNil(FState.PendingToolCalls);
  FreeAndNil(FSteeringQueue);
  FreeAndNil(FFollowUpQueue);
  FreeAndNil(FEventDispatcher);
  FreeAndNil(FAbortController);
  FreeAndNil(FIdleEvent);
  FreeAndNil(FConfirmationEvent);
  FreeAndNil(FStateLock);
  inherited;
end;

// --- Subscription ---

function TAgent.Subscribe(AHandler: TAgentEventHandler): Integer;
begin
  Result := FEventDispatcher.Subscribe(AHandler);
end;

procedure TAgent.Unsubscribe(AId: Integer);
begin
  FEventDispatcher.Unsubscribe(AId);
end;

// --- State Accessors ---

function TAgent.GetState: TAgentState;
begin
  TMonitor.Enter(FStateLock);
  try
    Result := FState;
    // WARNING: Result is a shallow copy of the record. The following fields are
    // CLASS REFERENCES owned by TAgent — caller must NOT free them:
    //   Result.Messages (TAgentMessageList)
    //   Result.PendingToolCalls (TToolCallSet)
    //   Result.StreamMessage (TAssistantMessage, may be nil)
    // Caller should only read these, not modify or free.
  finally
    TMonitor.Exit(FStateLock);
  end;
end;

function TAgent.GetIsStreaming: Boolean;
begin
  Result := FState.IsStreaming;
end;

procedure TAgent.SetSystemPrompt(const AValue: string);
begin
  TMonitor.Enter(FStateLock);
  try
    FState.SystemPrompt := AValue;
  finally
    TMonitor.Exit(FStateLock);
  end;
end;

procedure TAgent.SetModel(const AModel: TModelConfig);
begin
  TMonitor.Enter(FStateLock);
  try
    FState.Model := AModel;
  finally
    TMonitor.Exit(FStateLock);
  end;
end;

procedure TAgent.SetThinkingLevel(ALevel: TThinkingLevel);
begin
  TMonitor.Enter(FStateLock);
  try
    FState.ThinkingLevel := ALevel;
  finally
    TMonitor.Exit(FStateLock);
  end;
end;

procedure TAgent.SetTools(const ATools: TArray<IAgentTool>);
begin
  TMonitor.Enter(FStateLock);
  try
    FState.Tools := Copy(ATools);
  finally
    TMonitor.Exit(FStateLock);
  end;
end;

procedure TAgent.SetPermissions(const APerms: TToolPermissions);
begin
  TMonitor.Enter(FStateLock);
  try
    FState.Permissions := APerms;
  finally
    TMonitor.Exit(FStateLock);
  end;
end;

procedure TAgent.SetModelRef(AModel: IModel);
begin
  TMonitor.Enter(FStateLock);
  try
    FModel := AModel;
    if AModel <> nil then
    begin
      FState.Model.Name := AModel.GetName;
    end;
  finally
    TMonitor.Exit(FStateLock);
  end;
end;

procedure TAgent.ReplaceMessages(AMessages: TAgentMessageList);
begin
  TMonitor.Enter(FStateLock);
  try
    FState.Messages.Free;
    FState.Messages := AMessages;
  finally
    TMonitor.Exit(FStateLock);
  end;
end;

procedure TAgent.AppendMessage(AMessage: TAgentMessage);
begin
  TMonitor.Enter(FStateLock);
  try
    FState.Messages.Add(AMessage);
  finally
    TMonitor.Exit(FStateLock);
  end;
end;

procedure TAgent.ClearMessages;
begin
  TMonitor.Enter(FStateLock);
  try
    FState.Messages.Clear;
  finally
    TMonitor.Exit(FStateLock);
  end;
end;

// --- Queuing ---

procedure TAgent.Steer(AMessage: TAgentMessage);
begin
  TMonitor.Enter(FSteeringQueue);
  try
    FSteeringQueue.Add(AMessage);
  finally
    TMonitor.Exit(FSteeringQueue);
  end;
end;

procedure TAgent.FollowUp(AMessage: TAgentMessage);
begin
  TMonitor.Enter(FFollowUpQueue);
  try
    FFollowUpQueue.Add(AMessage);
  finally
    TMonitor.Exit(FFollowUpQueue);
  end;
end;

procedure TAgent.ClearSteeringQueue;
begin
  TMonitor.Enter(FSteeringQueue);
  try
    FSteeringQueue.Clear;
  finally
    TMonitor.Exit(FSteeringQueue);
  end;
end;

procedure TAgent.ClearFollowUpQueue;
begin
  TMonitor.Enter(FFollowUpQueue);
  try
    FFollowUpQueue.Clear;
  finally
    TMonitor.Exit(FFollowUpQueue);
  end;
end;

procedure TAgent.ClearAllQueues;
begin
  TMonitor.Enter(FSteeringQueue);
  try
    FSteeringQueue.Clear;
    TMonitor.Enter(FFollowUpQueue);
    try
      FFollowUpQueue.Clear;
    finally
      TMonitor.Exit(FFollowUpQueue);
    end;
  finally
    TMonitor.Exit(FSteeringQueue);
  end;
end;

function TAgent.HasQueuedMessages: Boolean;
begin
  Result := (FSteeringQueue.Count > 0) or (FFollowUpQueue.Count > 0);
end;

// --- Event Emitters ---

procedure TAgent.EmitAgentStart;
begin
  FEventDispatcher.DispatchEvent(TAgentStartEvent.Create);
end;

procedure TAgent.EmitAgentEnd;
var
  ClonedMessages: TAgentMessageList;
begin
  TMonitor.Enter(FStateLock);
  try
    ClonedMessages := FState.Messages.Clone;
  finally
    TMonitor.Exit(FStateLock);
  end;
  FEventDispatcher.DispatchEvent(TAgentEndEvent.Create(ClonedMessages));
end;

procedure TAgent.EmitTurnStart;
begin
  FEventDispatcher.DispatchEvent(TTurnStartEvent.Create);
end;

procedure TAgent.EmitTurnEnd(AMessage: TAssistantMessage;
  const AToolResults: TArray<TToolResultMessage>);
begin
  FEventDispatcher.DispatchEvent(TTurnEndEvent.Create(AMessage, AToolResults));
end;

procedure TAgent.EmitMessageStart(AMessage: TAgentMessage);
var
  Cloned: TAgentMessage;
begin
  if AMessage = nil then Exit;
  if Assigned(FLogger) then FLogger.Debug('EmitMessageStart: calling Clone');
  Cloned := AMessage.Clone;
  if Cloned = nil then Exit;
  if Assigned(FLogger) then FLogger.Debug('EmitMessageStart: calling DispatchEvent');
  FEventDispatcher.DispatchEvent(TMessageStartEvent.Create(Cloned));
  if Assigned(FLogger) then FLogger.Debug('EmitMessageStart: done');
end;

procedure TAgent.EmitMessageEnd(AMessage: TAgentMessage);
var
  Cloned: TAgentMessage;
begin
  if AMessage = nil then Exit;
  if Assigned(FLogger) then FLogger.Debug('EmitMessageEnd: calling Clone');
  Cloned := AMessage.Clone;
  if Cloned = nil then Exit;
  if Assigned(FLogger) then FLogger.Debug('EmitMessageEnd: calling DispatchEvent');
  FEventDispatcher.DispatchEvent(TMessageEndEvent.Create(Cloned));
  if Assigned(FLogger) then FLogger.Debug('EmitMessageEnd: done');
end;

// --- Main Entry Points ---

procedure TAgent.Prompt(const AText: string);
var
  Msg: TUserMessage;
  Arr: TArray<TAgentMessage>;
begin
  Msg := TUserMessage.Create(AText);
  SetLength(Arr, 1);
  Arr[0] := Msg;
  RunInBackground(Arr);
end;

procedure TAgent.Prompt(AMessage: TAgentMessage);
var
  Arr: TArray<TAgentMessage>;
begin
  SetLength(Arr, 1);
  Arr[0] := AMessage;
  RunInBackground(Arr);
end;

procedure TAgent.Prompt(const AMessages: TArray<TAgentMessage>);
begin
  RunInBackground(AMessages);
end;

procedure TAgent.RunInBackground(const AMessages: TArray<TAgentMessage>);
var
  MsgCopy: TArray<TAgentMessage>;
  Thread: TThread;
begin
  // Reset abort controller from any previous Abort call,
  // otherwise DoPrompt will immediately raise "Agent has been aborted"
  FAbortController.Reset;

  // Reset idle event BEFORE starting thread so WaitForIdle in the destructor
  // will actually wait for completion instead of returning immediately
  // (FIdleEvent is initially signaled from the constructor)
  FIdleEvent.ResetEvent;

  // Copy the array to ensure it remains valid in the background thread
  MsgCopy := Copy(AMessages);
  Thread := TThread.CreateAnonymousThread(
    procedure
    begin
      DoPrompt(MsgCopy);
    end);
  Thread.FreeOnTerminate := True;
  Thread.Start;
end;

// --- Extracted sub-methods for DoPrompt ---

function TAgent.BuildCompletionRequest: TCompletionRequest;
var
  ApiMessages: TArray<TApiChatMessage>;
  ApiTools: TArray<TApiToolDefinition>;
  MsgClone: TAgentMessageList;
  SystemPrompt: string;
  ModelConfig: TModelConfig;
  ThinkingLevel: TThinkingLevel;
  Tools: TArray<IAgentTool>;
begin
  // Snapshot state under lock
  TMonitor.Enter(FStateLock);
  try
    MsgClone := FState.Messages.Clone;
    SystemPrompt := FState.SystemPrompt;
    ModelConfig := FState.Model;
    ThinkingLevel := FState.ThinkingLevel;
    Tools := Copy(FState.Tools);
  finally
    TMonitor.Exit(FStateLock);
  end;
  try
    ApiMessages := AgentMessagesToApiMessages(
      DefaultConvertToLlm(MsgClone.ToArray), SystemPrompt);
  finally
    MsgClone.Free;
  end;

  if Length(Tools) > 0 then
    ApiTools := AgentToolsToApiTools(Tools)
  else
    ApiTools := nil;

  Result := TCompletionRequest.Create;
  Result.Model := ModelConfig.Name;
  Result.Messages := ApiMessages;
  Result.Tools := ApiTools;
  Result.MaxTokens := ModelConfig.MaxTokens;
  Result.Temperature := ModelConfig.Temperature;
  Result.TopP := ModelConfig.TopP;
  Result.FrequencyPenalty := ModelConfig.FrequencyPenalty;
  Result.PresencePenalty := ModelConfig.PresencePenalty;
  Result.ThinkingLevel := ThinkingLevel;
  Result.Stream := True;
  Result.SystemPrompt := '';  // Already included in ApiMessages
end;

procedure TAgent.ProcessStreamCallback(AEvent: TAssistantMessageEvent;
  var AStreamingAssistant: TAssistantMessage;
  var AOverflowRetry: Boolean);
var
  EventToFree: TAssistantMessageEvent;
begin
  EventToFree := nil;
  case AEvent.EventType of
    ametStart:
    begin
      EmitMessageStart(AStreamingAssistant.Clone as TAssistantMessage);
      EventToFree := AEvent;
    end;

    ametTextDelta:
    begin
      AStreamingAssistant.Content.Add(
        TTextContent.Create(TTextDeltaEvent(AEvent).Delta));
      TMonitor.Enter(FStateLock);
      try
        FState.StreamMessage := AStreamingAssistant;
      finally
        TMonitor.Exit(FStateLock);
      end;
      FEventDispatcher.DispatchEvent(
        TStreamDeltaEvent.Create(TTextDeltaEvent(AEvent).Delta, sdtText));
      EventToFree := AEvent;
    end;

    ametThinkingDelta:
    begin
      AStreamingAssistant.Content.Add(
        TThinkingContent.Create(TThinkingDeltaEvent(AEvent).Delta));
      FEventDispatcher.DispatchEvent(
        TStreamDeltaEvent.Create(TThinkingDeltaEvent(AEvent).Delta, sdtThinking));
      EventToFree := AEvent;
    end;

    ametToolCallDelta:
    begin
      FEventDispatcher.DispatchEvent(
        TStreamDeltaEvent.Create('', sdtToolCall));
      EventToFree := AEvent;
    end;

    ametDone:
    begin
      if Assigned(FLogger) then FLogger.Debug('DoPrompt: stream ametDone received');
      TMonitor.Enter(FStateLock);
      try
        FState.StreamMessage := nil;
        FState.Messages.Add(TDoneEvent(AEvent).Message.Clone as TAssistantMessage);
      finally
        TMonitor.Exit(FStateLock);
      end;
      AStreamingAssistant.Free;
      AStreamingAssistant := TDoneEvent(AEvent).Message.Clone as TAssistantMessage;
      EmitMessageEnd(AStreamingAssistant.Clone as TAssistantMessage);
      EventToFree := AEvent;
    end;

    ametError:
    begin
      if Assigned(FLogger) then
        FLogger.Error('DoPrompt: stream ametError received');
      TMonitor.Enter(FStateLock);
      try
        FState.StreamMessage := nil;
        FState.Messages.Add(TErrorEvent(AEvent).Error.Clone as TAssistantMessage);
      finally
        TMonitor.Exit(FStateLock);
      end;
      AStreamingAssistant.Free;
      AStreamingAssistant := TErrorEvent(AEvent).Error.Clone as TAssistantMessage;
      EmitMessageEnd(AStreamingAssistant.Clone as TAssistantMessage);
      EventToFree := AEvent;

      // Overflow recovery: emergency cut and retry
      if FCompactionEnabled and
         (FCompactionCount < FMaxCompactionRetries) and
         TCompaction.IsContextOverflow(AStreamingAssistant.ErrorMessage) then
      begin
        if Assigned(FLogger) then
          FLogger.Warn('Context overflow detected, emergency compaction...');
        TMonitor.Enter(FStateLock);
        try
          FState.Messages.Delete(FState.Messages.Count - 1);
          var Cut := TCompaction.EmergencyCut(FState.Messages);
          FState.Messages.Free;
          FState.Messages := Cut;
          Inc(FCompactionCount);
          if Assigned(FLogger) then
            FLogger.Info(Format('Emergency cut applied, %d messages remaining', [FState.Messages.Count]));
        finally
          TMonitor.Exit(FStateLock);
        end;
        AOverflowRetry := True;
      end;
    end;
  end;
  EventToFree.Free;
end;

procedure TAgent.ExecuteToolCalls(const AToolCalls: TArray<TToolCall>;
  out AToolResults: TArray<TToolResultMessage>);
var
  i: Integer;
  Tool: IAgentTool;
  ToolResult: TToolResult;
  ResultText: string;
  Perm: TToolPermission;
  Schema: TJSONObject;
  RequiredArr: TJSONArray;
  ReqKey: string;
  ConfirmPath, ConfirmDiff: string;
  ConfirmArgs, ExecArgs: TJSONObject;
  ErrContent, PermErrContent, AbortContent, RejectContent, ValErrContent: TContentBlockList;
begin
  SetLength(AToolResults, Length(AToolCalls));
  for i := 0 to High(AToolCalls) do
  begin
    if FAbortController.IsAborted then
    begin
      ErrContent := TContentBlockList.Create;
      ErrContent.Add(TTextContent.Create('Tool execution aborted'));
      AToolResults[i] := TToolResultMessage.Create(
        AToolCalls[i].Id, AToolCalls[i].Name, ErrContent, True);
      Continue;
    end;

    // Check tool permission
    TMonitor.Enter(FStateLock);
    try
      Perm := GetPermissionForToolName(AToolCalls[i].Name, FState.Permissions);
    finally
      TMonitor.Exit(FStateLock);
    end;
    if not Perm.Enabled then
    begin
      PermErrContent := TContentBlockList.Create;
      PermErrContent.Add(TTextContent.Create(
        'Tool "' + AToolCalls[i].Name + '" is disabled by permissions configuration'));
      AToolResults[i] := TToolResultMessage.Create(
        AToolCalls[i].Id, AToolCalls[i].Name, PermErrContent, True);
      FEventDispatcher.DispatchEvent(
        TToolExecutionEndEvent.Create(
          AToolCalls[i].Id, AToolCalls[i].Name,
          'Tool disabled by permissions', True));
      Continue;
    end;

    // Confirmation check: require user approval for write/edit tools
    if Perm.RequireConfirmation and
       (SameText(AToolCalls[i].Name, 'write') or SameText(AToolCalls[i].Name, 'edit')) then
    begin
      FConfirmationEvent.ResetEvent;
      FConfirmationResult := False;

      ConfirmPath := JsonGetStr(AToolCalls[i].Arguments, 'path', '');
      ConfirmDiff := '';

      if SameText(AToolCalls[i].Name, 'edit') then
      begin
        var OldT := JsonGetStr(AToolCalls[i].Arguments, 'oldText', '');
        var NewT := JsonGetStr(AToolCalls[i].Arguments, 'newText', '');
        ConfirmDiff := '--- ' + ConfirmPath + #10 + '+++ ' + ConfirmPath + #10;
        var OldLines := OldT.Split([#10]);
        var NewLines := NewT.Split([#10]);
        for var di := 0 to High(OldLines) do
          ConfirmDiff := ConfirmDiff + '- ' + OldLines[di] + #10;
        for var di := 0 to High(NewLines) do
          ConfirmDiff := ConfirmDiff + '+ ' + NewLines[di] + #10;
      end
      else if SameText(AToolCalls[i].Name, 'write') then
      begin
        var Content := JsonGetStr(AToolCalls[i].Arguments, 'content', '');
        var WLines := Content.Split([#10]);
        ConfirmDiff := '--- /dev/null' + #10 + '+++ ' + ConfirmPath + #10 +
          Format('@@ Writing %d lines, %d bytes @@' + #10, [Length(WLines), Length(Content)]);
        for var di := 0 to Min(High(WLines), 19) do
          ConfirmDiff := ConfirmDiff + '+ ' + WLines[di] + #10;
        if Length(WLines) > 20 then
          ConfirmDiff := ConfirmDiff + Format('... (%d more lines)' + #10, [Length(WLines) - 20]);
      end;

      if AToolCalls[i].Arguments <> nil then
        ConfirmArgs := TJSONObject(TJSONObject.Create.ParseJSONValue(
          AToolCalls[i].Arguments.ToJSON))
      else
        ConfirmArgs := TJSONObject.Create;
      try
        FEventDispatcher.DispatchEvent(
          TToolConfirmationRequestEvent.Create(
            AToolCalls[i].Id, AToolCalls[i].Name,
            ConfirmPath, ConfirmDiff, ConfirmArgs));
        ConfirmArgs := nil;  // Ownership transferred to event
      except
        ConfirmArgs.Free;
        raise;
      end;

      FConfirmationEvent.WaitFor(INFINITE);

      if FAbortController.IsAborted then
      begin
        AbortContent := TContentBlockList.Create;
        AbortContent.Add(TTextContent.Create('Tool execution aborted'));
        AToolResults[i] := TToolResultMessage.Create(
          AToolCalls[i].Id, AToolCalls[i].Name, AbortContent, True);
        Continue;
      end;

      if not FConfirmationResult then
      begin
        RejectContent := TContentBlockList.Create;
        RejectContent.Add(TTextContent.Create('Tool execution rejected by user'));
        AToolResults[i] := TToolResultMessage.Create(
          AToolCalls[i].Id, AToolCalls[i].Name, RejectContent, True);
        FEventDispatcher.DispatchEvent(
          TToolExecutionEndEvent.Create(
            AToolCalls[i].Id, AToolCalls[i].Name,
            'Rejected by user', True));
        Continue;
      end;
    end;

    // Find and validate tool
    TMonitor.Enter(FStateLock);
    try
      Tool := FState.FindTool(AToolCalls[i].Name);
    finally
      TMonitor.Exit(FStateLock);
    end;

    if Tool = nil then
    begin
      ErrContent := TContentBlockList.Create;
      ErrContent.Add(TTextContent.Create('Unknown tool: ' + AToolCalls[i].Name));
      AToolResults[i] := TToolResultMessage.Create(
        AToolCalls[i].Id, AToolCalls[i].Name, ErrContent, True);
    end
    else
    begin
      Schema := Tool.GetParameterSchema;
      try
        if Schema.TryGetValue('required', RequiredArr) then
        begin
          for var ri := 0 to RequiredArr.Count - 1 do
          begin
            ReqKey := RequiredArr[ri].Value;
            if (AToolCalls[i].Arguments = nil) or
               (AToolCalls[i].Arguments.GetValue(ReqKey) = nil) then
            begin
              ValErrContent := TContentBlockList.Create;
              ValErrContent.Add(TTextContent.Create(
                'Missing required parameter "' + ReqKey + '" for tool "' + AToolCalls[i].Name + '"'));
              AToolResults[i] := TToolResultMessage.Create(
                AToolCalls[i].Id, AToolCalls[i].Name, ValErrContent, True);
              FEventDispatcher.DispatchEvent(
                TToolExecutionEndEvent.Create(
                  AToolCalls[i].Id, AToolCalls[i].Name,
                  'Missing parameter: ' + ReqKey, True));
              Tool := nil;
              Break;
            end;
          end;
        end;
      finally
        Schema.Free;
      end;

      if Tool <> nil then
      begin
        if AToolCalls[i].Arguments <> nil then
          ExecArgs := TJSONObject(TJSONObject.Create.ParseJSONValue(
            AToolCalls[i].Arguments.ToJSON))
        else
          ExecArgs := TJSONObject.Create;
        try
          FEventDispatcher.DispatchEvent(
            TToolExecutionStartEvent.Create(
              AToolCalls[i].Id, AToolCalls[i].Name, ExecArgs));
          ExecArgs := nil;  // Ownership transferred to event
        except
          ExecArgs.Free;
          raise;
        end;

        try
          ToolResult := Tool.Execute(
            AToolCalls[i].Id,
            AToolCalls[i].Arguments,
            function: Boolean
            begin
              Result := FAbortController.IsAborted;
            end);
        except
          on E: Exception do
            ToolResult := TToolResult.CreateError(E.Message);
        end;

        ResultText := '';
        if ToolResult.Content <> nil then
          for var j := 0 to ToolResult.Content.Count - 1 do
            if ToolResult.Content[j].ContentType = cbtText then
              ResultText := ResultText + TTextContent(ToolResult.Content[j]).Text;
        FEventDispatcher.DispatchEvent(
          TToolExecutionEndEvent.Create(
            AToolCalls[i].Id, AToolCalls[i].Name,
            ResultText, ToolResult.IsError));

        AToolResults[i] := TToolResultMessage.Create(
          AToolCalls[i].Id, AToolCalls[i].Name,
          ToolResult.Content, ToolResult.IsError);
      end;
    end;

    // Add tool result to messages
    TMonitor.Enter(FStateLock);
    try
      FState.Messages.Add(AToolResults[i].Clone as TAgentMessage);
    finally
      TMonitor.Exit(FStateLock);
    end;
    EmitMessageStart(AToolResults[i]);
    EmitMessageEnd(AToolResults[i]);
  end;
end;

procedure TAgent.DoPrompt(const AMessages: TArray<TAgentMessage>);
var
  i: Integer;
  Request: TCompletionRequest;
  StreamingAssistant: TAssistantMessage;
  ToolCalls: TArray<TToolCall>;
  ToolResults: TArray<TToolResultMessage>;
  OverflowRetry: Boolean;
begin
  StreamingAssistant := nil;

  if FState.IsStreaming then
    raise Exception.Create('Agent is already streaming. Call Abort or WaitForIdle first.');

  if FAbortController.IsAborted then
    raise Exception.Create('Agent has been aborted. Call Reset first.');

  if Assigned(FLogger) then
    FLogger.Debug('DoPrompt: starting, FModel assigned=' + BoolToStr(FModel <> nil, True));

  // Mark as streaming
  FState.SetIsStreaming(True);
  FIdleEvent.ResetEvent;

  try
    try
      // Emit agent_start
      if Assigned(FLogger) then FLogger.Debug('DoPrompt: EmitAgentStart');
      EmitAgentStart;

      // Add user messages to state and emit events
      for i := 0 to High(AMessages) do
      begin
        if Assigned(FLogger) then FLogger.Debug(Format('DoPrompt: user msg %d/%d, Assigned=%s',
          [i+1, Length(AMessages), BoolToStr(AMessages[i] <> nil, True)]));
        EmitMessageStart(AMessages[i]);
        TMonitor.Enter(FStateLock);
        try
          FState.Messages.Add(AMessages[i]);
        finally
          TMonitor.Exit(FStateLock);
        end;
        EmitMessageEnd(AMessages[i]);
      end;

      // Agent loop: stream -> execute tools -> repeat
      FTurnCount := 0;
      while True do
      begin
        if FAbortController.IsAborted then
          Break;

        // MaxTurns safety limit
        Inc(FTurnCount);
        if FTurnCount > FMaxTurns then
        begin
          if Assigned(FLogger) then
            FLogger.Warn(Format('MaxTurns limit reached (%d), stopping agent loop', [FMaxTurns]));
          Break;
        end;

        // Consume steering messages (mid-stream user intervention)
        var SteeredMessages: TArray<TAgentMessage>;
        TMonitor.Enter(FSteeringQueue);
        try
          if FSteeringQueue.Count > 0 then
            SteeredMessages := FSteeringQueue.ExtractAll;
        finally
          TMonitor.Exit(FSteeringQueue);
        end;
        for var si := 0 to High(SteeredMessages) do
        begin
          TMonitor.Enter(FStateLock);
          try
            FState.Messages.Add(SteeredMessages[si]);
          finally
            TMonitor.Exit(FStateLock);
          end;
          EmitMessageStart(SteeredMessages[si]);
          EmitMessageEnd(SteeredMessages[si]);
        end;

        EmitTurnStart;

        // Build request using extracted method
        Request := BuildCompletionRequest;

        // Create fresh StreamingAssistant for this turn
        StreamingAssistant := TAssistantMessage.Create;
        OverflowRetry := False;

        if FModel <> nil then
        begin
          if Assigned(FLogger) then FLogger.Debug(Format(
            'DoPrompt: calling FModel.Stream, model=%s, msgs=%d, tools=%d',
            [Request.Model, Length(Request.Messages), Length(Request.Tools)]));
          FModel.Stream(Request,
            procedure(AEvent: TAssistantMessageEvent)
            begin
              ProcessStreamCallback(AEvent, StreamingAssistant, OverflowRetry);
            end,
            FAbortController);
          if Assigned(FLogger) then FLogger.Debug('DoPrompt: FModel.Stream returned');
        end
        else
        begin
          // No model configured - return error response
          EmitMessageStart(StreamingAssistant);
          StreamingAssistant.Content.Add(TTextContent.Create(
            'No AI model configured. Please go to Settings and configure your API settings.'));
          StreamingAssistant.Api := 'none';
          StreamingAssistant.Provider := 'none';
          StreamingAssistant.Model := Request.Model;
          StreamingAssistant.StopReason := srError;
          StreamingAssistant.ErrorMessage := 'No AI model configured';
          // Fire error event
          FEventDispatcher.DispatchEvent(TAgentErrorEvent.Create('No AI model configured'));
          TMonitor.Enter(FStateLock);
          try
            FState.Messages.Add(StreamingAssistant.Clone as TAssistantMessage);
          finally
            TMonitor.Exit(FStateLock);
          end;
          EmitMessageEnd(StreamingAssistant);
        end;

        // Free owned JSON objects from the request (cloned during ToJson serialization)
        FreeApiMessages(Request.Messages);
        FreeApiTools(Request.Tools);

        // Handle overflow retry from emergency compaction
        if OverflowRetry then
        begin
          StreamingAssistant.Free;
          StreamingAssistant := nil;
          Continue;
        end;

        // Check for abort or error
        if FAbortController.IsAborted or
           (StreamingAssistant.StopReason in [srError, srAborted]) then
        begin
          if Assigned(FLogger) then FLogger.Debug('DoPrompt: abort or error, breaking');
          EmitTurnEnd(StreamingAssistant.Clone as TAssistantMessage, nil);
          StreamingAssistant.Free;
          StreamingAssistant := nil;
          Break;
        end;

        // Check for tool calls
        ToolCalls := StreamingAssistant.Content.FindToolCalls;
        if Assigned(FLogger) then FLogger.Debug(Format(
          'DoPrompt: checking tool calls, found=%d, stopReason=%d',
          [Length(ToolCalls), Ord(StreamingAssistant.StopReason)]));
        if Length(ToolCalls) = 0 then
        begin
          // No tool calls - turn is done
          EmitTurnEnd(StreamingAssistant.Clone as TAssistantMessage, nil);
          StreamingAssistant.Free;
          StreamingAssistant := nil;
          Break;
        end;

        // Execute tool calls using extracted method
        ExecuteToolCalls(ToolCalls, ToolResults);

        EmitTurnEnd(StreamingAssistant.Clone as TAssistantMessage, ToolResults);

        // Release this turn's StreamingAssistant before next iteration
        StreamingAssistant.Free;
        StreamingAssistant := nil;

        // Consume follow-up messages (keep agent alive with new user input)
        var FollowUpMessages: TArray<TAgentMessage>;
        TMonitor.Enter(FFollowUpQueue);
        try
          if FFollowUpQueue.Count > 0 then
            FollowUpMessages := FFollowUpQueue.ExtractAll;
        finally
          TMonitor.Exit(FFollowUpQueue);
        end;
        if Length(FollowUpMessages) > 0 then
        begin
          for var fi := 0 to High(FollowUpMessages) do
          begin
            TMonitor.Enter(FStateLock);
            try
              FState.Messages.Add(FollowUpMessages[fi]);
            finally
              TMonitor.Exit(FStateLock);
            end;
            EmitMessageStart(FollowUpMessages[fi]);
            EmitMessageEnd(FollowUpMessages[fi]);
          end;
          Continue;
        end;
      end;

      // StreamingAssistant should already be nil at this point (freed in loop body),
      // FreeAndNil handles nil gracefully
      FreeAndNil(StreamingAssistant);

      // Auto-compaction check (before agent_end)
      if FCompactionEnabled then
        CheckAndCompact;

      // Mark streaming complete BEFORE emitting agent_end,
      // so UI can re-enable controls in HandleAgentEnd
      FState.SetIsStreaming(False);

      // Emit agent_end
      EmitAgentEnd;

      if Assigned(FLogger) then
        FLogger.Info('Agent prompt completed');
    except
      on E: Exception do
      begin
        if Assigned(FLogger) then
          FLogger.LogException(E, 'Agent prompt failed');
        FState.SetIsStreaming(False);
        // Fire dedicated error event so UI can display it distinctly
        FEventDispatcher.DispatchEvent(TAgentErrorEvent.Create(E.Message));
        try
          var ErrMsg := TAssistantMessage.Create;
          try
            ErrMsg.StopReason := srError;
            ErrMsg.ErrorMessage := E.Message;
            ErrMsg.Content.Add(TTextContent.Create('Error: ' + E.Message));
            EmitMessageStart(ErrMsg);
            EmitMessageEnd(ErrMsg);
          finally
            ErrMsg.Free;
          end;
        except
          // If error message emission also fails, don't cascade
          if Assigned(FLogger) then
            FLogger.Error('DoPrompt: failed to emit error message');
        end;
        EmitAgentEnd;
      end;
    end;
  finally
    // Always reset streaming state and signal idle (prevents UI lockup)
    FState.SetIsStreaming(False);
    FreeAndNil(StreamingAssistant);
    FState.StreamMessage := nil;
    FIdleEvent.SetEvent;
  end;
end;

procedure TAgent.Continue_;
var
  EmptyArr: TArray<TAgentMessage>;
  MsgCount: Integer;
begin
  if FState.IsStreaming then
    raise Exception.Create('Agent is already streaming.');

  TMonitor.Enter(FStateLock);
  try
    MsgCount := FState.Messages.Count;
  finally
    TMonitor.Exit(FStateLock);
  end;
  if MsgCount = 0 then
    raise Exception.Create('No messages to continue from.');

  // Skip if there are no queued messages and the last message is not a tool result
  // (continuing would produce a redundant API call)
  if not HasQueuedMessages then
  begin
    TMonitor.Enter(FStateLock);
    try
      if (FState.Messages.Count > 0) and
         (FState.Messages[FState.Messages.Count - 1].Role <> mrToolResult) then
        raise Exception.Create('Nothing to continue. Last message is not a tool result or queued input.');
    finally
      TMonitor.Exit(FStateLock);
    end;
  end;

  // Continue with existing context (no new user messages)
  EmptyArr := nil;
  RunInBackground(EmptyArr);
end;

// --- Abort ---

procedure TAgent.Abort;
begin
  FAbortController.Abort;
  FConfirmationEvent.SetEvent;  // Unblock confirmation wait
  if Assigned(FLogger) then
    FLogger.Warn('Agent abort requested');
end;

procedure TAgent.WaitForIdle(ATimeoutMs: Cardinal);
begin
  FIdleEvent.WaitFor(ATimeoutMs);
end;

procedure TAgent.Reset;
begin
  // Ensure background thread has finished before modifying state
  if FState.IsStreaming then
  begin
    FAbortController.Abort;
    FConfirmationEvent.SetEvent;
    WaitForIdle(5000);
  end;
  FAbortController.Reset;
  TMonitor.Enter(FStateLock);
  try
    FState.Reset;
  finally
    TMonitor.Exit(FStateLock);
  end;
  ClearAllQueues;
  FIdleEvent.SetEvent;
  FCompactionCount := 0;
  FLastSummary := '';
end;

procedure TAgent.ConfirmToolExecution(AApproved: Boolean);
begin
  FConfirmationResult := AApproved;
  FConfirmationEvent.SetEvent;
end;

// --- Convert helpers ---

function TAgent.DefaultConvertToLlm(
  AMessages: TArray<TAgentMessage>): TArray<TAgentMessage>;
var
  i, Count: Integer;

  function IsEmptyAssistant(Msg: TAgentMessage): Boolean;
  var
    Asst: TAssistantMessage;
    j: Integer;
  begin
    Result := False;
    if Msg.Role <> mrAssistant then Exit;
    Asst := TAssistantMessage(Msg);
    if Asst.Content = nil then Exit(True);
    if Asst.Content.Count = 0 then Exit(True);
    // Check if all content blocks are empty text
    for j := 0 to Asst.Content.Count - 1 do
      if Asst.Content[j].ContentType = cbtText then
        if TTextContent(Asst.Content[j]).Text.Trim <> '' then
          Exit;
    Result := True;
  end;

begin
  // Filter to only LLM-compatible message roles (user, assistant, toolResult)
  // Skip empty assistant messages (API rejects them)
  Count := 0;
  for i := 0 to High(AMessages) do
    if (AMessages[i].Role in [mrUser, mrAssistant, mrToolResult]) and
       not IsEmptyAssistant(AMessages[i]) then
      Inc(Count);

  SetLength(Result, Count);
  Count := 0;
  for i := 0 to High(AMessages) do
    if (AMessages[i].Role in [mrUser, mrAssistant, mrToolResult]) and
       not IsEmptyAssistant(AMessages[i]) then
    begin
      Result[Count] := AMessages[i];
      Inc(Count);
    end;
end;

// --- Compaction ---

procedure TAgent.SetCompactionSettings(AEnabled: Boolean;
  AReserveTokens, AKeepRecentTokens, AContextWindow: Integer);
begin
  FCompactionEnabled := AEnabled;
  FReserveTokens := AReserveTokens;
  FKeepRecentTokens := AKeepRecentTokens;
  FContextWindow := AContextWindow;
end;

function TAgent.CheckAndCompact: Boolean;
var
  Tokens: Integer;
  Slimmed, NewMsgs, MessagesSnapshot: TAgentMessageList;
  Prep: TCompactionPreparation;
  Res: TCompactionResult;
  SystemPrompt: string;
begin
  Result := False;

  // 1. Snapshot state under lock, then release lock before any LLM calls
  TMonitor.Enter(FStateLock);
  try
    Tokens := EstimateContextTokensFromUsage(FState.Messages);

    if not TCompaction.ShouldCompact(Tokens, FContextWindow, FReserveTokens) then
      Exit;

    if Assigned(FLogger) then
      FLogger.Info(Format('Compaction triggered: %d tokens > %d threshold',
        [Tokens, FContextWindow - FReserveTokens]));

    // Layer 1: Slim tool results (pure local operation, safe under lock)
    try
      Slimmed := SlimToolResults(FState.Messages);
      FState.Messages.Free;
      FState.Messages := Slimmed;

      Tokens := EstimateContextTokens(FState.Messages);
      if not TCompaction.ShouldCompact(Tokens, FContextWindow, FReserveTokens) then
      begin
        if Assigned(FLogger) then
          FLogger.Info('Tool result slimming was sufficient, no summary needed');
        Exit(True);
      end;
    except
      on E: Exception do
        if Assigned(FLogger) then
          FLogger.LogException(E, 'Tool result slimming failed');
    end;

    // Take a snapshot for LLM compaction — release lock during API call
    MessagesSnapshot := FState.Messages.Clone;
    SystemPrompt := FState.SystemPrompt;
  finally
    TMonitor.Exit(FStateLock);
  end;

  // 2. Layer 2: LLM summary compaction (OUTSIDE lock — no blocking other threads)
  try
    Prep := TCompaction.Prepare(MessagesSnapshot, FKeepRecentTokens, FLastSummary);
    try
      if Prep.MessagesToSummarize = nil then
      begin
        if Assigned(FLogger) then
          FLogger.Info('No valid compaction cut point found');
        MessagesSnapshot.Free;
        Exit;
      end;

      Res := TCompaction.Execute(Prep, FModel, SystemPrompt,
        FContextWindow, FLogger);

      // 3. Apply result back under lock
      TMonitor.Enter(FStateLock);
      try
        NewMsgs := TCompaction.Apply(FState.Messages, Res);
        FState.Messages.Free;
        FState.Messages := NewMsgs;

        FLastSummary := Res.Summary;
        Inc(FCompactionCount);
        Result := True;

        if Assigned(FLogger) then
          FLogger.Info(Format('Compaction completed: %d → %d messages, %d tokens before',
            [Res.TokensBefore, EstimateContextTokens(FState.Messages), Res.TokensBefore]));
      finally
        TMonitor.Exit(FStateLock);
      end;
    finally
      Prep.MessagesToSummarize.Free;
    end;
  except
    on E: Exception do
      if Assigned(FLogger) then
        FLogger.LogException(E, 'Compaction failed');
  end;
  MessagesSnapshot.Free;
end;

// --- Permission Helper ---

class function TAgent.GetPermissionForToolName(const AToolName: string;
  const APerms: TToolPermissions): TToolPermission;
begin
  if SameText(AToolName, 'bash') then
    Result := APerms.BashPerm
  else if SameText(AToolName, 'write') then
    Result := APerms.WritePerm
  else if SameText(AToolName, 'edit') then
    Result := APerms.EditPerm
  else if (AToolName = 'git_status') or (AToolName = 'git_diff') or
          (AToolName = 'git_log') or (AToolName = 'git_blame') then
    Result := APerms.GitPerm
  else if SameText(AToolName, 'web_search') or SameText(AToolName, 'web_fetch') then
    Result := APerms.SearchPerm
  else  // read, ls, find, grep -> read permission
    Result := APerms.ReadPerm;
end;

end.
