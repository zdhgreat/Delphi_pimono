unit AI.ModelConfig;

interface

uses
  System.SysUtils, System.JSON, System.Generics.Collections,
  Utils.JsonHelper;

type
  TCostRates = record
    Input: Double;       // per million tokens
    Output: Double;
    CacheRead: Double;
    CacheWrite: Double;
    class function Zero: TCostRates; static;
  end;

  TInputType = (itText, itImage);
  TInputTypes = set of TInputType;

  TModelInfo = record
    Id: string;
    Name: string;
    Api: string;           // e.g. 'openai-completions'
    Provider: string;      // e.g. 'internal'
    BaseUrl: string;
    Reasoning: Boolean;
    Input: TInputTypes;
    Cost: TCostRates;
    ContextWindow: Integer;
    MaxTokens: Integer;
    class function Create(const AId, AName, AProvider, ABaseUrl: string;
      AContextWindow: Integer = 128000; AMaxTokens: Integer = 16384): TModelInfo; static;
    function CalculateCost(AInputTokens, AOutputTokens,
      ACacheReadTokens, ACacheWriteTokens: Integer): Double;
  end;

  TModelList = class
  private
    FModels: TList<TModelInfo>;
    function GetCount: Integer;
    function GetItem(AIndex: Integer): TModelInfo;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AModel: TModelInfo);
    function FindById(const AId: string): TModelInfo;
    function FindByName(const AName: string): TModelInfo;
    function TryFindById(const AId: string; out AModel: TModelInfo): Boolean;
    function TryFindByName(const AName: string; out AModel: TModelInfo): Boolean;
    procedure Clear;
    property Count: Integer read GetCount;
    property Items[AIndex: Integer]: TModelInfo read GetItem; default;
  end;

function ModelInfoToJson(const AModel: TModelInfo): TJSONObject;
function JsonToModelInfo(AJson: TJSONObject): TModelInfo;

implementation

{ TCostRates }

class function TCostRates.Zero: TCostRates;
begin
  Result.Input := 0;
  Result.Output := 0;
  Result.CacheRead := 0;
  Result.CacheWrite := 0;
end;

{ TModelInfo }

class function TModelInfo.Create(const AId, AName, AProvider, ABaseUrl: string;
  AContextWindow, AMaxTokens: Integer): TModelInfo;
begin
  Result.Id := AId;
  Result.Name := AName;
  Result.Api := 'openai-completions';
  Result.Provider := AProvider;
  Result.BaseUrl := ABaseUrl;
  Result.Reasoning := False;
  Result.Input := [itText];
  Result.Cost := TCostRates.Zero;
  Result.ContextWindow := AContextWindow;
  Result.MaxTokens := AMaxTokens;
end;

function TModelInfo.CalculateCost(AInputTokens, AOutputTokens,
  ACacheReadTokens, ACacheWriteTokens: Integer): Double;
begin
  Result := (Cost.Input / 1000000) * AInputTokens +
            (Cost.Output / 1000000) * AOutputTokens +
            (Cost.CacheRead / 1000000) * ACacheReadTokens +
            (Cost.CacheWrite / 1000000) * ACacheWriteTokens;
end;

{ TModelList }

constructor TModelList.Create;
begin
  inherited Create;
  FModels := TList<TModelInfo>.Create;
end;

destructor TModelList.Destroy;
begin
  FModels.Free;
  inherited;
end;

procedure TModelList.Add(const AModel: TModelInfo);
begin
  FModels.Add(AModel);
end;

function TModelList.FindById(const AId: string): TModelInfo;
var
  i: Integer;
begin
  for i := 0 to FModels.Count - 1 do
    if SameText(FModels[i].Id, AId) then
      Exit(FModels[i]);
  Result := Default(TModelInfo);
end;

function TModelList.FindByName(const AName: string): TModelInfo;
var
  i: Integer;
begin
  for i := 0 to FModels.Count - 1 do
    if SameText(FModels[i].Name, AName) then
      Exit(FModels[i]);
  Result := Default(TModelInfo);
end;

function TModelList.TryFindById(const AId: string; out AModel: TModelInfo): Boolean;
var
  i: Integer;
begin
  for i := 0 to FModels.Count - 1 do
    if SameText(FModels[i].Id, AId) then
    begin
      AModel := FModels[i];
      Exit(True);
    end;
  AModel := Default(TModelInfo);
  Result := False;
end;

function TModelList.TryFindByName(const AName: string; out AModel: TModelInfo): Boolean;
var
  i: Integer;
begin
  for i := 0 to FModels.Count - 1 do
    if SameText(FModels[i].Name, AName) then
    begin
      AModel := FModels[i];
      Exit(True);
    end;
  AModel := Default(TModelInfo);
  Result := False;
end;

procedure TModelList.Clear;
begin
  FModels.Clear;
end;

function TModelList.GetCount: Integer;
begin
  Result := FModels.Count;
end;

function TModelList.GetItem(AIndex: Integer): TModelInfo;
begin
  Result := FModels[AIndex];
end;

{ JSON Helpers }

function ModelInfoToJson(const AModel: TModelInfo): TJSONObject;
var
  InputArr: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', AModel.Id);
  Result.AddPair('name', AModel.Name);
  Result.AddPair('api', AModel.Api);
  Result.AddPair('provider', AModel.Provider);
  Result.AddPair('baseUrl', AModel.BaseUrl);
  Result.AddPair('reasoning', TJSONBool.Create(AModel.Reasoning));
  Result.AddPair('contextWindow', TJSONNumber.Create(AModel.ContextWindow));
  Result.AddPair('maxTokens', TJSONNumber.Create(AModel.MaxTokens));

  InputArr := TJSONArray.Create;
  if itText in AModel.Input then
    InputArr.Add('text');
  if itImage in AModel.Input then
    InputArr.Add('image');
  Result.AddPair('input', InputArr);

  // Cost rates
  var CostObj := TJSONObject.Create;
  CostObj.AddPair('inputPerMillion', TJSONNumber.Create(AModel.Cost.Input));
  CostObj.AddPair('outputPerMillion', TJSONNumber.Create(AModel.Cost.Output));
  CostObj.AddPair('cacheReadPerMillion', TJSONNumber.Create(AModel.Cost.CacheRead));
  CostObj.AddPair('cacheWritePerMillion', TJSONNumber.Create(AModel.Cost.CacheWrite));
  Result.AddPair('cost', CostObj);
end;

function JsonToModelInfo(AJson: TJSONObject): TModelInfo;
var
  InputArr: TJSONArray;
  i: Integer;
  S: string;
begin
  Result := Default(TModelInfo);
  if AJson = nil then
    Exit;

  Result.Id := JsonGetStr(AJson, 'id', '');
  Result.Name := JsonGetStr(AJson, 'name', '');
  Result.Api := JsonGetStr(AJson, 'api', 'openai-completions');
  Result.Provider := JsonGetStr(AJson, 'provider', 'internal');
  Result.BaseUrl := JsonGetStr(AJson, 'baseUrl', '');
  Result.Reasoning := JsonGetBool(AJson, 'reasoning', False);
  Result.ContextWindow := JsonGetInt(AJson, 'contextWindow', 128000);
  Result.MaxTokens := JsonGetInt(AJson, 'maxTokens', 16384);

  Result.Input := [];
  var InputVal := AJson.FindValue('input');
  if (InputVal <> nil) and (InputVal is TJSONArray) then
  begin
    InputArr := InputVal as TJSONArray;
    for i := 0 to InputArr.Count - 1 do
    begin
      S := LowerCase(InputArr.Items[i].Value);
      if S = 'text' then Include(Result.Input, itText)
      else if S = 'image' then Include(Result.Input, itImage);
    end;
  end;

  // Cost rates
  Result.Cost := TCostRates.Zero;
  var CostObj := AJson.GetValue('cost') as TJSONObject;
  if CostObj <> nil then
  begin
    Result.Cost.Input := JsonGetDbl(CostObj, 'inputPerMillion', 0);
    Result.Cost.Output := JsonGetDbl(CostObj, 'outputPerMillion', 0);
    Result.Cost.CacheRead := JsonGetDbl(CostObj, 'cacheReadPerMillion', 0);
    Result.Cost.CacheWrite := JsonGetDbl(CostObj, 'cacheWritePerMillion', 0);
  end;
end;

end.
