# HDSH 迁移方案：基于 NGF 在鸿蒙全设备实现 DSH

> 状态：已确认（2026-08-16）。本文档是 HDSH 项目的技术路线依据。
> 上游参照：DeepSeek Harness（`deepseek-ai/deepseek-harness`，v0.1.0-rc.5，MIT，2026-08-13 发布）。
> 当前实现：HDSH 已先完成 DSH 官方 WebUI 经 ArkWeb 运行的设备闭环；ArkTS 原生 harness 与业务页面按下述里程碑继续迁移。

## 1. 项目目标

将 DeepSeek Harness（dsh）的能力迁移到 HarmonyOS，使用鸿蒙原生技术（ArkTS + NGF 框架）**全新实现**，使其可在鸿蒙**所有设备**（phone / tablet / 2in1 / car / tv / wearable）上运行。

**定位差异**：上游 dsh 是桌面/服务器 CLI + Web UI 形态；HDSH 当前以鸿蒙原生启动壳 + ArkWeb DSH WebUI 完成首个可运行闭环，后续逐步迁移为 ArkTS 原生会话界面，并保留 headless/服务化能力扩展空间。

## 2. DSH 架构要点（迁移输入）

- **一切皆插件**：Cordis kernel（vendor 拷贝）提供插件挂载/卸载/依赖管理、`ctx.effect()/on()/waterfall()`；模型适配器、工具注册表、会话日志、agent loop 本身都是插件，配置组合成 Profile/Bundle 树。
- **事件溯源会话**：`Session` = 追加式 `SessionEvent` 日志（唯一事实源）；`deriveMessages()` 从日志投影模型历史；核心不变式 **模型可见 ⟺ 已入日志**。
- **Turn/Step 循环**：step = 一次模型请求 + 其工具调用；turn = 0..n step。瀑布事件（`agent/pre-step`、`llm/stream`、`tools/*`）用 `next()` 委托。
- **LLM 接入**：`LlmAdapter` 契约 = `stream(options): AsyncIterable<StreamChunk>`；`StreamChunk` 闭式判别联合（block-start/text-delta/reasoning-delta/tool-call-delta/block-end/usage/finish）；DeepSeek/OpenAI/Anthropic/OpenAI 兼容网关。
- **工具/技能/MCP**：`ToolDefinition`（schema + execute + output）+ pre/execute/post 守卫流水线；MCP stdio/streamable-http 客户端桥接工具；技能 catalog/loader。
- **持久化**：JSONL（Zstd 压缩帧、原子写）或 SQLite；设置/凭据分层，凭据只存引用不落明文。
- **平台依赖**：Node 22+、`node:sqlite`、child_process、fs/promises、fetch/SSE、worker_threads、node-pty、Landlock 沙箱。仅 macOS/Linux/Windows。

## 3. HDSH 总体架构（鸿蒙原生）

```
┌─────────────────────────────────────────────────────────────┐
│ ArkUI 界面层 (entry/pages/hdsh/)                             │
│   会话对话页 · 工具卡片 · 设置页 · 模型管理 · 会话历史        │
│   复用 NGF：HDS 导航壳 / 主题 / i18n / 多窗口 / 设备感知      │
└──────────────┬──────────────────────────────────────────────┘
               │ 事件订阅 / 状态投影（会话日志驱动 UI）
┌──────────────▼──────────────────────────────────────────────┐
│ HDSH Harness 内核 (entry/hdsh/)   —— DSH 核心语义的 ArkTS 重写│
│ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────────┐ │
│ │ core     │ │ session  │ │ agent    │ │ llm              │ │
│ │ 服务容器  │→│ 事件溯源  │→│ turn/step│→│ 适配器注册表      │ │
│ │ 事件总线  │ │ SessionLog│ │ AgentLoop│ │ StreamChunk 词汇 │ │
│ │ 效果模型  │ │ JSONL 持久│ │ inbox    │ │ DeepSeek 适配器  │ │
│ └──────────┘ └──────────┘ └──────────┘ └──────────────────┘ │
│ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────────┐ │
│ │ tools    │ │ context  │ │ settings │ │ mcp (P2)         │ │
│ │ 注册表    │ │ 上下文组装│ │ 分层配置  │ │ stdio/http 客户端 │ │
│ │ 守卫流水线│ │ 压缩     │ │ 凭据引用  │ │                  │ │
│ └──────────┘ └──────────┘ └──────────┘ └──────────────────┘ │
└──────────────┬──────────────────────────────────────────────┘
               │ @ohos.* 系统能力
┌──────────────▼──────────────────────────────────────────────┐
│ 鸿蒙平台能力                                                 │
│ @ohos.net.http(流式) · @ohos.file.fs(沙箱) · @ohos.data.*     │
│ @ohos.security.asset(凭据) · @ohos.worker · @ohos.process     │
│ AAF 权限模型（沙箱） · MindSpore Lite（本地模型，可选）        │
└──────────────────────────────────────────────────────────────┘
```

**分层边界（PR-002）**：内核与 UI 在 `entry/`；通用基础设施（外壳/主题/i18n/存储/网络）复用 `ngf_framework`。

## 4. 核心技术映射

| DSH 上游 | 鸿蒙实现 | 迁移方式 |
|---|---|---|
| Cordis kernel（插件/效果/瀑布） | ArkTS 服务容器 + 事件总线 + 注册-回卷效果 | **重写**（语义移植） |
| SessionEvent 事件溯源日志 | `SessionLog`（追加式内存 + `@ohos.file.fs` JSONL 落盘） | **重写**（协议照搬） |
| turn/step AgentLoop | ArkTS 异步驱动循环 | **重写** |
| LlmAdapter + StreamChunk | 同词汇契约 + DeepSeek 适配器（`@ohos.net.http` 流式） | **重写**（协议 1:1） |
| ToolDefinition + 流水线 | 同语义注册表 + pre/execute/post | **重写** |
| MCP 客户端 | stdio（childprocess）/ streamable-http | **重写** |
| JSONL/SQLite 持久化 | JSONL + `@ohos.data.relationalStore` | **重写** |
| 设置/凭据 | `@ohos.data.preferences` + `@ohos.security.asset` | **重写** |
| React Web UI | ArkUI（复用 NGF 外壳） | **重写** |
| Landlock/ACL 沙箱 | AAF 应用权限模型（天然沙箱） | 平台替代 |
| worker_threads | `@ohos.worker` | 平台替代 |

## 5. 鸿蒙全设备适配策略

| 设备类型 | deviceTypes | 策略 |
|---|---|---|
| phone / tablet | phone, tablet | 全功能；会话 + 工具 + MCP |
| 2in1（PC） | 2in1 | 全功能 + 键盘/多窗口/分屏（NGF 多窗口） |
| car（车机） | car | 裁剪：免注视交互、语音输入优先、无 MCP |
| tv（智慧屏） | tv | 裁剪：遥控器导航、大屏会话展示、无本地工具执行 |
| wearable（手表） | wearable | 最小化：短会话、语音输入、通知式结果、省电（系统任务） |

**统一 UI 策略**：ArkUI 响应式布局（`@ohos.mediaquery`/栅格）+ NGF 设备感知（折叠屏/握持/能力探测）做能力分级渲染；能力差异由内核"能力注册表"暴露，UI 按设备查询可用能力。

## 6. 里程碑

| 里程碑 | 内容 | 验收标准 |
|---|---|---|
| **M0** | 项目初始化（NGF 基座 + Harness） | ✅ 已完成 |
| **M1** | 最小可用 harness：事件内核 + 会话日志 + AgentLoop + DeepSeek 流式适配 + 简易对话 UI | phone 真机可流式对话，会话可持久化恢复 |
| **M2** | 上下文管理（system-prompt 组装、token 预算、compaction 语义）+ 设置/凭据 | 长会话可压缩续聊；凭据经密钥保险箱 |
| **M3** | 工具系统（注册表 + 守卫流水线 + 内置工具）+ MCP 客户端 | 模型可调用工具并回显结果卡片；可连接外部 MCP 服务器 |
| **M4** | 全设备适配 + UI 完善 + 发布准备 | tablet/2in1/car/tv/wearable 能力分级可用，具备上架条件 |

## 7. 风险与开放问题

- **ArkTS 约束**：无 `any`/动态属性/解构/模板字面量（部分），事件字典需用显式联合类型而非 declaration merging；插件模型用接口注册表实现。
- **LLM 流式**：`@ohos.net.http` 流式响应能力需验证（SSE 解析、中断/重连语义）。
- **MCP stdio**：鸿蒙 `@ohos.process.childprocess` 拉起外部进程能力受限，优先级低于 streamable-http。
- **低资源设备**：手表/tv 的内存与网络预算需内核级裁剪（按设备能力开关模块）。
- **本地模型**：是否集成 MindSpore Lite 待产品决策（默认云端 API 优先）。
- **上游同步**：dsh 处于开发者预览（破坏性变更频繁），HDSH 锁定语义契约而非源码，上游重大变化时评审对齐。

## 8. 参考

- DSH 官方仓库：`github.com/deepseek-ai/deepseek-harness`（架构文档 `docs/architecture.md`、`docs/subsystems/*`）
- NGF：本仓库的 `ngf_framework/` 与 `.rules/` 技能库
- DSH 架构调研报告：本次任务 explore 子任务输出（详见对话记录）
