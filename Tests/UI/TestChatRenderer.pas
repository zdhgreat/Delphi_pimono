unit TestChatRenderer;

{ Tests for UI.ChatRenderer standalone pure functions }

interface

uses
  System.SysUtils,
  UI.ChatRenderer,
  PiMonoTestFramework;

procedure RegisterChatRendererTests;

implementation

type
  TTestNormalizeLineBreaks = class
  public
    procedure Test_CRLF_Unchanged;
    procedure Test_LF_ToCRLF;
    procedure Test_CR_ToCRLF;
    procedure Test_MixedLineBreaks;
    procedure Test_EmptyString;
    procedure Test_NoLineBreaks;
    procedure Test_MultipleLF;
    procedure Test_CRNotFollowedByLF;
    procedure Test_CRLFCRLF;
  end;

  TTestExtractSessionLabel = class
  public
    procedure Test_ShortText_NoTruncation;
    procedure Test_LongText_Truncated;
    procedure Test_EmptyString;
    procedure Test_WhitespaceOnly;
    procedure Test_Multiline_TakesFirstLine;
    procedure Test_ExactMaxLength_NoTruncation;
    procedure Test_CustomMaxLen;
    procedure Test_WordBoundaryTruncation;
  end;

{ TTestNormalizeLineBreaks }

procedure TTestNormalizeLineBreaks.Test_CRLF_Unchanged;
var
  S: string;
begin
  S := 'Hello'#13#10'World';
  Assert(NormalizeLineBreaks(S) = 'Hello'#13#10'World', 'CRLF should remain unchanged');
end;

procedure TTestNormalizeLineBreaks.Test_LF_ToCRLF;
var
  S: string;
begin
  S := 'Hello'#10'World';
  Assert(NormalizeLineBreaks(S) = 'Hello'#13#10'World', 'LF should become CRLF');
end;

procedure TTestNormalizeLineBreaks.Test_CR_ToCRLF;
var
  S: string;
begin
  S := 'Hello'#13'World';
  Assert(NormalizeLineBreaks(S) = 'Hello'#13#10'World', 'CR should become CRLF');
end;

procedure TTestNormalizeLineBreaks.Test_MixedLineBreaks;
var
  S: string;
begin
  S := 'A'#13#10'B'#10'C'#13'D';
  Assert(NormalizeLineBreaks(S) = 'A'#13#10'B'#13#10'C'#13#10'D', 'Mixed should all become CRLF');
end;

procedure TTestNormalizeLineBreaks.Test_EmptyString;
begin
  Assert(NormalizeLineBreaks('') = '', 'Empty string should remain empty');
end;

procedure TTestNormalizeLineBreaks.Test_NoLineBreaks;
begin
  Assert(NormalizeLineBreaks('Hello World') = 'Hello World', 'No breaks unchanged');
end;

procedure TTestNormalizeLineBreaks.Test_MultipleLF;
var
  S: string;
begin
  S := 'Line1'#10'Line2'#10'Line3';
  Assert(NormalizeLineBreaks(S) = 'Line1'#13#10'Line2'#13#10'Line3', 'Multiple LF all converted');
end;

procedure TTestNormalizeLineBreaks.Test_CRNotFollowedByLF;
var
  S: string;
begin
  S := 'Hello'#13'World';
  Assert(NormalizeLineBreaks(S) = 'Hello'#13#10'World', 'CR alone becomes CRLF');
end;

procedure TTestNormalizeLineBreaks.Test_CRLFCRLF;
var
  S: string;
begin
  S := 'A'#13#10#13#10'B';
  Assert(NormalizeLineBreaks(S) = 'A'#13#10#13#10'B', 'CRLF+CRLF preserved as is');
end;

{ TTestExtractSessionLabel }

procedure TTestExtractSessionLabel.Test_ShortText_NoTruncation;
var
  R: string;
begin
  R := ExtractSessionLabelText('Hello World');
  Assert(R = 'Hello World', 'Short text should not be truncated, got: ' + R);
end;

procedure TTestExtractSessionLabel.Test_LongText_Truncated;
var
  R: string;
begin
  R := ExtractSessionLabelText('This is a very long session label that definitely exceeds the forty character default limit');
  Assert(Length(R) <= 43, 'Truncated + "..." should be <= 43 chars, got ' + IntToStr(Length(R)));
  Assert(R.EndsWith('...'), 'Truncated text should end with ...');
  Assert(Pos('very long session', R) > 0, 'Should contain start of text');
end;

procedure TTestExtractSessionLabel.Test_EmptyString;
var
  R: string;
begin
  R := ExtractSessionLabelText('');
  Assert(R = '', 'Empty string should return empty, got: "' + R + '"');
end;

procedure TTestExtractSessionLabel.Test_WhitespaceOnly;
var
  R: string;
begin
  R := ExtractSessionLabelText('   ');
  Assert(R = '', 'Whitespace only should return empty, got: "' + R + '"');
end;

procedure TTestExtractSessionLabel.Test_Multiline_TakesFirstLine;
var
  R: string;
begin
  R := ExtractSessionLabelText('First Line'#10'Second Line');
  Assert(R = 'First Line', 'Should take only first line, got: ' + R);
end;

procedure TTestExtractSessionLabel.Test_ExactMaxLength_NoTruncation;
var
  S: string;
  R: string;
begin
  S := '1234567890123456789012345678901234567890'; // exactly 40 chars
  R := ExtractSessionLabelText(S);
  Assert(R = S, 'Exactly 40 chars should not be truncated, got: ' + R);
end;

procedure TTestExtractSessionLabel.Test_CustomMaxLen;
var
  R: string;
begin
  R := ExtractSessionLabelText('This is a string that is longer than twenty characters', 20);
  Assert(R.EndsWith('...'), 'Should end with ... with custom max, got: ' + R);
  Assert(Length(R) <= 23, 'Truncated with maxLen=20 should be <= 23 chars, got ' + IntToStr(Length(R)));
end;

procedure TTestExtractSessionLabel.Test_WordBoundaryTruncation;
var
  R: string;
begin
  R := ExtractSessionLabelText('The quick brown fox jumps over the lazy dog and keeps going');
  Assert(R.EndsWith('...'), 'Should end with ..., got: ' + R);
  // Should break at a word boundary, not mid-word
  Assert(Pos('...', R) > 0, 'Should contain ...');
  Assert(R.Length < 43, 'Total length with ... should be reasonable');
end;

{ Registration }

procedure RegisterChatRendererTests;
var
  TNL: TTestNormalizeLineBreaks;
  TSL: TTestExtractSessionLabel;
begin
  TNL := TTestNormalizeLineBreaks.Create;
  try
    GRunner.RunTest('ChatRenderer.NormalizeLineBreaks: CRLF unchanged', TNL.Test_CRLF_Unchanged);
    GRunner.RunTest('ChatRenderer.NormalizeLineBreaks: LF to CRLF', TNL.Test_LF_ToCRLF);
    GRunner.RunTest('ChatRenderer.NormalizeLineBreaks: CR to CRLF', TNL.Test_CR_ToCRLF);
    GRunner.RunTest('ChatRenderer.NormalizeLineBreaks: Mixed', TNL.Test_MixedLineBreaks);
    GRunner.RunTest('ChatRenderer.NormalizeLineBreaks: Empty', TNL.Test_EmptyString);
    GRunner.RunTest('ChatRenderer.NormalizeLineBreaks: No breaks', TNL.Test_NoLineBreaks);
    GRunner.RunTest('ChatRenderer.NormalizeLineBreaks: Multiple LF', TNL.Test_MultipleLF);
    GRunner.RunTest('ChatRenderer.NormalizeLineBreaks: CR alone', TNL.Test_CRNotFollowedByLF);
    GRunner.RunTest('ChatRenderer.NormalizeLineBreaks: CRLF CRLF', TNL.Test_CRLFCRLF);
  finally
    TNL.Free;
  end;

  TSL := TTestExtractSessionLabel.Create;
  try
    GRunner.RunTest('ChatRenderer.ExtractSessionLabel: Short text', TSL.Test_ShortText_NoTruncation);
    GRunner.RunTest('ChatRenderer.ExtractSessionLabel: Long text', TSL.Test_LongText_Truncated);
    GRunner.RunTest('ChatRenderer.ExtractSessionLabel: Empty', TSL.Test_EmptyString);
    GRunner.RunTest('ChatRenderer.ExtractSessionLabel: Whitespace', TSL.Test_WhitespaceOnly);
    GRunner.RunTest('ChatRenderer.ExtractSessionLabel: Multiline', TSL.Test_Multiline_TakesFirstLine);
    GRunner.RunTest('ChatRenderer.ExtractSessionLabel: Exact max', TSL.Test_ExactMaxLength_NoTruncation);
    GRunner.RunTest('ChatRenderer.ExtractSessionLabel: Custom max', TSL.Test_CustomMaxLen);
    GRunner.RunTest('ChatRenderer.ExtractSessionLabel: Word boundary', TSL.Test_WordBoundaryTruncation);
  finally
    TSL.Free;
  end;
end;

end.
