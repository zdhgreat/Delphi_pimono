# PiMono Agent (Delphi Edition) — 架构与技术报告

> 版本：6.0（ChatGPT 风格代码块拆分渲染 + UI 性能优化 + 消息复制）
> 日期：2026-04-21
> 技术栈：Delphi 11.x Alexandria / VCL / System.Net.HttpClient / System.JSON
> 原版参考：[pi-mono](https://github.com/badlogic/pi-mono) by Mario Zechner (MIT License)

---

## 一、项目概述

### 1.1 项目目标

PiMono Agent 是一个运行在 Windows 桌面的 **AI 驱动代码编辑助手**。它通过 OpenAI 兼容的 REST API 与企业内网部署的大语言模型（LLM）通信，为用户提供智能化的代码分析、文件编辑、命令执行和项目管理能力。

**核心定位**：

- 纯内网运行，不依赖外部公有云服务，数据不出企业网络
- ChatGPT/Gemini 风格的现代桌面 UI（TScrollBox 气泡消息、可折叠侧栏、欢迎屏）
- Markdown 渲染（标题、粗体、斜体、代码块、行内代码、引用、表格、链接）
- **ChatGPT 风格代码块拆分渲染**：每个代码块独立显示（语言标签 + Copy 按钮 + 等宽代码内容）
- 多模型配置与快速切换
- 支持多会话管理、会话分支、流式响应、工具调用、编辑确认等完整的 Agent 能力
- 消息文本可选择/复制，深色/浅色主题一键切换
- 内置撤销/回滚、会话搜索、文件拖放
- **每条消息独立的 Copy Message 按钮**（气泡上方）

### 1.2 代码规模

| 指标 | 数值 |
|------|------|
| 源文件数 | 34 个 .pas 文件 |
| 核心模块 | 9 个单元（Agent、State、Events、Messages、Session、Compaction、ToolResultSlim、UndoLog、App.Main） |
| AI 模块 | 3 个单元（IModel、CustomAPIAdapter、ModelConfig） |
| 工具模块 | 5 个单元（ITool、ToolRegistry、FileTools、BashTool、GitTool） |
| 配置模块 | 2 个单元（Config、SettingsManager） |
| UI 模块 | 5 个单元（MainForm、SettingsForm、HelpForm、ThemeManager、CustomButton） |
| 工具模块 | 5 个单元（Logger、JsonHelper、Localization、TokenEstimator、Markdown） |

### 1.3 版本演进

| 版本 | 重点功能 |
|------|----------|
| 1.0–2.0 | 核心 Agent 循环、基础 UI、SSE 解析 |
| 3.0 | 确认系统、模糊匹配、.gitignore、HTML 导出、Skills/模板 |
| 4.0 | ChatGPT 风格 TScrollBox 气泡 UI、38 色主题、可折叠侧栏、欢迎屏 |
| 5.0 | HTTP 流式传输、Git 工具、Markdown 渲染、代码复制、多模型切换、文件拖放、撤销回滚、会话搜索 |
| **6.0** | **代码块拆分渲染（ChatGPT 风格）、UI 性能优化（位图缓存/延迟渲染/节流/去抖）、消息复制按钮、TStreamDeltaEvent 轻量级事件** |

---

## 二、系统架构

### 2.1 分层架构

```
┌──────────────────────────────────────────────────────────┐
│                       UI 层 (VCL)                        │
│  UI.MainForm  UI.SettingsForm  UI.HelpForm               │
│  UI.ThemeManager (46+ 色主题系统)   UI.CustomButton       │
│  ↳ 多段渲染: ContentPanel → TRichEdit + CodeBlockPanel   │
├──────────────────────────────────────────────────────────┤
│                      Core 核心层                         │
│  Core.Agent (Agent 循环 + 权限 + 确认 + 队列)            │
│  Core.AgentState (状态 + 工具接口)                        │
│  Core.Events (12 种事件 + TStreamDeltaEvent + 发布订阅)   │
│  Core.Messages (消息 + 内容块类型)                         │
│  Core.SessionManager (JSONL 会话持久化)                   │
│  Core.Compaction (三层上下文压缩)                          │
│  Core.ToolResultSlim (工具结果精简)                       │
│  Core.UndoLog (操作撤销日志 + JSONL 持久化)               │
├──────────────────────────────────────────────────────────┤
│                      AI 模型层                           │
│  AI.IModel (模型接口 + API 格式定义)                      │
│  AI.CustomAPIAdapter (HTTP 流式 SSE 适配器)               │
│  AI.ModelConfig (模型配置 + 成本计算)                     │
├──────────────────────────────────────────────────────────┤
│                      Tools 工具层                        │
│  Tools.ITool (工具基类 + 路径安全 + UndoLog 集成)         │
│  Tools.ToolRegistry (工具注册表)                          │
│  Tools.FileTools (6 个文件工具 + 模糊匹配 + 撤销)        │
│  Tools.BashTool (Shell 命令工具)                          │
│  Tools.GitTool (4 个 Git 工具)                            │
├──────────────────────────────────────────────────────────┤
│                Settings / Utils 层                       │
│  Settings.Config (配置记录 + TModelProfile)               │
│  Settings.SettingsManager (双层配置管理)                   │
│  Utils.Logger / JsonHelper / Localization / Tokens        │
│  Utils.Markdown (Markdown→RTF + 段落解析器)               │
└──────────────────────────────────────────────────────────┘
```

### 2.2 数据流

```
用户输入 → BtnSendClick → FAgent.Prompt → Agent 循环（后台线程）
  → IModel.Stream (HTTP chunked 流式) → TStreamReader 逐行读取 SSE
  → TStreamDeltaEvent 轻量级增量事件（不克隆完整消息）
  → TEventDispatcher.Dispatch → OnAgentEvent (TThread.Synchronize)
  → HandleMessageUpdate → TLabel.Text 增量更新（流式中, 33ms 节流 ~30fps）
  → HandleMessageEnd → ParseMarkdownSegments → RenderMarkdownToBubble
    → 文本段: MarkdownToRtf → TRichEdit
    → 代码块: CreateCodeBlockPanel (语言标签 + Copy按钮 + TMemo)
  → AddCopyMessageButton → 气泡上方 Copy Message 按钮
  → 保存到 Session → 自动压缩检查
```

---

## 三、核心模块详解

### 3.1 Core.Agent — Agent 编排器

Agent 核心循环在一个后台线程中运行，每轮（Turn）包含：

1. 将内部消息转换为 API 格式（`AgentMessagesToApiMessages`）
2. 调用 `IModel.Stream` 发起 HTTP chunked 流式请求
3. 通过 `TStreamReader` 逐行读取 SSE 响应流，解析增量事件
4. 通过 `TEventDispatcher` 分发到 UI
5. 如果 AI 返回工具调用（`stop_reason = tool_use`），执行工具并追加结果
6. 检查是否需要用户确认（`requireConfirmation = true` 时阻塞等待）
7. 重复直到 AI 返回 `stop` 或达到 MaxTurns 上限（默认 30）

**关键特性**：
- **权限系统**：Read/Write/Edit/Bash/Git 五级独立权限控制
- **编辑确认**：Write/Edit 工具默认需要用户审批，通过 `TEvent` 阻塞
- **Steering/FollowUp 队列**：支持流式过程中插入消息或排队后续任务
- **MaxTurns 限制**：防止无限工具调用循环
- **轻量级增量事件**：流式 delta 使用 `TStreamDeltaEvent`（仅含字符串 + 枚举），不再克隆完整消息对象

### 3.2 Core.Events — 事件系统

两层事件体系：

**第一层：AI 流式事件** (`TAssistantMessageEventType`)
- `ametStart/Done` — 流式开始/结束
- `ametTextStart/Delta/End` — 文本内容增量
- `ametThinkingStart/Delta/End` — 思考内容增量
- `ametToolCallStart/Delta/End` — 工具调用增量

**第二层：Agent 生命周期事件** (`TAgentEventType`)
- `aetAgentStart/End` — Agent 运行开始/结束
- `aetTurnStart/End` — 单轮 LLM 调用
- `aetMessageStart/Update/End` — 消息级事件
- `aetToolExecutionStart/Update/End` — 工具执行事件
- `aetToolConfirmationRequest` — 阻塞确认请求

**TStreamDeltaEvent**（v6.0 新增）：

```pascal
TStreamDeltaType = (sdtText, sdtThinking, sdtToolCall);
TStreamDeltaEvent = class(TAgentEvent)
  DeltaText: string;
  DeltaType: TStreamDeltaType;
  function EventType: TAgentEventType; override; // = aetMessageUpdate
end;
```

- 轻量级：仅包含增量文本字符串 + 类型枚举，不克隆完整消息对象
- 流式 delta 场景下（`ametText/Delta`、`ametThinking/Delta`、`ametToolCall/Delta`）全部使用 `TStreamDeltaEvent`
- 仅 `ametDone`/`ametError` 仍使用 `TMessageUpdateEvent.Clone`（每条消息仅触发一次）
- 大幅减少流式过程中的内存分配和 GC 压力

**发布-订阅**：`TEventDispatcher` 支持 `Subscribe`/`Unsubscribe`，UI 通过订阅接收事件。

### 3.3 Core.Messages — 消息模型

```
TAgentMessage (abstract)
  ├── TUserMessage        — Content: string, ContentBlocks, IsCompactionSummary
  ├── TAssistantMessage   — Content: TContentBlockList, Usage, StopReason
  └── TToolResultMessage  — ToolCallId, ToolName, Content, IsError

TContentBlock (abstract)
  ├── TTextContent        — 文本
  ├── TThinkingContent    — 思考/推理
  ├── TImageContent       — 图片
  └── TToolCall           — 工具调用 (Id, Name, Arguments: TJSONObject)
```

所有类型支持 JSON 序列化和 `Clone`，用于跨线程安全传递。

### 3.4 Core.SessionManager — 会话持久化

**JSONL 格式**：每个会话文件由一行 JSON 头 + 每条消息一行 JSON 组成。

- **追加写入**：保存时只追加新消息，不重写整个文件
- **分支支持**：`BranchFrom(Index)` 创建子会话，记录 `ParentId` 和 `BranchPoint`
- **自动迁移**：启动时将旧 `.json` 格式自动转换为 `.jsonl`
- **快速列表**：`ListSessions` 只读头部第一行信息，不全量加载消息
- **线程安全**：`SetCurrentSession` 使用 `FLock.Acquire/Release` 保护（v6.0 修复）
- **高效更新**：`UpdateHeaderTimestamp` 使用 `TStreamReader.ReadLine + ReadToEnd`，避免全量 `ReadAllLines`

### 3.5 Core.Compaction — 三层上下文压缩

当对话接近模型 token 上限时自动触发：

1. **精简工具结果**（`SlimToolResults`）：截断大型工具输出为头尾各 3 行
2. **LLM 摘要**（`TCompaction.Execute`）：用 AI 对旧消息生成结构化摘要
3. **紧急截断**（`EmergencyCut`）：如果压缩后仍溢出，直接截断

配置参数：`CompactionEnabled`、`ReserveTokens`（默认 16384）、`KeepRecentTokens`（默认 20000）。

### 3.6 Core.UndoLog — 操作撤销日志

`TUndoLog` 记录文件操作的旧内容，支持逐次撤销回滚。

**数据结构**：

```
TUndoEntry = record
  Id: Integer;
  Timestamp: TDateTime;
  FilePath: string;
  Operation: string;    // 'write' 或 'edit'
  OldContent: string;   // 操作前的原始内容（空 = 新建文件）
  ToolCallId: string;   // 触发操作的工具调用 ID
end;
```

**关键设计**：
- **JSONL 持久化**：每条操作记录写入 `undo_log.jsonl`，程序重启后恢复
- **FIFO 淘汰**：默认保留最近 100 条记录，超出自动淘汰最早记录
- **线程安全**：使用 `TCriticalSection` 保护，Agent 线程写入、UI 线程读取
- **与工具集成**：`TBaseTool.UndoLog` 属性，Write/Edit 工具执行前自动捕获旧内容并记录
- **撤销逻辑**：`UndoLast` 恢复旧内容；若旧内容为空则删除文件（反向创建操作）

---

## 四、AI 模型层

### 4.1 AI.IModel — 模型接口

```pascal
IModel = interface
  function Stream(Request: TCompletionRequest; Callback: TStreamEventCallback): TAssistantMessage;
  function Complete(Request: TCompletionRequest): TAssistantMessage;
  function GetModels: TModelList;
end;
```

- `TCompletionRequest`：完整的 API 请求参数（model, messages, tools, maxTokens, temperature, topP, thinkingLevel, stream）
- `AgentMessagesToApiMessages`：内部消息到 API 格式的转换（处理系统提示词、结构化内容、工具调用、工具结果）

### 4.2 AI.CustomAPIAdapter — HTTP 流式 SSE 适配器

- HTTP POST 到 `/v1/chat/completions`，支持重试（指数退避）
- **真正的 HTTP 流式传输**：使用 `TStreamReader` 从 HTTP 响应流逐行读取 SSE，不再等待整个响应体
- SSE 流式解析：逐行读取 `data: {...}` 行，增量构建文本/思考/工具调用内容块
- 工具调用参数的 **部分 JSON 累积**：跨多个 delta 拼接不完整 JSON
- 支持 `reasoning_effort` 参数控制思考深度（off/minimal/low/medium/high/xhigh）

**流式传输架构**（v5.0 改进）：

```
HTTP Response Stream (chunked transfer)
  → TStreamReader.ReadLine (逐行, 不缓冲全部)
  → ParseSSELine (逐行解析 SSE 格式)
  → 立即回调 TStreamEventCallback
  → 首字延迟从"完整下载+解析"降低到"首行到达"
```

### 4.3 多模型配置

`TModelProfile` 记录支持配置多个模型，运行时快速切换：

```pascal
TModelProfile = record
  Id: string;           // 唯一标识符
  DisplayName: string;  // 显示名称
  Endpoint: string;     // API 端点
  ApiKey: string;       // 认证密钥
  ModelName: string;    // 模型标识
  MaxTokens: Integer;   // 最大 token 数
  Temperature: Double;  // 温度参数
end;
```

- 配置存储 `ModelProfiles: TArray<TModelProfile>` 和 `ActiveModelId`
- 工具栏 `TComboBox` 展示所有模型，切换时调用 `ConnectModel` 重建适配器
- 默认创建一个 'default' 配置文件，匹配基础 API/Model 配置

---

## 五、工具层

### 5.1 文件工具（Tools.FileTools）

| 工具 | 功能 | 关键特性 |
|------|------|----------|
| read | 读取文件（带行号） | offset/limit 分页，上限 2000 行 |
| write | 写入/创建文件 | 自动创建父目录，.bak 备份，**UndoLog 记录** |
| edit | 精确替换文本 | 三层模糊匹配，**UndoLog 记录** |
| ls | 列出目录 | 文件大小显示 |
| find | 按 glob 搜索文件 | 过滤 .gitignore 文件 |
| grep | 搜索文件内容 | 正则/字面量、大小写忽略、glob 过滤、上下文行 |

**Edit 工具模糊匹配**：AI 提供的 `oldText` 常有空白差异，模糊匹配通过归一化行尾符、折叠空行、逐行滑动窗口评分来容忍这些差异。

**UndoLog 集成**：Write/Edit 工具在执行前捕获原始文件内容，执行成功后通过 `FUndoLog.RecordOperation` 记录到撤销日志。

### 5.2 Bash 工具（Tools.BashTool）

- 通过 `CreateProcessW` + 管道捕获 stdout/stderr
- 禁止危险命令：`format`、`del /s`、`rd /s`、`rmdir /s`、`shutdown`
- 可配置超时（默认 30 秒），超时自动终止进程
- 输出超过 50KB 自动截断
- 默认禁用，需在 `settings.json` 中启用

### 5.3 Git 工具（Tools.GitTool）

提供 4 个 Git 操作工具，复用 BashTool 的 `CreateProcessW` + 管道模式：

| 工具名 | 命令 | 参数 | 说明 |
|--------|------|------|------|
| `git_status` | `git --no-pager status` | `path?` | 查看工作区状态 |
| `git_diff` | `git --no-pager diff` | `path`, `staged?` | 查看差异（可选暂存区） |
| `git_log` | `git --no-pager log` | `path?`, `count?`(默认10), `oneline?` | 查看提交历史 |
| `git_blame` | `git --no-pager blame` | `path`, `startLine?`, `endLine?` | 查看行级修改归属 |

**特性**：
- 所有命令使用 `--no-pager` 避免交互式分页
- 默认启用，不需要用户确认
- 非 Git 仓库目录返回友好错误信息
- 权限通过 `permissions.git` 控制

---

## 六、UI 层

### 6.1 UI.MainForm — ChatGPT 风格主窗口

**UI 结构**：

```
TMainForm
  ├── FToolBar (alTop, 44px)
  │     ├── FBtnToggleSidebar (☰ 汉堡按钮)
  │     ├── FCmbModel (模型下拉框)
  │     └── FBtnMenu (... 菜单按钮) → TPopupMenu
  │           └── FMnuUndo (撤销菜单项)
  ├── FToolbarBorder (alTop, 1px 分隔线)
  ├── FSessionPanel (alLeft, 220px, 可折叠)
  │     ├── FBtnNewChat (alTop, "New Chat" 按钮)
  │     └── FSessionList (alClient, Owner-Draw, 右键菜单)
  ├── FSessionBorder (alLeft, 1px 分隔线)
  ├── FChatScrollBox (alClient, 聊天气泡区域)
  │     ├── [动态] TPanel 消息容器
  │     │     ├── TLabel 角色标签
  │     │     ├── TFlatButton CopyMessage 按钮 (气泡上方, Name='CopyMsg')   ← v6.0
  │     │     └── TBubblePanel 圆角气泡
  │     │           └── ContentPanel (Name='ContentPanel', Align=alClient)   ← v6.0
  │     │                 ├── TRichEdit (Name='MD', 文本段, Markdown RTF)
  │     │                 ├── TPanel (Name='CB', 代码块容器)                  ← v6.0
  │     │                 │    ├── TPanel (Name='CBH', 标题栏, Height=24)
  │     │                 │    │    ├── TLabel (语言名称)
  │     │                 │    │    └── TFlatButton (Name='CopyCode', Copy 按钮)
  │     │                 │    └── TMemo (Name='CBC', 等宽代码内容)
  │     │                 ├── TRichEdit (文本段2)
  │     │                 └── TPanel (代码块2) ...
  │     └── FWelcomePanel (欢迎屏, 覆盖层)
  ├── FSearchPanel (alTop, 搜索栏)
  │     ├── FSearchEdit (搜索输入框)
  │     ├── FBtnSearchPrev / FBtnSearchNext (上/下一个)
  │     ├── FSearchLabel (匹配计数 "3 of 15")
  │     └── FBtnSearchClose (关闭搜索)
  ├── FBtnStop (浮动, 流式时显示)
  ├── FSplitter (alBottom)
  ├── FInputPanel (alBottom, 自动高度)
  │     ├── FInputBorder (2px 分隔线)
  │     ├── FInputMemo (bsNone, 自动扩展)
  │     └── FBtnSend (▶ 按钮, 内嵌右下角)
  └── FStatusBar (alBottom)
```

**气泡渲染系统**（v6.0 重构）：

- `TBubblePanel`：继承 `TPanel`，重写 `Paint` 使用 `Canvas.RoundRect` 绘制 12px 圆角矩形
- `Hint` 属性存储原始 Markdown 文本（用于主题切换时重渲染）
- `Tag` 属性高位存储气泡类型标识（20 = 助手消息）
- `AddMessageBubble`：创建消息气泡，助手消息使用 `RenderMarkdownToBubble` 多段渲染
- 用户消息右对齐（80% 宽度，蓝色背景 + 蓝色边框）
- 助手消息左对齐（85% 宽度，灰色背景 + 灰色边框）
- 工具结果/错误消息左对齐（90% 宽度，对应颜色背景 + 边框）

**代码块拆分渲染**（v6.0 新增）：

```
助手气泡内部结构：
  TBubblePanel (Hint=原始Markdown)
    └── ContentPanel (Align=alClient, Margins=14,10,14,10)
         ├── TRichEdit (Name='MD', Align=alTop)    ← Markdown 文本段
         ├── TPanel (Name='CB', Align=alTop)        ← 代码块容器
         │    ├── TPanel (Name='CBH', Height=24)    ← 标题栏（语言名 + Copy 按钮）
         │    └── TMemo (Name='CBC', Align=alClient) ← 等宽代码内容
         ├── TRichEdit ...                           ← 文本段2
         └── TPanel ...                              ← 代码块2
```

- `ParseMarkdownSegments`：将原始 Markdown 解析为 `TArray<TMarkdownSegment>`
- `RenderMarkdownToBubble`：遍历段落数组，交替创建 TRichEdit（文本段）和代码块容器（代码段）
- `CreateCodeBlockPanel`：创建代码块 UI（标题栏 + Copy 按钮 + TMemo）
- `MeasureContentPanel`：测量 ContentPanel 内所有子控件的总高度
- 每个代码块的 Copy 按钮仅复制该块的代码内容

**Markdown 渲染流程**（v6.0 重构）：

```
流式中:  TLabel 累积纯文本（快速, 33ms 节流 ~30fps）
流式结束:
  1. 获取完整 Markdown 文本
  2. ParseMarkdownSegments(text) → TArray<TMarkdownSegment>
  3. 遍历段落数组:
     - mskText → MarkdownToRtf(text, Colors) → TRichEdit 加载 RTF
     - mskCodeBlock → CreateCodeBlockPanel(language, code) → 独立代码块容器
  4. MeasureContentPanel(ContentPanel) → 设置气泡高度
  5. AddCopyMessageButton → 气泡上方 Copy Message 按钮
```

**流式渲染**（v6.0 优化）：
- 首次 delta 创建 TLabel 气泡，保存 `FStreamingLabel` 引用
- 后续 delta 更新 `FStreamingLabel.Caption`，重新计算高度
- **33ms 节流（~30fps）**，比 v5.0 的 50ms 提升 50% 帧率
- 使用 `TStreamDeltaEvent` 轻量级事件，不克隆完整消息
- 结束时替换为多段 ContentPanel（TRichEdit + 代码块 + Copy Message 按钮）

**UI 性能优化**（v6.0 新增）：

| 优化项 | 技术 | 效果 |
|--------|------|------|
| 按钮闪烁 | TFlatButton 位图缓存 (`FCacheBitmap`) | 消除按钮重绘闪烁 |
| 主题切换卡顿 | `DeferredThemeRenderTick` 延迟渲染（每 tick 处理 5 项） | 避免一次性重绘所有消息 |
| 会话列表闪烁 | `OnMouseMove` 追踪悬停项（替代每次 `GetCursorPos`） | 减少系统调用 |
| 窗口缩放卡顿 | `FResizeTimer` 80ms 去抖 | 避免每次 resize 事件都重排消息 |
| 流式帧率 | 33ms 节流 + TLabel 替代 TMemo | ~30fps 流式显示 |
| 流式内存 | TStreamDeltaEvent 轻量事件 | 消除每 delta 的消息克隆开销 |

**Copy Message 按钮**（v6.0 新增）：
- 每条助手消息气泡上方显示 "Copy Message" 按钮（`TFlatButton`, Name='CopyMsg'）
- 点击后复制气泡内所有文本内容到剪贴板
- 按钮临时显示 "Copied!"，2 秒后自动恢复
- 通过 `TCopyRestoreHelper` 计时器实现自动恢复

**会话内搜索**：
- `Ctrl+F` 显示搜索栏面板（聊天区顶部）
- 遍历 `FChatScrollBox` 中所有气泡，递归搜索 ContentPanel 内的 TRichEdit 和代码块 TMemo
- TMemo 用 `Pos()` + `EM_SETSEL` 高亮
- TRichEdit 用 `FindText()` API
- Next/Prev 导航，显示匹配计数 "3 of 15"

**文件拖放**：
- `FormShow` 中调用 `DragAcceptFiles(Self.Handle, True)`
- 处理 `WM_DROPFILES` 消息，读取文件内容
- 安全检查：大小限制（1MB）、二进制检测（前 8KB 含 null 字节则拒绝）
- 组合为 `[User dropped file: xxx]` + 代码围栏内容发送给 Agent

**鼠标滚轮处理**：
- TMemo/TRichEdit 子控件会截获 WM_MOUSEWHEEL
- 通过 `Application.OnMessage` 拦截，手动调整 `FChatScrollBox.VertScrollBar.Position`

**输入框自动扩展**：
- `InputMemoChange` 根据 `Lines.Count` 动态调整 `FInputPanel.Height`（52px ~ 160px）

### 6.2 UI.ThemeManager — 46+ 色主题系统

`TThemeColors` 记录包含 46+ 个颜色字段：

| 分类 | 字段 | 用途 |
|------|------|------|
| 背景层级 | Background, Surface, Border | 主背景、面板、分隔线 |
| 文本 | Text, TextSecondary, Accent | 主文本、次要文本、强调色 |
| 消息气泡 | UserMessage/Border, AssistantMessage/Border | 用户/助手气泡背景 + 边框 |
| 错误/工具 | ErrorMessage/Border, ToolMessage/Border | 错误/工具气泡背景 + 边框 |
| Diff | DiffAdded, DiffRemoved, DiffContext | 确认面板 Diff 着色 |
| 确认 | WarningColor, ApproveBg, RejectBg | 警告标题、批准/拒绝按钮 |
| 建议 | SuggestionBg, SuggestionBorder, SuggestionHover | 欢迎屏建议卡片 |
| 输入 | InputCardBg, InputCardBorder | 输入框卡片 |
| 分支 | BranchIndicator, LeafIndicator, TreeConnector | 会话分支标记 |
| 按钮 | ButtonBackground, ButtonText | 按钮样式 |
| **Markdown/代码** | **CodeBlockBg, CodeBlockBorder, CodeBlockText** | **代码块背景、边框、文本色** |
| **Markdown/代码** | **InlineCodeText, HeaderColor, LinkColor** | **行内代码、标题、链接色** |
| **Markdown/代码** | **QuoteColor, BoldColor** | **引用、加粗文本色** |

**动态重新着色**：`ApplyTheme` 遍历 `FChatScrollBox` 中所有已有消息气泡，根据 `Tag` 重新分配颜色和边框。助手消息通过 `DeferredThemeRenderTick` 延迟重渲染（每 tick 5 项），避免主题切换时界面冻结。支持旧式直接 TRichEdit 和新式 ContentPanel 两种气泡结构。

### 6.3 UI.CustomButton — 位图缓存按钮（v6.0 重写）

`TFlatButton` 使用位图缓存消除闪烁：

```pascal
TFlatButton
  FCacheBitmap: TBitmap;     // 离屏缓存位图
  FCacheValid: Boolean;      // 缓存有效性标志
  procedure InvalidateCache; // 标记缓存失效
  procedure RebuildCache;    // 重绘到 FCacheBitmap
  procedure Paint; override; // 直接绘制 FCacheBitmap
  procedure WMSize;          // Size 改变时 InvalidateCache
end;
```

**关键优化**：
- 仅在状态实际变化时调用 `Invalidate`（`MouseEnter/Leave/Down/Up` 检查当前状态）
- `Paint` 直接将 `FCacheBitmap` 绘制到 Canvas，避免重复文本测量和绘制
- `WMSize` 时重建缓存（窗口缩放适配）
- 析构函数释放 `FCacheBitmap`

### 6.4 Utils.Markdown — Markdown→RTF 转换器 + 段落解析

`Utils.Markdown.pas` 实现纯 Delphi 的 Markdown 到 RTF 转换，不依赖第三方库。

**段落解析器**（v6.0 新增）：

```pascal
TMarkdownSegmentKind = (mskText, mskCodeBlock);
TMarkdownSegment = record
  Kind: TMarkdownSegmentKind;
  Text: string;       // mskText: markdown文本; mskCodeBlock: 代码内容
  Language: string;    // 仅 mskCodeBlock: 语言标识（如 python, bash）
end;
function ParseMarkdownSegments(const AMarkdown: string): TArray<TMarkdownSegment>;
```

- 逐行扫描，`` ``` `` 开始时提取语言名（如 `` ```python `` → Language='python'）
- 代码块内容收集到 `Text`
- 非代码文本收集到 `Text`，相邻非代码行合并为一个 mskText 段
- 支持未闭合代码块的容错处理

**支持的 Markdown 元素**：

| 元素 | Markdown 语法 | RTF 渲染方式 |
|------|--------------|-------------|
| 标题 | `#` ~ `####` | 加粗 + HeaderColor + 字号递增 |
| 粗体 | `**text**` 或 `__text__` | `\b text\b0` |
| 斜体 | `*text*` 或 `_text_` | `\i text\i0` |
| 代码块 | ` ```lang ` | 独立代码块容器（标题栏 + Copy按钮 + TMemo） |
| 行内代码 | `` `code` `` | 等宽字体 + InlineCodeText |
| 引用 | `> text` | 左边框 + QuoteColor |
| 无序列表 | `- item` / `* item` | 缩进 + 项目符号 |
| 有序列表 | `1. item` | 缩进 + 数字编号 |
| 表格 | `\| col \|` | RTF 表格行 |
| 水平线 | `---` / `***` | 分隔线 |
| 链接 | `[text](url)` | LinkColor + 下划线 |

**核心函数**：

- `MarkdownToRtf(AMarkdown: string; AColors: TMarkdownColors; ABaseFont: TFont): string` — 主转换函数
- `ParseMarkdownSegments(AMarkdown: string): TArray<TMarkdownSegment>` — 段落解析（v6.0 新增）
- `HasCodeBlocks(AMarkdown: string): Boolean` — 快速检测是否含代码块

**TConverter 内部优化**：
- `EmitEscaped` 方法直接写入 `TStringBuilder`，替代旧的字符串拼接
- `FRtfCodeStart`/`FRtfCodeEnd` 预计算 RTF 控制字符串，避免运行时拼接

### 6.5 UI.SettingsForm / UI.HelpForm

- **设置窗口**：4 选项卡（API、Model、UI、Paths），全主题化，浏览目录按钮
- **帮助窗口**：3 选项卡（About、Shortcuts、Tips），全主题化

---

## 七、配置系统

### 7.1 双层配置

```
项目配置 (.pimonorc / .pi/settings.json)
    ↓ 覆盖
全局配置 (%APPDATA%/PiMono/settings.json)
    ↓ 默认值
代码默认值 (TPiMonoConfig.GetDefault)
```

### 7.2 配置结构

```json
{
  "version": "1.0",
  "api": { "endpoint", "apiKey", "modelsEndpoint", "timeout", "retryCount", "retryDelay", "enableStreaming" },
  "model": { "name", "maxTokens", "temperature", "topP", "frequencyPenalty", "presencePenalty" },
  "modelProfiles": [
    {
      "id": "default",
      "displayName": "Moonshot v1",
      "endpoint": "https://api.moonshot.cn/v1/",
      "apiKey": "sk-xxx",
      "modelName": "moonshot-v1-128k",
      "maxTokens": 8192,
      "temperature": 0.7
    }
  ],
  "activeModelId": "default",
  "directories": { "working", "backup", "cache", "logs" },
  "ui": { "theme", "fontSize", "fontFamily", "windowWidth", "windowHeight", "language" },
  "permissions": {
    "read":   { "enabled": true,  "requireConfirmation": false, "maxFileSize": 10485760 },
    "write":  { "enabled": true,  "requireConfirmation": true },
    "edit":   { "enabled": true,  "requireConfirmation": true },
    "bash":   { "enabled": false, "requireConfirmation": true },
    "git":    { "enabled": true,  "requireConfirmation": false }
  },
  "session": { "autoSave", "autoSaveInterval", "maxSessions", "defaultThinkingLevel", "compactionEnabled", "reserveTokens", "keepRecentTokens" },
  "logging": { "level", "maxFileSize", "maxFiles" }
}
```

---

## 八、安全设计

| 层级 | 措施 |
|------|------|
| 网络层 | 纯内网通信，不连接外部互联网 |
| 工具权限 | Read/Write/Edit/Bash/Git 五级独立开关 |
| 编辑确认 | Write/Edit 默认需用户审批 Diff 预览 |
| 命令安全 | Bash 禁止 format/del /s/rd /s/shutdown |
| 路径安全 | 所有文件操作限制在 Working Directory 内 |
| 编辑安全 | Edit 工具 .bak 备份 + 失败自动回滚 |
| 循环防护 | MaxTurns 上限 30 轮，防止无限工具调用 |
| 输出截断 | Bash 输出超 50KB 截断，工具结果可精简 |
| 撤销回滚 | 所有文件写/编辑操作记录 UndoLog，支持逐次撤销 |
| 拖放安全 | 文件大小限制 1MB，二进制文件检测拒绝 |

---

## 九、国际化

`Utils.Localization` 提供双语支持（英语/中文），通过 `L(Key)` 函数访问翻译字符串。

涵盖：工具栏/菜单按钮、会话面板、确认按钮、状态消息、聊天显示、欢迎屏标题/副标题/建议卡片、会话管理消息、Skill/Template 确认、设置表单标签、帮助表单内容。

v6.0 新增本地化字符串（2 条）：

| Key | English | 中文 |
|-----|---------|------|
| `chat.copyMsg` | Copy | 复制消息 |
| `chat.copyMsgDone` | Copied! | 已复制! |

v5.0 本地化字符串（14 条）：

| Key | English | 中文 |
|-----|---------|------|
| `chat.codeCopy` | Copy Code | 复制代码 |
| `chat.codeCopied` | Copied! | 已复制! |
| `chat.dropTooLarge` | File too large: %s | 文件过大: %s |
| `chat.dropBinary` | Cannot read binary: %s | 无法读取二进制文件: %s |
| `chat.undo` | Undo | 撤销 |
| `chat.undoSuccess` | Restored: %s | 已恢复: %s |
| `chat.undoEmpty` | Nothing to undo | 没有可撤销的操作 |
| `chat.searchNoMatch` | No matches | 无匹配 |
| `chat.searchMatchInfo` | %d of %d | 第 %d / %d 个 |
| `settings.activeModel` | Active Model | 当前模型 |
| `settings.tabModels` | Models | 模型列表 |
| `btn.undo` | Undo | 撤销 |
| `chat.dropFiles` | Drop files here | 拖放文件到此处 |
| `chat.search` | Search | 搜索 |

---

## 十、依赖关系

所有依赖均为 Delphi 自带，无第三方库：

- `System.Net.HttpClient` — HTTP 请求（流式 chunked 传输）
- `System.JSON` — JSON 序列化/反序列化
- `System.SyncObjs` — TEvent / TCriticalSection 线程同步
- `Vcl.*` — 标准 VCL 控件（含 TRichEdit）
- `Winapi.ShellAPI` — DragAcceptFiles / WM_DROPFILES 文件拖放
- `Vcl.Clipbrd` — 剪贴板操作（代码复制按钮 + 消息复制按钮）

---

*PiMono Agent 6.0 — 内部网络 AI 代码编辑助手（Delphi Edition）*
