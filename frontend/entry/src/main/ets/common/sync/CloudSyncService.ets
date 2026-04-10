import { cloudCommon, cloudDatabase } from '@kit.CloudFoundationKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { BusinessError } from '@kit.BasicServicesKit'
import auth from '@hw-agconnect/auth'
import type { Trip, MemoryNode } from '../service/types'
import { CloudTravel } from './CloudTravel'
import { CloudMemoryNode } from './CloudMemoryNode'

const DOMAIN = 0x0000
const TAG = 'CloudSyncService'
const ZONE_NAME = 'TravelPinZone'

let initialized: boolean = false
let databaseZone: cloudDatabase.DatabaseZone | null = null

export class CloudSyncService {
  static async ensureReady(): Promise<boolean> {
    if (initialized && databaseZone !== null) {
      return true
    }

    try {
      cloudCommon.init({
        region: cloudCommon.CloudRegion.CHINA,
        authProvider: auth.getAuthProvider()
      })
      databaseZone = cloudDatabase.zone(ZONE_NAME)
      initialized = true
      hilog.info(DOMAIN, TAG, `Cloud database ready: ${ZONE_NAME}`)
      return true
    } catch (err) {
      const error = err as BusinessError
      hilog.error(DOMAIN, TAG, `Cloud database init failed: ${error.message}`)
      databaseZone = null
      initialized = false
      return false
    }
  }

  static reset(): void {
    databaseZone = null
    initialized = false
  }

  static async upsertTravel(payload: string): Promise<string> {
    const ready = await CloudSyncService.ensureReady()
    if (!ready || databaseZone === null) {
      throw new Error('云数据库未初始化')
    }

    const data = JSON.parse(payload) as Record<string, string | number>
    const cloudId = (data.cloudId as string) || `travel_${data.localId as string}`
    const travel = new CloudTravel()
    travel.cloudId = cloudId
    travel.ownerUid = data.ownerUid as string
    travel.name = data.name as string
    travel.coverPhotoObjectKey = data.coverPhoto as string
    travel.startDate = data.startDate as number
    travel.endDate = data.endDate as number
    travel.createdAt = (data.createdAt as number) || (data.updatedAt as number)
    travel.updatedAt = data.updatedAt as number
    travel.deletedAt = data.deletedAt as number
    travel.version = data.version as number
    await databaseZone.upsert(travel)
    return cloudId
  }

  static async deleteTravel(payload: string): Promise<void> {
    const ready = await CloudSyncService.ensureReady()
    if (!ready || databaseZone === null) {
      throw new Error('云数据库未初始化')
    }

    const data = JSON.parse(payload) as Record<string, string>
    const travel = new CloudTravel()
    travel.cloudId = `travel_${data.localId}`
    await databaseZone.delete(travel)
  }

  static async upsertMemoryNode(payload: string): Promise<string> {
    const ready = await CloudSyncService.ensureReady()
    if (!ready || databaseZone === null) {
      throw new Error('云数据库未初始化')
    }

    const data = JSON.parse(payload) as Record<string, string | number | string[]>
    const cloudId = (data.cloudId as string) || `node_${data.localId as string}`
    const node = new CloudMemoryNode()
    node.cloudId = cloudId
    node.ownerUid = data.ownerUid as string
    node.travelCloudId = `travel_${data.travelId as string}`
    node.title = data.title as string
    node.content = data.content as string
    node.latitude = data.latitude as number
    node.longitude = data.longitude as number
    node.poiName = data.poiName as string
    node.mood = data.mood as string
    node.tagsJson = JSON.stringify(data.tags ?? [])
    node.nodeOrder = (data.nodeOrder as number) || 0
    node.photoManifest = data.photoManifest as string
    node.createdAt = (data.createdAt as number) || (data.updatedAt as number)
    node.updatedAt = data.updatedAt as number
    node.deletedAt = data.deletedAt as number
    node.version = data.version as number
    await databaseZone.upsert(node)
    return cloudId
  }

  static async deleteMemoryNode(payload: string): Promise<void> {
    const ready = await CloudSyncService.ensureReady()
    if (!ready || databaseZone === null) {
      throw new Error('云数据库未初始化')
    }

    const data = JSON.parse(payload) as Record<string, string>
    const node = new CloudMemoryNode()
    node.cloudId = `node_${data.localId}`
    await databaseZone.delete(node)
  }

  static async fetchTravels(ownerUid: string): Promise<Trip[]> {
    const ready = await CloudSyncService.ensureReady()
    if (!ready || databaseZone === null) {
      return []
    }

    const condition = new cloudDatabase.DatabaseQuery(CloudTravel)
    condition.equalTo('ownerUid', ownerUid).orderByDesc('updatedAt')
    const records = await databaseZone.query(condition)
    const result: Trip[] = []
    for (let i = 0; i < records.length; i++) {
      const record = records[i]
      result.push({
        id: '0',
        name: record.name ?? '',
        description: '',
        coverPhoto: record.coverPhotoObjectKey ?? '',
        startDate: record.startDate ?? 0,
        endDate: record.endDate ?? 0,
        nodeIds: [],
        totalDistance: 0,
        createdAt: record.createdAt ?? 0,
        updatedAt: record.updatedAt ?? 0,
        ownerUid: record.ownerUid ?? '',
        cloudId: record.cloudId ?? '',
        syncStatus: 'synced',
        deletedAt: record.deletedAt ?? 0,
        lastSyncedAt: Date.now(),
        version: record.version ?? 1
      })
    }
    return result
  }

  static async fetchMemoryNodes(ownerUid: string): Promise<MemoryNode[]> {
    const ready = await CloudSyncService.ensureReady()
    if (!ready || databaseZone === null) {
      return []
    }

    const condition = new cloudDatabase.DatabaseQuery(CloudMemoryNode)
    condition.equalTo('ownerUid', ownerUid).orderByDesc('updatedAt')
    const records = await databaseZone.query(condition)
    const result: MemoryNode[] = []
    for (let i = 0; i < records.length; i++) {
      const record = records[i]
      result.push({
        id: '0',
        travelId: '0',
        title: record.title ?? '',
        content: record.content ?? '',
        latitude: record.latitude ?? 0,
        longitude: record.longitude ?? 0,
        poiName: record.poiName ?? '',
        photos: [],
        mood: record.mood ?? '',
        tags: record.tagsJson ? JSON.parse(record.tagsJson) as string[] : [],
        createdAt: record.createdAt ?? 0,
        updatedAt: record.updatedAt ?? 0,
        ownerUid: record.ownerUid ?? '',
        cloudId: record.cloudId ?? '',
        syncStatus: 'synced',
        deletedAt: record.deletedAt ?? 0,
        lastSyncedAt: Date.now(),
        version: record.version ?? 1,
        photoManifest: record.photoManifest ?? ''
      })
    }
    return result
  }
}
