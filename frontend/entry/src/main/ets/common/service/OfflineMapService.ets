import { common, Want } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { logger } from '../utils/Logger'
import { OfflineMapStore } from '../utils/OfflineMapStore'

const TAG = 'OfflineMapService'
const PETAL_MAPS_BUNDLE = 'com.huawei.hmos.maps.app'
const PETAL_MAPS_URI = 'maps://main'
const ERR_TARGET_NOT_FOUND = 16000001

export interface PetalMapsLaunchResult {
  launched: boolean
  notInstalled: boolean
  errorCode?: number
  errorMessage?: string
}

/**
 * 离线地图服务
 *
 * Map Kit 自身不提供"按区域批量下载离线地图"的接口。但 HarmonyOS NEXT 的
 * Petal Maps 已支持离线地图，且当前 app 的 @kit.MapKit 在断网时会自动复用
 * Petal Maps 下载好的离线数据。因此我们的策略是：把用户引导到 Petal Maps
 * 完成下载，再回到我们 app —— 不做瓦片爬取，避免合规风险。
 */
export class OfflineMapService {
  private static instance: OfflineMapService

  static getInstance(): OfflineMapService {
    if (!OfflineMapService.instance) {
      OfflineMapService.instance = new OfflineMapService()
    }
    return OfflineMapService.instance
  }

  async openPetalMapsForDownload(context: common.UIAbilityContext): Promise<PetalMapsLaunchResult> {
    const want: Want = {
      bundleName: PETAL_MAPS_BUNDLE,
      uri: PETAL_MAPS_URI,
      parameters: { linkSource: 'memory_map_offline_setup' }
    }
    try {
      await context.startAbility(want)
      logger.info(TAG, 'Launched Petal Maps')
      return { launched: true, notInstalled: false }
    } catch (e) {
      const err = e as BusinessError
      logger.error(TAG, `startAbility failed code=${err.code} msg=${err.message}`)
      return {
        launched: false,
        notInstalled: err.code === ERR_TARGET_NOT_FOUND,
        errorCode: err.code,
        errorMessage: err.message
      }
    }
  }

  async markAsDownloaded(context: common.UIAbilityContext): Promise<void> {
    try {
      await OfflineMapStore.saveEnabled(context)
      logger.info(TAG, 'Offline map marked as downloaded')
    } catch (err) {
      logger.error(TAG, `markAsDownloaded failed: ${JSON.stringify(err)}`)
      throw new Error('保存离线地图状态失败')
    }
  }

  async clearDownloadedFlag(context: common.UIAbilityContext): Promise<void> {
    try {
      await OfflineMapStore.clearDownloaded(context)
      logger.info(TAG, 'Offline map flag cleared')
    } catch (err) {
      logger.error(TAG, `clearDownloadedFlag failed: ${JSON.stringify(err)}`)
      throw new Error('清除离线地图状态失败')
    }
  }
}
