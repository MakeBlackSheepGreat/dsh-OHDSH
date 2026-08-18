/**
 * HDSH 会话事件模型（事件溯源核心）。
 *
 * 语义对齐 DSH（DeepSeek Harness）的 SessionEventMap：
 * 会话日志是唯一事实源，UI 渲染与模型历史均由日志投影。
 * 核心不变式：模型可见 ⟺ 已入日志。
 *
 * 注：M1 仅实现最小事件集；后续里程碑按需扩展（tool/todo/request 等）。
 */

/** 事件类型枚举（数字枚举，ArkTS 兼容）。 */
export enum SessionEventKind {
  TurnStart,
  TurnEnd,
  StepStart,
  StepEnd,
  UserMessage,
  AssistantChunk,
  AssistantMessage,
  ToolCall,
  ToolResult
}

/** 事件基类：所有会话事件共享 seq/kind/timestamp。 */
export abstract class SessionEvent {
  /** 单调递增序号（会话内唯一）。 */
  readonly seq: number;
  readonly kind: SessionEventKind;
  readonly timestamp: number;

  constructor(seq: number, kind: SessionEventKind, timestamp: number) {
    this.seq = seq;
    this.kind = kind;
    this.timestamp = timestamp;
  }
}

/** turn 开始：一次完整的人类↔模型往返（0..n 个 step）。 */
export class TurnStartEvent extends SessionEvent {
  constructor(seq: number, timestamp: number) {
    super(seq, SessionEventKind.TurnStart, timestamp);
  }
}

/** turn 结束。 */
export class TurnEndEvent extends SessionEvent {
  constructor(seq: number, timestamp: number) {
    super(seq, SessionEventKind.TurnEnd, timestamp);
  }
}

/** step 开始：一次模型请求 + 其工具调用。 */
export class StepStartEvent extends SessionEvent {
  constructor(seq: number, timestamp: number) {
    super(seq, SessionEventKind.StepStart, timestamp);
  }
}

/** step 结束。 */
export class StepEndEvent extends SessionEvent {
  constructor(seq: number, timestamp: number) {
    super(seq, SessionEventKind.StepEnd, timestamp);
  }
}

/** 用户消息（模型可见，必须入日志）。 */
export class UserMessageEvent extends SessionEvent {
  readonly content: string;

  constructor(seq: number, timestamp: number, content: string) {
    super(seq, SessionEventKind.UserMessage, timestamp);
    this.content = content;
  }
}

/** 助手增量输出（token 级，保留回放保真）。 */
export class AssistantChunkEvent extends SessionEvent {
  readonly delta: string;

  constructor(seq: number, timestamp: number, delta: string) {
    super(seq, SessionEventKind.AssistantChunk, timestamp);
    this.delta = delta;
  }
}

/** 助手完整消息（当前 step 结束后的定型内容）。 */
export class AssistantMessageEvent extends SessionEvent {
  readonly content: string;
  readonly reasoningContent: string;
  readonly finishReason: string;

  constructor(seq: number, timestamp: number, content: string, reasoningContent: string, finishReason: string) {
    super(seq, SessionEventKind.AssistantMessage, timestamp);
    this.content = content;
    this.reasoningContent = reasoningContent;
    this.finishReason = finishReason;
  }
}

/** 工具调用（模型请求执行工具；M3 里程碑启用执行，M1 仅记录）。 */
export class ToolCallEvent extends SessionEvent {
  readonly toolName: string;
  readonly toolArguments: string;

  constructor(seq: number, timestamp: number, toolName: string, toolArguments: string) {
    super(seq, SessionEventKind.ToolCall, timestamp);
    this.toolName = toolName;
    this.toolArguments = toolArguments;
  }
}

/** 工具执行结果。 */
export class ToolResultEvent extends SessionEvent {
  readonly toolName: string;
  readonly content: string;
  readonly isError: boolean;

  constructor(seq: number, timestamp: number, toolName: string, content: string, isError: boolean) {
    super(seq, SessionEventKind.ToolResult, timestamp);
    this.toolName = toolName;
    this.content = content;
    this.isError = isError;
  }
}
