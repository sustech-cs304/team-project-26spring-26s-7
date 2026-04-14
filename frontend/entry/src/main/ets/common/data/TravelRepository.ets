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
    if (!Number.isInteger(parsed) || parsed <= 0) {
      throw new Error(`Invalid ${fieldName}: ${id}`);
    }
    return parsed;
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
      updatedAt: resultSet.getDouble(updatedIdx)
    };
    return trip;
  }

  async getAllTravels(): Promise<Trip[]> {
    let resultSet: rdb.ResultSet | undefined = undefined;
    try {
      const store = await this.getRdbStore();
      const predicates = new rdb.RdbPredicates(TABLE_NAME);
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

  async getTravelById(id: string): Promise<Trip | undefined> {
    let resultSet: rdb.ResultSet | undefined = undefined;
    try {
      const store = await this.getRdbStore();
      const predicates = new rdb.RdbPredicates(TABLE_NAME);
      predicates.equalTo('id', this.toDbId(id, 'travel id'));
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
      const valueBucket: rdb.ValuesBucket = {
        'name': travel.name,
        'cover_image_uri': travel.coverImageUri ?? '',
        'is_public': travel.isPublic ? 1 : 0,
        'start_date': travel.startDate,
        'end_date': travel.endDate,
        'created_at': now,
        'updated_at': now,
        'sensitivity': travel.sensitivity ?? 'S1'
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
      const valueBucket: rdb.ValuesBucket = {
        'updated_at': Date.now()
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
