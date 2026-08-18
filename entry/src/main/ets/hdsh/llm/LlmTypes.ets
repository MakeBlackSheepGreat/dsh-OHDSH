/**
 * HDSH LLM 层类型与契约。
 *
 * 语义对齐 DSH packages/llm（llm-streaming 子系统）：
 * - LlmAdapter 契约：stream(options) -> 流式产出 StreamChunk；
 * - StreamChunk 为判别联合（kind + 载荷字段）；
 * - 协议词汇（Message/ContentBlock/StreamChunk）纯数据模型，与上游 1:1 对齐。
 */

/** 消息角色。 */
export enum LlmRole {
  System,
  User,
  Assistant
}

/** 模型消息（发送给 LLM 的最小单元）。 */
export class LlmMessage {
  readonly role: LlmRole;
  readonly content: string;

  constructor(role: LlmRole, content: string) {
    this.role = role;
    this.content = content;
  }
}

/** 流式块类型。 */
export enum StreamChunkKind {
  BlockStart,
  TextDelta,
  ReasoningDelta,
  ToolCallDelta,
  BlockEnd,
  Usage,
  Finish
}

/** token 用量统计。 */
export class TokenUsage {
  readonly promptTokens: number;
  readonly completionTokens: number;
  readonly totalTokens: number;

  constructor(promptTokens: number, completionTokens: number) {
    this.promptTokens = promptTokens;
    this.completionTokens = completionTokens;
    this.totalTokens = promptTokens + completionTokens;
  }
}

/** 流式块（判别联合：kind 决定有效载荷字段）。 */
export class StreamChunk {
  readonly kind: StreamChunkKind;
  readonly text: string;
  readonly toolCallId: string;
  readonly toolName: string;
  readonly toolArguments: string;
  readonly usage: TokenUsage | null;
  readonly finishReason: string;

  constructor(kind: StreamChunkKind, text: string, toolCallId: string, toolName: string, toolArguments: string,
    usage: TokenUsage | null, finishReason: string) {
    this.kind = kind;
    this.text = text;
    this.toolCallId = toolCallId;
    this.toolName = toolName;
    this.toolArguments = toolArguments;
    this.usage = usage;
    this.finishReason = finishReason;
  }
}

/** 生成选项：一次模型请求的完整输入。 */
export class GenerateOptions {
  readonly model: string;
  readonly messages: LlmMessage[];
  readonly stream: boolean;

  constructor(model: string, messages: LlmMessage[], stream: boolean) {
    this.model = model;
    this.messages = messages;
    this.stream = stream;
  }
}

/** LLM 适配器契约：实现方只需产出合规 StreamChunk 序列。 */
export interface LlmAdapter {
  stream(options: GenerateOptions, onChunk: (chunk: StreamChunk) => void): Promise<void>;
}
