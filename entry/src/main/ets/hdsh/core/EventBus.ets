/**
 * HDSH 事件总线。
 *
 * 语义对齐 DSH/Cordis 的事件系统（最小子集）：
 * - 订阅返回回卷函数（disposer），插件卸载时自动取消订阅；
 * - 事件按 kind 分发，监听器无 next() 委托（M1 简化，瀑布模型后续里程碑引入）。
 */
import { SessionEvent, SessionEventKind } from '../session/SessionEvent';

/** 事件处理函数。 */
export type EventHandler = (event: SessionEvent) => void;

/** 回卷函数：取消订阅 / 卸载副作用。 */
export type Disposer = () => void;

export class EventBus {
  private handlers: Map<SessionEventKind, EventHandler[]> = new Map<SessionEventKind, EventHandler[]>();

  /** 订阅某类事件，返回取消订阅函数。 */
  on(kind: SessionEventKind, handler: EventHandler): Disposer {
    let list: EventHandler[] | undefined = this.handlers.get(kind);
    if (list === undefined) {
      list = [];
      this.handlers.set(kind, list);
    }
    list.push(handler);
    return (): void => {
      const current: EventHandler[] | undefined = this.handlers.get(kind);
      if (current === undefined) {
        return;
      }
      const index: number = current.indexOf(handler);
      if (index >= 0) {
        current.splice(index, 1);
      }
    };
  }

  /** 广播事件给该类事件的订阅者（副本遍历，允许监听器内再次订阅）。 */
  emit(event: SessionEvent): void {
    const list: EventHandler[] | undefined = this.handlers.get(event.kind);
    if (list === undefined) {
      return;
    }
    const snapshot: EventHandler[] = list.slice();
    for (let i = 0; i < snapshot.length; i++) {
      snapshot[i](event);
    }
  }

  /** 清空所有订阅。 */
  clear(): void {
    this.handlers.clear();
  }
}
