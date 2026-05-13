unit Utils.Markdown;

interface

uses
  System.SysUtils, System.StrUtils, Vcl.Graphics;

type
  TMarkdownColors = record
    TextColor: TColor;
    CodeBlockText: TColor;
    CodeBlockBorder: TColor;
    InlineCodeText: TColor;
    HeaderColor: TColor;
    LinkColor: TColor;
    QuoteColor: TColor;
    BoldColor: TColor;
  end;

/// <summary>Convert Markdown text to RTF string suitable for TRichEdit.</summary>
function MarkdownToRtf(const AMarkdown: string; const AFontName: string;
  AFontSize: Integer; const AColors: TMarkdownColors): string;

/// <summary>Extract all code blocks from Markdown text. Returns array of code strings.</summary>
function ExtractCodeBlocks(const AMarkdown: string): TArray<string>;

/// <summary>Check if Markdown text contains code blocks.</summary>
function HasCodeBlocks(const AMarkdown: string): Boolean;

type
  TMarkdownSegmentKind = (mskText, mskCodeBlock);
  TMarkdownSegment = record
    Kind: TMarkdownSegmentKind;
    Text: string;
    Language: string; // only for mskCodeBlock
  end;

/// <summary>Parse Markdown into alternating text and code-block segments.</summary>
function ParseMarkdownSegments(const AMarkdown: string): TArray<TMarkdownSegment>;

implementation

uses
  System.Math;

{ Helpers }

function ColorToRtf(AColor: TColor): string;
var
  RGB: Cardinal;
begin
  RGB := ColorToRGB(AColor);
  Result := Format('\red%d\green%d\blue%d;', [Byte(RGB), Byte(RGB shr 8), Byte(RGB shr 16)]);
end;

function EscapeRtfChar(C: Char): string;
begin
  case C of
    '\': Result := '\\';
    '{': Result := '\{';
    '}': Result := '\}';
  else
    if Ord(C) > 127 then
      Result := Format('\u%d?', [SmallInt(Ord(C))])
    else
      Result := C;
  end;
end;

{ TMarkdownToRtfConverter }

type
  TConverter = record
  private
    FSource: string;
    FLines: TArray<string>;
    FSB: TStringBuilder;
    FColors: TMarkdownColors;
    FFontName: string;
    FMonoFont: string;
    FFs: Integer; // base font size in half-points
    FInCodeBlock: Boolean;
    FInTable: Boolean;
    // Pre-computed RTF control strings
    FRtfCodeStart: string;
    FRtfCodeEnd: string;

    // Color table indices (1-based)
    const CI_TEXT = 1;
    const CI_CODETXT = 2;
    const CI_CODEBDR = 3;
    const CI_INLTXT = 4;
    const CI_HEADER = 5;
    const CI_LINK = 6;
    const CI_QUOTE = 7;
    const CI_BOLD = 8;

    procedure EmitRtfHeader;
    procedure EmitEscaped(const S: string);
    procedure RenderInline(const S: string);
    procedure EmitCodeLine(const S: string);
    function HeaderLevel(const S: string): Integer;
    function IsHRule(const S: string): Boolean;
    function IsUnorderedList(const S: string; out AText: string): Boolean;
    function IsOrderedList(const S: string; out ANumText, AText: string): Boolean;
    function IsTableSeparator(const S: string): Boolean;
    procedure Convert;
  public
    class function Execute(const AMarkdown: string; const AFontName: string;
      AFontSize: Integer; const AColors: TMarkdownColors): string; static;
  end;

procedure TConverter.EmitRtfHeader;
begin
  FSB.AppendLine('{\rtf1\ansi\ansicpg65001\deff0');
  FSB.AppendLine('{\fonttbl');
  FSB.AppendLine(Format('{\f0\fnil\fcharset134 %s;}', [FFontName]));
  FSB.AppendLine(Format('{\f1\fnil\fcharset0 %s;}', [FMonoFont]));
  FSB.AppendLine('}');
  FSB.AppendLine('{\colortbl;');
  FSB.AppendLine(ColorToRtf(FColors.TextColor));        // CI_TEXT = 1
  FSB.AppendLine(ColorToRtf(FColors.CodeBlockText));    // CI_CODETXT = 2
  FSB.AppendLine(ColorToRtf(FColors.CodeBlockBorder));  // CI_CODEBDR = 3
  FSB.AppendLine(ColorToRtf(FColors.InlineCodeText));   // CI_INLTXT = 4
  FSB.AppendLine(ColorToRtf(FColors.HeaderColor));      // CI_HEADER = 5
  FSB.AppendLine(ColorToRtf(FColors.LinkColor));        // CI_LINK = 6
  FSB.AppendLine(ColorToRtf(FColors.QuoteColor));       // CI_QUOTE = 7
  FSB.AppendLine(ColorToRtf(FColors.BoldColor));        // CI_BOLD = 8
  FSB.AppendLine('}');
  FSB.Append(Format('\pard\plain\f0\fs%d\cf%d ', [FFs, CI_TEXT]));
end;

procedure TConverter.EmitEscaped(const S: string);
var
  i: Integer;
begin
  for i := 1 to Length(S) do
  begin
    if S[i] = #13 then Continue;
    if S[i] = #10 then Continue;
    FSB.Append(EscapeRtfChar(S[i]));
  end;
end;

procedure TConverter.RenderInline(const S: string);
var
  i: Integer;

  function FindClosing(const AMarker: string; AFrom: Integer): Integer;
  var
    j: Integer;
  begin
    Result := 0;
    j := AFrom;
    while j <= Length(S) - Length(AMarker) + 1 do
    begin
      if Copy(S, j, Length(AMarker)) = AMarker then
      begin
        if j <> AFrom then // don't match the opening marker itself
        begin
          Result := j;
          Exit;
        end;
      end;
      Inc(j);
    end;
  end;

begin
  i := 1;
  while i <= Length(S) do
  begin
    // Inline code: `...`
    if S[i] = '`' then
    begin
      var EndP := PosEx('`', S, i + 1);
      if EndP > i then
      begin
        FSB.Append(FRtfCodeStart);
        EmitEscaped(Copy(S, i + 1, EndP - i - 1));
        FSB.Append(FRtfCodeEnd);
        i := EndP + 1;
        Continue;
      end;
    end;

    // Bold: **...**
    if (S[i] = '*') and (i + 1 <= Length(S)) and (S[i + 1] = '*') then
    begin
      var EndP := FindClosing('**', i + 2);
      if EndP > i then
      begin
        FSB.Append(Format('\b\cf%d ', [CI_BOLD]));
        RenderInline(Copy(S, i + 2, EndP - i - 2));
        FSB.Append(Format('\b0\cf%d ', [CI_TEXT]));
        i := EndP + 2;
        Continue;
      end;
    end;

    // Bold with __...__
    if (S[i] = '_') and (i + 1 <= Length(S)) and (S[i + 1] = '_') then
    begin
      var EndP := FindClosing('__', i + 2);
      if EndP > i then
      begin
        FSB.Append(Format('\b\cf%d ', [CI_BOLD]));
        RenderInline(Copy(S, i + 2, EndP - i - 2));
        FSB.Append(Format('\b0\cf%d ', [CI_TEXT]));
        i := EndP + 2;
        Continue;
      end;
    end;

    // Italic: *...*
    if S[i] = '*' then
    begin
      var EndP := PosEx('*', S, i + 1);
      if EndP > i then
      begin
        FSB.Append('\i ');
        RenderInline(Copy(S, i + 1, EndP - i - 1));
        FSB.Append('\i0 ');
        i := EndP + 1;
        Continue;
      end;
    end;

    // Italic: _..._
    if (S[i] = '_') and not ((i + 1 <= Length(S)) and (S[i + 1] = '_')) then
    begin
      var EndP := PosEx('_', S, i + 1);
      if EndP > i then
      begin
        FSB.Append('\i ');
        RenderInline(Copy(S, i + 1, EndP - i - 1));
        FSB.Append('\i0 ');
        i := EndP + 1;
        Continue;
      end;
    end;

    // Link: [text](url)
    if S[i] = '[' then
    begin
      var CloseB := PosEx(']', S, i + 1);
      if (CloseB > i) and (CloseB + 1 <= Length(S)) and (S[CloseB + 1] = '(') then
      begin
        var CloseP := PosEx(')', S, CloseB + 2);
        if CloseP > CloseB then
        begin
          FSB.Append(Format('\cf%d\ul ', [CI_LINK]));
          EmitEscaped(Copy(S, i + 1, CloseB - i - 1));
          FSB.Append(Format('\ul0\cf%d ', [CI_TEXT]));
          i := CloseP + 1;
          Continue;
        end;
      end;
    end;

    // Normal character
    FSB.Append(EscapeRtfChar(S[i]));
    Inc(i);
  end;
end;

procedure TConverter.EmitCodeLine(const S: string);
begin
  if S = '' then
  begin
    FSB.Append('\line ');
    Exit;
  end;
  // Escape each character preserving all whitespace and special chars
  for var i := 1 to Length(S) do
  begin
    if S[i] = #13 then Continue;
    if S[i] = #10 then Continue; // handled by caller
    case S[i] of
      '\': FSB.Append('\\');
      '{': FSB.Append('\{');
      '}': FSB.Append('\}');
    else
      if Ord(S[i]) > 127 then
        FSB.Append(Format('\u%d?', [SmallInt(Ord(S[i]))]))
      else if Ord(S[i]) >= 32 then
        FSB.Append(S[i]);
    end;
  end;
  FSB.Append('\line ');
end;

function TConverter.HeaderLevel(const S: string): Integer;
var
  j: Integer;
begin
  Result := 0;
  j := 1;
  while (j <= Length(S)) and (S[j] = '#') do
  begin
    Inc(Result);
    Inc(j);
  end;
  if (Result > 0) and (Result <= 6) and (j <= Length(S)) and (S[j] = ' ') then
    Exit
  else
    Result := 0;
end;

function TConverter.IsHRule(const S: string): Boolean;
var
  T: string;
  i, Cnt: Integer;
  Ch: Char;
begin
  T := Trim(S);
  if Length(T) < 3 then Exit(False);
  Ch := T[1];
  if not CharInSet(Ch, ['-', '*', '_']) then Exit(False);
  Cnt := 0;
  for i := 1 to Length(T) do
    if T[i] = Ch then Inc(Cnt)
    else if T[i] <> ' ' then Exit(False);
  Result := Cnt >= 3;
end;

function TConverter.IsUnorderedList(const S: string; out AText: string): Boolean;
var
  j: Integer;
begin
  Result := False;
  AText := '';
  j := 1;
  // skip leading spaces
  while (j <= Length(S)) and (S[j] = ' ') do Inc(j);
  if j > Length(S) then Exit;
  if not CharInSet(S[j], ['-', '*']) then Exit;
  if j + 1 > Length(S) then Exit;
  if S[j + 1] <> ' ' then Exit;
  // Must not be a horizontal rule (e.g., "---" or "***")
  if IsHRule(S) then Exit;
  AText := Copy(S, j + 2, MaxInt);
  Result := True;
end;

function TConverter.IsOrderedList(const S: string; out ANumText, AText: string): Boolean;
var
  j, DotPos: Integer;
begin
  Result := False;
  ANumText := '';
  AText := '';
  j := 1;
  while (j <= Length(S)) and (S[j] = ' ') do Inc(j);
  if j > Length(S) then Exit;
  if not CharInSet(S[j], ['0'..'9']) then Exit;
  var k := j;
  while (k <= Length(S)) and CharInSet(S[k], ['0'..'9']) do Inc(k);
  if k > Length(S) then Exit;
  if not CharInSet(S[k], ['.', ')']) then Exit;
  DotPos := k;
  if DotPos + 1 > Length(S) then Exit;
  if S[DotPos + 1] <> ' ' then Exit;
  ANumText := Copy(S, j, DotPos - j + 1);
  AText := Copy(S, DotPos + 2, MaxInt);
  Result := True;
end;

function TConverter.IsTableSeparator(const S: string): Boolean;
var
  T: string;
  i: Integer;
begin
  T := Trim(S);
  if not T.StartsWith('|') then Exit(False);
  for i := 2 to Length(T) do
    if not CharInSet(T[i], ['-', ':', ' ', '|']) then Exit(False);
  Result := True;
end;

procedure TConverter.Convert;
var
  i: Integer;
  Line, Trimmed: string;
  HL: Integer;
  ListItem, NumText: string;

  procedure EndTable;
  begin
    if FInTable then
    begin
      FSB.Append('\par ');
      FSB.Append(Format('\pard\plain\f0\fs%d\cf%d ', [FFs, CI_TEXT]));
      FInTable := False;
    end;
  end;

begin
  FLines := FSource.Split([#10]);
  FInCodeBlock := False;
  FInTable := False;

  EmitRtfHeader;

  for i := 0 to High(FLines) do
  begin
    Line := FLines[i];
    // Strip trailing CR
    if (Length(Line) > 0) and (Line[Length(Line)] = #13) then
      Line := Copy(Line, 1, Length(Line) - 1);

    // --- Code block state ---
    if FInCodeBlock then
    begin
      if Line.StartsWith('```') then
      begin
        FInCodeBlock := False;
        FSB.Append('\par ');
        FSB.Append(Format('\pard\plain\f0\fs%d\cf%d ', [FFs, CI_TEXT]));
      end
      else
        EmitCodeLine(Line);
      Continue;
    end;

    // --- Code block start ---
    if Line.StartsWith('```') then
    begin
      EndTable;
      FInCodeBlock := True;
      // Code block: left border, indented, monospace
      FSB.Append(Format(
        '\par\pard\li300\ri200\brdrl\brdrs\brdrw20\brdrcf%d\f1\fs%d\cf%d ',
        [CI_CODEBDR, FFs - 2, CI_CODETXT]));
      Continue;
    end;

    // --- Empty line ---
    Trimmed := Trim(Line);
    if Trimmed = '' then
    begin
      EndTable;
      FSB.Append('\par ');
      Continue;
    end;

    // --- Header ---
    HL := HeaderLevel(Line);
    if HL > 0 then
    begin
      EndTable;
      var HFs := FFs + (7 - HL) * 4;
      FSB.Append(Format('\pard\plain\f0\fs%d\cf%d\b ', [HFs, CI_HEADER]));
      RenderInline(Copy(Line, HL + 2, MaxInt));
      FSB.Append(Format('\b0\par\pard\plain\f0\fs%d\cf%d ', [FFs, CI_TEXT]));
      Continue;
    end;

    // --- Horizontal rule ---
    if IsHRule(Line) then
    begin
      EndTable;
      FSB.Append(Format('\pard\brdrb\brdrs\brdrw10\brdrcf%d\sp100 ', [CI_CODEBDR]));
      FSB.Append('\par ');
      FSB.Append(Format('\pard\plain\f0\fs%d\cf%d ', [FFs, CI_TEXT]));
      Continue;
    end;

    // --- Blockquote ---
    if Line.StartsWith('> ') or (Line = '>') then
    begin
      EndTable;
      var QText := Copy(Line, 3, MaxInt);
      FSB.Append(Format(
        '\pard\li400\ri100\brdrl\brdrs\brdrw15\brdrcf%d\f0\fs%d\cf%d ',
        [CI_CODEBDR, FFs, CI_QUOTE]));
      RenderInline(QText);
      FSB.Append(Format('\par\pard\plain\f0\fs%d\cf%d ', [FFs, CI_TEXT]));
      Continue;
    end;

    // --- Table ---
    if Line.StartsWith('|') then
    begin
      if not FInTable then
      begin
        FInTable := True;
        FSB.Append(Format('\pard\f1\fs%d\cf%d ', [FFs - 2, CI_TEXT]));
      end;
      if IsTableSeparator(Line) then
      begin
        // Skip separator row
        Continue;
      end;
      // Render table row as-is in monospace
      for var ci := 1 to Length(Line) do
      begin
        if Line[ci] = #13 then Continue;
        if Line[ci] = #10 then Continue;
        case Line[ci] of
          '\': FSB.Append('\\');
          '{': FSB.Append('\{');
          '}': FSB.Append('\}');
        else
          if Ord(Line[ci]) > 127 then
            FSB.Append(Format('\u%d?', [SmallInt(Ord(Line[ci]))]))
          else
            FSB.Append(Line[ci]);
        end;
      end;
      FSB.Append('\line ');
      Continue;
    end;
    EndTable;

    // --- Unordered list ---
    if IsUnorderedList(Line, ListItem) then
    begin
      FSB.Append(Format('\pard\li360\fi-220\f0\fs%d\cf%d ', [FFs, CI_TEXT]));
      FSB.Append('\u8226?  '); // bullet character
      RenderInline(ListItem);
      FSB.Append('\par ');
      Continue;
    end;

    // --- Ordered list ---
    if IsOrderedList(Line, NumText, ListItem) then
    begin
      FSB.Append(Format('\pard\li360\fi-220\f0\fs%d\cf%d ', [FFs, CI_TEXT]));
      EmitEscaped(NumText);
      FSB.Append(' ');
      RenderInline(ListItem);
      FSB.Append('\par ');
      Continue;
    end;

    // --- Regular paragraph ---
    FSB.Append(Format('\pard\f0\fs%d\cf%d ', [FFs, CI_TEXT]));
    RenderInline(Line);
    FSB.Append('\par ');
  end;

  EndTable;

  // Close code block if still open (unclosed ``` at EOF)
  if FInCodeBlock then
  begin
    FSB.Append('\par ');
    FSB.Append(Format('\pard\plain\f0\fs%d\cf%d ', [FFs, CI_TEXT]));
  end;

  FSB.Append('}');
end;

class function TConverter.Execute(const AMarkdown: string;
  const AFontName: string; AFontSize: Integer;
  const AColors: TMarkdownColors): string;
var
  Conv: TConverter;
begin
  Conv := Default(TConverter);
  Conv.FSource := AMarkdown;
  Conv.FColors := AColors;
  Conv.FFontName := AFontName;
  Conv.FMonoFont := 'Consolas';
  Conv.FFs := AFontSize * 2; // RTF uses half-points
  Conv.FRtfCodeStart := Format('\f1\fs%d\cf%d ', [Conv.FFs, Conv.CI_INLTXT]);
  Conv.FRtfCodeEnd := Format('\f0\fs%d\cf%d ', [Conv.FFs, Conv.CI_TEXT]);
  Conv.FSB := TStringBuilder.Create(Length(AMarkdown) * 3);
  try
    Conv.Convert;
    Result := Conv.FSB.ToString;
  finally
    Conv.FSB.Free;
  end;
end;

function MarkdownToRtf(const AMarkdown: string; const AFontName: string;
  AFontSize: Integer; const AColors: TMarkdownColors): string;
begin
  Result := TConverter.Execute(AMarkdown, AFontName, AFontSize, AColors);
end;

function ExtractCodeBlocks(const AMarkdown: string): TArray<string>;
var
  Lines: TArray<string>;
  i, Count: Integer;
  InCode: Boolean;
  CurrentBlock: TStringBuilder;
  Temp: TArray<string>;
begin
  Result := nil;
  Count := 0;
  SetLength(Temp, 64);  // pre-allocate
  InCode := False;
  CurrentBlock := nil;
  Lines := AMarkdown.Split([#10]);
  try
    for i := 0 to High(Lines) do
    begin
      var Line := Lines[i];
      if (Length(Line) > 0) and (Line[Length(Line)] = #13) then
        Line := Copy(Line, 1, Length(Line) - 1);

      if InCode then
      begin
        if Line.StartsWith('```') then
        begin
          InCode := False;
          if Count >= Length(Temp) then
            SetLength(Temp, Length(Temp) * 2);
          Temp[Count] := CurrentBlock.ToString;
          Inc(Count);
          FreeAndNil(CurrentBlock);
        end
        else
        begin
          if CurrentBlock.Length > 0 then
            CurrentBlock.AppendLine;
          CurrentBlock.Append(Line);
        end;
      end
      else
      begin
        if Line.StartsWith('```') then
        begin
          InCode := True;
          CurrentBlock := TStringBuilder.Create;
        end;
      end;
    end;

    // Handle unclosed code block
    if InCode and (CurrentBlock <> nil) then
    begin
      if Count >= Length(Temp) then
        SetLength(Temp, Length(Temp) * 2);
      Temp[Count] := CurrentBlock.ToString;
      Inc(Count);
    end;
  finally
    CurrentBlock.Free;
  end;

  SetLength(Temp, Count);
  Result := Temp;
end;

function HasCodeBlocks(const AMarkdown: string): Boolean;
var
  Lines: TArray<string>;
  i: Integer;
  InCode: Boolean;
begin
  Result := False;
  InCode := False;
  Lines := AMarkdown.Split([#10]);
  for i := 0 to High(Lines) do
  begin
    var Line := Lines[i];
    if (Length(Line) > 0) and (Line[Length(Line)] = #13) then
      Line := Copy(Line, 1, Length(Line) - 1);
    if Line.StartsWith('```') then
    begin
      if InCode then
      begin
        // Closed a code block — found a complete one
        Result := True;
        Exit;
      end
      else
        InCode := True;
    end;
  end;
end;

function ParseMarkdownSegments(const AMarkdown: string): TArray<TMarkdownSegment>;
var
  Lines: TArray<string>;
  i, SegCount: Integer;
  InCode: Boolean;
  CurrentLang: string;
  Seg: TMarkdownSegment;
  SB: TStringBuilder;
  Line: string;
  Temp: TArray<TMarkdownSegment>;

  procedure FlushText;
  begin
    if (SB <> nil) and (SB.Length > 0) then
    begin
      Seg.Kind := mskText;
      Seg.Text := SB.ToString;
      Seg.Language := '';
      if SegCount >= Length(Temp) then
        SetLength(Temp, Length(Temp) * 2);
      Temp[SegCount] := Seg;
      Inc(SegCount);
      SB.Clear;
    end;
  end;

  procedure FlushCode;
  begin
    if (SB <> nil) and (SB.Length > 0) then
    begin
      Seg.Kind := mskCodeBlock;
      Seg.Text := SB.ToString;
      Seg.Language := CurrentLang;
      if SegCount >= Length(Temp) then
        SetLength(Temp, Length(Temp) * 2);
      Temp[SegCount] := Seg;
      Inc(SegCount);
      SB.Clear;
    end;
  end;

begin
  SegCount := 0;
  SetLength(Temp, 32);  // pre-allocate
  InCode := False;
  CurrentLang := '';
  SB := TStringBuilder.Create;
  try
    Lines := AMarkdown.Split([#10]);
    for i := 0 to High(Lines) do
    begin
      Line := Lines[i];
      if (Length(Line) > 0) and (Line[Length(Line)] = #13) then
        Line := Copy(Line, 1, Length(Line) - 1);

      if InCode then
      begin
        if Line.StartsWith('```') then
        begin
          // Close code block
          FlushCode;
          InCode := False;
          CurrentLang := '';
        end
        else
        begin
          if SB.Length > 0 then SB.AppendLine;
          SB.Append(Line);
        end;
      end
      else
      begin
        if Line.StartsWith('```') then
        begin
          // Open code block
          FlushText;
          InCode := True;
          // Extract language identifier
          CurrentLang := Copy(Line, 4, MaxInt).Trim;
          if (CurrentLang <> '') and (CurrentLang[1] = '`') then
            CurrentLang := '';
        end
        else
        begin
          if SB.Length > 0 then SB.AppendLine;
          SB.Append(Line);
        end;
      end;
    end;

    // Flush remaining
    if InCode then
      FlushCode
    else
      FlushText;
  finally
    SB.Free;
  end;

  SetLength(Temp, SegCount);
  Result := Temp;
end;

end.
