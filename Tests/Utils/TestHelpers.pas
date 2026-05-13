unit TestHelpers;

interface

uses
  System.SysUtils, System.JSON,
  Utils.JsonHelper, Utils.Localization, Utils.TokenEstimator,
  PiMonoTestFramework;

procedure RegisterHelperTests;

implementation

type
  TTestJsonHelper = class
  public
    procedure Test_JsonGetStr_Exists;
    procedure Test_JsonGetStr_Missing;
    procedure Test_JsonGetStr_NilObject;
    procedure Test_JsonGetInt_Exists;
    procedure Test_JsonGetInt_Missing;
    procedure Test_JsonGetInt_WrongType;
    procedure Test_JsonGetDbl_Exists;
    procedure Test_JsonGetBool_True;
    procedure Test_JsonGetBool_False;
    procedure Test_JsonGetBool_Number0;
    procedure Test_JsonGetBool_Number1;
    procedure Test_JsonGetBool_Missing;
    procedure Test_JsonGetInt64_Exists;
  end;

  TTestLocalization = class
  public
    procedure Setup;
    procedure TearDown;

    procedure Test_EnglishKeyLookup;
    procedure Test_ChineseKeyLookup;
    procedure Test_MissingKey_ReturnsKey;
    procedure Test_LangFromCode_Zh;
    procedure Test_LangFromCode_Cn;
    procedure Test_LangFromCode_Chinese;
    procedure Test_LangFromCode_En;
    procedure Test_LangCode_En;
    procedure Test_LangCode_Zh;
    procedure Test_SwitchLanguage;
  end;

  TTestTokenEstimator = class
  public
    procedure Test_ASCII_Text;
    procedure Test_CJK_Text;
    procedure Test_EmptyText;
    procedure Test_MixedText;
  end;

{ TTestJsonHelper }

procedure TTestJsonHelper.Test_JsonGetStr_Exists;
var
  Json: TJSONObject;
begin
  Json := TJSONObject.Create;
  try
    Json.AddPair('name', 'test');
    Assert(JsonGetStr(Json, 'name', '') = 'test', 'JsonGetStr should return existing value');
  finally
    Json.Free;
  end;
end;

procedure TTestJsonHelper.Test_JsonGetStr_Missing;
var
  Json: TJSONObject;
begin
  Json := TJSONObject.Create;
  try
    Assert(JsonGetStr(Json, 'missing', 'default') = 'default', 'JsonGetStr should return default for missing key');
  finally
    Json.Free;
  end;
end;

procedure TTestJsonHelper.Test_JsonGetStr_NilObject;
begin
  Assert(JsonGetStr(nil, 'any', 'fallback') = 'fallback', 'JsonGetStr should return default for nil object');
end;

procedure TTestJsonHelper.Test_JsonGetInt_Exists;
var
  Json: TJSONObject;
begin
  Json := TJSONObject.Create;
  try
    Json.AddPair('count', TJSONNumber.Create(42));
    Assert(JsonGetInt(Json, 'count', 0) = 42, 'JsonGetInt should return existing value');
  finally
    Json.Free;
  end;
end;

procedure TTestJsonHelper.Test_JsonGetInt_Missing;
var
  Json: TJSONObject;
begin
  Json := TJSONObject.Create;
  try
    Assert(JsonGetInt(Json, 'missing', 99) = 99, 'JsonGetInt should return default for missing key');
  finally
    Json.Free;
  end;
end;

procedure TTestJsonHelper.Test_JsonGetInt_WrongType;
var
  Json: TJSONObject;
begin
  Json := TJSONObject.Create;
  try
    Json.AddPair('text', 'not_a_number');
    Assert(JsonGetInt(Json, 'text', 0) = 0, 'Should return default for non-numeric');
  finally
    Json.Free;
  end;
end;

procedure TTestJsonHelper.Test_JsonGetDbl_Exists;
var
  Json: TJSONObject;
  Val: Double;
begin
  Json := TJSONObject.Create;
  try
    Json.AddPair('temp', TJSONNumber.Create(0.7));
    Val := JsonGetDbl(Json, 'temp', 0.0);
    Assert(Abs(Val - 0.7) < 0.001, 'JsonGetDbl should return existing value');
  finally
    Json.Free;
  end;
end;

procedure TTestJsonHelper.Test_JsonGetBool_True;
var
  Json: TJSONObject;
begin
  Json := TJSONObject.Create;
  try
    Json.AddPair('enabled', TJSONBool.Create(True));
    Assert(JsonGetBool(Json, 'enabled', False), 'JsonGetBool should return true');
  finally
    Json.Free;
  end;
end;

procedure TTestJsonHelper.Test_JsonGetBool_False;
var
  Json: TJSONObject;
begin
  Json := TJSONObject.Create;
  try
    Json.AddPair('enabled', TJSONBool.Create(False));
    Assert(not JsonGetBool(Json, 'enabled', True), 'JsonGetBool should return false');
  finally
    Json.Free;
  end;
end;

procedure TTestJsonHelper.Test_JsonGetBool_Number0;
var
  Json: TJSONObject;
begin
  Json := TJSONObject.Create;
  try
    Json.AddPair('flag', TJSONNumber.Create(0));
    Assert(not JsonGetBool(Json, 'flag', True), '0 should be false');
  finally
    Json.Free;
  end;
end;

procedure TTestJsonHelper.Test_JsonGetBool_Number1;
var
  Json: TJSONObject;
begin
  Json := TJSONObject.Create;
  try
    Json.AddPair('flag', TJSONNumber.Create(1));
    Assert(JsonGetBool(Json, 'flag', False), '1 should be true');
  finally
    Json.Free;
  end;
end;

procedure TTestJsonHelper.Test_JsonGetBool_Missing;
var
  Json: TJSONObject;
begin
  Json := TJSONObject.Create;
  try
    Assert(not JsonGetBool(Json, 'missing', False), 'Missing key should return default false');
  finally
    Json.Free;
  end;
end;

procedure TTestJsonHelper.Test_JsonGetInt64_Exists;
var
  Json: TJSONObject;
begin
  Json := TJSONObject.Create;
  try
    Json.AddPair('big', TJSONNumber.Create(Int64(9999999999)));
    Assert(JsonGetInt64(Json, 'big', 0) = Int64(9999999999), 'JsonGetInt64 should return existing value');
  finally
    Json.Free;
  end;
end;

{ TTestLocalization }

procedure TTestLocalization.Setup;
begin
  SetLanguage(langEn);
end;

procedure TTestLocalization.TearDown;
begin
  SetLanguage(langEn);
end;

procedure TTestLocalization.Test_EnglishKeyLookup;
begin
  SetLanguage(langEn);
  var Val := L('btn.settings');
  Assert(Val = 'Settings', 'English key should return Settings');
end;

procedure TTestLocalization.Test_ChineseKeyLookup;
begin
  SetLanguage(langZh);
  var Val := L('btn.settings');
  Assert(Val <> 'btn.settings', 'Should return Chinese translation, not key');
end;

procedure TTestLocalization.Test_MissingKey_ReturnsKey;
begin
  var Val := L('nonexistent.key.12345');
  Assert(Val = 'nonexistent.key.12345', 'Missing key should return the key itself');
end;

procedure TTestLocalization.Test_LangFromCode_Zh;
begin
  Assert(Ord(LangFromCode('zh')) = Ord(langZh), 'LangFromCode(zh) should return langZh');
end;

procedure TTestLocalization.Test_LangFromCode_Cn;
begin
  Assert(Ord(LangFromCode('cn')) = Ord(langZh), 'LangFromCode(cn) should return langZh');
end;

procedure TTestLocalization.Test_LangFromCode_Chinese;
begin
  Assert(Ord(LangFromCode('chinese')) = Ord(langZh), 'LangFromCode(chinese) should return langZh');
end;

procedure TTestLocalization.Test_LangFromCode_En;
begin
  Assert(Ord(LangFromCode('en')) = Ord(langEn), 'LangFromCode(en) should return langEn');
end;

procedure TTestLocalization.Test_LangCode_En;
begin
  SetLanguage(langEn);
  Assert(LangCode = 'en', 'LangCode should be en');
end;

procedure TTestLocalization.Test_LangCode_Zh;
begin
  SetLanguage(langZh);
  Assert(LangCode = 'zh', 'LangCode should be zh');
end;

procedure TTestLocalization.Test_SwitchLanguage;
begin
  SetLanguage(langEn);
  var EnVal := L('btn.settings');
  SetLanguage(langZh);
  var ZhVal := L('btn.settings');
  Assert(EnVal <> ZhVal, 'EN and ZH should be different');
end;

{ TTestTokenEstimator }

procedure TTestTokenEstimator.Test_ASCII_Text;
var
  Est: Integer;
begin
  Est := EstimateTokens('Hello World! This is a test of the token estimator.');
  Assert(Est > 0, 'Token estimate should be positive');
  Assert(Est < 20, 'Should be reasonable for short ASCII text');
end;

procedure TTestTokenEstimator.Test_CJK_Text;
var
  Est: Integer;
begin
  Est := EstimateTokens(string('这是一段中文测试文本'));
  Assert(Est > 0, 'CJK token estimate should be positive');
end;

procedure TTestTokenEstimator.Test_EmptyText;
begin
  Assert(EstimateTokens('') = 0, 'Empty text should have 0 tokens');
end;

procedure TTestTokenEstimator.Test_MixedText;
var
  Est: Integer;
begin
  Est := EstimateTokens('Hello 你好 World 世界');
  Assert(Est > 0, 'Mixed text token estimate should be positive');
end;

{ Registration }

procedure RegisterHelperTests;
var
  TJH: TTestJsonHelper;
  TL: TTestLocalization;
  TTE: TTestTokenEstimator;
begin
  // JsonHelper tests (no setup/teardown needed)
  TJH := TTestJsonHelper.Create;
  try
    GRunner.RunTest('JsonHelper: JsonGetStr exists', TJH.Test_JsonGetStr_Exists);
    GRunner.RunTest('JsonHelper: JsonGetStr missing', TJH.Test_JsonGetStr_Missing);
    GRunner.RunTest('JsonHelper: JsonGetStr nil object', TJH.Test_JsonGetStr_NilObject);
    GRunner.RunTest('JsonHelper: JsonGetInt exists', TJH.Test_JsonGetInt_Exists);
    GRunner.RunTest('JsonHelper: JsonGetInt missing', TJH.Test_JsonGetInt_Missing);
    GRunner.RunTest('JsonHelper: JsonGetInt wrong type', TJH.Test_JsonGetInt_WrongType);
    GRunner.RunTest('JsonHelper: JsonGetDbl exists', TJH.Test_JsonGetDbl_Exists);
    GRunner.RunTest('JsonHelper: JsonGetBool true', TJH.Test_JsonGetBool_True);
    GRunner.RunTest('JsonHelper: JsonGetBool false', TJH.Test_JsonGetBool_False);
    GRunner.RunTest('JsonHelper: JsonGetBool number0', TJH.Test_JsonGetBool_Number0);
    GRunner.RunTest('JsonHelper: JsonGetBool number1', TJH.Test_JsonGetBool_Number1);
    GRunner.RunTest('JsonHelper: JsonGetBool missing', TJH.Test_JsonGetBool_Missing);
    GRunner.RunTest('JsonHelper: JsonGetInt64 exists', TJH.Test_JsonGetInt64_Exists);
  finally
    TJH.Free;
  end;

  // Localization tests (need setup/teardown)
  TL := TTestLocalization.Create;
  try
    GRunner.RunTest('Localization: english key lookup', TL.Test_EnglishKeyLookup, TL.Setup, TL.TearDown);
    GRunner.RunTest('Localization: chinese key lookup', TL.Test_ChineseKeyLookup, TL.Setup, TL.TearDown);
    GRunner.RunTest('Localization: missing key returns key', TL.Test_MissingKey_ReturnsKey, TL.Setup, TL.TearDown);
    GRunner.RunTest('Localization: LangFromCode zh', TL.Test_LangFromCode_Zh, TL.Setup, TL.TearDown);
    GRunner.RunTest('Localization: LangFromCode cn', TL.Test_LangFromCode_Cn, TL.Setup, TL.TearDown);
    GRunner.RunTest('Localization: LangFromCode chinese', TL.Test_LangFromCode_Chinese, TL.Setup, TL.TearDown);
    GRunner.RunTest('Localization: LangFromCode en', TL.Test_LangFromCode_En, TL.Setup, TL.TearDown);
    GRunner.RunTest('Localization: LangCode en', TL.Test_LangCode_En, TL.Setup, TL.TearDown);
    GRunner.RunTest('Localization: LangCode zh', TL.Test_LangCode_Zh, TL.Setup, TL.TearDown);
    GRunner.RunTest('Localization: switch language', TL.Test_SwitchLanguage, TL.Setup, TL.TearDown);
  finally
    TL.Free;
  end;

  // TokenEstimator tests (no setup/teardown needed)
  TTE := TTestTokenEstimator.Create;
  try
    GRunner.RunTest('TokenEstimator: ascii text', TTE.Test_ASCII_Text);
    GRunner.RunTest('TokenEstimator: cjk text', TTE.Test_CJK_Text);
    GRunner.RunTest('TokenEstimator: empty text', TTE.Test_EmptyText);
    GRunner.RunTest('TokenEstimator: mixed text', TTE.Test_MixedText);
  finally
    TTE.Free;
  end;
end;

end.
