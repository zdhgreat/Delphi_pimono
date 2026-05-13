unit TestSvgIcons;

{ Tests for Utils.SvgIcons constants }

interface

uses
  System.SysUtils,
  Utils.SvgIcons,
  PiMonoTestFramework;

procedure RegisterSvgIconsTests;

implementation

type
  TTestSvgIcons = class
  public
    procedure Test_IconCount;
    procedure Test_IconIndexValues;
    procedure Test_IconIndexSequential;
    procedure Test_SvgIconsArrayLength;
    procedure Test_SvgIconNamesArrayLength;
    procedure Test_SvgIconsStartWithSvg;
    procedure Test_SvgIconNamesNonEmpty;
    procedure Test_SvgIconsContainXmlns;
    procedure Test_SvgMenuContent;
    procedure Test_SvgSendContent;
  end;

{ TTestSvgIcons }

procedure TTestSvgIcons.Test_IconCount;
begin
  Assert(ICON_COUNT = 12, 'ICON_COUNT should be 12');
end;

procedure TTestSvgIcons.Test_IconIndexValues;
begin
  Assert(ICON_MENU = 0, 'ICON_MENU = 0');
  Assert(ICON_SEND = 1, 'ICON_SEND = 1');
  Assert(ICON_CHEVRON_UP = 2, 'ICON_CHEVRON_UP = 2');
  Assert(ICON_CHEVRON_DOWN = 3, 'ICON_CHEVRON_DOWN = 3');
  Assert(ICON_CLOSE = 4, 'ICON_CLOSE = 4');
  Assert(ICON_ELLIPSIS = 5, 'ICON_ELLIPSIS = 5');
  Assert(ICON_PLUS = 6, 'ICON_PLUS = 6');
  Assert(ICON_STOP = 7, 'ICON_STOP = 7');
  Assert(ICON_COPY = 8, 'ICON_COPY = 8');
  Assert(ICON_MESSAGE = 9, 'ICON_MESSAGE = 9');
  Assert(ICON_SETTINGS = 10, 'ICON_SETTINGS = 10');
  Assert(ICON_TRASH = 11, 'ICON_TRASH = 11');
end;

procedure TTestSvgIcons.Test_IconIndexSequential;
var
  i: Integer;
begin
  for i := 0 to ICON_COUNT - 1 do
    Assert(Length(SVG_ICONS[i]) > 0,
      'SVG_ICONS[' + IntToStr(i) + '] should not be empty');
end;

procedure TTestSvgIcons.Test_SvgIconsArrayLength;
begin
  Assert(Length(SVG_ICONS) = ICON_COUNT, 'SVG_ICONS length = ICON_COUNT');
end;

procedure TTestSvgIcons.Test_SvgIconNamesArrayLength;
begin
  Assert(Length(SVG_ICON_NAMES) = ICON_COUNT, 'SVG_ICON_NAMES length = ICON_COUNT');
end;

procedure TTestSvgIcons.Test_SvgIconsStartWithSvg;
var
  i: Integer;
begin
  for i := 0 to ICON_COUNT - 1 do
    Assert(Copy(SVG_ICONS[i], 1, 4) = '<svg',
      'SVG_ICONS[' + IntToStr(i) + '] should start with <svg');
end;

procedure TTestSvgIcons.Test_SvgIconNamesNonEmpty;
var
  i: Integer;
begin
  for i := 0 to ICON_COUNT - 1 do
    Assert(Length(SVG_ICON_NAMES[i]) > 0,
      'SVG_ICON_NAMES[' + IntToStr(i) + '] should not be empty');
end;

procedure TTestSvgIcons.Test_SvgIconsContainXmlns;
var
  i: Integer;
begin
  for i := 0 to ICON_COUNT - 1 do
    Assert(Pos('xmlns', SVG_ICONS[i]) > 0,
      'SVG_ICONS[' + IntToStr(i) + '] should contain xmlns');
end;

procedure TTestSvgIcons.Test_SvgMenuContent;
begin
  Assert(Pos('line', LowerCase(SVG_MENU)) > 0, 'SVG_MENU should contain line elements');
end;

procedure TTestSvgIcons.Test_SvgSendContent;
begin
  Assert(Pos('path', LowerCase(SVG_SEND)) > 0, 'SVG_SEND should contain path elements');
end;

{ Registration }

procedure RegisterSvgIconsTests;
var
  T: TTestSvgIcons;
begin
  T := TTestSvgIcons.Create;
  try
    GRunner.RunTest('SvgIcons: Icon count', T.Test_IconCount);
    GRunner.RunTest('SvgIcons: Index values', T.Test_IconIndexValues);
    GRunner.RunTest('SvgIcons: Index sequential', T.Test_IconIndexSequential);
    GRunner.RunTest('SvgIcons: Array length', T.Test_SvgIconsArrayLength);
    GRunner.RunTest('SvgIcons: Names array length', T.Test_SvgIconNamesArrayLength);
    GRunner.RunTest('SvgIcons: Start with <svg', T.Test_SvgIconsStartWithSvg);
    GRunner.RunTest('SvgIcons: Names non-empty', T.Test_SvgIconNamesNonEmpty);
    GRunner.RunTest('SvgIcons: Contain xmlns', T.Test_SvgIconsContainXmlns);
    GRunner.RunTest('SvgIcons: Menu content', T.Test_SvgMenuContent);
    GRunner.RunTest('SvgIcons: Send content', T.Test_SvgSendContent);
  finally
    T.Free;
  end;
end;

end.
