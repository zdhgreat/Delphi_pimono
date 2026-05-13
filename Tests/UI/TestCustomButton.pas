unit TestCustomButton;

{ Tests for UI.CustomButton MixColors function }

interface

uses
  System.SysUtils, Vcl.Graphics, Winapi.Windows,
  UI.CustomButton,
  PiMonoTestFramework;

procedure RegisterCustomButtonTests;

implementation

type
  TTestMixColors = class
  public
    procedure Test_BlackWhite50;
    procedure Test_RedBlue0;
    procedure Test_RedBlue100;
    procedure Test_SameColor;
    procedure Test_BoundaryZero;
    procedure Test_BoundaryHundred;
    procedure Test_25Percent;
    procedure Test_75Percent;
  end;

{ TTestMixColors }

procedure TTestMixColors.Test_BlackWhite50;
var
  R: TColor;
begin
  R := MixColors(clWhite, clBlack, 50);
  // At 50%, should be medium gray: RGB(127,127,127)
  Assert(GetRValue(R) >= 120, 'Gray R component >= 120');
  Assert(GetRValue(R) <= 135, 'Gray R component <= 135');
  Assert(GetGValue(R) >= 120, 'Gray G component >= 120');
  Assert(GetBValue(R) >= 120, 'Gray B component >= 120');
end;

procedure TTestMixColors.Test_RedBlue0;
begin
  // APerc <= 0 returns AColor2
  Assert(MixColors(clRed, clBlue, 0) = clBlue, '0% should return Color2');
end;

procedure TTestMixColors.Test_RedBlue100;
begin
  // APerc >= 100 returns AColor1
  Assert(MixColors(clRed, clBlue, 100) = clRed, '100% should return Color1');
end;

procedure TTestMixColors.Test_SameColor;
var
  R: TColor;
begin
  R := MixColors(clRed, clRed, 50);
  Assert(R = clRed, 'Same color should return same color');
end;

procedure TTestMixColors.Test_BoundaryZero;
begin
  Assert(MixColors(clRed, clBlue, 0) = clBlue, '0% boundary = Color2');
end;

procedure TTestMixColors.Test_BoundaryHundred;
begin
  Assert(MixColors(clRed, clBlue, 100) = clRed, '100% boundary = Color1');
end;

procedure TTestMixColors.Test_25Percent;
var
  R: TColor;
begin
  // 25% towards Red from Blue: R = 0 + (255-0)*25/100 = 63
  R := MixColors(clRed, clBlue, 25);
  Assert(GetRValue(R) > 0, '25% should have some Red');
  Assert(GetRValue(R) < 128, '25% should have less than half Red');
  Assert(GetBValue(R) > 128, '25% should have mostly Blue');
end;

procedure TTestMixColors.Test_75Percent;
var
  R: TColor;
begin
  // 75% towards Red from Blue
  R := MixColors(clRed, clBlue, 75);
  Assert(GetRValue(R) > 128, '75% should have mostly Red');
  Assert(GetBValue(R) < 128, '75% should have less Blue');
end;

{ Registration }

procedure RegisterCustomButtonTests;
var
  T: TTestMixColors;
begin
  T := TTestMixColors.Create;
  try
    GRunner.RunTest('CustomButton.MixColors: Black+White 50%', T.Test_BlackWhite50);
    GRunner.RunTest('CustomButton.MixColors: Red+Blue 0%', T.Test_RedBlue0);
    GRunner.RunTest('CustomButton.MixColors: Red+Blue 100%', T.Test_RedBlue100);
    GRunner.RunTest('CustomButton.MixColors: Same color', T.Test_SameColor);
    GRunner.RunTest('CustomButton.MixColors: Boundary 0', T.Test_BoundaryZero);
    GRunner.RunTest('CustomButton.MixColors: Boundary 100', T.Test_BoundaryHundred);
    GRunner.RunTest('CustomButton.MixColors: 25 percent', T.Test_25Percent);
    GRunner.RunTest('CustomButton.MixColors: 75 percent', T.Test_75Percent);
  finally
    T.Free;
  end;
end;

end.
