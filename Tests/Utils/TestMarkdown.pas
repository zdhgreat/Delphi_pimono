unit TestMarkdown;

interface

uses
  System.SysUtils,
  Utils.Markdown,
  PiMonoTestFramework;

procedure RegisterMarkdownTests;

implementation

type
  TTestMarkdown = class
  public
    // ExtractCodeBlocks
    procedure Test_ExtractCodeBlocks_Single;
    procedure Test_ExtractCodeBlocks_Multiple;
    procedure Test_ExtractCodeBlocks_WithLanguage;
    procedure Test_ExtractCodeBlocks_NoBlocks;
    procedure Test_ExtractCodeBlocks_Unclosed;
    procedure Test_ExtractCodeBlocks_EmptyBlock;
    procedure Test_ExtractCodeBlocks_NestedInText;

    // HasCodeBlocks
    procedure Test_HasCodeBlocks_True;
    procedure Test_HasCodeBlocks_False;
    procedure Test_HasCodeBlocks_Unclosed_False;

    // ParseMarkdownSegments
    procedure Test_ParseSegments_TextOnly;
    procedure Test_ParseSegments_CodeOnly;
    procedure Test_ParseSegments_Mixed;
    procedure Test_ParseSegments_LanguageExtracted;
    procedure Test_ParseSegments_MultipleCodeBlocks;
    procedure Test_ParseSegments_EmptyInput;
  end;

{ TTestMarkdown }

{ ExtractCodeBlocks }

procedure TTestMarkdown.Test_ExtractCodeBlocks_Single;
var
  Blocks: TArray<string>;
begin
  var Md := 'Before' + #10 + '```' + #10 + 'code here' + #10 + '```' + #10 + 'After';
  Blocks := ExtractCodeBlocks(Md);
  Assert(Length(Blocks) = 1, 'Should have 1 code block');
  Assert(Blocks[0].Trim = 'code here', 'Content should be "code here"');
end;

procedure TTestMarkdown.Test_ExtractCodeBlocks_Multiple;
var
  Blocks: TArray<string>;
begin
  var Md := '```' + #10 + 'block1' + #10 + '```' + #10 +
            'text' + #10 +
            '```' + #10 + 'block2' + #10 + '```';
  Blocks := ExtractCodeBlocks(Md);
  Assert(Length(Blocks) = 2, 'Should have 2 code blocks');
  Assert(Blocks[0].Trim = 'block1', 'First block should be block1');
  Assert(Blocks[1].Trim = 'block2', 'Second block should be block2');
end;

procedure TTestMarkdown.Test_ExtractCodeBlocks_WithLanguage;
var
  Blocks: TArray<string>;
begin
  var Md := '```pascal' + #10 + 'WriteLn(''Hello'');' + #10 + '```';
  Blocks := ExtractCodeBlocks(Md);
  Assert(Length(Blocks) = 1, 'Should have 1 code block');
  Assert(Pos('Hello', Blocks[0]) > 0, 'Should contain code content');
end;

procedure TTestMarkdown.Test_ExtractCodeBlocks_NoBlocks;
var
  Blocks: TArray<string>;
begin
  var Md := 'Just some text without code blocks.';
  Blocks := ExtractCodeBlocks(Md);
  Assert(Length(Blocks) = 0, 'Should have 0 code blocks');
end;

procedure TTestMarkdown.Test_ExtractCodeBlocks_Unclosed;
var
  Blocks: TArray<string>;
begin
  var Md := '```' + #10 + 'unclosed code';
  Blocks := ExtractCodeBlocks(Md);
  // Unclosed block should still be included
  Assert(Length(Blocks) >= 1, 'Unclosed block should be included');
end;

procedure TTestMarkdown.Test_ExtractCodeBlocks_EmptyBlock;
var
  Blocks: TArray<string>;
begin
  var Md := '```' + #10 + '```';
  Blocks := ExtractCodeBlocks(Md);
  Assert(Length(Blocks) = 1, 'Should have 1 empty code block');
end;

procedure TTestMarkdown.Test_ExtractCodeBlocks_NestedInText;
var
  Blocks: TArray<string>;
begin
  var Md := '# Title' + #10 + #10 +
            'Some paragraph text.' + #10 + #10 +
            '```python' + #10 + 'print("hello")' + #10 + '```' + #10 + #10 +
            'More text.';
  Blocks := ExtractCodeBlocks(Md);
  Assert(Length(Blocks) = 1, 'Should have 1 code block');
  Assert(Pos('print', Blocks[0]) > 0, 'Should contain code');
end;

{ HasCodeBlocks }

procedure TTestMarkdown.Test_HasCodeBlocks_True;
begin
  var Md := '```' + #10 + 'code' + #10 + '```';
  Assert(HasCodeBlocks(Md), 'Should have code blocks');
end;

procedure TTestMarkdown.Test_HasCodeBlocks_False;
begin
  var Md := 'No code here, just text.';
  Assert(not HasCodeBlocks(Md), 'Should not have code blocks');
end;

procedure TTestMarkdown.Test_HasCodeBlocks_Unclosed_False;
begin
  var Md := '```' + #10 + 'unclosed code';
  // Unclosed code block should NOT count as having code blocks
  Assert(not HasCodeBlocks(Md), 'Unclosed block should not count');
end;

{ ParseMarkdownSegments }

procedure TTestMarkdown.Test_ParseSegments_TextOnly;
var
  Segs: TArray<TMarkdownSegment>;
begin
  Segs := ParseMarkdownSegments('Just text');
  Assert(Length(Segs) = 1, 'Should have 1 segment');
  Assert(Segs[0].Kind = mskText, 'Should be text segment');
  Assert(Pos('Just text', Segs[0].Text) > 0, 'Should contain text');
end;

procedure TTestMarkdown.Test_ParseSegments_CodeOnly;
var
  Segs: TArray<TMarkdownSegment>;
begin
  var Md := '```pascal' + #10 + 'code' + #10 + '```';
  Segs := ParseMarkdownSegments(Md);
  Assert(Length(Segs) >= 1, 'Should have at least 1 segment');
  Assert(Segs[0].Kind = mskCodeBlock, 'Should be code block');
  Assert(Segs[0].Language = 'pascal', 'Language should be pascal');
end;

procedure TTestMarkdown.Test_ParseSegments_Mixed;
var
  Segs: TArray<TMarkdownSegment>;
  i, CodeCount, TextCount: Integer;
begin
  var Md := 'Before' + #10 + '```' + #10 + 'code' + #10 + '```' + #10 + 'After';
  Segs := ParseMarkdownSegments(Md);
  CodeCount := 0;
  TextCount := 0;
  for i := 0 to High(Segs) do
    if Segs[i].Kind = mskCodeBlock then
      Inc(CodeCount)
    else
      Inc(TextCount);
  Assert(CodeCount = 1, 'Should have 1 code block, got ' + IntToStr(CodeCount));
  Assert(TextCount >= 1, 'Should have at least 1 text segment');
end;

procedure TTestMarkdown.Test_ParseSegments_LanguageExtracted;
var
  Segs: TArray<TMarkdownSegment>;
begin
  var Md := '```javascript' + #10 + 'console.log("hi");' + #10 + '```';
  Segs := ParseMarkdownSegments(Md);
  Assert(Length(Segs) >= 1, 'Should have segments');
  if Length(Segs) > 0 then
    Assert(Segs[0].Language = 'javascript', 'Language should be javascript');
end;

procedure TTestMarkdown.Test_ParseSegments_MultipleCodeBlocks;
var
  Segs: TArray<TMarkdownSegment>;
  CodeCount, i: Integer;
begin
  var Md := '```a' + #10 + '1' + #10 + '```' + #10 +
            'text' + #10 +
            '```b' + #10 + '2' + #10 + '```';
  Segs := ParseMarkdownSegments(Md);
  CodeCount := 0;
  for i := 0 to High(Segs) do
    if Segs[i].Kind = mskCodeBlock then
      Inc(CodeCount);
  Assert(CodeCount = 2, 'Should have 2 code blocks, got ' + IntToStr(CodeCount));
end;

procedure TTestMarkdown.Test_ParseSegments_EmptyInput;
var
  Segs: TArray<TMarkdownSegment>;
begin
  Segs := ParseMarkdownSegments('');
  Assert(Length(Segs) = 0, 'Empty input should have 0 segments');
end;

{ Registration }

procedure RegisterMarkdownTests;
var
  T: TTestMarkdown;
begin
  T := TTestMarkdown.Create;
  try
    GRunner.RunTest('Markdown: ExtractCodeBlocks single', T.Test_ExtractCodeBlocks_Single);
    GRunner.RunTest('Markdown: ExtractCodeBlocks multiple', T.Test_ExtractCodeBlocks_Multiple);
    GRunner.RunTest('Markdown: ExtractCodeBlocks with language', T.Test_ExtractCodeBlocks_WithLanguage);
    GRunner.RunTest('Markdown: ExtractCodeBlocks no blocks', T.Test_ExtractCodeBlocks_NoBlocks);
    GRunner.RunTest('Markdown: ExtractCodeBlocks unclosed', T.Test_ExtractCodeBlocks_Unclosed);
    GRunner.RunTest('Markdown: ExtractCodeBlocks empty block', T.Test_ExtractCodeBlocks_EmptyBlock);
    GRunner.RunTest('Markdown: ExtractCodeBlocks nested in text', T.Test_ExtractCodeBlocks_NestedInText);
    GRunner.RunTest('Markdown: HasCodeBlocks true', T.Test_HasCodeBlocks_True);
    GRunner.RunTest('Markdown: HasCodeBlocks false', T.Test_HasCodeBlocks_False);
    GRunner.RunTest('Markdown: HasCodeBlocks unclosed false', T.Test_HasCodeBlocks_Unclosed_False);
    GRunner.RunTest('Markdown: ParseSegments text only', T.Test_ParseSegments_TextOnly);
    GRunner.RunTest('Markdown: ParseSegments code only', T.Test_ParseSegments_CodeOnly);
    GRunner.RunTest('Markdown: ParseSegments mixed', T.Test_ParseSegments_Mixed);
    GRunner.RunTest('Markdown: ParseSegments language', T.Test_ParseSegments_LanguageExtracted);
    GRunner.RunTest('Markdown: ParseSegments multiple code blocks', T.Test_ParseSegments_MultipleCodeBlocks);
    GRunner.RunTest('Markdown: ParseSegments empty input', T.Test_ParseSegments_EmptyInput);
  finally
    T.Free;
  end;
end;

end.
