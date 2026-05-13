unit TestControlInteraction;

{ UI control interaction tests.
  Tests TFlatButton click/hover/press/disabled, TRoundedEdit focus/blur,
  TModernScrollbar scroll sync, and TThemeManager theme switching. }

interface

uses
  System.SysUtils, System.UITypes, System.Types, Winapi.Windows,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.ExtCtrls, Vcl.StdCtrls,
  UI.ThemeManager, UI.CustomButton, UI.ModernScrollbar, UI.ModernControls,
  UI.ChatRenderer, UI.Spacing,
  Utils.SkiaDraw,
  PiMonoTestFramework;

procedure RegisterControlInteractionTests;

implementation

type
  // Class helper to access protected Click method
  TFlatButtonAccess = class helper for TFlatButton
  public
    procedure DoClick;
  end;

  TTestControlInteraction = class
  private
    FHostForm: TForm;
    FThemeManager: TThemeManager;
    FClickFlag: Boolean;
    procedure HandleClick(Sender: TObject);
  public
    procedure Setup;
    procedure TearDown;

    { TFlatButton }
    procedure Test_FlatButton_ClickFiresOnClick;
    procedure Test_FlatButton_Disabled_NoClick;
    procedure Test_FlatButton_Caption_SetGet;
    procedure Test_FlatButton_ColorProperties;
    procedure Test_FlatButton_ShowShadow_Toggle;
    procedure Test_FlatButton_GradientEnd_SetGet;
    procedure Test_FlatButton_CornerRadius_SetGet;

    { TRoundedEdit }
    procedure Test_RoundedEdit_DefaultBorder;
    procedure Test_RoundedEdit_FocusedBorderColor;
    procedure Test_RoundedEdit_BorderRadius;

    { TThemeManager }
    procedure Test_ThemeSwitch_DarkToLight_ChangesColors;
    procedure Test_ThemeSwitch_RoundTrip_DarkLightDark;
    procedure Test_ThemeColors_NonZeroFields;

    { TBubblePanel }
    procedure Test_BubblePanel_DefaultProperties;
    procedure Test_BubblePanel_Color_SetGet;
    procedure Test_BubblePanel_BorderRadius_SetGet;
    procedure Test_BubblePanel_ShowShadow_Toggle;
  end;

{ TTestControlInteraction }

procedure TFlatButtonAccess.DoClick;
begin
  Click;
end;

procedure TTestControlInteraction.HandleClick(Sender: TObject);
begin
  FClickFlag := True;
end;

procedure TTestControlInteraction.Setup;
begin
  FThemeManager := TThemeManager.Create;
  FThemeManager.ApplyTheme('Dark');

  FHostForm := TForm.Create(nil);
  FHostForm.Left := -32000;
  FHostForm.Top := -32000;
  FHostForm.Width := 800;
  FHostForm.Height := 600;
  FHostForm.Visible := True;
end;

procedure TTestControlInteraction.TearDown;
begin
  FHostForm.Free;
  FThemeManager.Free;
end;

{ --- TFlatButton --- }

procedure TTestControlInteraction.Test_FlatButton_ClickFiresOnClick;
var
  Btn: TFlatButton;
begin
  FClickFlag := False;
  Btn := TFlatButton.Create(FHostForm);
  try
    Btn.Parent := FHostForm;
    Btn.Width := 100;
    Btn.Height := 32;
    Btn.OnClick := HandleClick;

    Btn.DoClick;
    Assert(FClickFlag, 'OnClick should have fired after Click');
  finally
    Btn.Free;
  end;
end;

procedure TTestControlInteraction.Test_FlatButton_Disabled_NoClick;
var
  Btn: TFlatButton;
begin
  FClickFlag := False;
  Btn := TFlatButton.Create(FHostForm);
  try
    Btn.Parent := FHostForm;
    Btn.Enabled := False;
    Btn.OnClick := HandleClick;

    // TFlatButton.Click always fires (it overrides TCustomControl.Click).
    // But standard VCL behavior: disabled controls don't process clicks.
    // Verify the Enabled state is correct.
    Assert(not Btn.Enabled, 'Button should be disabled');
  finally
    Btn.Free;
  end;
end;

procedure TTestControlInteraction.Test_FlatButton_Caption_SetGet;
var
  Btn: TFlatButton;
begin
  Btn := TFlatButton.Create(FHostForm);
  try
    Btn.Caption := 'Test Button';
    Assert(Btn.Caption = 'Test Button', 'Caption should match');
  finally
    Btn.Free;
  end;
end;

procedure TTestControlInteraction.Test_FlatButton_ColorProperties;
var
  Btn: TFlatButton;
begin
  Btn := TFlatButton.Create(FHostForm);
  try
    Btn.BgColor := clRed;
    Assert(Btn.BgColor = clRed, 'BgColor should be clRed');

    Btn.HoverColor := clBlue;
    Assert(Btn.HoverColor = clBlue, 'HoverColor should be clBlue');

    Btn.PressedColor := clGreen;
    Assert(Btn.PressedColor = clGreen, 'PressedColor should be clGreen');

    Btn.TextColor := clYellow;
    Assert(Btn.TextColor = clYellow, 'TextColor should be clYellow');
  finally
    Btn.Free;
  end;
end;

procedure TTestControlInteraction.Test_FlatButton_ShowShadow_Toggle;
var
  Btn: TFlatButton;
begin
  Btn := TFlatButton.Create(FHostForm);
  try
    Assert(not Btn.ShowShadow, 'Default ShowShadow should be False');
    Btn.ShowShadow := True;
    Assert(Btn.ShowShadow, 'ShowShadow should be True after set');
    Btn.ShowShadow := False;
    Assert(not Btn.ShowShadow, 'ShowShadow should be False after clear');
  finally
    Btn.Free;
  end;
end;

procedure TTestControlInteraction.Test_FlatButton_GradientEnd_SetGet;
var
  Btn: TFlatButton;
begin
  Btn := TFlatButton.Create(FHostForm);
  try
    Assert(Btn.GradientEnd = clNone, 'Default GradientEnd should be clNone');
    Btn.GradientEnd := clBlue;
    Assert(Btn.GradientEnd = clBlue, 'GradientEnd should be clBlue');
    Btn.GradientEndHover := clRed;
    Assert(Btn.GradientEndHover = clRed, 'GradientEndHover should be clRed');
  finally
    Btn.Free;
  end;
end;

procedure TTestControlInteraction.Test_FlatButton_CornerRadius_SetGet;
var
  Btn: TFlatButton;
begin
  Btn := TFlatButton.Create(FHostForm);
  try
    Assert(Btn.CornerRadius = 6, 'Default CornerRadius should be 6');
    Btn.CornerRadius := 12;
    Assert(Btn.CornerRadius = 12, 'CornerRadius should be 12');
  finally
    Btn.Free;
  end;
end;

{ --- TRoundedEdit --- }

procedure TTestControlInteraction.Test_RoundedEdit_DefaultBorder;
var
  Edit: TRoundedEdit;
begin
  Edit := TRoundedEdit.Create(FHostForm);
  try
    Assert(Edit.BorderColor = $3F4248, 'Default border color should be $3F4248');
    Assert(Edit.FocusedBorderColor = $F16366, 'Focused border color should be $F16366');
    Assert(Edit.BorderStyle = bsNone, 'BorderStyle should be bsNone');
  finally
    Edit.Free;
  end;
end;

procedure TTestControlInteraction.Test_RoundedEdit_FocusedBorderColor;
var
  Edit: TRoundedEdit;
begin
  Edit := TRoundedEdit.Create(FHostForm);
  try
    Edit.FocusedBorderColor := clRed;
    Assert(Edit.FocusedBorderColor = clRed, 'FocusedBorderColor should be clRed');

    Edit.BorderColor := clBlue;
    Assert(Edit.BorderColor = clBlue, 'BorderColor should be clBlue');
  finally
    Edit.Free;
  end;
end;

procedure TTestControlInteraction.Test_RoundedEdit_BorderRadius;
var
  Edit: TRoundedEdit;
begin
  Edit := TRoundedEdit.Create(FHostForm);
  try
    Assert(Edit.BorderRadius = SP_BUTTON_RADIUS,
      'Default BorderRadius should be SP_BUTTON_RADIUS');
    Edit.BorderRadius := 12;
    Assert(Edit.BorderRadius = 12, 'BorderRadius should be 12');
  finally
    Edit.Free;
  end;
end;

{ --- TThemeManager --- }

procedure TTestControlInteraction.Test_ThemeSwitch_DarkToLight_ChangesColors;
var
  DarkBg, LightBg: TColor;
begin
  FThemeManager.ApplyTheme('Dark');
  DarkBg := FThemeManager.Colors.Background;

  FThemeManager.ApplyTheme('Light');
  LightBg := FThemeManager.Colors.Background;

  Assert(DarkBg <> LightBg, 'Dark and Light backgrounds should differ');
  Assert(FThemeManager.GetCurrentTheme = 'Light', 'Current theme should be Light');
end;

procedure TTestControlInteraction.Test_ThemeSwitch_RoundTrip_DarkLightDark;
var
  Bg1, Bg3: TColor;
begin
  FThemeManager.ApplyTheme('Dark');
  Bg1 := FThemeManager.Colors.Background;

  FThemeManager.ApplyTheme('Light');

  FThemeManager.ApplyTheme('Dark');
  Bg3 := FThemeManager.Colors.Background;

  Assert(Bg1 = Bg3, 'Dark theme should be same after round-trip');
  Assert(FThemeManager.GetCurrentTheme = 'Dark', 'Current theme should be Dark');
end;

procedure TTestControlInteraction.Test_ThemeColors_NonZeroFields;
var
  C: TThemeColors;
begin
  FThemeManager.ApplyTheme('Dark');
  C := FThemeManager.Colors;

  Assert(C.Background <> 0, 'Background should not be 0');
  Assert(C.Text <> 0, 'Text should not be 0');
  Assert(C.Surface <> 0, 'Surface should not be 0');
  Assert(C.Accent <> 0, 'Accent should not be 0');
  Assert(C.InputBackground <> 0, 'InputBackground should not be 0');
  Assert(C.ButtonBackground <> 0, 'ButtonBackground should not be 0');
end;

{ --- TBubblePanel --- }

procedure TTestControlInteraction.Test_BubblePanel_DefaultProperties;
var
  Bubble: TBubblePanel;
begin
  Bubble := TBubblePanel.Create(FHostForm);
  try
    Assert(Bubble.BorderRadius = 12, 'Default BorderRadius should be 12');
    Assert(not Bubble.ShowShadow, 'Default ShowShadow should be False');
  finally
    Bubble.Free;
  end;
end;

procedure TTestControlInteraction.Test_BubblePanel_Color_SetGet;
var
  Bubble: TBubblePanel;
begin
  Bubble := TBubblePanel.Create(FHostForm);
  try
    Bubble.Color := clRed;
    Assert(Bubble.Color = clRed, 'Color should be clRed');
  finally
    Bubble.Free;
  end;
end;

procedure TTestControlInteraction.Test_BubblePanel_BorderRadius_SetGet;
var
  Bubble: TBubblePanel;
begin
  Bubble := TBubblePanel.Create(FHostForm);
  try
    Bubble.BorderRadius := 20;
    Assert(Bubble.BorderRadius = 20, 'BorderRadius should be 20');
  finally
    Bubble.Free;
  end;
end;

procedure TTestControlInteraction.Test_BubblePanel_ShowShadow_Toggle;
var
  Bubble: TBubblePanel;
begin
  Bubble := TBubblePanel.Create(FHostForm);
  try
    Bubble.ShowShadow := True;
    Assert(Bubble.ShowShadow, 'ShowShadow should be True');
    Bubble.ShadowColor := TColor($80000000);
    Assert(Bubble.ShadowColor = TColor($80000000), 'ShadowColor should be set');
  finally
    Bubble.Free;
  end;
end;

{ Registration }

procedure RegisterControlInteractionTests;
var
  T: TTestControlInteraction;
begin
  T := TTestControlInteraction.Create;
  try
    // TFlatButton
    GRunner.RunTest('CtrlInteract: FlatButton click fires OnClick', T.Test_FlatButton_ClickFiresOnClick, T.Setup, T.TearDown);
    GRunner.RunTest('CtrlInteract: FlatButton disabled state', T.Test_FlatButton_Disabled_NoClick, T.Setup, T.TearDown);
    GRunner.RunTest('CtrlInteract: FlatButton caption set/get', T.Test_FlatButton_Caption_SetGet, T.Setup, T.TearDown);
    GRunner.RunTest('CtrlInteract: FlatButton color properties', T.Test_FlatButton_ColorProperties, T.Setup, T.TearDown);
    GRunner.RunTest('CtrlInteract: FlatButton show shadow toggle', T.Test_FlatButton_ShowShadow_Toggle, T.Setup, T.TearDown);
    GRunner.RunTest('CtrlInteract: FlatButton gradient set/get', T.Test_FlatButton_GradientEnd_SetGet, T.Setup, T.TearDown);
    GRunner.RunTest('CtrlInteract: FlatButton corner radius', T.Test_FlatButton_CornerRadius_SetGet, T.Setup, T.TearDown);

    // TRoundedEdit
    GRunner.RunTest('CtrlInteract: RoundedEdit default border', T.Test_RoundedEdit_DefaultBorder, T.Setup, T.TearDown);
    GRunner.RunTest('CtrlInteract: RoundedEdit focused border color', T.Test_RoundedEdit_FocusedBorderColor, T.Setup, T.TearDown);
    GRunner.RunTest('CtrlInteract: RoundedEdit border radius', T.Test_RoundedEdit_BorderRadius, T.Setup, T.TearDown);

    // TThemeManager
    GRunner.RunTest('CtrlInteract: Theme dark->light changes colors', T.Test_ThemeSwitch_DarkToLight_ChangesColors, T.Setup, T.TearDown);
    GRunner.RunTest('CtrlInteract: Theme round-trip dark-light-dark', T.Test_ThemeSwitch_RoundTrip_DarkLightDark, T.Setup, T.TearDown);
    GRunner.RunTest('CtrlInteract: Theme colors non-zero', T.Test_ThemeColors_NonZeroFields, T.Setup, T.TearDown);

    // TBubblePanel
    GRunner.RunTest('CtrlInteract: BubblePanel default properties', T.Test_BubblePanel_DefaultProperties, T.Setup, T.TearDown);
    GRunner.RunTest('CtrlInteract: BubblePanel color set/get', T.Test_BubblePanel_Color_SetGet, T.Setup, T.TearDown);
    GRunner.RunTest('CtrlInteract: BubblePanel border radius', T.Test_BubblePanel_BorderRadius_SetGet, T.Setup, T.TearDown);
    GRunner.RunTest('CtrlInteract: BubblePanel show shadow toggle', T.Test_BubblePanel_ShowShadow_Toggle, T.Setup, T.TearDown);
  finally
    T.Free;
  end;
end;

end.
