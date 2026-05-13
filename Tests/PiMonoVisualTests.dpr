program PiMonoVisualTests;

{ Layer 3: Interactive Visual Test Gallery.
  Standalone executable that displays all UI components in various
  visual states for manual verification. No automated assertions -
  this is for human visual inspection. }

{$APPTYPE GUI}

uses
  System.SysUtils, System.UITypes, System.Types, System.Classes, System.Math,
  Winapi.Windows, Winapi.Messages,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls, Vcl.Clipbrd,
  UI.Spacing, UI.ThemeManager, UI.CustomButton, UI.ModernScrollbar,
  UI.ModernControls, UI.Animations, UI.ChatRenderer,
  Utils.SkiaDraw;

type
  TVisualTestGallery = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FThemeManager: TThemeManager;
    FScrollBox: TScrollBox;
    FCurrentY: Integer;

    function AddSection(const ATitle: string): TPanel;
    procedure AddLabel(AParent: TWinControl; const AText: string; ATop: Integer; ABold: Boolean = False);
    procedure AddSpacer(AParent: TWinControl; AHeight: Integer = 16);

    { Section builders }
    procedure BuildButtonStates(AParent: TWinControl);
    procedure BuildButtonStyles(AParent: TWinControl);
    procedure BuildPillTabs(AParent: TWinControl);
    procedure BuildBubblePanels(AParent: TWinControl);
    procedure BuildRoundedEdits(AParent: TWinControl);
    procedure BuildScrollbarDemo(AParent: TWinControl);
    procedure BuildAnimationDemo(AParent: TWinControl);
    procedure BuildThemeToggle(AParent: TWinControl);
    procedure BuildSkiaPrimitives(AParent: TWinControl);

    procedure OnThemeToggle(Sender: TObject);
    procedure OnAnimateFloat(Sender: TObject);
    procedure OnAnimateColor(Sender: TObject);
    procedure OnCancelAnimations(Sender: TObject);

    FAnimTargetPanel: TPanel;
    FAnimColorPanel: TPanel;
  end;

var
  GalleryForm: TVisualTestGallery;

{ TVisualTestGallery }

procedure TVisualTestGallery.FormCreate(Sender: TObject);
var
  ThemeSection, ButtonSection, StyleSection, TabSection,
  BubbleSection, EditSection, ScrollSection, AnimSection,
  SkiaSection: TPanel;
begin
  Caption := 'PiMono Visual Test Gallery';
  ClientWidth := 900;
  ClientHeight := 700;
  Position := poScreenCenter;

  FThemeManager := TThemeManager.Create;
  FThemeManager.ApplyTheme('Dark');

  Color := FThemeManager.Colors.Background;
  Font.Color := FThemeManager.Colors.Text;
  Font.Name := 'Segoe UI';
  Font.Size := 10;

  // Theme toggle at top
  ThemeSection := AddSection('Theme');
  BuildThemeToggle(ThemeSection);

  // Main scrollable area
  FScrollBox := TScrollBox.Create(Self);
  FScrollBox.Parent := Self;
  FScrollBox.Align := alClient;
  FScrollBox.BorderStyle := bsNone;
  FScrollBox.Color := FThemeManager.Colors.Background;
  FScrollBox.VertScrollBar.Tracking := True;

  FCurrentY := 0;

  // Button states
  ButtonSection := AddSection('TFlatButton States');
  BuildButtonStates(ButtonSection);

  // Button styles (via properties)
  StyleSection := AddSection('TFlatButton Variants');
  BuildButtonStyles(StyleSection);

  // Pill tabs
  TabSection := AddSection('Pill Tab Drawing');
  BuildPillTabs(TabSection);

  // Bubble panels
  BubbleSection := AddSection('Chat Bubble Panels');
  BuildBubblePanels(BubbleSection);

  // Rounded edits
  EditSection := AddSection('TRoundedEdit');
  BuildRoundedEdits(EditSection);

  // Scrollbar
  ScrollSection := AddSection('TModernScrollbar');
  BuildScrollbarDemo(ScrollSection);

  // Animation demo
  AnimSection := AddSection('Animation Demo');
  BuildAnimationDemo(AnimSection);

  // Skia primitives
  SkiaSection := AddSection('Skia Drawing Primitives');
  BuildSkiaPrimitives(SkiaSection);
end;

procedure TVisualTestGallery.FormDestroy(Sender: TObject);
begin
  CancelAllAnimations;
  FThemeManager.Free;
end;

function TVisualTestGallery.AddSection(const ATitle: string): TPanel;
var
  TitleLabel: TLabel;
  Section: TPanel;
begin
  Section := TPanel.Create(Self);
  Section.Parent := FScrollBox;
  Section.SetBounds(20, FCurrentY, FScrollBox.ClientWidth - 40, 40);
  Section.BevelOuter := bvNone;
  Section.ParentBackground := False;
  Section.Color := FThemeManager.Colors.Surface;
  Section.Caption := '';
  Section.Tag := FCurrentY; // remember top for later resize

  TitleLabel := TLabel.Create(Section);
  TitleLabel.Parent := Section;
  TitleLabel.Caption := ATitle;
  TitleLabel.Font.Size := 14;
  TitleLabel.Font.Style := [fsBold];
  TitleLabel.Font.Color := FThemeManager.Colors.Text;
  TitleLabel.Left := 16;
  TitleLabel.Top := 10;

  Inc(FCurrentY, 48);
  Result := Section;
end;

procedure TVisualTestGallery.AddLabel(AParent: TWinControl; const AText: string;
  ATop: Integer; ABold: Boolean);
var
  L: TLabel;
begin
  L := TLabel.Create(Self);
  L.Parent := AParent;
  L.Caption := AText;
  L.Font.Color := FThemeManager.Colors.Text;
  if ABold then
    L.Font.Style := [fsBold];
  L.Top := ATop;
  L.Left := 16;
  L.AutoSize := True;
end;

procedure TVisualTestGallery.AddSpacer(AParent: TWinControl; AHeight: Integer);
begin
  Inc(FCurrentY, AHeight);
end;

procedure TVisualTestGallery.BuildThemeToggle(AParent: TWinControl);
var
  BtnDark, BtnLight: TFlatButton;
begin
  BtnDark := TFlatButton.Create(Self);
  BtnDark.Parent := AParent;
  BtnDark.Caption := 'Dark';
  BtnDark.BgColor := $383838;
  BtnDark.HoverColor := $484848;
  BtnDark.TextColor := $E0E0E0;
  BtnDark.Width := 80;
  BtnDark.Height := 32;
  BtnDark.Left := 16;
  BtnDark.Top := 30;
  BtnDark.Tag := 0;
  BtnDark.OnClick := OnThemeToggle;

  BtnLight := TFlatButton.Create(Self);
  BtnLight.Parent := AParent;
  BtnLight.Caption := 'Light';
  BtnLight.BgColor := $D0D0D0;
  BtnLight.HoverColor := $E0E0E0;
  BtnLight.TextColor := $202020;
  BtnLight.Width := 80;
  BtnLight.Height := 32;
  BtnLight.Left := 104;
  BtnLight.Top := 30;
  BtnLight.Tag := 1;
  BtnLight.OnClick := OnThemeToggle;

  AParent.Height := 70;
  Inc(FCurrentY, 70);
end;

procedure TVisualTestGallery.OnThemeToggle(Sender: TObject);
begin
  if TComponent(Sender).Tag = 0 then
    FThemeManager.ApplyTheme('Dark')
  else
    FThemeManager.ApplyTheme('Light');

  Color := FThemeManager.Colors.Background;
  Font.Color := FThemeManager.Colors.Text;
  FScrollBox.Color := FThemeManager.Colors.Background;
  Invalidate;
end;

procedure TVisualTestGallery.BuildButtonStates(AParent: TWinControl);
var
  BtnNormal, BtnHover, BtnPressed, BtnDisabled, BtnShadow, BtnNoShadow: TFlatButton;
  Colors: TThemeColors;
  Top: Integer;
begin
  Colors := FThemeManager.Colors;
  Top := 40;
  AParent.Height := 100;

  // Normal
  BtnNormal := TFlatButton.Create(Self);
  BtnNormal.Parent := AParent;
  BtnNormal.Caption := 'Normal';
  BtnNormal.BgColor := Colors.ButtonBackground;
  BtnNormal.HoverColor := Colors.ButtonBackground;
  BtnNormal.PressedColor := Colors.ButtonBackground;
  BtnNormal.TextColor := Colors.ButtonText;
  BtnNormal.Width := 100;
  BtnNormal.Height := 32;
  BtnNormal.Left := 16;
  BtnNormal.Top := Top;
  BtnNormal.ShowShadow := False;

  // Hover (simulated by setting HoverColor = BgColor so it stays)
  BtnHover := TFlatButton.Create(Self);
  BtnHover.Parent := AParent;
  BtnHover.Caption := 'Hover';
  BtnHover.BgColor := Colors.ButtonHover;
  BtnHover.HoverColor := Colors.ButtonHover;
  BtnHover.PressedColor := Colors.ButtonHover;
  BtnHover.TextColor := Colors.ButtonText;
  BtnHover.Width := 100;
  BtnHover.Height := 32;
  BtnHover.Left := 126;
  BtnHover.Top := Top;
  BtnHover.ShowShadow := False;

  // Pressed
  BtnPressed := TFlatButton.Create(Self);
  BtnPressed.Parent := AParent;
  BtnPressed.Caption := 'Pressed';
  BtnPressed.BgColor := Colors.ButtonPressed;
  BtnPressed.HoverColor := Colors.ButtonPressed;
  BtnPressed.PressedColor := Colors.ButtonPressed;
  BtnPressed.TextColor := Colors.ButtonText;
  BtnPressed.Width := 100;
  BtnPressed.Height := 32;
  BtnPressed.Left := 236;
  BtnPressed.Top := Top;
  BtnPressed.ShowShadow := False;

  // Disabled
  BtnDisabled := TFlatButton.Create(Self);
  BtnDisabled.Parent := AParent;
  BtnDisabled.Caption := 'Disabled';
  BtnDisabled.BgColor := $303030;
  BtnDisabled.HoverColor := $303030;
  BtnDisabled.PressedColor := $303030;
  BtnDisabled.TextColor := $606060;
  BtnDisabled.Width := 100;
  BtnDisabled.Height := 32;
  BtnDisabled.Left := 346;
  BtnDisabled.Top := Top;
  BtnDisabled.Enabled := False;
  BtnDisabled.ShowShadow := False;

  // With Shadow
  BtnShadow := TFlatButton.Create(Self);
  BtnShadow.Parent := AParent;
  BtnShadow.Caption := 'Shadow';
  BtnShadow.BgColor := Colors.ButtonBackground;
  BtnShadow.HoverColor := Colors.ButtonHover;
  BtnShadow.TextColor := Colors.ButtonText;
  BtnShadow.Width := 100;
  BtnShadow.Height := 32;
  BtnShadow.Left := 456;
  BtnShadow.Top := Top;
  BtnShadow.ShowShadow := True;

  Inc(FCurrentY, 100);
end;

procedure TVisualTestGallery.BuildButtonStyles(AParent: TWinControl);
var
  Colors: TThemeColors;

  procedure MakeBtn(const ACaption: string; ABg, AHover, AText: TColor; ALeft: Integer);
  var
    Btn: TFlatButton;
  begin
    Btn := TFlatButton.Create(Self);
    Btn.Parent := AParent;
    Btn.Caption := ACaption;
    Btn.BgColor := ABg;
    Btn.HoverColor := AHover;
    Btn.PressedColor := ABg;
    Btn.TextColor := AText;
    Btn.Width := 100;
    Btn.Height := 32;
    Btn.Left := ALeft;
    Btn.Top := 40;
    Btn.ShowShadow := False;
  end;

begin
  Colors := FThemeManager.Colors;
  AParent.Height := 80;

  MakeBtn('Toolbar', Colors.ButtonBackground, Colors.ButtonHover, Colors.ButtonText, 16);
  MakeBtn('Accent', Colors.Accent, Colors.AccentHover, $FFFFFF, 126);
  MakeBtn('Danger', Colors.RejectBg, $F04040, $FFFFFF, 236);
  MakeBtn('Ghost', Colors.Background, Colors.Surface, Colors.TextSecondary, 346);

  // Gradient button
  var BtnGrad := TFlatButton.Create(Self);
  BtnGrad.Parent := AParent;
  BtnGrad.Caption := 'Gradient';
  BtnGrad.BgColor := Colors.Accent;
  BtnGrad.HoverColor := Colors.AccentHover;
  BtnGrad.GradientEnd := Colors.AccentHover;
  BtnGrad.TextColor := $FFFFFF;
  BtnGrad.Width := 100;
  BtnGrad.Height := 32;
  BtnGrad.Left := 456;
  BtnGrad.Top := 40;
  BtnGrad.ShowShadow := False;

  Inc(FCurrentY, 80);
end;

procedure TVisualTestGallery.BuildPillTabs(AParent: TWinControl);
var
  PB: TPaintBox;
  Colors: TThemeColors;

  procedure DrawPill(AX, AY, AW, AH: Integer; AColor: TColor; const AText: string);
  begin
    DrawSkiaRoundRect(PB.Canvas, Rect(AX, AY, AX + AW, AY + AH), 8, AColor);
    PB.Canvas.Brush.Style := bsClear;
    PB.Canvas.Font.Color := FThemeManager.Colors.Text;
    if AColor = Colors.Accent then
    begin
      PB.Canvas.Font.Color := $FFFFFF;
      PB.Canvas.Font.Style := [fsBold];
    end
    else
      PB.Canvas.Font.Style := [];
    DrawText(PB.Canvas.Handle, PChar(AText), -1,
      Rect(AX + 12, AY + 4, AX + AW - 12, AY + AH - 4),
      DT_CENTER or DT_VCENTER or DT_SINGLELINE);
  end;

begin
  Colors := FThemeManager.Colors;
  AParent.Height := 80;

  PB := TPaintBox.Create(Self);
  PB.Parent := AParent;
  PB.SetBounds(16, 30, AParent.Width - 32, 40);
  PB.Color := Colors.Background;

  PB.OnPaint := procedure(Sender: TObject)
  begin
    var P: TPaintBox := TPaintBox(Sender);
    P.Canvas.Brush.Color := Colors.Background;
    P.Canvas.FillRect(P.ClientRect);

    DrawPill(10, 4, 100, 32, Colors.Accent, 'Active');
    DrawPill(120, 4, 100, 32, Colors.Surface, 'Hover');
    DrawPill(230, 4, 100, 32, Colors.Background, 'Inactive');
  end;

  Inc(FCurrentY, 80);
end;

procedure TVisualTestGallery.BuildBubblePanels(AParent: TWinControl);
var
  Colors: TThemeColors;
  Top: Integer;

  procedure MakeBubble(const ALabel: string; AColor: TColor; ALeft: Integer;
    AShadow: Boolean; ABorderColor: TColor = clNone);
  var
    Bubble: TBubblePanel;
    Lbl: TLabel;
  begin
    Lbl := TLabel.Create(Self);
    Lbl.Parent := AParent;
    Lbl.Caption := ALabel;
    Lbl.Font.Color := Colors.TextSecondary;
    Lbl.Font.Size := 8;
    Lbl.Left := ALeft;
    Lbl.Top := 28;

    Bubble := TBubblePanel.Create(Self);
    Bubble.Parent := AParent;
    Bubble.Color := AColor;
    Bubble.ShowShadow := AShadow;
    Bubble.ShadowColor := $40000000;
    Bubble.BorderRadius := 14;
    Bubble.BorderColor := ABorderColor;
    Bubble.SetBounds(ALeft, Top, 180, 50);
    Bubble.Caption := ALabel;

    // Set text color on child label
    var ChildLbl := TLabel.Create(Self);
    ChildLbl.Parent := Bubble;
    ChildLbl.Caption := ALabel + ' message content';
    ChildLbl.Font.Color := Colors.Text;
    ChildLbl.Left := 12;
    ChildLbl.Top := 14;
  end;

begin
  Colors := FThemeManager.Colors;
  Top := 50;
  AParent.Height := 120;

  AddLabel(AParent, 'User (right-aligned):', 28, True);

  MakeBubble('User', Colors.UserMessage, 16, True, Colors.UserMessageBorder);
  MakeBubble('Assistant', Colors.AssistantMessage, 210, True);
  MakeBubble('Tool', Colors.ToolMessage, 404, False);
  MakeBubble('Error', Colors.ErrorMessage, 598, True);

  Inc(FCurrentY, 120);
end;

procedure TVisualTestGallery.BuildRoundedEdits(AParent: TWinControl);
var
  Edit1, Edit2: TRoundedEdit;
begin
  AParent.Height := 100;

  AddLabel(AParent, 'Focused:', 28, True);
  Edit1 := TRoundedEdit.Create(Self);
  Edit1.Parent := AParent;
  Edit1.Left := 80;
  Edit1.Top := 28;
  Edit1.Width := 250;
  Edit1.Text := 'Focused input';

  AddLabel(AParent, 'Unfocused:', 58, True);
  Edit2 := TRoundedEdit.Create(Self);
  Edit2.Parent := AParent;
  Edit2.Left := 80;
  Edit2.Top := 58;
  Edit2.Width := 250;
  Edit2.Text := 'Unfocused input';

  Inc(FCurrentY, 100);
end;

procedure TVisualTestGallery.BuildScrollbarDemo(AParent: TWinControl);
var
  InnerScrollBox: TScrollBox;
  SB: TModernScrollbar;
  Colors: TThemeColors;
  i: Integer;
  L: TLabel;
begin
  Colors := FThemeManager.Colors;
  AParent.Height := 200;

  InnerScrollBox := TScrollBox.Create(Self);
  InnerScrollBox.Parent := AParent;
  InnerScrollBox.SetBounds(16, 30, 200, 150);
  InnerScrollBox.BorderStyle := bsNone;
  InnerScrollBox.Color := Colors.Background;
  InnerScrollBox.VertScrollBar.Tracking := True;

  // Add content to make it scroll
  for i := 0 to 19 do
  begin
    L := TLabel.Create(Self);
    L.Parent := InnerScrollBox;
    L.Caption := 'Line ' + IntToStr(i + 1) + ' of scrollable content';
    L.Font.Color := Colors.Text;
    L.Left := 8;
    L.Top := 8 + i * 22;
  end;

  SB := TModernScrollbar.Create(Self);
  SB.AttachToScrollBox(InnerScrollBox, FThemeManager);

  // Description
  AddLabel(AParent, 'Scroll the content to see the modern scrollbar', 40);
  // Move to right of scrollbox
  var DescLabel := AParent.FindChildControl('') as TLabel; // won't find by name

  Inc(FCurrentY, 200);
end;

procedure TVisualTestGallery.BuildAnimationDemo(AParent: TWinControl);
var
  BtnFloat, BtnColor, BtnCancel: TFlatButton;
  Colors: TThemeColors;
begin
  Colors := FThemeManager.Colors;
  AParent.Height := 100;

  // Animation target panel
  FAnimTargetPanel := TPanel.Create(Self);
  FAnimTargetPanel.Parent := AParent;
  FAnimTargetPanel.SetBounds(16, 60, 100, 24);
  FAnimTargetPanel.Color := Colors.Accent;
  FAnimTargetPanel.BevelOuter := bvNone;

  FAnimColorPanel := TPanel.Create(Self);
  FAnimColorPanel.Parent := AParent;
  FAnimColorPanel.SetBounds(16, 60, 0, 0); // hidden initially
  FAnimColorPanel.Color := Colors.Accent;

  BtnFloat := TFlatButton.Create(Self);
  BtnFloat.Parent := AParent;
  BtnFloat.Caption := 'Animate Width';
  BtnFloat.BgColor := Colors.ButtonBackground;
  BtnFloat.HoverColor := Colors.ButtonHover;
  BtnFloat.TextColor := Colors.ButtonText;
  BtnFloat.Width := 120;
  BtnFloat.Height := 28;
  BtnFloat.Left := 16;
  BtnFloat.Top := 28;
  BtnFloat.OnClick := OnAnimateFloat;

  BtnColor := TFlatButton.Create(Self);
  BtnColor.Parent := AParent;
  BtnColor.Caption := 'Animate Color';
  BtnColor.BgColor := Colors.ButtonBackground;
  BtnColor.HoverColor := Colors.ButtonHover;
  BtnColor.TextColor := Colors.ButtonText;
  BtnColor.Width := 120;
  BtnColor.Height := 28;
  BtnColor.Left := 146;
  BtnColor.Top := 28;
  BtnColor.OnClick := OnAnimateColor;

  BtnCancel := TFlatButton.Create(Self);
  BtnCancel.Parent := AParent;
  BtnCancel.Caption := 'Cancel All';
  BtnCancel.BgColor := Colors.RejectBg;
  BtnCancel.HoverColor := $F04040;
  BtnCancel.TextColor := $FFFFFF;
  BtnCancel.Width := 100;
  BtnCancel.Height := 28;
  BtnCancel.Left := 276;
  BtnCancel.Top := 28;
  BtnCancel.OnClick := OnCancelAnimations;

  Inc(FCurrentY, 100);
end;

procedure TVisualTestGallery.OnAnimateFloat(Sender: TObject);
begin
  if FAnimTargetPanel <> nil then
  begin
    FAnimTargetPanel.Width := 100; // reset
    AnimateFloat(FAnimTargetPanel, 'Width', 400, 300, aeCubic);
  end;
end;

procedure TVisualTestGallery.OnAnimateColor(Sender: TObject);
begin
  if FAnimTargetPanel <> nil then
  begin
    var Colors := FThemeManager.Colors;
    AnimateColor(FAnimTargetPanel, 'Color', Colors.RejectBg, 500, aeQuad);
  end;
end;

procedure TVisualTestGallery.OnCancelAnimations(Sender: TObject);
begin
  CancelAllAnimations;
end;

procedure TVisualTestGallery.BuildSkiaPrimitives(AParent: TWinControl);
var
  PB: TPaintBox;
  Colors: TThemeColors;
begin
  Colors := FThemeManager.Colors;
  AParent.Height := 200;

  PB := TPaintBox.Create(Self);
  PB.Parent := AParent;
  PB.SetBounds(16, 30, AParent.Width - 32, 160);

  PB.OnPaint := procedure(Sender: TObject)
  begin
    var P: TPaintBox := TPaintBox(Sender);
    P.Canvas.Brush.Color := Colors.Background;
    P.Canvas.FillRect(P.ClientRect);

    // Solid round rect
    DrawSkiaRoundRect(P.Canvas, Rect(10, 10, 110, 60), 10, Colors.Accent);

    // Gradient round rect
    DrawSkiaGradientRoundRect(P.Canvas, Rect(120, 10, 220, 60), 10,
      Colors.Accent, Colors.RejectBg);

    // With shadow
    DrawSkiaRoundRectWithShadow(P.Canvas, Rect(230, 10, 330, 60), 10,
      Colors.Surface, $40000000, 6, 0, 2, Colors.Border, 1.0);

    // Shadow level 1
    DrawSkiaRoundRectWithShadowLevel(P.Canvas, Rect(10, 80, 110, 130), 8,
      Colors.InputBackground, $40000000, SHADOW_1, Colors.Border, 1.0);

    // Shadow level 2
    DrawSkiaRoundRectWithShadowLevel(P.Canvas, Rect(120, 80, 220, 130), 8,
      Colors.InputBackground, $40000000, SHADOW_2, Colors.Border, 1.0);

    // Shadow level 3
    DrawSkiaRoundRectWithShadowLevel(P.Canvas, Rect(230, 80, 330, 130), 8,
      Colors.InputBackground, $40000000, SHADOW_3, Colors.Border, 1.0);

    // Large radius (circular)
    DrawSkiaRoundRect(P.Canvas, Rect(350, 10, 410, 70), 30, Colors.Accent);

    // Border only (no fill) - use transparent-ish fill
    DrawSkiaRoundRect(P.Canvas, Rect(350, 80, 410, 130), 10,
      Colors.Background, Colors.Accent, 2.0);

    // Labels
    P.Canvas.Font.Size := 8;
    P.Canvas.Font.Color := Colors.TextSecondary;
    P.Canvas.Brush.Style := bsClear;
    P.Canvas.TextOut(10, 62, 'Solid');
    P.Canvas.TextOut(120, 62, 'Gradient');
    P.Canvas.TextOut(230, 62, 'Shadow+Border');
    P.Canvas.TextOut(10, 134, 'SHADOW_1');
    P.Canvas.TextOut(120, 134, 'SHADOW_2');
    P.Canvas.TextOut(230, 134, 'SHADOW_3');
  end;

  Inc(FCurrentY, 200);
end;

{ Main }

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TVisualTestGallery, GalleryForm);
  Application.Run;
end.
