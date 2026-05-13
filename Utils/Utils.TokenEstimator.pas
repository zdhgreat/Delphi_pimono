unit Utils.TokenEstimator;

interface

uses
  System.Math, System.JSON, Core.Messages;

/// <summary>Estimate tokens for raw text using chars/4 heuristic</summary>
function EstimateTokens(const AText: string): Integer;

/// <summary>Estimate tokens for a single message</summary>
function EstimateMessageTokens(AMessage: TAgentMessage): Integer;

/// <summary>Estimate total tokens for all messages in a list</summary>
function EstimateContextTokens(AMessages: TAgentMessageList): Integer;

/// <summary>Hybrid estimation: use real Usage data when available, chars/4 for remainder</summary>
function EstimateContextTokensFromUsage(AMessages: TAgentMessageList): Integer;

implementation

function EstimateTokens(const AText: string): Integer;
var
  i, AsciiCount, CjkCount: Integer;
  Code: Word;
begin
  if AText = '' then
    Exit(0);

  // Count ASCII vs CJK characters for better estimation
  AsciiCount := 0;
  CjkCount := 0;
  i := 1;
  while i <= Length(AText) do
  begin
    Code := Ord(AText[i]);
    // Handle surrogate pairs: skip low surrogate, count pair as one CJK char
    if (Code >= $D800) and (Code <= $DBFF) then
    begin
      Inc(CjkCount);
      Inc(i, 2);  // skip high + low surrogate
      Continue;
    end;
    // Skip lone low surrogate (shouldn't happen in valid UTF-16)
    if (Code >= $DC00) and (Code <= $DFFF) then
    begin
      Inc(i);
      Continue;
    end;
    if Code >= $4E00 then
      Inc(CjkCount)
    else
      Inc(AsciiCount);
    Inc(i);
  end;

  // ASCII: ~4 chars per token, CJK: ~1.5 chars per token
  Result := Max(1, (AsciiCount div 4) + Round(CjkCount / 1.5));
end;

function EstimateMessageTokens(AMessage: TAgentMessage): Integer;
var
  i: Integer;
  S: string;
begin
  Result := 0;
  if AMessage = nil then
    Exit;

  case AMessage.Role of
    mrUser:
    begin
      var UserMsg := TUserMessage(AMessage);
      if UserMsg.HasStructuredContent and (UserMsg.ContentBlocks <> nil) then
      begin
        for i := 0 to UserMsg.ContentBlocks.Count - 1 do
          if UserMsg.ContentBlocks[i].ContentType = cbtText then
            Result := Result + EstimateTokens(TTextContent(UserMsg.ContentBlocks[i]).Text);
      end
      else
        Result := EstimateTokens(UserMsg.Content);
    end;

    mrAssistant:
    begin
      var AsstMsg := TAssistantMessage(AMessage);
      for i := 0 to AsstMsg.Content.Count - 1 do
      begin
        case AsstMsg.Content[i].ContentType of
          cbtText:
            Result := Result + EstimateTokens(TTextContent(AsstMsg.Content[i]).Text);
          cbtThinking:
            Result := Result + EstimateTokens(TThinkingContent(AsstMsg.Content[i]).Thinking);
          cbtToolCall:
          begin
            var TC := TToolCall(AsstMsg.Content[i]);
            S := TC.Name;
            if TC.Arguments <> nil then
              S := S + TC.Arguments.ToJSON;
            Result := Result + EstimateTokens(S);
          end;
        end;
      end;
    end;

    mrToolResult:
    begin
      var ToolMsg := TToolResultMessage(AMessage);
      if ToolMsg.Content <> nil then
      begin
        for i := 0 to ToolMsg.Content.Count - 1 do
          if ToolMsg.Content[i].ContentType = cbtText then
            Result := Result + EstimateTokens(TTextContent(ToolMsg.Content[i]).Text);
      end;
    end;
  end;

  // Minimum 1 token per message (overhead for role/metadata)
  if Result = 0 then
    Result := 1;
end;

function EstimateContextTokens(AMessages: TAgentMessageList): Integer;
var
  i: Integer;
begin
  Result := 0;
  if AMessages = nil then
    Exit;
  for i := 0 to AMessages.Count - 1 do
    Result := Result + EstimateMessageTokens(AMessages[i]);
end;

function EstimateContextTokensFromUsage(AMessages: TAgentMessageList): Integer;
var
  i, LastUsageIdx: Integer;
  UsageTokens: Integer;
begin
  UsageTokens := 0;
  if (AMessages = nil) or (AMessages.Count = 0) then
    Exit(0);

  // Find the last assistant message that has real usage data
  LastUsageIdx := -1;
  for i := AMessages.Count - 1 downto 0 do
  begin
    if AMessages[i].Role = mrAssistant then
    begin
      var Usage := TAssistantMessage(AMessages[i]).Usage;
      if Usage.TotalTokens > 0 then
      begin
        LastUsageIdx := i;
        UsageTokens := Usage.TotalTokens;
        Break;
      end;
    end;
  end;

  if LastUsageIdx < 0 then
    // No usage data - fall back to pure estimation
    Exit(EstimateContextTokens(AMessages));

  // Use real usage + estimate remaining messages after it
  Result := UsageTokens;
  for i := LastUsageIdx + 1 to AMessages.Count - 1 do
    Result := Result + EstimateMessageTokens(AMessages[i]);
end;

end.
