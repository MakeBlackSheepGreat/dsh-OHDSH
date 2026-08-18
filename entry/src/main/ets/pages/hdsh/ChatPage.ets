/**
 * HDSH 会话对话页（M1 最小可用 UI）。
 *
 * - 订阅 HDSH 事件总线，由会话日志事件驱动渲染（回放保真原则）；
 * - 输入区发送消息 -> AgentLoop.runTurn() -> LLM 流式生成；
 * - API Key 在页面顶部临时输入（M2 里程碑迁移到设置页 + 密钥保险箱）。
 * - 注意：M1 使用简单布局验证内核，HDS 导航壳/主题在 M4 统一接入。
 */
import { HdshHarness, HdshHarnessConfig } from '../../hdsh/HdshHarness';
import { Disposer } from '../../hdsh/core/EventBus';
import {
  SessionEvent,
  SessionEventKind,
  UserMessageEvent,
  AssistantChunkEvent,
  AssistantMessageEvent
} from '../../hdsh/session/SessionEvent';

/** 展示层消息项。 */
export class ChatItem {
  readonly id: number;
  readonly role: string;
  content: string;
  streaming: boolean;

  constructor(id: number, role: string, content: string, streaming: boolean) {
    this.id = id;
    this.role = role;
    this.content = content;
    this.streaming = streaming;
  }
}

@Entry
@Component
struct ChatPage {
  @State private chatItems: ChatItem[] = [];
  @State private inputText: string = '';
  @State private busy: boolean = false;
  @State private apiKeyInput: string = '';
  @State private hintText: string = '';
  private harness: HdshHarness | null = null;
  private disposers: Array<Disposer> = [];
  private nextItemId: number = 0;

  aboutToAppear(): void {
    this.initHarness();
  }

  aboutToDisappear(): void {
    for (let i = 0; i < this.disposers.length; i++) {
      this.disposers[i]();
    }
    this.disposers = [];
  }

  private initHarness(): void {
    const config: HdshHarnessConfig = new HdshHarnessConfig('', '', 'deepseek', 'deepseek-chat');
    this.harness = HdshHarness.create(config);
    const bus = this.harness.bus;
    this.disposers.push(bus.on(SessionEventKind.UserMessage, (event: SessionEvent) => {
      if (event instanceof UserMessageEvent) {
        this.appendChatItem('user', event.content, false);
      }
    }));
    this.disposers.push(bus.on(SessionEventKind.AssistantChunk, (event: SessionEvent) => {
      if (event instanceof AssistantChunkEvent) {
        this.appendStreamingDelta(event.delta);
      }
    }));
    this.disposers.push(bus.on(SessionEventKind.AssistantMessage, (event: SessionEvent) => {
      if (event instanceof AssistantMessageEvent) {
        this.finalizeStreaming(event.content);
      }
    }));
  }

  private appendChatItem(role: string, content: string, streaming: boolean): void {
    this.nextItemId = this.nextItemId + 1;
    const items: ChatItem[] = this.chatItems.slice();
    items.push(new ChatItem(this.nextItemId, role, content, streaming));
    this.chatItems = items;
  }

  private appendStreamingDelta(delta: string): void {
    const items: ChatItem[] = this.chatItems.slice();
    if (items.length === 0) {
      return;
    }
    const last: ChatItem = items[items.length - 1];
    if (last.role === 'assistant' && last.streaming) {
      items[items.length - 1] = new ChatItem(last.id, 'assistant', last.content + delta, true);
    } else {
      this.nextItemId = this.nextItemId + 1;
      items.push(new ChatItem(this.nextItemId, 'assistant', delta, true));
    }
    this.chatItems = items;
  }

  private finalizeStreaming(content: string): void {
    const items: ChatItem[] = this.chatItems.slice();
    if (items.length === 0) {
      return;
    }
    const last: ChatItem = items[items.length - 1];
    if (last.role === 'assistant') {
      items[items.length - 1] = new ChatItem(last.id, 'assistant', content, false);
    }
    this.chatItems = items;
  }

  private onSend(): void {
    if (this.harness === null || this.busy) {
      return;
    }
    const text: string = this.inputText.trim();
    if (text.length === 0) {
      return;
    }
    if (this.apiKeyInput.length === 0) {
      this.hintText = '请先在上方输入 DeepSeek API Key';
      return;
    }
    this.hintText = '';
    this.harness.setApiKey(this.apiKeyInput);
    this.inputText = '';
    this.busy = true;
    this.harness.loop.runTurn(text).then(() => {
      this.busy = false;
    }).catch((err: Error) => {
      this.busy = false;
      this.appendChatItem('assistant', '请求失败: ' + err.message, false);
    });
  }

  @Builder
  buildMessageBubble(item: ChatItem) {
    Row() {
      if (item.role === 'user') {
        Column() {
          Text(item.content)
            .fontSize(15)
            .fontColor('#FFFFFF')
            .copyOption(CopyOptions.LocalDevice)
        }
        .alignItems(HorizontalAlign.End)
        .backgroundColor('#4A90D9')
        .borderRadius(12)
        .padding(10)
        .constraintSize({ maxWidth: '82%' })
        .margin({ left: 60 })
      } else {
        Column() {
          Text(item.content)
            .fontSize(15)
            .fontColor('#333333')
            .copyOption(CopyOptions.LocalDevice)
        }
        .alignItems(HorizontalAlign.Start)
        .backgroundColor('#FFFFFF')
        .borderRadius(12)
        .padding(10)
        .constraintSize({ maxWidth: '82%' })
        .margin({ right: 60 })
      }
    }
    .width('100%')
    .justifyContent(item.role === 'user' ? FlexAlign.End : FlexAlign.Start)
  }

  build() {
    Column({ space: 0 }) {
      // API Key 配置栏（M1 临时；M2 迁移到设置页 + @ohos.security.asset）
      Row({ space: 8 }) {
        TextInput({ placeholder: 'DeepSeek API Key', text: this.apiKeyInput })
          .onChange((value: string) => {
            this.apiKeyInput = value;
          })
          .layoutWeight(1)
          .fontSize(14)
        Text(this.busy ? '生成中' : '就绪')
          .fontSize(12)
          .fontColor(this.busy ? '#FF9800' : '#4CAF50')
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor('#EDEDED')

      if (this.hintText.length > 0) {
        Text(this.hintText)
          .fontSize(12)
          .fontColor('#D32F2F')
          .padding({ left: 12, right: 12, top: 4 })
          .width('100%')
      }

      // 消息列表
      List({ space: 8 }) {
        ForEach(this.chatItems, (item: ChatItem) => {
          ListItem() {
            this.buildMessageBubble(item)
          }
        }, (item: ChatItem) => item.id.toString())
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 12 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      // 输入区
      Row({ space: 8 }) {
        TextInput({ placeholder: '输入消息...', text: this.inputText })
          .onChange((value: string) => {
            this.inputText = value;
          })
          .layoutWeight(1)
          .enterKeyType(EnterKeyType.Send)
          .onSubmit(() => {
            this.onSend();
          })
        Button('发送')
          .onClick(() => {
            this.onSend();
          })
          .enabled(!this.busy)
          .height(40)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 12 })
      .backgroundColor('#EDEDED')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
