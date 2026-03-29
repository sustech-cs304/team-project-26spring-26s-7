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
import { MemoryNode } from '../service/types';

const TAG = 'MemoryNodeRepository';

/**
 * 记忆节点数据仓库
 *
 * 功能职责：
 * - 管理 MemoryNode 实体的 CRUD 操作
 * - 封装数据库查询逻辑
 * - 提供业务层面的数据操作接口
 *
 * ---
 * 实现负责人：[队友姓名]
 * 参考文档：references/F1_local_storage_assignment.md
 * ---
 *
 * MemoryNode 实体结构：
 * {
 *   id: string,
 *   travelId: string,
 *   latitude: number,
 *   longitude: number,
 *   poiName: string,
 *   description: string,
 *   address: string,
 *   photos: string[],
 *   tags: string[],
 *   mood?: string,
 *   createdAt: number,
 *   updatedAt: number,
 *   sensitivity: string  // 数据分级标识
 * }
 */

/**
 * 创建节点的输入数据
 */
export interface CreateNodeInput {
  travelId: string;
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
  private rdb: RdbHelper;

  constructor() {
    this.rdb = RdbHelper.getInstance();
  }

  /**
   * 根据旅行 ID 获取所有节点
   * @param travelId 旅行 ID
   * @returns Promise<MemoryNode[]> 节点列表
   */
  async getNodesByTravelId(travelId: string): Promise<MemoryNode[]> {
    logger.debug(TAG, `Getting nodes for travel: ${travelId} (STUB)`);
    // ═══════════════════════════════════════════════════════════════
    // STUB: 占位实现 - 返回空数组
    // 队友完成后请替换为：
    // SELECT * FROM memory_nodes WHERE travel_id = ? ORDER BY "order" ASC
    // ═══════════════════════════════════════════════════════════════
    return Promise.resolve([]);
  }

  /**
   * 根据 ID 获取节点
   * @param id 节点 ID
   * @returns Promise<MemoryNode | undefined> 节点对象
   */
  async getNodeById(id: string): Promise<MemoryNode | undefined> {
    logger.debug(TAG, `Getting node by id: ${id} (STUB)`);
    // ═══════════════════════════════════════════════════════════════
    // STUB: 占位实现 - 返回 undefined
    // 队友完成后请替换为：SELECT * FROM memory_nodes WHERE id = ?
    // ═══════════════════════════════════════════════════════════════
    return Promise.resolve(undefined);
  }

  /**
   * 创建新节点
   * @param node 节点输入数据
   * @returns Promise<string> 创建的节点 ID
   */
  async createNode(node: CreateNodeInput): Promise<string> {
    logger.info(TAG, `Creating node for travel: ${node.travelId} (STUB)`);
    // ═══════════════════════════════════════════════════════════════
    // STUB: 占位实现 - 返回模拟 ID
    // 队友完成后请替换为：INSERT INTO memory_nodes (...) VALUES (...)
    // ═══════════════════════════════════════════════════════════════
    const id = Date.now().toString();
    return Promise.resolve(id);
  }

  /**
   * 更新节点
   * @param id 节点 ID
   * @param node 节点更新数据
   */
  async updateNode(id: string, node: UpdateNodeInput): Promise<boolean> {
    logger.info(TAG, `Updating node: ${id} (STUB)`);
    // ═══════════════════════════════════════════════════════════════
    // STUB: 占位实现 - 返回 false
    // 队友完成后请替换为：UPDATE memory_nodes SET ... WHERE id = ?
    // ═══════════════════════════════════════════════════════════════
    return Promise.resolve(false);
  }

  /**
   * 删除节点
   * @param id 节点 ID
   */
  async deleteNode(id: string): Promise<boolean> {
    logger.info(TAG, `Deleting node: ${id} (STUB)`);
    // ═══════════════════════════════════════════════════════════════
    // STUB: 占位实现 - 返回 false
    // 队友完成后请替换为：DELETE FROM memory_nodes WHERE id = ?
    // ═══════════════════════════════════════════════════════════════
    return Promise.resolve(false);
  }

  /**
   * 重新排序节点
   * @param travelId 旅行 ID
   * @param nodeIds 节点 ID 列表（新顺序）
   */
  async reorderNodes(travelId: string, nodeIds: string[]): Promise<void> {
    logger.info(TAG, `Reordering nodes for travel: ${travelId} (STUB)`);
    // ═══════════════════════════════════════════════════════════════
    // STUB: 占位实现
    // 队友完成后请替换为：批量 UPDATE memory_nodes SET "order" = ? WHERE id = ?
    // ═══════════════════════════════════════════════════════════════
    return Promise.resolve();
  }
}
