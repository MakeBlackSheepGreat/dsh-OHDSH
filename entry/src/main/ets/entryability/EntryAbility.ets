/**
 * HDSH EntryAbility（精简版，M1）。
 *
 * 说明：本文件为 M1 里程碑的独立实现，不依赖 ngf_framework。
 * 当前本机 SDK 缺少 UIDesignKit（NGF HDS UI 外壳依赖），故 M1 直接加载 HDSH 自绘对话页；
 * 待获取完整 DevEco SDK 后再接入 NGF 框架初始化（ngfStarterKernel 等）。
 */
import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import { setContext, clearContext, NGFAbilityContextLike } from '../GlobalContext';
import { HdshLogger } from '../hdsh/utils/Logger';

const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const abilityContext = this.context as NGFAbilityContextLike;
    setContext(abilityContext);
    HdshLogger.info(TAG, 'onCreate');
  }

  onDestroy(): void {
    clearContext();
    HdshLogger.info(TAG, 'onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    HdshLogger.info(TAG, 'onWindowStageCreate');
    windowStage.loadContent('pages/hdsh/HdshWebPage', (err: BusinessError): void => {
      if (err.code !== 0) {
        HdshLogger.error(TAG, '加载页面失败: ' + JSON.stringify(err));
        return;
      }
      HdshLogger.info(TAG, '页面加载成功');
      // 使用系统为当前设备形态提供的默认主窗口尺寸，避免将 2in1 强制缩成手机长条比例。
    });
  }

  onForeground(): void {
    HdshLogger.info(TAG, 'onForeground');
  }

  onBackground(): void {
    HdshLogger.info(TAG, 'onBackground');
  }
}
