/**
 * HDSH LLM 运行时：适配器注册表 + 路由。
 *
 * 语义对齐 DSH ctx.llm（LlmRuntime）的最小子集：
 * - 按 provider 注册适配器，返回回卷函数（插件可卸载）；
 * - resolve() 按 provider 名路由。
 */
import { LlmAdapter } from './LlmTypes';

export class LlmRuntime {
  private adapters: Map<string, LlmAdapter> = new Map<string, LlmAdapter>();
  private defaultProvider: string = 'deepseek';

  /** 注册适配器，返回回卷函数。 */
  register(provider: string, adapter: LlmAdapter): () => void {
    this.adapters.set(provider, adapter);
    return (): void => {
      this.adapters.delete(provider);
    };
  }

  /** 按 provider 解析适配器；未注册时抛错。 */
  resolve(provider: string): LlmAdapter {
    const adapter: LlmAdapter | undefined = this.adapters.get(provider);
    if (adapter === undefined) {
      throw new Error('No LLM adapter registered for provider: ' + provider);
    }
    return adapter;
  }

  /** 是否已注册指定 provider。 */
  has(provider: string): boolean {
    return this.adapters.has(provider);
  }

  getDefaultProvider(): string {
    return this.defaultProvider;
  }

  /** 列出已注册 provider（UI 模型选择用）。 */
  listProviders(): string[] {
    const result: string[] = [];
    this.adapters.forEach((adapter: LlmAdapter, key: string) => {
      result.push(key);
    });
    return result;
  }
}
