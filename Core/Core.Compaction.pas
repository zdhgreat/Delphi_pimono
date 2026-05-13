unit Core.Compaction;

interface

uses
  System.SysUtils, System.StrUtils, System.JSON, System.Classes, System.Math,
  Core.Messages, Core.AgentState,
  AI.IModel, AI.ModelConfig,
  Utils.Logger, Utils.TokenEstimator;

type
  TFileOperation = record
    FilePath: string;
    Operation: (foRead, foWrite, foEdit);
  end;

  TCompactionPreparation = record
    MessagesToSummarize: TAgentMessageList;
    FirstKeptIndex: Integer;
    PreviousSummary: string;
    FileOps: TArray<TFileOperation>;
    TokensBefore: Integer;
  end;

  TCompactionResult = record
    Summary: string;
    FirstKeptIndex: Integer;
    TokensBefore: Integer;
    ReadFiles: TArray<string>;
    ModifiedFiles: TArray<string>;
  end;

  TCompaction = class
  public
    /// <summary>Check if compaction should be triggered</summary>
    class function ShouldCompact(AContextTokens, AContextWindow,
      AReserveTokens: Integer): Boolean;

    /// <summary>Prepare compaction: find cut point, collect messages to summarize</summary>
    class function Prepare(AMessages: TAgentMessageList;
      AKeepRecentTokens: Integer;
      const APreviousSummary: string): TCompactionPreparation;

    /// <summary>Execute compaction: call LLM to generate summary</summary>
    class function Execute(const APrep: TCompactionPreparation;
      AModel: IModel; const ASystemPrompt: string;
      AContextWindow: Integer;
      ALogger: TLogger): TCompactionResult;

    /// <summary>Apply compaction: replace old messages with summary</summary>
    class function Apply(AMessages: TAgentMessageList;
      const AResult: TCompactionResult): TAgentMessageList;

    /// <summary>Emergency truncation when context overflows (no LLM call)</summary>
    class function EmergencyCut(AMessages: TAgentMessageList;
      ARatio: Double = 0.5): TAgentMessageList;

    /// <summary>Extract file operations from tool calls in messages</summary>
    class function ExtractFileOps(AMessages: TAgentMessageList): TArray<TFileOperation>;

    /// <summary>Serialize messages to plain text for the summarization prompt</summary>
    class function SerializeConversation(AMessages: TAgentMessageList): string;

    /// <summary>Check if an error message indicates context overflow</summary>
    class function IsContextOverflow(const AError: string): Boolean;
  end;

implementation

{$WARN IMPLICIT_STRING_CAST OFF}

const
  COMPACTION_SUMMARY_PREFIX = '[上下文摘要 - 由系统自动生成]';
  MAX_SERIALIZATION_CHARS = 80000;  // ~20K tokens worth of text
  SUMMARIZATION_SYSTEM_PROMPT =
    '你是一个专业的对话摘要助手。你的任务是阅读 AI 代码助手与用户的对话，' +
    '然后按照指定格式生成结构化摘要。' +
    '不要继续对话。不要回答对话中的任何问题。只输出结构化摘要。';

  SUMMARIZATION_PROMPT =
    '以下是 AI 代码助手与用户的完整对话历史。请生成结构化摘要，让另一个 AI 助手能无缝继续工作。' + #13#10 + #13#10 +
    '规则：' + #13#10 +
    '1. 保留所有文件路径、函数名、变量名、错误信息的原文' + #13#10 +
    '2. 不要继续对话，只生成摘要' + #13#10 +
    '3. 每个部分保持简洁' + #13#10 +
    '4. 如果某部分没有相关内容，写"(无)"' + #13#10 + #13#10 +
    '使用以下格式：' + #13#10 + #13#10 +
    '## 当前任务' + #13#10 +
    '{一句话：用户当前正在做什么}' + #13#10 + #13#10 +
    '## 已修改文件' + #13#10 +
    '- {路径}: {做了什么修改}' + #13#10 +
    '{如果没有修改过文件，写"(无)"}' + #13#10 + #13#10 +
    '## 进展' + #13#10 +
    '### 已完成' + #13#10 +
    '- [x] {具体事项}' + #13#10 +
    '### 进行中' + #13#10 +
    '- [ ] {正在做但未完成的事项}' + #13#10 +
    '### 受阻' + #13#10 +
    '- {阻碍因素}' + #13#10 + #13#10 +
    '## 关键决策' + #13#10 +
    '- **{决策}**: {原因}' + #13#10 + #13#10 +
    '## 用户约束' + #13#10 +
    '- {用户明确表达的偏好或要求}' + #13#10 + #13#10 +
    '## 未解决错误' + #13#10 +
    '- {错误信息和关键堆栈行}' + #13#10 + #13#10 +
    '## 关键代码上下文' + #13#10 +
    '{当前正在工作的核心代码片段，控制在 300 字以内}' + #13#10 + #13#10 +
    '## 下一步' + #13#10 +
    '1. {接下来应该做什么}';

  UPDATE_SUMMARIZATION_PROMPT =
    '以下是新的对话消息，需要合并到已有摘要中。' + #13#10 + #13#10 +
    '规则：' + #13#10 +
    '1. 保留已有摘要中的所有信息' + #13#10 +
    '2. 添加新的进展、决策和上下文' + #13#10 +
    '3. 更新"进展"：将完成的事项从"进行中"移到"已完成"' + #13#10 +
    '4. 更新"下一步"：基于最新进展调整' + #13#10 +
    '5. 保留所有文件路径、函数名、错误信息的原文' + #13#10 +
    '6. 已过时的信息可以移除' + #13#10 +
    '7. "已修改文件"列表只增不减（累积记录）' + #13#10 + #13#10 +
    '<previous-summary>' + #13#10 +
    '%s' + #13#10 +
    '</previous-summary>' + #13#10 + #13#10 +
    '使用以下格式：' + #13#10 + #13#10 +
    '## 当前任务' + #13#10 +
    '{一句话：用户当前正在做什么}' + #13#10 + #13#10 +
    '## 已修改文件' + #13#10 +
    '- {路径}: {做了什么修改}' + #13#10 + #13#10 +
    '## 进展' + #13#10 +
    '### 已完成' + #13#10 +
    '- [x] {具体事项}' + #13#10 +
    '### 进行中' + #13#10 +
    '- [ ] {正在做但未完成的事项}' + #13#10 +
    '### 受阻' + #13#10 +
    '- {阻碍因素}' + #13#10 + #13#10 +
    '## 关键决策' + #13#10 +
    '- **{决策}**: {原因}' + #13#10 + #13#10 +
    '## 用户约束' + #13#10 +
    '- {用户明确表达的偏好或要求}' + #13#10 + #13#10 +
    '## 未解决错误' + #13#10 +
    '- {错误信息和关键堆栈行}' + #13#10 + #13#10 +
    '## 关键代码上下文' + #13#10 +
    '{当前正在工作的核心代码片段，控制在 300 字以内}' + #13#10 + #13#10 +
    '## 下一步' + #13#10 +
    '1. {接下来应该做什么}';

{ TCompaction }

class function TCompaction.ShouldCompact(AContextTokens, AContextWindow,
  AReserveTokens: Integer): Boolean;
begin
  Result := (AContextWindow > 0) and
    (AContextTokens >= (AContextWindow - AReserveTokens));
end;

class function TCompaction.Prepare(AMessages: TAgentMessageList;
  AKeepRecentTokens: Integer;
  const APreviousSummary: string): TCompactionPreparation;
var
  i: Integer;
  Accumulated, TotalTokens: Integer;
  CutIndex: Integer;
  PrevCompactionIdx: Integer;
begin
  // Initialize
  Result.MessagesToSummarize := nil;
  Result.FirstKeptIndex := -1;
  Result.PreviousSummary := APreviousSummary;
  Result.FileOps := nil;
  Result.TokensBefore := 0;

  if (AMessages = nil) or (AMessages.Count = 0) then
    Exit;

  // Calculate total tokens
  TotalTokens := EstimateContextTokens(AMessages);
  Result.TokensBefore := TotalTokens;

  // Find the last compaction summary message
  PrevCompactionIdx := -1;
  for i := 0 to AMessages.Count - 1 do
  begin
    if (AMessages[i].Role = mrUser) and
       TUserMessage(AMessages[i]).IsCompactionSummary then
      PrevCompactionIdx := i;
  end;

  // Walk backwards from newest message, accumulating tokens
  Accumulated := 0;
  CutIndex := -1;

  for i := AMessages.Count - 1 downto 0 do
  begin
    Accumulated := Accumulated + EstimateMessageTokens(AMessages[i]);

    if Accumulated >= AKeepRecentTokens then
    begin
      // Found the rough cut point. Now snap to a valid position.
      // Valid cut: must be at a UserMessage (not ToolResult)
      CutIndex := i;

      // Walk forward from CutIndex to find the nearest UserMessage
      while (CutIndex < AMessages.Count) and
            (AMessages[CutIndex].Role = mrToolResult) do
        Inc(CutIndex);

      // If we went past the end, no valid cut found
      if CutIndex >= AMessages.Count then
      begin
        // Keep everything, can't compact
        Exit;
      end;

      Break;
    end;
  end;

  // If we didn't accumulate enough, no compaction needed
  if CutIndex < 0 then
    Exit;

  // Don't cut before/at the previous compaction
  if (PrevCompactionIdx >= 0) and (CutIndex <= PrevCompactionIdx) then
    Exit;

  // Collect messages to summarize (from start to CutIndex-1)
  Result.MessagesToSummarize := TAgentMessageList.Create;
  for i := 0 to CutIndex - 1 do
    Result.MessagesToSummarize.Add(AMessages[i].Clone);

  Result.FirstKeptIndex := CutIndex;

  // Extract file operations from messages being summarized
  Result.FileOps := ExtractFileOps(Result.MessagesToSummarize);
end;

class function TCompaction.Execute(const APrep: TCompactionPreparation;
  AModel: IModel; const ASystemPrompt: string;
  AContextWindow: Integer;
  ALogger: TLogger): TCompactionResult;
var
  ConversationText, Prompt, UserPrompt: string;
  Request: TCompletionRequest;
  ApiMessages: TArray<TApiChatMessage>;
  SummaryMsg: TAssistantMessage;
  MaxSummaryTokens: Integer;
  FileOpsXml: string;
  i: Integer;
  ReadSet, ModSet: TArray<string>;
begin
  Result.Summary := '';
  Result.FirstKeptIndex := APrep.FirstKeptIndex;
  Result.TokensBefore := APrep.TokensBefore;
  Result.ReadFiles := nil;
  Result.ModifiedFiles := nil;

  if (APrep.MessagesToSummarize = nil) or
     (APrep.MessagesToSummarize.Count = 0) or
     (AModel = nil) then
    Exit;

  // Serialize conversation to text
  ConversationText := SerializeConversation(APrep.MessagesToSummarize);

  // Classify file operations
  ReadSet := nil;
  ModSet := nil;
  for i := 0 to High(APrep.FileOps) do
  begin
    case APrep.FileOps[i].Operation of
      foRead:
      begin
        SetLength(ReadSet, Length(ReadSet) + 1);
        ReadSet[High(ReadSet)] := APrep.FileOps[i].FilePath;
      end;
      foWrite, foEdit:
      begin
        SetLength(ModSet, Length(ModSet) + 1);
        ModSet[High(ModSet)] := APrep.FileOps[i].FilePath;
      end;
    end;
  end;

  // Build file operations XML appendix
  FileOpsXml := '';
  if Length(ReadSet) > 0 then
  begin
    FileOpsXml := FileOpsXml + '<read-files>' + #13#10;
    for i := 0 to High(ReadSet) do
      FileOpsXml := FileOpsXml + ReadSet[i] + #13#10;
    FileOpsXml := FileOpsXml + '</read-files>' + #13#10;
  end;
  if Length(ModSet) > 0 then
  begin
    FileOpsXml := FileOpsXml + '<modified-files>' + #13#10;
    for i := 0 to High(ModSet) do
      FileOpsXml := FileOpsXml + ModSet[i] + #13#10;
    FileOpsXml := FileOpsXml + '</modified-files>';
  end;

  // Build the prompt
  if APrep.PreviousSummary <> '' then
    Prompt := Format(UPDATE_SUMMARIZATION_PROMPT, [APrep.PreviousSummary])
  else
    Prompt := SUMMARIZATION_PROMPT;

  UserPrompt := '<conversation>' + #13#10 +
    ConversationText + #13#10 +
    '</conversation>' + #13#10 + #13#10 +
    Prompt;

  // Call LLM to generate summary
  MaxSummaryTokens := Floor(0.8 * AContextWindow * 0.1);  // ~10% of context window, capped
  if MaxSummaryTokens > 16384 then
    MaxSummaryTokens := 16384;
  if MaxSummaryTokens < 2048 then
    MaxSummaryTokens := 2048;

  try
    ApiMessages := nil;
    SetLength(ApiMessages, 2);
    ApiMessages[0] := TApiChatMessage.CreateSystem(SUMMARIZATION_SYSTEM_PROMPT);
    ApiMessages[1] := TApiChatMessage.CreateUser(UserPrompt);

    Request := TCompletionRequest.Create;
    Request.Model := AModel.GetName;
    Request.Messages := ApiMessages;
    Request.Tools := nil;
    Request.MaxTokens := MaxSummaryTokens;
    Request.Temperature := 0.3;  // Low temperature for factual summaries
    Request.Stream := False;
    Request.SystemPrompt := '';

    SummaryMsg := AModel.Complete(Request);

    try
      if SummaryMsg <> nil then
      begin
        // Extract text content
        Result.Summary := '';
        for i := 0 to SummaryMsg.Content.Count - 1 do
          if SummaryMsg.Content[i].ContentType = cbtText then
            Result.Summary := Result.Summary +
              TTextContent(SummaryMsg.Content[i]).Text;

        // Append file operations XML
        if FileOpsXml <> '' then
          Result.Summary := Result.Summary + #13#10 + #13#10 + FileOpsXml;
      end;
    finally
      SummaryMsg.Free;
    end;
  except
    on E: Exception do
    begin
      if ALogger <> nil then
        ALogger.LogException(E, 'Compaction summarization failed');
      // Return a basic fallback summary
      Result.Summary := COMPACTION_SUMMARY_PREFIX + #13#10 +
        '## 注意' + #13#10 +
        '自动摘要生成失败: ' + E.Message + #13#10 +
        '以下是对话的简要回顾。' + #13#10;
      if FileOpsXml <> '' then
        Result.Summary := Result.Summary + #13#10 + FileOpsXml;
    end;
  end;

  Result.ReadFiles := ReadSet;
  Result.ModifiedFiles := ModSet;
end;

class function TCompaction.Apply(AMessages: TAgentMessageList;
  const AResult: TCompactionResult): TAgentMessageList;
var
  i: Integer;
  SummaryMsg: TUserMessage;
begin
  Result := TAgentMessageList.Create;

  // Add the compaction summary as a special user message
  SummaryMsg := TUserMessage.Create(COMPACTION_SUMMARY_PREFIX + #13#10 +
    AResult.Summary);
  SummaryMsg.IsCompactionSummary := True;
  SummaryMsg.Timestamp := Now;
  Result.Add(SummaryMsg);

  // Append kept messages (from FirstKeptIndex onwards)
  if AResult.FirstKeptIndex >= 0 then
  begin
    for i := AResult.FirstKeptIndex to AMessages.Count - 1 do
      Result.Add(AMessages[i].Clone);
  end
  else
  begin
    // No cut was made - keep all messages
    for i := 0 to AMessages.Count - 1 do
      Result.Add(AMessages[i].Clone);
  end;
end;

class function TCompaction.EmergencyCut(AMessages: TAgentMessageList;
  ARatio: Double): TAgentMessageList;
var
  CutCount, i: Integer;
begin
  Result := TAgentMessageList.Create;

  if (AMessages = nil) or (AMessages.Count = 0) then
    Exit;

  // Keep the newest (1 - ARatio) portion
  CutCount := Floor(AMessages.Count * ARatio);

  // Ensure we cut at a valid position (not mid-turn)
  // Walk forward from CutCount to find a UserMessage
  while (CutCount < AMessages.Count) and
        (AMessages[CutCount].Role = mrToolResult) do
    Inc(CutCount);

  for i := CutCount to AMessages.Count - 1 do
    Result.Add(AMessages[i].Clone);
end;

class function TCompaction.ExtractFileOps(
  AMessages: TAgentMessageList): TArray<TFileOperation>;
var
  i, j: Integer;
  ToolCalls: TArray<TToolCall>;
  Path: string;
  List: TArray<TFileOperation>;
  ListLen: Integer;
  Op: TFileOperation;
begin
  Result := nil;
  ListLen := 0;
  SetLength(List, AMessages.Count);  // Max possible size (pre-allocate)

  for i := 0 to AMessages.Count - 1 do
  begin
    if AMessages[i].Role <> mrAssistant then
      Continue;

    var AsstMsg := TAssistantMessage(AMessages[i]);
    ToolCalls := AsstMsg.Content.FindToolCalls;

    for j := 0 to High(ToolCalls) do
    begin
      var ToolName := LowerCase(ToolCalls[j].Name);
      if (ToolName <> 'read') and (ToolName <> 'write') and (ToolName <> 'edit')
        and (ToolName <> 'read_file') and (ToolName <> 'write_file') and (ToolName <> 'edit_file') then
        Continue;

      // Extract path from arguments
      Path := '';
      if ToolCalls[j].Arguments <> nil then
      begin
        try
          Path := ToolCalls[j].Arguments.GetValue<string>('path');
        except
          // No path field
          Continue;
        end;
      end;

      if Path = '' then
        Continue;

      Op.FilePath := Path;
      Op.Operation := foRead;  // default
      if (ToolName = 'read') or (ToolName = 'read_file') then
        Op.Operation := foRead
      else if (ToolName = 'write') or (ToolName = 'write_file') then
        Op.Operation := foWrite
      else if (ToolName = 'edit') or (ToolName = 'edit_file') then
        Op.Operation := foEdit;

      List[ListLen] := Op;
      Inc(ListLen);
    end;
  end;

  SetLength(List, ListLen);
  Result := List;
end;

class function TCompaction.SerializeConversation(
  AMessages: TAgentMessageList): string;
var
  SB: TStringBuilder;

  function ExtractText(AMsg: TAgentMessage): string;
  var
    j: Integer;
  begin
    Result := '';
    case AMsg.Role of
      mrUser:
        Result := TUserMessage(AMsg).Content;
      mrAssistant:
      begin
        for j := 0 to TAssistantMessage(AMsg).Content.Count - 1 do
          if TAssistantMessage(AMsg).Content[j].ContentType = cbtText then
            Result := Result + TTextContent(TAssistantMessage(AMsg).Content[j]).Text;
      end;
      mrToolResult:
      begin
        for j := 0 to TToolResultMessage(AMsg).Content.Count - 1 do
          if TToolResultMessage(AMsg).Content[j].ContentType = cbtText then
            Result := Result + TTextContent(TToolResultMessage(AMsg).Content[j]).Text;
      end;
    end;
  end;

var
  i: Integer;
  MaxLen: Integer;
  Text: string;
begin
  SB := TStringBuilder.Create;
  try
    MaxLen := MAX_SERIALIZATION_CHARS;

    for i := 0 to AMessages.Count - 1 do
    begin
      if SB.Length > MaxLen then
      begin
        SB.AppendLine('... (remaining messages omitted for length)');
        Break;
      end;

      case AMessages[i].Role of
        mrUser:
        begin
          var UserMsg := TUserMessage(AMessages[i]);
          if UserMsg.IsCompactionSummary then
          begin
            SB.AppendLine('[Previous Summary]:');
            SB.AppendLine(UserMsg.Content);
          end
          else
          begin
            SB.AppendLine('[User]: ' + UserMsg.Content);
          end;
        end;

        mrAssistant:
        begin
          var AsstMsg := TAssistantMessage(AMessages[i]);
          // Text content
          Text := '';
          for var j := 0 to AsstMsg.Content.Count - 1 do
          begin
            case AsstMsg.Content[j].ContentType of
              cbtText:
                Text := Text + TTextContent(AsstMsg.Content[j]).Text;
              cbtToolCall:
              begin
                var TC := TToolCall(AsstMsg.Content[j]);
                if Text <> '' then
                begin
                  SB.AppendLine('[Assistant]: ' + Text);
                  Text := '';
                end;
                SB.AppendLine('  [Tool: ' + TC.Name + ']');
              end;
            end;
          end;
          if Text <> '' then
            SB.AppendLine('[Assistant]: ' + Text);
        end;

        mrToolResult:
        begin
          var ToolMsg := TToolResultMessage(AMessages[i]);
          Text := ExtractText(AMessages[i]);
          if ToolMsg.IsError then
            SB.AppendLine('  [Error from ' + ToolMsg.ToolName + ']: ' + Text)
          else
          begin
            // Truncate large tool results in serialization
            if Length(Text) > 1000 then
              Text := Copy(Text, 1, 500) +
                '... (truncated) ...' +
                Copy(Text, Max(1, Length(Text) - 300), 301);
            SB.AppendLine('  [Result from ' + ToolMsg.ToolName + ']: ' + Text);
          end;
        end;
      end;

      SB.AppendLine('');
    end;

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TCompaction.IsContextOverflow(const AError: string): Boolean;
var
  Lower: string;
begin
  Lower := LowerCase(AError);
  Result :=
    ContainsText(Lower, 'context_length_exceeded') or
    ContainsText(Lower, 'token limit') or
    ContainsText(Lower, 'too many tokens') or
    ContainsText(Lower, 'maximum context') or
    ContainsText(Lower, 'context length') or
    (ContainsText(Lower, 'context') and ContainsText(Lower, 'length') and
     ContainsText(Lower, 'exceed'));
end;

end.
