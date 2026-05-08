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

import { relationalStore as rdb } from '@kit.ArkData';
import { logger } from '../utils/Logger';
import { TravelSpecialValues } from '../utils/Constants';
import { RdbHelper } from './RdbHelper';
import { AuthService } from '../auth';
import type { Trip } from '../service/types';

const TAG = 'TravelRepository';
const TABLE_NAME = 'travels';

/**
 * 创建旅行的输入数据（不包含 id、createdAt、updatedAt）
 */
export interface CreateTravelInput {
  name: string;
  coverImageUri?: string;
  isPublic?: boolean;
  startDate: number;
  endDate: number;
  sensitivity?: string;
  replayStyleKitId?: string;
  replayBgmId?: string;
  replayFilterId?: string;
  replayTransitionType?: string;
  replayEnableRipple?: boolean;
  replayEnableRouteAnimation?: boolean;
  replayEnableBlurOverlay?: boolean;
}

/**
 * 更新旅行的输入数据（所有字段可选）
 */
export interface UpdateTravelInput {
  name?: string;
  coverImageUri?: string;
  isPublic?: boolean;
  startDate?: number;
  endDate?: number;
  sensitivity?: string;
  replayStyleKitId?: string;
  replayBgmId?: string;
  replayFilterId?: string;
  replayTransitionType?: string;
  replayEnableRipple?: boolean;
  replayEnableRouteAnimation?: boolean;
  replayEnableBlurOverlay?: boolean;
}

interface NodePhotoData {
  photos: string;
  photoManifest: string;
}

export class TravelRepository {
  private rdbHelper: RdbHelper;

  constructor() {
    this.rdbHelper = RdbHelper.getInstance();
  }

  private async getRdbStore(): Promise<rdb.RdbStore> {
    return await this.rdbHelper.getStore();
  }

  private closeResultSet(resultSet?: rdb.ResultSet): void {
    if (!resultSet) {
      return;
    }
    try {
      resultSet.close();
    } catch (err) {
      logger.warn(TAG, `Failed to close ResultSet: ${JSON.stringify(err)}`);
    }
  }

  private toError(err: Object): Error {
    return new Error(JSON.stringify(err));
  }

  private toDbId(id: string, fieldName: string): number {
    const parsed = Number(id);
    const uncategorizedId = Number(TravelSpecialValues.UNCATEGORIZED_TRAVEL_ID);
    if (!Number.isInteger(parsed) || parsed === 0 || parsed < uncategorizedId) {
      throw new Error(`Invalid ${fieldName}: ${id}`);
    }
    return parsed;
  }

  private async getOwnerUid(): Promise<string> {
    const user = await AuthService.getCurrentUser();
    return user?.uid ?? '';
  }

  private mapResultSetToTrip(resultSet: rdb.ResultSet): Trip {
    const idIdx = resultSet.getColumnIndex('id');
    const nameIdx = resultSet.getColumnIndex('name');
    const coverIdx = resultSet.getColumnIndex('cover_image_uri');
    const isPublicIdx = resultSet.getColumnIndex('is_public');
    const startIdx = resultSet.getColumnIndex('start_date');
    const endIdx = resultSet.getColumnIndex('end_date');
    const createdIdx = resultSet.getColumnIndex('created_at');
    const updatedIdx = resultSet.getColumnIndex('updated_at');
    const ownerUidIdx = resultSet.getColumnIndex('owner_uid');
    const cloudIdIdx = resultSet.getColumnIndex('cloud_id');
    const syncStatusIdx = resultSet.getColumnIndex('sync_status');
    const deletedAtIdx = resultSet.getColumnIndex('deleted_at');
    const lastSyncedAtIdx = resultSet.getColumnIndex('last_synced_at');
    const versionIdx = resultSet.getColumnIndex('version');
    const replayStyleKitIdIdx = resultSet.getColumnIndex('replay_style_kit_id');
    const replayBgmIdIdx = resultSet.getColumnIndex('replay_bgm_id');
    const replayFilterIdIdx = resultSet.getColumnIndex('replay_filter_id');
    const replayTransitionTypeIdx = resultSet.getColumnIndex('replay_transition_type');
    const replayEnableRippleIdx = resultSet.getColumnIndex('replay_enable_ripple');
    const replayEnableRouteAnimationIdx = resultSet.getColumnIndex('replay_enable_route_animation');
    const replayEnableBlurOverlayIdx = resultSet.getColumnIndex('replay_enable_blur_overlay');

    const trip: Trip = {
      id: resultSet.getDouble(idIdx).toString(),
      name: resultSet.getString(nameIdx),
      description: '',
      coverPhoto: resultSet.getString(coverIdx),
      isPublic: isPublicIdx >= 0 ? resultSet.getDouble(isPublicIdx) === 1 : false,
      startDate: resultSet.getDouble(startIdx),
      endDate: resultSet.getDouble(endIdx),
      nodeIds: [],
      totalDistance: 0,
      createdAt: resultSet.getDouble(createdIdx),
      updatedAt: resultSet.getDouble(updatedIdx),
      ownerUid: ownerUidIdx >= 0 ? (resultSet.getString(ownerUidIdx) ?? '') : '',
      cloudId: cloudIdIdx >= 0 ? (resultSet.getString(cloudIdIdx) ?? '') : '',
      syncStatus: syncStatusIdx >= 0 ? (resultSet.getString(syncStatusIdx) ?? 'local_only') : 'local_only',
      deletedAt: deletedAtIdx >= 0 ? resultSet.getDouble(deletedAtIdx) : 0,
      lastSyncedAt: lastSyncedAtIdx >= 0 ? resultSet.getDouble(lastSyncedAtIdx) : 0,
      version: versionIdx >= 0 ? resultSet.getDouble(versionIdx) : 1,
      replayStyleKitId: replayStyleKitIdIdx >= 0 ? (resultSet.getString(replayStyleKitIdIdx) ?? '') : '',
      replayBgmId: replayBgmIdIdx >= 0 ? (resultSet.getString(replayBgmIdIdx) ?? '') : '',
      replayFilterId: replayFilterIdIdx >= 0 ? (resultSet.getString(replayFilterIdIdx) ?? '') : '',
      replayTransitionType: replayTransitionTypeIdx >= 0 ? (resultSet.getString(replayTransitionTypeIdx) ?? '') : '',
      replayEnableRipple: replayEnableRippleIdx >= 0 ? resultSet.getDouble(replayEnableRippleIdx) === 1 : false,
      replayEnableRouteAnimation: replayEnableRouteAnimationIdx >= 0 ?
        resultSet.getDouble(replayEnableRouteAnimationIdx) === 1 : false,
      replayEnableBlurOverlay: replayEnableBlurOverlayIdx >= 0 ? resultSet.getDouble(replayEnableBlurOverlayIdx) === 1 : false
    };
    return trip;
  }

  async getAllTravels(): Promise<Trip[]> {
    let resultSet: rdb.ResultSet | undefined = undefined;
    try {
      const store = await this.getRdbStore();
      const ownerUid = await this.getOwnerUid();
      const predicates = new rdb.RdbPredicates(TABLE_NAME);
      predicates.equalTo('owner_uid', ownerUid);
      predicates.equalTo('deleted_at', 0);
      predicates.orderByDesc('created_at');
      resultSet = await store.query(predicates);
      const trips: Trip[] = [];
      if (resultSet.goToFirstRow()) {
        do {
          trips.push(this.mapResultSetToTrip(resultSet));
        } while (resultSet.goToNextRow());
      }
      logger.info(TAG, `Loaded ${trips.length} travels`);
      return trips;
    } catch (err) {
      logger.error(TAG, `getAllTravels failed: ${JSON.stringify(err)}`);
      return [];
    } finally {
      this.closeResultSet(resultSet);
    }
  }

  async getAllTravelsIncludingDeleted(): Promise<Trip[]> {
    let resultSet: rdb.ResultSet | undefined = undefined;
    try {
      const store = await this.getRdbStore();
      const ownerUid = await this.getOwnerUid();
      const predicates = new rdb.RdbPredicates(TABLE_NAME);
      predicates.equalTo('owner_uid', ownerUid);
      predicates.orderByDesc('updated_at');
      resultSet = await store.query(predicates);
      const trips: Trip[] = [];
      if (resultSet.goToFirstRow()) {
        do {
          trips.push(this.mapResultSetToTrip(resultSet));
        } while (resultSet.goToNextRow());
      }
      logger.info(TAG, `Loaded ${trips.length} travels including deleted`);
      return trips;
    } catch (err) {
      logger.error(TAG, `getAllTravelsIncludingDeleted failed: ${JSON.stringify(err)}`);
      return [];
    } finally {
      this.closeResultSet(resultSet);
    }
  }

  async getTravelById(id: string): Promise<Trip | undefined> {
    let resultSet: rdb.ResultSet | undefined = undefined;
    try {
      const store = await this.getRdbStore();
      const predicates = new rdb.RdbPredicates(TABLE_NAME);
      predicates.equalTo('id', this.toDbId(id, 'travel id'));
      predicates.equalTo('deleted_at', 0);
      resultSet = await store.query(predicates);
      let trip: Trip | undefined = undefined;
      if (resultSet.goToFirstRow()) {
        trip = this.mapResultSetToTrip(resultSet);
      }
      return trip;
    } catch (err) {
      logger.error(TAG, `getTravelById failed: ${JSON.stringify(err)}`);
      return undefined;
    } finally {
      this.closeResultSet(resultSet);
    }
  }

  async createTravel(travel: CreateTravelInput): Promise<string> {
    try {
      const store = await this.getRdbStore();
      const now = Date.now();
      const ownerUid = await this.getOwnerUid();
      const valueBucket: rdb.ValuesBucket = {
        'name': travel.name,
        'cover_image_uri': travel.coverImageUri ?? '',
        'is_public': travel.isPublic ? 1 : 0,
        'start_date': travel.startDate,
        'end_date': travel.endDate,
        'created_at': now,
        'updated_at': now,
        'sensitivity': travel.sensitivity ?? 'S1',
        'owner_uid': ownerUid,
        'cloud_id': '',
        'sync_status': 'pending_create',
        'deleted_at': 0,
        'last_synced_at': 0,
        'version': 1,
        'replay_style_kit_id': travel.replayStyleKitId ?? '',
        'replay_bgm_id': travel.replayBgmId ?? '',
        'replay_filter_id': travel.replayFilterId ?? '',
        'replay_transition_type': travel.replayTransitionType ?? '',
        'replay_enable_ripple': travel.replayEnableRipple ? 1 : 0,
        'replay_enable_route_animation': travel.replayEnableRouteAnimation ? 1 : 0,
        'replay_enable_blur_overlay': travel.replayEnableBlurOverlay ? 1 : 0
      };
      const rowId = await store.insert(TABLE_NAME, valueBucket);
      logger.info(TAG, `Created travel: ${travel.name}, id=${rowId}`);
      return rowId.toString();
    } catch (err) {
      logger.error(TAG, `createTravel failed: ${JSON.stringify(err)}`);
      throw this.toError(err);
    }
  }

  async updateTravel(id: string, travel: UpdateTravelInput): Promise<boolean> {
    try {
      const store = await this.getRdbStore();
      const currentTrip = await this.getTravelById(id);
      if (!currentTrip) {
        return false;
      }
      const valueBucket: rdb.ValuesBucket = {
        'updated_at': Date.now(),
        'sync_status': currentTrip.cloudId && currentTrip.cloudId.length > 0 ? 'pending_update' : 'pending_create',
        'version': (currentTrip.version ?? 1) + 1
      };
      if (travel.name !== undefined) {
        valueBucket['name'] = travel.name;
      }
      if (travel.coverImageUri !== undefined) {
        valueBucket['cover_image_uri'] = travel.coverImageUri;
      }
      if (travel.isPublic !== undefined) {
        valueBucket['is_public'] = travel.isPublic ? 1 : 0;
      }
      if (travel.startDate !== undefined) {
        valueBucket['start_date'] = travel.startDate;
      }
      if (travel.endDate !== undefined) {
        valueBucket['end_date'] = travel.endDate;
      }
      if (travel.sensitivity !== undefined) {
        valueBucket['sensitivity'] = travel.sensitivity;
      }
      if (travel.replayStyleKitId !== undefined) {
        valueBucket['replay_style_kit_id'] = travel.replayStyleKitId;
      }
      if (travel.replayBgmId !== undefined) {
        valueBucket['replay_bgm_id'] = travel.replayBgmId;
      }
      if (travel.replayFilterId !== undefined) {
        valueBucket['replay_filter_id'] = travel.replayFilterId;
      }
      if (travel.replayTransitionType !== undefined) {
        valueBucket['replay_transition_type'] = travel.replayTransitionType;
      }
      if (travel.replayEnableRipple !== undefined) {
        valueBucket['replay_enable_ripple'] = travel.replayEnableRipple ? 1 : 0;
      }
      if (travel.replayEnableRouteAnimation !== undefined) {
        valueBucket['replay_enable_route_animation'] = travel.replayEnableRouteAnimation ? 1 : 0;
      }
      if (travel.replayEnableBlurOverlay !== undefined) {
        valueBucket['replay_enable_blur_overlay'] = travel.replayEnableBlurOverlay ? 1 : 0;
      }
      const predicates = new rdb.RdbPredicates(TABLE_NAME);
      predicates.equalTo('id', this.toDbId(id, 'travel id'));
      const affectedRows = await store.update(valueBucket, predicates);
      logger.info(TAG, `Updated travel ${id}, affected=${affectedRows}`);
      return affectedRows > 0;
    } catch (err) {
      logger.error(TAG, `updateTravel failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  async softDeleteTravel(id: string): Promise<boolean> {
    try {
      const store = await this.getRdbStore();
      const currentTrip = await this.getTravelById(id);
      if (!currentTrip) {
        return false;
      }
      const now = Date.now();
      const travelId = this.toDbId(id, 'travel id');

      const nodeValues: rdb.ValuesBucket = {
        travel_id: this.toDbId(TravelSpecialValues.UNCATEGORIZED_TRAVEL_ID, 'travel id'),
        updated_at: now,
        sync_status: currentTrip.cloudId && currentTrip.cloudId.length > 0 ? 'pending_update' : 'pending_create'
      };
      const nodePredicates = new rdb.RdbPredicates('memory_nodes');
      nodePredicates.equalTo('travel_id', travelId);
      nodePredicates.equalTo('deleted_at', 0);
      const currentNodesResultSet = await store.query(nodePredicates);
      const nodePhotosMap: Map<number, NodePhotoData> = new Map();
      try {
        if (currentNodesResultSet.goToFirstRow()) {
          do {
            const nodeId = currentNodesResultSet.getDouble(currentNodesResultSet.getColumnIndex('id'));
            const photos = currentNodesResultSet.getString(currentNodesResultSet.getColumnIndex('photos')) ?? '[]';
            logger.info(TAG, `[debug] softDeleteTravel before move nodeId=${nodeId}, photos=${photos}`);
            const photoManifestIndex = currentNodesResultSet.getColumnIndex('photo_manifest');
            const photoManifest = photoManifestIndex >= 0
              ? (currentNodesResultSet.getString(photoManifestIndex) ?? '')
              : '';
            const nodePhotoData: NodePhotoData = {
              photos: photos,
              photoManifest: photoManifest
            };
            nodePhotosMap.set(nodeId, nodePhotoData);
          } while (currentNodesResultSet.goToNextRow());
        }
      } finally {
        currentNodesResultSet.close();
      }
      await store.update(nodeValues, nodePredicates);
      const nodePhotoEntries = nodePhotosMap.entries();
      for (const entry of nodePhotoEntries) {
        const nodeId = entry[0];
        const nodePhotoData = entry[1];
        const restorePhotoValues: rdb.ValuesBucket = {
          photos: nodePhotoData.photos,
          photo_manifest: nodePhotoData.photoManifest.length > 0 ? nodePhotoData.photoManifest : nodePhotoData.photos
        };
        const restorePhotoPredicates = new rdb.RdbPredicates('memory_nodes');
        restorePhotoPredicates.equalTo('id', nodeId);
        await store.update(restorePhotoValues, restorePhotoPredicates);
        logger.info(TAG, `[debug] softDeleteTravel after move nodeId=${nodeId}, photos=${nodePhotoData.photos}, photoManifest=${restorePhotoValues.photo_manifest}`);
      }

      const travelValues: rdb.ValuesBucket = {
        deleted_at: now,
        updated_at: now,
        sync_status: 'pending_delete',
        version: (currentTrip.version ?? 1) + 1
      };
      const travelPredicates = new rdb.RdbPredicates(TABLE_NAME);
      travelPredicates.equalTo('id', travelId);
      travelPredicates.equalTo('deleted_at', 0);
      const affectedRows = await store.update(travelValues, travelPredicates);
      logger.info(TAG, `Soft deleted travel ${id}, affected=${affectedRows}`);
      return affectedRows > 0;
    } catch (err) {
      logger.error(TAG, `softDeleteTravel failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  async findLocalIdByCloudId(cloudId: string): Promise<string | null> {
    let resultSet: rdb.ResultSet | undefined = undefined;
    try {
      const store = await this.getRdbStore();
      const predicates = new rdb.RdbPredicates(TABLE_NAME);
      predicates.equalTo('cloud_id', cloudId);
      resultSet = await store.query(predicates);
      if (!resultSet.goToFirstRow()) {
        return null;
      }
      return resultSet.getDouble(resultSet.getColumnIndex('id')).toString();
    } catch (err) {
      logger.error(TAG, `findLocalIdByCloudId failed: ${JSON.stringify(err)}`);
      return null;
    } finally {
      this.closeResultSet(resultSet);
    }
  }

  async updateSyncMetadata(id: string, cloudId: string, syncStatus: string, lastSyncedAt: number): Promise<void> {
    const store = await this.getRdbStore();
    const valueBucket: rdb.ValuesBucket = {
      cloud_id: cloudId,
      sync_status: syncStatus,
      last_synced_at: lastSyncedAt
    };
    const predicates = new rdb.RdbPredicates(TABLE_NAME);
    predicates.equalTo('id', this.toDbId(id, 'travel id'));
    await store.update(valueBucket, predicates);
  }

  async upsertFromCloud(travel: Trip): Promise<void> {
    const store = await this.getRdbStore();
    const predicates = new rdb.RdbPredicates(TABLE_NAME);
    predicates.equalTo('cloud_id', travel.cloudId ?? '');
    const resultSet = await store.query(predicates);
    const valueBucket: rdb.ValuesBucket = {
      name: travel.name,
      cover_image_uri: travel.coverPhoto ?? '',
      start_date: travel.startDate,
      end_date: travel.endDate,
      created_at: travel.createdAt,
      updated_at: travel.updatedAt,
      owner_uid: travel.ownerUid ?? '',
      cloud_id: travel.cloudId ?? '',
      sync_status: 'synced',
      deleted_at: travel.deletedAt ?? 0,
      last_synced_at: Date.now(),
      version: travel.version ?? 1,
      sensitivity: 'S1',
      is_public: travel.isPublic ? 1 : 0,
      replay_style_kit_id: travel.replayStyleKitId ?? '',
      replay_bgm_id: travel.replayBgmId ?? '',
      replay_filter_id: travel.replayFilterId ?? '',
      replay_transition_type: travel.replayTransitionType ?? '',
      replay_enable_ripple: travel.replayEnableRipple ? 1 : 0,
      replay_enable_route_animation: travel.replayEnableRouteAnimation ? 1 : 0,
      replay_enable_blur_overlay: travel.replayEnableBlurOverlay ? 1 : 0
    };

    try {
      if (resultSet.goToFirstRow()) {
        const updatePredicates = new rdb.RdbPredicates(TABLE_NAME);
        updatePredicates.equalTo('cloud_id', travel.cloudId ?? '');
        await store.update(valueBucket, updatePredicates);
      } else {
        await store.insert(TABLE_NAME, valueBucket);
      }
    } finally {
      resultSet.close();
    }
  }

  async markDeletedByCloud(cloudId: string): Promise<void> {
    const store = await this.getRdbStore();
    const valueBucket: rdb.ValuesBucket = {
      deleted_at: Date.now(),
      sync_status: 'synced',
      last_synced_at: Date.now()
    };
    const predicates = new rdb.RdbPredicates(TABLE_NAME);
    predicates.equalTo('cloud_id', cloudId);
    await store.update(valueBucket, predicates);
  }

  async deleteTravel(id: string): Promise<boolean> {
    try {
      const store = await this.getRdbStore();
      const travelId = this.toDbId(id, 'travel id');
      // Explicitly delete child nodes first, then delete travel.
      // This works even if FK cascade is not enabled by runtime.
      const nodePredicates = new rdb.RdbPredicates('memory_nodes');
      nodePredicates.equalTo('travel_id', travelId);
      await store.delete(nodePredicates);

      const travelPredicates = new rdb.RdbPredicates(TABLE_NAME);
      travelPredicates.equalTo('id', travelId);
      const affectedRows = await store.delete(travelPredicates);
      if (affectedRows <= 0) {
        throw new Error(`Travel not found: ${id}`);
      }
      logger.info(TAG, `Deleted travel ${id}, affected=${affectedRows}`);
      return affectedRows > 0;
    } catch (err) {
      logger.error(TAG, `deleteTravel failed: ${JSON.stringify(err)}`);
      return false;
    }
  }
}
