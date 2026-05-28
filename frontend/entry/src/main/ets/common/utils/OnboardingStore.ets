import { preferences } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'
import { logger } from './Logger'

const TAG = 'OnboardingStore'
const STORE_NAME = 'onboarding_v1'

const KEY_ONBOARDING_SEEN = 'onboardingSeenV1'
const KEY_ONBOARDING_LOADED = 'onboardingLoaded'

/**
 * 持久化"是否看过首启教程"标志。
 *
 * PersistentStorage.persistProp 在本项目所用的 HMOS 版本下行为不稳定（实测每次
 * 冷启动都拿不到上次写入的值），所以走和 ConsentManager / OfflineMapStore 一样的
 * @kit.ArkData preferences 方案——显式 async 读盘 + 写盘 + 镜像到 AppStorage。
 *
 * 时序：
 *   - MainPage.aboutToAppear fire-and-forget 调 ensureLoaded(ctx)
 *   - OnboardingOverlay 读 @StorageLink('onboardingLoaded') 和
 *     @StorageLink('onboardingSeenV1')；只有 loaded === true && seen === false
 *     才显示，避免冷启动期间读盘还没完成时一闪
 *   - dismiss 时 OnboardingStore.markSeen(ctx) 同时把 AppStorage 和
 *     preferences 落盘
 */
export class OnboardingStore {
  private static loaded: boolean = false

  static async ensureLoaded(context: common.UIAbilityContext): Promise<void> {
    if (OnboardingStore.loaded) {
      AppStorage.setOrCreate(KEY_ONBOARDING_LOADED, true)
      return
    }
    try {
      const store = await preferences.getPreferences(context, { name: STORE_NAME })
      const seen = await store.get(KEY_ONBOARDING_SEEN, false) as boolean
      AppStorage.setOrCreate(KEY_ONBOARDING_SEEN, seen)
      AppStorage.setOrCreate(KEY_ONBOARDING_LOADED, true)
      OnboardingStore.loaded = true
      logger.info(TAG, `Loaded: seen=${seen}`)
    } catch (err) {
      logger.error(TAG, `ensureLoaded failed: ${JSON.stringify(err)}`)
      // 读盘失败按"已看过"处理，避免功能性 UI 上反复弹引导骚扰用户
      AppStorage.setOrCreate(KEY_ONBOARDING_SEEN, true)
      AppStorage.setOrCreate(KEY_ONBOARDING_LOADED, true)
      OnboardingStore.loaded = true
    }
  }

  static async markSeen(context: common.UIAbilityContext): Promise<void> {
    AppStorage.setOrCreate(KEY_ONBOARDING_SEEN, true)
    try {
      const store = await preferences.getPreferences(context, { name: STORE_NAME })
      await store.put(KEY_ONBOARDING_SEEN, true)
      await store.flush()
      logger.info(TAG, 'Marked onboarding as seen')
    } catch (err) {
      logger.error(TAG, `markSeen persist failed: ${JSON.stringify(err)}`)
    }
  }
}
