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

const TAG = 'MockDataService';

/**
 * Mock 数据服务 - 用于开发和测试阶段
 * 提供模拟数据，不依赖真实数据库
 *
 * 使用场景：
 * - UI 开发阶段（数据库未完成时）
 * - Previewer 预览
 * - 单元测试
 */
export class MockDataService implements IDataService {
  private travels: Trip[] = [];

  constructor() {
    this.initMockData();
  }

  /**
   * 初始化模拟数据
   */
  private initMockData(): void {
    const now = Date.now();
    const dayMs = 86400000; // 一天的毫秒数

    this.travels = [
      {
        id: 'travel-001',
        name: '深圳三日游',
        description: '春天的深圳美景，与家人一起游玩',
        coverPhoto: '',
        startDate: now - dayMs * 7,
        endDate: now - dayMs * 5,
        nodeIds: ['node-001', 'node-002', 'node-003'],
        totalDistance: 128,
        createdAt: now - dayMs * 10,
        updatedAt: now - dayMs * 5
      },
      {
        id: 'travel-002',
        name: '广州周末游',
        description: '周末短途旅行',
        coverPhoto: '',
        startDate: now - dayMs * 30,
        endDate: now - dayMs * 29,
        nodeIds: ['node-004', 'node-005'],
        totalDistance: 45,
        createdAt: now - dayMs * 35,
        updatedAt: now - dayMs * 29
      }
    ];

    logger.info(TAG, `Mock data initialized: ${this.travels.length} travels`);
  }

  // ==================== Travel CRUD ====================

  async getAllTravels(): Promise<Trip[]> {
    logger.debug(TAG, 'Getting all travels');
    return this.travels;
  }

  async getTravelById(travelId: string): Promise<Trip | null> {
    logger.debug(TAG, `Getting travel by id: ${travelId}`);
    const travel = this.travels.find(t => t.id === travelId);
    return travel || null;
  }

  async createTravel(travel: CreateTravelInput): Promise<Trip> {
    const now = Date.now();
    const newTravel: Trip = {
      id: this.generateUUID(),
      name: travel.name,
      description: travel.description,
      coverPhoto: travel.coverPhoto,
      startDate: travel.startDate,
      endDate: travel.endDate,
      nodeIds: travel.nodeIds,
      totalDistance: travel.totalDistance,
      createdAt: now,
      updatedAt: now
    };
    this.travels.push(newTravel);
    logger.info(TAG, `Travel created: ${newTravel.id}`);
    return newTravel;
  }

  async updateTravel(travelId: string, data: UpdateTravelInput): Promise<Trip> {
    const index = this.travels.findIndex(t => t.id === travelId);
    if (index === -1) {
      throw new Error(`Travel not found: ${travelId}`);
    }

    const current = this.travels[index];
    if (data.name !== undefined) current.name = data.name;
    if (data.description !== undefined) current.description = data.description;
    if (data.coverPhoto !== undefined) current.coverPhoto = data.coverPhoto;
    if (data.startDate !== undefined) current.startDate = data.startDate;
    if (data.endDate !== undefined) current.endDate = data.endDate;
    if (data.nodeIds !== undefined) current.nodeIds = data.nodeIds;
    if (data.totalDistance !== undefined) current.totalDistance = data.totalDistance;
    current.updatedAt = Date.now();

    logger.info(TAG, `Travel updated: ${travelId}`);
    return current;
  }

  async deleteTravel(travelId: string): Promise<void> {
    const index = this.travels.findIndex(t => t.id === travelId);
    if (index === -1) {
      throw new Error(`Travel not found: ${travelId}`);
    }

    this.travels.splice(index, 1);
    logger.info(TAG, `Travel deleted: ${travelId}`);
  }

  // ==================== MemoryNode CRUD ====================

  async getNodesByTravelId(travelId: string): Promise<MemoryNode[]> {
    logger.debug(TAG, `Getting nodes for travel: ${travelId}`);
    const travel = this.travels.find(t => t.id === travelId);
    if (!travel) {
      return [];
    }

    const nodes: MemoryNode[] = [];
    for (let i = 0; i < travel.nodeIds.length; i++) {
      const id = travel.nodeIds[i];
      nodes.push({
        id: id,
        travelId: travelId,
        title: `节点 ${i + 1}`,
        content: '这是一个模拟的记忆节点',
        latitude: 22.5 + i * 0.01,
        longitude: 113.9 + i * 0.01,
        poiName: `POI ${i + 1}`,
        photos: [],
        mood: 'happy',
        tags: ['mock'],
        createdAt: Date.now(),
        updatedAt: Date.now()
      });
    }
    return nodes;
  }

  async getNodeById(nodeId: string): Promise<MemoryNode | null> {
    for (const travel of this.travels) {
      if (travel.nodeIds.includes(nodeId)) {
        return {
          id: nodeId,
          travelId: travel.id,
          title: `节点 ${nodeId}`,
          content: '这是一个模拟的记忆节点',
          latitude: 22.5,
          longitude: 113.9,
          poiName: '模拟 POI',
          photos: [],
          mood: 'happy',
          tags: ['mock'],
          createdAt: Date.now(),
          updatedAt: Date.now()
        };
      }
    }
    return null;
  }

  async createNode(node: CreateNodeInput): Promise<MemoryNode> {
    const travel = this.travels.find(t => t.id === node.travelId);
    if (!travel) {
      throw new Error(`Travel not found: ${node.travelId}`);
    }

    const now = Date.now();
    const newNode: MemoryNode = {
      id: this.generateUUID(),
      travelId: node.travelId,
      title: node.title,
      content: node.content,
      latitude: node.latitude,
      longitude: node.longitude,
      poiName: node.poiName,
      photos: node.photos,
      mood: node.mood,
      tags: node.tags,
      createdAt: now,
      updatedAt: now
    };

    travel.nodeIds.push(newNode.id);
    travel.updatedAt = now;

    logger.info(TAG, `Node created: ${newNode.id}`);
    return newNode;
  }

  async updateNode(nodeId: string, data: UpdateNodeInput): Promise<MemoryNode> {
    for (const travel of this.travels) {
      const nodeIndex = travel.nodeIds.findIndex(id => id === nodeId);
      if (nodeIndex !== -1) {
        // Mock 模式下简化处理
        logger.info(TAG, `Node updated: ${nodeId}`);
        return await this.getNodeById(nodeId) as MemoryNode;
      }
    }
    throw new Error(`Node not found: ${nodeId}`);
  }

  async deleteNode(nodeId: string): Promise<void> {
    for (const travel of this.travels) {
      const nodeIndex = travel.nodeIds.findIndex(id => id === nodeId);
      if (nodeIndex !== -1) {
        travel.nodeIds.splice(nodeIndex, 1);
        travel.updatedAt = Date.now();
        logger.info(TAG, `Node deleted: ${nodeId}`);
        return;
      }
    }
    throw new Error(`Node not found: ${nodeId}`);
  }

  async reorderNodes(travelId: string, nodeIds: string[]): Promise<void> {
    const travel = this.travels.find(t => t.id === travelId);
    if (!travel) {
      throw new Error(`Travel not found: ${travelId}`);
    }
    travel.nodeIds = nodeIds;
    travel.updatedAt = Date.now();
    logger.info(TAG, `Nodes reordered for travel: ${travelId}`);
  }

  // ==================== 工具方法 ====================

  private generateUUID(): string {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
      const r = Math.random() * 16 | 0;
      return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
    });
  }
}
