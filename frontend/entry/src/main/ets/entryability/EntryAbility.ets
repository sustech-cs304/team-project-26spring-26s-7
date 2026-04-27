import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import { connection } from '@kit.NetworkKit';
import { RdbHelper } from '../common/data/RdbHelper';
import { AuthService, SyncManager, ImageSanitizer } from '../common';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private netConnection?: connection.NetConnection
  private isOnline: boolean = true
  private networkDialogToken: number = 0

  private getCurrentNetworkStatus(): boolean {
    try {
      const netHandle = connection.getDefaultNetSync()
      if (!netHandle || netHandle.netId === 0) {
        return false
      }
      const capabilities = connection.getNetCapabilitiesSync(netHandle)
      const caps = capabilities.networkCap ?? []
      return caps.includes(connection.NetCap.NET_CAPABILITY_VALIDATED)
    } catch (_) {
      return false
    }
  }

  private updateNetworkState(isOnline: boolean): void {
    if (this.isOnline === isOnline) {
      return
    }

    this.isOnline = isOnline
    AppStorage.setOrCreate('networkOnline', isOnline)
    if (isOnline) {
      AppStorage.setOrCreate('networkJustReconnected', true)
      this.publishNetworkDialog('网络已恢复', '离线期间的更改不会自动同步，请前往个人页手动同步')
      return
    }

    AppStorage.setOrCreate('networkJustReconnected', false)
    this.publishNetworkDialog('网络已断开', '你已断网，操作不会上传云端')
  }

  private publishNetworkDialog(title: string, message: string): void {
    this.networkDialogToken += 1
    AppStorage.setOrCreate('networkDialogTitle', title)
    AppStorage.setOrCreate('networkDialogMessage', message)
    AppStorage.setOrCreate('networkDialogToken', this.networkDialogToken)
  }

  private registerNetworkListener(): void {
    try {
      this.netConnection = connection.createNetConnection()
      this.netConnection.on('netCapabilitiesChange', () => {
        const latestStatus = this.getCurrentNetworkStatus()
        hilog.info(DOMAIN, 'testTag', 'Network capabilities changed, online=%{public}s', latestStatus ? 'true' : 'false')
        this.updateNetworkState(latestStatus)
      })
      this.netConnection.on('netLost', () => {
        hilog.info(DOMAIN, 'testTag', '%{public}s', 'Network lost event received')
        this.updateNetworkState(false)
      })
      this.netConnection.on('netUnavailable', () => {
        hilog.info(DOMAIN, 'testTag', '%{public}s', 'Network unavailable event received')
        this.updateNetworkState(false)
      })
      this.netConnection.register((err?: BusinessError) => {
        if (err) {
          hilog.error(DOMAIN, 'testTag', 'Network listener register failed: %{public}s', err.message)
          return
        }
        hilog.info(DOMAIN, 'testTag', '%{public}s', 'Network listener registered')
      })
    } catch (err) {
      const error = err as BusinessError
      hilog.error(DOMAIN, 'testTag', 'Network listener init failed: %{public}s', error.message)
    }
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    AppStorage.setOrCreate('travelDataVersion', 0);
    AppStorage.setOrCreate('cloudStatusText', '云存储未连接');
    AppStorage.setOrCreate('networkOnline', true);
    AppStorage.setOrCreate('networkJustReconnected', false);
    AppStorage.setOrCreate('networkDialogTitle', '');
    AppStorage.setOrCreate('networkDialogMessage', '');
    AppStorage.setOrCreate('networkDialogToken', 0);
    this.isOnline = this.getCurrentNetworkStatus();
    hilog.info(DOMAIN, 'testTag', 'Initial network status: %{public}s', this.isOnline ? 'true' : 'false');
    AppStorage.setOrCreate('networkOnline', this.isOnline);
    this.registerNetworkListener();

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

    // 兜底清理：上次会话异常退出可能残留的 sanitize 副本（含像素，无 EXIF），
    // 启动时一次性扫掉，避免长期堆积
    try {
      ImageSanitizer.purgeAll(this.context);
    } catch (err) {
      hilog.warn(DOMAIN, 'testTag', 'Sanitizer purge on start failed: %{public}s', JSON.stringify(err));
    }
  }

  onDestroy(): void {
    try {
      this.netConnection?.unregister(() => {})
    } catch (_) {}
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
