import { hilog } from '@kit.PerformanceAnalysisKit'
import { logger } from '../utils/Logger'
import { TravelSpecialValues } from '../utils/Constants'
import { RdbHelper } from '../data/RdbHelper'
import { TravelRepository } from '../data/TravelRepository'
import { MemoryNodeRepository } from '../data/MemoryNodeRepository'
import { AuthService, CloudStorageService } from '../auth'
import { CloudSyncService } from './CloudSyncService'
import type { SyncQueueItem, Trip, MemoryNode } from '../service/types'
import { PhotoPickerUtil } from '../utils/PhotoPickerUtil'

const TAG = 'SyncManager'
const DOMAIN = 0x0000

export class SyncManager {
  private static syncing: boolean = false
  private static pendingRetry: boolean = false

  static async pushLocalNow(): Promise<void> {
    if (SyncManager.syncing) {
      SyncManager.pendingRetry = true
      return
    }

    SyncManager.syncing = true
    try {
      const user = await AuthService.getCurrentUser()
      if (!user) {
        return
      }
      let items = await RdbHelper.getInstance().getPendingSyncQueueItems(user.uid)
      while (items.length > 0) {
        SyncManager.pendingRetry = false
        for (let i = 0; i < items.length; i++) {
          await SyncManager.handleItem(items[i])
        }
        items = await RdbHelper.getInstance().getPendingSyncQueueItems(user.uid)
      }
      await RdbHelper.getInstance().setSyncState('last_push_at', Date.now(), user.uid)
    } finally {
      SyncManager.syncing = false
      if (SyncManager.pendingRetry) {
        SyncManager.pendingRetry = false
        void SyncManager.pushLocalNow()
      }
    }
  }

  static async pullCloudNow(): Promise<void> {
    if (SyncManager.syncing) {
      return
    }

    SyncManager.syncing = true
    try {
      const user = await AuthService.getCurrentUser()
      if (!user) {
        return
      }
      await RdbHelper.getInstance().clearSyncQueue(user.uid)
      await SyncManager.replaceLocalWithCloud()
      await RdbHelper.getInstance().setSyncState('last_pull_at', Date.now(), user.uid)
    } finally {
      SyncManager.syncing = false
    }
  }

  static async pushAllLocalToCloud(): Promise<void> {
    if (SyncManager.syncing) {
      return
    }

    SyncManager.syncing = true
    try {
      const user = await AuthService.getCurrentUser()
      if (!user) {
        return
      }
      await SyncManager.syncAllLocalToCloud()
      // syncAllLocalToCloud 已对全量本地数据按当前状态推送到云端，
      // sync_queue 里残留的离线 CRUD 记录此时已被覆盖，全部清空以避免 pendingCount 永不归零，
      // 也避免下次任何手动调用 pushLocalNow 时把过期 payload 再推一次。
      await RdbHelper.getInstance().clearSyncQueue(user.uid)
      await RdbHelper.getInstance().setSyncState('last_push_at', Date.now(), user.uid)
    } finally {
      SyncManager.syncing = false
    }
  }

  static async pullAllCloudToLocal(): Promise<void> {
    if (SyncManager.syncing) {
      return
    }

    SyncManager.syncing = true
    try {
      const user = await AuthService.getCurrentUser()
      if (!user) {
        return
      }
      await RdbHelper.getInstance().clearSyncQueue(user.uid)
      await SyncManager.replaceLocalWithCloud()
      await RdbHelper.getInstance().setSyncState('last_pull_at', Date.now(), user.uid)
    } finally {
      SyncManager.syncing = false
    }
  }

  static async triggerNow(): Promise<void> {
    await SyncManager.pushLocalNow()
    await SyncManager.replaceLocalWithCloud()
  }

  static isSyncing(): boolean {
    return SyncManager.syncing
  }

  private static async handleItem(item: SyncQueueItem): Promise<void> {
    try {
      if (item.entityType === 'travel' && item.operation === 'upsert') {
        hilog.info(DOMAIN, TAG, `[handleItem] travel upsert payload=${item.payload}`)
        const cloudId = await CloudSyncService.upsertTravel(item.payload)
        hilog.info(DOMAIN, TAG, `[handleItem] travel upsert success cloudId=${cloudId}`)
        await new TravelRepository().updateSyncMetadata(item.entityId, cloudId, 'synced', Date.now())
      } else if (item.entityType === 'travel' && item.operation === 'delete') {
        // Bug 1 修复关键点：删 travel 时**只删 cloudDB 行**，不再 deleteDirectoryRecursively
        // 整个 travels/<T>/ 目录。原因：在我们的设计里 deleteTravel 只是软删 travel 元数据，
        // 子节点会被迁移到 UNCATEGORIZED（不删）。它们的图片文件仍然保留在原 travels/<T>/nodes/<N>/
        // 路径下，photoManifest 也指向那里。如果这里 wipe 整目录，孩子们的图就一起没了。
        // 真正需要删图的场景在 deleteNode 那条路径上，按 photoCloudPaths 精准删。
        const data = JSON.parse(item.payload) as Record<string, string | number>
        const localId = (data.localId as string) || item.entityId
        const ownerUid = (data.ownerUid as string) || ''
        const cloudId = (data.cloudId as string) || CloudSyncService.buildTravelCloudId(ownerUid, localId)
        await CloudSyncService.hardDeleteTravelByCloudId(cloudId, ownerUid)
        await new TravelRepository().updateSyncMetadata(item.entityId, cloudId, 'synced', Date.now())
      } else if (item.entityType === 'memory_node' && item.operation === 'upsert') {
        const cloudId = await CloudSyncService.upsertMemoryNode(item.payload)
        await new MemoryNodeRepository().updateSyncMetadata(item.entityId, cloudId, 'synced', Date.now())
      } else if (item.entityType === 'memory_node' && item.operation === 'delete') {
        // 删节点时按 photoCloudPaths 精准删每张图（这些路径来自 photoManifest，是云端真实位置）。
        // 不再 deleteDirectoryRecursively(travels/<currentTravelId>/nodes/<N>/) —— 节点可能跨过 travel
        // （比如经历过 deleteTravel 进入 UNCATEGORIZED），currentTravelId='-1' 但实际文件在原 travel 目录，
        // 那条 wipe 既删错地方又会顺手把别的孤儿文件牵连。
        const data = JSON.parse(item.payload) as Record<string, string | number | string[]>
        const localId = (data.localId as string) || item.entityId
        const ownerUid = (data.ownerUid as string) || ''
        const cloudId = (data.cloudId as string) || CloudSyncService.buildNodeCloudId(ownerUid, localId)
        const photoCloudPaths = Array.isArray(data.photoCloudPaths) ? data.photoCloudPaths as string[] : []
        for (let i = 0; i < photoCloudPaths.length; i++) {
          try {
            await CloudStorageService.deleteFile(photoCloudPaths[i])
          } catch (err) {
            // 单张图删失败不阻断后续删除（可能是已经被删过、路径不存在等等）
            hilog.warn(DOMAIN, TAG, `delete photo file failed: ${photoCloudPaths[i]}: ${JSON.stringify(err)}`)
          }
        }
        await CloudSyncService.hardDeleteMemoryNodeByCloudId(cloudId, ownerUid)
        await new MemoryNodeRepository().updateSyncMetadata(item.entityId, cloudId, 'synced', Date.now())
      } else {
        logger.warn(TAG, `Skip unsupported sync item: ${item.entityType}/${item.operation}`)
        return
      }
      await RdbHelper.getInstance().removeSyncItems(item.entityType, item.entityId, item.ownerUid)
    } catch (err) {
      logger.error(TAG, `Failed to sync item ${item.id}: ${JSON.stringify(err)}`)
    }
  }

  private static async syncAllLocalToCloud(): Promise<void> {
    const user = await AuthService.getCurrentUser()
    if (!user) {
      return
    }

    const travelRepo = new TravelRepository()
    const nodeRepo = new MemoryNodeRepository()
    const localTravels = await travelRepo.getAllTravelsIncludingDeleted()
    const localNodes = await nodeRepo.getAllNodesIncludingDeleted()
    const cloudTravels = await CloudSyncService.fetchTravels(user.uid)
    const cloudNodes = await CloudSyncService.fetchMemoryNodes(user.uid)

    const localTravelMap: Map<string, Trip> = new Map<string, Trip>()
    const localNodeMap: Map<string, MemoryNode> = new Map<string, MemoryNode>()
    const cloudTravelIds: Set<string> = new Set<string>()
    const cloudNodeIds: Set<string> = new Set<string>()

    for (let i = 0; i < localTravels.length; i++) {
      const travel = localTravels[i]
      const cloudId = travel.cloudId && travel.cloudId.length > 0
        ? travel.cloudId
        : CloudSyncService.buildTravelCloudId(user.uid, travel.id)
      localTravelMap.set(cloudId, travel)
      const payload = await CloudSyncService.buildTravelPayload(travel)
      if ((travel.deletedAt ?? 0) > 0) {
        // 与 handleItem('travel','delete') 同款修法：只删 cloudDB 行，不再 wipe travels/<T>/ 整目录。
        // 子节点（已迁到 UNCATEGORIZED）的图片仍然在 travels/<T>/nodes/<N>/ 下被引用，不能动。
        await CloudSyncService.hardDeleteTravelByCloudId(cloudId, user.uid)
      } else {
        await CloudSyncService.upsertTravel(payload)
      }
      await travelRepo.updateSyncMetadata(travel.id, cloudId, 'synced', Date.now())
    }

    for (let i = 0; i < localNodes.length; i++) {
      const node = localNodes[i]
      const cloudId = node.cloudId && node.cloudId.length > 0
        ? node.cloudId
        : CloudSyncService.buildNodeCloudId(user.uid, node.id)
      localNodeMap.set(cloudId, node)
      const payload = await CloudSyncService.buildNodePayload(node)
      if ((node.deletedAt ?? 0) > 0) {
        // 按 photoManifest 精准删每张图，避免按 currentTravelId 拼出来的目录指错地方
        // （跨 travel 的节点 currentTravelId='-1' 但实际文件在原 travel 目录）。
        const manifestPaths = SyncManager.parsePhotoManifest(node.photoManifest ?? '')
        for (let p = 0; p < manifestPaths.length; p++) {
          try {
            await CloudStorageService.deleteFile(manifestPaths[p])
          } catch (err) {
            hilog.warn(DOMAIN, TAG, `delete node photo failed: ${manifestPaths[p]}: ${JSON.stringify(err)}`)
          }
        }
        await CloudSyncService.hardDeleteMemoryNodeByCloudId(cloudId, user.uid)
      } else {
        await CloudSyncService.upsertMemoryNode(payload)
        await SyncManager.syncNodePhotosForUpload(node)
        // 上传照片后 photoManifest 已更新，重新 upsert 以写入正确的云端路径
        const updatedPayload = await CloudSyncService.buildNodePayload(node)
        await CloudSyncService.upsertMemoryNode(updatedPayload)
      }
      await nodeRepo.updateSyncMetadata(node.id, cloudId, 'synced', Date.now())
    }

    for (let i = 0; i < cloudTravels.length; i++) {
      const cloudTravel = cloudTravels[i]
      const cloudId = cloudTravel.cloudId ?? ''
      cloudTravelIds.add(cloudId)
      if (!cloudId || localTravelMap.has(cloudId)) {
        continue
      }
      // 反向清理：fetch 已按 ownerUid 过滤，hardDelete 又加 ownerUid 闸门，
      // 所以只会动到当前用户的行。这里只删 DB 行，不再 wipe 目录 —— 同 deletedAt 分支理由。
      await CloudSyncService.hardDeleteTravelByCloudId(cloudId, user.uid)
    }

    for (let i = 0; i < cloudNodes.length; i++) {
      const cloudNode = cloudNodes[i]
      const cloudId = cloudNode.cloudId ?? ''
      cloudNodeIds.add(cloudId)
      if (!cloudId || localNodeMap.has(cloudId)) {
        continue
      }
      // 反向清理节点：按云端节点自己的 photoManifest 精准删图（这是最可靠的真相），
      // 没有 manifest 才回退到按 cloud_id 反推的路径。
      const cloudManifestPaths = SyncManager.parsePhotoManifest(cloudNode.photoManifest ?? '')
      if (cloudManifestPaths.length > 0) {
        for (let p = 0; p < cloudManifestPaths.length; p++) {
          try {
            await CloudStorageService.deleteFile(cloudManifestPaths[p])
          } catch (err) {
            hilog.warn(DOMAIN, TAG, `reverse-cleanup delete photo failed: ${cloudManifestPaths[p]}: ${JSON.stringify(err)}`)
          }
        }
      } else {
        const nodeLocalIdForPath = CloudSyncService.extractLocalIdFromCloudId(cloudId)
        const travelLocalIdForPath = cloudNode.travelId
          ? CloudSyncService.extractLocalIdFromCloudId(cloudNode.travelId)
          : ''
        if (travelLocalIdForPath.length > 0) {
          await CloudStorageService.deleteDirectoryRecursively(CloudStorageService.buildNodePhotoDir(travelLocalIdForPath, nodeLocalIdForPath))
        }
      }
      await CloudSyncService.hardDeleteMemoryNodeByCloudId(cloudId, user.uid)
    }

    for (let i = 0; i < localNodes.length; i++) {
      const node = localNodes[i]
      if ((node.deletedAt ?? 0) > 0) {
        continue
      }
      const cloudId = node.cloudId && node.cloudId.length > 0
        ? node.cloudId
        : CloudSyncService.buildNodeCloudId(user.uid, node.id)
      if (!cloudNodeIds.has(cloudId)) {
        await SyncManager.syncNodePhotosForUpload(node)
      }
    }
  }

  private static async replaceLocalWithCloud(): Promise<void> {
    const failedNodeIds: string[] = []

    try {
      const user = await AuthService.getCurrentUser()
      if (!user) {
        return
      }

      const travelRepo = new TravelRepository()
      const nodeRepo = new MemoryNodeRepository()
      const localTravels = await travelRepo.getAllTravelsIncludingDeleted()
      const localNodes = await nodeRepo.getAllNodesIncludingDeleted()
      const cloudTravels = await CloudSyncService.fetchTravels(user.uid)
      const cloudNodes = await CloudSyncService.fetchMemoryNodes(user.uid)
      hilog.info(DOMAIN, TAG, `replaceLocalWithCloud fetched travels=${cloudTravels.length}, nodes=${cloudNodes.length}`)

      const activeCloudTravelIds = new Set<string>()
      const activeCloudNodeIds = new Set<string>()

    for (let i = 0; i < cloudTravels.length; i++) {
      const travel = cloudTravels[i]
      if (!travel.cloudId) {
        continue
      }
      if ((travel.deletedAt ?? 0) > 0) {
        const localTravelId = await travelRepo.findLocalIdByCloudId(travel.cloudId)
        if (localTravelId) {
          await travelRepo.deleteTravel(localTravelId)
        }
        continue
      }
      activeCloudTravelIds.add(travel.cloudId)
      await travelRepo.upsertFromCloud(travel)
    }

    for (let i = 0; i < localTravels.length; i++) {
      const localTravel = localTravels[i]
      if ((localTravel.deletedAt ?? 0) > 0) {
        continue
      }
      const cloudId = localTravel.cloudId && localTravel.cloudId.length > 0
        ? localTravel.cloudId
        : CloudSyncService.buildTravelCloudId(user.uid, localTravel.id)
      if (!activeCloudTravelIds.has(cloudId)) {
        await travelRepo.deleteTravel(localTravel.id)
        await travelRepo.updateSyncMetadata(localTravel.id, cloudId, 'synced', Date.now())
      }
    }

    for (let i = 0; i < cloudNodes.length; i++) {
      const node = cloudNodes[i]
      const travelCloudId = node.travelId
      if (!node.cloudId) {
        continue
      }
      if (travelCloudId === TravelSpecialValues.UNCATEGORIZED_TRAVEL_ID) {
        hilog.info(
          DOMAIN,
          TAG,
          `[debug] download uncategorized node cloudId=${node.cloudId}, localTravelId=${TravelSpecialValues.UNCATEGORIZED_TRAVEL_ID}`
        )
        node.travelId = TravelSpecialValues.UNCATEGORIZED_TRAVEL_ID
      } else {
        const localTravelId = await travelRepo.findLocalIdByCloudId(travelCloudId)
        hilog.info(
          DOMAIN,
          TAG,
          `[debug] download node start cloudId=${node.cloudId ?? ''}, travelCloudId=${travelCloudId}, localTravelId=${localTravelId ?? ''}, deletedAt=${node.deletedAt ?? 0}, photoManifest=${node.photoManifest ?? ''}`
        )
        if (!localTravelId) {
          hilog.info(
            DOMAIN,
            TAG,
            `[debug] skip cloud node due to missing mapping, cloudId=${node.cloudId ?? ''}, localTravelId=${localTravelId ?? ''}`
          )
          continue
        }
        node.travelId = localTravelId
      }
      if ((node.deletedAt ?? 0) > 0) {
        const localNodeId = await nodeRepo.findLocalIdByCloudId(node.cloudId)
        hilog.info(
          DOMAIN,
          TAG,
          `[debug] cloud node marked deleted cloudId=${node.cloudId}, localNodeId=${localNodeId ?? ''}`
        )
        if (localNodeId) {
          await nodeRepo.deleteNode(localNodeId)
        }
        continue
      }
      activeCloudNodeIds.add(node.cloudId)
      const localNodeId = await nodeRepo.findLocalIdByCloudId(node.cloudId)
      if (localNodeId) {
        node.id = localNodeId
      }
      try {
        await SyncManager.syncNodePhotosForDownload(node)
      } catch (err) {
        hilog.warn(DOMAIN, TAG, `Photo download failed for node ${node.id}: ${JSON.stringify(err)}`)
        failedNodeIds.push(node.id)
      }
      await nodeRepo.upsertFromCloud(node)
    }

    for (let i = 0; i < localNodes.length; i++) {
      const localNode = localNodes[i]
      if ((localNode.deletedAt ?? 0) > 0) {
        continue
      }
      const cloudId = localNode.cloudId && localNode.cloudId.length > 0
        ? localNode.cloudId
        : CloudSyncService.buildNodeCloudId(user.uid, localNode.id)
      if (!activeCloudNodeIds.has(cloudId)) {
        if (localNode.travelId === TravelSpecialValues.UNCATEGORIZED_TRAVEL_ID) {
          continue
        }
        await nodeRepo.deleteNode(localNode.id)
        await nodeRepo.updateSyncMetadata(localNode.id, cloudId, 'synced', Date.now())
      }
    }
    } finally {
      await SyncManager.bumpTravelDataVersion()

      if (failedNodeIds.length > 0) {
        AppStorage.setOrCreate('syncPartialFailure', true)
        AppStorage.setOrCreate('syncFailedNodeCount', failedNodeIds.length)
      } else {
        AppStorage.setOrCreate('syncPartialFailure', false)
        AppStorage.setOrCreate('syncFailedNodeCount', 0)
      }
    }
  }

  private static async bumpTravelDataVersion(): Promise<void> {
    const version = (AppStorage.get('travelDataVersion') as number) || 0
    AppStorage.setOrCreate('travelDataVersion', version + 1)
  }

  private static parsePhotoManifest(photoManifest: string): string[] {
    if (!photoManifest || photoManifest.length === 0) {
      return []
    }
    try {
      const parsed = JSON.parse(photoManifest) as Object
      if (!Array.isArray(parsed)) {
        return []
      }
      const result: string[] = []
      for (let i = 0; i < parsed.length; i++) {
        const item = parsed[i] as string
        if (typeof item === 'string' && item.length > 0) {
          result.push(item)
        }
      }
      return result
    } catch (_) {
      return []
    }
  }

  private static async syncNodePhotosForUpload(node: MemoryNode): Promise<void> {
    if ((node.deletedAt ?? 0) > 0) {
      return
    }
    // 用 home dir 作为上传/清理的目录前缀，而不是 node.travelId。这样跨过 travel 的节点
    // 上传仍然落到原 travel 目录，与 photoManifest 中既有路径保持一致；下面的"清理孤儿"也只
    // 在 home dir 范围内做，绝不会越界删别的 travel 的文件。
    const homeDir = CloudStorageService.getNodeHomeDir(node.photoManifest ?? '', node.travelId, node.id)
    const oldManifestPaths = SyncManager.parsePhotoManifest(node.photoManifest ?? '')
    const oldBasenameToPath = new Map<string, string>()
    for (let i = 0; i < oldManifestPaths.length; i++) {
      const p = oldManifestPaths[i]
      const slashIdx = p.lastIndexOf('/')
      if (slashIdx >= 0) {
        oldBasenameToPath.set(p.substring(slashIdx + 1), p)
      }
    }

    const expectedCloudFiles: Set<string> = new Set<string>()
    const manifestPaths: string[] = []
    for (let i = 0; i < node.photos.length; i++) {
      const photo = node.photos[i]
      if (!PhotoPickerUtil.photoExists(photo)) {
        continue
      }
      const fileName = CloudStorageService.getFileNameFromPath(photo)
      // 已经在旧 manifest 里出现过的图沿用旧路径（即使它的 dir 与当前 home dir 不同也保留），
      // 没在的（新加图）落到当前 home dir。
      const cloudPath = oldBasenameToPath.get(fileName) ?? `${homeDir}${fileName}`
      expectedCloudFiles.add(cloudPath)
      manifestPaths.push(cloudPath)
      await CloudStorageService.uploadFile(photo, cloudPath)
    }

    // 在 home dir 下做孤儿清理：listFiles(homeDir) 出来的文件，凡是不在 expectedCloudFiles 里的就删。
    // 之前这一步用的是 buildNodePhotoDir(node.travelId, node.id)，对跨过 travel 的节点会指向错误目录。
    const cloudFiles = await CloudStorageService.listFiles(homeDir)
    for (let i = 0; i < cloudFiles.length; i++) {
      const relativeCloudPath = `${homeDir}${cloudFiles[i]}`
      if (!expectedCloudFiles.has(relativeCloudPath)) {
        await CloudStorageService.deleteFile(relativeCloudPath)
      }
    }

    // 上传完成后，把正确的 manifest 写回本地 DB；node.photoManifest 也即时更新。
    const manifest = JSON.stringify(manifestPaths)
    const nodeRepo = new MemoryNodeRepository()
    await nodeRepo.updatePhotoManifest(node.id, manifest)
    node.photoManifest = manifest
  }

  private static async syncNodePhotosForDownload(node: MemoryNode): Promise<void> {
    if ((node.deletedAt ?? 0) > 0) {
      hilog.info(DOMAIN, TAG, `[debug] skip photo download for deleted node cloudId=${node.cloudId ?? ''}`)
      return
    }
    const manifestPaths = SyncManager.parsePhotoManifest(node.photoManifest ?? '')
    const cloudDir = CloudStorageService.buildNodePhotoDir(node.travelId, node.id)
    if (manifestPaths.length <= 0) {
      hilog.info(
        DOMAIN,
        TAG,
        `[debug] empty manifest fallback listFiles, cloudId=${node.cloudId ?? ''}, nodeId=${node.id}, cloudDir=${cloudDir}, rawManifest=${node.photoManifest ?? ''}`
      )
    }
    const files: string[] = manifestPaths.length > 0 ? manifestPaths : await CloudStorageService.listFiles(cloudDir)
    hilog.info(
      DOMAIN,
      TAG,
      `[debug] syncNodePhotosForDownload cloudId=${node.cloudId ?? ''}, nodeId=${node.id}, cloudDir=${cloudDir}, manifestCount=${manifestPaths.length}, fileCount=${files.length}, files=${JSON.stringify(files)}`
    )
    const downloadedPhotos: string[] = []
    for (let i = 0; i < files.length; i++) {
      const manifestEntry: string = files[i]
      const cloudPath = manifestEntry.includes('/') ? manifestEntry : `${cloudDir}${manifestEntry}`
      hilog.info(
        DOMAIN,
        TAG,
        `[debug] download node photo cloudId=${node.cloudId ?? ''}, manifestEntry=${manifestEntry}, resolvedCloudPath=${cloudPath}`
      )
      const localPhotoPath = await CloudStorageService.downloadNodePhotoToSandbox(cloudPath)
      downloadedPhotos.push(localPhotoPath)
    }
    node.photos = downloadedPhotos
    if (manifestPaths.length > 0) {
      node.photoManifest = JSON.stringify(manifestPaths)
    }
    hilog.info(
      DOMAIN,
      TAG,
      `[debug] syncNodePhotosForDownload prepared photos cloudId=${node.cloudId ?? ''}, photos=${JSON.stringify(downloadedPhotos)}, photoManifest=${node.photoManifest ?? ''}`
    )
  }
}
