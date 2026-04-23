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
import { CloudStorageService, AuthService } from '../auth';
import { SyncManager } from '../sync/SyncManager';
import { RdbHelper } from '../data/RdbHelper';
import { TravelRepository } from '../data/TravelRepository';
import { MemoryNodeRepository } from '../data/MemoryNodeRepository';
import type { IDataService, CreateTravelInput, UpdateTravelInput, CreateNodeInput, UpdateNodeInput } from './IDataService';
import type { Trip, MemoryNode, SyncStatus } from './types';
import type { CreateTravelInput as RepoCreateTravelInput, UpdateTravelInput as RepoUpdateTravelInput } from '../data/TravelRepository';
import type { CreateNodeInput as RepoCreateNodeInput, UpdateNodeInput as RepoUpdateNodeInput } from '../data/MemoryNodeRepository';

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
    void SyncManager.pushLocalNow();
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

  private async uploadNodePhotosToCloud(travelId: string, nodeId: string, photos: string[], previousTravelId?: string): Promise<boolean> {
    let allSucceeded = true;
    const shouldMigrate = previousTravelId !== undefined && previousTravelId !== travelId;
    const migratedPhotos: string[] = [];
    for (const photo of photos) {
      try {
        if (shouldMigrate && previousTravelId) {
          await CloudStorageService.copyNodePhoto(previousTravelId, travelId, nodeId, photo);
          migratedPhotos.push(photo);
          logger.info(TAG, `Migrated node photo in cloud: ${nodeId} ${previousTravelId} -> ${travelId}`);
        } else {
          await CloudStorageService.uploadNodePhoto(travelId, nodeId, photo);
          logger.info(TAG, `Uploaded node photo to cloud: ${nodeId} -> ${photo}`);
        }
      } catch (err) {
        const error = err as Error;
        logger.error(TAG, `Failed to upload node photo ${photo}: ${error.message}`);
        allSucceeded = false;
      }
    }
    if (shouldMigrate && previousTravelId && migratedPhotos.length > 0) {
      await this.deleteNodePhotosFromCloud(previousTravelId, nodeId, migratedPhotos);
    }
    return allSucceeded;
  }

  private syncDeletedNodePhotosToCloud(travelId: string, nodeId: string, photos: string[]): void {
    if (photos.length === 0) {
      return;
    }

    void this.deleteNodePhotosFromCloud(travelId, nodeId, photos);
  }

  private async deleteNodePhotosFromCloud(travelId: string, nodeId: string, photos: string[]): Promise<void> {
    for (const photo of photos) {
      try {
        await CloudStorageService.deleteNodePhoto(travelId, nodeId, photo);
        logger.info(TAG, `Deleted node photo from cloud: ${nodeId} -> ${photo}`);
      } catch (err) {
        const error = err as Error;
        logger.error(TAG, `Failed to delete node photo ${photo}: ${error.message}`);
      }
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
          version: trips[i].version
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
        version: trip.version
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
      endDate: travel.endDate
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
      if (shouldSyncCloudNow && node.photos.length > 0 && affectedNode.travelId !== node.travelId) {
        const migrated = await this.uploadNodePhotosToCloud(node.travelId, node.id, node.photos, affectedNode.travelId)
        if (!migrated) {
          nextTravelId = affectedNode.travelId;
          nextPhotos = [...affectedNode.photos];
        }
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
        updatedAt: node.updatedAt,
        deletedAt: node.deletedAt ?? 0,
        version: node.version ?? 1,
        photoManifest: this.buildPhotoManifest(nextTravelId, node.id, nextPhotos)
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
      mood: node.mood
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
      updatedAt: created.updatedAt,
      deletedAt: created.deletedAt ?? 0,
      version: created.version ?? 1,
      photoManifest: this.buildPhotoManifest(created.travelId, created.id, created.photos)
    })
    await this.enqueueSync('memory_node', created.id, 'upsert', payload);
    this.syncNodePhotosToCloud(created.travelId, created.id, created.photos);
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
    const updatedOk = await this.nodeRepo.updateNode(nodeId, repoInput);
    if (!updatedOk) {
      throw new Error(`Failed to update node: ${nodeId}`);
    }

    if (data.photos !== undefined) {
      const removedPhotos = this.getRemovedPhotos(oldPhotos, data.photos);
      if (removedPhotos.length > 0) {
        await PhotoPickerUtil.deletePhotos(removedPhotos);
        logger.info(TAG, `Cleaned ${removedPhotos.length} removed photos for node ${nodeId}`);
        if (travelId.length > 0) {
          this.syncDeletedNodePhotosToCloud(travelId, nodeId, removedPhotos);
        }
      }
    }

    const updated = await this.nodeRepo.getNodeById(nodeId);
    if (!updated) {
      throw new Error('Failed to retrieve updated node');
    }

    if (data.photos !== undefined) {
      const addedPhotos = this.getAddedPhotos(oldPhotos, updated.photos);
      this.syncNodePhotosToCloud(updated.travelId, updated.id, addedPhotos);
    }

    if (data.travelId !== undefined && oldTravelId.length > 0 && oldTravelId !== updated.travelId && updated.photos.length > 0) {
      const shouldSyncCloudNow = (AppStorage.get('networkOnline') as boolean) ?? false;
      if (shouldSyncCloudNow) {
        const migrated = await this.uploadNodePhotosToCloud(updated.travelId, updated.id, updated.photos, oldTravelId);
        if (!migrated) {
          data.travelId = oldTravelId;
          updated.photos = [...oldPhotos];
        }
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
      updatedAt: updated.updatedAt,
      deletedAt: updated.deletedAt ?? 0,
      version: updated.version ?? 1,
      photoManifest: this.buildPhotoManifest(nextTravelId, updated.id, nextPhotos)
    })
    await this.enqueueSync('memory_node', updated.id, 'upsert', payload);

    return updated;
  }

  async deleteNode(nodeId: string): Promise<void> {
    const node = await this.nodeRepo.getNodeById(nodeId);
    if (node && node.photos.length > 0) {
      await PhotoPickerUtil.deletePhotos(node.photos);
      logger.info(TAG, `Cleaned ${node.photos.length} photos for deleted node ${nodeId}`);
    }
    const deleted = await this.nodeRepo.softDeleteNode(nodeId);
    if (!deleted) {
      throw new Error(`Failed to delete node: ${nodeId}`);
    }
    if (node && node.photos.length > 0) {
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
      travelId: node?.travelId ?? '',
      deletedAt: Date.now(),
      photoCloudPaths: photoCloudPaths
    })
    await this.enqueueSync('memory_node', nodeId, 'delete', payload);
  }

  async reorderNodes(travelId: string, nodeIds: string[]): Promise<void> {
    await this.nodeRepo.reorderNodes(travelId, nodeIds);
    const payload = JSON.stringify({
      localId: travelId,
      nodeIds: nodeIds
    })
    await this.enqueueSync('travel', travelId, 'reorder_nodes', payload);
  }
}
