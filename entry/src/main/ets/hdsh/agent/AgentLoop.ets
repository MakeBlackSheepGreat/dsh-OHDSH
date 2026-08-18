/**
 * HDSH Agent 驱动循环（turn/step 模型）。
 *
 * 语义对齐 DSH packages/core/agent-loop（默认驱动）：
 * - step = 一次模型请求 + 其工具调用；turn = 0..n 个 step；
 * - 事件序列：turn/start → step/start → user/message → deriveMessages → llm/stream
 *   → assistant/chunk* → assistant/message → step/end → turn/end；
 * - M1 不执行工具（tool 流水线在 M3 里程碑接入），但事件模型已预留。
 */
import {
  TurnStartEvent,
  TurnEndEvent,
  StepStartEvent,
  StepEndEvent,
  UserMessageEvent,
  AssistantChunkEvent,
  AssistantMessageEvent
} from '../session/SessionEvent';
import { SessionLog } from '../session/SessionLog';
import { LlmRuntime } from '../llm/LlmRuntime';
import { GenerateOptions, StreamChunk, StreamChunkKind, LlmMessage } from '../llm/LlmTypes';

export class AgentLoop {
  private readonly log: SessionLog;
  private readonly llm: LlmRuntime;
  private readonly defaultProvider: string;
  private readonly defaultModel: string;
  private isRunning: boolean = false;
  /** 当前 step 聚合中的文本（assistant/chunk 累积）。 */
  private stepText: string = '';
  private stepReasoning: string = '';
  private stepFinishReason: string = '';

  constructor(log: SessionLog, llm: LlmRuntime, defaultProvider: string, defaultModel: string) {
    this.log = log;
    this.llm = llm;
    this.defaultProvider = defaultProvider;
    this.defaultModel = defaultModel;
  }

  get running(): boolean {
    return this.isRunning;
  }

  /** 执行一次完整 turn：追加用户消息并驱动 LLM 流式生成。 */
  async runTurn(userInput: string): Promise<void> {
    if (this.isRunning) {
      throw new Error('Agent loop is already running');
    }
    const trimmed: string = userInput.trim();
    if (trimmed.length === 0) {
      return;
    }
    this.isRunning = true;
    try {
      await this.executeTurn(trimmed);
    } finally {
      this.isRunning = false;
    }
  }

  private async executeTurn(userInput: string): Promise<void> {
    const now: number = Date.now();
    this.log.append(new TurnStartEvent(this.log.nextSeq(), now));

    // step 1：模型请求 + 流式生成（M1 仅单 step，工具执行留待 M3）
    await this.executeStep(userInput);

    this.log.append(new TurnEndEvent(this.log.nextSeq(), Date.now()));
  }

  private async executeStep(userInput: string): Promise<void> {
    const now: number = Date.now();
    this.log.append(new StepStartEvent(this.log.nextSeq(), now));
    this.log.append(new UserMessageEvent(this.log.nextSeq(), Date.now(), userInput));
    this.stepText = '';
    this.stepReasoning = '';
    this.stepFinishReason = '';

    const history: LlmMessage[] = this.log.deriveMessages();
    const adapter = this.llm.resolve(this.defaultProvider);
    const options: GenerateOptions = new GenerateOptions(this.defaultModel, history, true);

    await adapter.stream(options, (chunk: StreamChunk) => {
      this.onChunk(chunk);
    });

    this.log.append(new AssistantMessageEvent(
      this.log.nextSeq(),
      Date.now(),
      this.stepText,
      this.stepReasoning,
      this.stepFinishReason
    ));
    this.log.append(new StepEndEvent(this.log.nextSeq(), Date.now()));
  }

  private onChunk(chunk: StreamChunk): void {
    if (chunk.kind === StreamChunkKind.TextDelta) {
      this.stepText = this.stepText + chunk.text;
      this.log.append(new AssistantChunkEvent(this.log.nextSeq(), Date.now(), chunk.text));
    } else if (chunk.kind === StreamChunkKind.ReasoningDelta) {
      this.stepReasoning = this.stepReasoning + chunk.text;
    } else if (chunk.kind === StreamChunkKind.Finish) {
      this.stepFinishReason = chunk.finishReason;
    }
    // Usage / ToolCallDelta 在 M1 仅忽略（M3 接入工具流水线时消费）
  }
}
