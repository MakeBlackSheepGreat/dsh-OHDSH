/**
 * HDSH Harness 组合根（composition root）。
 *
 * 装配并持有内核各组件，提供应用启动入口：
 * - 事件总线（EventBus）
 * - 会话日志（SessionLog，事件溯源）
 * - LLM 运行时（LlmRuntime，适配器注册）
 * - Agent 驱动循环（AgentLoop，turn/step）
 *
 * 设计对齐 DSH 的"无特权内核 + 一切皆插件"哲学（最小实现）：
 * 组件间通过事件总线解耦，适配器/驱动可通过配置替换。
 */
import { EventBus } from './core/EventBus';
import { SessionLog } from './session/SessionLog';
import { LlmRuntime } from './llm/LlmRuntime';
import { DeepSeekAdapter } from './llm/DeepSeekAdapter';
import { AgentLoop } from './agent/AgentLoop';

/** Harness 启动配置。 */
export class HdshHarnessConfig {
  readonly apiKey: string;
  readonly baseUrl: string;
  readonly provider: string;
  readonly model: string;

  constructor(apiKey: string, baseUrl: string, provider: string, model: string) {
    this.apiKey = apiKey;
    this.baseUrl = baseUrl;
    this.provider = provider;
    this.model = model;
  }
}

export class HdshHarness {
  readonly bus: EventBus;
  readonly log: SessionLog;
  readonly llm: LlmRuntime;
  readonly loop: AgentLoop;
  private readonly adapter: DeepSeekAdapter;

  private constructor(bus: EventBus, log: SessionLog, llm: LlmRuntime, loop: AgentLoop, adapter: DeepSeekAdapter) {
    this.bus = bus;
    this.log = log;
    this.llm = llm;
    this.loop = loop;
    this.adapter = adapter;
  }

  /** 按配置装配 Harness 实例。 */
  static create(config: HdshHarnessConfig): HdshHarness {
    const bus: EventBus = new EventBus();
    const log: SessionLog = new SessionLog();
    const llm: LlmRuntime = new LlmRuntime();
    const adapter: DeepSeekAdapter = new DeepSeekAdapter(config.apiKey, config.baseUrl);
    llm.register(config.provider, adapter);
    const loop: AgentLoop = new AgentLoop(log, llm, config.provider, config.model);
    return new HdshHarness(bus, log, llm, loop, adapter);
  }

  /** 更新 LLM API Key（设置页/启动引导时调用）。 */
  setApiKey(key: string): void {
    this.adapter.setApiKey(key);
  }
}
