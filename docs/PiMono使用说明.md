# PiMono Agent 使用说明书

> 版本 6.0 | Delphi Edition | 内部网络 AI 代码编辑助手
> 界面风格：ChatGPT/Gemini 风格 TScrollBox 气泡 UI + Markdown 渲染 + 代码块拆分
> 更新日期：2026-04-21

---

## 目录

1. [项目简介](#1-项目简介)
2. [环境要求](#2-环境要求)
3. [编译与构建](#3-编译与构建)
4. [首次运行配置](#4-首次运行配置)
5. [界面布局](#5-界面布局)
6. [基本使用流程](#6-基本使用流程)
7. [Markdown 渲染](#7-markdown-渲染)
8. [代码块拆分渲染](#8-代码块拆分渲染)
9. [消息复制](#9-消息复制)
10. [多模型切换](#10-多模型切换)
11. [文件拖放](#11-文件拖放)
12. [撤销/回滚](#12-撤销回滚)
13. [会话内搜索](#13-会话内搜索)
14. [Git 工具](#14-git-工具)
15. [设置详解](#15-设置详解)
16. [会话管理](#16-会话管理)
17. [特殊命令](#17-特殊命令)
18. [快捷键](#18-快捷键)
19. [工具说明](#19-工具说明)
20. [编辑确认](#20-编辑确认)
21. [主题与外观](#21-主题与外观)
22. [目录与文件结构](#22-目录与文件结构)
23. [配置文件详解](#23-配置文件详解)
24. [日志系统](#24-日志系统)
25. [常见问题](#25-常见问题)
26. [安全说明](#26-安全说明)

---

## 1. 项目简介

PiMono Agent 是一个运行在内部网络的 **AI 代码编辑助手**，使用 Delphi 11.x Alexandria + VCL 构建。它通过 OpenAI 兼容 API 连接内部 LLM 服务，提供 ChatGPT/Gemini 风格的桌面体验。

### 核心特性

- **ChatGPT 风格气泡 UI** — 圆角消息气泡、可折叠侧栏、欢迎屏、浮动操作按钮
- **Markdown 渲染** — AI 回复自动渲染标题、粗体、斜体、代码块、行内代码、引用、表格、链接
- **代码块拆分渲染** — 每个代码块独立显示：语言标签 + Copy 按钮 + 等宽代码内容（ChatGPT 风格）
- **消息复制** — 每条气泡上方有 Copy 按钮，一键复制整条消息内容
- **消息可选择/复制** — 每条气泡内嵌 TMemo/TRichEdit，支持文本选中与复制
- **流式实时显示** — AI 回复逐字流式渲染，33ms 节流（~30fps）
- **UI 性能优化** — 位图缓存按钮、延迟主题渲染、窗口缩放去抖、轻量级流式事件
- **多模型切换** — 配置多个模型配置文件，工具栏快速切换
- **文件拖放** — 将文件拖入窗口，自动读取内容发送给 AI
- **撤销/回滚** — 所有文件写/编辑操作可逐次撤销（Ctrl+Z）
- **会话内搜索** — Ctrl+F 搜索聊天记录，高亮匹配，上下导航
- **Git 集成** — 内置 git status/diff/log/blame 工具
- **深色/浅色主题** — 46+ 色主题系统，一键切换，动态重新着色已有消息
- **中英双语** — 界面语言一键切换
- **对话式代码编辑** — 文件读写、搜索、编辑（三层模糊匹配）
- **Shell 命令执行** — 可选，带权限控制与安全过滤
- **多会话管理** — 会话列表、分支、JSONL 持久化
- **编辑确认** — AI 修改文件前显示 diff 预览，用户审批
- **自动上下文压缩** — 长对话自动摘要，三层压缩策略
- **Skills 与模板命令** — `/skill:` 和 `/template:` 命令系统
- **会话 HTML 导出** — 导出为暗色主题 HTML 文件

---

## 2. 环境要求

| 项目 | 要求 |
|------|------|
| 操作系统 | Windows 10 / 11 |
| 开发环境 | RAD Studio / Delphi 11.x Alexandria |
| 网络 | 可访问内部 LLM API 服务器（纯内网，不依赖外部互联网） |
| API 服务器 | 提供 OpenAI 兼容接口（`/v1/chat/completions`、`/v1/models`） |
| 依赖库 | System.Net.HttpClient、System.JSON、System.SyncObjs、Vcl.Clipbrd（均随 Delphi 自带，无第三方库） |

---

## 3. 编译与构建

### 3.1 打开项目

1. 启动 Delphi 11.x Alexandria
2. 菜单 → File → Open Project → 选择 `PiMonoDelphi\PiMono.dpr`

### 3.2 项目结构

```
PiMonoDelphi/
├── PiMono.dpr              # 项目主文件
├── Core/                   # 核心逻辑
│   ├── App.Main.pas        # 应用初始化 + 项目上下文 + Git 分支检测
│   ├── Core.Agent.pas      # Agent 编排器（循环 + 权限 + 确认 + 队列）
│   ├── Core.AgentState.pas # Agent 状态 + 工具接口
│   ├── Core.Compaction.pas # 三层上下文压缩
│   ├── Core.Events.pas     # 事件系统（12 种事件类型 + TStreamDeltaEvent）
│   ├── Core.Messages.pas   # 消息与内容块类型（JSON 序列化 + Clone）
│   ├── Core.SessionManager.pas  # JSONL 会话持久化（追加写入 + 分支）
│   ├── Core.ToolResultSlim.pas  # 工具结果精简
│   └── Core.UndoLog.pas    # 操作撤销日志（JSONL 持久化 + FIFO 淘汰）
├── AI/                     # AI 模型适配层
│   ├── AI.IModel.pas       # 模型接口 + API 格式定义
│   ├── AI.CustomAPIAdapter.pas  # HTTP 流式 SSE 适配器（chunked 传输）
│   └── AI.ModelConfig.pas  # 模型配置 + 成本计算
├── Tools/                  # 工具集
│   ├── Tools.ITool.pas     # 工具接口与基类（路径安全 + UndoLog 集成）
│   ├── Tools.ToolRegistry.pas   # 工具注册表
│   ├── Tools.FileTools.pas # 6 个文件工具 + 三层模糊匹配 + 撤销记录
│   ├── Tools.BashTool.pas  # Shell 命令工具（安全过滤 + 超时）
│   └── Tools.GitTool.pas   # 4 个 Git 工具（status/diff/log/blame）
├── Settings/               # 配置管理
│   ├── Settings.Config.pas       # 配置记录 + TModelProfile 多模型配置
│   └── Settings.SettingsManager.pas  # 双层配置管理器（项目 > 全局 > 默认）
├── UI/                     # 界面
│   ├── UI.MainForm.pas     # 主窗口（多段气泡 UI + 代码块拆分 + 搜索 + 拖放）
│   ├── UI.SettingsForm.pas # 设置窗口（4 选项卡）
│   ├── UI.HelpForm.pas     # 帮助窗口（3 选项卡）
│   ├── UI.ThemeManager.pas # 46+ 色主题管理（深色/浅色）
│   └── UI.CustomButton.pas # 位图缓存自定义按钮组件（v6.0 重写）
├── Utils/                  # 工具类
│   ├── Utils.JsonHelper.pas    # JSON 兼容垫片
│   ├── Utils.Logger.pas        # 线程安全日志（轮转）
│   ├── Utils.Localization.pas  # 中英双语国际化
│   ├── Utils.Markdown.pas      # Markdown→RTF 转换器 + 段落解析器
│   └── Utils.TokenEstimator.pas # Token 估算
└── docs/                   # 文档
    ├── PiMono_Delphi_架构技术报告.md
    └── PiMono使用说明.md
```

### 3.3 编译

1. 确认 `PiMono.dpr` 中所有单元路径正确
2. 菜单 → Project → Build PiMono（或按 `Ctrl+F9`）
3. 编译成功后生成 `PiMono.exe`

### 3.4 首次运行

首次启动时，程序会自动创建以下目录和文件：

| 路径 | 用途 |
|------|------|
| `%APPDATA%\PiMono\` | 全局配置目录 |
| `%APPDATA%\PiMono\settings.json` | 全局配置文件（自动生成默认值） |
| `%APPDATA%\PiMono\sessions\` | 会话存储目录（JSONL 格式） |
| `%LOCALAPPDATA%\PiMono\Logs\` | 日志文件目录 |
| `%LOCALAPPDATA%\PiMono\Cache\` | 缓存目录 |
| `%LOCALAPPDATA%\PiMono\Cache\undo_log.jsonl` | 操作撤销日志 |

> 启动时会自动将旧的 `.json` 会话文件迁移为 `.jsonl` 格式。

---

## 4. 首次运行配置

### 4.1 配置 API 连接

首次运行后，需要配置内部 LLM API 地址：

1. 点击工具栏右侧 **"..."** 菜单按钮 → 选择 **Settings**（或按 `Ctrl+,`）
2. 在 **API** 选项卡中填入：
   - **API Endpoint**：内部 LLM 服务的接口地址（默认：`https://api.moonshot.cn/v1/`）
   - **API Key**：认证密钥
   - **Enable Streaming**：勾选以启用 SSE 流式响应（推荐）
   - **Timeout**：请求超时毫秒数（默认 60000）
   - **Retry Count**：失败重试次数（默认 3 次）
3. 点击 **Save** 保存

### 4.2 配置模型

在 **Model** 选项卡中：

| 字段 | 默认值 | 说明 |
|------|--------|------|
| Model Name | `moonshot-v1-128k` | 模型标识符 |
| Max Tokens | `8192` | 单次响应最大 token 数 |
| Temperature | `0.7` | 创造性程度（0-2） |
| Top P | `1.0` | 核采样参数 |
| Thinking Level | `medium` | 思考深度（off/minimal/low/medium/high/xhigh） |

### 4.3 配置工作目录

在 **Paths** 选项卡中：

- **Working Directory**：Agent 操作文件的根目录（默认 `%USERPROFILE%\Projects`）
- **Backup Directory**：文件编辑备份目录

> Agent 的所有文件操作都基于 Working Directory 执行。

---

## 5. 界面布局

### 5.1 整体结构

```
┌──────────────────────────────────────────────────────────────┐
│  [☰]  [Moonshot v1 ▼]                            [...]      │  ← 工具栏（模型下拉框 + 菜单）
│──────────────────────────────────────────────────────────────│  ← 1px 分隔线
┌──────────┬───────────────────────────────────────────────────┐
│          │  ┌─ 搜索栏 (Ctrl+F) ──────────────────────┐       │
│ [New Chat]│  │ [搜索框] [◀] [▶] 3 of 15     [×]     │       │  ← 可展开搜索栏
│          │  └──────────────────────────────────────────┘       │
│ Session 1│                                                   │
│ Session 2│      ╭─────────────────────────────╮              │
│ Session 3│      │ You:                         │              │  ← 用户气泡（蓝色，右对齐 80%）
│ [B] Sess4│      │ 帮我分析 main.pas 的结构     │              │
│          │      ╰─────────────────────────────╯              │
│          │                                                   │
│          │  Assistant:                              [Copy]    │  ← 消息复制按钮
│          │      ╭─────────────────────────────────────╮      │
│          │      │ ## 代码结构                          │      │  ← 助手气泡（TRichEdit Markdown）
│          │      │ 这个文件包含以下结构...              │      │
│          │      │ ┌────────────────────────────────┐  │      │  ← 独立代码块容器
│          │      │ │ pascal                    [Copy]│  │      │  ← 标题栏（语言 + 复制按钮）
│          │      │ │ procedure TForm1.Click;         │  │      │  ← 等宽代码内容
│          │      │ │ begin                           │  │      │
│          │      │ │   ShowMessage('Hello');         │  │      │
│          │      │ │ end;                            │  │      │
│          │      │ └────────────────────────────────┘  │      │
│          │      │ 以下是第二段代码...                  │      │
│          │      │ ┌────────────────────────────────┐  │      │  ← 第二个代码块（独立）
│          │      │ │ bash                      [Copy]│  │      │
│          │      │ │ dcc32 PiMono.dpr                │  │      │
│          │      │ └────────────────────────────────┘  │      │
│          │      ╰─────────────────────────────────────╯      │
│          │                                                   │
│          │          ╭───────────────────╮  [Stop]            │  ← 浮动 Stop 按钮
│──────────│──────────│ 输入消息...        │──────────[▶]──────│  ← 无边框输入区
│          │          ╰───────────────────╘                    │
├──────────┴───────────────────────────────────────────────────┤
│ Ready (12K tokens) [main]                                    │  ← 状态栏
└──────────────────────────────────────────────────────────────┘
```

### 5.2 区域说明

| 区域 | 组件 | 说明 |
|------|------|------|
| 工具栏 | ☰ 汉堡按钮 + 模型下拉框 + "..." 菜单 | 汉堡按钮切换侧栏；下拉框切换模型；"..." 打开弹出菜单 |
| 侧栏（可折叠） | New Chat + 会话列表 | 220px 宽，Owner-Draw 渲染，右键菜单（打开/重命名/删除） |
| 搜索栏 | 输入框 + 上/下/关闭按钮 | `Ctrl+F` 展开，搜索聊天区所有消息（含代码块内容），显示匹配计数 |
| 聊天区 | TScrollBox + 动态气泡 | 圆角气泡、Markdown 渲染、代码块拆分、消息复制、鼠标滚轮滚动 |
| 欢迎屏 | 居中标题 + 4 建议卡片 | 新会话时显示，发送消息后自动消失 |
| 输入区 | 无边框 TMemo + ▶ 发送按钮 | 自动扩展高度（52px ~ 160px），Enter 发送，支持拖放文件 |
| Stop 按钮 | 浮动红色按钮 | 流式时显示在底部居中，结束后自动隐藏 |
| 状态栏 | TStatusBar | 显示运行状态 + token 用量 + git 分支 |

### 5.3 消息气泡视觉样式

| 消息类型 | 角色标签 | 气泡颜色（深色主题） | 对齐方式 | 最大宽度 | 内容控件 |
|----------|----------|---------------------|----------|----------|----------|
| 用户消息 | "You:" 强调色加粗 | 深蓝 $1E3A5F + 蓝色边框 | **右对齐** | 80% | TMemo |
| 助手消息 | "Assistant:" 次要色加粗 | 深灰 $2A2A2A + 灰色边框 | 左对齐 | 85% | **多段 ContentPanel** |
| 工具调用 | "[Tool: xxx]" 强调色加粗 | 无气泡（纯标签） | 左对齐 | — | — |
| 工具结果 | "[ToolName]" 次要色 | 橄榄色 $3A3A1A + 边框 | 左对齐 | 90% | TMemo |
| 错误结果 | "[ToolName]" 次要色 | 深红 $5C1A1A + 红色边框 | 左对齐 | 90% | TMemo |
| 系统消息 | 无角色标签 | 无气泡（次级色文字） | 左对齐 | — | TMemo |
| Diff 预览 | "[Confirmation Required]" | 多色行（红/绿/灰） | 左对齐 | — | TMemo |

所有气泡均为 **12px 圆角**（`TBubblePanel` 自定义绘制）。

**助手消息气泡**（v6.0）使用多段 ContentPanel 结构：
- **文本段**：TRichEdit 渲染 Markdown RTF（标题、粗体、斜体、行内代码、引用、列表、表格、链接）
- **代码块段**：独立容器（语言标签标题栏 + Copy 按钮 + 等宽 TMemo）
- 文本段与代码块段交替排列，每段独立测量高度

---

## 6. 基本使用流程

### 6.1 发起对话

1. 在底部输入框中输入你的问题或指令
2. 按 **Enter** 发送（或点击右侧 **▶** 按钮）
3. AI 回复会**实时流式显示**在聊天区：
   - 首次 delta 自动创建助手气泡（流式中使用 TLabel）
   - 后续 delta 增量更新气泡文本（33ms 节流，~30fps）
   - **流式结束后自动替换为多段 ContentPanel**：
     - 文本段落渲染为 TRichEdit（Markdown RTF 格式）
     - 代码块渲染为独立容器（语言标签 + Copy 按钮 + 等宽代码）
   - 气泡上方自动显示 **Copy** 消息复制按钮
4. 状态栏实时显示：
   - `Agent running...` — Agent 正在工作
   - `Streaming...` — AI 正在生成回复
   - `Executing tool: xxx...` — AI 正在调用工具
   - `Ready (12K tokens) [main]` — 回复完成，显示 token 用量和 git 分支

### 6.2 欢迎屏

新会话时显示欢迎屏，包含：
- 居中标题："今天我能帮你做什么？"
- 副标题："让我帮你分析、编辑或搜索代码"
- 4 个建议卡片（2x2 网格布局）：
  - "分析这个项目的结构"
  - "查找代码中所有 TODO 注释"
  - "解释主模块的代码"
  - "帮我重构这个单元"

点击建议卡片会将文本填入输入框（不自动发送），方便修改后发送。

### 6.3 典型使用场景

**代码分析**
```
你：帮我分析 src/utils/helper.pas 的代码结构
AI 会调用 read 工具读取文件，然后给出分析结果（Markdown 格式渲染）
```

**代码编辑**（需确认）
```
你：把 helper.pas 中的 TStringUtils.CamelToSnake 方法改为支持带点号的命名空间
AI 会先读取文件，确认代码位置，然后弹出 diff 预览：
  [Confirmation Required] Tool: edit  File: helper.pas
  - 旧代码
  + 新代码
  [Approve] [Reject]
点击 Approve 后执行修改
执行后可通过 Ctrl+Z 撤销
```

**项目搜索**
```
你：在项目中搜索所有调用 GetConfig 的地方
AI 会调用 grep 工具搜索，自动过滤 .gitignore 中的文件
```

**Git 操作**
```
你：查看当前项目的 git 状态和最近的提交
AI 会调用 git_status 和 git_log 工具
```

**文件拖放**
```
将 helper.pas 文件从资源管理器拖入窗口
AI 自动读取文件内容并分析
```

**运行命令**（需启用 Bash 权限）
```
你：运行项目的单元测试
AI 会调用 bash 工具执行测试命令
```

### 6.4 中止操作

- 点击浮动 **Stop** 按钮（底部居中红色按钮）
- 按 **Escape** 键
- 如果正在等待编辑确认，会自动拒绝并中止
- 中止时自动清理未完成的流式气泡

---

## 7. Markdown 渲染

### 7.1 概述

AI 助手的回复自动以 Markdown 格式渲染，提供丰富的视觉体验。渲染在流式结束后自动完成，无需手动操作。

### 7.2 支持的 Markdown 元素

| 元素 | 语法 | 效果 |
|------|------|------|
| 标题 | `#` ~ `####` | 加粗、颜色高亮、字号递增 |
| 粗体 | `**text**` | **加粗** |
| 斜体 | `*text*` | *斜体* |
| 代码块 | ` ``` ` | **独立代码块容器**（标题栏 + Copy按钮 + 等宽代码） |
| 行内代码 | `` `code` `` | 等宽字体 + 颜色高亮 |
| 引用 | `> text` | 左边框 + 引用色 |
| 无序列表 | `- item` | 缩进 + 项目符号 |
| 有序列表 | `1. item` | 缩进 + 数字编号 |
| 表格 | `| col |` | 表格行 |
| 水平线 | `---` | 分隔线 |
| 链接 | `[text](url)` | 链接色 + 下划线 |

### 7.3 渲染流程

```
流式中 → TLabel 显示纯文本（快速更新, 33ms 节流 ~30fps）
流式结束 → 自动替换为多段 ContentPanel：
  1. ParseMarkdownSegments() 将 Markdown 解析为文本段和代码块段
  2. 文本段: MarkdownToRtf() → TRichEdit 加载 RTF（富文本显示）
  3. 代码块段: CreateCodeBlockPanel() → 独立容器（语言标签 + Copy按钮 + TMemo）
  4. MeasureContentPanel() → 计算总高度，设置气泡尺寸
```

### 7.4 主题适配

Markdown 渲染颜色跟随主题自动调整：

| 元素 | 深色主题 | 浅色主题 |
|------|----------|----------|
| 代码块背景 | $1E1E1E | $F6F8FA |
| 代码块文本 | $D4D4D4 | $24292F |
| 代码块边框 | $444444 | $D0D7DE |
| 行内代码 | $CE9178 | $CF222E |
| 标题 | $4FC3F7 | $007ACC |
| 链接 | $569CD6 | $0969DA |
| 引用 | $6A9955 | $6A737D |
| 加粗 | $D4D4D4 | $24292F |

切换主题时，所有已显示的助手消息会自动使用新主题色重新渲染（延迟处理，避免界面冻结）。

---

## 8. 代码块拆分渲染

### 8.1 概述

v6.0 新增 **ChatGPT 风格代码块拆分渲染**。当 AI 回复包含多个代码块时，每个代码块独立显示，拥有自己的语言标签、Copy 按钮和等宽代码区域。

### 8.2 代码块结构

每个代码块由三部分组成：

```
┌────────────────────────────────────────┐
│ pascal                            Copy │  ← 标题栏（语言名称 + Copy 按钮）
├────────────────────────────────────────┤
│ procedure TForm1.Click;                │  ← 等宽代码内容（TMemo）
│ begin                                  │
│   ShowMessage('Hello');                │
│ end;                                   │
└────────────────────────────────────────┘
```

- **标题栏**：显示代码块的语言标识（如 `pascal`、`bash`、`python`），右侧为 Copy 按钮
- **Copy 按钮**：点击后仅复制该代码块的内容到剪贴板，显示 "Copied!" 后 2 秒自动恢复
- **代码内容**：等宽字体（Consolas）显示，背景色跟随主题

### 8.3 多代码块示例

当 AI 回复中包含多个代码块时：

```
┌─ 文本段（TRichEdit, Markdown RTF）───────────────┐
│ ## 方案一                                          │
│ 使用以下代码实现...                                 │
├─ 代码块 1 ────────────────────────────────────────┤
│ │ pascal                                     Copy │
│ │ procedure Method1;                               │
│ │ begin ... end;                                   │
├─ 文本段（TRichEdit）──────────────────────────────┤
│ ## 方案二                                          │
│ 或者使用这种方式...                                 │
├─ 代码块 2 ────────────────────────────────────────┤
│ │ bash                                       Copy │
│ │ dcc32 PiMono.dpr                                 │
├─ 文本段（TRichEdit）──────────────────────────────┤
│ 以上两种方案都可以实现目标。                          │
└───────────────────────────────────────────────────┘
```

每个代码块的 Copy 按钮**仅复制该块的代码**，互不影响。

---

## 9. 消息复制

### 9.1 概述

每条助手消息气泡上方都有一个 **Copy** 按钮（位于气泡右上角），可以一键复制整条消息的所有文本内容。

### 9.2 使用方法

1. 找到助手消息气泡上方的 **Copy** 按钮
2. 点击按钮
3. 按钮临时显示 **"Copied!"**，2 秒后自动恢复为 "Copy"
4. 消息的所有文本内容（含代码块）已复制到剪贴板

### 9.3 与代码块复制的区别

| 功能 | 位置 | 复制范围 |
|------|------|----------|
| **消息复制** (Copy) | 气泡上方 | 整条消息的所有文本内容 |
| **代码块复制** (Copy) | 代码块标题栏右侧 | 仅该代码块的代码内容 |

---

## 10. 多模型切换

### 10.1 概述

支持配置多个模型配置文件（Model Profile），每个配置文件可以有不同的 API 端点、密钥、模型名称和参数。通过工具栏下拉框可快速切换。

### 10.2 配置模型

在 `settings.json` 中添加 `modelProfiles` 数组：

```json
{
  "modelProfiles": [
    {
      "id": "moonshot",
      "displayName": "Moonshot v1",
      "endpoint": "https://api.moonshot.cn/v1/",
      "apiKey": "sk-xxx",
      "modelName": "moonshot-v1-128k",
      "maxTokens": 8192,
      "temperature": 0.7
    },
    {
      "id": "deepseek",
      "displayName": "DeepSeek Coder",
      "endpoint": "https://api.deepseek.com/v1/",
      "apiKey": "sk-yyy",
      "modelName": "deepseek-coder",
      "maxTokens": 4096,
      "temperature": 0.5
    }
  ],
  "activeModelId": "moonshot"
}
```

每个 `TModelProfile` 包含：

| 字段 | 说明 |
|------|------|
| `id` | 唯一标识符（字符串） |
| `displayName` | 工具栏下拉框显示名称 |
| `endpoint` | 该模型的 API 端点 |
| `apiKey` | 该模型的认证密钥 |
| `modelName` | 模型标识符 |
| `maxTokens` | 最大响应 token 数 |
| `temperature` | 温度参数 |

### 10.3 切换模型

1. 在工具栏中找到 **模型下拉框**（显示当前活跃模型名称）
2. 点击下拉框选择目标模型
3. 系统自动重建 API 适配器，后续请求使用新模型

> 切换模型后，新发送的消息使用新模型。已有消息不受影响。

### 10.4 默认配置

首次运行时自动创建一个 `id: "default"` 的模型配置文件，使用基础 API 和 Model 配置中的参数。

---

## 11. 文件拖放

### 11.1 使用方法

1. 从 Windows 资源管理器中选择文件
2. 将文件拖入 PiMono 窗口
3. 程序自动读取文件内容，以代码围栏格式发送给 AI

### 11.2 拖放行为

- 文件内容被包装为 `[User dropped file: filename.ext]` + 代码围栏
- 自动根据文件扩展名添加语言标识（如 `.pas` → ````pascal`）
- 支持同时拖放多个文件

### 11.3 安全限制

| 限制 | 说明 |
|------|------|
| 文件大小 | 单文件不超过 **1 MB** |
| 二进制检测 | 前 8 KB 包含 null 字节则拒绝（防止拖入 .exe/.dll 等） |
| 拒绝提示 | 显示 "文件过大: xxx" 或 "无法读取二进制文件: xxx" |

---

## 12. 撤销/回滚

### 12.1 概述

所有通过 AI 执行的文件写入（write）和编辑（edit）操作都会被记录到撤销日志中，可以逐次撤销回滚到之前的状态。

### 12.2 使用方法

- 按 **Ctrl+Z** 撤销最近一次文件操作
- 或点击工具栏菜单 → **Undo**

每次撤销会：
1. 恢复该次操作之前的文件内容
2. 如果该操作是新建文件（之前不存在），撤销时自动删除该文件
3. 状态栏显示 "已恢复: filename"

### 12.3 撤销日志

| 属性 | 值 |
|------|-----|
| 存储位置 | `%LOCALAPPDATA%\PiMono\Cache\undo_log.jsonl` |
| 格式 | JSONL（每行一条 JSON 记录） |
| 容量 | 默认保留最近 **100** 条操作记录 |
| 淘汰策略 | FIFO（超出容量自动淘汰最早记录） |
| 持久化 | 程序重启后保留，可继续撤销 |

### 12.4 记录内容

每条撤销记录包含：

| 字段 | 说明 |
|------|------|
| id | 记录序号 |
| timestamp | 操作时间 |
| path | 文件路径 |
| operation | 操作类型（`write` 或 `edit`） |
| oldContent | 操作前的原始内容（空表示新建文件） |
| toolCallId | 触发操作的工具调用 ID |

### 12.5 注意事项

- 撤销按**时间倒序**逐次回滚（最近操作先撤销）
- 撤销不会影响 AI 的对话历史（仅恢复文件内容）
- 如果文件在 AI 操作后被手动修改，撤销会覆盖手动修改

---

## 13. 会话内搜索

### 13.1 使用方法

1. 按 **Ctrl+F** 打开搜索栏（聊天区顶部）
2. 在搜索框中输入关键词
3. 按 **Enter** 或点击搜索按钮开始搜索
4. 使用 **◀** / **▶** 按钮在匹配结果之间导航
5. 点击 **×** 关闭搜索栏

### 13.2 搜索范围

搜索会遍历当前聊天区所有消息气泡的内容：

- **TRichEdit** 文本段（助手消息的 Markdown 渲染文本）：使用 `FindText()` API 匹配 + 高亮选中
- **TMemo** 气泡（用户消息、工具结果等）：使用 `Pos()` 匹配 + `EM_SETSEL` 高亮选中
- **TMemo** 代码块（助手消息中的代码块内容）：递归搜索 ContentPanel 内的代码块

### 13.3 搜索状态

- 右侧显示匹配计数：**"3 of 15"**（第 3 个，共 15 个匹配）
- 无匹配时显示：**"无匹配"**
- 搜索栏自动滚动到当前匹配位置

### 13.4 快捷键

| 按键 | 操作 |
|------|------|
| `Ctrl+F` | 打开搜索栏 |
| `Enter` | 搜索 / 下一个匹配 |
| `Shift+Enter` | 上一个匹配 |
| `Escape` | 关闭搜索栏 |

---

## 14. Git 工具

### 14.1 概述

内置 4 个 Git 操作工具，AI 可以直接调用这些工具来查看项目状态、差异、历史和代码归属。

### 14.2 可用工具

| 工具名 | 功能 | 参数 | 示例 |
|--------|------|------|------|
| **git_status** | 查看工作区状态 | `path?`（可选子目录） | 查看哪些文件被修改 |
| **git_diff** | 查看代码差异 | `path`（文件路径）, `staged?`（是否查看暂存区） | 查看具体改动 |
| **git_log** | 查看提交历史 | `path?`（可选文件）, `count?`（显示条数，默认 10）, `oneline?`（简洁模式） | 查看项目历史 |
| **git_blame** | 查看行级归属 | `path`（文件路径）, `startLine?`, `endLine?`（行号范围） | 谁修改了某行代码 |

### 14.3 使用场景

```
你：看看这个项目最近的提交记录
AI → git_log(count=10, oneline=true)

你：检查哪些文件被修改了
AI → git_status()

你：看看 Core.Agent.pas 最近的改动
AI → git_diff(path="Core/Core.Agent.pas")

你：这行代码是谁写的？
AI → git_blame(path="Core/Core.Agent.pas", startLine=100, endLine=120)
```

### 14.4 特性

- **默认启用**，不需要额外配置
- 所有命令使用 `--no-pager` 避免交互式分页
- 不需要用户确认（与 Bash 不同）
- 非 Git 仓库目录返回友好错误信息
- 权限通过 `settings.json` 中 `permissions.git` 控制

---

## 15. 设置详解

点击工具栏 **"..."** 菜单 → **Settings**，或按 `Ctrl+,` 打开设置窗口。设置窗口包含四个选项卡，全主题化。

### 15.1 API 设置

| 设置项 | 说明 | 默认值 |
|--------|------|--------|
| API Endpoint | LLM 接口地址 | `https://api.moonshot.cn/v1/` |
| API Key | 认证密钥 | （预设） |
| Models Endpoint | 模型列表端点 | — |
| Enable Streaming | SSE 流式传输 | 启用 |
| Timeout | HTTP 请求超时（毫秒） | 60000 |
| Retry Count | 请求失败重试次数 | 3 |

### 15.2 模型设置

| 设置项 | 说明 | 默认值 |
|--------|------|--------|
| Model Name | 模型标识符 | `moonshot-v1-128k` |
| Max Tokens | 单次回复最大 token 数 | 8192 |
| Temperature | 随机性控制 | 0.7 |
| Top P | 核采样阈值 | 1.0 |
| Thinking Level | AI 思考深度 | medium |

Thinking Level 选项：
- `off` — 不使用思考模式
- `minimal` / `low` / `medium`（推荐）/ `high` / `xhigh`（较慢）

### 15.3 界面设置

| 设置项 | 说明 | 默认值 |
|--------|------|--------|
| Theme | Dark 或 Light | Dark |
| Font Size | 聊天区字体大小 | 12 |
| Font Family | 聊天区字体 | Consolas |
| Language | 界面语言 | English / 中文 |

### 15.4 路径设置

| 设置项 | 说明 | 默认值 |
|--------|------|--------|
| Working Directory | Agent 的文件操作根目录 | `%USERPROFILE%\Projects` |
| Backup Directory | 文件编辑时的备份目录 | `%USERPROFILE%\Backups\PiMono` |

保存设置后，界面自动应用新主题和语言，无需重启。

---

## 16. 会话管理

### 16.1 侧栏

- **折叠/展开**：点击工具栏 ☰ 汉堡按钮切换侧栏显隐
- **New Chat 按钮**：顶部按钮，创建新会话并显示欢迎屏
- **会话列表**：Owner-Draw 渲染，显示会话名称、时间、消息数
  - 当前活跃会话左侧显示蓝色指示条
  - 分支会话显示橙色 `[B]` 标记
- **右键菜单**：在会话上右键弹出菜单（打开/重命名/删除）

### 16.2 会话操作

| 操作 | 方式 | 说明 |
|------|------|------|
| 新建会话 | 侧栏 New Chat / 菜单 New Session / `Ctrl+N` | 创建空白会话，显示欢迎屏 |
| 打开会话 | 双击列表项 / 右键打开 | 加载历史会话及所有消息，批量渲染气泡 |
| 删除会话 | 选中后右键 → Del | 确认后删除会话文件 |
| 重命名会话 | 选中后右键 → Rename | 弹出输入框修改名称 |
| 分支会话 | 菜单 Branch | 基于当前所有消息创建分支副本 |
| 导出 HTML | 菜单 Export | 导出当前会话为暗色主题 HTML 文件 |

### 16.3 自动保存

- 每当 AI 回复完成后，自动保存到 JSONL 会话文件（**追加写入**，不重写整个文件）
- 定时自动保存（默认 300 秒，可在配置中调整）
- Agent 运行时暂停定时保存，结束后恢复

### 16.4 会话分支

分支功能允许你基于当前对话创建一个副本，在副本上继续探索不同的方向。

- 分支记录 **ParentId** 和 **BranchPoint**（分支点的消息索引）
- 会话列表中分支会话显示橙色 `[B]` 标记
- 分支会话是独立的 JSONL 文件，修改不影响原始会话

### 16.5 会话自动命名

第一条用户消息发送后，系统会自动从消息内容中提取前 40 个字符作为会话名称（在词边界处截断并添加 "..."）。

### 16.6 上下文压缩

当对话变得很长时（接近模型 token 上限），系统自动执行上下文压缩：

1. **精简工具输出**（`SlimToolResults`）：截断大型工具输出为头尾各 3 行
2. **LLM 摘要**（`TCompaction.Execute`）：用 AI 对旧消息生成结构化摘要
3. **紧急截断**（`EmergencyCut`）：溢出时直接截断（安全网）

压缩后聊天区会显示：`[上下文已自动压缩: 旧消息已摘要，保留最近对话]`

配置参数（在 `settings.json` 的 `session` 节中）：
- `compactionEnabled`：是否启用（默认 `true`）
- `reserveTokens`：保留给回复的空间（默认 16384）
- `keepRecentTokens`：保留最近对话的 token 数（默认 20000）

---

## 17. 特殊命令

在输入框中可以使用以下命令：

### 17.1 Skill 命令

```
/skill:review
```

加载 `.pi/skills/review.md` 文件的内容作为 prompt 发送给 AI。

### 17.2 Template 命令

```
/template:bugfix 修复空指针异常
```

加载 `.pi/skills/templates/bugfix.md`，将 `{1}` 替换为 "修复空指针异常"，然后发送给 AI。支持多个参数：

```
/template:refactor unit1.pas unit2.pas
```

`{1}` = "unit1.pas"，`{2}` = "unit2.pas"

---

## 18. 快捷键

| 快捷键 | 功能 |
|--------|------|
| `Enter` | 发送消息 |
| `Shift+Enter` | 输入框内换行 |
| `Ctrl+S` | 保存当前会话 |
| `Ctrl+N` | 新建会话 |
| `Ctrl+O` | 打开选中的会话 |
| `Ctrl+,` | 打开设置窗口 |
| `Ctrl+L` | 清空聊天显示区 |
| `Ctrl+F` | 打开会话内搜索栏 |
| `Ctrl+Z` | 撤销最近一次文件操作 |
| `Escape` | 中止当前操作 / 关闭搜索栏 / 拒绝待确认的编辑 |
| `F1` | 打开帮助窗口 |
| `Ctrl+Q` | 退出程序 |

---

## 19. 工具说明

Agent 可以调用以下工具来完成任务。所有文件操作限制在 Working Directory 内。

### 19.1 文件操作工具

| 工具名 | 功能 | 参数 |
|--------|------|------|
| **read** | 读取文件内容（带行号） | `path`, `offset?`, `limit?`（上限 2000 行） |
| **write** | 写入/创建文件 | `path`, `content`（自动创建父目录，.bak 备份，**撤销日志记录**） |
| **edit** | 精确替换文本（三层模糊匹配） | `path`, `oldText`, `newText`（**撤销日志记录**） |
| **ls** | 列出目录内容 | `path?` |
| **find** | 按 glob 模式搜索文件 | `pattern`, `path?`, `limit?`（过滤 .gitignore） |
| **grep** | 搜索文件内容 | `pattern`, `path?`, `glob?`, `ignoreCase?`, `literal?`, `context?` |

### 19.2 Git 工具

| 工具名 | 功能 | 参数 |
|--------|------|------|
| **git_status** | 查看工作区状态 | `path?` |
| **git_diff** | 查看差异 | `path`, `staged?` |
| **git_log** | 查看提交历史 | `path?`, `count?`（默认 10）, `oneline?` |
| **git_blame** | 查看行级归属 | `path`, `startLine?`, `endLine?` |

特性：默认启用，不需要确认，使用 `--no-pager` 避免交互。

### 19.3 Shell 工具

| 工具名 | 功能 | 参数 |
|--------|------|------|
| **bash** | 执行 Shell 命令 | `command`, `timeout?`（默认使用配置的超时值） |

**安全限制**：
- 禁止命令：`format`、`del /s`、`rd /s`、`rmdir /s`、`shutdown`
- 输出超过 50KB 截断
- 超时后自动终止进程
- **默认禁用**，需在 `settings.json` 中启用 `permissions.bash.enabled`

### 19.4 Edit 工具的三层模糊匹配

当 AI 提供的 `oldText` 在文件中找不到精确匹配时，系统自动尝试：

1. **精确匹配**：直接文本比对
2. **归一化匹配**：统一行尾符（CRLF/LF/CR → CRLF）、折叠空行、去除行尾空白后重新匹配
3. **逐行评分**：滑动窗口对比每一行，case-insensitive 完全匹配 = 2 分，部分匹配 = 1 分，达到 70% 阈值即可匹配

这大大提高了 AI 编辑代码的成功率，即使 AI 对空白、引号等细节不完全准确。

---

## 20. 编辑确认

当 AI 尝试使用 `write` 或 `edit` 工具修改文件时，如果该工具的 `requireConfirmation` 为 `true`（write 和 edit 默认均为 true），系统会暂停执行并显示确认面板。

### 20.1 确认流程

1. 聊天区显示黄色警告标题：`[Confirmation Required] Tool: edit  File: xxx.pas`
2. 下方显示 Diff 预览（多色行）：
   - 红色行（`-` / `---`）：将被删除的旧代码
   - 绿色行（`+` / `+++`）：将写入的新代码
   - 灰色行：上下文行
3. 底部弹出确认按钮面板：绿色 **Approve** + 红色 **Reject**

### 20.2 操作

- 点击 **Approve**（绿色）：执行修改（**自动记录到撤销日志**）
- 点击 **Reject**（红色）：拒绝修改，AI 收到 "rejected by user" 错误
- 按 **Escape**：拒绝并中止整个 Agent 操作

### 20.3 撤销已确认的操作

即使点击了 Approve，也可以通过 **Ctrl+Z** 撤销文件修改。参见 [第 12 节：撤销/回滚](#12-撤销回滚)。

### 20.4 关闭确认

如果不需要确认提示，编辑 `settings.json`：
```json
"permissions": {
  "edit": { "enabled": true, "requireConfirmation": false },
  "write": { "enabled": true, "requireConfirmation": false }
}
```

---

## 21. 主题与外观

### 21.1 主题切换

在设置窗口 → UI 选项卡中选择 **Dark** 或 **Light**，保存后立即生效。

切换主题时，系统会：
- 更新所有区域颜色（工具栏、侧栏、聊天区、输入区、状态栏）
- **延迟重新着色已有消息气泡**（每 tick 处理 5 项，避免界面冻结）
- **重新渲染所有助手消息**：
  - 文本段 TRichEdit 使用新主题色重新生成 RTF
  - 代码块容器更新标题栏、代码背景和文本颜色
- 更新欢迎屏和设置窗口颜色

### 21.2 颜色体系

46+ 色主题系统涵盖以下分类：

| 分类 | 字段示例 | 用途 |
|------|----------|------|
| 背景层级 | Background, Surface, Border | 主背景、面板、分隔线 |
| 文本 | Text, TextSecondary, Accent | 主文本、次要文本、强调色 |
| 消息气泡 | UserMessage/Border, AssistantMessage/Border | 用户/助手气泡背景 + 边框 |
| 错误/工具 | ErrorMessage/Border, ToolMessage/Border | 错误/工具气泡背景 + 边框 |
| Diff 显示 | DiffAdded, DiffRemoved, DiffContext | 确认面板 diff 行着色 |
| 确认面板 | WarningColor, ApproveBg, RejectBg | 警告标题、批准/拒绝按钮 |
| 分支标记 | BranchIndicator, LeafIndicator, TreeConnector | 会话分支指示色 |
| 建议卡片 | SuggestionBg, SuggestionBorder, SuggestionHover | 欢迎屏建议卡片 |
| 输入区 | InputCardBg, InputCardBorder, InputBackground | 输入框卡片 |
| 按钮 | ButtonBackground, ButtonText, StatusBar/Text | 按钮、状态栏样式 |
| **Markdown/代码** | **CodeBlockBg, CodeBlockBorder, CodeBlockText** | **代码块背景、边框、文本** |
| **Markdown/代码** | **InlineCodeText, HeaderColor, LinkColor** | **行内代码、标题、链接** |
| **Markdown/代码** | **QuoteColor, BoldColor** | **引用、加粗文本** |

### 21.3 字体与 DPI

- **ScaleFont** 函数根据配置的 FontSize 自动缩放 UI 元素字号（基准 12px）
- 输入框字体使用配置的 FontFamily 和 FontSize
- 消息气泡内 TRichEdit 使用相同字体设置
- 代码块使用 Consolas 等宽字体
- Diff 预览固定使用 Consolas + ScaleFont(9)

### 21.4 语言切换

在设置窗口 → UI 选项卡中选择 **English** 或 **Chinese**，保存后立即生效。涵盖所有界面文本：菜单、按钮、状态消息、欢迎屏、确认面板、设置/帮助窗口、搜索栏、撤销提示。

---

## 22. 目录与文件结构

### 22.1 程序数据目录

```
%APPDATA%\PiMono\
├── settings.json              # 全局配置文件
└── sessions\                  # 会话存储目录
    ├── 20260413_143000_1234.jsonl   # JSONL 格式会话（header + 消息逐行追加）
    └── 20260413_150000_5678.jsonl
```

```
%LOCALAPPDATA%\PiMono\
├── Logs\                      # 日志文件目录
│   ├── PiMono_2026-04-13.log  # 当天日志
│   └── PiMono_*.log           # 历史日志（自动轮转，最多 30 个文件）
└── Cache\
    └── undo_log.jsonl         # 操作撤销日志（JSONL，FIFO 100 条）
```

### 22.2 项目配置文件

在工作目录下可放置以下文件：

| 文件 | 用途 |
|------|------|
| `.pimonorc` 或 `.pi/settings.json` | 项目级配置（覆盖全局配置） |
| `AGENTS.md` 或 `CLAUDE.md` | 项目上下文说明（自动注入 AI 系统提示词） |
| `.pi/skills/*.md` | Skill 文件（`/skill:name` 命令加载） |
| `.pi/skills/templates/*.md` | 模板文件（`/template:name` 命令加载） |
| `.gitignore` | 文件过滤规则（find/grep 工具自动遵守） |

### 22.3 AGENTS.md 示例

```markdown
# 项目说明
这是一个 Delphi 11.x VCL 桌面应用项目。

# 代码规范
- 使用前缀 T 命名类型
- 私有字段以 F 开头
- 事件处理器以 On 开头

# 关键文件
- Core/Core.Agent.pas — Agent 核心循环
- UI/UI.MainForm.pas — 主窗口
```

AI 启动时会自动读取此文件，了解项目上下文。

---

## 23. 配置文件详解

全局配置文件 `settings.json` 的完整结构：

```json
{
  "version": "1.0",
  "api": {
    "endpoint": "https://api.moonshot.cn/v1/",
    "apiKey": "sk-xxx",
    "modelsEndpoint": "https://api.moonshot.cn/v1/models",
    "timeout": 60000,
    "retryCount": 3,
    "retryDelay": 1000,
    "enableStreaming": true
  },
  "model": {
    "name": "moonshot-v1-128k",
    "maxTokens": 8192,
    "temperature": 0.7,
    "topP": 1.0,
    "frequencyPenalty": 0.0,
    "presencePenalty": 0.0
  },
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
  "directories": {
    "working": "C:\\Users\\用户名\\Projects",
    "backup": "C:\\Users\\用户名\\Backups\\PiMono",
    "cache": "C:\\Users\\用户名\\AppData\\Local\\PiMono\\Cache",
    "logs": "C:\\Users\\用户名\\AppData\\Local\\PiMono\\Logs"
  },
  "ui": {
    "theme": "Dark",
    "fontSize": 12,
    "fontFamily": "Consolas",
    "windowWidth": 1200,
    "windowHeight": 800,
    "language": "en"
  },
  "permissions": {
    "read":   { "enabled": true,  "requireConfirmation": false, "maxFileSize": 10485760 },
    "write":  { "enabled": true,  "requireConfirmation": true },
    "edit":   { "enabled": true,  "requireConfirmation": true },
    "bash":   { "enabled": false, "requireConfirmation": true },
    "git":    { "enabled": true,  "requireConfirmation": false }
  },
  "session": {
    "autoSave": true,
    "autoSaveInterval": 300,
    "maxSessions": 100,
    "defaultThinkingLevel": "medium",
    "compactionEnabled": true,
    "reserveTokens": 16384,
    "keepRecentTokens": 20000
  },
  "logging": {
    "level": "INFO",
    "maxFileSize": 10485760,
    "maxFiles": 30
  }
}
```

### 配置优先级

```
项目配置 (.pimonorc / .pi/settings.json) > 全局配置 (settings.json) > 代码默认值
```

---

## 24. 日志系统

### 日志级别

| 级别 | 值 | 用途 |
|------|----|------|
| TRACE | 0 | 最详细的调试信息 |
| DEBUG | 10 | 调试信息 |
| INFO | 20 | 一般运行信息（默认级别） |
| WARN | 30 | 警告（如 Agent 中止、压缩触发） |
| ERROR | 40 | 错误（如 API 调用失败） |
| FATAL | 50 | 致命错误 |

### 日志轮转

- 单个日志文件最大 **10MB**
- 超过大小后自动重命名
- 最多保留 **30** 个历史日志文件

### 查看日志

日志文件位于 `%LOCALAPPDATA%\PiMono\Logs\`，可以用任何文本编辑器打开。

---

## 25. 常见问题

### Q: 启动后提示连接失败

**A:** 检查：
1. 内部 LLM API 服务器是否正常运行
2. API Endpoint 地址是否正确（Settings → API）
3. 网络是否能访问该地址
4. API Key 是否有效

### Q: AI 回复中断或乱码

**A:** 可能原因：
1. API 服务器超时 — 增大 Timeout 设置
2. Max Tokens 太小 — 增大到 8192 或更高
3. 长对话触发了上下文压缩 — 这是正常行为

### Q: 文件操作报错 "path not found"

**A:** 确认 Working Directory 设置正确。Agent 的文件操作相对于该目录执行。

### Q: Bash 工具不可用

**A:** Bash 工具默认禁用。编辑 `settings.json`：
```json
"permissions": {
  "bash": { "enabled": true, "requireConfirmation": true }
}
```

### Q: 编辑确认太频繁

**A:** 编辑 `settings.json`，将 `requireConfirmation` 设为 `false`：
```json
"permissions": {
  "edit": { "enabled": true, "requireConfirmation": false }
}
```

### Q: 如何撤销 AI 的文件修改

**A:** 按 **Ctrl+Z** 或点击菜单 → Undo。每次撤销恢复最近一次文件操作。可连续按多次逐个撤销。参见 [第 12 节：撤销/回滚](#12-撤销回滚)。

### Q: 如何切换不同的 AI 模型

**A:** 在工具栏的模型下拉框中选择。需要先在 `settings.json` 中配置 `modelProfiles` 数组。参见 [第 10 节：多模型切换](#10-多模型切换)。

### Q: 拖放文件没反应

**A:** 确认拖入的是文本文件（.txt、.pas、.py 等源代码文件）。二进制文件（.exe、.dll、.jpg 等）会被自动拒绝。单文件大小不能超过 1MB。

### Q: 搜索不到聊天内容

**A:** 会话内搜索（Ctrl+F）搜索当前聊天区显示的所有消息内容，包括代码块内的代码。不搜索历史会话。如果消息太多被压缩了，搜索无法找到已压缩的旧消息。

### Q: 代码块的 Copy 按钮复制的是什么

**A:** 每个代码块的 Copy 按钮只复制**该代码块**内的代码内容。气泡上方的 Copy 按钮复制**整条消息**的所有文本。参见 [第 8 节：代码块拆分渲染](#8-代码块拆分渲染) 和 [第 9 节：消息复制](#9-消息复制)。

### Q: Git 工具不可用

**A:** 确认工作目录是一个 Git 仓库。如果工作目录不是 Git 仓库，Git 工具会返回错误信息。

### Q: 会话文件变大很快

**A:** 这是正常现象。JSONL 格式采用追加写入，不会每次重写。上下文压缩会自动缩减旧消息。也可以手动删除不需要的旧会话。

### Q: 旧的会话文件打不开

**A:** 启动时自动将旧 `.json` 格式迁移为 `.jsonl`。如果迁移失败，检查日志文件中的错误信息。

### Q: 如何使用 Skill 命令

**A:** 在工作目录下创建 `.pi/skills/` 目录，放入 `.md` 文件。例如 `.pi/skills/review.md`，然后在聊天中输入 `/skill:review`。

### Q: 如何恢复默认配置

**A:** 删除 `%APPDATA%\PiMono\settings.json`，重启程序会自动生成默认配置。

### Q: 窗口 resize 后消息布局错乱

**A:** 程序使用 80ms 去抖机制，resize 停止后自动调用 `RelayoutMessages` 重新计算所有消息气泡的位置和大小，包括代码块容器的高度。如果仍有问题，尝试最大化/还原窗口。

### Q: 气泡内文本无法滚动选择

**A:** 气泡内 TMemo/TRichEdit 是 ReadOnly 且无边框的，可以直接用鼠标选中文本并 Ctrl+C 复制。鼠标滚轮在气泡上时由程序全局拦截，控制的是外层 TScrollBox 的滚动。

### Q: 主题切换时界面卡顿

**A:** v6.0 使用延迟渲染机制（每 tick 处理 5 条消息），避免一次性重绘所有消息。如果会话中消息非常多，切换主题时可能仍有短暂延迟，这是正常现象。

### Q: Markdown 渲染效果不理想

**A:** Markdown 渲染支持常见的标题、粗体、斜体、代码块、行内代码、引用、列表、表格、链接等元素。嵌套格式（如列表中的代码块）可能不完全支持。复杂的 Markdown 扩展语法（如数学公式、脚注）暂不支持。

---

## 26. 安全说明

### 数据安全

- 所有通信在**内部网络**中进行，不连接外部互联网
- 会话数据存储在本地 `%APPDATA%` 目录
- API Key 存储在本地配置文件中

### 工具安全

| 措施 | 说明 |
|------|------|
| 权限控制 | Read/Write/Edit/Bash/Git 五级权限，独立启用/禁用 |
| 编辑确认 | write/edit 默认需用户审批 diff 预览 |
| 命令黑名单 | `format`、`del /s`、`rd /s`、`rmdir /s`、`shutdown` 被禁止 |
| 超时限制 | Bash 命令超时强制终止 |
| 输出截断 | 命令输出超过 50KB 自动截断 |
| 编辑备份 | edit 工具 .bak 备份 + 失败自动回滚 |
| MaxTurns | Agent 最多 30 轮工具调用，防止失控 |
| 路径安全 | 所有文件操作限制在 Working Directory 内 |
| 撤销回滚 | 所有文件写/编辑操作记录撤销日志，支持 Ctrl+Z 撤销 |
| 拖放安全 | 文件大小限制 1MB + 二进制文件检测 |

### 建议的安全实践

1. 不要将 `settings.json` 提交到版本控制系统
2. 生产环境保持 Bash 工具禁用，仅在开发时启用
3. 保持 write/edit 的 `requireConfirmation` 为 `true`
4. 将 Working Directory 设为专用工作区，避免指向系统目录
5. 定期清理 `%APPDATA%\PiMono\sessions\` 中的旧会话

---

*PiMono Agent 6.0 — 内部网络 AI 代码编辑助手（Delphi Edition）*
