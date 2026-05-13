unit TestHGMUtils;

{ Tests for HGM.Common.Utils pure functions }

interface

uses
  System.SysUtils, System.Types, Vcl.Graphics, Winapi.Windows,
  HGM.Common.Utils,
  PiMonoTestFramework;

procedure RegisterHGMUtilsTests;

implementation

type
  TTestHGMUtils = class
  public
    procedure Test_Between_Inside;
    procedure Test_Between_Below;
    procedure Test_Between_Above;
    procedure Test_Between_AtMin;
    procedure Test_Between_AtMax;
    procedure Test_Centred_Equal;
    procedure Test_Centred_Different;
    procedure Test_ColorDarker_White;
    procedure Test_ColorLighter_Black;
    procedure Test_ColorDarker_NeverNegative;
    procedure Test_ColorLighter_NeverExceed255;
    procedure Test_CutString_Short;
    procedure Test_CutString_Long;
    procedure Test_CutString_Exact;
    procedure Test_CutString_Empty;
    procedure Test_GetFileNameWoE_Normal;
    procedure Test_GetFileNameWoE_NoExt;
    procedure Test_GetFileNameWoE_MultipleDots;
    procedure Test_GetLastDir_Normal;
    procedure Test_GetLastDir_NoDelimiter;
    procedure Test_GetSeconds;
    procedure Test_IndexInList_Inside;
    procedure Test_IndexInList_Outside;
    procedure Test_IndexInList_Empty;
    procedure Test_PercentRound_Normal;
    procedure Test_PercentRound_Over100;
    procedure Test_PercentRound_Negative;
    procedure Test_Reverse_Normal;
    procedure Test_Reverse_Empty;
    procedure Test_Reverse_Single;
    procedure Test_SimpleStrCompare_Same;
    procedure Test_SimpleStrCompare_Different;
    procedure Test_SimpleStrCompare_Empty;
    procedure Test_ScaledRect;
  end;

{ TTestHGMUtils }

procedure TTestHGMUtils.Test_Between_Inside;
begin
  Assert(Between(3, 5, 10), '5 is between 3 and 10');
end;

procedure TTestHGMUtils.Test_Between_Below;
begin
  Assert(not Between(3, 1, 10), '1 is not between 3 and 10');
end;

procedure TTestHGMUtils.Test_Between_Above;
begin
  Assert(not Between(3, 15, 10), '15 is not between 3 and 10');
end;

procedure TTestHGMUtils.Test_Between_AtMin;
begin
  Assert(Between(3, 3, 10), 'At min boundary should be True');
end;

procedure TTestHGMUtils.Test_Between_AtMax;
begin
  Assert(Between(3, 10, 10), 'At max boundary should be True');
end;

procedure TTestHGMUtils.Test_Centred_Equal;
begin
  Assert(Centred(100, 100) = 0, 'Centred(100,100) should be 0');
end;

procedure TTestHGMUtils.Test_Centred_Different;
begin
  // (200 div 2) - (100 div 2) = 100 - 50 = 50
  Assert(Centred(200, 100) = 50, 'Centred(200,100) should be 50');
end;

procedure TTestHGMUtils.Test_ColorDarker_White;
var
  R: TColor;
begin
  R := ColorDarker(clWhite, 50);
  // Darker white should be gray (less than 255 per channel)
  Assert(GetRValue(R) < 255, 'Darker white R < 255');
  Assert(GetGValue(R) < 255, 'Darker white G < 255');
  Assert(GetBValue(R) < 255, 'Darker white B < 255');
end;

procedure TTestHGMUtils.Test_ColorLighter_Black;
var
  R: TColor;
begin
  R := ColorLighter(clBlack, 50);
  // Lighter black should be gray (more than 0 per channel)
  Assert(GetRValue(R) > 0, 'Lighter black R > 0');
  Assert(GetGValue(R) > 0, 'Lighter black G > 0');
  Assert(GetBValue(R) > 0, 'Lighter black B > 0');
end;

procedure TTestHGMUtils.Test_ColorDarker_NeverNegative;
var
  R: TColor;
begin
  R := ColorDarker(clBlack, 100);
  Assert(GetRValue(R) = 0, 'Darker black should stay 0');
  Assert(GetGValue(R) = 0, 'Darker black G stays 0');
  Assert(GetBValue(R) = 0, 'Darker black B stays 0');
end;

procedure TTestHGMUtils.Test_ColorLighter_NeverExceed255;
var
  R: TColor;
begin
  R := ColorLighter(clWhite, 100);
  // GetRValue/GetGValue/GetBValue return Byte (0..255) — always <= 255.
  // Verify ColorLighter on clWhite returns clWhite (no overflow).
  Assert(R = clWhite, 'Lighter white should remain white');
end;

procedure TTestHGMUtils.Test_CutString_Short;
begin
  Assert(CutString('Hello', 10) = 'Hello', 'Short string unchanged');
end;

procedure TTestHGMUtils.Test_CutString_Long;
begin
  Assert(CutString('Hello World', 5) = 'Hello...', 'Long string truncated with ...');
end;

procedure TTestHGMUtils.Test_CutString_Exact;
begin
  Assert(CutString('Hello', 5) = 'Hello', 'Exact length no truncation');
end;

procedure TTestHGMUtils.Test_CutString_Empty;
begin
  Assert(CutString('', 5) = '', 'Empty string stays empty');
end;

procedure TTestHGMUtils.Test_GetFileNameWoE_Normal;
begin
  Assert(GetFileNameWoE('test.txt') = 'test', 'test.txt -> test');
end;

procedure TTestHGMUtils.Test_GetFileNameWoE_NoExt;
begin
  // No extension: function returns empty (Length < 3 check) or full string
  var R := GetFileNameWoE('ab');
  Assert(R = '', 'Short name without ext returns empty');
end;

procedure TTestHGMUtils.Test_GetFileNameWoE_MultipleDots;
begin
  Assert(GetFileNameWoE('archive.tar.gz') = 'archive.tar', 'archive.tar.gz -> archive.tar');
end;

procedure TTestHGMUtils.Test_GetLastDir_Normal;
begin
  Assert(GetLastDir('C:\foo\bar') = 'bar', 'Last dir of C:\foo\bar is bar');
end;

procedure TTestHGMUtils.Test_GetLastDir_NoDelimiter;
begin
  Assert(GetLastDir('foobar') = 'foobar', 'No delimiter returns full string');
end;

procedure TTestHGMUtils.Test_GetSeconds;
var
  T: TTime;
begin
  T := EncodeTime(1, 30, 45, 0);
  Assert(GetSeconds(T) = 1 * 3600 + 30 * 60 + 45, '1:30:45 = 5445 seconds');
end;

procedure TTestHGMUtils.Test_IndexInList_Inside;
begin
  Assert(IndexInList(2, 5), 'Index 2 in list of 5 is valid');
end;

procedure TTestHGMUtils.Test_IndexInList_Outside;
begin
  Assert(not IndexInList(5, 5), 'Index 5 in list of 5 is out of range');
end;

procedure TTestHGMUtils.Test_IndexInList_Empty;
begin
  Assert(not IndexInList(0, 0), 'Index 0 in empty list is invalid');
end;

procedure TTestHGMUtils.Test_PercentRound_Normal;
begin
  Assert(Abs(PercentRound(50.0) - 50.0) < 0.001, '50% stays 50');
end;

procedure TTestHGMUtils.Test_PercentRound_Over100;
begin
  Assert(Abs(PercentRound(150.0) - 100.0) < 0.001, '150% clamped to 100');
end;

procedure TTestHGMUtils.Test_PercentRound_Negative;
begin
  Assert(Abs(PercentRound(-10.0)) < 0.001, 'Negative clamped to 0');
end;

procedure TTestHGMUtils.Test_Reverse_Normal;
begin
  Assert(Reverse('abc') = 'cba', 'Reverse abc = cba');
end;

procedure TTestHGMUtils.Test_Reverse_Empty;
begin
  Assert(Reverse('') = '', 'Reverse empty = empty');
end;

procedure TTestHGMUtils.Test_Reverse_Single;
begin
  Assert(Reverse('a') = 'a', 'Reverse single char = same');
end;

procedure TTestHGMUtils.Test_SimpleStrCompare_Same;
begin
  Assert(Abs(SimpleStrCompare('abc', 'abc') - 1.0) < 0.001, 'Same strings = 1.0');
end;

procedure TTestHGMUtils.Test_SimpleStrCompare_Different;
begin
  Assert(SimpleStrCompare('abc', 'xyz') < 1.0, 'Different strings < 1.0');
end;

procedure TTestHGMUtils.Test_SimpleStrCompare_Empty;
begin
  Assert(Abs(SimpleStrCompare('', 'abc')) < 0.001, 'Empty vs non-empty = 0');
end;

procedure TTestHGMUtils.Test_ScaledRect;
var
  R: TRect;
begin
  R := ScaledRect(Rect(10, 20, 30, 40), 5);
  // ScaledRect expands: Left-Delta, Top-Delta, Right+Delta, Bottom+Delta
  Assert(R.Left = 5, 'Left should be 10-5=5');
  Assert(R.Top = 15, 'Top should be 20-5=15');
  Assert(R.Right = 35, 'Right should be 30+5=35');
  Assert(R.Bottom = 45, 'Bottom should be 40+5=45');
end;

{ Registration }

procedure RegisterHGMUtilsTests;
var
  T: TTestHGMUtils;
begin
  T := TTestHGMUtils.Create;
  try
    GRunner.RunTest('HGMUtils: Between inside', T.Test_Between_Inside);
    GRunner.RunTest('HGMUtils: Between below', T.Test_Between_Below);
    GRunner.RunTest('HGMUtils: Between above', T.Test_Between_Above);
    GRunner.RunTest('HGMUtils: Between at min', T.Test_Between_AtMin);
    GRunner.RunTest('HGMUtils: Between at max', T.Test_Between_AtMax);
    GRunner.RunTest('HGMUtils: Centred equal', T.Test_Centred_Equal);
    GRunner.RunTest('HGMUtils: Centred different', T.Test_Centred_Different);
    GRunner.RunTest('HGMUtils: ColorDarker white', T.Test_ColorDarker_White);
    GRunner.RunTest('HGMUtils: ColorLighter black', T.Test_ColorLighter_Black);
    GRunner.RunTest('HGMUtils: ColorDarker never negative', T.Test_ColorDarker_NeverNegative);
    GRunner.RunTest('HGMUtils: ColorLighter max 255', T.Test_ColorLighter_NeverExceed255);
    GRunner.RunTest('HGMUtils: CutString short', T.Test_CutString_Short);
    GRunner.RunTest('HGMUtils: CutString long', T.Test_CutString_Long);
    GRunner.RunTest('HGMUtils: CutString exact', T.Test_CutString_Exact);
    GRunner.RunTest('HGMUtils: CutString empty', T.Test_CutString_Empty);
    GRunner.RunTest('HGMUtils: GetFileNameWoE normal', T.Test_GetFileNameWoE_Normal);
    GRunner.RunTest('HGMUtils: GetFileNameWoE no ext', T.Test_GetFileNameWoE_NoExt);
    GRunner.RunTest('HGMUtils: GetFileNameWoE multi dot', T.Test_GetFileNameWoE_MultipleDots);
    GRunner.RunTest('HGMUtils: GetLastDir normal', T.Test_GetLastDir_Normal);
    GRunner.RunTest('HGMUtils: GetLastDir no delim', T.Test_GetLastDir_NoDelimiter);
    GRunner.RunTest('HGMUtils: GetSeconds', T.Test_GetSeconds);
    GRunner.RunTest('HGMUtils: IndexInList inside', T.Test_IndexInList_Inside);
    GRunner.RunTest('HGMUtils: IndexInList outside', T.Test_IndexInList_Outside);
    GRunner.RunTest('HGMUtils: IndexInList empty', T.Test_IndexInList_Empty);
    GRunner.RunTest('HGMUtils: PercentRound normal', T.Test_PercentRound_Normal);
    GRunner.RunTest('HGMUtils: PercentRound over 100', T.Test_PercentRound_Over100);
    GRunner.RunTest('HGMUtils: PercentRound negative', T.Test_PercentRound_Negative);
    GRunner.RunTest('HGMUtils: Reverse normal', T.Test_Reverse_Normal);
    GRunner.RunTest('HGMUtils: Reverse empty', T.Test_Reverse_Empty);
    GRunner.RunTest('HGMUtils: Reverse single', T.Test_Reverse_Single);
    GRunner.RunTest('HGMUtils: SimpleStrCompare same', T.Test_SimpleStrCompare_Same);
    GRunner.RunTest('HGMUtils: SimpleStrCompare diff', T.Test_SimpleStrCompare_Different);
    GRunner.RunTest('HGMUtils: SimpleStrCompare empty', T.Test_SimpleStrCompare_Empty);
    GRunner.RunTest('HGMUtils: ScaledRect', T.Test_ScaledRect);
  finally
    T.Free;
  end;
end;

end.
