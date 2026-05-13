unit TestSpacing;

{ Tests for UI.Spacing constants }

interface

uses
  System.SysUtils,
  UI.Spacing,
  PiMonoTestFramework;

procedure RegisterSpacingTests;

implementation

type
  TTestSpacing = class
  public
    procedure Test_SpacingScale;
    procedure Test_LayoutConstants;
    procedure Test_CornerRadii;
    procedure Test_IconSizes;
    procedure Test_ChatLayout;
    procedure Test_ButtonSizes;
    procedure Test_SettingsForm;
  end;

{ TTestSpacing }

procedure TTestSpacing.Test_SpacingScale;
begin
  Assert(SP_NONE  = 0,  'SP_NONE should be 0');
  Assert(SP_XS    = 4,  'SP_XS should be 4');
  Assert(SP_S     = 8,  'SP_S should be 8');
  Assert(SP_M     = 12, 'SP_M should be 12');
  Assert(SP_L     = 16, 'SP_L should be 16');
  Assert(SP_XL    = 20, 'SP_XL should be 20');
  Assert(SP_XXL   = 28, 'SP_XXL should be 28');
  Assert(SP_XXXL  = 40, 'SP_XXXL should be 40');
  // Scale is monotonically increasing
  Assert(SP_NONE < SP_XS, 'SP_NONE < SP_XS');
  Assert(SP_XS < SP_S, 'SP_XS < SP_S');
  Assert(SP_S < SP_M, 'SP_S < SP_M');
  Assert(SP_M < SP_L, 'SP_M < SP_L');
  Assert(SP_L < SP_XL, 'SP_L < SP_XL');
  Assert(SP_XL < SP_XXL, 'SP_XL < SP_XXL');
  Assert(SP_XXL < SP_XXXL, 'SP_XXL < SP_XXXL');
end;

procedure TTestSpacing.Test_LayoutConstants;
begin
  Assert(SP_TOOLBAR_HEIGHT   = 48, 'SP_TOOLBAR_HEIGHT should be 48');
  Assert(SP_SIDEBAR_WIDTH    = 220, 'SP_SIDEBAR_WIDTH should be 220');
  Assert(SP_STATUSBAR_HEIGHT = 28, 'SP_STATUSBAR_HEIGHT should be 28');
  Assert(SP_INPUT_MIN_HEIGHT = 72, 'SP_INPUT_MIN_HEIGHT should be 72');
  Assert(SP_SPLITTER_HEIGHT  = 4, 'SP_SPLITTER_HEIGHT should be 4');
end;

procedure TTestSpacing.Test_CornerRadii;
begin
  Assert(SP_BUBBLE_RADIUS      = 14, 'SP_BUBBLE_RADIUS should be 14');
  Assert(SP_CARD_RADIUS        = 10, 'SP_CARD_RADIUS should be 10');
  Assert(SP_CODE_RADIUS        = 8, 'SP_CODE_RADIUS should be 8');
  Assert(SP_BUTTON_RADIUS      = 6, 'SP_BUTTON_RADIUS should be 6');
  Assert(SP_TAG_RADIUS         = 4, 'SP_TAG_RADIUS should be 4');
  Assert(SP_SEND_BUTTON_RADIUS = 18, 'SP_SEND_BUTTON_RADIUS should be 18');
  // Radii are reasonable (1..100)
  Assert((SP_BUBBLE_RADIUS > 0) and (SP_BUBBLE_RADIUS < 100), 'BUBBLE_RADIUS in range');
  Assert((SP_SEND_BUTTON_RADIUS > 0) and (SP_SEND_BUTTON_RADIUS < 100), 'SEND_BUTTON_RADIUS in range');
end;

procedure TTestSpacing.Test_IconSizes;
begin
  Assert(SP_ICON_SIZE       = 20, 'SP_ICON_SIZE should be 20');
  Assert(SP_ICON_SIZE_SMALL = 16, 'SP_ICON_SIZE_SMALL should be 16');
  Assert(SP_ROLE_ICON_SIZE  = 28, 'SP_ROLE_ICON_SIZE should be 28');
  Assert(SP_WELCOME_LOGO_SIZE = 48, 'SP_WELCOME_LOGO_SIZE should be 48');
  // Small < Normal < Role < Logo
  Assert(SP_ICON_SIZE_SMALL < SP_ICON_SIZE, 'SMALL < ICON_SIZE');
  Assert(SP_ICON_SIZE < SP_ROLE_ICON_SIZE, 'ICON_SIZE < ROLE_ICON_SIZE');
  Assert(SP_ROLE_ICON_SIZE < SP_WELCOME_LOGO_SIZE, 'ROLE_ICON_SIZE < LOGO_SIZE');
end;

procedure TTestSpacing.Test_ChatLayout;
begin
  Assert(SP_CHAT_MAX_WIDTH  = 860, 'SP_CHAT_MAX_WIDTH should be 860');
  Assert(SP_MESSAGE_SPACING = 20, 'SP_MESSAGE_SPACING should be 20');
  Assert(SP_MESSAGE_SPACING_SAME_ROLE = 12, 'SP_MESSAGE_SPACING_SAME_ROLE should be 12');
  Assert(SP_BUBBLE_PADDING_H = 14, 'SP_BUBBLE_PADDING_H should be 14');
  Assert(SP_BUBBLE_PADDING_V = 12, 'SP_BUBBLE_PADDING_V should be 12');
  Assert(SP_SIDE_MARGIN     = 20, 'SP_SIDE_MARGIN should be 20');
  Assert(SP_ROLE_ICON_GAP   = 10, 'SP_ROLE_ICON_GAP should be 10');
  // Same role spacing is tighter
  Assert(SP_MESSAGE_SPACING_SAME_ROLE < SP_MESSAGE_SPACING,
    'SAME_ROLE spacing should be less than normal spacing');
end;

procedure TTestSpacing.Test_ButtonSizes;
begin
  Assert(SP_TOOLBAR_BTN_W = 36, 'SP_TOOLBAR_BTN_W should be 36');
  Assert(SP_TOOLBAR_BTN_H = 32, 'SP_TOOLBAR_BTN_H should be 32');
  Assert(SP_SEND_BTN_SIZE = 36, 'SP_SEND_BTN_SIZE should be 36');
  Assert(SP_STOP_BTN_W   = 80, 'SP_STOP_BTN_W should be 80');
  Assert(SP_STOP_BTN_H   = 24, 'SP_STOP_BTN_H should be 24');
  Assert(SP_NEWCHAT_BTN_H = 38, 'SP_NEWCHAT_BTN_H should be 38');
  Assert(SP_SKILL_BTN_H  = 28, 'SP_SKILL_BTN_H should be 28');
  Assert(SP_SEARCH_BTN_W = 28, 'SP_SEARCH_BTN_W should be 28');
  Assert(SP_SEARCH_BTN_H = 24, 'SP_SEARCH_BTN_H should be 24');
  // Width >= Height for most buttons
  Assert(SP_TOOLBAR_BTN_W >= SP_TOOLBAR_BTN_H, 'Toolbar btn W >= H');
  Assert(SP_STOP_BTN_W >= SP_STOP_BTN_H, 'Stop btn W >= H');
end;

procedure TTestSpacing.Test_SettingsForm;
begin
  Assert(SP_SETTINGS_ROW_GAP        = 46, 'SP_SETTINGS_ROW_GAP should be 46');
  Assert(SP_SETTINGS_LABEL_EDIT_GAP = 20, 'SP_SETTINGS_LABEL_EDIT_GAP should be 20');
  Assert(SP_SETTINGS_CHECKBOX_GAP   = 30, 'SP_SETTINGS_CHECKBOX_GAP should be 30');
  Assert(SP_SETTINGS_FIELD_LEFT     = 16, 'SP_SETTINGS_FIELD_LEFT should be 16');
  Assert(SP_SETTINGS_BTN_W          = 80, 'SP_SETTINGS_BTN_W should be 80');
  Assert(SP_SETTINGS_BTN_H          = 28, 'SP_SETTINGS_BTN_H should be 28');
end;

{ Registration }

procedure RegisterSpacingTests;
var
  T: TTestSpacing;
begin
  T := TTestSpacing.Create;
  try
    GRunner.RunTest('Spacing: Scale values', T.Test_SpacingScale);
    GRunner.RunTest('Spacing: Layout constants', T.Test_LayoutConstants);
    GRunner.RunTest('Spacing: Corner radii', T.Test_CornerRadii);
    GRunner.RunTest('Spacing: Icon sizes', T.Test_IconSizes);
    GRunner.RunTest('Spacing: Chat layout', T.Test_ChatLayout);
    GRunner.RunTest('Spacing: Button sizes', T.Test_ButtonSizes);
    GRunner.RunTest('Spacing: Settings form', T.Test_SettingsForm);
  finally
    T.Free;
  end;
end;

end.
