/**
 * HDSH MultitonEntryAbility（多实例入口，精简版，M1）。
 */
import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import { setContext, clearContext, NGFAbilityContextLike } from '../GlobalContext';
import { HdshLogger } from '../hdsh/utils/Logger';

const TAG: string = 'MultitonEntryAbility';

export default class MultitonEntryAbility extends UIAbility {
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
    });
  }
}
