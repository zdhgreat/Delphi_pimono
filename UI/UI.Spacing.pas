unit UI.Spacing;

{ Unified spacing system for PiMono UI.
  All layout dimensions should reference these constants
  instead of hardcoded pixel values. }

interface

const
  // --- 8-level spacing scale ---
  SP_NONE  = 0;
  SP_XS    = 4;
  SP_S     = 8;
  SP_M     = 12;
  SP_L     = 16;
  SP_XL    = 20;
  SP_XXL   = 28;
  SP_XXXL  = 40;

  // --- Layout constants ---
  SP_TOOLBAR_HEIGHT    = 48;
  SP_SIDEBAR_WIDTH     = 220;
  SP_STATUSBAR_HEIGHT  = 28;
  SP_INPUT_MIN_HEIGHT  = 72;
  SP_SPLITTER_HEIGHT   = 4;

  // --- Corner radii ---
  SP_BUBBLE_RADIUS     = 14;
  SP_CARD_RADIUS       = 10;
  SP_CODE_RADIUS       = 8;
  SP_BUTTON_RADIUS     = 6;
  SP_TAG_RADIUS        = 4;
  SP_SEND_BUTTON_RADIUS = 18;

  // --- Icon sizes ---
  SP_ICON_SIZE         = 20;
  SP_ICON_SIZE_SMALL   = 16;
  SP_ROLE_ICON_SIZE    = 28;
  SP_WELCOME_LOGO_SIZE = 48;

  // --- Chat layout ---
  SP_CHAT_MAX_WIDTH    = 860;
  SP_MESSAGE_SPACING   = 20;
  SP_MESSAGE_SPACING_SAME_ROLE = 12;
  SP_BUBBLE_PADDING_H  = 14;
  SP_BUBBLE_PADDING_V  = 12;
  SP_SIDE_MARGIN       = 20;
  SP_ROLE_ICON_GAP     = 10;

  // --- Button sizes ---
  SP_TOOLBAR_BTN_W     = 36;
  SP_TOOLBAR_BTN_H     = 32;
  SP_SEND_BTN_SIZE     = 36;
  SP_STOP_BTN_W        = 80;
  SP_STOP_BTN_H        = 24;
  SP_NEWCHAT_BTN_H     = 38;
  SP_SKILL_BTN_H       = 28;
  SP_SEARCH_BTN_W      = 28;
  SP_SEARCH_BTN_H      = 24;

  // --- Settings form ---
  SP_SETTINGS_ROW_GAP  = 46;
  SP_SETTINGS_LABEL_EDIT_GAP = 20;
  SP_SETTINGS_CHECKBOX_GAP = 30;
  SP_SETTINGS_FIELD_LEFT = 16;
  SP_SETTINGS_BTN_W    = 80;
  SP_SETTINGS_BTN_H    = 28;

implementation

end.
