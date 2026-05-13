unit Core.AgentState;

interface

uses
  System.SysUtils, System.Generics.Collections, System.JSON,
  System.SyncObjs, Core.Messages, Settings.Config;

type
  // Abort controller for cancelling operations
  TAbortController = class
  private
    FAborted: Integer;  // 0 = not aborted, 1 = aborted (atomic)
    FEvent: TEvent;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Abort;
    function IsAborted: Boolean;
    procedure Reset;
    property Aborted: Boolean read IsAborted;
  end;

  // Tool execution result
  TToolResult = record
    Content: TContentBlockList;
    IsError: Boolean;
    class function Create(AContent: TContentBlockList; AIsError: Boolean): TToolResult; static;
    class function CreateText(const AText: string): TToolResult; static;
    class function CreateError(const AMessage: string): TToolResult; static;
    procedure ReleaseContent;
  end;

  // Abort check callback
  TAbortedCallback = reference to function: Boolean;

  // Tool interface - implemented by all tools
  IAgentTool = interface
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}']
    function GetName: string;
    function GetLabel: string;
    function GetDescription: string;
    function GetParameterSchema: TJSONObject;
    function Execute(const AToolCallId: string; AParams: TJSONObject;
      AIsAborted: TAbortedCallback): TToolResult;
  end;

  TToolCallSet = class
  private
    FData: TList<string>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AId: string);
    procedure Remove(const AId: string);
    function Contains(const AId: string): Boolean;
    procedure Clear;
    function ToArray: TArray<string>;
    function Count: Integer;
  end;

  TAgentState = record
    SystemPrompt: string;
    Model: TModelConfig;
    ThinkingLevel: TThinkingLevel;
    Tools: TArray<IAgentTool>;
    Messages: TAgentMessageList;
    StreamingFlag: Integer;    // 0 = not streaming, 1 = streaming (atomic)
    StreamMessage: TAgentMessage;
    PendingToolCalls: TToolCallSet;
    Permissions: TToolPermissions;
    Error: string;

    class function Create: TAgentState; static;
    procedure Reset;
    function FindTool(const AName: string): IAgentTool;
    function GetIsStreaming: Boolean;
    procedure SetIsStreaming(AValue: Boolean);
    property IsStreaming: Boolean read GetIsStreaming write SetIsStreaming;
  end;

implementation

{ TAbortController }

constructor TAbortController.Create;
begin
  inherited Create;
  FAborted := 0;
  FEvent := TEvent.Create(nil, True, False, '');
end;

destructor TAbortController.Destroy;
begin
  FEvent.Free;
  inherited;
end;

procedure TAbortController.Abort;
begin
  TInterlocked.Exchange(FAborted, 1);
  FEvent.SetEvent;
end;

function TAbortController.IsAborted: Boolean;
begin
  Result := FAborted = 1;
end;

procedure TAbortController.Reset;
begin
  TInterlocked.Exchange(FAborted, 0);
  FEvent.ResetEvent;
end;

{ TToolResult }

class function TToolResult.Create(AContent: TContentBlockList;
  AIsError: Boolean): TToolResult;
begin
  Result.Content := AContent;
  Result.IsError := AIsError;
end;

class function TToolResult.CreateText(const AText: string): TToolResult;
var
  List: TContentBlockList;
begin
  List := TContentBlockList.Create;
  List.Add(TTextContent.Create(AText));
  Result := TToolResult.Create(List, False);
end;

class function TToolResult.CreateError(const AMessage: string): TToolResult;
var
  List: TContentBlockList;
begin
  List := TContentBlockList.Create;
  List.Add(TTextContent.Create('Error: ' + AMessage));
  Result := TToolResult.Create(List, True);
end;

procedure TToolResult.ReleaseContent;
begin
  Content.Free;
  Content := nil;
end;

{ TToolCallSet }

constructor TToolCallSet.Create;
begin
  inherited Create;
  FData := TList<string>.Create;
end;

destructor TToolCallSet.Destroy;
begin
  FData.Free;
  inherited;
end;

procedure TToolCallSet.Add(const AId: string);
begin
  if not Contains(AId) then
    FData.Add(AId);
end;

procedure TToolCallSet.Remove(const AId: string);
var
  Idx: Integer;
begin
  Idx := FData.IndexOf(AId);
  if Idx >= 0 then
    FData.Delete(Idx);
end;

function TToolCallSet.Contains(const AId: string): Boolean;
begin
  Result := FData.IndexOf(AId) >= 0;
end;

procedure TToolCallSet.Clear;
begin
  FData.Clear;
end;

function TToolCallSet.ToArray: TArray<string>;
begin
  Result := FData.ToArray;
end;

function TToolCallSet.Count: Integer;
begin
  Result := FData.Count;
end;

{ TAgentState }

class function TAgentState.Create: TAgentState;
begin
  Result.SystemPrompt := '';
  Result.Model := TModelConfig.GetDefault;
  Result.ThinkingLevel := tlMedium;
  Result.Tools := nil;
  Result.Messages := TAgentMessageList.Create;
  Result.StreamingFlag := 0;
  Result.StreamMessage := nil;
  Result.PendingToolCalls := TToolCallSet.Create;
  Result.Permissions := TPiMonoConfig.GetDefault.Permissions;
  Result.Error := '';
end;

procedure TAgentState.Reset;
begin
  if Messages <> nil then
    Messages.Clear;
  StreamingFlag := 0;
  StreamMessage := nil;
  if PendingToolCalls <> nil then
    PendingToolCalls.Clear;
  Error := '';
  // Do NOT nil Messages or PendingToolCalls here — they are owned by TAgent
  // and freed in its destructor. Nilling them would cause the destructor
  // to skip freeing, leaking memory.
end;

function TAgentState.GetIsStreaming: Boolean;
begin
  Result := StreamingFlag = 1;
end;

procedure TAgentState.SetIsStreaming(AValue: Boolean);
begin
  if AValue then
    TInterlocked.Exchange(StreamingFlag, 1)
  else
    TInterlocked.Exchange(StreamingFlag, 0);
end;

function TAgentState.FindTool(const AName: string): IAgentTool;
var
  i: Integer;
begin
  for i := 0 to High(Tools) do
    if SameText(Tools[i].GetName, AName) then
      Exit(Tools[i]);
  Result := nil;
end;

end.
