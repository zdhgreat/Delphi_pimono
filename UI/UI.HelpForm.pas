unit UI.HelpForm;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Utils.Localization,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Grids,
  UI.ThemeManager, UI.Spacing;

type
  THelpForm = class(TForm)
    procedure FormCreate(Sender: TObject);
  private
    FPageControl: TPageControl;
    FTabAbout: TTabSheet;
    FTabShortcuts: TTabSheet;
    FTabTips: TTabSheet;
    FBtnClose: TButton;
    FThemeManager: TThemeManager;
    FHotTabIndex: Integer;
    procedure CreateComponents;
    procedure ApplyTheme;
    procedure DrawTab(Control: TCustomTabControl; TabIndex: Integer;
      const Rect: TRect; Active: Boolean);
    procedure HotTabChanged(Sender: TObject; Shift: TShiftState; X, Y: Integer);
  public
    class procedure ShowHelp(AThemeManager: TThemeManager = nil);
  end;

implementation

{$R *.dfm}

type
  TControlAccess = class(TControl);

{ THelpForm }

procedure THelpForm.FormCreate(Sender: TObject);
begin
  Caption := L('help.title');
  ClientWidth := 520;
  ClientHeight := 480;
  Position := poScreenCenter;
  BorderStyle := bsDialog;
  FHotTabIndex := -1;
  CreateComponents;
end;

procedure THelpForm.CreateComponents;

  procedure AddShortcut(AGrid: TStringGrid; ARow: Integer;
    const AKey, ADesc: string);
  begin
    AGrid.Cells[0, ARow] := AKey;
    AGrid.Cells[1, ARow] := ADesc;
  end;

  procedure AddTip(AMemo: TMemo; const ATip: string);
  begin
    AMemo.Lines.Add(ATip);
    AMemo.Lines.Add('');
  end;

var
  Grid: TStringGrid;
  Memo: TMemo;
  Label1: TLabel;
begin
  FPageControl := TPageControl.Create(Self);
  FPageControl.Parent := Self;
  FPageControl.Align := alClient;
  FPageControl.Margins.SetBounds(8, 8, 8, 40);

  // --- About Tab ---
  FTabAbout := TTabSheet.Create(FPageControl);
  FTabAbout.PageControl := FPageControl;
  FTabAbout.Caption := L('help.about');

  Label1 := TLabel.Create(FTabAbout);
  Label1.Parent := FTabAbout;
  Label1.Left := 20;
  Label1.Top := 20;
  Label1.Caption := L('help.appName');
  Label1.Font.Size := 18;
  Label1.Font.Style := [fsBold];

  var LblVersion := TLabel.Create(FTabAbout);
  LblVersion.Parent := FTabAbout;
  LblVersion.Left := 20;
  LblVersion.Top := 55;
  LblVersion.Caption := L('help.version');

  var LblDesc := TMemo.Create(FTabAbout);
  LblDesc.Parent := FTabAbout;
  LblDesc.Left := 20;
  LblDesc.Top := 85;
  LblDesc.Width := 460;
  LblDesc.Height := 200;
  LblDesc.Text := L('help.desc');
  LblDesc.ReadOnly := True;
  LblDesc.WordWrap := True;
  LblDesc.ScrollBars := ssVertical;
  LblDesc.BorderStyle := bsNone;

  var LblTech := TLabel.Create(FTabAbout);
  LblTech.Parent := FTabAbout;
  LblTech.Left := 20;
  LblTech.Top := 295;
  LblTech.Caption := L('help.tech');

  // --- Shortcuts Tab ---
  FTabShortcuts := TTabSheet.Create(FPageControl);
  FTabShortcuts.PageControl := FPageControl;
  FTabShortcuts.Caption := L('help.shortcuts');

  Grid := TStringGrid.Create(FTabShortcuts);
  Grid.Parent := FTabShortcuts;
  Grid.Align := alClient;
  Grid.Margins.SetBounds(8, 8, 8, 8);
  Grid.ColCount := 2;
  Grid.RowCount := 11;
  Grid.FixedRows := 1;
  Grid.FixedCols := 0;
  Grid.Cells[0, 0] := L('help.colShortcut');
  Grid.Cells[1, 0] := L('help.colAction');
  Grid.ColWidths[0] := 180;
  Grid.ColWidths[1] := 280;

  AddShortcut(Grid, 1, 'Enter', L('help.sk.send'));
  AddShortcut(Grid, 2, 'Shift+Enter', L('help.sk.newline'));
  AddShortcut(Grid, 3, 'Ctrl+S', L('help.sk.save'));
  AddShortcut(Grid, 4, 'Ctrl+N', L('help.sk.new'));
  AddShortcut(Grid, 5, 'Ctrl+O', L('help.sk.open'));
  AddShortcut(Grid, 6, 'Ctrl+,', L('help.sk.settings'));
  AddShortcut(Grid, 7, 'Ctrl+L', L('help.sk.clear'));
  AddShortcut(Grid, 8, 'Escape', L('help.sk.abort'));
  AddShortcut(Grid, 9, 'F1', L('help.sk.help'));
  AddShortcut(Grid, 10, 'Ctrl+Q', L('help.sk.quit'));

  // --- Tips Tab ---
  FTabTips := TTabSheet.Create(FPageControl);
  FTabTips.PageControl := FPageControl;
  FTabTips.Caption := L('help.tips');

  Memo := TMemo.Create(FTabTips);
  Memo.Parent := FTabTips;
  Memo.Align := alClient;
  Memo.Margins.SetBounds(8, 8, 8, 8);
  Memo.ReadOnly := True;
  Memo.WordWrap := True;
  Memo.ScrollBars := ssVertical;
  Memo.Font.Size := 10;

  AddTip(Memo, L('help.tip1'));
  AddTip(Memo, L('help.tip2'));
  AddTip(Memo, L('help.tip3'));
  AddTip(Memo, L('help.tip4'));
  AddTip(Memo, L('help.tip5'));
  AddTip(Memo, L('help.tip6'));
  AddTip(Memo, L('help.tip7'));

  // --- Close Button ---
  FBtnClose := TButton.Create(Self);
  FBtnClose.Parent := Self;
  FBtnClose.Caption := L('help.close');
  FBtnClose.Width := 80;
  FBtnClose.Height := 28;
  FBtnClose.Left := (ClientWidth - FBtnClose.Width) div 2;
  FBtnClose.Top := ClientHeight - FBtnClose.Height - 8;
  FBtnClose.Anchors := [akBottom];
  FBtnClose.ModalResult := mrClose;

  FPageControl.ActivePageIndex := 0;
end;

procedure THelpForm.ApplyTheme;
var
  Colors: TThemeColors;
  i, j: Integer;
begin
  if FThemeManager = nil then Exit;
  Colors := FThemeManager.Colors;

  // Use the enhanced standard form theming
  FThemeManager.ApplyToStandardForm(Self);

  // Modern pill tabs
  SetupModernPageControl(FPageControl, Colors);
  FPageControl.OnDrawTab := DrawTab;
  FPageControl.OnMouseMove := HotTabChanged;

  // Theme the grid with proper colors
  for i := 0 to FPageControl.PageCount - 1 do
  begin
    var Tab := FPageControl.Pages[i];
    Tab.Brush.Color := Colors.InputBackground;
    for j := 0 to Tab.ControlCount - 1 do
    begin
      if Tab.Controls[j] is TStringGrid then
      begin
        var Grid := TStringGrid(Tab.Controls[j]);
        Grid.Color := Colors.InputBackground;
        Grid.Font.Color := Colors.Text;
        Grid.FixedColor := Colors.Surface;
        Grid.GridLineWidth := 0;
        Grid.DefaultDrawing := True;
      end;
    end;
  end;

  // Close button
  FBtnClose.Font.Color := Colors.Text;
end;

procedure THelpForm.HotTabChanged(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  NewHot: Integer;
begin
  NewHot := FPageControl.IndexOfTabAt(
    FPageControl.ScreenToClient(Mouse.CursorPos).X,
    FPageControl.ScreenToClient(Mouse.CursorPos).Y);
  if NewHot <> FHotTabIndex then
  begin
    FHotTabIndex := NewHot;
    FPageControl.Invalidate;
  end;
end;

procedure THelpForm.DrawTab(Control: TCustomTabControl; TabIndex: Integer;
  const Rect: TRect; Active: Boolean);
begin
  if FThemeManager <> nil then
    DrawPillTab(Control, TabIndex, Rect, Active, FThemeManager.Colors, FHotTabIndex);
end;

class procedure THelpForm.ShowHelp(AThemeManager: TThemeManager);
var
  Form: THelpForm;
begin
  Form := THelpForm.Create(nil);
  try
    Form.FThemeManager := AThemeManager;
    Form.ApplyTheme;
    Form.ShowModal;
  finally
    Form.Free;
  end;
end;

end.
