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
import { TravelRepository } from './TravelRepository';
import type { MemoryNode } from '../service/types';

const TAG = 'MemoryNodeRepository';
const TABLE_NAME = 'memory_nodes';
const NODE_ORDER_COLUMN = 'node_order';

/**
 * 创建节点的输入数据
 */
export interface CreateNodeInput {
  travelId: string;
  title?: string;
  latitude: number;
  longitude: number;
  poiName?: string;
  description?: string;
  address?: string;
  photos?: string[];
  tags?: string[];
  mood?: string;
  sensitivity?: string;
  visitedAt?: number;
}

/**
 * 更新节点的输入数据
 */
export interface UpdateNodeInput {
  travelId?: string;
  title?: string;
  latitude?: number;
  longitude?: number;
  poiName?: string;
  description?: string;
  address?: string;
  photos?: string[];
  tags?: string[];
  mood?: string;
  visitedAt?: number;
}

export interface SoftDeleteResult {
  success: boolean;
  travelId: string;
}

export class MemoryNodeRepository {
  private rdbHelper: RdbHelper;

  // Test-overridable hooks. Reassigned by integration tests
  // (see frontend/entry/src/test/integration/data/MemoryNodeRepository.test.ets).
  // Default values let production go through the real rdb / AuthService / TravelRepository.
  static ownerUidProvider: (() => Promise<string>) | null = null;
  static predicatesFactory: (table: string) => Object = (table: string): Object => {
    return new rdb.RdbPredicates(table);
  };
  static travelRepositoryFactory: (() => TravelRepository) | null = null;
  static nowProvider: (() => number) | null = null;

  /** Reset all static test hooks back to defaults. */
  static resetTestingHooks(): void {
    MemoryNodeRepository.ownerUidProvider = null;
    MemoryNodeRepository.predicatesFactory = (table: string): Object => {
      return new rdb.RdbPredicates(table);
    };
    MemoryNodeRepository.travelRepositoryFactory = null;
    MemoryNodeRepository.nowProvider = null;
  }

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

  private parseJsonArray(jsonStr: string): string[] {
    if (!jsonStr || jsonStr.length === 0) {
      return [];
    }
    try {
      const parsed: Object = JSON.parse(jsonStr) as Object;
      if (Array.isArray(parsed)) {
        const values = parsed as Object[];
        const result: string[] = [];
        for (let i = 0; i < values.length; i++) {
          const value = values[i];
          if (typeof value === 'string') {
            result.push(value);
          }
        }
        return result;
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  private mapResultSetToNode(resultSet: rdb.ResultSet): MemoryNode {
    const idIdx = resultSet.getColumnIndex('id');
    const travelIdIdx = resultSet.getColumnIndex('travel_id');
    const latIdx = resultSet.getColumnIndex('latitude');
    const lngIdx = resultSet.getColumnIndex('longitude');
    const titleIdx = resultSet.getColumnIndex('title');
    const poiIdx = resultSet.getColumnIndex('poi_name');
    const descIdx = resultSet.getColumnIndex('description');
    const moodIdx = resultSet.getColumnIndex('mood');
    const tagsIdx = resultSet.getColumnIndex('tags');
    const photosIdx = resultSet.getColumnIndex('photos');
    const createdIdx = resultSet.getColumnIndex('created_at');
    const updatedIdx = resultSet.getColumnIndex('updated_at');
    const nodeOrderIdx = resultSet.getColumnIndex(NODE_ORDER_COLUMN);
    const ownerUidIdx = resultSet.getColumnIndex('owner_uid');
    const cloudIdIdx = resultSet.getColumnIndex('cloud_id');
    const syncStatusIdx = resultSet.getColumnIndex('sync_status');
    const deletedAtIdx = resultSet.getColumnIndex('deleted_at');
    const lastSyncedAtIdx = resultSet.getColumnIndex('last_synced_at');
    const versionIdx = resultSet.getColumnIndex('version');
    const photoManifestIdx = resultSet.getColumnIndex('photo_manifest');
    const visitedAtIdx = resultSet.getColumnIndex('visited_at');

    const title = titleIdx >= 0 ? (resultSet.getString(titleIdx) ?? '') : '';
    const poiName = resultSet.getString(poiIdx) ?? '';
    const description = resultSet.getString(descIdx) ?? '';

    const node: MemoryNode = {
      id: resultSet.getDouble(idIdx).toString(),
      travelId: resultSet.getDouble(travelIdIdx).toString(),
      title: title.length > 0 ? title : poiName,
      content: description,
      latitude: resultSet.getDouble(latIdx),
      longitude: resultSet.getDouble(lngIdx),
      poiName: poiName,
      photos: this.parseJsonArray(resultSet.getString(photosIdx) ?? ''),
      mood: resultSet.getString(moodIdx) ?? '',
      tags: this.parseJsonArray(resultSet.getString(tagsIdx) ?? ''),
      createdAt: resultSet.getDouble(createdIdx),
      updatedAt: resultSet.getDouble(updatedIdx),
      nodeOrder: nodeOrderIdx >= 0 ? resultSet.getDouble(nodeOrderIdx) : 0,
      ownerUid: ownerUidIdx >= 0 ? (resultSet.getString(ownerUidIdx) ?? '') : '',
      cloudId: cloudIdIdx >= 0 ? (resultSet.getString(cloudIdIdx) ?? '') : '',
      syncStatus: syncStatusIdx >= 0 ? (resultSet.getString(syncStatusIdx) ?? 'local_only') : 'local_only',
      deletedAt: deletedAtIdx >= 0 ? resultSet.getDouble(deletedAtIdx) : 0,
      lastSyncedAt: lastSyncedAtIdx >= 0 ? resultSet.getDouble(lastSyncedAtIdx) : 0,
      version: versionIdx >= 0 ? resultSet.getDouble(versionIdx) : 1,
      photoManifest: photoManifestIdx >= 0 ? (resultSet.getString(photoManifestIdx) ?? '') : '',
      visitedAt: visitedAtIdx >= 0 ? resultSet.getDouble(visitedAtIdx) : 0
    };
    return node;
  }

  private async getNextNodeOrder(store: rdb.RdbStore, travelId: string): Promise<number> {
    let resultSet: rdb.ResultSet | undefined = undefined;
    try {
      const ownerUid = await this.getOwnerUid();
      const predicates = new rdb.RdbPredicates(TABLE_NAME);
      predicates.equalTo('travel_id', this.toDbId(travelId, 'travel id'));
      predicates.equalTo('owner_uid', ownerUid);
      predicates.equalTo('deleted_at', 0);
      predicates.orderByDesc(NODE_ORDER_COLUMN);
      resultSet = await store.query(predicates);
      if (resultSet.goToFirstRow()) {
        const orderIndex = resultSet.getColumnIndex(NODE_ORDER_COLUMN);
        return resultSet.getDouble(orderIndex) + 1;
      }
      return 0;
    } catch (err) {
      logger.warn(TAG, `Failed to calculate node order: ${JSON.stringify(err)}`);
      return 0;
    } finally {
      this.closeResultSet(resultSet);
    }
  }

  async getAllNodesIncludingDeleted(): Promise<MemoryNode[]> {
    let resultSet: rdb.ResultSet | undefined = undefined;
    try {
      const store = await this.getRdbStore();
      const ownerUid = await this.getOwnerUid();
      const predicates = new rdb.RdbPredicates(TABLE_NAME);
      predicates.equalTo('owner_uid', ownerUid);
      predicates.orderByAsc(NODE_ORDER_COLUMN);
      resultSet = await store.query(predicates);
      const nodes: MemoryNode[] = [];
      if (resultSet.goToFirstRow()) {
        do {
          nodes.push(this.mapResultSetToNode(resultSet));
        } while (resultSet.goToNextRow());
      }
      logger.info(TAG, `Loaded ${nodes.length} nodes including deleted`);
      return nodes;
    } catch (err) {
      logger.error(TAG, `getAllNodesIncludingDeleted failed: ${JSON.stringify(err)}`);
      return [];
    } finally {
      this.closeResultSet(resultSet);
    }
  }

  async getNodesByTravelId(travelId: string): Promise<MemoryNode[]> {
    let resultSet: rdb.ResultSet | undefined = undefined;
    try {
      const store = await this.getRdbStore();
      const ownerUid = await this.getOwnerUid();
      const predicates = new rdb.RdbPredicates(TABLE_NAME);
      predicates.equalTo('travel_id', this.toDbId(travelId, 'travel id'));
      predicates.equalTo('owner_uid', ownerUid);
      predicates.equalTo('deleted_at', 0);
      predicates.orderByAsc(NODE_ORDER_COLUMN);
      resultSet = await store.query(predicates);
      const nodes: MemoryNode[] = [];
      if (resultSet.goToFirstRow()) {
        do {
          nodes.push(this.mapResultSetToNode(resultSet));
        } while (resultSet.goToNextRow());
      }
      logger.info(TAG, `Loaded ${nodes.length} nodes for travel ${travelId}`);
      return nodes;
    } catch (err) {
      logger.error(TAG, `getNodesByTravelId failed: ${JSON.stringify(err)}`);
      return [];
    } finally {
      this.closeResultSet(resultSet);
    }
  }

  async getNodeById(id: string): Promise<MemoryNode | undefined> {
    let resultSet: rdb.ResultSet | undefined = undefined;
    try {
      const store = await this.getRdbStore();
      const ownerUid = await this.getOwnerUid();
      const predicates = new rdb.RdbPredicates(TABLE_NAME);
      predicates.equalTo('id', this.toDbId(id, 'node id'));
      predicates.equalTo('owner_uid', ownerUid);
      predicates.equalTo('deleted_at', 0);
      resultSet = await store.query(predicates);
      let node: MemoryNode | undefined = undefined;
      if (resultSet.goToFirstRow()) {
        node = this.mapResultSetToNode(resultSet);
      }
      return node;
    } catch (err) {
      logger.error(TAG, `getNodeById failed: ${JSON.stringify(err)}`);
      return undefined;
    } finally {
      this.closeResultSet(resultSet);
    }
  }

  async createNode(node: CreateNodeInput): Promise<string> {
    try {
      const store = await this.getRdbStore();
      const now = Date.now();
      const ownerUid = await this.getOwnerUid();
      if (node.travelId !== TravelSpecialValues.UNCATEGORIZED_TRAVEL_ID) {
        const parentTravel = await new TravelRepository().getTravelById(node.travelId);
        if (!parentTravel || parentTravel.ownerUid !== ownerUid) {
          throw new Error(`Travel not found or not owned by current user: ${node.travelId}`);
        }
      }
      const nodeOrder = await this.getNextNodeOrder(store, node.travelId);
      const valueBucket: rdb.ValuesBucket = {
        'travel_id': this.toDbId(node.travelId, 'travel id'),
        'latitude': node.latitude,
        'longitude': node.longitude,
        'title': node.title ?? '',
        'poi_name': node.poiName ?? '',
        'description': node.description ?? '',
        'address': node.address ?? '',
        'mood': node.mood ?? '',
        'tags': JSON.stringify(node.tags ?? []),
        'photos': JSON.stringify(node.photos ?? []),
        'photo_manifest': '[]',
        node_order: nodeOrder,
        'created_at': now,
        'updated_at': now,
        'sensitivity': node.sensitivity ?? 'S2',
        'visited_at': node.visitedAt ?? now,
        'owner_uid': ownerUid,
        'cloud_id': '',
        'sync_status': 'pending_create',
        'deleted_at': 0,
        'last_synced_at': 0,
        'version': 1
      };
      const rowId = await store.insert(TABLE_NAME, valueBucket);
      logger.info(TAG, `Created node for travel ${node.travelId}, id=${rowId}`);
      return rowId.toString();
    } catch (err) {
      logger.error(TAG, `createNode failed: ${JSON.stringify(err)}`);
      throw this.toError(err);
    }
  }

  async updateNode(id: string, node: UpdateNodeInput): Promise<boolean> {
    try {
      const store = await this.getRdbStore();
      const currentNode = await this.getNodeById(id);
      if (!currentNode) {
        return false;
      }
      const ownerUid = currentNode.ownerUid;
      const valueBucket: rdb.ValuesBucket = {
        'updated_at': Date.now(),
        'sync_status': currentNode.cloudId && currentNode.cloudId.length > 0 ? 'pending_update' : 'pending_create',
        'version': (currentNode.version ?? 1) + 1
      };
      if (node.travelId !== undefined) {
        if (node.travelId !== TravelSpecialValues.UNCATEGORIZED_TRAVEL_ID) {
          const parentTravel = await new TravelRepository().getTravelById(node.travelId);
          if (!parentTravel || parentTravel.ownerUid !== ownerUid) {
            return false;
          }
        }
        valueBucket['travel_id'] = this.toDbId(node.travelId, 'travel id');
        if (node.travelId !== currentNode.travelId) {
          valueBucket[NODE_ORDER_COLUMN] = await this.getNextNodeOrder(store, node.travelId);
          valueBucket['photos'] = JSON.stringify(currentNode.photos ?? []);
          valueBucket['photo_manifest'] = currentNode.photoManifest ?? '[]';
        }
      }
      if (node.title !== undefined) {
        valueBucket['title'] = node.title;
      }
      if (node.latitude !== undefined) {
        valueBucket['latitude'] = node.latitude;
      }
      if (node.longitude !== undefined) {
        valueBucket['longitude'] = node.longitude;
      }
      if (node.poiName !== undefined) {
        valueBucket['poi_name'] = node.poiName;
      }
      if (node.description !== undefined) {
        valueBucket['description'] = node.description;
      }
      if (node.address !== undefined) {
        valueBucket['address'] = node.address;
      }
      if (node.mood !== undefined) {
        valueBucket['mood'] = node.mood;
      }
      if (node.visitedAt !== undefined) {
        valueBucket['visited_at'] = node.visitedAt;
      }
      if (node.tags !== undefined) {
        valueBucket['tags'] = JSON.stringify(node.tags);
      }
      if (node.photos !== undefined) {
        valueBucket['photos'] = JSON.stringify(node.photos);
        // 不再把 photo_manifest 重置成 '[]'：跨 travel 时如果 manifest 被这条 reset 抹掉，
        // 紧接着 sortNodesByVisitedAt → syncNodeOrdersToCloud 会用 sibling.travelId（新 travel）
        // 兜底 buildPhotoManifest 算出错的路径并入队。
        // 现在的契约：调用方（RdbDataService.updateNode）在 photos 变更后立即用 home dir 重算
        // manifest 并通过 updatePhotoManifest 显式写回，确保同一事务结束时 manifest 始终正确。
      }
      const predicates = new rdb.RdbPredicates(TABLE_NAME);
      predicates.equalTo('id', this.toDbId(id, 'node id'));
      predicates.equalTo('owner_uid', ownerUid);
      const affectedRows = await store.update(valueBucket, predicates);
      logger.info(TAG, `Updated node ${id}, affected=${affectedRows}`);
      return affectedRows > 0;
    } catch (err) {
      logger.error(TAG, `updateNode failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  async moveNodesToTravel(oldTravelId: string, newTravelId: string): Promise<number> {
    try {
      const store = await this.getRdbStore();
      const now = Date.now();
      const ownerUid = await this.getOwnerUid();
      if (newTravelId !== TravelSpecialValues.UNCATEGORIZED_TRAVEL_ID) {
        const targetTravel = await new TravelRepository().getTravelById(newTravelId);
        if (!targetTravel || targetTravel.ownerUid !== ownerUid) {
          return 0;
        }
      }
      const currentNodes = await this.getNodesByTravelId(oldTravelId);
      let movedCount = 0;
      let nextNodeOrder = await this.getNextNodeOrder(store, newTravelId);

      for (let i = 0; i < currentNodes.length; i++) {
        const currentNode = currentNodes[i];
        const valueBucket: rdb.ValuesBucket = {
          'travel_id': this.toDbId(newTravelId, 'travel id'),
          'updated_at': now,
          'sync_status': currentNode.cloudId && currentNode.cloudId.length > 0 ? 'pending_update' : 'pending_create',
          'version': (currentNode.version ?? 1) + 1
        };
        valueBucket[NODE_ORDER_COLUMN] = nextNodeOrder;
        const predicates = new rdb.RdbPredicates(TABLE_NAME);
        predicates.equalTo('id', this.toDbId(currentNode.id, 'node id'));
        predicates.equalTo('owner_uid', ownerUid);
        predicates.equalTo('deleted_at', 0);
        const affectedRows = await store.update(valueBucket, predicates);
        if (affectedRows > 0) {
          movedCount += affectedRows;
          nextNodeOrder += 1;
        }
      }

      logger.info(TAG, `Moved ${movedCount} nodes from travel ${oldTravelId} to ${newTravelId}`);
      return movedCount;
    } catch (err) {
      logger.error(TAG, `moveNodesToTravel failed: ${JSON.stringify(err)}`);
      return 0;
    }
  }

  async softDeleteNode(id: string): Promise<SoftDeleteResult> {
    try {
      const store = await this.getRdbStore();
      const currentNode = await this.getNodeById(id);
      if (!currentNode) {
        const fail: SoftDeleteResult = { success: false, travelId: '' };
        return fail;
      }
      const travelId = currentNode.travelId;
      const valueBucket: rdb.ValuesBucket = {
        'deleted_at': Date.now(),
        'updated_at': Date.now(),
        'sync_status': 'pending_delete',
        'version': (currentNode.version ?? 1) + 1
      };
      const predicates = new rdb.RdbPredicates(TABLE_NAME);
      predicates.equalTo('id', this.toDbId(id, 'node id'));
      predicates.equalTo('owner_uid', currentNode.ownerUid);
      predicates.equalTo('deleted_at', 0);
      const affectedRows = await store.update(valueBucket, predicates);
      logger.info(TAG, `Soft deleted node ${id}, affected=${affectedRows}`);
      const ok: SoftDeleteResult = { success: affectedRows > 0, travelId: travelId };
      return ok;
    } catch (err) {
      logger.error(TAG, `softDeleteNode failed: ${JSON.stringify(err)}`);
      const fail: SoftDeleteResult = { success: false, travelId: '' };
      return fail;
    }
  }

  async findLocalIdByCloudId(cloudId: string): Promise<string | null> {
    let resultSet: rdb.ResultSet | undefined = undefined;
    try {
      const store = await this.getRdbStore();
      const ownerUid = await this.getOwnerUid();
      const predicates = new rdb.RdbPredicates(TABLE_NAME);
      predicates.equalTo('cloud_id', cloudId);
      predicates.equalTo('owner_uid', ownerUid);
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
    predicates.equalTo('id', this.toDbId(id, 'node id'));
    predicates.equalTo('owner_uid', await this.getOwnerUid());
    await store.update(valueBucket, predicates);
  }

  async updatePhotoManifest(id: string, manifest: string): Promise<void> {
    const store = await this.getRdbStore();
    const valueBucket: rdb.ValuesBucket = {
      photo_manifest: manifest
    };
    const predicates = new rdb.RdbPredicates(TABLE_NAME);
    predicates.equalTo('id', this.toDbId(id, 'node id'));
    predicates.equalTo('owner_uid', await this.getOwnerUid());
    await store.update(valueBucket, predicates);
  }

  async upsertFromCloud(node: MemoryNode): Promise<void> {
    const store = await this.getRdbStore();
    const ownerUid = node.ownerUid ?? '';
    const predicates = new rdb.RdbPredicates(TABLE_NAME);
    predicates.equalTo('cloud_id', node.cloudId ?? '');
    predicates.equalTo('owner_uid', ownerUid);
    const resultSet = await store.query(predicates);
    const valueBucket: rdb.ValuesBucket = {
      travel_id: this.toDbId(node.travelId, 'travel id'),
      latitude: node.latitude,
      longitude: node.longitude,
      title: node.title,
      poi_name: node.poiName,
      description: node.content,
      mood: node.mood,
      tags: JSON.stringify(node.tags),
      photos: JSON.stringify(node.photos),
      photo_manifest: node.photoManifest && node.photoManifest.length > 2 ? node.photoManifest : '[]',
      node_order: node.nodeOrder ?? 0,
      created_at: node.createdAt,
      updated_at: node.updatedAt,
      owner_uid: node.ownerUid ?? '',
      cloud_id: node.cloudId ?? '',
      sync_status: 'synced',
      deleted_at: node.deletedAt ?? 0,
      last_synced_at: Date.now(),
      version: node.version ?? 1,
      sensitivity: 'S2',
      visited_at: node.visitedAt ?? 0
    };

    try {
      if (resultSet.goToFirstRow()) {
        logger.info(
          TAG,
          `[debug] upsertFromCloud update cloudId=${node.cloudId ?? ''}, travelId=${node.travelId}, deletedAt=${node.deletedAt ?? 0}, photoCount=${node.photos.length}, photoManifest=${node.photoManifest ?? ''}`
        );
        const updatePredicates = new rdb.RdbPredicates(TABLE_NAME);
        updatePredicates.equalTo('cloud_id', node.cloudId ?? '');
        updatePredicates.equalTo('owner_uid', ownerUid);
        await store.update(valueBucket, updatePredicates);
      } else {
        logger.info(
          TAG,
          `[debug] upsertFromCloud insert cloudId=${node.cloudId ?? ''}, travelId=${node.travelId}, deletedAt=${node.deletedAt ?? 0}, photoCount=${node.photos.length}, photoManifest=${node.photoManifest ?? ''}`
        );
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
    predicates.equalTo('owner_uid', await this.getOwnerUid());
    await store.update(valueBucket, predicates);
  }

  async deleteNode(id: string): Promise<boolean> {
    try {
      const store = await this.getRdbStore();
      const ownerUid = await this.getOwnerUid();
      // Read travelId before deleting so we can renormalize afterwards
      let travelId: string | undefined = undefined;
      let lookupResultSet: rdb.ResultSet | undefined = undefined;
      try {
        const lookupPredicates = new rdb.RdbPredicates(TABLE_NAME);
        lookupPredicates.equalTo('id', this.toDbId(id, 'node id'));
        lookupPredicates.equalTo('owner_uid', ownerUid);
        lookupResultSet = await store.query(lookupPredicates);
        if (lookupResultSet.goToFirstRow()) {
          travelId = lookupResultSet.getDouble(lookupResultSet.getColumnIndex('travel_id')).toString();
        }
      } finally {
        this.closeResultSet(lookupResultSet);
      }

      const predicates = new rdb.RdbPredicates(TABLE_NAME);
      predicates.equalTo('id', this.toDbId(id, 'node id'));
      predicates.equalTo('owner_uid', ownerUid);
      const affectedRows = await store.delete(predicates);
      logger.info(TAG, `Deleted node ${id}, affected=${affectedRows}`);
      if (affectedRows > 0 && travelId !== undefined) {
        const siblings = await this.getNodesByTravelId(travelId);
        const siblingIds = siblings.map((n: MemoryNode) => n.id);
        if (siblingIds.length > 0) {
          await this.reorderNodes(travelId, siblingIds);
        }
      }
      return affectedRows > 0;
    } catch (err) {
      logger.error(TAG, `deleteNode failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  async reorderNodes(travelId: string, nodeIds: string[]): Promise<void> {
    try {
      const store = await this.getRdbStore();
      const ownerUid = await this.getOwnerUid();
      for (let i = 0; i < nodeIds.length; i++) {
        const valueBucket: rdb.ValuesBucket = {
          node_order: i,
          'updated_at': Date.now(),
          'sync_status': 'pending_reorder'
        };
        const predicates = new rdb.RdbPredicates(TABLE_NAME);
        predicates.equalTo('id', this.toDbId(nodeIds[i], 'node id'));
        predicates.equalTo('owner_uid', ownerUid);
        await store.update(valueBucket, predicates);
      }
      logger.info(TAG, `Reordered ${nodeIds.length} nodes for travel ${travelId}`);
    } catch (err) {
      logger.error(TAG, `reorderNodes failed: ${JSON.stringify(err)}`);
    }
  }
}
