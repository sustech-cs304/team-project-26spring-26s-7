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
import { IDataService, CreateTravelInput, UpdateTravelInput, CreateNodeInput, UpdateNodeInput } from './IDataService';
import { Trip, MemoryNode } from './types';

const TAG = 'DataServiceStub';

/**
 * 数据库占位服务 - 用于数据库功能完成前的过渡
 *
 * 与 MockDataService 的区别：
 * - MockDataService: 返回模拟数据，用于 UI 展示和开发
 * - DataServiceStub: 返回空数据/默认值，用于"数据库未启用"状态
 *
 * 使用场景：
 * - 数据库代码未完成时，避免调用报错
 * - 华为云同步功能未完成时的降级处理
 * - 可选功能的安全降级（如无数据时显示空状态）
 *
 * ---
 * 设计说明：
 * 所有读取操作返回空数组或 null，不报错
 * 所有写入操作记录日志但不执行，返回"成功"假象
 * 这样上层调用不会因异常而崩溃
 */
export class DataServiceStub implements IDataService {
  constructor() {
    logger.warn(TAG, 'DataServiceStub is active - database features are not available');
  }

  // ==================== Travel 相关 ====================

  async getAllTravels(): Promise<Trip[]> {
    logger.debug(TAG, 'getAllTravels() called - returning empty array (STUB)');
    // 返回空数组，让 UI 显示"无数据"状态
    return [];
  }

  async getTravelById(travelId: string): Promise<Trip | null> {
    logger.debug(TAG, `getTravelById(${travelId}) called - returning null (STUB)`);
    return null;
  }

  async createTravel(travel: CreateTravelInput): Promise<Trip> {
    logger.warn(TAG, `createTravel() called but not implemented - returning mock travel (STUB)`);
    // 返回一个 mock 对象，避免上层崩溃
    return {
      id: 'stub-travel-001',
      name: travel.name || '未命名旅行',
      description: '',
      coverPhoto: '',
      startDate: Date.now(),
      endDate: Date.now(),
      nodeIds: [],
      totalDistance: 0,
      createdAt: Date.now(),
      updatedAt: Date.now()
    };
  }

  async updateTravel(travelId: string, data: UpdateTravelInput): Promise<Trip> {
    logger.warn(TAG, `updateTravel(${travelId}) called but not implemented (STUB)`);
    // 返回一个 mock 对象
    return {
      id: travelId,
      name: '',
      description: '',
      coverPhoto: '',
      startDate: 0,
      endDate: 0,
      nodeIds: [],
      totalDistance: 0,
      createdAt: Date.now(),
      updatedAt: Date.now()
    };
  }

  async deleteTravel(travelId: string): Promise<void> {
    logger.warn(TAG, `deleteTravel(${travelId}) called but not implemented (STUB)`);
    // 不执行任何操作，假装成功
  }

  // ==================== MemoryNode 相关 ====================

  async getNodesByTravelId(travelId: string): Promise<MemoryNode[]> {
    logger.debug(TAG, `getNodesByTravelId(${travelId}) called - returning empty array (STUB)`);
    return [];
  }

  async getNodeById(nodeId: string): Promise<MemoryNode | null> {
    logger.debug(TAG, `getNodeById(${nodeId}) called - returning null (STUB)`);
    return null;
  }

  async createNode(node: CreateNodeInput): Promise<MemoryNode> {
    logger.warn(TAG, `createNode() called but not implemented - returning mock node (STUB)`);
    return {
      id: 'stub-node-001',
      travelId: node.travelId,
      title: '',
      content: '',
      latitude: 0,
      longitude: 0,
      poiName: '',
      photos: [],
      mood: '',
      tags: [],
      createdAt: Date.now(),
      updatedAt: Date.now()
    };
  }

  async updateNode(nodeId: string, data: UpdateNodeInput): Promise<MemoryNode> {
    logger.warn(TAG, `updateNode(${nodeId}) called but not implemented (STUB)`);
    return {
      id: nodeId,
      travelId: '',
      title: '',
      content: '',
      latitude: 0,
      longitude: 0,
      poiName: '',
      photos: [],
      mood: '',
      tags: [],
      createdAt: Date.now(),
      updatedAt: Date.now()
    };
  }

  async deleteNode(nodeId: string): Promise<void> {
    logger.warn(TAG, `deleteNode(${nodeId}) called but not implemented (STUB)`);
    // 不执行任何操作
  }

  async getAllNodes(): Promise<MemoryNode[]> {
    logger.debug(TAG, 'getAllNodes() called - returning empty array (STUB)');
    return [];
  }

  async reorderNodes(travelId: string, nodeIds: string[]): Promise<void> {
    logger.warn(TAG, `reorderNodes() called but not implemented (STUB)`);
    // 不执行任何操作
  }
}
