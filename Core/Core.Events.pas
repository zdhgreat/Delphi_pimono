unit Core.Events;

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.JSON,
  System.Generics.Collections, Core.Messages;

type
  // --- Assistant Message Streaming Events (from AI layer) ---

  TAssistantMessageEventType = (
    ametStart,
    ametTextStart, ametTextDelta, ametTextEnd,
    ametThinkingStart, ametThinkingDelta, ametThinkingEnd,
    ametToolCallStart, ametToolCallDelta, ametToolCallEnd,
    ametDone, ametError
  );

  TAssistantMessageEvent = class abstract
  public
    function EventType: TAssistantMessageEventType; virtual; abstract;
    function PartialMessage: TAssistantMessage; virtual; abstract;
  end;

  TStartEvent = class(TAssistantMessageEvent)
  private
    FPartial: TAssistantMessage;
  public
    constructor Create(APartial: TAssistantMessage);
    destructor Destroy; override;
    function EventType: TAssistantMessageEventType; override;
    function PartialMessage: TAssistantMessage; override;
  end;

  /// <summary>Text delta event. FPartial is a BORROWED reference — do not free.
  /// Only TDoneEvent and TErrorEvent own their message and free it in their destructor.</summary>
  TTextDeltaEvent = class(TAssistantMessageEvent)
  private
    FContentIndex: Integer;
    FDelta: string;
    FPartial: TAssistantMessage;
  public
    constructor Create(AContentIndex: Integer; const ADelta: string;
      APartial: TAssistantMessage);
    destructor Destroy; override;
    function EventType: TAssistantMessageEventType; override;
    function PartialMessage: TAssistantMessage; override;
    property ContentIndex: Integer read FContentIndex;
    property Delta: string read FDelta;
  end;

  /// <summary>Thinking delta event. FPartial is a BORROWED reference — do not free.</summary>
  TThinkingDeltaEvent = class(TAssistantMessageEvent)
  private
    FContentIndex: Integer;
    FDelta: string;
    FPartial: TAssistantMessage;
  public
    constructor Create(AContentIndex: Integer; const ADelta: string;
      APartial: TAssistantMessage);
    destructor Destroy; override;
    function EventType: TAssistantMessageEventType; override;
    function PartialMessage: TAssistantMessage; override;
    property ContentIndex: Integer read FContentIndex;
    property Delta: string read FDelta;
  end;

  /// <summary>Tool call delta event. FPartial is a BORROWED reference — do not free.</summary>
  TToolCallDeltaEvent = class(TAssistantMessageEvent)
  private
    FContentIndex: Integer;
    FDelta: string;
    FPartial: TAssistantMessage;
  public
    constructor Create(AContentIndex: Integer; const ADelta: string;
      APartial: TAssistantMessage);
    destructor Destroy; override;
    function EventType: TAssistantMessageEventType; override;
    function PartialMessage: TAssistantMessage; override;
    property ContentIndex: Integer read FContentIndex;
    property Delta: string read FDelta;
  end;

  TDoneEvent = class(TAssistantMessageEvent)
  private
    FReason: TStopReason;
    FMessage: TAssistantMessage;
  public
    constructor Create(AReason: TStopReason; AMessage: TAssistantMessage);
    destructor Destroy; override;
    function EventType: TAssistantMessageEventType; override;
    function PartialMessage: TAssistantMessage; override;
    property Reason: TStopReason read FReason;
    property Message: TAssistantMessage read FMessage;
  end;

  TErrorEvent = class(TAssistantMessageEvent)
  private
    FReason: TStopReason;
    FError: TAssistantMessage;
  public
    constructor Create(AReason: TStopReason; AError: TAssistantMessage);
    destructor Destroy; override;
    function EventType: TAssistantMessageEventType; override;
    function PartialMessage: TAssistantMessage; override;
    property Reason: TStopReason read FReason;
    property Error: TAssistantMessage read FError;
  end;

  // --- Agent Events (from agent loop) ---

  TAgentEventType = (
    aetAgentStart,
    aetAgentEnd,
    aetTurnStart,
    aetTurnEnd,
    aetMessageStart,
    aetMessageUpdate,
    aetMessageEnd,
    aetToolExecutionStart,
    aetToolExecutionUpdate,
    aetToolExecutionEnd,
    aetToolConfirmationRequest,
    aetError
  );

  TAgentEvent = class abstract
  public
    function EventType: TAgentEventType; virtual; abstract;
  end;

  TAgentStartEvent = class(TAgentEvent)
  public
    function EventType: TAgentEventType; override;
  end;

  TAgentEndEvent = class(TAgentEvent)
  private
    FMessages: TAgentMessageList;
  public
    constructor Create(AMessages: TAgentMessageList);
    destructor Destroy; override;
    function EventType: TAgentEventType; override;
    property Messages: TAgentMessageList read FMessages;
  end;

  TTurnStartEvent = class(TAgentEvent)
  public
    function EventType: TAgentEventType; override;
  end;

  TTurnEndEvent = class(TAgentEvent)
  private
    FMessage: TAssistantMessage;
    FToolResults: TArray<TToolResultMessage>;
  public
    constructor Create(AMessage: TAssistantMessage;
      const AToolResults: TArray<TToolResultMessage>);
    destructor Destroy; override;
    function EventType: TAgentEventType; override;
    property Message: TAssistantMessage read FMessage;
    property ToolResults: TArray<TToolResultMessage> read FToolResults;
  end;

  TMessageStartEvent = class(TAgentEvent)
  private
    FMessage: TAgentMessage;
  public
    constructor Create(AMessage: TAgentMessage);
    destructor Destroy; override;
    function EventType: TAgentEventType; override;
    property Message: TAgentMessage read FMessage;
  end;

  TMessageUpdateEvent = class(TAgentEvent)
  private
    FMessage: TAgentMessage;
    FAssistantMessageEvent: TAssistantMessageEvent;
  public
    constructor Create(AMessage: TAgentMessage;
      AAssistantMessageEvent: TAssistantMessageEvent);
    destructor Destroy; override;
    function EventType: TAgentEventType; override;
    property Message: TAgentMessage read FMessage;
    property AssistantMessageEvent: TAssistantMessageEvent read FAssistantMessageEvent;
  end;

  TStreamDeltaType = (sdtText, sdtThinking, sdtToolCall);

  TStreamDeltaEvent = class(TAgentEvent)
  private
    FDeltaText: string;
    FDeltaType: TStreamDeltaType;
  public
    constructor Create(const ADeltaText: string; ADeltaType: TStreamDeltaType);
    function EventType: TAgentEventType; override;
    property DeltaText: string read FDeltaText;
    property DeltaType: TStreamDeltaType read FDeltaType;
  end;

  TMessageEndEvent = class(TAgentEvent)
  private
    FMessage: TAgentMessage;
  public
    constructor Create(AMessage: TAgentMessage);
    destructor Destroy; override;
    function EventType: TAgentEventType; override;
    property Message: TAgentMessage read FMessage;
  end;

  TToolExecutionStartEvent = class(TAgentEvent)
  private
    FToolCallId: string;
    FToolName: string;
    FArgs: TJSONObject;
  public
    constructor Create(const AToolCallId, AToolName: string; AArgs: TJSONObject);
    destructor Destroy; override;
    function EventType: TAgentEventType; override;
    property ToolCallId: string read FToolCallId;
    property ToolName: string read FToolName;
    property Args: TJSONObject read FArgs;
  end;

  TToolExecutionUpdateEvent = class(TAgentEvent)
  private
    FToolCallId: string;
    FToolName: string;
    FPartialResult: string;
  public
    constructor Create(const AToolCallId, AToolName, APartialResult: string);
    function EventType: TAgentEventType; override;
    property ToolCallId: string read FToolCallId;
    property ToolName: string read FToolName;
    property PartialResult: string read FPartialResult;
  end;

  TToolExecutionEndEvent = class(TAgentEvent)
  private
    FToolCallId: string;
    FToolName: string;
    FResult: string;
    FIsError: Boolean;
  public
    constructor Create(const AToolCallId, AToolName, AResult: string;
      AIsError: Boolean);
    function EventType: TAgentEventType; override;
    property ToolCallId: string read FToolCallId;
    property ToolName: string read FToolName;
    property Result: string read FResult;
    property IsError: Boolean read FIsError;
  end;

  TToolConfirmationRequestEvent = class(TAgentEvent)
  private
    FToolCallId: string;
    FToolName: string;
    FFilePath: string;
    FDiffPreview: string;
    FArgs: TJSONObject;
  public
    constructor Create(const AToolCallId, AToolName, AFilePath,
      ADiffPreview: string; AArgs: TJSONObject);
    destructor Destroy; override;
    function EventType: TAgentEventType; override;
    property ToolCallId: string read FToolCallId;
    property ToolName: string read FToolName;
    property FilePath: string read FFilePath;
    property DiffPreview: string read FDiffPreview;
    property Args: TJSONObject read FArgs;
  end;

  TAgentErrorEvent = class(TAgentEvent)
  private
    FErrorMessage: string;
  public
    constructor Create(const AErrorMessage: string);
    function EventType: TAgentEventType; override;
    property ErrorMessage: string read FErrorMessage;
  end;

  // --- Event Stream (replaces TS AsyncIterable) ---

  TAgentEventStream = class
  private
    FQueue: TQueue<TAgentEvent>;
    FWaitEvent: TEvent;
    FDone: Boolean;
    FFinalMessages: TAgentMessageList;
    FLock: TObject;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Push(AEvent: TAgentEvent);
    procedure EndStream(AMessages: TAgentMessageList);
    function Next(ATimeoutMs: Cardinal = INFINITE): TAgentEvent;
    function IsDone: Boolean;
    function GetResult: TAgentMessageList;
  end;

  // --- Event Dispatcher (replaces TS Set of listeners) ---

  TAgentEventHandler = reference to procedure(AEvent: TAgentEvent);

  TSubscription = record
    Id: Integer;
    Handler: TAgentEventHandler;
  end;

  TEventDispatcher = class
  private
    FHandlers: TArray<TSubscription>;
    FHandlerCount: Integer;
    FHandlerCapacity: Integer;
    FNextId: Integer;
    FLock: TCriticalSection;
    FDestroyed: Boolean;
    FSnapCache: TArray<TSubscription>;  // Pre-allocated snapshot cache
    FSnapCacheCap: Integer;
    procedure GrowHandlers;
  public
    constructor Create;
    destructor Destroy; override;

    function Subscribe(AHandler: TAgentEventHandler): Integer;
    procedure Unsubscribe(AId: Integer);
    procedure DispatchEvent(AEvent: TAgentEvent);
    function HandlerCount: Integer;
  end;

implementation

{ TStartEvent }

constructor TStartEvent.Create(APartial: TAssistantMessage);
begin
  inherited Create;
  FPartial := APartial;
end;

destructor TStartEvent.Destroy;
begin
  FPartial.Free;
  inherited;
end;

function TStartEvent.EventType: TAssistantMessageEventType;
begin
  Result := ametStart;
end;

function TStartEvent.PartialMessage: TAssistantMessage;
begin
  Result := FPartial;
end;

{ TTextDeltaEvent }

constructor TTextDeltaEvent.Create(AContentIndex: Integer;
  const ADelta: string; APartial: TAssistantMessage);
begin
  inherited Create;
  FContentIndex := AContentIndex;
  FDelta := ADelta;
  FPartial := APartial;
end;

function TTextDeltaEvent.EventType: TAssistantMessageEventType;
begin
  Result := ametTextDelta;
end;

function TTextDeltaEvent.PartialMessage: TAssistantMessage;
begin
  Result := FPartial;
end;

destructor TTextDeltaEvent.Destroy;
begin
  // Delta events do NOT own FPartial — it is a borrowed reference.
  // Only free if we explicitly took ownership (FPartialOwns = True).
  FPartial := nil;
  inherited;
end;

{ TThinkingDeltaEvent }

constructor TThinkingDeltaEvent.Create(AContentIndex: Integer;
  const ADelta: string; APartial: TAssistantMessage);
begin
  inherited Create;
  FContentIndex := AContentIndex;
  FDelta := ADelta;
  FPartial := APartial;
end;

function TThinkingDeltaEvent.EventType: TAssistantMessageEventType;
begin
  Result := ametThinkingDelta;
end;

function TThinkingDeltaEvent.PartialMessage: TAssistantMessage;
begin
  Result := FPartial;
end;

destructor TThinkingDeltaEvent.Destroy;
begin
  // Delta events do NOT own FPartial — it is a borrowed reference.
  FPartial := nil;
  inherited;
end;

{ TToolCallDeltaEvent }

constructor TToolCallDeltaEvent.Create(AContentIndex: Integer;
  const ADelta: string; APartial: TAssistantMessage);
begin
  inherited Create;
  FContentIndex := AContentIndex;
  FDelta := ADelta;
  FPartial := APartial;
end;

function TToolCallDeltaEvent.EventType: TAssistantMessageEventType;
begin
  Result := ametToolCallDelta;
end;

function TToolCallDeltaEvent.PartialMessage: TAssistantMessage;
begin
  Result := FPartial;
end;

destructor TToolCallDeltaEvent.Destroy;
begin
  // Delta events do NOT own FPartial — it is a borrowed reference.
  FPartial := nil;
  inherited;
end;

{ TDoneEvent }

constructor TDoneEvent.Create(AReason: TStopReason;
  AMessage: TAssistantMessage);
begin
  inherited Create;
  FReason := AReason;
  FMessage := AMessage;
end;

destructor TDoneEvent.Destroy;
begin
  FMessage.Free;
  inherited;
end;

function TDoneEvent.EventType: TAssistantMessageEventType;
begin
  Result := ametDone;
end;

function TDoneEvent.PartialMessage: TAssistantMessage;
begin
  Result := FMessage;
end;

{ TErrorEvent }

constructor TErrorEvent.Create(AReason: TStopReason;
  AError: TAssistantMessage);
begin
  inherited Create;
  FReason := AReason;
  FError := AError;
end;

destructor TErrorEvent.Destroy;
begin
  FError.Free;
  inherited;
end;

function TErrorEvent.EventType: TAssistantMessageEventType;
begin
  Result := ametError;
end;

function TErrorEvent.PartialMessage: TAssistantMessage;
begin
  Result := FError;
end;

{ TAgentStartEvent }

function TAgentStartEvent.EventType: TAgentEventType;
begin
  Result := aetAgentStart;
end;

{ TAgentEndEvent }

constructor TAgentEndEvent.Create(AMessages: TAgentMessageList);
begin
  inherited Create;
  FMessages := AMessages;
end;

destructor TAgentEndEvent.Destroy;
begin
  FMessages.Free;
  inherited;
end;

function TAgentEndEvent.EventType: TAgentEventType;
begin
  Result := aetAgentEnd;
end;

{ TTurnStartEvent }

function TTurnStartEvent.EventType: TAgentEventType;
begin
  Result := aetTurnStart;
end;

{ TTurnEndEvent }

constructor TTurnEndEvent.Create(AMessage: TAssistantMessage;
  const AToolResults: TArray<TToolResultMessage>);
begin
  inherited Create;
  FMessage := AMessage;
  FToolResults := AToolResults;
end;

destructor TTurnEndEvent.Destroy;
var
  i: Integer;
begin
  FMessage.Free;
  for i := 0 to High(FToolResults) do
    FToolResults[i].Free;
  inherited;
end;

function TTurnEndEvent.EventType: TAgentEventType;
begin
  Result := aetTurnEnd;
end;

{ TMessageStartEvent }

constructor TMessageStartEvent.Create(AMessage: TAgentMessage);
begin
  inherited Create;
  FMessage := AMessage;
end;

destructor TMessageStartEvent.Destroy;
begin
  FMessage.Free;
  inherited;
end;

function TMessageStartEvent.EventType: TAgentEventType;
begin
  Result := aetMessageStart;
end;

{ TMessageUpdateEvent }

constructor TMessageUpdateEvent.Create(AMessage: TAgentMessage;
  AAssistantMessageEvent: TAssistantMessageEvent);
begin
  inherited Create;
  FMessage := AMessage;
  FAssistantMessageEvent := AAssistantMessageEvent;
end;

destructor TMessageUpdateEvent.Destroy;
begin
  FMessage.Free;
  FAssistantMessageEvent.Free;
  inherited;
end;

function TMessageUpdateEvent.EventType: TAgentEventType;
begin
  Result := aetMessageUpdate;
end;

{ TStreamDeltaEvent }

constructor TStreamDeltaEvent.Create(const ADeltaText: string;
  ADeltaType: TStreamDeltaType);
begin
  inherited Create;
  FDeltaText := ADeltaText;
  FDeltaType := ADeltaType;
end;

function TStreamDeltaEvent.EventType: TAgentEventType;
begin
  Result := aetMessageUpdate;
end;

{ TMessageEndEvent }

constructor TMessageEndEvent.Create(AMessage: TAgentMessage);
begin
  inherited Create;
  FMessage := AMessage;
end;

destructor TMessageEndEvent.Destroy;
begin
  FMessage.Free;
  inherited;
end;

function TMessageEndEvent.EventType: TAgentEventType;
begin
  Result := aetMessageEnd;
end;

{ TToolExecutionStartEvent }

constructor TToolExecutionStartEvent.Create(const AToolCallId,
  AToolName: string; AArgs: TJSONObject);
begin
  inherited Create;
  FToolCallId := AToolCallId;
  FToolName := AToolName;
  FArgs := AArgs;
end;

destructor TToolExecutionStartEvent.Destroy;
begin
  FArgs.Free;
  inherited;
end;

function TToolExecutionStartEvent.EventType: TAgentEventType;
begin
  Result := aetToolExecutionStart;
end;

{ TToolExecutionUpdateEvent }

constructor TToolExecutionUpdateEvent.Create(const AToolCallId,
  AToolName, APartialResult: string);
begin
  inherited Create;
  FToolCallId := AToolCallId;
  FToolName := AToolName;
  FPartialResult := APartialResult;
end;

function TToolExecutionUpdateEvent.EventType: TAgentEventType;
begin
  Result := aetToolExecutionUpdate;
end;

{ TToolExecutionEndEvent }

constructor TToolExecutionEndEvent.Create(const AToolCallId, AToolName,
  AResult: string; AIsError: Boolean);
begin
  inherited Create;
  FToolCallId := AToolCallId;
  FToolName := AToolName;
  FResult := AResult;
  FIsError := AIsError;
end;

function TToolExecutionEndEvent.EventType: TAgentEventType;
begin
  Result := aetToolExecutionEnd;
end;

{ TToolConfirmationRequestEvent }

constructor TToolConfirmationRequestEvent.Create(const AToolCallId, AToolName,
  AFilePath, ADiffPreview: string; AArgs: TJSONObject);
begin
  inherited Create;
  FToolCallId := AToolCallId;
  FToolName := AToolName;
  FFilePath := AFilePath;
  FDiffPreview := ADiffPreview;
  FArgs := AArgs;
end;

destructor TToolConfirmationRequestEvent.Destroy;
begin
  FArgs.Free;
  inherited;
end;

function TToolConfirmationRequestEvent.EventType: TAgentEventType;
begin
  Result := aetToolConfirmationRequest;
end;

{ TAgentErrorEvent }

constructor TAgentErrorEvent.Create(const AErrorMessage: string);
begin
  inherited Create;
  FErrorMessage := AErrorMessage;
end;

function TAgentErrorEvent.EventType: TAgentEventType;
begin
  Result := aetError;
end;

{ TAgentEventStream }

constructor TAgentEventStream.Create;
begin
  inherited Create;
  FQueue := TQueue<TAgentEvent>.Create;
  FWaitEvent := TEvent.Create(nil, True, False, '');
  FDone := False;
  FFinalMessages := nil;
  FLock := TObject.Create;
end;

destructor TAgentEventStream.Destroy;
var
  Event: TAgentEvent;
begin
  // Free any remaining events in queue
  while FQueue.Count > 0 do
  begin
    Event := FQueue.Dequeue;
    Event.Free;
  end;
  FQueue.Free;
  FWaitEvent.Free;
  FLock.Free;
  // Note: FFinalMessages is not freed here - caller takes ownership
  inherited;
end;

procedure TAgentEventStream.Push(AEvent: TAgentEvent);
begin
  TMonitor.Enter(FLock);
  try
    FQueue.Enqueue(AEvent);
    FWaitEvent.SetEvent;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TAgentEventStream.EndStream(AMessages: TAgentMessageList);
begin
  TMonitor.Enter(FLock);
  try
    FDone := True;
    FFinalMessages := AMessages;
    FWaitEvent.SetEvent;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TAgentEventStream.Next(ATimeoutMs: Cardinal): TAgentEvent;
var
  WaitResult: TWaitResult;
begin
  Result := nil;
  while True do
  begin
    TMonitor.Enter(FLock);
    try
      if FQueue.Count > 0 then
      begin
        Result := FQueue.Dequeue;
        if FQueue.Count = 0 then
          FWaitEvent.ResetEvent;
        Exit;
      end;
      if FDone then
        Exit;  // Returns nil to signal end
    finally
      TMonitor.Exit(FLock);
    end;

    WaitResult := FWaitEvent.WaitFor(ATimeoutMs);
    if WaitResult <> wrSignaled then
      Exit;  // Timeout - return nil
  end;
end;

function TAgentEventStream.IsDone: Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := FDone and (FQueue.Count = 0);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TAgentEventStream.GetResult: TAgentMessageList;
begin
  Result := FFinalMessages;
end;

{ TEventDispatcher }

constructor TEventDispatcher.Create;
begin
  inherited Create;
  FHandlers := nil;
  FHandlerCount := 0;
  FHandlerCapacity := 0;
  FNextId := 1;
  FLock := TCriticalSection.Create;
  FDestroyed := False;
  FSnapCache := nil;
  FSnapCacheCap := 0;
end;

destructor TEventDispatcher.Destroy;
begin
  FLock.Acquire;
  try
    FDestroyed := True;
    FHandlers := nil;
    FHandlerCount := 0;
  finally
    FLock.Release;
  end;
  FLock.Free;
  inherited;
end;

procedure TEventDispatcher.GrowHandlers;
var
  NewCap, i: Integer;
  NewHandlers: TArray<TSubscription>;
begin
  if FHandlerCapacity = 0 then
    FHandlerCapacity := 4
  else
    FHandlerCapacity := FHandlerCapacity * 2;
  if FHandlerCapacity > Length(FHandlers) then
  begin
    NewCap := FHandlerCapacity;
    SetLength(NewHandlers, NewCap);
    for i := 0 to FHandlerCount - 1 do
      NewHandlers[i] := FHandlers[i];
    FHandlers := NewHandlers;
  end;
end;

function TEventDispatcher.Subscribe(AHandler: TAgentEventHandler): Integer;
var
  Sub: TSubscription;
begin
  FLock.Acquire;
  try
    Sub.Id := FNextId;
    Sub.Handler := AHandler;
    if FHandlerCount >= Length(FHandlers) then
      GrowHandlers;
    FHandlers[FHandlerCount] := Sub;
    Inc(FHandlerCount);
    Inc(FNextId);
    Result := Sub.Id;
  finally
    FLock.Release;
  end;
end;

procedure TEventDispatcher.Unsubscribe(AId: Integer);
var
  i, FoundIdx: Integer;
begin
  FLock.Acquire;
  try
    FoundIdx := -1;
    for i := 0 to FHandlerCount - 1 do
    begin
      if FHandlers[i].Id = AId then
      begin
        FoundIdx := i;
        Break;
      end;
    end;

    if FoundIdx >= 0 then
    begin
      for i := FoundIdx to FHandlerCount - 2 do
        FHandlers[i] := FHandlers[i + 1];
      Dec(FHandlerCount);
      FHandlers[FHandlerCount] := Default(TSubscription);
    end;
  finally
    FLock.Release;
  end;
end;

procedure TEventDispatcher.DispatchEvent(AEvent: TAgentEvent);
var
  CopyCount, i: Integer;
begin
  FLock.Acquire;
  try
    if FDestroyed then
    begin
      AEvent.Free;
      Exit;
    end;
    CopyCount := FHandlerCount;
    if CopyCount = 0 then
    begin
      AEvent.Free;
      Exit;
    end;
    // Sanity check: FHandlers must be valid
    if (FHandlers = nil) or (CopyCount > Length(FHandlers)) then
    begin
      AEvent.Free;
      Exit;
    end;
    // Grow snapshot cache if needed (avoids per-dispatch allocation)
    if CopyCount > FSnapCacheCap then
    begin
      FSnapCacheCap := CopyCount + 4;
      SetLength(FSnapCache, FSnapCacheCap);
    end;
    for i := 0 to CopyCount - 1 do
      FSnapCache[i] := FHandlers[i];
  finally
    FLock.Release;
  end;

  for i := 0 to CopyCount - 1 do
  try
    if FSnapCache[i].Handler <> nil then
      FSnapCache[i].Handler(AEvent);
  except
    on E: Exception do
      ; // Swallow handler exceptions so remaining handlers still execute
  end;

  AEvent.Free;
end;

function TEventDispatcher.HandlerCount: Integer;
begin
  FLock.Acquire;
  try
    Result := FHandlerCount;
  finally
    FLock.Release;
  end;
end;

end.
