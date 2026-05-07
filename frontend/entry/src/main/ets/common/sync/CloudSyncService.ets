import { cloudCommon, cloudDatabase } from '@kit.CloudFoundationKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { BusinessError } from '@kit.BasicServicesKit'
import auth from '@hw-agconnect/auth'
import type { Trip, MemoryNode } from '../service/types'
import { TravelSpecialValues } from '../utils/Constants'
import { CloudTravel } from './CloudTravel'
import { CloudMemoryNode } from './CloudMemoryNode'
import { CloudProfile } from './CloudProfile'

const DOMAIN = 0x0000
const TAG = 'CloudSyncService'
const ZONE_NAME = 'TravelPinZone'

let initialized: boolean = false
let databaseZone: cloudDatabase.DatabaseZone | null = null

interface TravelPayload {
  ownerUid: string
  localId: string
  cloudId: string
  name: string
  coverPhoto: string
  startDate: number
  endDate: number
  createdAt: number
  updatedAt: number
  deletedAt: number
  version: number
}

interface NodePayload {
  ownerUid: string
  localId: string
  cloudId: string
  travelId: string
  title: string
  content: string
  latitude: number
  longitude: number
  poiName: string
  photos: string[]
  mood: string
  tags: string[]
  nodeOrder: number
  createdAt: number
  updatedAt: number
  deletedAt: number
  version: number
  photoManifest: string
  visitedAt: number
}

interface ProfilePayload {
  ownerUid: string
  cloudId: string
  nickname: string
  bio: string
  avatarCloudPath: string
  version: number
  updatedAt: number
}

export class CloudSyncService {
  static async ensureReady(): Promise<boolean> {
    if (initialized && databaseZone !== null) {
      return true
    }

    try {
      cloudCommon.init({
        region: cloudCommon.CloudRegion.CHINA,
        authProvider: auth.getAuthProvider(),
        databaseOptions: { schema: 'schema.json' }
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

  static async buildTravelPayload(travel: Trip): Promise<string> {
    const payload: TravelPayload = {
      ownerUid: travel.ownerUid ?? '',
      localId: travel.id,
      cloudId: travel.cloudId && travel.cloudId.length > 0 ? travel.cloudId : `travel_${travel.id}`,
      name: travel.name,
      coverPhoto: travel.coverPhoto ?? '',
      startDate: travel.startDate,
      endDate: travel.endDate,
      createdAt: travel.createdAt,
      updatedAt: travel.updatedAt,
      deletedAt: travel.deletedAt ?? 0,
      version: travel.version ?? 1
    }
    return JSON.stringify(payload)
  }

  static async buildNodePayload(node: MemoryNode): Promise<string> {
    const payload: NodePayload = {
      ownerUid: node.ownerUid ?? '',
      localId: node.id,
      cloudId: node.cloudId && node.cloudId.length > 0 ? node.cloudId : `node_${node.id}`,
      travelId: node.travelId === TravelSpecialValues.UNCATEGORIZED_TRAVEL_ID ? '' : node.travelId,
      title: node.title,
      content: node.content,
      latitude: node.latitude,
      longitude: node.longitude,
      poiName: node.poiName,
      photos: node.photos,
      mood: node.mood,
      tags: node.tags,
      nodeOrder: node.nodeOrder ?? 0,
      createdAt: node.createdAt,
      updatedAt: node.updatedAt,
      deletedAt: node.deletedAt ?? 0,
      version: node.version ?? 1,
      photoManifest: node.photoManifest && node.photoManifest.length > 2 ? node.photoManifest : '[]',
      visitedAt: node.visitedAt ?? 0
    }
    return JSON.stringify(payload)
  }

  static async upsertTravel(payload: string): Promise<string> {
    const ready = await CloudSyncService.ensureReady()
    if (!ready || databaseZone === null) {
      throw new Error('云数据库未初始化')
    }

    const data = JSON.parse(payload) as TravelPayload
    const cloudId = data.cloudId || `travel_${data.localId}`
    const travel = new CloudTravel()
    travel.cloudId = cloudId
    travel.ownerUid = data.ownerUid
    travel.name = data.name
    travel.coverPhotoObjectKey = data.coverPhoto
    travel.startDate = data.startDate
    travel.endDate = data.endDate
    travel.createdAt = data.createdAt || data.updatedAt
    travel.updatedAt = data.updatedAt
    travel.deletedAt = data.deletedAt
    travel.version = data.version
    await databaseZone.upsert(travel)
    return cloudId
  }

  static async deleteTravel(payload: string): Promise<void> {
    const ready = await CloudSyncService.ensureReady()
    if (!ready || databaseZone === null) {
      throw new Error('云数据库未初始化')
    }

    const data = JSON.parse(payload) as TravelPayload
    const travel = new CloudTravel()
    travel.cloudId = data.cloudId || `travel_${data.localId}`
    travel.deletedAt = data.deletedAt
    travel.updatedAt = data.deletedAt
    travel.version = Math.max(data.version, 999999)
    await databaseZone.upsert(travel)
  }

  static async upsertMemoryNode(payload: string): Promise<string> {
    const ready = await CloudSyncService.ensureReady()
    if (!ready || databaseZone === null) {
      throw new Error('云数据库未初始化')
    }

    const data = JSON.parse(payload) as NodePayload
    const cloudId = data.cloudId || `node_${data.localId}`
    const node = new CloudMemoryNode()
    node.cloudId = cloudId
    node.ownerUid = data.ownerUid
    node.travelCloudId = data.travelId.length > 0 && data.travelId !== TravelSpecialValues.UNCATEGORIZED_TRAVEL_ID
      ? `travel_${data.travelId}`
      : ''
    node.title = data.title
    node.content = data.content
    node.latitude = data.latitude
    node.longitude = data.longitude
    node.poiName = data.poiName
    node.mood = data.mood
    node.tagsJson = JSON.stringify(data.tags)
    node.nodeOrder = data.nodeOrder
    node.photoManifest = data.photoManifest
    node.createdAt = data.createdAt || data.updatedAt
    node.updatedAt = data.updatedAt
    node.deletedAt = data.deletedAt
    node.version = data.version
    node.visitedAt = data.visitedAt
    await databaseZone.upsert(node)
    return cloudId
  }

  static async deleteMemoryNode(payload: string): Promise<void> {
    const ready = await CloudSyncService.ensureReady()
    if (!ready || databaseZone === null) {
      throw new Error('云数据库未初始化')
    }

    const data = JSON.parse(payload) as NodePayload
    const node = new CloudMemoryNode()
    node.cloudId = data.cloudId || `node_${data.localId}`
    node.deletedAt = data.deletedAt
    node.updatedAt = data.deletedAt
    node.version = Math.max(data.version, 999999)
    await databaseZone.upsert(node)
  }

  static async hardDeleteTravelByCloudId(cloudId: string): Promise<void> {
    const ready = await CloudSyncService.ensureReady()
    if (!ready || databaseZone === null || cloudId.length === 0) {
      return
    }

    const condition = new cloudDatabase.DatabaseQuery(CloudTravel)
    condition.equalTo('cloudId', cloudId)
    const records = await databaseZone.query(condition)
    hilog.info(DOMAIN, TAG, `Query travel delete target count=${records.length}, cloudId=${cloudId}`)
    if (records.length <= 0) {
      return
    }
    const deletedCount = await databaseZone.delete(records)
    hilog.info(DOMAIN, TAG, `Hard deleted travel count=${deletedCount}, cloudId=${cloudId}`)
  }

  static async hardDeleteMemoryNodeByCloudId(cloudId: string): Promise<void> {
    const ready = await CloudSyncService.ensureReady()
    if (!ready || databaseZone === null || cloudId.length === 0) {
      return
    }

    const condition = new cloudDatabase.DatabaseQuery(CloudMemoryNode)
    condition.equalTo('cloudId', cloudId)
    const records = await databaseZone.query(condition)
    hilog.info(DOMAIN, TAG, `Query memory node delete target count=${records.length}, cloudId=${cloudId}`)
    if (records.length <= 0) {
      return
    }
    const deletedCount = await databaseZone.delete(records)
    hilog.info(DOMAIN, TAG, `Hard deleted memory node count=${deletedCount}, cloudId=${cloudId}`)
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
      const trip: Trip = {
        id: '0',
        name: record.name ?? '',
        description: '',
        coverPhoto: record.coverPhotoObjectKey ?? '',
        isPublic: false,
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
      }
      result.push(trip)
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
      const node: MemoryNode = {
        id: '0',
        travelId: (record.travelCloudId && record.travelCloudId.length > 0)
          ? record.travelCloudId
          : TravelSpecialValues.UNCATEGORIZED_TRAVEL_ID,
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
        nodeOrder: record.nodeOrder ?? 0,
        ownerUid: record.ownerUid ?? '',
        cloudId: record.cloudId ?? '',
        syncStatus: 'synced',
        deletedAt: record.deletedAt ?? 0,
        lastSyncedAt: Date.now(),
        version: record.version ?? 1,
        photoManifest: record.photoManifest ?? '',
        visitedAt: record.visitedAt ?? 0
      }
      result.push(node)
    }
    return result
  }

  // ========== Profile ==========

  static async upsertProfile(payload: string): Promise<string> {
    const ready = await CloudSyncService.ensureReady()
    if (!ready || databaseZone === null) {
      throw new Error('云数据库未初始化')
    }

    const data = JSON.parse(payload) as ProfilePayload
    const cloudId = data.cloudId || `profile_${data.ownerUid}`
    hilog.info(DOMAIN, TAG, `upsertProfile: creating CloudProfile, cloudId=${cloudId}, className=${new CloudProfile().naturalbase_ClassName()}`)
    const profile = new CloudProfile()
    profile.cloudId = cloudId
    profile.ownerUid = data.ownerUid
    profile.nickname = data.nickname ?? undefined
    profile.bio = data.bio ?? undefined
    profile.avatarCloudPath = data.avatarCloudPath ?? undefined
    profile.version = data.version ?? undefined
    profile.updatedAt = data.updatedAt ?? undefined
    hilog.info(DOMAIN, TAG, `upsertProfile: fields assigned, bio="${profile.bio}", nickname="${profile.nickname}"`)
    try {
      await databaseZone.upsert(profile)
      hilog.info(DOMAIN, TAG, `upsertProfile done: cloudId=${cloudId}`)
    } catch (err) {
      const error = err as BusinessError
      hilog.error(DOMAIN, TAG, `upsertProfile upsert FAILED: code=${error.code}, message=${error.message}, name=${error.name}`)
      throw new Error(`个人资料保存失败(${error.code})，请重试`)
    }
    return cloudId
  }

  static async fetchProfile(ownerUid: string): Promise<CloudProfile | null> {
    const ready = await CloudSyncService.ensureReady()
    if (!ready || databaseZone === null) {
      return null
    }

    const condition = new cloudDatabase.DatabaseQuery(CloudProfile)
    condition.equalTo('ownerUid', ownerUid)
    const records = await databaseZone.query(condition)
    if (records.length <= 0) {
      hilog.info(DOMAIN, TAG, `fetchProfile: no record for ownerUid=${ownerUid}`)
      return null
    }
    hilog.info(DOMAIN, TAG, `fetchProfile: found record for ownerUid=${ownerUid}`)
    return records[0] as CloudProfile
  }

  static async hardDeleteProfileByOwnerUid(ownerUid: string): Promise<void> {
    const ready = await CloudSyncService.ensureReady()
    if (!ready || databaseZone === null || !ownerUid) {
      return
    }

    const condition = new cloudDatabase.DatabaseQuery(CloudProfile)
    condition.equalTo('ownerUid', ownerUid)
    const records = await databaseZone.query(condition)
    hilog.info(DOMAIN, TAG, `hardDeleteProfile: count=${records.length}, ownerUid=${ownerUid}`)
    if (records.length <= 0) {
      return
    }
    await databaseZone.delete(records)
    hilog.info(DOMAIN, TAG, `hardDeleteProfile: deleted count=${records.length}`)
  }
}
