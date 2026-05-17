import { cloudCommon, cloudDatabase } from '@kit.CloudFoundationKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { BusinessError } from '@kit.BasicServicesKit'
import auth from '@hw-agconnect/auth'
import type { Trip, MemoryNode } from '../service/types'
import { TravelSpecialValues } from '../utils/Constants'
import { CloudTravel } from './CloudTravel'
import { CloudMemoryNode } from './CloudMemoryNode'
import { CloudProfile } from './CloudProfile'
import { TravelRepository } from '../data/TravelRepository'

const DOMAIN = 0x0000
const TAG = 'CloudSyncService'
const ZONE_NAME = 'ItsMapPinZone'
const MAX_CLOUD_ID_PROBE_COUNT = 10000

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
  isPublic: number
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
  /**
   * 把 cloud_id 用 ownerUid 隔开，避免不同设备/账号的 local id 撞车。
   * 旧格式 `travel_<localId>` / `node_<localId>` 已不安全：两个用户的 local id=5
   * 会 upsert 到同一行，互相覆盖。新格式 `travel_<uid>_<localId>` / `node_<uid>_<localId>`
   * 内嵌 uid 后天然不会冲突。
   * 已有 cloud_id 的实体保留旧值（迁移成本），但下面的 hardDelete*ByCloudId 都会再加
   * ownerUid 过滤条件，即使 cloud_id 历史撞车也只动自己的行。
   */
  static buildTravelCloudId(ownerUid: string, localId: string): string {
    return ownerUid && ownerUid.length > 0 ? `travel_${ownerUid}_${localId}` : `travel_${localId}`
  }

  static buildNodeCloudId(ownerUid: string, localId: string): string {
    return ownerUid && ownerUid.length > 0 ? `node_${ownerUid}_${localId}` : `node_${localId}`
  }

  private static nextCloudId(candidate: string): string {
    const lastUnderscore = candidate.lastIndexOf('_')
    if (lastUnderscore < 0 || lastUnderscore >= candidate.length - 1) {
      return `${candidate}_1`
    }

    const suffix = candidate.substring(lastUnderscore + 1)
    const suffixNumber = Number(suffix)
    if (!Number.isInteger(suffixNumber)) {
      return `${candidate}_1`
    }

    return `${candidate.substring(0, lastUnderscore + 1)}${suffixNumber + 1}`
  }

  private static async travelCloudIdExists(cloudId: string): Promise<boolean> {
    if (databaseZone === null || cloudId.length === 0) {
      return false
    }
    const condition = new cloudDatabase.DatabaseQuery(CloudTravel)
    condition.equalTo('cloudId', cloudId)
    const records = await databaseZone.query(condition)
    return records.length > 0
  }

  private static async nodeCloudIdExists(cloudId: string): Promise<boolean> {
    if (databaseZone === null || cloudId.length === 0) {
      return false
    }
    const condition = new cloudDatabase.DatabaseQuery(CloudMemoryNode)
    condition.equalTo('cloudId', cloudId)
    const records = await databaseZone.query(condition)
    return records.length > 0
  }

  private static async resolveAvailableTravelCloudId(data: TravelPayload): Promise<string> {
    if (data.cloudId && data.cloudId.length > 0) {
      return data.cloudId
    }

    let cloudId = CloudSyncService.buildTravelCloudId(data.ownerUid, data.localId)
    for (let i = 0; i < MAX_CLOUD_ID_PROBE_COUNT; i++) {
      if (!(await CloudSyncService.travelCloudIdExists(cloudId))) {
        return cloudId
      }
      const nextCloudId = CloudSyncService.nextCloudId(cloudId)
      hilog.warn(DOMAIN, TAG, `[resolveAvailableTravelCloudId] cloudId collision: ${cloudId} -> ${nextCloudId}`)
      cloudId = nextCloudId
    }
    throw new Error(`No available travel cloudId after ${MAX_CLOUD_ID_PROBE_COUNT} probes`)
  }

  private static async resolveAvailableNodeCloudId(data: NodePayload): Promise<string> {
    if (data.cloudId && data.cloudId.length > 0) {
      return data.cloudId
    }

    let cloudId = CloudSyncService.buildNodeCloudId(data.ownerUid, data.localId)
    for (let i = 0; i < MAX_CLOUD_ID_PROBE_COUNT; i++) {
      if (!(await CloudSyncService.nodeCloudIdExists(cloudId))) {
        return cloudId
      }
      const nextCloudId = CloudSyncService.nextCloudId(cloudId)
      hilog.warn(DOMAIN, TAG, `[resolveAvailableNodeCloudId] cloudId collision: ${cloudId} -> ${nextCloudId}`)
      cloudId = nextCloudId
    }
    throw new Error(`No available memory node cloudId after ${MAX_CLOUD_ID_PROBE_COUNT} probes`)
  }

  /**
   * 从 cloud_id 反推原始 localId（用于构造云端存储路径）：
   *  - 旧格式 'travel_5' → '5'
   *  - 新格式 'travel_<uid>_5' → '5'（取最后一个下划线之后的部分）
   * 注意：跨设备同步时 localId 可能与当前设备的 RDB id 不一致，
   *       但由于云端存储路径是 `users/<uid>/...` 用户隔离的，最坏情况只会动到自己用户下的错误目录。
   */
  static extractLocalIdFromCloudId(cloudId: string): string {
    const lastUnderscore = cloudId.lastIndexOf('_')
    if (lastUnderscore < 0 || lastUnderscore >= cloudId.length - 1) {
      return cloudId
    }
    return cloudId.substring(lastUnderscore + 1)
  }

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
    hilog.info(DOMAIN, TAG, `[buildTravelPayload] travel.id=${travel.id}, isPublic=${travel.isPublic}`)
    const ownerUid = travel.ownerUid ?? ''
    const payload: TravelPayload = {
      ownerUid: ownerUid,
      localId: travel.id,
      cloudId: travel.cloudId && travel.cloudId.length > 0
        ? travel.cloudId
        : CloudSyncService.buildTravelCloudId(ownerUid, travel.id),
      name: travel.name,
      coverPhoto: travel.coverPhoto ?? '',
      startDate: travel.startDate,
      endDate: travel.endDate,
      createdAt: travel.createdAt,
      updatedAt: travel.updatedAt,
      deletedAt: travel.deletedAt ?? 0,
      version: travel.version ?? 1,
      isPublic: travel.isPublic ? 1 : 0
    }
    hilog.info(DOMAIN, TAG, `[buildTravelPayload] payload.isPublic=${payload.isPublic}, id=${travel.id}`)
    return JSON.stringify(payload)
  }

  static async buildNodePayload(node: MemoryNode): Promise<string> {
    const ownerUid = node.ownerUid ?? ''
    const payload: NodePayload = {
      ownerUid: ownerUid,
      localId: node.id,
      cloudId: node.cloudId && node.cloudId.length > 0
        ? node.cloudId
        : CloudSyncService.buildNodeCloudId(ownerUid, node.id),
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
    const cloudId = await CloudSyncService.resolveAvailableTravelCloudId(data)
    hilog.info(DOMAIN, TAG, `[upsertTravel] isPublic=${data.isPublic}, cloudId=${cloudId}, name=${data.name}`)
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
    travel.isPublic = data.isPublic
    hilog.info(DOMAIN, TAG, `[upsertTravel] travel.isPublic assigned=${travel.isPublic}`)
    await databaseZone.upsert(travel)
    hilog.info(DOMAIN, TAG, `[upsertTravel] upsert completed for cloudId=${cloudId}`)
    return cloudId
  }

  static async deleteTravel(payload: string): Promise<void> {
    const ready = await CloudSyncService.ensureReady()
    if (!ready || databaseZone === null) {
      throw new Error('云数据库未初始化')
    }

    const data = JSON.parse(payload) as TravelPayload
    const travel = new CloudTravel()
    travel.cloudId = data.cloudId || CloudSyncService.buildTravelCloudId(data.ownerUid, data.localId)
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
    const cloudId = await CloudSyncService.resolveAvailableNodeCloudId(data)
    const node = new CloudMemoryNode()
    node.cloudId = cloudId
    node.ownerUid = data.ownerUid
    // 父 travel 的外键引用：优先用本地 DB 里父 travel 已存在的 cloud_id，
    // 这样旧数据（cloud_id='travel_<id>'）和新数据（cloud_id='travel_<uid>_<id>'）能共存，
    // 不会因 FK 不匹配导致 replaceLocalWithCloud 找不到 localTravelId 而跳过节点。
    if (data.travelId.length > 0 && data.travelId !== TravelSpecialValues.UNCATEGORIZED_TRAVEL_ID) {
      const parentTravel = await new TravelRepository().getTravelById(data.travelId)
      if (parentTravel && parentTravel.cloudId && parentTravel.cloudId.length > 0) {
        node.travelCloudId = parentTravel.cloudId
      } else {
        node.travelCloudId = CloudSyncService.buildTravelCloudId(data.ownerUid, data.travelId)
      }
    } else {
      node.travelCloudId = ''
    }
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
    node.cloudId = data.cloudId || CloudSyncService.buildNodeCloudId(data.ownerUid, data.localId)
    node.deletedAt = data.deletedAt
    node.updatedAt = data.deletedAt
    node.version = Math.max(data.version, 999999)
    await databaseZone.upsert(node)
  }

  /**
   * 必须传 ownerUid：硬删除前再加一条 ownerUid 过滤，
   * 防止历史 cloud_id 撞车把别的账号的行也删掉。
   */
  static async hardDeleteTravelByCloudId(cloudId: string, ownerUid: string): Promise<void> {
    const ready = await CloudSyncService.ensureReady()
    if (!ready || databaseZone === null || cloudId.length === 0 || ownerUid.length === 0) {
      hilog.warn(DOMAIN, TAG, `hardDeleteTravelByCloudId skipped: cloudId=${cloudId}, ownerUid=${ownerUid}`)
      return
    }

    const condition = new cloudDatabase.DatabaseQuery(CloudTravel)
    condition.equalTo('cloudId', cloudId).and().equalTo('ownerUid', ownerUid)
    const records = await databaseZone.query(condition)
    hilog.info(DOMAIN, TAG, `Query travel delete target count=${records.length}, cloudId=${cloudId}, ownerUid=${ownerUid}`)
    if (records.length <= 0) {
      return
    }
    const deletedCount = await databaseZone.delete(records)
    hilog.info(DOMAIN, TAG, `Hard deleted travel count=${deletedCount}, cloudId=${cloudId}`)
  }

  static async hardDeleteMemoryNodeByCloudId(cloudId: string, ownerUid: string): Promise<void> {
    const ready = await CloudSyncService.ensureReady()
    if (!ready || databaseZone === null || cloudId.length === 0 || ownerUid.length === 0) {
      hilog.warn(DOMAIN, TAG, `hardDeleteMemoryNodeByCloudId skipped: cloudId=${cloudId}, ownerUid=${ownerUid}`)
      return
    }

    const condition = new cloudDatabase.DatabaseQuery(CloudMemoryNode)
    condition.equalTo('cloudId', cloudId).and().equalTo('ownerUid', ownerUid)
    const records = await databaseZone.query(condition)
    hilog.info(DOMAIN, TAG, `Query memory node delete target count=${records.length}, cloudId=${cloudId}, ownerUid=${ownerUid}`)
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
        isPublic: (record.isPublic ?? 0) === 1,
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
