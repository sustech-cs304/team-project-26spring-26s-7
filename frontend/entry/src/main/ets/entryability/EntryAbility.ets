import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import { RdbHelper } from '../common/data/RdbHelper';
import { AuthService, SyncManager } from '../common';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    AppStorage.setOrCreate('travelDataVersion', 0);
    AppStorage.setOrCreate('cloudStatusText', '云存储未连接');

    try {
      AuthService.init(this.context);
      hilog.info(DOMAIN, 'testTag', 'Auth initialized successfully');
      AuthService.restoreSession().then((cloudReady: boolean) => {
        AppStorage.setOrCreate('cloudStatusText', cloudReady ? '云存储已连接' : '云存储暂不可用');
        if (cloudReady) {
          void SyncManager.triggerNow();
        }
      }).catch((err: Error) => {
        hilog.error(DOMAIN, 'testTag', 'Cloud restore failed: %{public}s', err.message);
        AppStorage.setOrCreate('cloudStatusText', '云存储暂不可用');
      });
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(DOMAIN, 'testTag', 'Auth initialization failed: %{public}s', error.message);
    }

    // 初始化 RDB 数据库
    RdbHelper.getInstance().initDatabase(this.context).then(() => {
      hilog.info(DOMAIN, 'testTag', 'Database initialized successfully');
    }).catch((err: Error) => {
      hilog.error(DOMAIN, 'testTag', 'Database initialization failed: %{public}s', err.message);
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
