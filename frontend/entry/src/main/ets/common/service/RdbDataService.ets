/*
 * Copyright (c) 2024 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { logger } from '../utils/Logger';
import { PhotoPickerUtil } from '../utils/PhotoPickerUtil';
import { TravelSpecialValues } from '../utils/Constants';
import { AuthService, CloudStorageService } from '../auth';
import { SyncManager } from '../sync/SyncManager';
import { RdbHelper } from '../data/RdbHelper';
import { TravelRepository } from '../data/TravelRepository';
import { MemoryNodeRepository } from '../data/MemoryNodeRepository';
import type { IDataService, CreateTravelInput, UpdateTravelInput, CreateNodeInput, UpdateNodeInput } from './IDataService';
import type { Trip, MemoryNode, ReplayTripPreferences, SyncStatus } from './types';
import type { CreateTravelInput as RepoCreateTravelInput, UpdateTravelInput as RepoUpdateTravelInput } from '../data/TravelRepository';
import type { CreateNodeInput as RepoCreateNodeInput, UpdateNodeInput as RepoUpdateNodeInput, SoftDeleteResult } from '../data/MemoryNodeRepository';

const TAG = 'RdbDataService';

/**
 * 基于 RDB 数据库的数据服务实现
 * 实现 IDataService 接口，桥接 Service Layer 和 Repository Layer
 */
export class RdbDataService implements IDataService {
  private travelRepo: TravelRepository;
  private nodeRepo: MemoryNodeRepository;
  private rdbHelper: RdbHelper;

  constructor() {
    this.travelRepo = new TravelRepository();
    this.nodeRepo = new MemoryNodeRepository();
    this.rdbHelper = RdbHelper.getInstance();
  }

  private getOwnerUidFromPayload(payload: string): string {
    try {
      const parsed = JSON.parse(payload) as Record<string, string | number | boolean | string[]>;
      const ownerUid = parsed.ownerUid;
      return typeof ownerUid === 'string' ? ownerUid : '';
    } catch (_) {
      return '';
    }
  }

  private async enqueueSync(entityType: string, entityId: string, operation: string, payload: string): Promise<void> {
    const ownerUid = this.getOwnerUidFromPayload(payload);
    // 在线时入队后立即 push 到云端（实现"在线即时同步"）。
    // 这条之前曾经是 Bug 1 的引信：离线 deleteTravel 把"删 travel + 重 upsert 子节点"
    // 一起塞进队列，重联网后只要任何一次写操作触发 enqueueSync 就会把整队列 drain，
    // 而当时 handleItem('travel','delete') 会无脑 deleteDirectoryRecursively(travels/<T>/)
    // 把孩子节点的图也一起干掉。Bug 1 的修复在 SyncManager 里：把那条 wipe 改成只删
    // 元数据 + 让 photoManifest 在子节点跨 travel 时保留旧路径。这里 auto-push 本身没问题。
    await this.rdbHelper.removeSyncItems(entityType, entityId, ownerUid);
    await this.rdbHelper.enqueueSyncItem(ownerUid, entityType, entityId, operation, payload);
    const isOnline = (AppStorage.get('networkOnline') as boolean) ?? false;
    if (isOnline) {
      void SyncManager.pushLocalNow();
    }
  }

  private async enqueueSyncSilently(entityType: string, entityId: string, operation: string, payload: string): Promise<void> {
    const ownerUid = this.getOwnerUidFromPayload(payload);
    // 仅入队，不触发 push。用于批量操作（deleteTravel 内对 affected 子节点的 upsert 等），
    // 在所有相关项都进队列后由调用方统一 push 一次，避免半途同步导致顺序错乱。
    await this.rdbHelper.removeSyncItems(entityType, entityId, ownerUid);
    await this.rdbHelper.enqueueSyncItem(ownerUid, entityType, entityId, operation, payload);
  }

  async getSyncStatus(): Promise<SyncStatus> {
    const user = await AuthService.getCurrentUser();
    const ownerUid = user?.uid ?? '';
    const pendingItems = ownerUid.length > 0 ? await this.rdbHelper.getPendingSyncQueueItems(ownerUid) : [];
    const lastPushTime = await this.rdbHelper.getSyncState('last_push_at', ownerUid);
    const lastPullTime = await this.rdbHelper.getSyncState('last_pull_at', ownerUid);
    const status: SyncStatus = {
      lastSyncTime: Math.max(lastPushTime, lastPullTime),
      lastPushTime: lastPushTime,
      lastPullTime: lastPullTime,
      pendingCount: pendingItems.length,
      isSyncing: SyncManager.isSyncing()
    }
    return status;
  }

  /**
   * 旧版 buildPhotoManifest：直接按 (travelId, nodeId, photos) 拼路径，
   * 仅在 createNode 这种"还没有 manifest 的全新节点"场景下用，
   * 其它情况都走 buildPhotoManifestForNode（基于 home dir，不会被跨 travel 污染）。
   */
  private buildPhotoManifest(travelId: string, nodeId: string, photos: string[]): string {
    const cloudPaths: string[] = [];
    for (let i = 0; i < photos.length; i++) {
      cloudPaths.push(CloudStorageService.buildNodePhotoPath(travelId, nodeId, photos[i]));
    }
    return JSON.stringify(cloudPaths);
  }

  /**
   * 用 home-dir 模型给一个节点生成 photoManifest：
   *  - kept 照片（basename 在旧 manifest 中能找到）：保留旧路径，绝不换 dir。
   *  - added 照片：用 home dir + basename 拼出新路径。
   * 这样跨 travel 时旧图保留原 dir、新图也跟着 home dir 走（home 由旧 manifest 决定，
   * 旧 manifest 为空才退到当前 travelId）—— 整套规则保证 manifest 永远指向云端实际位置。
   */
  private buildPhotoManifestForNode(node: MemoryNode, photos: string[]): string {
    const homeDir = CloudStorageService.getNodeHomeDir(node.photoManifest ?? '', node.travelId, node.id);
    const oldPaths = this.parsePhotoManifest(node.photoManifest);
    const basenameToOldPath = new Map<string, string>();
    for (let i = 0; i < oldPaths.length; i++) {
      const p = oldPaths[i];
      const slashIdx = p.lastIndexOf('/');
      if (slashIdx >= 0) {
        basenameToOldPath.set(p.substring(slashIdx + 1), p);
      }
    }
    const newPaths: string[] = [];
    for (let i = 0; i < photos.length; i++) {
      const fileName = CloudStorageService.getFileNameFromPath(photos[i]);
      const reused = basenameToOldPath.get(fileName);
      newPaths.push(reused ?? `${homeDir}${fileName}`);
    }
    return JSON.stringify(newPaths);
  }

  /**
   * fire-and-forget：把指定的本地照片上传到节点的 home dir（不一定是当前 travel）。
   * 跨 travel 移动后新增的图也仍然落到 home dir，保证 manifest 中"path 前缀"始终是
   * 该节点首次上传时的位置 —— 这是 Bug 1 的修复关键点之一：路径不动则不会有迁移失败。
   */
  private syncNodePhotosToCloud(node: MemoryNode, photos: string[]): void {
    if (photos.length === 0) {
      return;
    }
    void this.uploadNodePhotosToCloud(node, photos);
  }

  private async uploadNodePhotosToCloud(node: MemoryNode, photos: string[]): Promise<void> {
    const homeDir = CloudStorageService.getNodeHomeDir(node.photoManifest ?? '', node.travelId, node.id);
    for (const photo of photos) {
      try {
        const cloudPath = CloudStorageService.buildNodePhotoPathInHomeDir(homeDir, photo);
        await CloudStorageService.uploadFile(photo, cloudPath);
      } catch (err) {
        logger.error(TAG, `Upload node photo failed: ${(err as Error).message}`);
      }
    }
  }

  /**
   * fire-and-forget：从云端删除被 updateNode 移除的若干张照片。
   * 优先按 oldManifest 里记录的真实路径删（如果有），否则用 home dir 拼路径。
   */
  private syncDeletedNodePhotosToCloud(node: MemoryNode, photos: string[]): void {
    if (photos.length === 0) {
      return;
    }
    const oldPaths = this.parsePhotoManifest(node.photoManifest);
    const basenameToOldPath = new Map<string, string>();
    for (let i = 0; i < oldPaths.length; i++) {
      const p = oldPaths[i];
      const slashIdx = p.lastIndexOf('/');
      if (slashIdx >= 0) {
        basenameToOldPath.set(p.substring(slashIdx + 1), p);
      }
    }
    const homeDir = CloudStorageService.getNodeHomeDir(node.photoManifest ?? '', node.travelId, node.id);
    for (const photo of photos) {
      try {
        const fileName = CloudStorageService.getFileNameFromPath(photo);
        const cloudPath = basenameToOldPath.get(fileName) ?? `${homeDir}${fileName}`;
        void CloudStorageService.deleteFile(cloudPath);
      } catch (_) {}
    }
  }

  private getRemovedPhotos(oldPhotos: string[], newPhotos: string[]): string[] {
    return oldPhotos.filter((photo: string) => !newPhotos.includes(photo));
  }

  private getAddedPhotos(oldPhotos: string[], newPhotos: string[]): string[] {
    return newPhotos.filter((photo: string) => !oldPhotos.includes(photo));
  }

  /**
   * 解析节点的 photoManifest（JSON 字符串），返回云端绝对路径数组。
   * 用于 deleteNode / deleteTravel 等场景下确定"实际要删/要保留的云端路径"——
   * 由于节点可能跨过 travel，photo_manifest 才是云端实际路径的真相，
   * 不能再用 buildNodePhotoPath(currentTravelId, ...) 反推。
   */
  private parsePhotoManifest(manifest: string | undefined): string[] {
    if (!manifest || manifest.length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(manifest) as Object;
      if (!Array.isArray(parsed)) {
        return [];
      }
      const result: string[] = [];
      for (let i = 0; i < parsed.length; i++) {
        const item = parsed[i] as string;
        if (typeof item === 'string' && item.length > 0) {
          result.push(item);
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  private calculateDistanceBetweenPoints(
    startLatitude: number,
    startLongitude: number,
    endLatitude: number,
    endLongitude: number
  ): number {
    const toRadians = (value: number): number => value * Math.PI / 180;
    const earthRadiusKm = 6371;
    const deltaLatitude = toRadians(endLatitude - startLatitude);
    const deltaLongitude = toRadians(endLongitude - startLongitude);
    const startLatRadians = toRadians(startLatitude);
    const endLatRadians = toRadians(endLatitude);
    const a = Math.sin(deltaLatitude / 2) * Math.sin(deltaLatitude / 2) +
      Math.cos(startLatRadians) * Math.cos(endLatRadians) *
      Math.sin(deltaLongitude / 2) * Math.sin(deltaLongitude / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  private calculateTotalDistance(nodes: MemoryNode[]): number {
    if (nodes.length < 2) {
      return 0;
    }

    let distance = 0;
    for (let i = 1; i < nodes.length; i++) {
      distance += this.calculateDistanceBetweenPoints(
        nodes[i - 1].latitude,
        nodes[i - 1].longitude,
        nodes[i].latitude,
        nodes[i].longitude
      );
    }
    return Math.round(distance * 10) / 10;
  }

  // ==================== Travel 相关 ====================

  async getAllTravels(): Promise<Trip[]> {
    try {
      const trips = await this.travelRepo.getAllTravels();
      // 为每个旅行填充 nodeIds
      for (let i = 0; i < trips.length; i++) {
        const nodes = await this.nodeRepo.getNodesByTravelId(trips[i].id);
        const nodeIds: string[] = [];
        for (const node of nodes) {
          nodeIds.push(node.id);
        }
        trips[i] = {
          id: trips[i].id,
          name: trips[i].name,
          description: trips[i].description,
          coverPhoto: trips[i].coverPhoto,
          isPublic: trips[i].isPublic,
          startDate: trips[i].startDate,
          endDate: trips[i].endDate,
          nodeIds: nodeIds,
          totalDistance: this.calculateTotalDistance(nodes),
          createdAt: trips[i].createdAt,
          updatedAt: trips[i].updatedAt,
          ownerUid: trips[i].ownerUid,
          cloudId: trips[i].cloudId,
        syncStatus: trips[i].syncStatus,
        deletedAt: trips[i].deletedAt,
        lastSyncedAt: trips[i].lastSyncedAt,
        version: trips[i].version,
        replayStyleKitId: trips[i].replayStyleKitId,
        replayBgmId: trips[i].replayBgmId,
        replayFilterId: trips[i].replayFilterId,
        replayTransitionType: trips[i].replayTransitionType,
        replayEnableRipple: trips[i].replayEnableRipple,
        replayEnableRouteAnimation: trips[i].replayEnableRouteAnimation,
        replayEnableBlurOverlay: trips[i].replayEnableBlurOverlay
      };
      }
      return trips;
    } catch (err) {
      logger.error(TAG, `getAllTravels failed: ${JSON.stringify(err)}`);
      return [];
    }
  }

  async getTravelById(travelId: string): Promise<Trip | null> {
    try {
      const trip = await this.travelRepo.getTravelById(travelId);
      if (!trip) {
        return null;
      }
      const nodes = await this.nodeRepo.getNodesByTravelId(travelId);
      const nodeIds: string[] = [];
      for (const node of nodes) {
        nodeIds.push(node.id);
      }
      const result: Trip = {
        id: trip.id,
        name: trip.name,
        description: trip.description,
        coverPhoto: trip.coverPhoto,
        isPublic: trip.isPublic,
        startDate: trip.startDate,
        endDate: trip.endDate,
        nodeIds: nodeIds,
        totalDistance: this.calculateTotalDistance(nodes),
        createdAt: trip.createdAt,
        updatedAt: trip.updatedAt,
        ownerUid: trip.ownerUid,
        cloudId: trip.cloudId,
        syncStatus: trip.syncStatus,
        deletedAt: trip.deletedAt,
        lastSyncedAt: trip.lastSyncedAt,
        version: trip.version,
        replayStyleKitId: trip.replayStyleKitId,
        replayBgmId: trip.replayBgmId,
        replayFilterId: trip.replayFilterId,
        replayTransitionType: trip.replayTransitionType,
        replayEnableRipple: trip.replayEnableRipple,
        replayEnableRouteAnimation: trip.replayEnableRouteAnimation,
        replayEnableBlurOverlay: trip.replayEnableBlurOverlay
      };
      return result;
    } catch (err) {
      logger.error(TAG, `getTravelById failed: ${JSON.stringify(err)}`);
      return null;
    }
  }

  async createTravel(travel: CreateTravelInput): Promise<Trip> {
    const repoInput: RepoCreateTravelInput = {
      name: travel.name,
      coverImageUri: travel.coverPhoto,
      isPublic: travel.isPublic ?? false,
      startDate: travel.startDate,
      endDate: travel.endDate,
      replayStyleKitId: travel.replayStyleKitId,
      replayBgmId: travel.replayBgmId,
      replayFilterId: travel.replayFilterId,
      replayTransitionType: travel.replayTransitionType,
      replayEnableRipple: travel.replayEnableRipple,
      replayEnableRouteAnimation: travel.replayEnableRouteAnimation,
      replayEnableBlurOverlay: travel.replayEnableBlurOverlay
    };
    const id = await this.travelRepo.createTravel(repoInput);
    const created = await this.getTravelById(id);
    if (!created) {
      throw new Error('Failed to retrieve created travel');
    }
    const payload = JSON.stringify({
      ownerUid: created.ownerUid ?? '',
      localId: created.id,
      cloudId: created.cloudId ?? '',
      name: created.name,
      coverPhoto: created.coverPhoto ?? '',
      startDate: created.startDate,
      endDate: created.endDate,
      updatedAt: created.updatedAt,
      deletedAt: created.deletedAt ?? 0,
      version: created.version ?? 1,
      isPublic: created.isPublic ? 1 : 0
    })
    await this.enqueueSync('travel', created.id, 'upsert', payload);
    return created;
  }

  async updateTravel(travelId: string, data: UpdateTravelInput): Promise<Trip> {
    logger.info(TAG, `[updateTravel] ENTER isPublic=${data.isPublic}, travelId=${travelId}`)
    const repoInput: RepoUpdateTravelInput = {};
    if (data.name !== undefined) {
      repoInput.name = data.name;
    }
    if (data.coverPhoto !== undefined) {
      repoInput.coverImageUri = data.coverPhoto;
    }
    if (data.isPublic !== undefined) {
      repoInput.isPublic = data.isPublic;
    }
    if (data.startDate !== undefined) {
      repoInput.startDate = data.startDate;
    }
    if (data.endDate !== undefined) {
      repoInput.endDate = data.endDate;
    }
    if (data.replayStyleKitId !== undefined) {
      repoInput.replayStyleKitId = data.replayStyleKitId;
    }
    if (data.replayBgmId !== undefined) {
      repoInput.replayBgmId = data.replayBgmId;
    }
    if (data.replayFilterId !== undefined) {
      repoInput.replayFilterId = data.replayFilterId;
    }
    if (data.replayTransitionType !== undefined) {
      repoInput.replayTransitionType = data.replayTransitionType;
    }
    if (data.replayEnableRipple !== undefined) {
      repoInput.replayEnableRipple = data.replayEnableRipple;
    }
    if (data.replayEnableRouteAnimation !== undefined) {
      repoInput.replayEnableRouteAnimation = data.replayEnableRouteAnimation;
    }
    if (data.replayEnableBlurOverlay !== undefined) {
      repoInput.replayEnableBlurOverlay = data.replayEnableBlurOverlay;
    }
    const updatedOk = await this.travelRepo.updateTravel(travelId, repoInput);
    if (!updatedOk) {
      throw new Error(`Failed to update travel: ${travelId}`);
    }
    const updated = await this.getTravelById(travelId);
    if (!updated) {
      throw new Error('Failed to retrieve updated travel');
    }
    logger.info(TAG, `[updateTravel] READ BACK isPublic=${updated.isPublic}, id=${updated.id}`)
    const payload = JSON.stringify({
      ownerUid: updated.ownerUid ?? '',
      localId: updated.id,
      cloudId: updated.cloudId ?? '',
      name: updated.name,
      coverPhoto: updated.coverPhoto ?? '',
      startDate: updated.startDate,
      endDate: updated.endDate,
      updatedAt: updated.updatedAt,
      deletedAt: updated.deletedAt ?? 0,
      version: updated.version ?? 1,
      isPublic: updated.isPublic ? 1 : 0
    })
    logger.info(TAG, `[updateTravel] PAYLOAD isPublic=${updated.isPublic ? 1 : 0}, payload=${payload}`)
    await this.enqueueSync('travel', updated.id, 'upsert', payload);
    return updated;
  }

  async getTripReplayPreferences(travelId: string): Promise<ReplayTripPreferences> {
    const trip = await this.travelRepo.getTravelById(travelId);
    if (!trip) {
      return {};
    }
    return {
      replayStyleKitId: trip.replayStyleKitId ?? '',
      replayBgmId: trip.replayBgmId ?? '',
      replayFilterId: trip.replayFilterId ?? '',
      replayTransitionType: trip.replayTransitionType ?? '',
      replayEnableRipple: trip.replayEnableRipple ?? false,
      replayEnableRouteAnimation: trip.replayEnableRouteAnimation ?? true,
      replayEnableBlurOverlay: trip.replayEnableBlurOverlay ?? false
    };
  }

  async updateTripReplayPreferences(travelId: string, data: ReplayTripPreferences): Promise<ReplayTripPreferences> {
    const updatedOk = await this.travelRepo.updateTravel(travelId, {
      replayStyleKitId: data.replayStyleKitId,
      replayBgmId: data.replayBgmId,
      replayFilterId: data.replayFilterId,
      replayTransitionType: data.replayTransitionType,
      replayEnableRipple: data.replayEnableRipple,
      replayEnableRouteAnimation: data.replayEnableRouteAnimation,
      replayEnableBlurOverlay: data.replayEnableBlurOverlay
    });
    if (!updatedOk) {
      throw new Error(`Failed to update replay preferences for travel: ${travelId}`);
    }
    return await this.getTripReplayPreferences(travelId);
  }

  async deleteTravel(travelId: string): Promise<void> {
    const affectedNodes = await this.nodeRepo.getNodesByTravelId(travelId)
    const travelToDelete = await this.travelRepo.getTravelById(travelId)
    const shouldSyncCloudNow = (AppStorage.get('networkOnline') as boolean) ?? false

    // 关键：在 softDeleteTravel 之前，先按 *原 travelId* 把每个 affected 节点的 photoManifest
    // 快照下来。softDelete 之后这些节点的 travel_id 会被改成 UNCATEGORIZED，
    // 如果再调 buildPhotoManifest(node.travelId, ...) 算出来的就是错的（指向 -1 目录），
    // 但实际云端文件还在原 travel 的目录下 —— 这正是 Bug 1 的源头之一。
    // 把原路径写回本地 photo_manifest 字段，让后续 push（auto 或手动）和 pull 都拿到正确路径。
    const preservedManifests = new Map<string, string>()
    for (let i = 0; i < affectedNodes.length; i++) {
      const aff = affectedNodes[i]
      const m = aff.photoManifest && aff.photoManifest.length > 2
        ? aff.photoManifest
        : this.buildPhotoManifest(aff.travelId, aff.id, aff.photos)
      preservedManifests.set(aff.id, m)
    }

    const deleted = await this.travelRepo.softDeleteTravel(travelId);
    if (!deleted) {
      throw new Error(`Failed to delete travel: ${travelId}`);
    }

    for (let i = 0; i < affectedNodes.length; i++) {
      const affectedNode = affectedNodes[i]
      const node = await this.nodeRepo.getNodeById(affectedNode.id)
      if (!node) {
        continue
      }
      logger.info(TAG, `[debug] deleteTravel affectedNode after localId=${node.id}, travelId=${node.travelId}, photos=${JSON.stringify(node.photos)}`)
      const nextTravelId = node.travelId; // 已被 softDeleteTravel 改成 UNCATEGORIZED
      const nextPhotos = [...node.photos];
      const preservedManifest = preservedManifests.get(node.id) ?? this.buildPhotoManifest(nextTravelId, node.id, nextPhotos)
      // 把保留下来的 manifest 写回本地 DB，这样 deleteNode、replaceLocalWithCloud 等场景
      // 用 node.photoManifest 都能拿到指向原 travel 路径的真实 cloud paths。
      if (preservedManifest.length > 2 && preservedManifest !== node.photoManifest) {
        await this.nodeRepo.updatePhotoManifest(node.id, preservedManifest)
      }
      const payload = JSON.stringify({
        ownerUid: node.ownerUid ?? '',
        localId: node.id,
        cloudId: node.cloudId ?? '',
        travelId: nextTravelId,
        title: node.title,
        content: node.content,
        latitude: node.latitude,
        longitude: node.longitude,
        poiName: node.poiName,
        photos: nextPhotos,
        mood: node.mood,
        tags: node.tags,
        nodeOrder: node.nodeOrder ?? 0,
        updatedAt: node.updatedAt,
        deletedAt: node.deletedAt ?? 0,
        version: node.version ?? 1,
        photoManifest: preservedManifest,
        visitedAt: node.visitedAt ?? 0
      })
      await this.enqueueSyncSilently('memory_node', node.id, 'upsert', payload)
    }

    const payload = JSON.stringify({
      ownerUid: travelToDelete?.ownerUid ?? '',
      localId: travelId,
      cloudId: travelToDelete?.cloudId ?? '',
      deletedAt: Date.now()
    })
    await this.enqueueSyncSilently('travel', travelId, 'delete', payload);
    if (shouldSyncCloudNow) {
      // 在线时统一在末尾 push 一次：先把 affected 子节点 upsert（含保留的原路径 manifest）写到云端，
      // 然后 handleItem('travel','delete') 只删 cloudDB 行（不再 wipe 整个目录），保证孩子图安全。
      void SyncManager.pushLocalNow()
    }
  }

  // ==================== MemoryNode 相关 ====================

  async getNodesByTravelId(travelId: string): Promise<MemoryNode[]> {
    return await this.nodeRepo.getNodesByTravelId(travelId);
  }

  async getNodeById(nodeId: string): Promise<MemoryNode | null> {
    const node = await this.nodeRepo.getNodeById(nodeId);
    return node ?? null;
  }

  async createNode(node: CreateNodeInput): Promise<MemoryNode> {
    const repoInput: RepoCreateNodeInput = {
      travelId: node.travelId,
      title: node.title,
      latitude: node.latitude,
      longitude: node.longitude,
      poiName: node.poiName,
      description: node.content,
      photos: node.photos,
      tags: node.tags,
      mood: node.mood,
      visitedAt: node.visitedAt
    };
    const id = await this.nodeRepo.createNode(repoInput);
    const created = await this.nodeRepo.getNodeById(id);
    if (!created) {
      throw new Error('Failed to retrieve created node');
    }
    // 新建节点时立刻把 manifest（指向当前 travel 目录）写回本地 DB，
    // 这样以后无论怎么跨 travel，home dir 都从这个 manifest 反推出来——
    // 第一次写入就把"home"锁定为创建时的 travel/node 目录。
    const initialManifest = this.buildPhotoManifest(created.travelId, created.id, created.photos);
    if (initialManifest.length > 2) {
      await this.nodeRepo.updatePhotoManifest(created.id, initialManifest);
      created.photoManifest = initialManifest;
    }
    const payload = JSON.stringify({
      ownerUid: created.ownerUid ?? '',
      localId: created.id,
      cloudId: created.cloudId ?? '',
      travelId: created.travelId,
      title: created.title,
      content: created.content,
      latitude: created.latitude,
      longitude: created.longitude,
      poiName: created.poiName,
      photos: created.photos,
      mood: created.mood,
      tags: created.tags,
      nodeOrder: created.nodeOrder ?? 0,
      updatedAt: created.updatedAt,
      deletedAt: created.deletedAt ?? 0,
      version: created.version ?? 1,
      photoManifest: initialManifest,
      visitedAt: created.visitedAt ?? 0
    })
    // 新建节点时如果是真实路线，按 visitedAt 重排并通过 sortNodesByVisitedAt 同步到云
    // （sortNodesByVisitedAt 里的 enqueueSyncSilently 已包含新节点，跳过下方单独的 enqueueSync）
    const isRealTravel = created.travelId !== TravelSpecialValues.UNCATEGORIZED_TRAVEL_ID;
    if (isRealTravel) {
      await this.sortNodesByVisitedAt(created.travelId);
    } else {
      // uncategorized 路线：只 enqueue 新节点本身（不排序）
      await this.enqueueSync('memory_node', created.id, 'upsert', payload);
    }
    const isOnlineForCreate = (AppStorage.get('networkOnline') as boolean) ?? false;
    if (isOnlineForCreate) {
      // 第一次上传时 manifest 刚写好，home dir 就是当前 travel 目录，等价于直接传到 currentTravelId 下。
      this.syncNodePhotosToCloud(created, created.photos);
    }
    return created;
  }

  async updateNode(nodeId: string, data: UpdateNodeInput): Promise<MemoryNode> {
    let oldPhotos: string[] = [];
    let travelId: string = '';
    let oldTravelId: string = '';
    let oldNodeSnapshot: MemoryNode | undefined = undefined;
    // 在 repo.updateNode 之前抓快照：home dir 推导依赖 *update 之前*的 photoManifest，
    // 不能用 update 之后的 updated（updated.travelId 已经是新 travel，但旧图还在原 travel 目录）。
    if (data.photos !== undefined || data.travelId !== undefined) {
      const oldNode = await this.nodeRepo.getNodeById(nodeId);
      if (oldNode) {
        oldNodeSnapshot = oldNode;
        oldPhotos = [...oldNode.photos];
        travelId = oldNode.travelId;
        oldTravelId = oldNode.travelId;
      }
    }

    const repoInput: RepoUpdateNodeInput = {};
    if (data.travelId !== undefined) {
      repoInput.travelId = data.travelId;
    }
    if (data.title !== undefined) {
      repoInput.title = data.title;
    }
    if (data.content !== undefined) {
      repoInput.description = data.content;
    }
    if (data.latitude !== undefined) {
      repoInput.latitude = data.latitude;
    }
    if (data.longitude !== undefined) {
      repoInput.longitude = data.longitude;
    }
    if (data.poiName !== undefined) {
      repoInput.poiName = data.poiName;
    }
    if (data.photos !== undefined) {
      repoInput.photos = data.photos;
    }
    if (data.mood !== undefined) {
      repoInput.mood = data.mood;
    }
    if (data.tags !== undefined) {
      repoInput.tags = data.tags;
    }
    if (data.visitedAt !== undefined) {
      repoInput.visitedAt = data.visitedAt;
    }
    const updatedOk = await this.nodeRepo.updateNode(nodeId, repoInput);
    if (!updatedOk) {
      throw new Error(`Failed to update node: ${nodeId}`);
    }

    // 删除被移除的本地图片，并从云端删除（按 oldNodeSnapshot 的 manifest 推 home dir，避免错路径）
    if (data.photos !== undefined) {
      const removedPhotos = this.getRemovedPhotos(oldPhotos, data.photos);
      if (removedPhotos.length > 0) {
        await PhotoPickerUtil.deletePhotos(removedPhotos);
        logger.info(TAG, `Cleaned ${removedPhotos.length} removed photos for node ${nodeId}`);
        const isOnlineForDelete = (AppStorage.get('networkOnline') as boolean) ?? false;
        if (isOnlineForDelete && oldNodeSnapshot) {
          this.syncDeletedNodePhotosToCloud(oldNodeSnapshot, removedPhotos);
        }
      }
    }

    const updated = await this.nodeRepo.getNodeById(nodeId);
    if (!updated) {
      throw new Error('Failed to retrieve updated node');
    }

    // ★ 关键修复点 ★
    // 紧接着 repo.updateNode 之后，立刻按 home-dir 模型把正确的 photoManifest 写回本地 DB。
    // 这样后面 sortNodesByVisitedAt → syncNodeOrdersToCloud 在重新读 sibling 时拿到的就是正确的
    // manifest（指向原 travel 的云路径），不会因为 photo_manifest 之前被 reset 成 '[]' 而走兜底
    // 把 manifest 算成 `travels/<新travelId>/...` 错误路径入队。
    //
    // home-dir 由 oldNodeSnapshot.photoManifest 决定（即 update 前的状态）：
    //  - 旧 manifest 非空：home = 旧 manifest 第一条的 dirname（节点首次上传时的 travel/node 目录）
    //  - 旧 manifest 为空：home = oldNodeSnapshot.travelId/node.id（节点从未传过图，本次创建 home）
    if (data.photos !== undefined && oldNodeSnapshot) {
      const newManifest = this.buildPhotoManifestForNode(oldNodeSnapshot, updated.photos);
      await this.nodeRepo.updatePhotoManifest(updated.id, newManifest);
      updated.photoManifest = newManifest;
    } else if (data.travelId !== undefined && oldNodeSnapshot && oldTravelId !== updated.travelId) {
      // 仅跨 travel 不改图：旧 manifest 已经在 DB 里且仍然有效，无需重算；
      // 但 updated 是 update 之后读出来的，它的 photoManifest 字段值就是旧 manifest（repo 没动它）。
      // 这里不需要再写一次。保留以备 future 修改。
    }

    // 在线时立即上传新增图——一律落到 home dir，不是 updated.travelId。
    if (data.photos !== undefined) {
      const isOnlineForPhotos = (AppStorage.get('networkOnline') as boolean) ?? false;
      if (isOnlineForPhotos && oldNodeSnapshot) {
        const addedPhotos = this.getAddedPhotos(oldPhotos, updated.photos);
        // 用 oldNodeSnapshot 的 manifest 推 home（updated.photoManifest 已经是新 manifest，但 home 由 dir
        // 前缀决定，新 manifest 也是从 oldNodeSnapshot 推导出来的，两边等价。
        // 这里显式传 oldNodeSnapshot 是为了语义清晰：home 来自 update 前的状态）。
        this.syncNodePhotosToCloud(oldNodeSnapshot, addedPhotos);
      }
    }

    let destinationSortAndSync = false;
    if (data.travelId !== undefined && oldTravelId.length > 0 && oldTravelId !== updated.travelId) {
      // Renormalize node orders in the source travel after the node left
      const remainingNodes = await this.nodeRepo.getNodesByTravelId(oldTravelId);
      const remainingIds = remainingNodes.map((n: MemoryNode) => n.id);
      if (remainingIds.length > 0) {
        await this.nodeRepo.reorderNodes(oldTravelId, remainingIds);
        await this.syncNodeOrdersToCloud(oldTravelId);
      }
      // 目标路线是真实路线时，按 visitedAt 重排并同步到云。
      // 此时 updated.photoManifest 已经被上面那段写成正确的 home-dir 路径，sortNodesByVisitedAt
      // 内部读 sibling 时拿到的就是对的，不会再算错。
      if (updated.travelId !== TravelSpecialValues.UNCATEGORIZED_TRAVEL_ID) {
        await this.sortNodesByVisitedAt(updated.travelId);
        destinationSortAndSync = true;
      }
    }

    const nextTravelId = data.travelId ?? updated.travelId;
    const nextPhotos = [...updated.photos];
    // payload 里的 manifest 直接用 updated.photoManifest（已经是 home-dir-aware 的正确值）。
    // 只有"既没改 photos 也没改 travelId 但走到这里"这种边缘情况下 updated.photoManifest 可能为空，
    // 那就退到旧版 buildPhotoManifest 兜底（此时 nextTravelId == oldTravelId，路径也对）。
    const manifestForPayload = updated.photoManifest && updated.photoManifest.length > 2
      ? updated.photoManifest
      : this.buildPhotoManifest(nextTravelId, updated.id, nextPhotos);
    const payload = JSON.stringify({
      ownerUid: updated.ownerUid ?? '',
      localId: updated.id,
      cloudId: updated.cloudId ?? '',
      travelId: nextTravelId,
      title: updated.title,
      content: updated.content,
      latitude: updated.latitude,
      longitude: updated.longitude,
      poiName: updated.poiName,
      photos: nextPhotos,
      mood: updated.mood,
      tags: updated.tags,
      nodeOrder: updated.nodeOrder ?? 0,
      updatedAt: updated.updatedAt,
      deletedAt: updated.deletedAt ?? 0,
      version: updated.version ?? 1,
      photoManifest: manifestForPayload,
      visitedAt: updated.visitedAt ?? 0
    })
    // 如果目标路线是真实路线，sortNodesByVisitedAt 已处理了移动节点的云端同步，跳过此处单独的 enqueueSync
    if (!destinationSortAndSync) {
      await this.enqueueSync('memory_node', updated.id, 'upsert', payload);
    }

    return updated;
  }

  async deleteNode(nodeId: string): Promise<void> {
    const node = await this.nodeRepo.getNodeById(nodeId);
    if (node && node.photos.length > 0) {
      await PhotoPickerUtil.deletePhotos(node.photos);
      logger.info(TAG, `Cleaned ${node.photos.length} photos for deleted node ${nodeId}`);
    }
    const result = await this.nodeRepo.softDeleteNode(nodeId);
    if (!result.success) {
      throw new Error(`Failed to delete node: ${nodeId}`);
    }
    const travelId = result.travelId;
    const belongsToTravel = travelId.length > 0 && travelId !== TravelSpecialValues.UNCATEGORIZED_TRAVEL_ID;
    if (travelId.length > 0) {
      const remainingNodes = await this.nodeRepo.getNodesByTravelId(travelId);
      const remainingIds = remainingNodes.map((n: MemoryNode) => n.id);
      if (remainingIds.length > 0) {
        await this.nodeRepo.reorderNodes(travelId, remainingIds);
      }
    }

    // photoCloudPaths：以 photoManifest 为准，因为节点可能跨过 travel（比如先经历过 deleteTravel
    // 进入 UNCATEGORIZED），此时云端文件还在原 travel 目录，buildNodePhotoPath(node.travelId, ...)
    // 算出来的就指向 -1 目录而不是真实位置。manifest 是云端路径的唯一可靠真相。
    let photoCloudPaths: string[] = [];
    if (node) {
      photoCloudPaths = this.parsePhotoManifest(node.photoManifest);
      if (photoCloudPaths.length === 0 && node.photos.length > 0) {
        // manifest 为空（极少见：节点从未同步过且首次创建后照片就被删了）走兜底，
        // 用当前 travelId 拼路径 —— 这种情况下云端基本也没有文件，不会误删别处。
        for (let i = 0; i < node.photos.length; i++) {
          photoCloudPaths.push(CloudStorageService.buildNodePhotoPath(node.travelId, node.id, node.photos[i]));
        }
      }
    }
    const ownerUid = node?.ownerUid ?? '';
    const cloudId = node?.cloudId ?? '';
    const payload = JSON.stringify({
      ownerUid: ownerUid,
      localId: nodeId,
      cloudId: cloudId,
      travelId: travelId,
      deletedAt: Date.now(),
      photoCloudPaths: photoCloudPaths
    })
    if (belongsToTravel) {
      // sortNodesByVisitedAt 内部已按需触发 push（在线时），这里只入队 delete，
      // 入队后再 push 一次保证 delete 项（晚于排序入队）也被推上去。
      await this.sortNodesByVisitedAt(travelId);
      await this.enqueueSyncSilently('memory_node', nodeId, 'delete', payload);
      const isOnline = (AppStorage.get('networkOnline') as boolean) ?? false;
      if (isOnline) {
        void SyncManager.pushLocalNow();
      }
    } else {
      await this.enqueueSync('memory_node', nodeId, 'delete', payload);
    }
  }

  async reorderNodes(travelId: string, nodeIds: string[]): Promise<void> {
    await this.nodeRepo.reorderNodes(travelId, nodeIds);
  }

  /**
   * 按 visitedAt ASC 重排路线内所有节点的 nodeOrder，并同步到云。
   * 仅对已关联旅行的节点生效（空置节点无路线，不处理）。
   */
  async sortNodesByVisitedAt(travelId: string): Promise<void> {
    if (!travelId || travelId === TravelSpecialValues.UNCATEGORIZED_TRAVEL_ID) {
      return
    }

    const siblings = await this.nodeRepo.getNodesByTravelId(travelId)
    // 按 visitedAt ASC 排序（visitedAt 为 0 则 fallback 到 createdAt）
    siblings.sort((a, b) => {
      const aTime = a.visitedAt && a.visitedAt > 0 ? a.visitedAt : a.createdAt
      const bTime = b.visitedAt && b.visitedAt > 0 ? b.visitedAt : b.createdAt
      return aTime - bTime
    })

    // 批量写入新的 nodeOrder（0, 1, 2, ...）
    await this.nodeRepo.reorderNodes(travelId, siblings.map(n => n.id))

    // 同步到云端
    await this.syncNodeOrdersToCloud(travelId)
  }

  async syncNodeOrdersToCloud(travelId: string): Promise<void> {
    const siblings = await this.nodeRepo.getNodesByTravelId(travelId);
    for (let i = 0; i < siblings.length; i++) {
      const sibling = siblings[i];
      // 用本地 DB 已有的 manifest（来自之前的同步 / 创建）；为空才回退到 buildPhotoManifest。
      // 这样跨过 deleteTravel 进入 UNCATEGORIZED 的节点，重排时不会把指向原 travel 的 manifest
      // 错改成指向 -1 目录。
      const preservedManifest = sibling.photoManifest && sibling.photoManifest.length > 2
        ? sibling.photoManifest
        : this.buildPhotoManifest(sibling.travelId, sibling.id, sibling.photos);
      const siblingPayload = JSON.stringify({
        ownerUid: sibling.ownerUid ?? '',
        localId: sibling.id,
        cloudId: sibling.cloudId ?? '',
        travelId: sibling.travelId,
        title: sibling.title,
        content: sibling.content,
        latitude: sibling.latitude,
        longitude: sibling.longitude,
        poiName: sibling.poiName,
        photos: sibling.photos,
        mood: sibling.mood,
        tags: sibling.tags,
        nodeOrder: sibling.nodeOrder ?? 0,
        updatedAt: sibling.updatedAt,
        deletedAt: sibling.deletedAt ?? 0,
        version: sibling.version ?? 1,
        photoManifest: preservedManifest,
        visitedAt: sibling.visitedAt ?? 0
      });
      await this.enqueueSyncSilently('memory_node', sibling.id, 'upsert', siblingPayload);
    }
    const isOnline = (AppStorage.get('networkOnline') as boolean) ?? false;
    if (isOnline) {
      void SyncManager.pushLocalNow();
    }
  }
}
