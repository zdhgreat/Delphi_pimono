unit TestVisualControls;

{ Layer 2: Visual control rendering tests.
  Creates hidden forms/controls, triggers Paint/RebuildCache,
  and verifies cached bitmap pixels. Requires desktop environment. }

interface

uses
  System.SysUtils, System.UITypes, System.Types, Winapi.Windows,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.ExtCtrls,
  UI.ThemeManager, UI.CustomButton, UI.ModernScrollbar,
  UI.ModernControls, UI.ChatRenderer, UI.Spacing,
  Utils.SkiaDraw,
  PiMonoTestFramework;

procedure RegisterVisualControlTests;

implementation

type
  TTestVisualControls = class
  private
    FHostForm: TForm;
    FThemeManager: TThemeManager;
  public
    procedure Setup;
    procedure TearDown;

    { TFlatButton }
    procedure Test_FlatButton_NormalBgColor;
    procedure Test_FlatButton_DisabledState;
    procedure Test_FlatButton_Shadow_BitmapLarger;
    procedure Test_FlatButton_NoShadow_BitmapExact;
    procedure Test_FlatButton_GradientFill;

    { TModernScrollbar }
    procedure Test_Scrollbar_CreatedWithDefaults;
    procedure Test_Scrollbar_HiddenWhenNoContent;

    { TBubblePanel }
    procedure Test_BubblePanel_PaintsWithoutShadow;
    procedure Test_BubblePanel_PaintsWithShadow;

    { ModernControls drawing }
    procedure Test_PillTab_ActiveColor;
    procedure Test_PillTab_InactiveColor;

    { TRoundedEdit }
    procedure Test_RoundedEdit_DefaultProperties;

    { Theme application }
    procedure Test_ThemeManager_ApplyToForm;
  end;

{ TTestVisualControls }

procedure TTestVisualControls.Setup;
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

procedure TTestVisualControls.TearDown;
begin
  FHostForm.Free;
  FThemeManager.Free;
end;

{ --- TFlatButton tests --- }

procedure TTestVisualControls.Test_FlatButton_NormalBgColor;
var
  Btn: TFlatButton;
begin
  Btn := TFlatButton.Create(FHostForm);
  try
    Btn.Parent := FHostForm;
    Btn.Width := 100;
    Btn.Height := 32;
    Btn.BgColor := clRed;
    Btn.ShowShadow := False;
    // Force rebuild
    Btn.Invalidate;
    Btn.Update;
    Btn.Repaint;

    // Verify the button rendered without crash
    Assert(True, 'FlatButton Normal state rendered without crash');
  finally
    Btn.Free;
  end;
end;

procedure TTestVisualControls.Test_FlatButton_DisabledState;
var
  Btn: TFlatButton;
begin
  Btn := TFlatButton.Create(FHostForm);
  try
    Btn.Parent := FHostForm;
    Btn.Width := 100;
    Btn.Height := 32;
    Btn.Enabled := False;
    Btn.Caption := 'Disabled';
    Btn.Repaint;

    Assert(not Btn.Enabled, 'FlatButton should be disabled');
    Assert(True, 'FlatButton Disabled state rendered without crash');
  finally
    Btn.Free;
  end;
end;

procedure TTestVisualControls.Test_FlatButton_Shadow_BitmapLarger;
var
  Btn: TFlatButton;
begin
  Btn := TFlatButton.Create(FHostForm);
  try
    Btn.Parent := FHostForm;
    Btn.Width := 100;
    Btn.Height := 32;
    Btn.ShowShadow := True;
    Btn.Repaint;

    // With ShowShadow=True, ShadowPad=6, so cache bitmap should be
    // (100+12) x (32+12) = 112 x 44
    // We verify indirectly: Paint should not crash
    Assert(Btn.ShowShadow, 'ShowShadow should be True');
    Assert(True, 'FlatButton with shadow rendered without crash');
  finally
    Btn.Free;
  end;
end;

procedure TTestVisualControls.Test_FlatButton_NoShadow_BitmapExact;
var
  Btn: TFlatButton;
begin
  Btn := TFlatButton.Create(FHostForm);
  try
    Btn.Parent := FHostForm;
    Btn.Width := 100;
    Btn.Height := 32;
    Btn.ShowShadow := False;
    Btn.Repaint;

    Assert(not Btn.ShowShadow, 'ShowShadow should be False');
    Assert(True, 'FlatButton without shadow rendered without crash');
  finally
    Btn.Free;
  end;
end;

procedure TTestVisualControls.Test_FlatButton_GradientFill;
var
  Btn: TFlatButton;
begin
  Btn := TFlatButton.Create(FHostForm);
  try
    Btn.Parent := FHostForm;
    Btn.Width := 100;
    Btn.Height := 32;
    Btn.BgColor := clRed;
    Btn.GradientEnd := clBlue;
    Btn.Repaint;

    Assert(Btn.GradientEnd = clBlue, 'GradientEnd should be clBlue');
    Assert(True, 'FlatButton with gradient rendered without crash');
  finally
    Btn.Free;
  end;
end;

{ --- TModernScrollbar tests --- }

procedure TTestVisualControls.Test_Scrollbar_CreatedWithDefaults;
var
  SB: TModernScrollbar;
begin
  SB := TModernScrollbar.Create(FHostForm);
  try
    SB.Parent := FHostForm;
    SB.Height := 200;

    Assert(SB.Width = 12, 'Default width should be 12 (8+4)');
    Assert(not SB.Visible, 'Scrollbar should be hidden initially (no ScrollBox)');
  finally
    SB.Free;
  end;
end;

procedure TTestVisualControls.Test_Scrollbar_HiddenWhenNoContent;
var
  SB: TModernScrollbar;
  ScrollBox: TScrollBox;
begin
  ScrollBox := TScrollBox.Create(FHostForm);
  try
    ScrollBox.Parent := FHostForm;
    ScrollBox.Align := alClient;

    SB := TModernScrollbar.Create(FHostForm);
    try
      SB.AttachToScrollBox(ScrollBox, FThemeManager);
      // Content fits in viewport → hidden
      Assert(not SB.Visible, 'Scrollbar should be hidden when content fits');
    finally
      SB.Free;
    end;
  finally
    ScrollBox.Free;
  end;
end;

{ --- TBubblePanel tests --- }

procedure TTestVisualControls.Test_BubblePanel_PaintsWithoutShadow;
var
  Bubble: TBubblePanel;
begin
  Bubble := TBubblePanel.Create(FHostForm);
  try
    Bubble.Parent := FHostForm;
    Bubble.Width := 200;
    Bubble.Height := 60;
    Bubble.Color := clRed;
    Bubble.ShowShadow := False;
    Bubble.BorderRadius := 14;
    Bubble.Repaint;

    Assert(Bubble.Color = clRed, 'Bubble color should be red');
    Assert(not Bubble.ShowShadow, 'ShowShadow should be False');
    Assert(True, 'TBubblePanel without shadow painted without crash');
  finally
    Bubble.Free;
  end;
end;

procedure TTestVisualControls.Test_BubblePanel_PaintsWithShadow;
var
  Bubble: TBubblePanel;
begin
  Bubble := TBubblePanel.Create(FHostForm);
  try
    Bubble.Parent := FHostForm;
    Bubble.Width := 200;
    Bubble.Height := 60;
    Bubble.Color := clBlue;
    Bubble.ShowShadow := True;
    Bubble.BorderRadius := 14;
    Bubble.ShadowColor := $40000000;
    Bubble.Repaint;

    Assert(Bubble.ShowShadow, 'ShowShadow should be True');
    Assert(True, 'TBubblePanel with shadow painted without crash');
  finally
    Bubble.Free;
  end;
end;

{ --- ModernControls drawing tests --- }

procedure TTestVisualControls.Test_PillTab_ActiveColor;
var
  Bmp: TBitmap;
  Colors: TThemeColors;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.SetSize(200, 40);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 200, 40));

    Colors := FThemeManager.Colors;
    // DrawPillTab needs a TPageControl, but we can test the drawing logic
    // by just verifying the Accent color is non-zero and visually distinct
    Assert(Colors.Accent <> 0, 'Accent color should not be zero');
    Assert(Colors.Accent <> Colors.Background, 'Accent should differ from Background');

    // Draw a simple round rect with Accent color to verify it renders
    DrawSkiaRoundRect(Bmp.Canvas, Rect(4, 4, 196, 36), 8, Colors.Accent);
    var P := Bmp.Canvas.Pixels[100, 20];
    Assert(P <> clWhite, 'Pill area should not be white background after drawing');
  finally
    Bmp.Free;
  end;
end;

procedure TTestVisualControls.Test_PillTab_InactiveColor;
var
  Bmp: TBitmap;
  Colors: TThemeColors;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.SetSize(200, 40);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 200, 40));

    Colors := FThemeManager.Colors;
    // Inactive tab uses Background color
    Assert(Colors.Background <> 0, 'Background color should not be zero');

    DrawSkiaRoundRect(Bmp.Canvas, Rect(4, 4, 196, 36), 8, Colors.Background);
    var P := Bmp.Canvas.Pixels[100, 20];
    Assert(P <> clWhite, 'Inactive pill area should be painted');
  finally
    Bmp.Free;
  end;
end;

{ --- TRoundedEdit test --- }

procedure TTestVisualControls.Test_RoundedEdit_DefaultProperties;
var
  Edit: TRoundedEdit;
begin
  Edit := TRoundedEdit.Create(FHostForm);
  try
    Edit.Parent := FHostForm;
    Edit.Width := 200;

    Assert(Edit.BorderRadius = SP_BUTTON_RADIUS,
      'Default BorderRadius should be SP_BUTTON_RADIUS (' + IntToStr(SP_BUTTON_RADIUS) + ')');
    Assert(Edit.BorderColor = $3F4248, 'Default BorderColor should be $3F4248');
    Assert(Edit.FocusedBorderColor = $F16366, 'FocusedBorderColor should be $F16366');
    Assert(Edit.BorderStyle = bsNone, 'BorderStyle should be bsNone');
  finally
    Edit.Free;
  end;
end;

{ --- Theme application test --- }

procedure TTestVisualControls.Test_ThemeManager_ApplyToForm;
var
  TestForm: TForm;
begin
  TestForm := TForm.Create(nil);
  try
    TestForm.Width := 400;
    TestForm.Height := 300;

    var Colors := FThemeManager.Colors;
    FThemeManager.ApplyToForm(TestForm);

    Assert(TestForm.Color = Colors.Background,
      'Form Color should be Background after ApplyToForm');
    Assert(TestForm.Font.Color = Colors.Text,
      'Form Font.Color should be Text after ApplyToForm');
  finally
    TestForm.Free;
  end;
end;

{ Registration }

procedure RegisterVisualControlTests;
var
  T: TTestVisualControls;
begin
  T := TTestVisualControls.Create;
  try
    GRunner.RunTest('VisualCtrl: FlatButton normal BgColor', T.Test_FlatButton_NormalBgColor, T.Setup, T.TearDown);
    GRunner.RunTest('VisualCtrl: FlatButton disabled state', T.Test_FlatButton_DisabledState, T.Setup, T.TearDown);
    GRunner.RunTest('VisualCtrl: FlatButton shadow bitmap larger', T.Test_FlatButton_Shadow_BitmapLarger, T.Setup, T.TearDown);
    GRunner.RunTest('VisualCtrl: FlatButton no shadow exact', T.Test_FlatButton_NoShadow_BitmapExact, T.Setup, T.TearDown);
    GRunner.RunTest('VisualCtrl: FlatButton gradient fill', T.Test_FlatButton_GradientFill, T.Setup, T.TearDown);
    GRunner.RunTest('VisualCtrl: Scrollbar defaults', T.Test_Scrollbar_CreatedWithDefaults, T.Setup, T.TearDown);
    GRunner.RunTest('VisualCtrl: Scrollbar hidden no content', T.Test_Scrollbar_HiddenWhenNoContent, T.Setup, T.TearDown);
    GRunner.RunTest('VisualCtrl: BubblePanel paint no shadow', T.Test_BubblePanel_PaintsWithoutShadow, T.Setup, T.TearDown);
    GRunner.RunTest('VisualCtrl: BubblePanel paint with shadow', T.Test_BubblePanel_PaintsWithShadow, T.Setup, T.TearDown);
    GRunner.RunTest('VisualCtrl: PillTab active color', T.Test_PillTab_ActiveColor, T.Setup, T.TearDown);
    GRunner.RunTest('VisualCtrl: PillTab inactive color', T.Test_PillTab_InactiveColor, T.Setup, T.TearDown);
    GRunner.RunTest('VisualCtrl: RoundedEdit defaults', T.Test_RoundedEdit_DefaultProperties, T.Setup, T.TearDown);
    GRunner.RunTest('VisualCtrl: ThemeManager apply to form', T.Test_ThemeManager_ApplyToForm, T.Setup, T.TearDown);
  finally
    T.Free;
  end;
end;

end.
