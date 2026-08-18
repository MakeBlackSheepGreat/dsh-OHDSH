import { BackupExtensionAbility, BundleVersion } from '@kit.CoreFileKit';
import { HdshLogger } from '../hdsh/utils/Logger';

const TAG: string = 'EntryBackupAbility';

export default class EntryBackupAbility extends BackupExtensionAbility {
  async onBackup() {
    HdshLogger.info(TAG, '生命周期: onBackup');
    await Promise.resolve();
  }

  async onRestore(bundleVersion: BundleVersion) {
    HdshLogger.info(TAG, '生命周期: onRestore', JSON.stringify(bundleVersion));
    await Promise.resolve();
  }
}
