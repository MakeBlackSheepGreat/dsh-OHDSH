/**
 * HDSH 会话日志（事件溯源）。
 *
 * 语义对齐 DSH packages/core/session：
 * - 追加式 SessionEvent 日志，唯一事实源；
 * - deriveMessages() 从日志投影模型可见历史（核心不变式：模型可见 ⟺ 已入日志）；
 * - M1 为内存实现，JSONL 落盘与崩溃恢复在 M2 里程碑接入。
 */
import {
  SessionEvent,
  SessionEventKind,
  UserMessageEvent,
  AssistantMessageEvent
} from './SessionEvent';
import { LlmMessage, LlmRole } from '../llm/LlmTypes';

export class SessionLog {
  private events: SessionEvent[] = [];
  private seqCounter: number = 0;

  /** 生成下一个事件序号。 */
  nextSeq(): number {
    this.seqCounter = this.seqCounter + 1;
    return this.seqCounter;
  }

  /** 追加事件（日志只增不改）。 */
  append(event: SessionEvent): void {
    this.events.push(event);
  }

  /** 获取全部事件（副本，防止外部篡改）。 */
  getEvents(): SessionEvent[] {
    return this.events.slice();
  }

  /** 获取事件总数。 */
  size(): number {
    return this.events.length;
  }

  /**
   * 从日志投影模型可见历史。
   * 规则：user/message 与 assistant/message 进入历史；assistant/chunk 仅在聚合助手消息时使用。
   */
  deriveMessages(): LlmMessage[] {
    const result: LlmMessage[] = [];
    for (let i = 0; i < this.events.length; i++) {
      const event: SessionEvent = this.events[i];
      if (event instanceof UserMessageEvent) {
        result.push(new LlmMessage(LlmRole.User, event.content));
      } else if (event instanceof AssistantMessageEvent) {
        result.push(new LlmMessage(LlmRole.Assistant, event.content));
      }
    }
    return result;
  }

  /** 按 event 类型统计（调试/UI 徽标用）。 */
  countByKind(kind: SessionEventKind): number {
    let count: number = 0;
    for (let i = 0; i < this.events.length; i++) {
      if (this.events[i].kind === kind) {
        count = count + 1;
      }
    }
    return count;
  }
}
