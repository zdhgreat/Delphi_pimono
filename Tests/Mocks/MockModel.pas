unit MockModel;

interface

uses
  System.SysUtils, System.JSON, System.Classes, System.SyncObjs,
  AI.IModel, AI.ModelConfig, Core.Messages, Core.Events, Core.AgentState;

type
  // Mock IModel implementation for unit testing
  TMockModel = class(TInterfacedObject, IModel)
  private
    FModelInfo: TModelInfo;
    FResponses: TArray<TContentBlockList>;
    FResponseIndex: Integer;
    FStreamDelay: Integer; // ms between chunks
  public
    constructor Create;
    destructor Destroy; override;

    // Add a response that will be returned on next Stream/Complete call
    procedure AddTextResponse(const AText: string);
    procedure AddToolCallResponse(const AToolCallId, AToolName, AArgs: string);
    procedure AddMultiToolCallResponse(const AToolCalls: array of string); // [id1,name1,args1, id2,name2,args2]

    // IModel
    function GetModelInfo: TModelInfo;
    function GetId: string;
    function GetName: string;
    function GetProvider: string;
    function GetBaseUrl: string;
    procedure Stream(ARequest: TCompletionRequest;
      AOnEvent: TStreamEventCallback;
      AAbortSignal: TAbortController = nil);
    function Complete(ARequest: TCompletionRequest;
      AAbortSignal: TAbortController = nil): TAssistantMessage;
    function GetModels: TModelList;

    property StreamDelay: Integer read FStreamDelay write FStreamDelay;
  end;

implementation

{ TMockModel }

constructor TMockModel.Create;
begin
  inherited Create;
  FResponseIndex := 0;
  FStreamDelay := 10;
  FModelInfo := TModelInfo.Create('mock-model', 'Mock Model', 'mock', 'http://mock.api');
end;

destructor TMockModel.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(FResponses) do
    FResponses[i].Free;
  inherited;
end;

procedure TMockModel.AddTextResponse(const AText: string);
var
  List: TContentBlockList;
begin
  List := TContentBlockList.Create;
  List.Add(TTextContent.Create(AText));
  SetLength(FResponses, Length(FResponses) + 1);
  FResponses[High(FResponses)] := List;
end;

procedure TMockModel.AddToolCallResponse(const AToolCallId, AToolName, AArgs: string);
var
  List: TContentBlockList;
  ArgsObj: TJSONObject;
begin
  List := TContentBlockList.Create;
  ArgsObj := TJSONObject.ParseJSONValue(AArgs) as TJSONObject;
  if ArgsObj = nil then
    ArgsObj := TJSONObject.Create;
  List.Add(TToolCall.Create(AToolCallId, AToolName, ArgsObj));
  SetLength(FResponses, Length(FResponses) + 1);
  FResponses[High(FResponses)] := List;
end;

procedure TMockModel.AddMultiToolCallResponse(const AToolCalls: array of string);
var
  List: TContentBlockList;
  ArgsObj: TJSONObject;
  i: Integer;
begin
  List := TContentBlockList.Create;
  i := 0;
  while i + 2 <= High(AToolCalls) do
  begin
    ArgsObj := TJSONObject.ParseJSONValue(AToolCalls[i + 2]) as TJSONObject;
    if ArgsObj = nil then
      ArgsObj := TJSONObject.Create;
    List.Add(TToolCall.Create(AToolCalls[i], AToolCalls[i + 1], ArgsObj));
    Inc(i, 3);
  end;
  SetLength(FResponses, Length(FResponses) + 1);
  FResponses[High(FResponses)] := List;
end;

function TMockModel.GetModelInfo: TModelInfo;
begin
  Result := FModelInfo;
end;

function TMockModel.GetId: string;
begin
  Result := FModelInfo.Id;
end;

function TMockModel.GetName: string;
begin
  Result := FModelInfo.Name;
end;

function TMockModel.GetProvider: string;
begin
  Result := FModelInfo.Provider;
end;

function TMockModel.GetBaseUrl: string;
begin
  Result := FModelInfo.BaseUrl;
end;

procedure TMockModel.Stream(ARequest: TCompletionRequest;
  AOnEvent: TStreamEventCallback; AAbortSignal: TAbortController);
var
  Blocks: TContentBlockList;
  Msg: TAssistantMessage;
  Snap: TAssistantMessage;
  i: Integer;
  Text: string;
  DeltaSize, Pos: Integer;
  Delta: string;
  TC: TToolCall;
  ArgsClone: TJSONObject;
begin
  if FResponseIndex <= High(FResponses) then
    Blocks := FResponses[FResponseIndex]
  else
    Blocks := nil;

  Inc(FResponseIndex);

  // Emit Start event with empty partial message
  AOnEvent(TStartEvent.Create(TAssistantMessage.Create));

  if Blocks <> nil then
  begin
    for i := 0 to Blocks.Count - 1 do
    begin
      if Blocks[i].ContentType = cbtText then
      begin
        Text := TTextContent(Blocks[i]).Text;
        DeltaSize := 5;
        Pos := 1;
        while Pos <= Length(Text) do
        begin
          Delta := Copy(Text, Pos, DeltaSize);
          Snap := TAssistantMessage.Create;
          Snap.Content.Add(TTextContent.Create(Delta));
          AOnEvent(TTextDeltaEvent.Create(0, Delta, Snap));
          Inc(Pos, DeltaSize);
          if FStreamDelay > 0 then
            Sleep(FStreamDelay);
        end;
      end
      else if Blocks[i].ContentType = cbtToolCall then
      begin
        TC := TToolCall(Blocks[i]);
        ArgsClone := nil;
        if TC.Arguments <> nil then
          ArgsClone := TJSONObject(TC.Arguments.Clone);
        Snap := TAssistantMessage.Create;
        Snap.Content.Add(TToolCall.Create(TC.Id, TC.Name, ArgsClone));
        AOnEvent(TToolCallDeltaEvent.Create(0, TC.Name, Snap));
      end;
    end;
  end;

  // Emit Done event with final message
  Msg := TAssistantMessage.Create;
  if Blocks <> nil then
    for i := 0 to Blocks.Count - 1 do
      Msg.Content.Add(Blocks[i].Clone);

  // Determine correct stop reason: srToolUse if response contains tool calls
  var StopReason_: TStopReason;
  StopReason_ := srStop;
  if Blocks <> nil then
  begin
    for var bi := 0 to Blocks.Count - 1 do
      if Blocks[bi] is TToolCall then
      begin
        StopReason_ := srToolUse;
        Break;
      end;
  end;
  Msg.StopReason := StopReason_;
  AOnEvent(TDoneEvent.Create(StopReason_, Msg));
end;

function TMockModel.Complete(ARequest: TCompletionRequest;
  AAbortSignal: TAbortController): TAssistantMessage;
var
  Blocks: TContentBlockList;
  i: Integer;
begin
  Result := TAssistantMessage.Create;

  if FResponseIndex <= High(FResponses) then
    Blocks := FResponses[FResponseIndex]
  else
    Blocks := nil;

  Inc(FResponseIndex);

  if Blocks <> nil then
    for i := 0 to Blocks.Count - 1 do
      Result.Content.Add(Blocks[i].Clone);

  Result.StopReason := srStop;
end;

function TMockModel.GetModels: TModelList;
begin
  Result := TModelList.Create;
  Result.Add(FModelInfo);
end;

end.
