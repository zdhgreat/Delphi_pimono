unit Utils.Localization;

interface

type
  TLang = (langEn, langZh);

procedure SetLanguage(ALang: TLang);
function GetCurrentLang: TLang;
function LangCode: string;
function LangFromCode(const ACode: string): TLang;

/// <summary>Return localized string for key. Falls back to key itself.</summary>
function L(const AKey: string): string;

implementation

{$WARN IMPLICIT_STRING_CAST OFF}

uses
  System.SysUtils, System.SyncObjs, System.Generics.Collections;

var
  GLang: TLang = langEn;
  FStrings: TDictionary<string, string>;
  FLock: TCriticalSection;

function L(const AKey: string): string;
begin
  if (FLock <> nil) and (FStrings <> nil) then
  begin
    FLock.Acquire;
    try
      if not FStrings.TryGetValue(AKey, Result) then
        Result := AKey;
    finally
      FLock.Release;
    end;
  end
  else
    Result := AKey;
end;

procedure InitEnglish; forward;
procedure InitChinese; forward;

procedure SetLanguage(ALang: TLang);
begin
  if FLock = nil then Exit;
  FLock.Acquire;
  try
    GLang := ALang;
    if FStrings <> nil then
      FStrings.Clear;
    case ALang of
      langEn: InitEnglish;
      langZh: InitChinese;
    end;
  finally
    FLock.Release;
  end;
end;

function GetCurrentLang: TLang;
begin
  if FLock <> nil then
  begin
    FLock.Acquire;
    try
      Result := GLang;
    finally
      FLock.Release;
    end;
  end
  else
    Result := GLang;
end;

function LangCode: string;
var
  CurrentLang: TLang;
begin
  CurrentLang := GetCurrentLang;
  case CurrentLang of
    langEn: Result := 'en';
    langZh: Result := 'zh';
  else
    Result := 'en';
  end;
end;

function LangFromCode(const ACode: string): TLang;
begin
  if SameText(ACode, 'zh') or SameText(ACode, 'cn') or SameText(ACode, 'chinese') then
    Result := langZh
  else
    Result := langEn;
end;

procedure InitEnglish;
begin
  // --- MainForm: Toolbar Buttons ---
  FStrings.Add('btn.settings',    'Settings');
  FStrings.Add('btn.abort',       'Abort');
  FStrings.Add('btn.clear',       'Clear');
  FStrings.Add('btn.newsession',  'New Session');
  FStrings.Add('btn.branch',      'Branch');
  FStrings.Add('btn.help',        'Help');
  FStrings.Add('btn.export',      'Export');
  FStrings.Add('btn.send',        'Send');

  // --- MainForm: Session Panel Buttons ---
  FStrings.Add('btn.new',         'New');
  FStrings.Add('btn.open',        'Open');
  FStrings.Add('btn.del',         'Del');
  FStrings.Add('btn.save',        'Save');
  FStrings.Add('btn.rename',      'Rename');

  // --- MainForm: Confirmation Buttons ---
  FStrings.Add('btn.approve',     'Approve');
  FStrings.Add('btn.reject',      'Reject');
  FStrings.Add('btn.stop',        'Stop');
  FStrings.Add('btn.newchat',     'New Chat');

  // --- MainForm: Session Name ---
  FStrings.Add('session.prefix',  'Session ');

  // --- MainForm: Status Messages ---
  FStrings.Add('status.ready',            'Ready');
  FStrings.Add('status.readyBranch',      'Ready [%s]');
  FStrings.Add('status.running',          'Agent running...');
  FStrings.Add('status.streaming',        'Streaming...');
  FStrings.Add('status.readyTokens',      'Ready (%dK tokens)');
  FStrings.Add('status.readyTokensBranch','Ready (%dK tokens) [%s]');
  FStrings.Add('status.readyNew',         'Ready - New session');
  FStrings.Add('status.readyBranched',    'Ready - Branched session');
  FStrings.Add('status.aborted',          'Aborted');
  FStrings.Add('status.execTool',         'Executing tool: %s...');
  FStrings.Add('status.toolFailed',       'Tool %s failed');
  FStrings.Add('status.toolDone',         'Tool %s completed');

  // --- MainForm: Chat Display ---
  FStrings.Add('chat.welcome',
    'Welcome to PiMono Agent - Delphi Edition');
  FStrings.Add('chat.instruction',
    'Type your message below and press Enter (or Ctrl+Enter for new line).');
  FStrings.Add('chat.you',         'You:');
  FStrings.Add('chat.assistant',   'Assistant:');
  FStrings.Add('chat.thinking',    '[Thinking] ');
  FStrings.Add('chat.tool',        '  [Tool: %s]');
  FStrings.Add('chat.args',        '  Args: ');
  FStrings.Add('chat.compacted',
    '[Context auto-compacted: old messages summarized, recent conversation preserved]');
  FStrings.Add('chat.compactionHeader', '[Context Summary]');
  FStrings.Add('chat.codeCopy',  'Copy Code');
  FStrings.Add('chat.codeCopied', 'Copied!');
  FStrings.Add('chat.copyMsg',   'Copy');
  FStrings.Add('chat.copyMsgDone', 'Copied!');
  FStrings.Add('chat.dropTooLarge', 'File too large (max 1 MB): %s');
  FStrings.Add('chat.dropBinary', 'Cannot read binary file: %s');
  FStrings.Add('settings.activeModel', 'Switched to model: %s');
  FStrings.Add('chat.undo', 'Undo');
  FStrings.Add('chat.undoSuccess', 'Restored: %s');
  FStrings.Add('chat.undoEmpty', 'Nothing to undo');
  FStrings.Add('chat.searchNoMatch', 'No matches');
  FStrings.Add('chat.searchMatchInfo', '%d of %d');

  // --- MainForm: Welcome Screen ---
  FStrings.Add('welcome.title',    'How can I help you today?');
  FStrings.Add('welcome.subtitle', 'Ask me to analyze, edit, or search your code');
  FStrings.Add('welcome.examples',  'Examples');
  FStrings.Add('welcome.suggest1', 'Analyze the structure of this project');
  FStrings.Add('welcome.suggest2', 'Find all TODO comments in the codebase');
  FStrings.Add('welcome.suggest3', 'Explain the main module');
  FStrings.Add('welcome.suggest4', 'Help me refactor this unit');

  // --- MainForm: Session Messages ---
  FStrings.Add('msg.newSession',        'New session started.');
  FStrings.Add('msg.newSessionCreated', 'New session created.');
  FStrings.Add('msg.chatCleared',       'Chat cleared.');
  FStrings.Add('msg.settingsUpdated',   'Settings updated.');
  FStrings.Add('msg.sessionSaved',      'Session saved.');
  FStrings.Add('msg.sessionDeleted',    'Session deleted.');
  FStrings.Add('msg.noSessionSave',     'No active session to save.');
  FStrings.Add('msg.noSessionExport',   'No active session to export.');
  FStrings.Add('msg.selectOpen',        'Select a session to open.');
  FStrings.Add('msg.selectDelete',      'Select a session to delete.');
  FStrings.Add('msg.selectRename',      'Select a session to rename.');
  FStrings.Add('msg.renameTitle',       'Rename Session');
  FStrings.Add('msg.renamePrompt',      'New name:');
  FStrings.Add('msg.sessionRenamed',    'Session renamed.');
  FStrings.Add('msg.openFailed',        'Failed to open session.');
  FStrings.Add('msg.deleteConfirm',     'Delete this session?');
  FStrings.Add('msg.openedSession',     'Opened session: ');
  FStrings.Add('msg.branchedSession',   'Branched session: ');
  FStrings.Add('msg.branchFailed',      'Branch failed: ');
  FStrings.Add('msg.exportedTo',        'Session exported to: ');

  // --- MainForm: Skill / Template ---
  FStrings.Add('confirm.title',           '[Confirmation Required] Tool: %s  File: %s');
  FStrings.Add('confirm.skillLoaded',     '[Skill: %s loaded]');
  FStrings.Add('confirm.skillNotFound',   'Skill not found: %s');
  FStrings.Add('confirm.templateLoaded',  '[Template: %s]');
  FStrings.Add('confirm.templateNotFound','Template not found: %s');

  // --- Settings Form ---
  FStrings.Add('settings.title',          'Settings');
  FStrings.Add('settings.tabApi',         'API');
  FStrings.Add('settings.tabModel',       'Model');
  FStrings.Add('settings.tabUI',          'UI');
  FStrings.Add('settings.tabPaths',       'Paths');
  FStrings.Add('settings.apiEndpoint',    'API Endpoint:');
  FStrings.Add('settings.apiKey',         'API Key:');
  FStrings.Add('settings.modelsEndpoint', 'Models Endpoint:');
  FStrings.Add('settings.streaming',      'Enable Streaming');
  FStrings.Add('settings.timeout',        'Timeout (ms):');
  FStrings.Add('settings.retryCount',     'Retry Count:');
  FStrings.Add('settings.modelName',      'Model Name:');
  FStrings.Add('settings.maxTokens',      'Max Tokens:');
  FStrings.Add('settings.temperature',    'Temperature:');
  FStrings.Add('settings.topP',           'Top P:');
  FStrings.Add('settings.thinkingLevel',  'Thinking Level:');
  FStrings.Add('settings.topPHint',       'Default 1.0, controls sampling range');
  FStrings.Add('settings.thinkingHint',   'Only for reasoning models');
  FStrings.Add('settings.theme',          'Theme:');
  FStrings.Add('settings.dark',           'Dark');
  FStrings.Add('settings.light',          'Light');
  FStrings.Add('settings.fontSize',       'Font Size:');
  FStrings.Add('settings.fontFamily',     'Font Family:');
  FStrings.Add('settings.language',       'Language:');
  FStrings.Add('settings.langEn',         'English');
  FStrings.Add('settings.langZh',         'Chinese');
  FStrings.Add('settings.workingDir',     'Working Directory:');
  FStrings.Add('settings.backupDir',      'Backup Directory:');
  FStrings.Add('settings.browse',         'Browse');
  FStrings.Add('settings.save',           'Save');
  FStrings.Add('settings.cancel',         'Cancel');
  FStrings.Add('settings.selectWorkingDir','Select Working Directory');
  FStrings.Add('settings.selectBackupDir', 'Select Backup Directory');
  FStrings.Add('settings.tabProfiles',       'Profiles');
  FStrings.Add('settings.addProfile',        'Add');
  FStrings.Add('settings.deleteProfile',     'Delete');
  FStrings.Add('settings.setActive',         'Set Active');
  FStrings.Add('settings.profileDisplayName','Display Name:');
  FStrings.Add('settings.profileEndpoint',   'API Endpoint:');
  FStrings.Add('settings.profileApiKey',     'API Key:');
  FStrings.Add('settings.profileModelName',  'Model Name:');
  FStrings.Add('settings.profileMaxTokens',  'Max Tokens:');
  FStrings.Add('settings.profileTemperature','Temperature:');
  FStrings.Add('settings.newProfile',        'New Profile');
  FStrings.Add('settings.cantDeleteLast',    'Cannot delete the last profile.');
  FStrings.Add('settings.activeSuffix',      ' (Active)');

  // --- Settings Form: Search Tab ---
  FStrings.Add('settings.tabSearch',             'Search');
  FStrings.Add('settings.searchEnabled',         'Enable Web Search');
  FStrings.Add('settings.searchProvider',        'Search Provider:');
  FStrings.Add('settings.searchNone',            '(None)');
  FStrings.Add('settings.searchApiKey',          'API Key:');
  FStrings.Add('settings.searchCustomId',        'Custom Engine ID (Google CX):');
  FStrings.Add('settings.searchInstanceUrl',     'SearXNG Instance URL:');
  FStrings.Add('settings.searchMaxResults',      'Max Results:');
  FStrings.Add('settings.searchTimeout',         'Timeout (ms):');
  FStrings.Add('settings.searchEnableFetch',     'Enable Web Page Fetching');
  FStrings.Add('settings.searchFetchMaxLength',  'Fetch Max Length (chars):');
  FStrings.Add('settings.searchHintNone',        'Select a search provider to enable web search.');
  FStrings.Add('settings.searchHintGoogle',      'Google Custom Search requires an API Key and CX (Custom Search Engine ID). Free tier: 100 queries/day.');
  FStrings.Add('settings.searchHintDDG',         'DuckDuckGo is free and requires no API Key. Uses HTML parsing, stability may vary.');
  FStrings.Add('settings.searchHintSearXNG',     'SearXNG is an open-source meta-search engine. Provide your self-hosted instance URL above.');
  FStrings.Add('settings.searchHintBrave',       'Brave Search API. Free tier: 2,000 queries/month. Privacy-focused.');
  FStrings.Add('settings.searchHintSerper',      'Serper.dev provides Google SERP results via API. Free tier: 2,500 queries/month.');
  FStrings.Add('settings.searchHintTavily',      'Tavily is an AI-native search API. Free tier: 1,000 queries/month.');
  FStrings.Add('settings.searchHintYouCom',      'You.com search API. Provides $100 free credits for new accounts.');
  FStrings.Add('settings.searchHintExa',         'Exa provides semantic/neural search capabilities. Good for finding similar content.');
  FStrings.Add('settings.searchHintFirecrawl',   'Firecrawl is extraction-first search. 500 one-time free credits.');
  FStrings.Add('settings.searchHintLinkup',      'Linkup search API. High accuracy on SimpleQA benchmarks (90.10%).');
  FStrings.Add('settings.searchHintPerplexity',  'Perplexity API search. Access to billions of webpages.');
  FStrings.Add('settings.searchHintMoonshot',    'Moonshot/Kimi built-in web search. Uses your existing Moonshot API Key.');

  // --- Settings Form: Skills Tab ---
  FStrings.Add('settings.tabSkills',             'Skills');
  FStrings.Add('settings.skillNew',              'New');
  FStrings.Add('settings.skillDelete',           'Delete');
  FStrings.Add('settings.skillName',             'Name:');
  FStrings.Add('settings.skillDesc',             'Description:');
  FStrings.Add('settings.skillPrompt',           'Prompt:');
  FStrings.Add('settings.skillCantDelete',       'Select a skill to delete.');
  FStrings.Add('settings.skillReferences',       'References:');
  FStrings.Add('settings.skillExamples',         'Examples:');
  FStrings.Add('settings.skillTabMain',          'Main');
  FStrings.Add('settings.skillTabRefs',          'References');
  FStrings.Add('settings.skillTabExamples',      'Examples');
  FStrings.Add('settings.skillInstall',          'Install...');
  FStrings.Add('settings.skillInstallTitle',     'Select Skill File');
  FStrings.Add('settings.skillInstallFailed',    'Failed to install skill: %s');
  FStrings.Add('settings.skillOverwrite',        'Skill "%s" already exists. Overwrite?');

  // --- MainForm: Skill Panel ---
  FStrings.Add('skills.attached',                'Attached Skills');
  FStrings.Add('skills.noneAttached',            'No skills');
  FStrings.Add('skills.add',                     '+ Add');
  FStrings.Add('sidebar.empty',                  'Start your first conversation');
  FStrings.Add('sidebar.newChat',                'New Chat');

  // --- Context Menu ---
  FStrings.Add('context.rename',                 'Rename');
  FStrings.Add('context.delete',                 'Delete');

  // --- Skill Panel ---
  FStrings.Add('skills.label',                   'Attached Skills');
  FStrings.Add('sidebar.noSkillDetail',          'No details available');
  FStrings.Add('chat.placeholder',               'Type a message... (Enter to send, Shift+Enter for new line)');
  FStrings.Add('error.noApiKey',                  'API Key not configured. Please go to Settings and enter your API Key.');
  FStrings.Add('error.noEndpoint',                'API Endpoint not configured. Please go to Settings and enter the API Endpoint.');
  FStrings.Add('error.noModel',                   'Model name not configured. Please go to Settings and select a model.');
  FStrings.Add('status.error',                    'Error');
  FStrings.Add('status.executingTool',            'Executing tool: ');
  FStrings.Add('status.toolFailedShort',           'Tool failed: ');
  FStrings.Add('status.toolDoneShort',             'Tool done: ');

  // --- Help Form ---
  FStrings.Add('help.title',       'PiMono Agent - Help');
  FStrings.Add('help.about',       'About');
  FStrings.Add('help.shortcuts',   'Shortcuts');
  FStrings.Add('help.tips',        'Tips');
  FStrings.Add('help.close',       'Close');
  FStrings.Add('help.appName',     'PiMono Agent');
  FStrings.Add('help.version',     'Version 1.0.0 (Delphi Edition)');
  FStrings.Add('help.desc',
    'PiMono Agent is an AI-powered code editing assistant that runs entirely ' +
    'on your internal network. It can read, write, edit, and search files, ' +
    'execute commands, and help with code analysis and refactoring.' + #13#10#13#10 +
    'Built with Delphi 11.x Alexandria.' + #13#10 +
    'Powered by internal LLM API server.');
  FStrings.Add('help.tech', 'Components: VCL, System.Net.HttpClient, System.JSON');
  FStrings.Add('help.colShortcut', 'Shortcut');
  FStrings.Add('help.colAction',   'Action');

  // Shortcuts
  FStrings.Add('help.sk.send',     'Send message');
  FStrings.Add('help.sk.newline',  'New line in input');
  FStrings.Add('help.sk.save',     'Save current session');
  FStrings.Add('help.sk.new',      'New session');
  FStrings.Add('help.sk.open',     'Open session');
  FStrings.Add('help.sk.settings', 'Open settings');
  FStrings.Add('help.sk.clear',    'Clear chat display');
  FStrings.Add('help.sk.abort',    'Abort current operation');
  FStrings.Add('help.sk.help',     'Show this help');
  FStrings.Add('help.sk.quit',     'Quit application');

  // Tips
  FStrings.Add('help.tip1',
    '1. Be specific about what you want to do. Instead of "fix the bug", ' +
    'say "fix the null pointer exception in the TUser.Validate method".');
  FStrings.Add('help.tip2',
    '2. The agent can read, write, and edit files. It will show you what it plans to change before making edits.');
  FStrings.Add('help.tip3',
    '3. Use the read tool results to understand code before asking for changes.');
  FStrings.Add('help.tip4',
    '4. For large refactors, break them into smaller steps the agent can execute one at a time.');
  FStrings.Add('help.tip5',
    '5. The bash tool can run builds, tests, and other commands.');
  FStrings.Add('help.tip6',
    '6. Sessions are auto-saved. You can switch between sessions from the session panel.');
  FStrings.Add('help.tip7',
    '7. Use the Branch button to fork a conversation and explore different directions.');
end;

procedure InitChinese;
begin
  // --- MainForm: Toolbar Buttons ---
  FStrings.Add('btn.settings',    '设置');
  FStrings.Add('btn.abort',       '中止');
  FStrings.Add('btn.clear',       '清空');
  FStrings.Add('btn.newsession',  '新会话');
  FStrings.Add('btn.branch',      '分支');
  FStrings.Add('btn.help',        '帮助');
  FStrings.Add('btn.export',      '导出');
  FStrings.Add('btn.send',        '发送');

  // --- MainForm: Session Panel Buttons ---
  FStrings.Add('btn.new',         '新建');
  FStrings.Add('btn.open',        '打开');
  FStrings.Add('btn.del',         '删除');
  FStrings.Add('btn.save',        '保存');
  FStrings.Add('btn.rename',      '重命名');

  // --- MainForm: Confirmation Buttons ---
  FStrings.Add('btn.approve',     '批准');
  FStrings.Add('btn.reject',      '拒绝');
  FStrings.Add('btn.stop',        '停止');
  FStrings.Add('btn.newchat',     '新对话');

  // --- MainForm: Session Name ---
  FStrings.Add('session.prefix',  '会话 ');

  // --- MainForm: Status Messages ---
  FStrings.Add('status.ready',            '就绪');
  FStrings.Add('status.readyBranch',      '就绪 [%s]');
  FStrings.Add('status.running',          'Agent 运行中...');
  FStrings.Add('status.streaming',        '正在输出...');
  FStrings.Add('status.readyTokens',      '就绪 (%dK tokens)');
  FStrings.Add('status.readyTokensBranch','就绪 (%dK tokens) [%s]');
  FStrings.Add('status.readyNew',         '就绪 - 新会话');
  FStrings.Add('status.readyBranched',    '就绪 - 分支会话');
  FStrings.Add('status.aborted',          '已中止');
  FStrings.Add('status.execTool',         '执行工具: %s...');
  FStrings.Add('status.toolFailed',       '工具 %s 失败');
  FStrings.Add('status.toolDone',         '工具 %s 完成');

  // --- MainForm: Chat Display ---
  FStrings.Add('chat.welcome',
    '欢迎使用 PiMono Agent - Delphi 版');
  FStrings.Add('chat.instruction',
    '在下方输入消息，按 Enter 发送（Ctrl+Enter 换行）。');
  FStrings.Add('chat.you',         '你:');
  FStrings.Add('chat.assistant',   '助手:');
  FStrings.Add('chat.thinking',    '[思考] ');
  FStrings.Add('chat.tool',        '  [工具: %s]');
  FStrings.Add('chat.args',        '  参数: ');
  FStrings.Add('chat.compacted',
    '[上下文已自动压缩: 旧消息已摘要，保留最近对话]');
  FStrings.Add('chat.compactionHeader', '[上下文摘要]');
  FStrings.Add('chat.codeCopy',  '复制代码');
  FStrings.Add('chat.codeCopied', '已复制!');
  FStrings.Add('chat.copyMsg',   '复制');
  FStrings.Add('chat.copyMsgDone', '已复制!');
  FStrings.Add('chat.dropTooLarge', '文件过大（最大 1 MB）: %s');
  FStrings.Add('chat.dropBinary', '无法读取二进制文件: %s');
  FStrings.Add('settings.activeModel', '已切换到模型: %s');
  FStrings.Add('chat.undo', '撤销');
  FStrings.Add('chat.undoSuccess', '已恢复: %s');
  FStrings.Add('chat.undoEmpty', '没有可撤销的操作');
  FStrings.Add('chat.searchNoMatch', '无匹配');
  FStrings.Add('chat.searchMatchInfo', '第 %d / %d 个');

  // --- MainForm: Welcome Screen ---
  FStrings.Add('welcome.title',    '今天我能帮你做什么？');
  FStrings.Add('welcome.subtitle', '让我帮你分析、编辑或搜索代码');
  FStrings.Add('welcome.examples',  '示例');
  FStrings.Add('welcome.suggest1', '分析这个项目的结构');
  FStrings.Add('welcome.suggest2', '查找代码中所有 TODO 注释');
  FStrings.Add('welcome.suggest3', '解释主模块的代码');
  FStrings.Add('welcome.suggest4', '帮我重构这个单元');

  // --- MainForm: Session Messages ---
  FStrings.Add('msg.newSession',        '新会话已开始。');
  FStrings.Add('msg.newSessionCreated', '新会话已创建。');
  FStrings.Add('msg.chatCleared',       '聊天已清空。');
  FStrings.Add('msg.settingsUpdated',   '设置已更新。');
  FStrings.Add('msg.sessionSaved',      '会话已保存。');
  FStrings.Add('msg.sessionDeleted',    '会话已删除。');
  FStrings.Add('msg.noSessionSave',     '没有可保存的会话。');
  FStrings.Add('msg.noSessionExport',   '没有可导出的会话。');
  FStrings.Add('msg.selectOpen',        '请选择要打开的会话。');
  FStrings.Add('msg.selectDelete',      '请选择要删除的会话。');
  FStrings.Add('msg.selectRename',      '请选择要重命名的会话。');
  FStrings.Add('msg.renameTitle',       '重命名会话');
  FStrings.Add('msg.renamePrompt',      '新名称:');
  FStrings.Add('msg.sessionRenamed',    '会话已重命名。');
  FStrings.Add('msg.openFailed',        '打开会话失败。');
  FStrings.Add('msg.deleteConfirm',     '删除此会话？');
  FStrings.Add('msg.openedSession',     '已打开会话: ');
  FStrings.Add('msg.branchedSession',   '已分支会话: ');
  FStrings.Add('msg.branchFailed',      '分支失败: ');
  FStrings.Add('msg.exportedTo',        '会话已导出至: ');

  // --- MainForm: Skill / Template ---
  FStrings.Add('confirm.title',           '[需要确认] 工具: %s  文件: %s');
  FStrings.Add('confirm.skillLoaded',     '[技能: %s 已加载]');
  FStrings.Add('confirm.skillNotFound',   '找不到技能: %s');
  FStrings.Add('confirm.templateLoaded',  '[模板: %s]');
  FStrings.Add('confirm.templateNotFound','找不到模板: %s');

  // --- Settings Form ---
  FStrings.Add('settings.title',          '设置');
  FStrings.Add('settings.tabApi',         'API');
  FStrings.Add('settings.tabModel',       '模型');
  FStrings.Add('settings.tabUI',          '界面');
  FStrings.Add('settings.tabPaths',       '路径');
  FStrings.Add('settings.apiEndpoint',    'API 端点:');
  FStrings.Add('settings.apiKey',         'API 密钥:');
  FStrings.Add('settings.modelsEndpoint', '模型端点:');
  FStrings.Add('settings.streaming',      '启用流式传输');
  FStrings.Add('settings.timeout',        '超时 (毫秒):');
  FStrings.Add('settings.retryCount',     '重试次数:');
  FStrings.Add('settings.modelName',      '模型名称:');
  FStrings.Add('settings.maxTokens',      '最大 Token:');
  FStrings.Add('settings.temperature',    '温度:');
  FStrings.Add('settings.topP',           'Top P:');
  FStrings.Add('settings.thinkingLevel',  '思考等级:');
  FStrings.Add('settings.topPHint',       '默认 1.0，控制采样范围');
  FStrings.Add('settings.thinkingHint',   '仅推理模型生效');
  FStrings.Add('settings.theme',          '主题:');
  FStrings.Add('settings.dark',           '暗色');
  FStrings.Add('settings.light',          '亮色');
  FStrings.Add('settings.fontSize',       '字体大小:');
  FStrings.Add('settings.fontFamily',     '字体:');
  FStrings.Add('settings.language',       '语言:');
  FStrings.Add('settings.langEn',         'English');
  FStrings.Add('settings.langZh',         '中文');
  FStrings.Add('settings.workingDir',     '工作目录:');
  FStrings.Add('settings.backupDir',      '备份目录:');
  FStrings.Add('settings.browse',         '浏览');
  FStrings.Add('settings.save',           '保存');
  FStrings.Add('settings.cancel',         '取消');
  FStrings.Add('settings.selectWorkingDir','选择工作目录');
  FStrings.Add('settings.selectBackupDir', '选择备份目录');
  FStrings.Add('settings.tabProfiles',       '配置');
  FStrings.Add('settings.addProfile',        '添加');
  FStrings.Add('settings.deleteProfile',     '删除');
  FStrings.Add('settings.setActive',         '设为当前');
  FStrings.Add('settings.profileDisplayName','显示名称:');
  FStrings.Add('settings.profileEndpoint',   'API 端点:');
  FStrings.Add('settings.profileApiKey',     'API 密钥:');
  FStrings.Add('settings.profileModelName',  '模型名称:');
  FStrings.Add('settings.profileMaxTokens',  '最大 Token:');
  FStrings.Add('settings.profileTemperature','温度:');
  FStrings.Add('settings.newProfile',        '新配置');
  FStrings.Add('settings.cantDeleteLast',    '无法删除最后一个配置。');
  FStrings.Add('settings.activeSuffix',      ' (当前)');

  // --- Settings Form: Search Tab ---
  FStrings.Add('settings.tabSearch',             '搜索');
  FStrings.Add('settings.searchEnabled',         '启用联网搜索');
  FStrings.Add('settings.searchProvider',        '搜索引擎:');
  FStrings.Add('settings.searchNone',            '(无)');
  FStrings.Add('settings.searchApiKey',          'API 密钥:');
  FStrings.Add('settings.searchCustomId',        '自定义引擎 ID (Google CX):');
  FStrings.Add('settings.searchInstanceUrl',     'SearXNG 实例地址:');
  FStrings.Add('settings.searchMaxResults',      '最大结果数:');
  FStrings.Add('settings.searchTimeout',         '超时 (毫秒):');
  FStrings.Add('settings.searchEnableFetch',     '启用网页抓取');
  FStrings.Add('settings.searchFetchMaxLength',  '抓取最大字符数:');
  FStrings.Add('settings.searchHintNone',        '选择搜索引擎以启用联网搜索功能。');
  FStrings.Add('settings.searchHintGoogle',      'Google 自定义搜索需要 API Key 和 CX（自定义搜索引擎 ID）。免费额度：100 次/天。');
  FStrings.Add('settings.searchHintDDG',         'DuckDuckGo 免费，无需 API Key。使用 HTML 解析，稳定性可能有限。');
  FStrings.Add('settings.searchHintSearXNG',     'SearXNG 是开源元搜索引擎。请在上方输入自建实例地址。');
  FStrings.Add('settings.searchHintBrave',       'Brave 搜索 API。免费额度：2,000 次/月。注重隐私。');
  FStrings.Add('settings.searchHintSerper',      'Serper.dev 提供 Google 搜索结果 API。免费额度：2,500 次/月。');
  FStrings.Add('settings.searchHintTavily',      'Tavily 是 AI 原生搜索 API。免费额度：1,000 次/月。');
  FStrings.Add('settings.searchHintYouCom',      'You.com 搜索 API。新账户赠送 $100 免费额度。');
  FStrings.Add('settings.searchHintExa',         'Exa 提供语义/神经搜索能力。擅长查找相似内容。');
  FStrings.Add('settings.searchHintFirecrawl',   'Firecrawl 是以内容抓取为主的搜索。500 次一次性免费额度。');
  FStrings.Add('settings.searchHintLinkup',      'Linkup 搜索 API。SimpleQA 准确率高达 90.10%。');
  FStrings.Add('settings.searchHintPerplexity',  'Perplexity API 搜索。索引数十亿网页。');
  FStrings.Add('settings.searchHintMoonshot',    'Moonshot/Kimi 内置联网搜索。使用现有的 Moonshot API Key。');

  // --- Settings Form: Skills Tab ---
  FStrings.Add('settings.tabSkills',             '技能');
  FStrings.Add('settings.skillNew',              '新建');
  FStrings.Add('settings.skillDelete',           '删除');
  FStrings.Add('settings.skillName',             '名称:');
  FStrings.Add('settings.skillDesc',             '描述:');
  FStrings.Add('settings.skillPrompt',           '提示词:');
  FStrings.Add('settings.skillCantDelete',       '请先选择要删除的技能。');
  FStrings.Add('settings.skillReferences',       '参考资料:');
  FStrings.Add('settings.skillExamples',         '示例:');
  FStrings.Add('settings.skillTabMain',          '主提示词');
  FStrings.Add('settings.skillTabRefs',          '参考资料');
  FStrings.Add('settings.skillTabExamples',      '示例');
  FStrings.Add('settings.skillInstall',          '安装...');
  FStrings.Add('settings.skillInstallTitle',     '选择 Skill 文件');
  FStrings.Add('settings.skillInstallFailed',    '安装 Skill 失败：%s');
  FStrings.Add('settings.skillOverwrite',        'Skill "%s" 已存在，是否覆盖？');

  // --- MainForm: Skill Panel ---
  FStrings.Add('skills.attached',                '已挂载技能');
  FStrings.Add('skills.noneAttached',            '未挂载');
  FStrings.Add('skills.add',                     '+ 添加');
  FStrings.Add('sidebar.empty',                  '开始你的第一个对话');
  FStrings.Add('sidebar.newChat',                '新对话');

  // --- Context Menu ---
  FStrings.Add('context.rename',                 '重命名');
  FStrings.Add('context.delete',                 '删除');

  // --- Skill Panel ---
  FStrings.Add('skills.label',                   '已挂载技能');
  FStrings.Add('sidebar.noSkillDetail',          '暂无详细信息');
  FStrings.Add('chat.placeholder',               '输入消息... (Enter 发送, Shift+Enter 换行)');
  FStrings.Add('error.noApiKey',                  '未配置 API Key，请前往设置页面填写 API Key。');
  FStrings.Add('error.noEndpoint',                '未配置 API 端点，请前往设置页面填写 API Endpoint。');
  FStrings.Add('error.noModel',                   '未配置模型名称，请前往设置页面选择模型。');
  FStrings.Add('status.error',                    '错误');
  FStrings.Add('status.executingTool',            '执行工具: ');
  FStrings.Add('status.toolFailedShort',           '工具失败: ');
  FStrings.Add('status.toolDoneShort',             '工具完成: ');

  // --- Help Form ---
  FStrings.Add('help.title',       'PiMono Agent - 帮助');
  FStrings.Add('help.about',       '关于');
  FStrings.Add('help.shortcuts',   '快捷键');
  FStrings.Add('help.tips',        '提示');
  FStrings.Add('help.close',       '关闭');
  FStrings.Add('help.appName',     'PiMono Agent');
  FStrings.Add('help.version',     '版本 1.0.0 (Delphi 版)');
  FStrings.Add('help.desc',
    'PiMono Agent 是一个运行在内网的 AI 驱动代码编辑助手。' +
    '它可以读取、写入、编辑和搜索文件，执行命令，并帮助进行代码分析和重构。' + #13#10#13#10 +
    '基于 Delphi 11.x Alexandria 构建。' + #13#10 +
    '由内网 LLM API 服务器提供支持。');
  FStrings.Add('help.tech', '组件: VCL, System.Net.HttpClient, System.JSON');
  FStrings.Add('help.colShortcut', '快捷键');
  FStrings.Add('help.colAction',   '操作');

  // Shortcuts
  FStrings.Add('help.sk.send',     '发送消息');
  FStrings.Add('help.sk.newline',  '输入换行');
  FStrings.Add('help.sk.save',     '保存当前会话');
  FStrings.Add('help.sk.new',      '新建会话');
  FStrings.Add('help.sk.open',     '打开会话');
  FStrings.Add('help.sk.settings', '打开设置');
  FStrings.Add('help.sk.clear',    '清空聊天显示');
  FStrings.Add('help.sk.abort',    '中止当前操作');
  FStrings.Add('help.sk.help',     '显示帮助');
  FStrings.Add('help.sk.quit',     '退出应用');

  // Tips
  FStrings.Add('help.tip1',
    '1. 描述要具体。与其说"修复这个 bug"，不如说"修复 TUser.Validate 方法中的空指针异常"。');
  FStrings.Add('help.tip2',
    '2. Agent 可以读取、写入和编辑文件。它会在编辑前展示计划进行的修改。');
  FStrings.Add('help.tip3',
    '3. 先使用读取工具了解代码，再提出修改建议。');
  FStrings.Add('help.tip4',
    '4. 大型重构应拆分为多个小步骤，让 Agent 逐步执行。');
  FStrings.Add('help.tip5',
    '5. Bash 工具可以运行构建、测试和其他命令。');
  FStrings.Add('help.tip6',
    '6. 会话会自动保存。你可以通过左侧面板切换不同会话。');
  FStrings.Add('help.tip7',
    '7. 使用"分支"按钮可以基于当前对话创建分支，探索不同方向。');
end;

initialization
  FLock := TCriticalSection.Create;
  FStrings := TDictionary<string, string>.Create;
  SetLanguage(langEn);

finalization
  FStrings.Free;
  FLock.Free;

end.
