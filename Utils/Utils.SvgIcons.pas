unit Utils.SvgIcons;

{ SVG icon constants and runtime collection builder.
  Uses SVGIconImageList (Image32 engine, no DLL required).
  Lucide-style icons (MIT/ISC license). }

interface

uses
  System.SysUtils, System.Classes, Vcl.Controls, Vcl.Graphics,
  SVGIconImageCollection,
  SVGIconVirtualImageList;

const
  { Icon index constants — must match the order in CreateSvgIconCollection }
  ICON_MENU          = 0;   // 3 horizontal lines (hamburger)
  ICON_SEND          = 1;   // right-pointing arrow
  ICON_CHEVRON_UP    = 2;   // upward chevron
  ICON_CHEVRON_DOWN  = 3;   // downward chevron
  ICON_CLOSE         = 4;   // X close
  ICON_ELLIPSIS      = 5;   // 3 dots (more)
  ICON_PLUS          = 6;   // plus sign
  ICON_STOP          = 7;   // stop circle
  ICON_COPY          = 8;   // two overlapping rectangles
  ICON_MESSAGE       = 9;   // chat bubble (message-square)
  ICON_SETTINGS      = 10;  // gear (settings)
  ICON_TRASH         = 11;  // trash can (delete)

  ICON_COUNT = 12;

{ SVG text for each icon — stroke-based, 24x24 viewBox }
const
  SVG_MENU =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" '+
    'fill="none" stroke="#000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'+
    '<line x1="4" x2="20" y1="6" y2="6"/>'+
    '<line x1="4" x2="20" y1="12" y2="12"/>'+
    '<line x1="4" x2="20" y1="18" y2="18"/>'+
    '</svg>';

  SVG_SEND =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" '+
    'fill="none" stroke="#000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'+
    '<path d="M5 12h14"/>'+
    '<path d="m12 5 7 7-7 7"/>'+
    '</svg>';

  SVG_CHEVRON_UP =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" '+
    'fill="none" stroke="#000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'+
    '<path d="m18 15-6-6-6 6"/>'+
    '</svg>';

  SVG_CHEVRON_DOWN =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" '+
    'fill="none" stroke="#000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'+
    '<path d="m6 9 6 6 6-6"/>'+
    '</svg>';

  SVG_CLOSE =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" '+
    'fill="none" stroke="#000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'+
    '<path d="M18 6 6 18"/>'+
    '<path d="m6 6 12 12"/>'+
    '</svg>';

  SVG_ELLIPSIS =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" '+
    'fill="none" stroke="#000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'+
    '<circle cx="12" cy="12" r="1.5"/>'+
    '<circle cx="19" cy="12" r="1.5"/>'+
    '<circle cx="5" cy="12" r="1.5"/>'+
    '</svg>';

  SVG_PLUS =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" '+
    'fill="none" stroke="#000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'+
    '<path d="M5 12h14"/>'+
    '<path d="M12 5v14"/>'+
    '</svg>';

  SVG_STOP =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" '+
    'fill="none" stroke="#000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'+
    '<circle cx="12" cy="12" r="10"/>'+
    '<rect x="9" y="9" width="6" height="6" rx="1"/>'+
    '</svg>';

  SVG_COPY =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" '+
    'fill="none" stroke="#000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'+
    '<rect width="14" height="14" x="8" y="8" rx="2" ry="2"/>'+
    '<path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>'+
    '</svg>';

  SVG_MESSAGE =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" '+
    'fill="none" stroke="#000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'+
    '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>'+
    '</svg>';

  SVG_SETTINGS =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" '+
    'fill="none" stroke="#000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'+
    '<path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/>'+
    '<circle cx="12" cy="12" r="3"/>'+
    '</svg>';

  SVG_TRASH =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" '+
    'fill="none" stroke="#000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'+
    '<path d="M3 6h18"/>'+
    '<path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/>'+
    '<path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/>'+
    '</svg>';

{ SVG text array for programmatic access }
const
  SVG_ICONS: array[0..ICON_COUNT - 1] of string = (
    SVG_MENU, SVG_SEND, SVG_CHEVRON_UP, SVG_CHEVRON_DOWN,
    SVG_CLOSE, SVG_ELLIPSIS, SVG_PLUS, SVG_STOP, SVG_COPY,
    SVG_MESSAGE, SVG_SETTINGS, SVG_TRASH
  );

  SVG_ICON_NAMES: array[0..ICON_COUNT - 1] of string = (
    'menu', 'send', 'chevron-up', 'chevron-down',
    'close', 'ellipsis', 'plus', 'stop', 'copy',
    'message', 'settings', 'trash'
  );

{ Create the SVG icon collection at runtime.
  Caller must free via Owner (usually Self/MainForm). }
function CreateSvgIconCollection(AOwner: TComponent): TSVGIconImageCollection;

{ Create a virtual image list linked to the collection.
  Size = icon dimensions (default 24).
  FixedColor = override all icon colors (clNone = use original). }
function CreateSvgImageList(AOwner: TComponent; ACollection: TSVGIconImageCollection;
  ASize: Integer = 24; AFixedColor: TColor = -1): TSVGIconVirtualImageList;

{ Update the FixedColor of an image list (for theme changes) }
procedure SetSvgImageListColor(AImageList: TSVGIconVirtualImageList; AColor: TColor);

implementation

function CreateSvgIconCollection(AOwner: TComponent): TSVGIconImageCollection;
var
  i: Integer;
begin
  Result := TSVGIconImageCollection.Create(AOwner);
  for i := 0 to ICON_COUNT - 1 do
  begin
    with Result.SVGIconItems.Add do
    begin
      SVGText := SVG_ICONS[i];
      Name := SVG_ICON_NAMES[i];
    end;
  end;
end;

function CreateSvgImageList(AOwner: TComponent; ACollection: TSVGIconImageCollection;
  ASize: Integer = 24; AFixedColor: TColor = -1): TSVGIconVirtualImageList;
begin
  Result := TSVGIconVirtualImageList.Create(AOwner);
  Result.Size := ASize;
  Result.AutoFill := True;
  Result.ImageCollection := ACollection;
  if AFixedColor >= 0 then
    Result.FixedColor := AFixedColor;
end;

procedure SetSvgImageListColor(AImageList: TSVGIconVirtualImageList; AColor: TColor);
begin
  AImageList.FixedColor := AColor;
  // Force rebuild of cached bitmaps with the new color
  AImageList.AutoFill := False;
  AImageList.AutoFill := True;
end;

end.
