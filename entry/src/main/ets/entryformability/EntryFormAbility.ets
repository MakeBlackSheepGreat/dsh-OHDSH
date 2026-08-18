import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { HdshLogger } from '../hdsh/utils/Logger';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    HdshLogger.info('EntryFormAbility', 'onAddForm called');
    const formData: Record<string, string> = {
      'frameworkStatus': '已就绪 (Ready)',
      'lastUpdate': new Date().toLocaleTimeString()
    };
    return formBindingData.createFormBindingData(formData);
  }

  onCastToNormalForm(formId: string): void {
    HdshLogger.info('EntryFormAbility', 'onCastToNormalForm formId: ' + formId);
  }

  onUpdateForm(formId: string): void {
    HdshLogger.info('EntryFormAbility', 'onUpdateForm formId: ' + formId);
    const formData: Record<string, string> = {
      'frameworkStatus': '刷新完成 (Updated)',
      'lastUpdate': new Date().toLocaleTimeString()
    };
    const formBinding = formBindingData.createFormBindingData(formData);
    formProvider.updateForm(formId, formBinding).catch((error: Error) => {
      HdshLogger.error('EntryFormAbility', 'updateForm error: ' + error.message);
    });
  }

  onChangeFormVisibility(newStatus: Record<string, number>): void {
    HdshLogger.info('EntryFormAbility', 'onChangeFormVisibility called');
  }

  onFormEvent(formId: string, message: string): void {
    HdshLogger.info('EntryFormAbility', 'onFormEvent formId: ' + formId + ', message: ' + message);
    // Respond to widget message event (e.g., refresh button)
    if (message === 'refresh') {
      this.onUpdateForm(formId);
    }
  }

  onRemoveForm(formId: string): void {
    HdshLogger.info('EntryFormAbility', 'onRemoveForm formId: ' + formId);
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }
}
