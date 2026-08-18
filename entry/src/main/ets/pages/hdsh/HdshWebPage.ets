/**
 * HDSH DSH Web UI 页（ArkWeb 容器）。
 *
 * 启动流程：解压 DSH 环境 → 启动 native 子进程（libnode + DSH）→ 轮询 3080 → 加载 ArkWeb。
 */
import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { DshBootstrap } from '../../hdsh/bootstrap/DshBootstrap';
import { WorkspaceAccess } from '../../hdsh/access/WorkspaceAccess';
import { writeOhosInfo } from '../../hdsh/access/OhosInfoBridge';
import { HdshLogger } from '../../hdsh/utils/Logger';

const TAG: string = 'HdshWebPage';

@Entry
@Component
struct HdshWebPage {
  private controller: webview.WebviewController = new webview.WebviewController();
  @State private ready: boolean = false;
  @State private statusText: string = '正在启动 DSH 运行时...';
  private lastWidthBucket: number = -1;
  private sizeListenerOn: boolean = false;

  aboutToAppear(): void {
    this.boot();
  }

  aboutToDisappear(): void {
    if (this.sizeListenerOn) {
      this.unregisterWindowSizeListener();
    }
  }

  private async unregisterWindowSizeListener(): Promise<void> {
    if (!this.sizeListenerOn) return;
    try {
      const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const win = await window.getLastWindow(hostCtx);
      if (win !== null) {
        win.off('windowSizeChange');
        HdshLogger.info(TAG, '注销 windowSizeChange 监听');
      }
    } catch (e) {
      /* 窗口监听注销失败时忽略 */
    }
    this.sizeListenerOn = false;
  }

  // HDSH 鸿蒙适配：2in1 窗口可在手机/平板/PC 断点间切换，ArkWeb 内容宽度
  // 不跟随窗口（实测 PC 1920 窗口下 layout 仍按窄屏处理 → 白屏）。
  // 用系统 windowSizeChange 事件（比组件 onAreaChange 可靠），宽度跨断点
  // （<700 / 700-1024 / >1024）时刷新 ArkWeb，前端按新尺寸重排。
  private async registerWindowSizeListener(): Promise<void> {
    if (this.sizeListenerOn) return;
    try {
      const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const win = await window.getLastWindow(hostCtx);
      if (win === null) return;
      win.on('windowSizeChange', (size: window.Size): void => {
        const w: number = size.width;
        const bucket: number = w < 700 ? 0 : (w < 1024 ? 1 : 2);
        if (this.lastWidthBucket !== -1 && bucket !== this.lastWidthBucket) {
          HdshLogger.info(TAG, '窗口宽度跨断点 ' + this.lastWidthBucket + '→' + bucket + '（' + w + 'px），刷新 ArkWeb');
          this.controller.refresh(true);
        }
        this.lastWidthBucket = bucket;
      });
      // 记录初始断点桶（避免启动时误触发刷新）
      this.lastWidthBucket = win.getWindowProperties().windowRect.width < 700 ? 0 :
        (win.getWindowProperties().windowRect.width < 1024 ? 1 : 2);
      this.sizeListenerOn = true;
      HdshLogger.info(TAG, '已注册 windowSizeChange 监听（初始断点桶 ' + this.lastWidthBucket + '）');
    } catch (e) {
      HdshLogger.warn(TAG, '注册 windowSizeChange 监听失败: ' + String(e));
    }
  }

  private async boot(): Promise<void> {
    try {
      const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await DshBootstrap.ensureDshDir(hostCtx);
      await DshBootstrap.ensureBusybox(hostCtx);
      await DshBootstrap.ensurePnpm(hostCtx);
      // 恢复持久授权并把授权目录同步到沙箱 workspace（dsh 的 tool-fs/bash 可读写）
      await WorkspaceAccess.syncAuthorizedToWorkspace(hostCtx);
      // 写入鸿蒙信息 JSON，供 dsh Web UI 的"鸿蒙设置"段展示
      await writeOhosInfo(hostCtx);
      await DshBootstrap.launchDsh();
      HdshLogger.info(TAG, '等待 DSH server 就绪...');
      this.ready = await DshBootstrap.waitForServer(120000);
      if (this.ready) {
        this.statusText = 'DSH 已就绪';
        HdshLogger.info(TAG, 'DSH server 就绪，加载 ArkWeb');
        // HDSH 鸿蒙适配：注册窗口尺寸监听，跨断点切换时刷新 ArkWeb 重排
        this.registerWindowSizeListener();
      } else {
        this.statusText = 'DSH server 启动超时';
        HdshLogger.error(TAG, 'DSH server 启动超时，回读 node 日志');
        await DshBootstrap.dumpNodeLogs(hostCtx);
        await DshBootstrap.dumpFallbackDiag(hostCtx);
      }
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      this.statusText = '启动失败: ' + msg;
      HdshLogger.error(TAG, '启动失败: ' + msg);
    }
  }

  build() {
    Column() {
      if (this.ready) {
        Web({ src: 'http://127.0.0.1:3080', controller: this.controller })
          .width('100%')
          .height('100%')
          // HDSH 鸿蒙适配：手机/平板沉浸式——Web 内容扩展到系统栏区域，
          // 安全区避让由 Web 层插件注入的 env(safe-area-inset-*) CSS 处理
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          // 跨断点刷新由 registerWindowSizeListener 的 windowSizeChange 事件处理
      } else {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color('#4A90D9')
          Text(this.statusText)
            .fontSize(14)
            .fontColor('#666666')
            .margin({ top: 16 })
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
  }
}
