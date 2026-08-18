/**
 * HDSH 日志工具（基于 hilog）。
 *
 * M1 暂不依赖 ngf_framework 的 logger，后续集成 NGF 时可切换到框架日志系统。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

export class HdshLogger {
  static readonly DOMAIN: number = 0x0001;

  static info(tag: string, message: string): void {
    hilog.info(HdshLogger.DOMAIN, tag, '%{public}s', message);
  }

  static debug(tag: string, message: string): void {
    hilog.debug(HdshLogger.DOMAIN, tag, '%{public}s', message);
  }

  static warn(tag: string, message: string): void {
    hilog.warn(HdshLogger.DOMAIN, tag, '%{public}s', message);
  }

  static error(tag: string, message: string): void {
    hilog.error(HdshLogger.DOMAIN, tag, '%{public}s', message);
  }
}
