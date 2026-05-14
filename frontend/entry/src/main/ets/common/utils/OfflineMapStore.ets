import { preferences } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'
import { logger } from './Logger'

const TAG = 'OfflineMapStore'
const STORE_NAME = 'offline_map_v1'

const KEY_HAS_DOWNLOADED = 'offlineMapHasDownloaded'
const KEY_CITY_NAME = 'offlineMapCityName'
const KEY_ENABLED_AT = 'offlineMapDownloadedAt'

export class OfflineMapStore {
  private static loaded: boolean = false

  static async ensureLoaded(context: common.UIAbilityContext): Promise<void> {
    if (OfflineMapStore.loaded) {
      return
    }
    try {
      const store = await preferences.getPreferences(context, { name: STORE_NAME })
      const hasDownloaded = await store.get(KEY_HAS_DOWNLOADED, false) as boolean
      const cityName = await store.get(KEY_CITY_NAME, '') as string
      const enabledAt = await store.get(KEY_ENABLED_AT, 0) as number

      AppStorage.setOrCreate(KEY_HAS_DOWNLOADED, hasDownloaded)
      AppStorage.setOrCreate(KEY_CITY_NAME, cityName)
      AppStorage.setOrCreate(KEY_ENABLED_AT, enabledAt)

      OfflineMapStore.loaded = true
      logger.info(TAG, `Loaded: enabled=${hasDownloaded}`)
    } catch (err) {
      logger.error(TAG, `ensureLoaded failed: ${JSON.stringify(err)}`)
      AppStorage.setOrCreate(KEY_HAS_DOWNLOADED, false)
      AppStorage.setOrCreate(KEY_CITY_NAME, '')
      AppStorage.setOrCreate(KEY_ENABLED_AT, 0)
      OfflineMapStore.loaded = true
    }
  }

  static async saveEnabled(context: common.UIAbilityContext): Promise<void> {
    const now = Date.now()
    AppStorage.setOrCreate(KEY_HAS_DOWNLOADED, true)
    AppStorage.setOrCreate(KEY_CITY_NAME, '全球基础地图')
    AppStorage.setOrCreate(KEY_ENABLED_AT, now)

    try {
      const store = await preferences.getPreferences(context, { name: STORE_NAME })
      await store.put(KEY_HAS_DOWNLOADED, true)
      await store.put(KEY_CITY_NAME, '全球基础地图')
      await store.put(KEY_ENABLED_AT, now)
      await store.flush()
      logger.info(TAG, 'Offline map enabled')
    } catch (err) {
      logger.error(TAG, `saveEnabled persist failed: ${JSON.stringify(err)}`)
    }
  }

  static async clearDownloaded(context: common.UIAbilityContext): Promise<void> {
    AppStorage.setOrCreate(KEY_HAS_DOWNLOADED, false)
    AppStorage.setOrCreate(KEY_CITY_NAME, '')
    AppStorage.setOrCreate(KEY_ENABLED_AT, 0)

    try {
      const store = await preferences.getPreferences(context, { name: STORE_NAME })
      await store.put(KEY_HAS_DOWNLOADED, false)
      await store.put(KEY_CITY_NAME, '')
      await store.put(KEY_ENABLED_AT, 0)
      await store.flush()
      logger.info(TAG, 'Offline map cleared')
    } catch (err) {
      logger.error(TAG, `clearDownloaded persist failed: ${JSON.stringify(err)}`)
    }
  }
}
