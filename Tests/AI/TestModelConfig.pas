unit TestModelConfig;

interface

uses
  System.SysUtils, System.JSON,
  AI.ModelConfig,
  PiMonoTestFramework;

procedure RegisterModelConfigTests;

implementation

uses
  Utils.JsonHelper;

type
  TTestModelConfig = class
  public
    // TCostRates
    procedure Test_CostRates_Zero;

    // TModelInfo
    procedure Test_ModelInfo_Create;
    procedure Test_ModelInfo_CalculateCost;
    procedure Test_ModelInfo_CalculateCost_Zero;

    // ModelInfoToJson / JsonToModelInfo
    procedure Test_ModelInfoToJson_Roundtrip;
    procedure Test_JsonToModelInfo_Nil;
    procedure Test_JsonToModelInfo_MissingFields;
    procedure Test_ModelInfoToJson_WithCost;
    procedure Test_ModelInfoToJson_WithImageInput;

    // TModelList
    procedure Test_ModelList_AddCount;
    procedure Test_ModelList_FindById;
    procedure Test_ModelList_FindById_NotFound;
    procedure Test_ModelList_FindByName;
    procedure Test_ModelList_Clear;
    procedure Test_ModelList_Items;
  end;

{ TTestModelConfig }

procedure TTestModelConfig.Test_CostRates_Zero;
var
  C: TCostRates;
begin
  C := TCostRates.Zero;
  Assert(C.Input = 0, 'Input should be 0');
  Assert(C.Output = 0, 'Output should be 0');
  Assert(C.CacheRead = 0, 'CacheRead should be 0');
  Assert(C.CacheWrite = 0, 'CacheWrite should be 0');
end;

procedure TTestModelConfig.Test_ModelInfo_Create;
var
  M: TModelInfo;
begin
  M := TModelInfo.Create('gpt-4', 'GPT-4', 'openai', 'https://api.openai.com');
  Assert(M.Id = 'gpt-4', 'Id should match');
  Assert(M.Name = 'GPT-4', 'Name should match');
  Assert(M.Provider = 'openai', 'Provider should match');
  Assert(M.BaseUrl = 'https://api.openai.com', 'BaseUrl should match');
  Assert(M.ContextWindow = 128000, 'Default ContextWindow should be 128000');
  Assert(M.MaxTokens = 16384, 'Default MaxTokens should be 16384');
  Assert(not M.Reasoning, 'Reasoning default should be False');
  Assert(itText in M.Input, 'Input should include text');
  Assert(not (itImage in M.Input), 'Input should not include image by default');
end;

procedure TTestModelConfig.Test_ModelInfo_CalculateCost;
var
  M: TModelInfo;
  Cost: Double;
begin
  M := Default(TModelInfo);
  M.Cost.Input := 10.0;     // $10 per million input tokens
  M.Cost.Output := 30.0;    // $30 per million output tokens
  M.Cost.CacheRead := 1.0;
  M.Cost.CacheWrite := 5.0;

  Cost := M.CalculateCost(1000000, 1000000, 0, 0);
  Assert(Abs(Cost - 40.0) < 0.001, 'Cost should be 40.0, got ' + FloatToStr(Cost));
end;

procedure TTestModelConfig.Test_ModelInfo_CalculateCost_Zero;
var
  M: TModelInfo;
  Cost: Double;
begin
  M := Default(TModelInfo);
  M.Cost := TCostRates.Zero;
  Cost := M.CalculateCost(1000000, 1000000, 1000000, 1000000);
  Assert(Abs(Cost) < 0.001, 'Zero cost rates should produce 0 cost');
end;

procedure TTestModelConfig.Test_ModelInfoToJson_Roundtrip;
var
  M: TModelInfo;
  Json: TJSONObject;
  M2: TModelInfo;
begin
  M := TModelInfo.Create('test-model', 'Test Model', 'test-provider', 'https://test.com', 64000, 8192);

  Json := ModelInfoToJson(M);
  try
    M2 := JsonToModelInfo(Json);
    Assert(M2.Id = 'test-model', 'Id roundtrip should match');
    Assert(M2.Name = 'Test Model', 'Name roundtrip should match');
    Assert(M2.Provider = 'test-provider', 'Provider roundtrip should match');
    Assert(M2.BaseUrl = 'https://test.com', 'BaseUrl roundtrip should match');
    Assert(M2.ContextWindow = 64000, 'ContextWindow roundtrip should match');
    Assert(M2.MaxTokens = 8192, 'MaxTokens roundtrip should match');
  finally
    Json.Free;
  end;
end;

procedure TTestModelConfig.Test_JsonToModelInfo_Nil;
var
  M: TModelInfo;
begin
  M := JsonToModelInfo(nil);
  Assert(M.Id = '', 'Nil JSON should produce default Id');
end;

procedure TTestModelConfig.Test_JsonToModelInfo_MissingFields;
var
  Json: TJSONObject;
  M: TModelInfo;
begin
  Json := TJSONObject.Create;
  try
    Json.AddPair('id', 'partial');
    M := JsonToModelInfo(Json);
    Assert(M.Id = 'partial', 'Should parse id');
    Assert(M.Name = '', 'Missing name should be empty');
    Assert(M.ContextWindow = 128000, 'Missing contextWindow should use default');
  finally
    Json.Free;
  end;
end;

procedure TTestModelConfig.Test_ModelInfoToJson_WithCost;
var
  M: TModelInfo;
  Json: TJSONObject;
  M2: TModelInfo;
begin
  M := TModelInfo.Create('cost-model', 'Cost Model', 'test', 'https://test.com');
  M.Cost.Input := 5.0;
  M.Cost.Output := 15.0;
  M.Cost.CacheRead := 0.5;
  M.Cost.CacheWrite := 2.5;

  Json := ModelInfoToJson(M);
  try
    M2 := JsonToModelInfo(Json);
    Assert(Abs(M2.Cost.Input - 5.0) < 0.001, 'Cost.Input roundtrip');
    Assert(Abs(M2.Cost.Output - 15.0) < 0.001, 'Cost.Output roundtrip');
    Assert(Abs(M2.Cost.CacheRead - 0.5) < 0.001, 'Cost.CacheRead roundtrip');
    Assert(Abs(M2.Cost.CacheWrite - 2.5) < 0.001, 'Cost.CacheWrite roundtrip');
  finally
    Json.Free;
  end;
end;

procedure TTestModelConfig.Test_ModelInfoToJson_WithImageInput;
var
  M: TModelInfo;
  Json: TJSONObject;
  M2: TModelInfo;
begin
  M := TModelInfo.Create('vision-model', 'Vision', 'test', 'https://test.com');
  M.Input := [itText, itImage];

  Json := ModelInfoToJson(M);
  try
    M2 := JsonToModelInfo(Json);
    Assert(itText in M2.Input, 'Should include text input');
    Assert(itImage in M2.Input, 'Should include image input');
  finally
    Json.Free;
  end;
end;

{ TModelList }

procedure TTestModelConfig.Test_ModelList_AddCount;
var
  List: TModelList;
begin
  List := TModelList.Create;
  try
    Assert(List.Count = 0, 'New list should have 0 items');
    List.Add(TModelInfo.Create('m1', 'Model 1', 'p1', ''));
    List.Add(TModelInfo.Create('m2', 'Model 2', 'p2', ''));
    Assert(List.Count = 2, 'Should have 2 items');
  finally
    List.Free;
  end;
end;

procedure TTestModelConfig.Test_ModelList_FindById;
var
  List: TModelList;
  M: TModelInfo;
begin
  List := TModelList.Create;
  try
    List.Add(TModelInfo.Create('gpt-4', 'GPT-4', 'openai', ''));
    List.Add(TModelInfo.Create('claude-3', 'Claude 3', 'anthropic', ''));

    M := List.FindById('gpt-4');
    Assert(M.Id = 'gpt-4', 'Should find by id');

    M := List.FindById('CLAUDE-3');
    Assert(M.Id = 'claude-3', 'FindById should be case insensitive');
  finally
    List.Free;
  end;
end;

procedure TTestModelConfig.Test_ModelList_FindById_NotFound;
var
  List: TModelList;
  M: TModelInfo;
begin
  List := TModelList.Create;
  try
    List.Add(TModelInfo.Create('m1', 'Model 1', 'p1', ''));
    M := List.FindById('nonexistent');
    Assert(M.Id = '', 'Not found should return default');
  finally
    List.Free;
  end;
end;

procedure TTestModelConfig.Test_ModelList_FindByName;
var
  List: TModelList;
  M: TModelInfo;
begin
  List := TModelList.Create;
  try
    List.Add(TModelInfo.Create('gpt-4', 'GPT-4', 'openai', ''));

    M := List.FindByName('GPT-4');
    Assert(M.Id = 'gpt-4', 'Should find by name');

    M := List.FindByName('gpt-4');
    Assert(M.Id = 'gpt-4', 'FindByName should be case insensitive');
  finally
    List.Free;
  end;
end;

procedure TTestModelConfig.Test_ModelList_Clear;
var
  List: TModelList;
begin
  List := TModelList.Create;
  try
    List.Add(TModelInfo.Create('m1', 'M1', 'p1', ''));
    List.Add(TModelInfo.Create('m2', 'M2', 'p2', ''));
    Assert(List.Count = 2, 'Should have 2');
    List.Clear;
    Assert(List.Count = 0, 'Should be empty after clear');
  finally
    List.Free;
  end;
end;

procedure TTestModelConfig.Test_ModelList_Items;
var
  List: TModelList;
begin
  List := TModelList.Create;
  try
    List.Add(TModelInfo.Create('first', 'First', 'p', ''));
    List.Add(TModelInfo.Create('second', 'Second', 'p', ''));

    Assert(List[0].Id = 'first', 'Index 0 should be first');
    Assert(List[1].Id = 'second', 'Index 1 should be second');
  finally
    List.Free;
  end;
end;

{ Registration }

procedure RegisterModelConfigTests;
var
  T: TTestModelConfig;
begin
  T := TTestModelConfig.Create;
  try
    GRunner.RunTest('ModelConfig: CostRates Zero', T.Test_CostRates_Zero);
    GRunner.RunTest('ModelConfig: ModelInfo Create', T.Test_ModelInfo_Create);
    GRunner.RunTest('ModelConfig: CalculateCost', T.Test_ModelInfo_CalculateCost);
    GRunner.RunTest('ModelConfig: CalculateCost zero', T.Test_ModelInfo_CalculateCost_Zero);
    GRunner.RunTest('ModelConfig: Json roundtrip', T.Test_ModelInfoToJson_Roundtrip);
    GRunner.RunTest('ModelConfig: Json nil', T.Test_JsonToModelInfo_Nil);
    GRunner.RunTest('ModelConfig: Json missing fields', T.Test_JsonToModelInfo_MissingFields);
    GRunner.RunTest('ModelConfig: Json with cost', T.Test_ModelInfoToJson_WithCost);
    GRunner.RunTest('ModelConfig: Json with image input', T.Test_ModelInfoToJson_WithImageInput);
    GRunner.RunTest('ModelConfig: ModelList AddCount', T.Test_ModelList_AddCount);
    GRunner.RunTest('ModelConfig: ModelList FindById', T.Test_ModelList_FindById);
    GRunner.RunTest('ModelConfig: ModelList FindById not found', T.Test_ModelList_FindById_NotFound);
    GRunner.RunTest('ModelConfig: ModelList FindByName', T.Test_ModelList_FindByName);
    GRunner.RunTest('ModelConfig: ModelList Clear', T.Test_ModelList_Clear);
    GRunner.RunTest('ModelConfig: ModelList Items', T.Test_ModelList_Items);
  finally
    T.Free;
  end;
end;

end.
