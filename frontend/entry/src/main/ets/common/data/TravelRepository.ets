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
import { RdbHelper } from './RdbHelper';
import { Trip, MemoryNode } from '../service/types';

const TAG = 'TravelRepository';

/**
 * 旅行数据仓库
 *
 * 功能职责：
 * - 管理 Travel 实体的 CRUD 操作
 * - 封装数据库查询逻辑
 * - 提供业务层面的数据操作接口
 *
 * ---
 * 实现负责人：[队友姓名]
 * 参考文档：references/F1_local_storage_assignment.md
 * ---
 *
 * Travel 实体结构：
 * {
 *   id: string,
 *   name: string,
 *   coverImageUri: string,
 *   startDate: number,
 *   endDate: number,
 *   createdAt: number,
 *   updatedAt: number,
 *   sensitivity: string  // 数据分级标识
 * }
 */

/**
 * 创建旅行的输入数据（不包含 id、createdAt、updatedAt）
 */
export interface CreateTravelInput {
  name: string;
  coverImageUri?: string;
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
  startDate?: number;
  endDate?: number;
  sensitivity?: string;
}

export class TravelRepository {
  private rdb: RdbHelper;

  constructor() {
    this.rdb = RdbHelper.getInstance();
  }

  /**
   * 获取所有旅行
   * @returns Promise<Travel[]> 旅行列表
   */
  async getAllTravels(): Promise<Trip[]> {
    logger.info(TAG, 'Getting all travels (STUB - to be implemented)');
    // ═══════════════════════════════════════════════════════════════
    // STUB: 占位实现 - 返回空数组
    // 队友完成后请替换为真实 SQL 查询
    // SELECT * FROM travels ORDER BY created_at DESC
    // ═══════════════════════════════════════════════════════════════
    return Promise.resolve([]);
  }

  /**
   * 根据 ID 获取旅行
   * @param id 旅行 ID
   * @returns Promise<Trip | undefined> 旅行对象
   */
  async getTravelById(id: string): Promise<Trip | undefined> {
    logger.debug(TAG, `Getting travel by id: ${id} (STUB)`);
    // ═══════════════════════════════════════════════════════════════
    // STUB: 占位实现 - 返回 undefined
    // 队友完成后请替换为：SELECT * FROM travels WHERE id = ?
    // ═══════════════════════════════════════════════════════════════
    return Promise.resolve(undefined);
  }

  /**
   * 创建新旅行
   * @param travel 旅行输入数据
   * @returns Promise<string> 创建的旅行 ID
   */
  async createTravel(travel: CreateTravelInput): Promise<string> {
    logger.info(TAG, `Creating travel: ${travel.name} (STUB)`);
    // ═══════════════════════════════════════════════════════════════
    // STUB: 占位实现 - 返回模拟 ID
    // 队友完成后请替换为：INSERT INTO travels (...) VALUES (...) RETURNING id
    // ═══════════════════════════════════════════════════════════════
    const id = Date.now().toString();
    return Promise.resolve(id);
  }

  /**
   * 更新旅行
   * @param travel 旅行对象
   */
  async updateTravel(id: string, travel: UpdateTravelInput): Promise<boolean> {
    logger.info(TAG, `Updating travel: ${id} (STUB)`);
    // ═══════════════════════════════════════════════════════════════
    // STUB: 占位实现 - 返回 false
    // 队友完成后请替换为：UPDATE travels SET ... WHERE id = ?
    // ═══════════════════════════════════════════════════════════════
    return Promise.resolve(false);
  }

  /**
   * 删除旅行（级联删除节点）
   * @param id 旅行 ID
   */
  async deleteTravel(id: string): Promise<boolean> {
    logger.info(TAG, `Deleting travel: ${id} (STUB)`);
    // ═══════════════════════════════════════════════════════════════
    // STUB: 占位实现 - 返回 false
    // 队友完成后请替换为：
    // 1. DELETE FROM memory_nodes WHERE travel_id = ?
    // 2. DELETE FROM travels WHERE id = ?
    // ═══════════════════════════════════════════════════════════════
    return Promise.resolve(false);
  }
}
