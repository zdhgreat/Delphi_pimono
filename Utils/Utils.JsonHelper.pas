unit Utils.JsonHelper;

interface

uses
  System.JSON, System.SysUtils, System.Variants;

// Safe JSON value extraction compatible with Delphi 11.x
// Replaces GetValue<T>(key, default) which is only available in Delphi 12+

function JsonGetStr(AObj: TJSONObject; const AKey, ADefault: string): string;
function JsonGetInt(AObj: TJSONObject; const AKey: string; ADefault: Integer): Integer;
function JsonGetInt64(AObj: TJSONObject; const AKey: string; ADefault: Int64): Int64;
function JsonGetDbl(AObj: TJSONObject; const AKey: string; ADefault: Double): Double;
function JsonGetBool(AObj: TJSONObject; const AKey: string; ADefault: Boolean): Boolean;

// Auto-free JSON scope: creates a TJSONObject that is automatically freed when
// the scope ends. Use for the repetitive create-serialize-free pattern.
//
// Usage:
//   var J: TJSONObject;
//   with TJsonScope.Create(J) do
//   begin
//     J.AddPair('event', 'my_event');
//     PostToJS(J.ToJSON);
//   end;  // J is freed here

type
  TJsonScope = class
  private
    FJson: TJSONObject;
  public
    constructor Create(out AJson: TJSONObject);
    destructor Destroy; override;
  end;

implementation

function JsonGetStr(AObj: TJSONObject; const AKey, ADefault: string): string;
var
  Val: TJSONValue;
begin
  if (AObj = nil) or not AObj.TryGetValue(AKey, Val) then
    Result := ADefault
  else
    Result := Val.Value;
end;

function JsonGetInt(AObj: TJSONObject; const AKey: string; ADefault: Integer): Integer;
var
  Val: TJSONValue;
begin
  if (AObj = nil) or not AObj.TryGetValue(AKey, Val) then
    Result := ADefault
  else if (Val <> nil) and (Val is TJSONNumber) then
    Result := TJSONNumber(Val).AsInt
  else
    Result := ADefault;
end;

function JsonGetInt64(AObj: TJSONObject; const AKey: string; ADefault: Int64): Int64;
var
  Val: TJSONValue;
begin
  if (AObj = nil) or not AObj.TryGetValue(AKey, Val) then
    Result := ADefault
  else if (Val <> nil) and (Val is TJSONNumber) then
    Result := TJSONNumber(Val).AsInt64
  else
    Result := ADefault;
end;

function JsonGetDbl(AObj: TJSONObject; const AKey: string; ADefault: Double): Double;
var
  Val: TJSONValue;
begin
  if (AObj = nil) or not AObj.TryGetValue(AKey, Val) then
    Result := ADefault
  else if (Val <> nil) and (Val is TJSONNumber) then
    Result := TJSONNumber(Val).AsDouble
  else
    Result := ADefault;
end;

function JsonGetBool(AObj: TJSONObject; const AKey: string; ADefault: Boolean): Boolean;
var
  Val: TJSONValue;
begin
  if (AObj = nil) or not AObj.TryGetValue(AKey, Val) then
    Result := ADefault
  else if Val is TJSONBool then
    Result := TJSONBool(Val).AsBoolean
  else if Val is TJSONNumber then
    Result := TJSONNumber(Val).AsInt <> 0
  else
    Result := ADefault;
end;

{ TJsonScope }

constructor TJsonScope.Create(out AJson: TJSONObject);
begin
  inherited Create;
  FJson := TJSONObject.Create;
  AJson := FJson;
end;

destructor TJsonScope.Destroy;
begin
  FJson.Free;
  inherited;
end;

end.
