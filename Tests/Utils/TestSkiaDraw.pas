unit TestSkiaDraw;

{ Tests for Utils.SkiaDraw - ColorToAlphaColor and shadow constants }

interface

uses
  System.SysUtils, System.UITypes, Vcl.Graphics, Winapi.Windows,
  Utils.SkiaDraw,
  PiMonoTestFramework;

procedure RegisterSkiaDrawTests;

implementation

type
  TTestSkiaDraw = class
  public
    procedure Test_ColorToAlphaColor_Red;
    procedure Test_ColorToAlphaColor_Black;
    procedure Test_ColorToAlphaColor_White;
    procedure Test_ColorToAlphaColor_None;
    procedure Test_Shadow1Constants;
    procedure Test_Shadow2Constants;
    procedure Test_Shadow3Constants;
    procedure Test_ShadowLevelProgression;
    procedure Test_TShadowLevelRecord;
  end;

{ TTestSkiaDraw }

procedure TTestSkiaDraw.Test_ColorToAlphaColor_Red;
var
  A: TAlphaColor;
begin
  A := ColorToAlphaColor(RGB(255, 0, 0));
  Assert(TAlphaColorRec(A).R = 255, 'Red channel should be 255');
  Assert(TAlphaColorRec(A).G = 0, 'Green channel should be 0');
  Assert(TAlphaColorRec(A).B = 0, 'Blue channel should be 0');
  Assert(TAlphaColorRec(A).A = 255, 'Alpha should be 255');
end;

procedure TTestSkiaDraw.Test_ColorToAlphaColor_Black;
var
  A: TAlphaColor;
begin
  A := ColorToAlphaColor(RGB(0, 0, 0));
  Assert(TAlphaColorRec(A).R = 0, 'Black R = 0');
  Assert(TAlphaColorRec(A).G = 0, 'Black G = 0');
  Assert(TAlphaColorRec(A).B = 0, 'Black B = 0');
  Assert(TAlphaColorRec(A).A = 255, 'Black Alpha = 255');
end;

procedure TTestSkiaDraw.Test_ColorToAlphaColor_White;
var
  A: TAlphaColor;
begin
  A := ColorToAlphaColor(RGB(255, 255, 255));
  Assert(TAlphaColorRec(A).R = 255, 'White R = 255');
  Assert(TAlphaColorRec(A).G = 255, 'White G = 255');
  Assert(TAlphaColorRec(A).B = 255, 'White B = 255');
  Assert(TAlphaColorRec(A).A = 255, 'White Alpha = 255');
end;

procedure TTestSkiaDraw.Test_ColorToAlphaColor_None;
var
  A: TAlphaColor;
begin
  A := ColorToAlphaColor(clNone);
  Assert(A = TAlphaColorRec.Null, 'clNone should return Null');
end;

procedure TTestSkiaDraw.Test_Shadow1Constants;
begin
  Assert(Abs(SHADOW_1.Blur - 3) < 0.001, 'SHADOW_1.Blur = 3');
  Assert(Abs(SHADOW_1.OffsetX - 0) < 0.001, 'SHADOW_1.OffsetX = 0');
  Assert(Abs(SHADOW_1.OffsetY - 1) < 0.001, 'SHADOW_1.OffsetY = 1');
end;

procedure TTestSkiaDraw.Test_Shadow2Constants;
begin
  Assert(Abs(SHADOW_2.Blur - 6) < 0.001, 'SHADOW_2.Blur = 6');
  Assert(Abs(SHADOW_2.OffsetX - 0) < 0.001, 'SHADOW_2.OffsetX = 0');
  Assert(Abs(SHADOW_2.OffsetY - 2) < 0.001, 'SHADOW_2.OffsetY = 2');
end;

procedure TTestSkiaDraw.Test_Shadow3Constants;
begin
  Assert(Abs(SHADOW_3.Blur - 12) < 0.001, 'SHADOW_3.Blur = 12');
  Assert(Abs(SHADOW_3.OffsetX - 0) < 0.001, 'SHADOW_3.OffsetX = 0');
  Assert(Abs(SHADOW_3.OffsetY - 4) < 0.001, 'SHADOW_3.OffsetY = 4');
end;

procedure TTestSkiaDraw.Test_ShadowLevelProgression;
begin
  // Blur increases: 3 < 6 < 12
  Assert(SHADOW_1.Blur < SHADOW_2.Blur, 'Blur: S1 < S2');
  Assert(SHADOW_2.Blur < SHADOW_3.Blur, 'Blur: S2 < S3');
  // OffsetY increases: 1 < 2 < 4
  Assert(SHADOW_1.OffsetY < SHADOW_2.OffsetY, 'OffsetY: S1 < S2');
  Assert(SHADOW_2.OffsetY < SHADOW_3.OffsetY, 'OffsetY: S2 < S3');
end;

procedure TTestSkiaDraw.Test_TShadowLevelRecord;
var
  S: TShadowLevel;
begin
  S.Blur := 5.0;
  S.OffsetX := 1.0;
  S.OffsetY := 2.0;
  Assert(Abs(S.Blur - 5.0) < 0.001, 'Record Blur');
  Assert(Abs(S.OffsetX - 1.0) < 0.001, 'Record OffsetX');
  Assert(Abs(S.OffsetY - 2.0) < 0.001, 'Record OffsetY');
end;

{ Registration }

procedure RegisterSkiaDrawTests;
var
  T: TTestSkiaDraw;
begin
  T := TTestSkiaDraw.Create;
  try
    GRunner.RunTest('SkiaDraw: ColorToAlphaColor Red', T.Test_ColorToAlphaColor_Red);
    GRunner.RunTest('SkiaDraw: ColorToAlphaColor Black', T.Test_ColorToAlphaColor_Black);
    GRunner.RunTest('SkiaDraw: ColorToAlphaColor White', T.Test_ColorToAlphaColor_White);
    GRunner.RunTest('SkiaDraw: ColorToAlphaColor None', T.Test_ColorToAlphaColor_None);
    GRunner.RunTest('SkiaDraw: Shadow1 constants', T.Test_Shadow1Constants);
    GRunner.RunTest('SkiaDraw: Shadow2 constants', T.Test_Shadow2Constants);
    GRunner.RunTest('SkiaDraw: Shadow3 constants', T.Test_Shadow3Constants);
    GRunner.RunTest('SkiaDraw: Shadow progression', T.Test_ShadowLevelProgression);
    GRunner.RunTest('SkiaDraw: TShadowLevel record', T.Test_TShadowLevelRecord);
  finally
    T.Free;
  end;
end;

end.
