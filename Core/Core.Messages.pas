unit Core.Messages;

interface

uses
  System.SysUtils, System.JSON, System.Generics.Collections,
  System.Classes, System.DateUtils, Utils.JsonHelper;

type
  // --- Content Block Types ---

  TContentBlockType = (
    cbtText,
    cbtThinking,
    cbtImage,
    cbtToolCall
  );

  TContentBlock = class abstract
  public
    function ContentType: TContentBlockType; virtual; abstract;
    function Clone: TContentBlock; virtual; abstract;
    function ToJson: TJSONObject; virtual; abstract;
    class function FromJson(AJson: TJSONObject): TContentBlock; static;
  end;

  TTextContent = class(TContentBlock)
  private
    FText: string;
  public
    constructor Create(const AText: string);
    function ContentType: TContentBlockType; override;
    function Clone: TContentBlock; override;
    function ToJson: TJSONObject; override;
    property Text: string read FText write FText;
  end;

  TThinkingContent = class(TContentBlock)
  private
    FThinking: string;
  public
    constructor Create(const AThinking: string);
    function ContentType: TContentBlockType; override;
    function Clone: TContentBlock; override;
    function ToJson: TJSONObject; override;
    property Thinking: string read FThinking write FThinking;
  end;

  TImageContent = class(TContentBlock)
  private
    FData: string;
    FMimeType: string;
  public
    constructor Create(const AData, AMimeType: string);
    function ContentType: TContentBlockType; override;
    function Clone: TContentBlock; override;
    function ToJson: TJSONObject; override;
    property Data: string read FData write FData;
    property MimeType: string read FMimeType write FMimeType;
  end;

  TToolCall = class(TContentBlock)
  private
    FId: string;
    FName: string;
    FArguments: TJSONObject;
  public
    constructor Create(const AId, AName: string; AArguments: TJSONObject);
    destructor Destroy; override;
    function ContentType: TContentBlockType; override;
    function Clone: TContentBlock; override;
    function ToJson: TJSONObject; override;
    property Id: string read FId write FId;
    property Name: string read FName write FName;
    property Arguments: TJSONObject read FArguments;
  end;

  // --- Content Block List ---

  TContentBlockList = class
  private
    FItems: TArray<TContentBlock>;
    FCount: Integer;
    FCapacity: Integer;
    procedure Grow;
    function GetCount: Integer;
    function GetItem(AIndex: Integer): TContentBlock;
  public
    destructor Destroy; override;
    procedure Add(AItem: TContentBlock);
    procedure Clear;
    function Clone: TContentBlockList;
    function FindToolCalls: TArray<TToolCall>;
    function ToJson: TJSONArray;
    class function FromJson(AArr: TJSONArray): TContentBlockList; static;
    property Count: Integer read GetCount;
    property Items[AIndex: Integer]: TContentBlock read GetItem; default;
  end;

  // --- Usage and Cost ---

  TCostInfo = record
    Input: Double;
    Output: Double;
    CacheRead: Double;
    CacheWrite: Double;
    Total: Double;
    class function Empty: TCostInfo; static;
  end;

  TUsage = record
    Input: Integer;
    Output: Integer;
    CacheRead: Integer;
    CacheWrite: Integer;
    TotalTokens: Integer;
    Cost: TCostInfo;
    class function Empty: TUsage; static;
  end;

  TStopReason = (
    srStop,
    srLength,
    srToolUse,
    srError,
    srAborted
  );

  // --- Message Types ---

  TMessageRole = (
    mrUser,
    mrAssistant,
    mrToolResult
  );

  TAgentMessage = class abstract
  private
    FRole: TMessageRole;
    FTimestamp: TDateTime;
  public
    constructor Create(ARole: TMessageRole);
    function Clone: TAgentMessage; virtual; abstract;
    function ToJson: TJSONObject; virtual; abstract;
    class function FromJson(AJson: TJSONObject): TAgentMessage; static;
    property Role: TMessageRole read FRole;
    property Timestamp: TDateTime read FTimestamp write FTimestamp;
  end;

  TUserMessage = class(TAgentMessage)
  private
    FContent: string;
    FContentBlocks: TContentBlockList;
    FHasStructuredContent: Boolean;
    FIsCompactionSummary: Boolean;
  public
    constructor Create(const AText: string); overload;
    constructor Create(ABlocks: TContentBlockList); overload;
    destructor Destroy; override;
    function Clone: TAgentMessage; override;
    function ToJson: TJSONObject; override;
    property Content: string read FContent;
    property ContentBlocks: TContentBlockList read FContentBlocks;
    property HasStructuredContent: Boolean read FHasStructuredContent;
    property IsCompactionSummary: Boolean read FIsCompactionSummary write FIsCompactionSummary;
  end;

  TAssistantMessage = class(TAgentMessage)
  private
    FContent: TContentBlockList;
    FApi: string;
    FProvider: string;
    FModel: string;
    FUsage: TUsage;
    FStopReason: TStopReason;
    FErrorMessage: string;
  public
    constructor Create;
    destructor Destroy; override;
    function Clone: TAgentMessage; override;
    function ToJson: TJSONObject; override;
    property Content: TContentBlockList read FContent;
    property Api: string read FApi write FApi;
    property Provider: string read FProvider write FProvider;
    property Model: string read FModel write FModel;
    property Usage: TUsage read FUsage write FUsage;
    property StopReason: TStopReason read FStopReason write FStopReason;
    property ErrorMessage: string read FErrorMessage write FErrorMessage;
  end;

  TToolResultMessage = class(TAgentMessage)
  private
    FToolCallId: string;
    FToolName: string;
    FContent: TContentBlockList;
    FDetails: TJSONObject;
    FIsError: Boolean;
  public
    constructor Create(const AToolCallId, AToolName: string;
      AContent: TContentBlockList; AIsError: Boolean);
    destructor Destroy; override;
    function Clone: TAgentMessage; override;
    function ToJson: TJSONObject; override;
    property ToolCallId: string read FToolCallId;
    property ToolName: string read FToolName;
    property Content: TContentBlockList read FContent;
    property Details: TJSONObject read FDetails write FDetails;
    property IsError: Boolean read FIsError;
  end;

  // --- Message List ---

  TAgentMessageList = class
  private
    FItems: TArray<TAgentMessage>;
    FCount: Integer;
    FCapacity: Integer;
    procedure Grow;
    function GetCount: Integer;
    function GetItem(AIndex: Integer): TAgentMessage;
  public
    destructor Destroy; override;
    procedure Add(AMessage: TAgentMessage);
    procedure Clear;
    function ExtractAll: TArray<TAgentMessage>;
    function Last: TAgentMessage;
    function Clone: TAgentMessageList;
    function ToArray: TArray<TAgentMessage>;
    procedure Delete(AIndex: Integer);
    property Count: Integer read GetCount;
    property Items[AIndex: Integer]: TAgentMessage read GetItem; default;
  end;

function MessageRoleToString(ARole: TMessageRole): string;
function StopReasonToString(AReason: TStopReason): string;
function StringToStopReason(const AValue: string): TStopReason;

implementation

{ TContentBlock }

class function TContentBlock.FromJson(AJson: TJSONObject): TContentBlock;
var
  TypeVal: string;
  ArgsObj: TJSONObject;
begin
  TypeVal := AJson.GetValue<string>('type');
  if TypeVal = 'text' then
    Result := TTextContent.Create(AJson.GetValue<string>('text'))
  else if TypeVal = 'thinking' then
    Result := TThinkingContent.Create(AJson.GetValue<string>('thinking'))
  else if TypeVal = 'image' then
    Result := TImageContent.Create(
      AJson.GetValue<string>('data'),
      AJson.GetValue<string>('mimeType'))
  else if TypeVal = 'toolCall' then
  begin
    ArgsObj := AJson.GetValue('arguments') as TJSONObject;
    if ArgsObj <> nil then
      ArgsObj := ArgsObj.Clone as TJSONObject;
    Result := TToolCall.Create(
      AJson.GetValue<string>('id'),
      AJson.GetValue<string>('name'),
      ArgsObj);
  end
  else
    Result := TTextContent.Create(AJson.ToString);
end;

{ TTextContent }

constructor TTextContent.Create(const AText: string);
begin
  inherited Create;
  FText := AText;
end;

function TTextContent.ContentType: TContentBlockType;
begin
  Result := cbtText;
end;

function TTextContent.Clone: TContentBlock;
begin
  Result := TTextContent.Create(FText);
end;

function TTextContent.ToJson: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'text');
  Result.AddPair('text', FText);
end;

{ TThinkingContent }

constructor TThinkingContent.Create(const AThinking: string);
begin
  inherited Create;
  FThinking := AThinking;
end;

function TThinkingContent.ContentType: TContentBlockType;
begin
  Result := cbtThinking;
end;

function TThinkingContent.Clone: TContentBlock;
begin
  Result := TThinkingContent.Create(FThinking);
end;

function TThinkingContent.ToJson: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'thinking');
  Result.AddPair('thinking', FThinking);
end;

{ TImageContent }

constructor TImageContent.Create(const AData, AMimeType: string);
begin
  inherited Create;
  FData := AData;
  FMimeType := AMimeType;
end;

function TImageContent.ContentType: TContentBlockType;
begin
  Result := cbtImage;
end;

function TImageContent.Clone: TContentBlock;
begin
  Result := TImageContent.Create(FData, FMimeType);
end;

function TImageContent.ToJson: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'image');
  Result.AddPair('data', FData);
  Result.AddPair('mimeType', FMimeType);
end;

{ TToolCall }

constructor TToolCall.Create(const AId, AName: string;
  AArguments: TJSONObject);
begin
  inherited Create;
  FId := AId;
  FName := AName;
  FArguments := AArguments;
end;

destructor TToolCall.Destroy;
begin
  FArguments.Free;
  inherited;
end;

function TToolCall.ContentType: TContentBlockType;
begin
  Result := cbtToolCall;
end;

function TToolCall.Clone: TContentBlock;
begin
  if FArguments <> nil then
    Result := TToolCall.Create(FId, FName,
      TJSONObject(FArguments.Clone))
  else
    Result := TToolCall.Create(FId, FName, TJSONObject.Create);
end;

function TToolCall.ToJson: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'toolCall');
  Result.AddPair('id', FId);
  Result.AddPair('name', FName);
  if FArguments <> nil then
    Result.AddPair('arguments', TJSONObject(FArguments.Clone))
  else
    Result.AddPair('arguments', TJSONObject.Create);
end;

{ TContentBlockList }

destructor TContentBlockList.Destroy;
begin
  Clear;
  inherited;
end;

procedure TContentBlockList.Grow;
begin
  if FCapacity = 0 then
    FCapacity := 4
  else
    FCapacity := FCapacity * 2;
  if FCapacity > Length(FItems) then
    SetLength(FItems, FCapacity);
end;

procedure TContentBlockList.Add(AItem: TContentBlock);
begin
  if FCount >= Length(FItems) then
    Grow;
  FItems[FCount] := AItem;
  Inc(FCount);
end;

procedure TContentBlockList.Clear;
var
  i: Integer;
begin
  for i := 0 to FCount - 1 do
    FItems[i].Free;
  FCount := 0;
  FCapacity := 0;
  FItems := nil;
end;

function TContentBlockList.Clone: TContentBlockList;
var
  i: Integer;
begin
  Result := TContentBlockList.Create;
  Result.FCapacity := FCount;
  SetLength(Result.FItems, FCount);
  for i := 0 to FCount - 1 do
    Result.FItems[i] := FItems[i].Clone;
  Result.FCount := FCount;
end;

function TContentBlockList.FindToolCalls: TArray<TToolCall>;
var
  i, Cnt, Cap: Integer;
begin
  Cap := 0;
  Cnt := 0;
  Result := nil;
  for i := 0 to FCount - 1 do
  begin
    if FItems[i].ContentType = cbtToolCall then
    begin
      if Cnt >= Cap then
      begin
        if Cap = 0 then
          Cap := 4
        else
          Cap := Cap * 2;
        SetLength(Result, Cap);
      end;
      Result[Cnt] := TToolCall(FItems[i]);
      Inc(Cnt);
    end;
  end;
  SetLength(Result, Cnt);
end;

function TContentBlockList.GetCount: Integer;
begin
  Result := FCount;
end;

function TContentBlockList.GetItem(AIndex: Integer): TContentBlock;
begin
  if (AIndex < 0) or (AIndex >= FCount) then
    raise EArgumentOutOfRangeException.CreateFmt('ContentBlockList index %d out of range [0..%d]', [AIndex, FCount - 1]);
  Result := FItems[AIndex];
end;

function TContentBlockList.ToJson: TJSONArray;
var
  i: Integer;
begin
  Result := TJSONArray.Create;
  for i := 0 to FCount - 1 do
    Result.AddElement(FItems[i].ToJson);
end;

class function TContentBlockList.FromJson(AArr: TJSONArray): TContentBlockList;
var
  i: Integer;
begin
  Result := TContentBlockList.Create;
  if AArr = nil then
    Exit;
  for i := 0 to AArr.Count - 1 do
    Result.Add(TContentBlock.FromJson(AArr.Items[i] as TJSONObject));
end;

{ TCostInfo }

class function TCostInfo.Empty: TCostInfo;
begin
  Result.Input := 0;
  Result.Output := 0;
  Result.CacheRead := 0;
  Result.CacheWrite := 0;
  Result.Total := 0;
end;

{ TUsage }

class function TUsage.Empty: TUsage;
begin
  Result.Input := 0;
  Result.Output := 0;
  Result.CacheRead := 0;
  Result.CacheWrite := 0;
  Result.TotalTokens := 0;
  Result.Cost := TCostInfo.Empty;
end;

{ TAgentMessage }

constructor TAgentMessage.Create(ARole: TMessageRole);
begin
  inherited Create;
  FRole := ARole;
  FTimestamp := Now;
end;

class function TAgentMessage.FromJson(AJson: TJSONObject): TAgentMessage;
var
  Role: string;
  ContentArr: TJSONArray;
  Content: TContentBlockList;
begin
  Result := nil;
  Role := JsonGetStr(AJson, 'role', '');
  if Role = 'user' then
  begin
    Result := TUserMessage.Create(JsonGetStr(AJson, 'content', ''));
    TUserMessage(Result).IsCompactionSummary := JsonGetBool(AJson, 'isCompactionSummary', False);
  end
  else if Role = 'assistant' then
  begin
    Result := TAssistantMessage.Create;
    var AsstMsg := TAssistantMessage(Result);
    ContentArr := AJson.GetValue('content') as TJSONArray;
    if ContentArr <> nil then
      for var j := 0 to ContentArr.Count - 1 do
        AsstMsg.Content.Add(TContentBlock.FromJson(ContentArr.Items[j] as TJSONObject));
    AsstMsg.Api := JsonGetStr(AJson, 'api', '');
    AsstMsg.Provider := JsonGetStr(AJson, 'provider', '');
    AsstMsg.Model := JsonGetStr(AJson, 'model', '');
    AsstMsg.StopReason := StringToStopReason(JsonGetStr(AJson, 'stopReason', 'stop'));
    AsstMsg.ErrorMessage := JsonGetStr(AJson, 'errorMessage', '');
  end
  else if Role = 'toolResult' then
  begin
    Content := TContentBlockList.Create;
    ContentArr := AJson.GetValue('content') as TJSONArray;
    if ContentArr <> nil then
      for var j := 0 to ContentArr.Count - 1 do
        Content.Add(TContentBlock.FromJson(ContentArr.Items[j] as TJSONObject));
    Result := TToolResultMessage.Create(
      JsonGetStr(AJson, 'toolCallId', ''),
      JsonGetStr(AJson, 'toolName', ''),
      Content,
      JsonGetBool(AJson, 'isError', False));
  end;

  if Result <> nil then
    Result.Timestamp := UnixToDateTime(JsonGetInt64(AJson, 'timestamp', 0), False);
end;

{ TUserMessage }

constructor TUserMessage.Create(const AText: string);
begin
  inherited Create(mrUser);
  FContent := AText;
  FContentBlocks := nil;
  FHasStructuredContent := False;
  FIsCompactionSummary := False;
end;

constructor TUserMessage.Create(ABlocks: TContentBlockList);
begin
  inherited Create(mrUser);
  FContent := '';
  FContentBlocks := ABlocks;
  FHasStructuredContent := True;
  FIsCompactionSummary := False;
end;

destructor TUserMessage.Destroy;
begin
  FContentBlocks.Free;
  inherited;
end;

function TUserMessage.Clone: TAgentMessage;
var
  Msg: TUserMessage;
begin
  if FHasStructuredContent then
    Msg := TUserMessage.Create(FContentBlocks.Clone)
  else
    Msg := TUserMessage.Create(FContent);
  Msg.Timestamp := FTimestamp;
  Msg.FIsCompactionSummary := FIsCompactionSummary;
  Result := Msg;
end;

function TUserMessage.ToJson: TJSONObject;
begin
  if Self = nil then
  begin
    Result := TJSONObject.Create;
    Result.AddPair('role', 'user');
    Exit;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('role', 'user');
  if FHasStructuredContent and (FContentBlocks <> nil) then
    Result.AddPair('content', FContentBlocks.ToJson)
  else
    Result.AddPair('content', FContent);
  Result.AddPair('timestamp', TJSONNumber.Create(DateTimeToUnix(FTimestamp, False)));
  if FIsCompactionSummary then
    Result.AddPair('isCompactionSummary', TJSONBool.Create(True));
end;

{ TAssistantMessage }

constructor TAssistantMessage.Create;
begin
  inherited Create(mrAssistant);
  FContent := TContentBlockList.Create;
  FUsage := TUsage.Empty;
  FStopReason := srStop;
end;

destructor TAssistantMessage.Destroy;
begin
  FContent.Free;
  inherited;
end;

function TAssistantMessage.Clone: TAgentMessage;
var
  Msg: TAssistantMessage;
begin
  Msg := TAssistantMessage.Create;
  Msg.Content.Clear;
  // Rebuild content from clone
  Msg.FContent.Free;
  Msg.FContent := FContent.Clone;
  Msg.Api := FApi;
  Msg.Provider := FProvider;
  Msg.Model := FModel;
  Msg.Usage := FUsage;
  Msg.StopReason := FStopReason;
  Msg.ErrorMessage := FErrorMessage;
  Msg.Timestamp := FTimestamp;
  Result := Msg;
end;

function TAssistantMessage.ToJson: TJSONObject;
var
  UsageObj, CostObj: TJSONObject;
begin
  if Self = nil then
  begin
    Result := TJSONObject.Create;
    Result.AddPair('role', 'assistant');
    Result.AddPair('content', TJSONArray.Create);
    Exit;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('role', 'assistant');
  if FContent <> nil then
    Result.AddPair('content', FContent.ToJson)
  else
    Result.AddPair('content', TJSONArray.Create);
  Result.AddPair('api', FApi);
  Result.AddPair('provider', FProvider);
  Result.AddPair('model', FModel);
  Result.AddPair('stopReason', StopReasonToString(FStopReason));
  if FErrorMessage <> '' then
    Result.AddPair('errorMessage', FErrorMessage);

  CostObj := TJSONObject.Create;
  CostObj.AddPair('input', TJSONNumber.Create(FUsage.Cost.Input));
  CostObj.AddPair('output', TJSONNumber.Create(FUsage.Cost.Output));
  CostObj.AddPair('total', TJSONNumber.Create(FUsage.Cost.Total));

  UsageObj := TJSONObject.Create;
  UsageObj.AddPair('input', TJSONNumber.Create(FUsage.Input));
  UsageObj.AddPair('output', TJSONNumber.Create(FUsage.Output));
  UsageObj.AddPair('cacheRead', TJSONNumber.Create(FUsage.CacheRead));
  UsageObj.AddPair('cacheWrite', TJSONNumber.Create(FUsage.CacheWrite));
  UsageObj.AddPair('totalTokens', TJSONNumber.Create(FUsage.TotalTokens));
  UsageObj.AddPair('cost', CostObj);
  Result.AddPair('usage', UsageObj);

  Result.AddPair('timestamp', TJSONNumber.Create(DateTimeToUnix(FTimestamp, False)));
end;

{ TToolResultMessage }

constructor TToolResultMessage.Create(const AToolCallId, AToolName: string;
  AContent: TContentBlockList; AIsError: Boolean);
begin
  inherited Create(mrToolResult);
  FToolCallId := AToolCallId;
  FToolName := AToolName;
  FContent := AContent;
  FDetails := nil;
  FIsError := AIsError;
end;

destructor TToolResultMessage.Destroy;
begin
  FContent.Free;
  FDetails.Free;
  inherited;
end;

function TToolResultMessage.Clone: TAgentMessage;
var
  Msg: TToolResultMessage;
  Content: TContentBlockList;
begin
  Content := nil;
  if FContent <> nil then
    Content := FContent.Clone;
  Msg := TToolResultMessage.Create(FToolCallId, FToolName, Content, FIsError);
  if FDetails <> nil then
    Msg.FDetails := TJSONObject(FDetails.Clone);
  Msg.Timestamp := FTimestamp;
  Result := Msg;
end;

function TToolResultMessage.ToJson: TJSONObject;
begin
  if Self = nil then
  begin
    Result := TJSONObject.Create;
    Result.AddPair('role', 'toolResult');
    Exit;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('role', 'toolResult');
  Result.AddPair('toolCallId', FToolCallId);
  Result.AddPair('toolName', FToolName);
  if FContent <> nil then
    Result.AddPair('content', FContent.ToJson)
  else
    Result.AddPair('content', TJSONArray.Create);
  Result.AddPair('isError', TJSONBool.Create(FIsError));
  if FDetails <> nil then
    Result.AddPair('details', TJSONObject(FDetails.Clone));
  Result.AddPair('timestamp', TJSONNumber.Create(DateTimeToUnix(FTimestamp, False)));
end;

{ TAgentMessageList }

destructor TAgentMessageList.Destroy;
begin
  Clear;
  inherited;
end;

procedure TAgentMessageList.Grow;
begin
  if FCapacity = 0 then
    FCapacity := 8
  else
    FCapacity := FCapacity * 2;
  if FCapacity > Length(FItems) then
    SetLength(FItems, FCapacity);
end;

procedure TAgentMessageList.Add(AMessage: TAgentMessage);
begin
  if FCount >= Length(FItems) then
    Grow;
  FItems[FCount] := AMessage;
  Inc(FCount);
end;

procedure TAgentMessageList.Clear;
var
  i: Integer;
begin
  for i := 0 to FCount - 1 do
    FItems[i].Free;
  FCount := 0;
  FCapacity := 0;
  FItems := nil;
end;

function TAgentMessageList.ExtractAll: TArray<TAgentMessage>;
// Ownership transfer: caller is now responsible for freeing all elements.
// The list becomes empty after this call.
begin
  SetLength(Result, FCount);
  if FCount > 0 then
    Move(FItems[0], Result[0], FCount * SizeOf(TAgentMessage));
  FCount := 0;
  FCapacity := 0;
  FItems := nil;  // Transfer ownership without freeing
end;

function TAgentMessageList.Clone: TAgentMessageList;
var
  i: Integer;
begin
  Result := TAgentMessageList.Create;
  Result.FCapacity := FCount;
  SetLength(Result.FItems, FCount);
  for i := 0 to FCount - 1 do
    Result.FItems[i] := FItems[i].Clone;
  Result.FCount := FCount;
end;

function TAgentMessageList.GetCount: Integer;
begin
  Result := FCount;
end;

function TAgentMessageList.GetItem(AIndex: Integer): TAgentMessage;
begin
  if (AIndex < 0) or (AIndex >= FCount) then
    raise EArgumentOutOfRangeException.CreateFmt('MessageList index %d out of range [0..%d]', [AIndex, FCount - 1]);
  Result := FItems[AIndex];
end;

function TAgentMessageList.Last: TAgentMessage;
begin
  if FCount = 0 then
    Result := nil
  else
    Result := FItems[FCount - 1];
end;

function TAgentMessageList.ToArray: TArray<TAgentMessage>;
// Returns shared references — caller must NOT free the elements.
// For an owned copy, use Clone.ToArray instead.
begin
  SetLength(Result, FCount);
  if FCount > 0 then
    Move(FItems[0], Result[0], FCount * SizeOf(TAgentMessage));
end;

procedure TAgentMessageList.Delete(AIndex: Integer);
var
  i: Integer;
begin
  if (AIndex < 0) or (AIndex >= FCount) then
    raise EArgumentOutOfRangeException.Create('Index out of range');
  // Free the item being removed
  FItems[AIndex].Free;
  // Shift items down
  for i := AIndex to FCount - 2 do
    FItems[i] := FItems[i + 1];
  Dec(FCount);
  FItems[FCount] := nil;
end;

{ Helpers }

function MessageRoleToString(ARole: TMessageRole): string;
begin
  case ARole of
    mrUser:       Result := 'user';
    mrAssistant:  Result := 'assistant';
    mrToolResult: Result := 'toolResult';
  else
    Result := 'unknown';
  end;
end;

function StopReasonToString(AReason: TStopReason): string;
begin
  case AReason of
    srStop:    Result := 'stop';
    srLength:  Result := 'length';
    srToolUse: Result := 'toolUse';
    srError:   Result := 'error';
    srAborted: Result := 'aborted';
  else
    Result := 'stop';
  end;
end;

function StringToStopReason(const AValue: string): TStopReason;
begin
  if AValue = 'stop' then Result := srStop
  else if AValue = 'length' then Result := srLength
  else if (AValue = 'toolUse') or (AValue = 'tool_calls') or (AValue = 'function_call') then Result := srToolUse
  else if (AValue = 'error') or (AValue = 'content_filter') then Result := srError
  else if AValue = 'aborted' then Result := srAborted
  else Result := srStop;
end;

end.
