unit Core.ToolResultSlim;

interface

uses
  System.SysUtils, Core.Messages, Utils.TokenEstimator;

/// <summary>
/// Slim large tool results to reduce context size.
/// Keeps error results intact. Truncates large successful tool outputs
/// to head + tail with an omission marker.
/// </summary>
function SlimToolResults(AMessages: TAgentMessageList;
  AMaxResultChars: Integer = 2000): TAgentMessageList;

implementation

const
  SLIM_HEAD_LINES = 3;
  SLIM_TAIL_LINES = 3;

function ExtractTextFromContent(AContent: TContentBlockList): string;
var
  i: Integer;
begin
  Result := '';
  if AContent = nil then
    Exit;
  for i := 0 to AContent.Count - 1 do
    if AContent[i].ContentType = cbtText then
      Result := Result + TTextContent(AContent[i]).Text;
end;

function SplitLines(const AText: string): TArray<string>;
var
  Start, Pos_, Count, Capacity: Integer;
  Line: string;
begin
  Result := nil;
  if AText = '' then
    Exit;
  Capacity := 64;
  SetLength(Result, Capacity);
  Count := 0;
  Start := 1;
  for Pos_ := 1 to Length(AText) do
  begin
    if AText[Pos_] = #10 then
    begin
      Line := Copy(AText, Start, Pos_ - Start);
      if (Length(Line) > 0) and (Line[Length(Line)] = #13) then
        Line := Copy(Line, 1, Length(Line) - 1);
      if Count >= Capacity then
      begin
        Capacity := Capacity * 2;
        SetLength(Result, Capacity);
      end;
      Result[Count] := Line;
      Inc(Count);
      Start := Pos_ + 1;
    end;
  end;
  // Last line (no trailing LF)
  if Start <= Length(AText) then
  begin
    if Count >= Capacity then
    begin
      Capacity := Capacity + 1;
      SetLength(Result, Capacity);
    end;
    Result[Count] := Copy(AText, Start, MaxInt);
    Inc(Count);
  end;
  SetLength(Result, Count);
end;

function SlimToolResults(AMessages: TAgentMessageList;
  AMaxResultChars: Integer): TAgentMessageList;
var
  i: Integer;
  Msg: TAgentMessage;
  ToolMsg: TToolResultMessage;
  FullText, SlimmedText: string;
  Lines: TArray<string>;
  HeadCount, TailCount, Omitted: Integer;
  SB: TStringBuilder;
begin
  Result := TAgentMessageList.Create;

  for i := 0 to AMessages.Count - 1 do
  begin
    Msg := AMessages[i];

    if Msg.Role <> mrToolResult then
    begin
      // Non-tool messages: clone as-is
      Result.Add(Msg.Clone);
      Continue;
    end;

    ToolMsg := TToolResultMessage(Msg);

    // Never slim error results
    if ToolMsg.IsError then
    begin
      Result.Add(ToolMsg.Clone);
      Continue;
    end;

    FullText := ExtractTextFromContent(ToolMsg.Content);

    // Small enough - keep as-is
    if Length(FullText) <= AMaxResultChars then
    begin
      Result.Add(ToolMsg.Clone);
      Continue;
    end;

    // Slim: keep first 3 lines + ... + last 3 lines
    Lines := SplitLines(FullText);
    if Length(Lines) <= (SLIM_HEAD_LINES + SLIM_TAIL_LINES) then
    begin
      // Even though total chars exceeds, lines are few - just truncate
      SlimmedText := Copy(FullText, 1, AMaxResultChars) +
        #13#10'... (truncated)';
    end
    else
    begin
      HeadCount := SLIM_HEAD_LINES;
      TailCount := SLIM_TAIL_LINES;
      Omitted := Length(Lines) - HeadCount - TailCount;

      SB := TStringBuilder.Create;
      try
        for var j := 0 to HeadCount - 1 do
        begin
          if j > 0 then SB.AppendLine;
          SB.Append(Lines[j]);
        end;
        SB.AppendLine;
        SB.Append(Format('... (%d lines omitted) ...', [Omitted]));
        SB.AppendLine;
        for var j := Length(Lines) - TailCount to High(Lines) do
        begin
          SB.AppendLine;
          SB.Append(Lines[j]);
        end;
        SlimmedText := SB.ToString;
      finally
        SB.Free;
      end;
    end;

    // Create new ToolResultMessage with slimmed content
    var NewContent := TContentBlockList.Create;
    NewContent.Add(TTextContent.Create(SlimmedText));
    var NewMsg := TToolResultMessage.Create(
      ToolMsg.ToolCallId, ToolMsg.ToolName, NewContent, False);
    NewMsg.Timestamp := ToolMsg.Timestamp;
    Result.Add(NewMsg);
  end;
end;

end.
