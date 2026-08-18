/**
 * HDSH DeepSeek LLM 适配器（OpenAI Chat Completions 兼容 SSE 流式）。
 *
 * 语义对齐 DSH packages/llm/llm-deepseek：
 * - 通过 @ohos.net.http 流式请求 https://api.deepseek.com/chat/completions；
 * - 解析 SSE 帧（data: {...}）并产出 StreamChunk 序列；
 * - 支持 deepseek-chat / deepseek-reasoner（reasoning_content）。
 *
 * 注意：requestInStream + dataReceive 的 API 签名需在 DevEco SDK 环境最终验证。
 */
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import {
  LlmAdapter,
  GenerateOptions,
  StreamChunk,
  StreamChunkKind,
  TokenUsage,
  LlmMessage,
  LlmRole
} from './LlmTypes';

const DEFAULT_BASE_URL: string = 'https://api.deepseek.com';

/** wire 层消息（OpenAI 兼容）。 */
interface WireMessage {
  role: string;
  content: string;
}

/** wire 层请求载荷（OpenAI Chat Completions 兼容）。 */
interface WireStreamOptions {
  include_usage: boolean;
}

interface WirePayload {
  model: string;
  messages: WireMessage[];
  stream: boolean;
  stream_options: WireStreamOptions;
}

export class DeepSeekAdapter implements LlmAdapter {
  private apiKey: string;
  private readonly baseUrl: string;

  constructor(apiKey: string, baseUrl: string) {
    this.apiKey = apiKey;
    this.baseUrl = baseUrl.length > 0 ? baseUrl : DEFAULT_BASE_URL;
  }

  /** 更新 API Key（设置页调用）。 */
  setApiKey(key: string): void {
    this.apiKey = key;
  }

  stream(options: GenerateOptions, onChunk: (chunk: StreamChunk) => void): Promise<void> {
    if (this.apiKey.length === 0) {
      return Promise.reject(new Error('DeepSeek API key is not configured'));
    }
    const request: http.HttpRequest = http.createHttp();
    const wireStreamOptions: WireStreamOptions = {
      include_usage: true
    };
    const payload: WirePayload = {
      model: options.model,
      messages: this.toWireMessages(options.messages),
      stream: true,
      stream_options: wireStreamOptions
    };
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + this.apiKey,
      'Accept': 'text/event-stream'
    };
    const httpOptions: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: JSON.stringify(payload),
      readTimeout: 120000,
      connectTimeout: 30000
    };

    return new Promise<void>((resolve: () => void, reject: (reason?: Object) => void) => {
      let buffer: string = '';
      let settled: boolean = false;

      const finish = (): void => {
        if (settled) {
          return;
        }
        settled = true;
        request.destroy();
        resolve();
      };

      const fail = (reason: Object): void => {
        if (settled) {
          return;
        }
        settled = true;
        request.destroy();
        reject(reason);
      };

      request.on('dataReceive', (data: ArrayBuffer) => {
        buffer = buffer + this.arrayBufferToUtf8(data);
        buffer = this.drainSse(buffer, onChunk);
      });

      request.on('dataEnd', () => {
        // 尾部残留帧（无 \n\n 结尾）也尝试解析
        if (buffer.length > 0) {
          this.handleSseFrame(buffer, onChunk);
        }
        onChunk(new StreamChunk(StreamChunkKind.Finish, '', '', '', '', null, 'stop'));
        finish();
      });

      request.requestInStream(this.baseUrl + '/chat/completions', httpOptions, (err: BusinessError) => {
        if (err && err.code !== undefined) {
          fail(new Error('DeepSeek stream request failed: code=' + err.code + ', message=' + err.message));
          return;
        }
        // 无错误：数据通过 dataReceive 持续到达，dataReceiveEnd 结束
      });
    });
  }

  private toWireMessages(messages: LlmMessage[]): WireMessage[] {
    const result: WireMessage[] = [];
    for (let i = 0; i < messages.length; i++) {
      const msg: LlmMessage = messages[i];
      const role: string = msg.role === LlmRole.System ? 'system'
        : (msg.role === LlmRole.Assistant ? 'assistant' : 'user');
      result.push({ role: role, content: msg.content });
    }
    return result;
  }

  /** 解析并消费 buffer 中完整的 SSE 帧，返回剩余未完成的字节串。 */
  private drainSse(buffer: string, onChunk: (chunk: StreamChunk) => void): string {
    let rest: string = buffer;
    for (;;) {
      const frameEnd: number = rest.indexOf('\n\n');
      if (frameEnd < 0) {
        break;
      }
      const frame: string = rest.substring(0, frameEnd);
      rest = rest.substring(frameEnd + 2);
      this.handleSseFrame(frame, onChunk);
    }
    return rest;
  }

  /** 解析单个 SSE 帧（可能含多行 data:）。 */
  private handleSseFrame(frame: string, onChunk: (chunk: StreamChunk) => void): void {
    const lines: string[] = frame.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i];
      if (!line.startsWith('data:')) {
        continue;
      }
      const data: string = line.substring(5).trim();
      if (data.length === 0 || data === '[DONE]') {
        continue;
      }
      try {
        const parsed: object = JSON.parse(data) as object;
        this.handleSseData(parsed, onChunk);
      } catch {
        // 忽略无法解析的帧（网络分包边界时不属于错误）
      }
    }
  }

  /** 解析 DeepSeek/OpenAI 兼容的流式 JSON 数据块。 */
  private handleSseData(parsed: object, onChunk: (chunk: StreamChunk) => void): void {
    const record: Record<string, Object> = parsed as Record<string, Object>;
    // usage（最终块附带）
    const usageValue: Object | undefined = record['usage'];
    if (usageValue !== undefined) {
      const usageRecord: Record<string, Object> = usageValue as Record<string, Object>;
      const prompt: number = this.toNumber(usageRecord['prompt_tokens']);
      const completion: number = this.toNumber(usageRecord['completion_tokens']);
      onChunk(new StreamChunk(StreamChunkKind.Usage, '', '', '', '', new TokenUsage(prompt, completion), ''));
    }

    const choices: Object | undefined = record['choices'];
    if (choices === undefined || !Array.isArray(choices)) {
      return;
    }
    const choicesArr: Object[] = choices as Object[];
    if (choicesArr.length === 0) {
      return;
    }
    const first: Object = choicesArr[0];
    const choiceRecord: Record<string, Object> = first as Record<string, Object>;

    // finish_reason
    const finish: Object | undefined = choiceRecord['finish_reason'];
    const finishReason: string = finish !== undefined ? String(finish) : '';

    const delta: Object | undefined = choiceRecord['delta'];
    if (delta === undefined) {
      return;
    }
    const deltaRecord: Record<string, Object> = delta as Record<string, Object>;
    const content: Object | undefined = deltaRecord['content'];
    const reasoning: Object | undefined = deltaRecord['reasoning_content'];

    if (content !== undefined && String(content).length > 0) {
      onChunk(new StreamChunk(StreamChunkKind.TextDelta, String(content), '', '', '', null, finishReason));
    }
    if (reasoning !== undefined && String(reasoning).length > 0) {
      onChunk(new StreamChunk(StreamChunkKind.ReasoningDelta, '', String(reasoning), '', '', null, finishReason));
    }
  }

  private toNumber(value: Object | undefined): number {
    if (value === undefined) {
      return 0;
    }
    const num: number = Number(value);
    return Number.isNaN(num) ? 0 : num;
  }

  private arrayBufferToUtf8(buffer: ArrayBuffer): string {
    try {
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(new Uint8Array(buffer));
    } catch (e) {
      return '';
    }
  }
}
