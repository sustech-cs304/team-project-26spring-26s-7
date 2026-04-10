import { logger } from '../utils/Logger'
import { RdbHelper } from '../data/RdbHelper'
import { TravelRepository } from '../data/TravelRepository'
import { MemoryNodeRepository } from '../data/MemoryNodeRepository'
import { AuthService } from '../auth'
import { CloudSyncService } from './CloudSyncService'
import type { SyncQueueItem } from '../service/types'

const TAG = 'SyncManager'

export class SyncManager {
  private static syncing: boolean = false

  static async triggerNow(): Promise<void> {
    if (SyncManager.syncing) {
      return
    }

    SyncManager.syncing = true
    try {
      const items = await RdbHelper.getInstance().getPendingSyncQueueItems()
      for (let i = 0; i < items.length; i++) {
        await SyncManager.handleItem(items[i])
      }
      await SyncManager.pullFromCloud()
    } finally {
      SyncManager.syncing = false
    }
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
        await CloudSyncService.deleteTravel(item.payload)
        await new TravelRepository().updateSyncMetadata(item.entityId, `travel_${item.entityId}`, 'synced', Date.now())
      } else if (item.entityType === 'memory_node' && item.operation === 'upsert') {
        const cloudId = await CloudSyncService.upsertMemoryNode(item.payload)
        await new MemoryNodeRepository().updateSyncMetadata(item.entityId, cloudId, 'synced', Date.now())
      } else if (item.entityType === 'memory_node' && item.operation === 'delete') {
        await CloudSyncService.deleteMemoryNode(item.payload)
        await new MemoryNodeRepository().updateSyncMetadata(item.entityId, `node_${item.entityId}`, 'synced', Date.now())
      } else {
        logger.warn(TAG, `Skip unsupported sync item: ${item.entityType}/${item.operation}`)
        return
      }
      await RdbHelper.getInstance().removeSyncItems(item.entityType, item.entityId)
    } catch (err) {
      logger.error(TAG, `Failed to sync item ${item.id}: ${JSON.stringify(err)}`)
    }
  }

  private static async pullFromCloud(): Promise<void> {
    const user = await AuthService.getCurrentUser()
    if (!user) {
      return
    }

    const travelRepo = new TravelRepository()
    const nodeRepo = new MemoryNodeRepository()
    const travels = await CloudSyncService.fetchTravels(user.uid)
    for (let i = 0; i < travels.length; i++) {
      const travel = travels[i]
      if ((travel.deletedAt ?? 0) > 0 && travel.cloudId) {
        await travelRepo.markDeletedByCloud(travel.cloudId)
      } else {
        await travelRepo.upsertFromCloud(travel)
      }
    }

    const nodes = await CloudSyncService.fetchMemoryNodes(user.uid)
    for (let i = 0; i < nodes.length; i++) {
      const node = nodes[i]
      if ((node.deletedAt ?? 0) > 0 && node.cloudId) {
        await nodeRepo.markDeletedByCloud(node.cloudId)
      } else {
        await nodeRepo.upsertFromCloud(node)
      }
    }
  }
}
