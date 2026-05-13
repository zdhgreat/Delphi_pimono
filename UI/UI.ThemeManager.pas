unit UI.ThemeManager;

interface

uses
  System.SysUtils, System.Classes, Vcl.Graphics, Vcl.Controls, Vcl.Forms,
  Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ExtCtrls,
  Winapi.Windows;

type
  TThemeColors = record
    Background: TColor;
    Surface: TColor;
    Text: TColor;
    TextSecondary: TColor;
    Accent: TColor;
    Border: TColor;
    InputBackground: TColor;
    UserMessage: TColor;
    UserMessageBorder: TColor;
    AssistantMessage: TColor;
    AssistantMessageBorder: TColor;
    ErrorMessage: TColor;
    ErrorMessageBorder: TColor;
    ToolMessage: TColor;
    ToolMessageBorder: TColor;
    ButtonBackground: TColor;
    ButtonText: TColor;
    ButtonHover: TColor;
    ButtonPressed: TColor;
    AccentHover: TColor;
    StatusBar: TColor;
    StatusBarText: TColor;
    // Diff display
    DiffAdded: TColor;
    DiffRemoved: TColor;
    DiffContext: TColor;
    // Warning / confirmation
    WarningColor: TColor;
    ApproveBg: TColor;
    RejectBg: TColor;
    // Branch / tree navigation
    BranchIndicator: TColor;
    LeafIndicator: TColor;
    TreeConnector: TColor;
    // Suggestion cards
    SuggestionBg: TColor;
    SuggestionBorder: TColor;
    SuggestionHover: TColor;
    // Input card
    InputCardBg: TColor;
    InputCardBorder: TColor;
    // Markdown / code rendering
    CodeBlockBg: TColor;
    CodeBlockBorder: TColor;
    CodeBlockText: TColor;
    InlineCodeText: TColor;
    HeaderColor: TColor;
    LinkColor: TColor;
    QuoteColor: TColor;
    BoldColor: TColor;
    // Syntax highlighting
    CodeKeywordColor: TColor;
    CodeStringColor: TColor;
    CodeCommentColor: TColor;
    CodeNumberColor: TColor;
    // Gradient / shadow effects
    AccentGradientEnd: TColor;
    ButtonShadow: TColor;
    BubbleShadow: TColor;
    SidebarActiveBg: TColor;
    InputFocusBorder: TColor;
    AccentGradientEndHover: TColor;
    // Role icon colors (chatgpt-main inspired)
    UserIconColor: TColor;
    AssistantIconColor: TColor;
    ToolIconColor: TColor;
    ErrorIconColor: TColor;
    SystemIconColor: TColor;
    // Layout constants (spacing & sizing) — prefer UI.Spacing constants for new code
    MaxChatWidth: Integer;     // DEPRECATED: use SP_CHAT_MAX_WIDTH from UI.Spacing
    MessageSpacing: Integer;   // DEPRECATED: use SP_MESSAGE_SPACING from UI.Spacing
    RoleIconSize: Integer;     // role indicator square size
    BubblePadding: Integer;    // inner padding of message bubbles
    SideMargin: Integer;       // minimum margin from chat edges
  end;

  TThemeManager = class
  private
    FCurrentTheme: string;
    FColors: TThemeColors;
    procedure SetDarkTheme;
    procedure SetLightTheme;
  public
    constructor Create;
    procedure ApplyTheme(const AThemeName: string);
    procedure ApplyToForm(AForm: TForm);
    procedure ApplyToRichEdit(AEdit: TCustomMemo);
    procedure ApplyToPanel(APanel: TPanel);
    procedure ApplyToStatusBar(AStatusBar: TStatusBar);
    procedure ApplyToStandardForm(AForm: TForm);
    procedure ApplyDarkScrollbar(AHandle: HWND);
    procedure ApplyDarkComboBox(AComboBox: TComboBox);
    function GetCurrentTheme: string;
    function GetColors: TThemeColors;
    property Theme: string read FCurrentTheme;
    property Colors: TThemeColors read FColors;
  end;

implementation

const
  CB_GETCOMBOBOXINFO = $0164;

type
  TControlAccess = class(TControl);

{ TThemeManager }

constructor TThemeManager.Create;
begin
  inherited Create;
  ApplyTheme('Dark');
end;

procedure TThemeManager.ApplyTheme(const AThemeName: string);
begin
  FCurrentTheme := AThemeName;
  if SameText(AThemeName, 'Dark') then
    SetDarkTheme
  else
    SetLightTheme;
end;

procedure TThemeManager.SetDarkTheme;
begin
  // Background layers - warm-tinted hierarchy (subtle blue undertone)
  FColors.Background := $1A1B1E;       // Deepest - chat area bg
  FColors.Surface := $2B2D31;          // Panels, sidebar, toolbar
  FColors.Border := $3F4248;           // Visible separator lines
  FColors.InputBackground := $1E1F22;  // Input fields

  // Text
  FColors.Text := $F0F0F0;
  FColors.TextSecondary := $999999;
  FColors.Accent := $F16366;           // Purple accent (#6366F1 BGR)

  // Message bubbles - strong contrast with background
  FColors.UserMessage := $1E3A5F;      // Deep blue
  FColors.UserMessageBorder := $234A70; // Subtle, close to fill
  FColors.AssistantMessage := $2E2E2E;  // Slightly lighter than bg
  FColors.AssistantMessageBorder := $323232; // Very subtle, nearly invisible
  FColors.ErrorMessage := $5C1A1A;     // Deep red
  FColors.ErrorMessageBorder := $6E2020; // Subtle, close to fill
  FColors.ToolMessage := $3A3A1A;      // Olive
  FColors.ToolMessageBorder := $444420; // Subtle, close to fill

  // Buttons
  FColors.ButtonBackground := $383838;
  FColors.ButtonText := $E0E0E0;
  FColors.ButtonHover := $484848;
  FColors.ButtonPressed := $2E2E2E;
  FColors.AccentHover := $C454EE;       // Lighter purple hover

  // Status bar
  FColors.StatusBar := $007ACC;
  FColors.StatusBarText := $FFFFFF;

  // Diff display
  FColors.DiffAdded := $2EA043;
  FColors.DiffRemoved := $F85149;
  FColors.DiffContext := $8B949E;

  // Warning / confirmation
  FColors.WarningColor := $D29922;
  FColors.ApproveBg := $238636;
  FColors.RejectBg := $DA3633;

  // Branch / tree navigation
  FColors.BranchIndicator := $FFA657;
  FColors.LeafIndicator := $3FB950;
  FColors.TreeConnector := $6E7681;

  // Suggestion cards
  FColors.SuggestionBg := $2B2D31;
  FColors.SuggestionBorder := $303030; // Subtle
  FColors.SuggestionHover := $303030;

  // Input card (floating card style)
  FColors.InputCardBg := $2A2B2F;
  FColors.InputCardBorder := $3C3F45; // Warm gray border

  // Markdown / code rendering
  FColors.CodeBlockBg := $1A1B22;
  FColors.CodeBlockBorder := $444444;
  FColors.CodeBlockText := $D4D4D4;
  FColors.InlineCodeText := $CE9178;
  FColors.HeaderColor := $F16366;
  FColors.LinkColor := $569CD6;
  FColors.QuoteColor := $9CDCFE;
  FColors.BoldColor := $F0F0F0;

  // Syntax highlighting (VS Code Dark+ inspired)
  FColors.CodeKeywordColor := $D56B06;    // Blue keywords (BGR for $569CD6)
  FColors.CodeStringColor := $7891CE;     // Orange strings (BGR for $CE9178)
  FColors.CodeCommentColor := $55996A;    // Green comments (BGR for $6A9955)
  FColors.CodeNumberColor := $A8CEB5;     // Light green numbers (BGR for $B5CEA8)

  // Gradient / shadow effects
  FColors.AccentGradientEnd := $8B5CF6;       // Purple gradient end (lighter)
  FColors.AccentGradientEndHover := $A78BFA;  // Hover gradient end
  FColors.ButtonShadow := $101010;             // Dark shadow color
  FColors.BubbleShadow := $101010;             // Subtle bubble shadow
  FColors.SidebarActiveBg := $3D2E6A;          // Dark purple active background
  FColors.InputFocusBorder := $F16366;         // Purple focus border

  // Role icon colors (inspired by chatgpt-main's role-based color coding)
  FColors.UserIconColor := $DA36D1;           // Purple (#D136DA) - user messages
  FColors.AssistantIconColor := $7F10A3;      // Teal-green (#10A37F) - AI responses
  FColors.ToolIconColor := $DD48D8;           // Cyan (#48D8DD) - tool calls
  FColors.ErrorIconColor := $4848DD;          // Red (#DD4848) - errors
  FColors.SystemIconColor := $366FDA;         // Orange (#DA6F36) - system info

  // Layout constants
  FColors.MaxChatWidth := 860;                // max content area width
  FColors.MessageSpacing := 20;               // vertical gap between messages
  FColors.RoleIconSize := 28;                 // role indicator square
  FColors.BubblePadding := 14;                // inner padding
  FColors.SideMargin := 20;                   // margin from chat edges
end;

procedure TThemeManager.SetLightTheme;
begin
  FColors.Background := $F5F5F5;
  FColors.Surface := $FFFFFF;
  FColors.Border := $D0D0D0;
  FColors.InputBackground := $FFFFFF;

  FColors.Text := $1E1E1E;
  FColors.TextSecondary := $6E6E6E;
  FColors.Accent := $007ACC;

  FColors.UserMessage := $D6EEFF;
  FColors.UserMessageBorder := $90CAF9;
  FColors.AssistantMessage := $FFFFFF;
  FColors.AssistantMessageBorder := $E0E0E0;
  FColors.ErrorMessage := $FDDEDE;
  FColors.ErrorMessageBorder := $F5A0A0;
  FColors.ToolMessage := $FFF8E1;
  FColors.ToolMessageBorder := $E0D090;

  FColors.ButtonBackground := $E8E8E8;
  FColors.ButtonText := $1E1E1E;
  FColors.ButtonHover := $D8D8D8;
  FColors.ButtonPressed := $C8C8C8;
  FColors.AccentHover := $006AB5;

  FColors.StatusBar := $007ACC;
  FColors.StatusBarText := $FFFFFF;

  FColors.DiffAdded := $1A7F37;
  FColors.DiffRemoved := $CF222E;
  FColors.DiffContext := $656D76;

  FColors.WarningColor := $9A6700;
  FColors.ApproveBg := $1A7F37;
  FColors.RejectBg := $CF222E;

  FColors.BranchIndicator := $953800;
  FColors.LeafIndicator := $116327;
  FColors.TreeConnector := $B1BAC4;

  FColors.SuggestionBg := $FFFFFF;
  FColors.SuggestionBorder := $D0D0D0;
  FColors.SuggestionHover := $F0F0F0;

  FColors.InputCardBg := $FFFFFF;
  FColors.InputCardBorder := $C8C8D0;

  // Markdown / code rendering
  FColors.CodeBlockBg := $F6F8FA;
  FColors.CodeBlockBorder := $D0D7DE;
  FColors.CodeBlockText := $24292F;
  FColors.InlineCodeText := $CF222E;
  FColors.HeaderColor := $007ACC;
  FColors.LinkColor := $0969DA;
  FColors.QuoteColor := $656D76;
  FColors.BoldColor := $1E1E1E;

  // Syntax highlighting (light theme)
  FColors.CodeKeywordColor := $003DA5;    // Blue keywords
  FColors.CodeStringColor := $0F32CF;     // Red/orange strings
  FColors.CodeCommentColor := $00703A;    // Green comments
  FColors.CodeNumberColor := $056F09;     // Teal numbers

  // Gradient / shadow effects (light theme)
  FColors.AccentGradientEnd := $8B5CF6;
  FColors.AccentGradientEndHover := $A78BFA;
  FColors.ButtonShadow := $808080;
  FColors.BubbleShadow := $A0A0A0;
  FColors.SidebarActiveBg := $FFDEE8;       // Light purple active background (web #E8DEFF)
  FColors.InputFocusBorder := $F16366;

  // Role icon colors (light theme - same hues, slightly adjusted)
  FColors.UserIconColor := $C230B5;           // Purple
  FColors.AssistantIconColor := $6F0E92;      // Teal-green
  FColors.ToolIconColor := $C040C8;           // Cyan
  FColors.ErrorIconColor := $4040C8;          // Red
  FColors.SystemIconColor := $3060C0;         // Orange

  // Layout constants (same for both themes)
  FColors.MaxChatWidth := 860;
  FColors.MessageSpacing := 20;
  FColors.RoleIconSize := 28;
  FColors.BubblePadding := 14;
  FColors.SideMargin := 20;
end;

procedure TThemeManager.ApplyToForm(AForm: TForm);
begin
  AForm.Color := FColors.Background;
  AForm.Font.Color := FColors.Text;
end;

procedure TThemeManager.ApplyToRichEdit(AEdit: TCustomMemo);
begin
  TControlAccess(AEdit).Color := FColors.InputBackground;
  TControlAccess(AEdit).Font.Color := FColors.Text;
end;

procedure TThemeManager.ApplyToPanel(APanel: TPanel);
begin
  APanel.Color := FColors.Surface;
  APanel.Font.Color := FColors.Text;
end;

procedure TThemeManager.ApplyToStatusBar(AStatusBar: TStatusBar);
begin
  AStatusBar.Color := FColors.StatusBar;
  AStatusBar.Font.Color := FColors.StatusBarText;
end;

function TThemeManager.GetCurrentTheme: string;
begin
  Result := FCurrentTheme;
end;

function TThemeManager.GetColors: TThemeColors;
begin
  Result := FColors;
end;

procedure TThemeManager.ApplyToStandardForm(AForm: TForm);

  procedure ThemeControl(AControl: TControl);
  begin
    if AControl is TWinControl then
    begin
      var WC := TWinControl(AControl);
      for var i := 0 to WC.ControlCount - 1 do
        ThemeControl(WC.Controls[i]);
    end;

    if AControl is TLabel then
    begin
      TLabel(AControl).Font.Color := FColors.Text;
    end
    else if AControl is TEdit then
    begin
      TEdit(AControl).Color := FColors.InputBackground;
      TEdit(AControl).Font.Color := FColors.Text;
      TEdit(AControl).BorderStyle := bsNone;
    end
    else if AControl is TMemo then
    begin
      TMemo(AControl).Color := FColors.InputBackground;
      TMemo(AControl).Font.Color := FColors.Text;
    end
    else if AControl is TComboBox then
    begin
      TComboBox(AControl).Color := FColors.InputBackground;
      TComboBox(AControl).Font.Color := FColors.Text;
    end
    else if AControl is TCheckBox then
    begin
      TCheckBox(AControl).Font.Color := FColors.Text;
    end
    else if AControl is TRadioButton then
    begin
      TRadioButton(AControl).Font.Color := FColors.Text;
    end
    else if AControl is TListBox then
    begin
      TListBox(AControl).Color := FColors.InputBackground;
      TListBox(AControl).Font.Color := FColors.Text;
    end
    else if AControl is TPageControl then
    begin
      TPageControl(AControl).OwnerDraw := True;
    end
    else if AControl is TTabSheet then
    begin
      TControlAccess(AControl).Color := FColors.Background;
    end
    else if AControl is TGroupBox then
    begin
      TGroupBox(AControl).Color := FColors.Background;
      TGroupBox(AControl).Font.Color := FColors.Text;
    end
    else if AControl is TPanel then
    begin
      if TPanel(AControl).ParentBackground then
        TPanel(AControl).ParentBackground := False;
      if TPanel(AControl).BevelOuter <> bvNone then
        TPanel(AControl).BevelOuter := bvNone;
    end;
  end;

begin
  AForm.Color := FColors.Background;
  AForm.Font.Color := FColors.Text;
  ThemeControl(AForm);
end;

procedure TThemeManager.ApplyDarkScrollbar(AHandle: HWND);
type
  TSetWindowTheme = function(hwnd: HWND; pszSubAppName: PWideChar;
    pszSubIdList: PWideChar): HResult; stdcall;
var
  hUxTheme: THandle;
  SetWindowThemeProc: TSetWindowTheme;
begin
  hUxTheme := GetModuleHandle('uxtheme.dll');
  if hUxTheme = 0 then
    hUxTheme := LoadLibrary('uxtheme.dll');
  if hUxTheme = 0 then Exit;
  SetWindowThemeProc := GetProcAddress(hUxTheme, 'SetWindowTheme');
  if not Assigned(SetWindowThemeProc) then Exit;
  SetWindowThemeProc(AHandle, 'DarkMode_Explorer', nil);
end;

procedure TThemeManager.ApplyDarkComboBox(AComboBox: TComboBox);
var
  Info: TComboBoxInfo;
begin
  if AComboBox.Handle = 0 then Exit;
  ApplyDarkScrollbar(AComboBox.Handle);
  FillChar(Info, SizeOf(Info), 0);
  Info.cbSize := SizeOf(Info);
  if SendMessage(AComboBox.Handle, CB_GETCOMBOBOXINFO, 0, LPARAM(@Info)) <> 0 then
  begin
    if Info.hwndList <> 0 then
      ApplyDarkScrollbar(Info.hwndList);
    if Info.hwndItem <> 0 then
      ApplyDarkScrollbar(Info.hwndItem);
  end;
end;

end.
