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
import { CloudStorageService, AuthService } from '../auth';
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

  private async enqueueSync(entityType: string, entityId: string, operation: string, payload: string): Promise<void> {
    await this.rdbHelper.removeSyncItems(entityType, entityId);
    await this.rdbHelper.enqueueSyncItem(entityType, entityId, operation, payload);
    const isOnline = (AppStorage.get('networkOnline') as boolean) ?? false;
    if (isOnline) {
      void SyncManager.pushLocalNow();
    }
  }

  private async enqueueSyncSilently(entityType: string, entityId: string, operation: string, payload: string): Promise<void> {
    await this.rdbHelper.removeSyncItems(entityType, entityId);
    await this.rdbHelper.enqueueSyncItem(entityType, entityId, operation, payload);
  }

  async getSyncStatus(): Promise<SyncStatus> {
    const pendingItems = await this.rdbHelper.getPendingSyncQueueItems();
    const lastPushTime = await this.rdbHelper.getSyncState('last_push_at');
    const lastPullTime = await this.rdbHelper.getSyncState('last_pull_at');
    const status: SyncStatus = {
      lastSyncTime: Math.max(lastPushTime, lastPullTime),
      lastPushTime: lastPushTime,
      lastPullTime: lastPullTime,
      pendingCount: pendingItems.length,
      isSyncing: SyncManager.isSyncing()
    }
    return status;
  }

  private buildPhotoManifest(travelId: string, nodeId: string, photos: string[]): string {
    const cloudPaths: string[] = [];
    for (let i = 0; i < photos.length; i++) {
      cloudPaths.push(CloudStorageService.buildNodePhotoPath(travelId, nodeId, photos[i]));
    }
    return JSON.stringify(cloudPaths);
  }

  private syncNodePhotosToCloud(travelId: string, nodeId: string, photos: string[], previousTravelId?: string): void {
    if (photos.length === 0) {
      return;
    }

    void this.uploadNodePhotosToCloud(travelId, nodeId, photos, previousTravelId);
  }

  private migrateNodePhotosToNewTravel(travelId: string, nodeId: string, photos: string[], oldTravelId: string): void {
    if (photos.length === 0) {
      return;
    }
    void this.uploadNodePhotosToCloud(travelId, nodeId, photos, oldTravelId);
  }

  private async uploadNodePhotosToCloud(travelId: string, nodeId: string, photos: string[], previousTravelId?: string): Promise<boolean> {
    let allSucceeded = true;
    const shouldMigrate = previousTravelId !== undefined && previousTravelId !== travelId;

    if (shouldMigrate && photos.length > 0) {
      // 直接上传本地文件到新云目录（不下载！）
      for (const photo of photos) {
        try {
          await CloudStorageService.uploadNodePhoto(travelId, nodeId, photo);
          logger.info(TAG, `Migrated photo to new travel: ${nodeId} -> ${photo}`);
        } catch (err) {
          logger.error(TAG, `Migrate photo failed: ${(err as Error).message}`);
          allSucceeded = false;
        }
      }
      // 后台删除旧云目录照片（fire-and-forget）
      this.deleteNodePhotosFromCloud(previousTravelId, nodeId, photos);
      return allSucceeded;
    }

    // 新增照片上传（原有逻辑不变）
    for (const photo of photos) {
      try {
        await CloudStorageService.uploadNodePhoto(travelId, nodeId, photo);
        logger.info(TAG, `Uploaded node photo to cloud: ${nodeId} -> ${photo}`);
      } catch (err) {
        allSucceeded = false;
      }
    }
    return allSucceeded;
  }

  private syncDeletedNodePhotosToCloud(travelId: string, nodeId: string, photos: string[]): void {
    if (photos.length === 0) {
      return;
    }

    void this.deleteNodePhotosFromCloud(travelId, nodeId, photos);
  }

  private deleteNodePhotosFromCloud(travelId: string, nodeId: string, photos: string[]): void {
    for (const photo of photos) {
      try {
        void CloudStorageService.deleteNodePhoto(travelId, nodeId, photo);
      } catch (_) {}
    }
  }

  private getAddedPhotos(oldPhotos: string[], newPhotos: string[]): string[] {
    return newPhotos.filter((photo: string) => !oldPhotos.includes(photo));
  }

  private getRemovedPhotos(oldPhotos: string[], newPhotos: string[]): string[] {
    return oldPhotos.filter((photo: string) => !newPhotos.includes(photo));
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
        replayTransitionType: trips[i].replayTransitionType
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
        replayTransitionType: trip.replayTransitionType
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
      replayTransitionType: travel.replayTransitionType
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
      version: created.version ?? 1
    })
    await this.enqueueSync('travel', created.id, 'upsert', payload);
    return created;
  }

  async updateTravel(travelId: string, data: UpdateTravelInput): Promise<Trip> {
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
    const updatedOk = await this.travelRepo.updateTravel(travelId, repoInput);
    if (!updatedOk) {
      throw new Error(`Failed to update travel: ${travelId}`);
    }
    const updated = await this.getTravelById(travelId);
    if (!updated) {
      throw new Error('Failed to retrieve updated travel');
    }
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
      version: updated.version ?? 1
    })
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
      replayTransitionType: trip.replayTransitionType ?? ''
    };
  }

  async updateTripReplayPreferences(travelId: string, data: ReplayTripPreferences): Promise<ReplayTripPreferences> {
    const updatedOk = await this.travelRepo.updateTravel(travelId, {
      replayStyleKitId: data.replayStyleKitId,
      replayBgmId: data.replayBgmId,
      replayFilterId: data.replayFilterId,
      replayTransitionType: data.replayTransitionType
    });
    if (!updatedOk) {
      throw new Error(`Failed to update replay preferences for travel: ${travelId}`);
    }
    return await this.getTripReplayPreferences(travelId);
  }

  async deleteTravel(travelId: string): Promise<void> {
    const affectedNodes = await this.nodeRepo.getNodesByTravelId(travelId)
    const shouldSyncCloudNow = (AppStorage.get('networkOnline') as boolean) ?? false
    const deleted = await this.travelRepo.softDeleteTravel(travelId);
    if (!deleted) {
      throw new Error(`Failed to delete travel: ${travelId}`);
    }

    for (let i = 0; i < affectedNodes.length; i++) {
      const affectedNode = affectedNodes[i]
      logger.info(TAG, `[debug] deleteTravel affectedNode before localId=${affectedNode.id}, travelId=${affectedNode.travelId}, photos=${JSON.stringify(affectedNode.photos)}`)
      const node = await this.nodeRepo.getNodeById(affectedNode.id)
      if (!node) {
        continue
      }
      logger.info(TAG, `[debug] deleteTravel affectedNode after localId=${node.id}, travelId=${node.travelId}, photos=${JSON.stringify(node.photos)}`)
      let nextTravelId = node.travelId;
      let nextPhotos = [...node.photos];
      if (node.photos.length > 0 && affectedNode.travelId !== node.travelId) {
        // 照片迁移到新目录，后台执行
        this.migrateNodePhotosToNewTravel(node.travelId, node.id, node.photos, affectedNode.travelId);
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
        photoManifest: this.buildPhotoManifest(nextTravelId, node.id, nextPhotos),
        visitedAt: node.visitedAt ?? 0
      })
      await this.enqueueSyncSilently('memory_node', node.id, 'upsert', payload)
    }

    const payload = JSON.stringify({
      localId: travelId,
      deletedAt: Date.now()
    })
    await this.enqueueSyncSilently('travel', travelId, 'delete', payload);
    if (shouldSyncCloudNow) {
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
      photoManifest: this.buildPhotoManifest(created.travelId, created.id, created.photos),
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
      this.syncNodePhotosToCloud(created.travelId, created.id, created.photos);
    }
    return created;
  }

  async updateNode(nodeId: string, data: UpdateNodeInput): Promise<MemoryNode> {
    let oldPhotos: string[] = [];
    let travelId: string = '';
    let oldTravelId: string = '';
    if (data.photos !== undefined || data.travelId !== undefined) {
      const oldNode = await this.nodeRepo.getNodeById(nodeId);
      if (oldNode) {
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

    if (data.photos !== undefined) {
      const removedPhotos = this.getRemovedPhotos(oldPhotos, data.photos);
      if (removedPhotos.length > 0) {
        await PhotoPickerUtil.deletePhotos(removedPhotos);
        logger.info(TAG, `Cleaned ${removedPhotos.length} removed photos for node ${nodeId}`);
        const isOnlineForDelete = (AppStorage.get('networkOnline') as boolean) ?? false;
        if (isOnlineForDelete && travelId.length > 0) {
          this.syncDeletedNodePhotosToCloud(travelId, nodeId, removedPhotos);
        }
      }
    }

    const updated = await this.nodeRepo.getNodeById(nodeId);
    if (!updated) {
      throw new Error('Failed to retrieve updated node');
    }

    if (data.photos !== undefined) {
      const isOnlineForPhotos = (AppStorage.get('networkOnline') as boolean) ?? false;
      if (isOnlineForPhotos) {
        const addedPhotos = this.getAddedPhotos(oldPhotos, updated.photos);
        this.syncNodePhotosToCloud(updated.travelId, updated.id, addedPhotos);
      }
    }

    let destinationSortAndSync = false;
    if (data.travelId !== undefined && oldTravelId.length > 0 && oldTravelId !== updated.travelId) {
      // Renormalize node orders in the source travel after the node left
      const remainingNodes = await this.nodeRepo.getNodesByTravelId(oldTravelId);
      const remainingIds = remainingNodes.map((n: MemoryNode) => n.id);
      if (remainingIds.length > 0) {
        await this.nodeRepo.reorderNodes(oldTravelId, remainingIds);
        // 将源路线重编号后的 nodeOrder 同步到云端（bugfix）
        await this.syncNodeOrdersToCloud(oldTravelId);
      }

      // 目标路线是真实路线时，按 visitedAt 重排并同步到云
      if (updated.travelId !== TravelSpecialValues.UNCATEGORIZED_TRAVEL_ID) {
        await this.sortNodesByVisitedAt(updated.travelId);
        destinationSortAndSync = true;
      }

      // 照片迁移：直接上传本地文件到新云目录，后台执行
      if (updated.photos.length > 0) {
        const newManifest = this.buildPhotoManifest(updated.travelId, updated.id, updated.photos);
        updated.photoManifest = newManifest;
        void this.nodeRepo.updatePhotoManifest(updated.id, newManifest);
        this.migrateNodePhotosToNewTravel(updated.travelId, updated.id, updated.photos, oldTravelId);
      }
    }

    const nextTravelId = data.travelId ?? updated.travelId;
    const nextPhotos = [...updated.photos];
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
      photoManifest: this.buildPhotoManifest(nextTravelId, updated.id, nextPhotos),
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
    // Renormalize sibling node orders and sync to cloud
    const travelId = result.travelId;
    const belongsToTravel = travelId.length > 0 && travelId !== TravelSpecialValues.UNCATEGORIZED_TRAVEL_ID;
    if (travelId.length > 0) {
      const remainingNodes = await this.nodeRepo.getNodesByTravelId(travelId);
      const remainingIds = remainingNodes.map((n: MemoryNode) => n.id);
      if (remainingIds.length > 0) {
        await this.nodeRepo.reorderNodes(travelId, remainingIds);
      }
    }
    const isOnlineForNodeDelete = (AppStorage.get('networkOnline') as boolean) ?? false;
    if (isOnlineForNodeDelete && node && node.photos.length > 0) {
      this.syncDeletedNodePhotosToCloud(node.travelId, node.id, node.photos);
    }
    const photoCloudPaths: string[] = [];
    if (node) {
      for (let i = 0; i < node.photos.length; i++) {
        photoCloudPaths.push(CloudStorageService.buildNodePhotoPath(node.travelId, node.id, node.photos[i]));
      }
    }
    const payload = JSON.stringify({
      localId: nodeId,
      travelId: travelId,
      deletedAt: Date.now(),
      photoCloudPaths: photoCloudPaths
    })
    if (belongsToTravel) {
      await this.sortNodesByVisitedAt(travelId);
      // sortNodesByVisitedAt 里的 pushLocalNow 已处理完剩余节点，
      // delete item 在其之后才入队，需要单独再触发一次 push（仅在线时）
      await this.enqueueSyncSilently('memory_node', nodeId, 'delete', payload);
      const isOnline = (AppStorage.get('networkOnline') as boolean) ?? false;
      if (isOnline) {
        SyncManager.pushLocalNow();
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
        photoManifest: this.buildPhotoManifest(sibling.travelId, sibling.id, sibling.photos),
        visitedAt: sibling.visitedAt ?? 0
      });
      await this.enqueueSyncSilently('memory_node', sibling.id, 'upsert', siblingPayload);
    }
    const isOnline = (AppStorage.get('networkOnline') as boolean) ?? false;
    if (isOnline) {
      await SyncManager.pushLocalNow();
    }
  }
}
