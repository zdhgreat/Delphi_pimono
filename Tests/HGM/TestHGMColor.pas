unit TestHGMColor;

{ Tests for HGM.Utils.Color - TRGB/TCMYK/THSV records and conversion functions }

interface

uses
  System.SysUtils, System.Math, Vcl.Graphics, Winapi.Windows,
  HGM.Utils.Color,
  PiMonoTestFramework;

procedure RegisterHGMColorTests;

implementation

type
  TTestRGB = class
  public
    procedure Test_Create_RGB;
    procedure Test_Create_Cardinal;
    procedure Test_Implicit_TColor_To_TRGB;
    procedure Test_Implicit_TRGB_To_TColor;
    procedure Test_SetRGB;
    procedure Test_Properties;
    procedure Test_SetIndividualChannels;
  end;

  TTestCMYK = class
  public
    procedure Test_Create;
    procedure Test_SetCMYK;
    procedure Test_Implicit_Roundtrip;
  end;

  TTestHSV = class
  public
    procedure Test_Create;
    procedure Test_SetHSV;
    procedure Test_PureRed;
    procedure Test_PureGreen;
  end;

  TTestConversions = class
  public
    procedure Test_RGBToColor_Roundtrip;
    procedure Test_GetRValue;
    procedure Test_GetGValue;
    procedure Test_GetBValue;
    procedure Test_GetAValue;
    procedure Test_RGBToCMYK_Black;
    procedure Test_CMYKToRGB_Roundtrip;
    procedure Test_RGBToHSV_Red;
    procedure Test_HSVToRGB_Roundtrip;
    procedure Test_HSVToColor_Red;
    procedure Test_GrayColor;
    procedure Test_InvertColor_White;
    procedure Test_InvertColor_Black;
    procedure Test_InvertColor_Roundtrip;
    procedure Test_HexToTColor_ColorToHex;
    procedure Test_ColorToHtml_HtmlToColor;
    procedure Test_VisibilityColor_Dark;
    procedure Test_VisibilityColor_Light;
    procedure Test_ColorToString_Format;
  end;

{ TTestRGB }

procedure TTestRGB.Test_Create_RGB;
var
  R: TRGB;
begin
  R := TRGB.Create(255, 0, 128);
  Assert(R.R = 255, 'R should be 255');
  Assert(R.G = 0, 'G should be 0');
  Assert(R.B = 128, 'B should be 128');
end;

procedure TTestRGB.Test_Create_Cardinal;
var
  R: TRGB;
begin
  R := TRGB.Create(Cardinal(RGBToColor(100, 150, 200)));
  Assert(R.R = 100, 'R should be 100');
  Assert(R.G = 150, 'G should be 150');
  Assert(R.B = 200, 'B should be 200');
end;

procedure TTestRGB.Test_Implicit_TColor_To_TRGB;
var
  R: TRGB;
  C: TColor;
begin
  C := RGBToColor(50, 100, 150);
  R := C;
  Assert(R.R = 50, 'Implicit TColor->TRGB R');
  Assert(R.G = 100, 'Implicit TColor->TRGB G');
  Assert(R.B = 150, 'Implicit TColor->TRGB B');
end;

procedure TTestRGB.Test_Implicit_TRGB_To_TColor;
var
  R: TRGB;
  C: TColor;
begin
  R := TRGB.Create(255, 128, 0);
  C := R;
  Assert(C = RGBToColor(255, 128, 0), 'Implicit TRGB->TColor');
end;

procedure TTestRGB.Test_SetRGB;
var
  R: TRGB;
begin
  R := TRGB.Create(0, 0, 0);
  R.SetRGB(10, 20, 30);
  Assert(R.R = 10, 'SetRGB R');
  Assert(R.G = 20, 'SetRGB G');
  Assert(R.B = 30, 'SetRGB B');
end;

procedure TTestRGB.Test_Properties;
var
  R: TRGB;
begin
  R := TRGB.Create(0, 0, 0);
  R.R := 255;
  R.G := 128;
  R.B := 64;
  Assert(R.R = 255, 'Property R');
  Assert(R.G = 128, 'Property G');
  Assert(R.B = 64, 'Property B');
end;

procedure TTestRGB.Test_SetIndividualChannels;
var
  R: TRGB;
  C: TColor;
begin
  R := TRGB.Create(100, 100, 100);
  R.R := 200;
  C := R;
  Assert(GetRValue(C) = 200, 'Setting R updates Color');
end;

{ TTestCMYK }

procedure TTestCMYK.Test_Create;
var
  C: TCMYK;
begin
  C := TCMYK.Create(10, 20, 30, 40);
  Assert(C.C = 10, 'C = 10');
  Assert(C.M = 20, 'M = 20');
  Assert(C.Y = 30, 'Y = 30');
  Assert(C.K = 40, 'K = 40');
end;

procedure TTestCMYK.Test_SetCMYK;
var
  C: TCMYK;
begin
  C := TCMYK.Create(0, 0, 0, 0);
  C.SetCMYK(50, 60, 70, 80);
  Assert(C.C = 50, 'C = 50');
  Assert(C.M = 60, 'M = 60');
  Assert(C.Y = 70, 'Y = 70');
  Assert(C.K = 80, 'K = 80');
end;

procedure TTestCMYK.Test_Implicit_Roundtrip;
var
  C: TCMYK;
  Color: TColor;
begin
  C := TCMYK.Create(10, 20, 30, 40);
  Color := C;
  Assert(Color = CMYKToColor(10, 20, 30, 40), 'CMYK->TColor roundtrip');
end;

{ TTestHSV }

procedure TTestHSV.Test_Create;
var
  H: THSV;
begin
  H := THSV.Create(0, 100, 100);
  Assert(Abs(H.H - 0) < 0.001, 'H = 0');
  Assert(Abs(H.S - 100) < 0.001, 'S = 100');
  Assert(Abs(H.V - 100) < 0.001, 'V = 100');
end;

procedure TTestHSV.Test_SetHSV;
var
  H: THSV;
begin
  H := THSV.Create(0, 0, 0);
  H.SetHSV(120, 50, 75);
  Assert(Abs(H.H - 120) < 0.001, 'H = 120');
  Assert(Abs(H.S - 50) < 0.001, 'S = 50');
  Assert(Abs(H.V - 75) < 0.001, 'V = 75');
end;

procedure TTestHSV.Test_PureRed;
var
  H: THSV;
  R, G, B: Byte;
begin
  // Pure red in HSV: H=0, S=100, V=100
  H := THSV.Create(0, 100, 100);
  HSVToRGB(H.H, H.S, H.V, R, G, B);
  Assert(R = 255, 'Red channel should be 255');
  Assert(G = 0, 'Green channel should be 0');
  Assert(B = 0, 'Blue channel should be 0');
end;

procedure TTestHSV.Test_PureGreen;
var
  H: THSV;
  R, G, B: Byte;
begin
  // Pure green in HSV: H=120, S=100, V=100
  H := THSV.Create(120, 100, 100);
  HSVToRGB(H.H, H.S, H.V, R, G, B);
  Assert(R = 0, 'Red should be 0');
  Assert(G = 255, 'Green should be 255');
  Assert(B = 0, 'Blue should be 0');
end;

{ TTestConversions }

procedure TTestConversions.Test_RGBToColor_Roundtrip;
var
  C: TColor;
begin
  C := RGBToColor(128, 64, 32);
  Assert(GetRValue(C) = 128, 'R roundtrip');
  Assert(GetGValue(C) = 64, 'G roundtrip');
  Assert(GetBValue(C) = 32, 'B roundtrip');
end;

procedure TTestConversions.Test_GetRValue;
begin
  Assert(HGM.Utils.Color.GetRValue(Cardinal($0000FF)) = 255, 'R of $FF = 255');
end;

procedure TTestConversions.Test_GetGValue;
begin
  Assert(HGM.Utils.Color.GetGValue(Cardinal($00FF00)) = 255, 'G of $FF00 = 255');
end;

procedure TTestConversions.Test_GetBValue;
begin
  Assert(HGM.Utils.Color.GetBValue(Cardinal($FF0000)) = 255, 'B of $FF0000 = 255');
end;

procedure TTestConversions.Test_GetAValue;
begin
  Assert(HGM.Utils.Color.GetAValue(Cardinal($FF000000)) = 255, 'A of $FF000000 = 255');
end;

procedure TTestConversions.Test_RGBToCMYK_Black;
var
  C, M, Y, K: Byte;
begin
  RGBToCMYK(0, 0, 0, C, M, Y, K);
  Assert(K = 255, 'Black K should be 255');
  Assert(C = 0, 'Black C should be 0');
  Assert(M = 0, 'Black M should be 0');
  Assert(Y = 0, 'Black Y should be 0');
end;

procedure TTestConversions.Test_CMYKToRGB_Roundtrip;
var
  R1, G1, B1: Byte;
  R2, G2, B2: Byte;
  C, M, Y, K: Byte;
begin
  R1 := 100; G1 := 150; B1 := 200;
  RGBToCMYK(R1, G1, B1, C, M, Y, K);
  CMYKToRGB(C, M, Y, K, R2, G2, B2);
  Assert(R2 = R1, 'CMYK roundtrip R');
  Assert(G2 = G1, 'CMYK roundtrip G');
  Assert(B2 = B1, 'CMYK roundtrip B');
end;

procedure TTestConversions.Test_RGBToHSV_Red;
var
  H, S, V: Double;
begin
  RGBToHSV(255, 0, 0, H, S, V);
  Assert(Abs(H - 0) < 1.0, 'Red H ~0');
  Assert(Abs(S - 100) < 1.0, 'Red S ~100');
  Assert(Abs(V - 100) < 1.0, 'Red V ~100');
end;

procedure TTestConversions.Test_HSVToRGB_Roundtrip;
var
  R1, G1, B1: Byte;
  R2, G2, B2: Byte;
  H, S, V: Double;
begin
  R1 := 128; G1 := 64; B1 := 200;
  RGBToHSV(R1, G1, B1, H, S, V);
  HSVToRGB(H, S, V, R2, G2, B2);
  Assert(Abs(R2 - R1) <= 2, 'HSV roundtrip R');
  Assert(Abs(G2 - G1) <= 2, 'HSV roundtrip G');
  Assert(Abs(B2 - B1) <= 2, 'HSV roundtrip B');
end;

procedure TTestConversions.Test_HSVToColor_Red;
var
  Value: TColor;
begin
  HSVToColor(0, 100, 100, Value);
  Assert(GetRValue(Value) = 255, 'HSV Red R=255');
  Assert(GetGValue(Value) = 0, 'HSV Red G=0');
  Assert(GetBValue(Value) = 0, 'HSV Red B=0');
end;

procedure TTestConversions.Test_GrayColor;
var
  G: TColor;
begin
  G := GrayColor(RGBToColor(255, 0, 0));
  Assert(GetRValue(G) = GetGValue(G), 'Gray R=G');
  Assert(GetGValue(G) = GetBValue(G), 'Gray G=B');
end;

procedure TTestConversions.Test_InvertColor_White;
var
  R: TColor;
begin
  R := InvertColor(RGBToColor(255, 255, 255));
  Assert(GetRValue(R) = 0, 'Invert white R=0');
  Assert(GetGValue(R) = 0, 'Invert white G=0');
  Assert(GetBValue(R) = 0, 'Invert white B=0');
end;

procedure TTestConversions.Test_InvertColor_Black;
var
  R: TColor;
begin
  R := InvertColor(RGBToColor(0, 0, 0));
  Assert(GetRValue(R) = 255, 'Invert black R=255');
  Assert(GetGValue(R) = 255, 'Invert black G=255');
  Assert(GetBValue(R) = 255, 'Invert black B=255');
end;

procedure TTestConversions.Test_InvertColor_Roundtrip;
var
  C, R: TColor;
begin
  C := RGBToColor(100, 150, 200);
  R := InvertColor(InvertColor(C));
  Assert(R = C, 'Double invert = identity');
end;

procedure TTestConversions.Test_HexToTColor_ColorToHex;
var
  C: TColor;
  Hex, RHex: string;
begin
  C := RGBToColor(255, 128, 64);
  Hex := ColorToHex(C);
  RHex := IntToHex(64, 2) + IntToHex(128, 2) + IntToHex(255, 2);
  Assert(Hex = RHex, 'ColorToHex format');

  var C2 := HexToTColor(Hex);
  Assert(GetRValue(C2) = 255, 'HexToTColor R roundtrip');
  Assert(GetGValue(C2) = 128, 'HexToTColor G roundtrip');
  Assert(GetBValue(C2) = 64, 'HexToTColor B roundtrip');
end;

procedure TTestConversions.Test_ColorToHtml_HtmlToColor;
var
  C: TColor;
  Html: string;
begin
  C := RGBToColor(255, 128, 64);
  Html := ColorToHtml(C);
  Assert(Html = '#FF8040', 'ColorToHtml format');  // IntToHex returns uppercase
end;

procedure TTestConversions.Test_VisibilityColor_Dark;
var
  V: TColor;
begin
  // Dark color (all channels < $40) -> should return white-ish
  V := VisibilityColor(RGBToColor(10, 10, 10));
  Assert(GetRValue(V) = $FF, 'Dark visibility should be white R');
  Assert(GetGValue(V) = $FF, 'Dark visibility should be white G');
  Assert(GetBValue(V) = $FF, 'Dark visibility should be white B');
end;

procedure TTestConversions.Test_VisibilityColor_Light;
var
  V: TColor;
begin
  // Light color (all channels > $40) -> should return dark-ish
  V := VisibilityColor(RGBToColor(200, 200, 200));
  Assert(GetRValue(V) = $00, 'Light visibility should be black R');
  Assert(GetGValue(V) = $00, 'Light visibility should be black G');
  Assert(GetBValue(V) = $00, 'Light visibility should be black B');
end;

procedure TTestConversions.Test_ColorToString_Format;
var
  S: string;
begin
  S := ColorToString(RGBToColor(255, 128, 64));
  Assert(Length(S) = 8, 'ColorToString should be 8 hex chars');
end;

{ Registration }

procedure RegisterHGMColorTests;
var
  TRGB: TTestRGB;
  TCMYK: TTestCMYK;
  THSV: TTestHSV;
  TC: TTestConversions;
begin
  TRGB := TTestRGB.Create;
  TCMYK := TTestCMYK.Create;
  THSV := TTestHSV.Create;
  TC := TTestConversions.Create;
  try
    GRunner.RunTest('HGMColor.RGB: Create RGB', TRGB.Test_Create_RGB);
    GRunner.RunTest('HGMColor.RGB: Create Cardinal', TRGB.Test_Create_Cardinal);
    GRunner.RunTest('HGMColor.RGB: Implicit TColor->TRGB', TRGB.Test_Implicit_TColor_To_TRGB);
    GRunner.RunTest('HGMColor.RGB: Implicit TRGB->TColor', TRGB.Test_Implicit_TRGB_To_TColor);
    GRunner.RunTest('HGMColor.RGB: SetRGB', TRGB.Test_SetRGB);
    GRunner.RunTest('HGMColor.RGB: Properties', TRGB.Test_Properties);
    GRunner.RunTest('HGMColor.RGB: SetIndividualChannels', TRGB.Test_SetIndividualChannels);

    GRunner.RunTest('HGMColor.CMYK: Create', TCMYK.Test_Create);
    GRunner.RunTest('HGMColor.CMYK: SetCMYK', TCMYK.Test_SetCMYK);
    GRunner.RunTest('HGMColor.CMYK: Implicit roundtrip', TCMYK.Test_Implicit_Roundtrip);

    GRunner.RunTest('HGMColor.HSV: Create', THSV.Test_Create);
    GRunner.RunTest('HGMColor.HSV: SetHSV', THSV.Test_SetHSV);
    GRunner.RunTest('HGMColor.HSV: Pure red', THSV.Test_PureRed);
    GRunner.RunTest('HGMColor.HSV: Pure green', THSV.Test_PureGreen);

    GRunner.RunTest('HGMColor.Conv: RGBToColor roundtrip', TC.Test_RGBToColor_Roundtrip);
    GRunner.RunTest('HGMColor.Conv: GetRValue', TC.Test_GetRValue);
    GRunner.RunTest('HGMColor.Conv: GetGValue', TC.Test_GetGValue);
    GRunner.RunTest('HGMColor.Conv: GetBValue', TC.Test_GetBValue);
    GRunner.RunTest('HGMColor.Conv: GetAValue', TC.Test_GetAValue);
    GRunner.RunTest('HGMColor.Conv: RGBToCMYK black', TC.Test_RGBToCMYK_Black);
    GRunner.RunTest('HGMColor.Conv: CMYKToRGB roundtrip', TC.Test_CMYKToRGB_Roundtrip);
    GRunner.RunTest('HGMColor.Conv: RGBToHSV red', TC.Test_RGBToHSV_Red);
    GRunner.RunTest('HGMColor.Conv: HSVToRGB roundtrip', TC.Test_HSVToRGB_Roundtrip);
    GRunner.RunTest('HGMColor.Conv: HSVToColor red', TC.Test_HSVToColor_Red);
    GRunner.RunTest('HGMColor.Conv: GrayColor', TC.Test_GrayColor);
    GRunner.RunTest('HGMColor.Conv: InvertColor white', TC.Test_InvertColor_White);
    GRunner.RunTest('HGMColor.Conv: InvertColor black', TC.Test_InvertColor_Black);
    GRunner.RunTest('HGMColor.Conv: InvertColor roundtrip', TC.Test_InvertColor_Roundtrip);
    GRunner.RunTest('HGMColor.Conv: Hex roundtrip', TC.Test_HexToTColor_ColorToHex);
    GRunner.RunTest('HGMColor.Conv: Html format', TC.Test_ColorToHtml_HtmlToColor);
    GRunner.RunTest('HGMColor.Conv: VisibilityColor dark', TC.Test_VisibilityColor_Dark);
    GRunner.RunTest('HGMColor.Conv: VisibilityColor light', TC.Test_VisibilityColor_Light);
    GRunner.RunTest('HGMColor.Conv: ColorToString', TC.Test_ColorToString_Format);
  finally
    TRGB.Free;
    TCMYK.Free;
    THSV.Free;
    TC.Free;
  end;
end;

end.
