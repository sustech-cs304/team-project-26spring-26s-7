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
import { RdbHelper } from './RdbHelper';
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
}

/**
 * 更新节点的输入数据
 */
export interface UpdateNodeInput {
  title?: string;
  latitude?: number;
  longitude?: number;
  poiName?: string;
  description?: string;
  address?: string;
  photos?: string[];
  tags?: string[];
  mood?: string;
}

export class MemoryNodeRepository {
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
      updatedAt: resultSet.getDouble(updatedIdx)
    };
    return node;
  }

  private async getNextNodeOrder(store: rdb.RdbStore, travelId: string): Promise<number> {
    let resultSet: rdb.ResultSet | undefined = undefined;
    try {
      const predicates = new rdb.RdbPredicates(TABLE_NAME);
      predicates.equalTo('travel_id', parseInt(travelId));
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

  async getNodesByTravelId(travelId: string): Promise<MemoryNode[]> {
    let resultSet: rdb.ResultSet | undefined = undefined;
    try {
      const store = await this.getRdbStore();
      const predicates = new rdb.RdbPredicates(TABLE_NAME);
      predicates.equalTo('travel_id', parseInt(travelId));
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
      const predicates = new rdb.RdbPredicates(TABLE_NAME);
      predicates.equalTo('id', parseInt(id));
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
      const nodeOrder = await this.getNextNodeOrder(store, node.travelId);
      const valueBucket: rdb.ValuesBucket = {
        'travel_id': parseInt(node.travelId),
        'latitude': node.latitude,
        'longitude': node.longitude,
        'title': node.title ?? '',
        'poi_name': node.poiName ?? '',
        'description': node.description ?? '',
        'address': node.address ?? '',
        'mood': node.mood ?? '',
        'tags': JSON.stringify(node.tags ?? []),
        'photos': JSON.stringify(node.photos ?? []),
        node_order: nodeOrder,
        'created_at': now,
        'updated_at': now,
        'sensitivity': node.sensitivity ?? 'S2'
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
      const valueBucket: rdb.ValuesBucket = {
        'updated_at': Date.now()
      };
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
      if (node.tags !== undefined) {
        valueBucket['tags'] = JSON.stringify(node.tags);
      }
      if (node.photos !== undefined) {
        valueBucket['photos'] = JSON.stringify(node.photos);
      }
      const predicates = new rdb.RdbPredicates(TABLE_NAME);
      predicates.equalTo('id', parseInt(id));
      const affectedRows = await store.update(valueBucket, predicates);
      logger.info(TAG, `Updated node ${id}, affected=${affectedRows}`);
      return affectedRows > 0;
    } catch (err) {
      logger.error(TAG, `updateNode failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  async deleteNode(id: string): Promise<boolean> {
    try {
      const store = await this.getRdbStore();
      const predicates = new rdb.RdbPredicates(TABLE_NAME);
      predicates.equalTo('id', parseInt(id));
      const affectedRows = await store.delete(predicates);
      logger.info(TAG, `Deleted node ${id}, affected=${affectedRows}`);
      return affectedRows > 0;
    } catch (err) {
      logger.error(TAG, `deleteNode failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  async reorderNodes(travelId: string, nodeIds: string[]): Promise<void> {
    try {
      const store = await this.getRdbStore();
      for (let i = 0; i < nodeIds.length; i++) {
        const valueBucket: rdb.ValuesBucket = {
          node_order: i,
          'updated_at': Date.now()
        };
        const predicates = new rdb.RdbPredicates(TABLE_NAME);
        predicates.equalTo('id', parseInt(nodeIds[i]));
        await store.update(valueBucket, predicates);
      }
      logger.info(TAG, `Reordered ${nodeIds.length} nodes for travel ${travelId}`);
    } catch (err) {
      logger.error(TAG, `reorderNodes failed: ${JSON.stringify(err)}`);
    }
  }
}
