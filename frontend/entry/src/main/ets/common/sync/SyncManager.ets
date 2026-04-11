import { logger } from '../utils/Logger'
import { RdbHelper } from '../data/RdbHelper'
import { TravelRepository } from '../data/TravelRepository'
import { MemoryNodeRepository } from '../data/MemoryNodeRepository'
import { AuthService, CloudStorageService } from '../auth'
import { CloudSyncService } from './CloudSyncService'
import type { SyncQueueItem, Trip, MemoryNode } from '../service/types'
import { PhotoPickerUtil } from '../utils/PhotoPickerUtil'

const TAG = 'SyncManager'

export class SyncManager {
  private static syncing: boolean = false

  static async pushLocalNow(): Promise<void> {
    if (SyncManager.syncing) {
      return
    }

    SyncManager.syncing = true
    try {
      const items = await RdbHelper.getInstance().getPendingSyncQueueItems()
      for (let i = 0; i < items.length; i++) {
        await SyncManager.handleItem(items[i])
      }
      await RdbHelper.getInstance().setSyncState('last_push_at', Date.now())
    } finally {
      SyncManager.syncing = false
    }
  }

  static async pullCloudNow(): Promise<void> {
    if (SyncManager.syncing) {
      return
    }

    SyncManager.syncing = true
    try {
      await SyncManager.replaceLocalWithCloud()
      await RdbHelper.getInstance().setSyncState('last_pull_at', Date.now())
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
      await SyncManager.syncAllLocalToCloud()
      await RdbHelper.getInstance().setSyncState('last_push_at', Date.now())
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
      await SyncManager.replaceLocalWithCloud()
      await RdbHelper.getInstance().setSyncState('last_pull_at', Date.now())
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
        const cloudId = await CloudSyncService.upsertTravel(item.payload)
        await new TravelRepository().updateSyncMetadata(item.entityId, cloudId, 'synced', Date.now())
      } else if (item.entityType === 'travel' && item.operation === 'delete') {
        const data = JSON.parse(item.payload) as Record<string, string | number>
        const localId = (data.localId as string) || item.entityId
        const cloudId = `travel_${localId}`
        await CloudStorageService.deleteDirectoryRecursively(CloudStorageService.buildTravelPhotoRoot(localId))
        await CloudSyncService.hardDeleteTravelByCloudId(cloudId)
        await new TravelRepository().updateSyncMetadata(item.entityId, cloudId, 'synced', Date.now())
      } else if (item.entityType === 'memory_node' && item.operation === 'upsert') {
        const cloudId = await CloudSyncService.upsertMemoryNode(item.payload)
        await new MemoryNodeRepository().updateSyncMetadata(item.entityId, cloudId, 'synced', Date.now())
      } else if (item.entityType === 'memory_node' && item.operation === 'delete') {
        const data = JSON.parse(item.payload) as Record<string, string | number | string[]>
        const localId = (data.localId as string) || item.entityId
        const travelId = (data.travelId as string) || ''
        const cloudId = `node_${localId}`
        const photoCloudPaths = Array.isArray(data.photoCloudPaths) ? data.photoCloudPaths as string[] : []
        for (let i = 0; i < photoCloudPaths.length; i++) {
          await CloudStorageService.deleteFile(photoCloudPaths[i])
        }
        if (travelId.length > 0) {
          await CloudStorageService.deleteDirectoryRecursively(CloudStorageService.buildNodePhotoDir(travelId, localId))
        }
        await CloudSyncService.hardDeleteMemoryNodeByCloudId(cloudId)
        await new MemoryNodeRepository().updateSyncMetadata(item.entityId, cloudId, 'synced', Date.now())
      } else {
        logger.warn(TAG, `Skip unsupported sync item: ${item.entityType}/${item.operation}`)
        return
      }
      await RdbHelper.getInstance().removeSyncItems(item.entityType, item.entityId)
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
      const cloudId = travel.cloudId && travel.cloudId.length > 0 ? travel.cloudId : `travel_${travel.id}`
      localTravelMap.set(cloudId, travel)
      const payload = await CloudSyncService.buildTravelPayload(travel)
      if ((travel.deletedAt ?? 0) > 0) {
        await CloudStorageService.deleteDirectoryRecursively(CloudStorageService.buildTravelPhotoRoot(travel.id))
        await CloudSyncService.hardDeleteTravelByCloudId(cloudId)
      } else {
        await CloudSyncService.upsertTravel(payload)
      }
      await travelRepo.updateSyncMetadata(travel.id, cloudId, 'synced', Date.now())
    }

    for (let i = 0; i < localNodes.length; i++) {
      const node = localNodes[i]
      const cloudId = node.cloudId && node.cloudId.length > 0 ? node.cloudId : `node_${node.id}`
      localNodeMap.set(cloudId, node)
      const payload = await CloudSyncService.buildNodePayload(node)
      if ((node.deletedAt ?? 0) > 0) {
        await CloudStorageService.deleteDirectoryRecursively(CloudStorageService.buildNodePhotoDir(node.travelId, node.id))
        await CloudSyncService.hardDeleteMemoryNodeByCloudId(cloudId)
      } else {
        await CloudSyncService.upsertMemoryNode(payload)
        await SyncManager.syncNodePhotosForUpload(node)
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
      const deletedTravel: Trip = {
        id: cloudId.replace('travel_', ''),
        name: cloudTravel.name,
        description: cloudTravel.description,
        coverPhoto: cloudTravel.coverPhoto,
        startDate: cloudTravel.startDate,
        endDate: cloudTravel.endDate,
        nodeIds: cloudTravel.nodeIds,
        totalDistance: cloudTravel.totalDistance,
        createdAt: cloudTravel.createdAt,
        updatedAt: Date.now(),
        ownerUid: cloudTravel.ownerUid ?? user.uid,
        cloudId: cloudId,
        syncStatus: 'synced',
        deletedAt: Date.now(),
        lastSyncedAt: Date.now(),
        version: Math.max(cloudTravel.version ?? 1, 999999)
      }
      await CloudStorageService.deleteDirectoryRecursively(CloudStorageService.buildTravelPhotoRoot(deletedTravel.id))
      await CloudSyncService.hardDeleteTravelByCloudId(cloudId)
    }

    for (let i = 0; i < cloudNodes.length; i++) {
      const cloudNode = cloudNodes[i]
      const cloudId = cloudNode.cloudId ?? ''
      cloudNodeIds.add(cloudId)
      if (!cloudId || localNodeMap.has(cloudId)) {
        continue
      }
      const deletedNode: MemoryNode = {
        id: cloudId.replace('node_', ''),
        travelId: cloudNode.travelId,
        title: cloudNode.title,
        content: cloudNode.content,
        latitude: cloudNode.latitude,
        longitude: cloudNode.longitude,
        poiName: cloudNode.poiName,
        photos: cloudNode.photos,
        mood: cloudNode.mood,
        tags: cloudNode.tags,
        createdAt: cloudNode.createdAt,
        updatedAt: Date.now(),
        nodeOrder: cloudNode.nodeOrder ?? 0,
        ownerUid: cloudNode.ownerUid ?? user.uid,
        cloudId: cloudId,
        syncStatus: 'synced',
        deletedAt: Date.now(),
        lastSyncedAt: Date.now(),
        version: Math.max(cloudNode.version ?? 1, 999999),
        photoManifest: cloudNode.photoManifest ?? JSON.stringify(cloudNode.photos)
      }
      await CloudStorageService.deleteDirectoryRecursively(CloudStorageService.buildNodePhotoDir(deletedNode.travelId.replace('travel_', ''), deletedNode.id))
      await CloudSyncService.hardDeleteMemoryNodeByCloudId(cloudId)
    }

    for (let i = 0; i < localNodes.length; i++) {
      const node = localNodes[i]
      if ((node.deletedAt ?? 0) > 0) {
        continue
      }
      const cloudId = node.cloudId && node.cloudId.length > 0 ? node.cloudId : `node_${node.id}`
      if (!cloudNodeIds.has(cloudId)) {
        await SyncManager.syncNodePhotosForUpload(node)
      }
    }
  }

  private static async replaceLocalWithCloud(): Promise<void> {
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
      const cloudId = localTravel.cloudId && localTravel.cloudId.length > 0 ? localTravel.cloudId : `travel_${localTravel.id}`
      if (!activeCloudTravelIds.has(cloudId)) {
        await travelRepo.deleteTravel(localTravel.id)
        await travelRepo.updateSyncMetadata(localTravel.id, cloudId, 'synced', Date.now())
      }
    }

    for (let i = 0; i < cloudNodes.length; i++) {
      const node = cloudNodes[i]
      const travelCloudId = node.travelId
      if (!travelCloudId) {
        continue
      }
      const localTravelId = await travelRepo.findLocalIdByCloudId(travelCloudId)
      if (!localTravelId || !node.cloudId) {
        continue
      }
      node.travelId = localTravelId
      if ((node.deletedAt ?? 0) > 0) {
        const localNodeId = node.cloudId ? await nodeRepo.findLocalIdByCloudId(node.cloudId) : null
        if (localNodeId) {
          await nodeRepo.deleteNode(localNodeId)
        }
        continue
      }
      activeCloudNodeIds.add(node.cloudId)
      await nodeRepo.upsertFromCloud(node)
      await SyncManager.syncNodePhotosForDownload(node)
    }

    for (let i = 0; i < localNodes.length; i++) {
      const localNode = localNodes[i]
      const cloudId = localNode.cloudId && localNode.cloudId.length > 0 ? localNode.cloudId : `node_${localNode.id}`
      if (!activeCloudNodeIds.has(cloudId)) {
        await nodeRepo.deleteNode(localNode.id)
        await nodeRepo.updateSyncMetadata(localNode.id, cloudId, 'synced', Date.now())
      }
    }
  }

  private static async syncNodePhotosForUpload(node: MemoryNode): Promise<void> {
    if ((node.deletedAt ?? 0) > 0) {
      return
    }
    const expectedCloudFiles: Set<string> = new Set<string>()
    for (let i = 0; i < node.photos.length; i++) {
      const photo = node.photos[i]
      if (!PhotoPickerUtil.photoExists(photo)) {
        continue
      }
      const cloudPath = CloudStorageService.buildNodePhotoPath(node.travelId, node.id, photo)
      expectedCloudFiles.add(cloudPath)
      await CloudStorageService.uploadFile(photo, cloudPath)
    }

    const cloudFiles = await CloudStorageService.listFiles(CloudStorageService.buildNodePhotoDir(node.travelId, node.id))
    for (let i = 0; i < cloudFiles.length; i++) {
      const relativeCloudPath = `${CloudStorageService.buildNodePhotoDir(node.travelId, node.id)}${cloudFiles[i]}`
      if (!expectedCloudFiles.has(relativeCloudPath)) {
        await CloudStorageService.deleteFile(relativeCloudPath)
      }
    }
  }

  private static async syncNodePhotosForDownload(node: MemoryNode): Promise<void> {
    if ((node.deletedAt ?? 0) > 0) {
      return
    }
    const cloudDir = CloudStorageService.buildNodePhotoDir(node.travelId, node.id)
    const files = await CloudStorageService.listFiles(cloudDir)
    const downloadedPhotos: string[] = []
    for (let i = 0; i < files.length; i++) {
      const fileName: string = files[i]
      const cloudPath = `${cloudDir}${fileName}`
      const localRelativePath = `downloaded/${node.travelId}/${node.id}/${fileName}`
      await CloudStorageService.downloadFile(cloudPath, localRelativePath)
      downloadedPhotos.push(`file://${CloudStorageService.normalizeCachePath(localRelativePath)}`)
    }
    node.photos = downloadedPhotos
    node.photoManifest = JSON.stringify(downloadedPhotos)
    await new MemoryNodeRepository().upsertFromCloud(node)
  }
}
