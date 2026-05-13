# PiMono 功能规划报告

> 生成日期：2026-05-08
> 当前分支：feature/webview2-ui
> 分析基准：a42e24f Baseline: VCL+Skia UI before WebView2 migration

---

## 一、项目现状概览

PiMono 是一个基于 Delphi + WebView2 的 AI Agent 桌面客户端。

### 1.1 技术架构

| 层级 | 技术选型 |
|------|---------|
| 后端语言 | Object Pascal (Delphi 12.x Athens) |
| 前端界面 | HTML/CSS/JS (WebView2) |
| 原生控件 | VCL + Skia |
| WebView 集成 | WebView4Delphi (submodule) |
| API 协议 | OpenAI Chat Completions (SSE 流式) |
| 编译产物 | 单文件 PiMono.exe (4.2MB) |

### 1.2 已实现模块

```
PiMono/
├── AI/                          # API 适配层
│   ├── AI.IModel.pas            #   模型接口 (IModel)
│   ├── AI.CustomAPIAdapter.pas  #   OpenAI 兼容 API 适配器
│   └── AI.ModelConfig.pas       #   请求/响应数据结构
│
├── Core/                        # Agent 核心引擎
│   ├── Core.Agent.pas           #   Agent 主循环 (状态机 + 流式 + 工具调用)
│   ├── Core.AgentState.pas      #   状态管理、工具接口、中止控制器
│   ├── Core.AgentFactory.pas    #   Agent 工厂
│   ├── Core.Messages.pas        #   消息体系 (User/Assistant/ToolResult/ContentBlock)
│   ├── Core.Events.pas          #   事件总线 (发布-订阅模式)
│   ├── Core.SessionManager.pas  #   会话持久化管理
│   ├── Core.Compaction.pas      #   上下文压缩 (双层: Slim + LLM 摘要)
│   ├── Core.ToolResultSlim.pas  #   工具结果瘦身
│   └── Core.UndoLog.pas         #   操作撤销日志
│
├── Tools/                       # 工具系统
│   ├── Tools.ITool.pas          #   工具基类 + 路径安全校验
│   ├── Tools.FileTools.pas      #   文件操作 (read/write/edit/ls/find/grep)
│   ├── Tools.BashTool.pas       #   Shell 命令执行
│   ├── Tools.CommandRunner.pas  #   命令运行器 (进程管理)
│   ├── Tools.GitTool.pas        #   Git 操作 (status/diff/log/blame)
│   ├── Tools.WebSearchTool.pas  #   Web 搜索 (12+ 搜索引擎)
│   └── Tools.ToolRegistry.pas   #   工具注册中心
│
├── Settings/                    # 配置系统
│   ├── Settings.Config.pas      #   全局配置结构 (含序列化/反序列化)
│   ├── Settings.SettingsManager.pas  # 配置管理器 (全局 + 项目级合并)
│   └── Settings.SkillStore.pas  #   技能存储
│
├── UI/                          # 界面层
│   ├── UI.MainForm.pas          #   主窗口 (WebView2 宿主)
│   ├── UI.WebViewBridge.pas     #   JS ↔ Delphi 双向通信桥
│   ├── UI.SessionChatForm.pas   #   弹出式会话窗口
│   ├── UI.ThemeManager.pas      #   主题管理
│   ├── UI.Spacing.pas           #   布局间距常量
│   └── UI.HelpForm.pas          #   帮助窗口
│
├── WebUI/                       # WebView2 前端
│   ├── index.html               #   主页面
│   ├── js/bridge.js             #   通信桥 (前端侧)
│   ├── js/chat.js               #   聊天渲染
│   ├── js/settings.js           #   设置面板
│   ├── js/sidebar.js            #   侧边栏
│   ├── js/theme.js              #   主题引擎
│   └── js/onboarding.js         #   引导流程
│
├── Utils/                       # 工具库
│   ├── Utils.Logger.pas         #   日志系统 (滚动文件)
│   ├── Utils.JsonHelper.pas     #   JSON 辅助函数
│   ├── Utils.Localization.pas   #   国际化框架
│   ├── Utils.Markdown.pas       #   Markdown 解析
│   ├── Utils.TokenEstimator.pas #   Token 用量估算
│   ├── Utils.SkiaDraw.pas       #   Skia 绘图辅助
│   └── Utils.SvgIcons.pas       #   SVG 图标管理
│
└── Tests/                       # 测试 (37 个文件, ~14,800 行)
    ├── AI/                      #   AI 模块测试
    ├── Core/                    #   核心模块测试
    ├── Settings/                #   配置模块测试
    ├── Tools/                   #   工具模块测试
    ├── UI/                      #   UI 模块测试
    └── Utils/                   #   工具库测试
```

### 1.3 项目规模

| 指标 | 数值 |
|------|------|
| 项目自有 Pascal 源码 | ~24,000 行 (44 个文件) |
| 测试代码 | ~14,800 行 (37 个文件) |
| WebUI 前端代码 | ~5,800 行 |
| 测试/源码比 | ~61% |
| 项目级别 | 中型产品级应用 |

### 1.4 已有核心能力

| 能力 | 实现状态 | 说明 |
|------|---------|------|
| Agent 执行循环 | ✅ 完成 | 状态机驱动，支持流式输出、工具调用、中止恢复 |
| SSE 流式通信 | ✅ 完成 | 兼容 OpenAI API 格式，支持 thinking/token 流 |
| 工具系统 | ✅ 完成 | 6 类工具，路径安全校验，权限控制 |
| 会话管理 | ✅ 完成 | 增量写入、分支、导出、弹出窗口 |
| 上下文压缩 | ✅ 完成 | 双层压缩 (工具结果瘦身 + LLM 摘要)，溢出紧急恢复 |
| 撤销操作 | ✅ 完成 | 文件编辑可撤销 |
| 多模型 Profile | ✅ 完成 | 多套 API 配置切换 |
| 工具权限系统 | ✅ 完成 | 6 类权限，含确认机制 (write/edit 需用户确认) |
| 技能系统 | ✅ 完成 | 项目级 + 全局技能池 |
| WebView2 UI | ✅ 完成 | 现代前端 + 双向通信桥 |
| 主题系统 | ✅ 完成 | cyberpunk-neon 主题 |
| 搜索引擎集成 | ✅ 完成 | 12+ 搜索引擎提供商 |
| Onboarding 引导 | ✅ 完成 | 首次使用引导流程 |

---

## 二、缺失功能分析

### P0 级 — 核心缺失（影响基本可用性）

#### 2.1 多模态消息支持

**现状：** 消息系统 (`Core.Messages.pas`) 的 `TContentBlock` 只有文本 (`cbtText`)、思考 (`cbtThinking`)、工具调用 (`cbtToolCall`) 三种类型，无法处理图片。

**需要：**
- 扩展 `TContentBlock` 增加 `cbtImage` 类型，支持图片 URL 和 base64 编码
- 修改 `AgentMessagesToApiMessages` 构造 `image_url` 类型的 content
- WebView 前端增加图片消息渲染
- 输入框支持 Ctrl+V 粘贴剪贴板图片

**涉及文件：**
- `Core/Core.Messages.pas` — 增加 TImageContent 类
- `AI/AI.ModelConfig.pas` — 修改消息序列化增加 image_url 类型
- `UI/UI.WebViewBridge.pas` — 增加图片粘贴处理
- `WebUI/js/chat.js` — 图片消息渲染
- `WebUI/js/bridge.js` — 图片 base64 传输

#### 2.2 Token 用量统计

**现状：** SSE 流式响应未解析 `usage` 字段，用户无法看到每次对话消耗了多少 Token。

**需要：**
- 从 API 响应 (stream_options include_usage) 中提取 `usage.prompt_tokens` / `completion_tokens`
- 在 `TAssistantMessage` 中记录 usage 数据
- 每次对话结束在 UI 上显示本次用量和累计用量
- 支持费用估算（根据模型定价表计算）

**涉及文件：**
- `AI/AI.CustomAPIAdapter.pas` — 解析 SSE usage 事件
- `Core/Core.Messages.pas` — TAssistantMessage 增加 Usage 字段
- `Core/Core.Events.pas` — 增加 Usage 事件
- `UI/UI.WebViewBridge.pas` — 转发 usage 数据到前端
- `WebUI/js/chat.js` — 渲染 token 用量

#### 2.3 对话内搜索

**现状：** 无消息搜索功能，长对话中难以定位特定内容。

**需要：**
- 前端实现搜索栏（Ctrl+F 触发）
- 支持关键词高亮和上下一条导航
- 支持在所有会话中全局搜索（可选）

**涉及文件：**
- `WebUI/js/chat.js` — 搜索逻辑和高亮渲染
- `WebUI/index.html` — 搜索栏 UI
- `WebUI/css/styles.css` — 搜索样式

#### 2.4 API 连接测试优化

**现状：** `HandleTestConnection` 已实现基本功能，但用户体验需完善。

**需要：**
- 测试过程中显示加载动画和进度
- 成功后显示延迟 (ms) 和可用模型列表
- 失败时给出明确的错误原因和修复建议

**涉及文件：**
- `UI/UI.WebViewBridge.pas` — 增强 TestConnection 处理逻辑
- `WebUI/js/settings.js` — 测试按钮状态和结果展示

#### 2.5 剪贴板图片粘贴

**现状：** 输入框只支持纯文本输入。

**需要：**
- 监听 paste 事件，检测剪贴板中的图片数据
- 转换为 base64 后发送给多模态模型
- 输入框中显示图片预览

**涉及文件：**
- `WebUI/js/chat.js` — paste 事件处理
- `WebUI/js/bridge.js` — 图片传输
- `WebUI/css/styles.css` — 图片预览样式

---

### P1 级 — 重要增强（提升专业体验）

#### 2.6 MCP (Model Context Protocol) 支持

**现状：** 无 MCP 支持，工具系统完全内置。

**价值：** MCP 是 AI Agent 生态的标准协议，能让 PiMono 连接外部工具服务器（文件系统、数据库、Git、Slack 等），大幅扩展能力边界。

**需要：**
- 实现 MCP Client，支持 `initialize` / `tools/list` / `tools/call` 协议
- 支持 stdio 和 SSE 两种传输方式
- 将 MCP 工具动态注册到 Agent 的工具列表
- 在设置界面中管理 MCP 服务器配置

**涉及文件：**
- 新增 `Core/Core.MCPClient.pas` — MCP 协议客户端
- 新增 `Core/Core.MCPTransport.pas` — 传输层 (stdio/SSE)
- `Core/Core.Agent.pas` — 动态合并 MCP 工具
- `Settings/Settings.Config.pas` — 增加 MCP 服务器配置
- `UI/UI.WebViewBridge.pas` — MCP 服务器管理接口
- `WebUI/js/settings.js` — MCP 配置面板

#### 2.7 系统托盘 & 后台运行

**现状：** 关闭窗口即退出程序，无法后台运行。

**需要：**
- 关闭按钮最小化到系统托盘
- 托盘图标右键菜单（显示主窗口、新建会话、退出）
- 长时间任务完成后桌面通知

**涉及文件：**
- `UI/UI.MainForm.pas` — 处理 WM_SYSCOMMAND，添加 TTrayIcon
- `WebUI/js/chat.js` — 通知请求接口

#### 2.8 Prompt 模板库

**现状：** 有技能系统但无内置模板。

**需要：**
- 内置常用 prompt 模板：代码审查、翻译、文档生成、Bug 分析等
- 用户可自定义模板
- 模板支持变量插值 `{{selection}}` `{{language}}` 等

**涉及文件：**
- 复用 `Settings/Settings.SkillStore.pas` 框架
- `WebUI/js/sidebar.js` — 模板选择面板
- `WebUI/js/chat.js` — 变量替换逻辑

#### 2.9 Markdown/HTML 导出

**现状：** 只支持 JSON 格式导出会话。

**需要：**
- 导出为 Markdown 文件（保留代码高亮标记）
- 导出为 HTML 文件（带样式，可直接浏览）
- 支持导出当前会话或选中消息范围

**涉及文件：**
- `UI/UI.WebViewBridge.pas` — 增加 Markdown/HTML 导出处理
- `Core/Core.SessionManager.pas` — 消息格式转换

#### 2.10 拖拽文件发送

**现状：** 无文件拖拽功能。

**需要：**
- 监听 dragover/drop 事件
- 文本文件：读取内容作为消息上下文发送
- 图片文件：转为 base64 发送给多模态模型
- 显示文件预览

**涉及文件：**
- `WebUI/js/chat.js` — 拖拽事件处理
- `WebUI/css/styles.css` — 拖拽视觉反馈

#### 2.11 代理/VPN 配置

**现状：** API 请求无代理支持，部分地区用户可能无法直连。

**需要：**
- 在 `TApiConfig` 中增加代理配置字段
- 在 `TCustomAPIAdapter` 中配置 `TNetHttpClient` 的代理
- 设置界面增加代理配置入口

**涉及文件：**
- `Settings/Settings.Config.pas` — 增加代理配置字段
- `AI/AI.CustomAPIAdapter.pas` — 配置 HTTP 代理
- `WebUI/js/settings.js` — 代理设置面板

#### 2.12 草稿自动保存

**现状：** 切换会话时输入框内容丢失。

**需要：**
- 切换会话前自动保存当前输入
- 切换回来时自动恢复
- 使用 localStorage 或传递给 Delphi 端存储

**涉及文件：**
- `WebUI/js/chat.js` — 草稿保存/恢复逻辑
- `WebUI/js/bridge.js` — 草稿存储接口

---

### P2 级 — 进阶功能（差异化竞争力）

#### 2.13 RAG 本地知识库

**现状：** 无本地文档索引和检索能力。

**需要：**
- 对本地文档进行分块和 Embedding 向量化
- 用户提问时检索相关文档片段注入上下文
- 支持常见文档格式 (.txt, .md, .pdf, .docx)

**涉及文件：**
- 新增 `Core/Core.RAG.pas` — RAG 引擎
- 新增 `Core/Core.Embedding.pas` — Embedding 调用
- 新增 `Core/Core.VectorStore.pas` — 向量存储
- `WebUI/js/settings.js` — 知识库管理面板

#### 2.14 自动更新机制

**现状：** 无版本检查和更新机制。

**需要：**
- 启动时检查 GitHub Release 最新版本
- 发现新版本时提示下载
- 利用 Delphi 单 exe 优势实现简单替换更新

**涉及文件：**
- 新增 `Utils/Utils.Updater.pas` — 版本检查与更新
- `UI/UI.MainForm.pas` — 更新提示 UI

#### 2.15 多会话并行

**现状：** Popup 窗口已有雏形，但共享同一个 Agent 实例。

**需要：**
- 每个弹出窗口创建独立的 Agent 实例
- 各自维护独立的消息状态和工具上下文
- 支持同时流式输出

**涉及文件：**
- `UI/UI.MainForm.pas` — 多 Agent 实例管理
- `UI/UI.SessionChatForm.pas` — 独立 Agent 绑定
- `Core/Core.AgentFactory.pas` — Agent 工厂增强

#### 2.16 快捷键系统

**现状：** 无可配置的快捷键。

**需要：**
- 预定义常用操作快捷键
- 用户可在设置中自定义
- 支持 WebView2 内快捷键拦截

**涉及文件：**
- 新增 `Utils/Utils.Hotkeys.pas` — 快捷键管理
- `WebUI/js/bridge.js` — 快捷键注册
- `WebUI/js/settings.js` — 快捷键配置面板

#### 2.17 流式响应重试

**现状：** 网络断开后只能从头开始。

**需要：**
- 记录最后一条完整的 Assistant 消息位置
- 断线后从该位置重试，不丢失已完成的内容
- 指数退避重试策略

**涉及文件：**
- `AI/AI.CustomAPIAdapter.pas` — 断线检测和重连
- `Core/Core.Agent.pas` — 恢复点记录

#### 2.18 代码块增强

**现状：** 代码块有基本渲染，但交互不足。

**需要：**
- 一键复制按钮
- 语法错误检测提示
- "在编辑器中打开" 功能
- 行号显示
- 语言标签

**涉及文件：**
- `WebUI/js/chat.js` — 代码块渲染增强
- `WebUI/css/styles.css` — 代码块样式

---

### P3 级 — 生态与社区（开源发布后）

#### 2.19 插件/扩展系统

动态加载第三方工具（DLL 或脚本），类似 Claude Code 的 MCP 工具模式。

#### 2.20 多语言 i18n 完善

`Utils.Localization.pas` 框架已就位，需要完善中文翻译覆盖。

#### 2.21 贡献者指南 + CI

- CONTRIBUTING.md
- GitHub Actions 自动化测试
- Release 自动打包上传

#### 2.22 社区翻译平台

接入 Crowdin 或类似的社区翻译平台，支持多语言协作翻译。

---

## 三、实施路线图

```
┌─────────────────────────────────────────────────────┐
│  Phase 1 — 基础完善 (P0 + P1 核心)                  │
│                                                     │
│  多模态支持 → Token 统计 → 对话搜索 → MCP 支持      │
│  系统托盘 → Prompt 模板 → Markdown/HTML 导出        │
│                                                     │
│  目标：让产品真正可用，达到日常使用标准               │
├─────────────────────────────────────────────────────┤
│  Phase 2 — 体验提升 (P1 完善 + P2 核心)             │
│                                                     │
│  拖拽文件 → 代理配置 → 草稿保存 → RAG 知识库       │
│  自动更新 → 多会话并行 → 快捷键系统                  │
│                                                     │
│  目标：差异化体验，对标商业级 AI 客户端               │
├─────────────────────────────────────────────────────┤
│  Phase 3 — 生态建设 (P2 完善 + P3 全部)             │
│                                                     │
│  流式重试 → 代码块增强 → 插件系统 → i18n            │
│  CI/CD → 贡献者指南 → 社区翻译                      │
│                                                     │
│  目标：建立开源社区，形成生态                         │
└─────────────────────────────────────────────────────┘
```

---

## 四、关键文件索引

| 功能方向 | 主要涉及的现有文件 |
|---------|------------------|
| 消息系统扩展 | `Core/Core.Messages.pas`, `AI/AI.ModelConfig.pas` |
| 工具系统扩展 | `Tools/Tools.ITool.pas`, `Tools/Tools.ToolRegistry.pas` |
| UI 交互增强 | `WebUI/js/chat.js`, `WebUI/js/bridge.js`, `WebUI/index.html` |
| 配置扩展 | `Settings/Settings.Config.pas`, `Settings/Settings.SettingsManager.pas` |
| Agent 核心 | `Core/Core.Agent.pas`, `Core/Core.AgentState.pas` |
| 通信桥 | `UI/UI.WebViewBridge.pas` |
| API 层 | `AI/AI.CustomAPIAdapter.pas`, `AI/AI.IModel.pas` |
