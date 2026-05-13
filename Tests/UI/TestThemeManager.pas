unit TestThemeManager;

{ Tests for UI.ThemeManager - theme switching and color values }

interface

uses
  System.SysUtils, Vcl.Graphics, Winapi.Windows,
  UI.ThemeManager,
  PiMonoTestFramework;

procedure RegisterThemeManagerTests;

implementation

type
  TTestThemeManager = class
  private
    FTM: TThemeManager;
  public
    procedure Setup;
    procedure TearDown;
    procedure Test_Create_DefaultTheme;
    procedure Test_ApplyDarkTheme;
    procedure Test_ApplyLightTheme;
    procedure Test_SwitchDarkToLight;
    procedure Test_DarkBackgroundIsDark;
    procedure Test_DarkTextIsLight;
    procedure Test_LightBackgroundIsLight;
    procedure Test_LightTextIsDark;
    procedure Test_DarkLightDifferentColors;
    procedure Test_LayoutIntegersPositive;
    procedure Test_ThemeProperty;
    procedure Test_GetColorsReturnsRecord;
    procedure Test_DarkSpecificColorValues;
    procedure Test_LightSpecificColorValues;
  end;

{ TTestThemeManager }

procedure TTestThemeManager.Setup;
begin
  FTM := TThemeManager.Create;
end;

procedure TTestThemeManager.TearDown;
begin
  FTM.Free;
end;

procedure TTestThemeManager.Test_Create_DefaultTheme;
begin
  Assert(FTM.GetCurrentTheme = 'Dark', 'Default theme should be Dark');
end;

procedure TTestThemeManager.Test_ApplyDarkTheme;
var
  C: TThemeColors;
begin
  FTM.ApplyTheme('Dark');
  Assert(FTM.GetCurrentTheme = 'Dark', 'Theme should be Dark');
  C := FTM.GetColors;
  Assert(C.Background <> 0, 'Background should not be 0');
  Assert(C.Text <> 0, 'Text should not be 0');
end;

procedure TTestThemeManager.Test_ApplyLightTheme;
var
  C: TThemeColors;
begin
  FTM.ApplyTheme('Light');
  Assert(FTM.GetCurrentTheme = 'Light', 'Theme should be Light');
  C := FTM.GetColors;
  Assert(C.Background <> 0, 'Background should not be 0');
  Assert(C.Text <> 0, 'Text should not be 0');
end;

procedure TTestThemeManager.Test_SwitchDarkToLight;
begin
  FTM.ApplyTheme('Dark');
  Assert(FTM.GetCurrentTheme = 'Dark', 'Should be Dark');
  FTM.ApplyTheme('Light');
  Assert(FTM.GetCurrentTheme = 'Light', 'Should be Light after switch');
  FTM.ApplyTheme('Dark');
  Assert(FTM.GetCurrentTheme = 'Dark', 'Should be Dark again');
end;

procedure TTestThemeManager.Test_DarkBackgroundIsDark;
var
  C: TThemeColors;
begin
  FTM.ApplyTheme('Dark');
  C := FTM.GetColors;
  // Dark background: RGB components should all be < 128
  Assert(GetRValue(C.Background) < 128, 'Dark bg R < 128');
  Assert(GetGValue(C.Background) < 128, 'Dark bg G < 128');
  Assert(GetBValue(C.Background) < 128, 'Dark bg B < 128');
end;

procedure TTestThemeManager.Test_DarkTextIsLight;
var
  C: TThemeColors;
begin
  FTM.ApplyTheme('Dark');
  C := FTM.GetColors;
  // Light text: average luminance should be bright (> 180)
  var Luminance := (GetRValue(C.Text) + GetGValue(C.Text) + GetBValue(C.Text)) div 3;
  Assert(Luminance > 180, 'Dark theme text should be light (avg luminance > 180), got ' + IntToStr(Luminance));
end;

procedure TTestThemeManager.Test_LightBackgroundIsLight;
var
  C: TThemeColors;
begin
  FTM.ApplyTheme('Light');
  C := FTM.GetColors;
  // Light background: all RGB components should be > 200
  Assert(GetRValue(C.Background) > 200, 'Light bg R > 200');
  Assert(GetGValue(C.Background) > 200, 'Light bg G > 200');
  Assert(GetBValue(C.Background) > 200, 'Light bg B > 200');
end;

procedure TTestThemeManager.Test_LightTextIsDark;
var
  C: TThemeColors;
begin
  FTM.ApplyTheme('Light');
  C := FTM.GetColors;
  // Dark text: all components should be < 128
  Assert(GetRValue(C.Text) < 128, 'Light theme text R < 128');
  Assert(GetGValue(C.Text) < 128, 'Light theme text G < 128');
  Assert(GetBValue(C.Text) < 128, 'Light theme text B < 128');
end;

procedure TTestThemeManager.Test_DarkLightDifferentColors;
var
  DarkC, LightC: TThemeColors;
begin
  FTM.ApplyTheme('Dark');
  DarkC := FTM.GetColors;
  FTM.ApplyTheme('Light');
  LightC := FTM.GetColors;
  Assert(DarkC.Background <> LightC.Background, 'Dark/Light bg should differ');
  Assert(DarkC.Text <> LightC.Text, 'Dark/Light text should differ');
  Assert(DarkC.Surface <> LightC.Surface, 'Dark/Light surface should differ');
  Assert(DarkC.ButtonBackground <> LightC.ButtonBackground, 'Button bg should differ');
end;

procedure TTestThemeManager.Test_LayoutIntegersPositive;
var
  C: TThemeColors;
begin
  FTM.ApplyTheme('Dark');
  C := FTM.GetColors;
  Assert(C.MaxChatWidth > 0, 'MaxChatWidth should be positive');
  Assert(C.MessageSpacing > 0, 'MessageSpacing should be positive');
  Assert(C.RoleIconSize > 0, 'RoleIconSize should be positive');
  Assert(C.BubblePadding > 0, 'BubblePadding should be positive');
  Assert(C.SideMargin > 0, 'SideMargin should be positive');
end;

procedure TTestThemeManager.Test_ThemeProperty;
begin
  Assert(FTM.Theme = 'Dark', 'Theme property should match current theme');
  FTM.ApplyTheme('Light');
  Assert(FTM.Theme = 'Light', 'Theme property after switch');
end;

procedure TTestThemeManager.Test_GetColorsReturnsRecord;
var
  C: TThemeColors;
begin
  C := FTM.GetColors;
  Assert(C.MaxChatWidth > 0, 'GetColors should return valid record');
end;

procedure TTestThemeManager.Test_DarkSpecificColorValues;
var
  C: TThemeColors;
begin
  FTM.ApplyTheme('Dark');
  C := FTM.GetColors;
  Assert(C.Background = $1A1B1E, 'Dark background should be $1A1B1E');
  Assert(C.Surface = $2B2D31, 'Dark surface should be $2B2D31');
  Assert(C.Text = $F0F0F0, 'Dark text should be $F0F0F0');
end;

procedure TTestThemeManager.Test_LightSpecificColorValues;
var
  C: TThemeColors;
begin
  FTM.ApplyTheme('Light');
  C := FTM.GetColors;
  // Light theme should have light background (all RGB > 200)
  Assert(GetRValue(C.Background) > 200, 'Light bg R > 200');
  Assert(GetGValue(C.Background) > 200, 'Light bg G > 200');
  Assert(GetBValue(C.Background) > 200, 'Light bg B > 200');
end;

{ Registration }

procedure RegisterThemeManagerTests;
var
  T: TTestThemeManager;
begin
  T := TTestThemeManager.Create;
  try
    GRunner.RunTest('ThemeManager: Create default theme', T.Test_Create_DefaultTheme, T.Setup, T.TearDown);
    GRunner.RunTest('ThemeManager: Apply Dark theme', T.Test_ApplyDarkTheme, T.Setup, T.TearDown);
    GRunner.RunTest('ThemeManager: Apply Light theme', T.Test_ApplyLightTheme, T.Setup, T.TearDown);
    GRunner.RunTest('ThemeManager: Switch Dark to Light', T.Test_SwitchDarkToLight, T.Setup, T.TearDown);
    GRunner.RunTest('ThemeManager: Dark bg is dark', T.Test_DarkBackgroundIsDark, T.Setup, T.TearDown);
    GRunner.RunTest('ThemeManager: Dark text is light', T.Test_DarkTextIsLight, T.Setup, T.TearDown);
    GRunner.RunTest('ThemeManager: Light bg is light', T.Test_LightBackgroundIsLight, T.Setup, T.TearDown);
    GRunner.RunTest('ThemeManager: Light text is dark', T.Test_LightTextIsDark, T.Setup, T.TearDown);
    GRunner.RunTest('ThemeManager: Dark/Light differ', T.Test_DarkLightDifferentColors, T.Setup, T.TearDown);
    GRunner.RunTest('ThemeManager: Layout integers', T.Test_LayoutIntegersPositive, T.Setup, T.TearDown);
    GRunner.RunTest('ThemeManager: Theme property', T.Test_ThemeProperty, T.Setup, T.TearDown);
    GRunner.RunTest('ThemeManager: GetColors record', T.Test_GetColorsReturnsRecord, T.Setup, T.TearDown);
    GRunner.RunTest('ThemeManager: Dark specific values', T.Test_DarkSpecificColorValues, T.Setup, T.TearDown);
    GRunner.RunTest('ThemeManager: Light specific values', T.Test_LightSpecificColorValues, T.Setup, T.TearDown);
  finally
    T.Free;
  end;
end;

end.
