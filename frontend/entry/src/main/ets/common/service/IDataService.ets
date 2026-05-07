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

import type { Trip, MemoryNode, ReplayTripPreferences } from './types';

/**
 * 创建旅行输入参数（不包含 id, createdAt, updatedAt）
 */
export interface CreateTravelInput {
  name: string;
  description?: string;
  coverPhoto?: string;
  isPublic?: boolean;
  startDate: number;
  endDate: number;
  nodeIds: string[];
  totalDistance: number;
  replayStyleKitId?: string;
  replayBgmId?: string;
  replayFilterId?: string;
  replayTransitionType?: string;
  replayEnableRipple?: boolean;
  replayEnableBlurOverlay?: boolean;
}

/**
 * 更新旅行输入参数（所有字段可选）
 */
export interface UpdateTravelInput {
  name?: string;
  description?: string;
  coverPhoto?: string;
  isPublic?: boolean;
  startDate?: number;
  endDate?: number;
  nodeIds?: string[];
  totalDistance?: number;
  replayStyleKitId?: string;
  replayBgmId?: string;
  replayFilterId?: string;
  replayTransitionType?: string;
  replayEnableRipple?: boolean;
  replayEnableBlurOverlay?: boolean;
}

/**
 * 创建节点输入参数（不包含 id, createdAt, updatedAt）
 */
export interface CreateNodeInput {
  travelId: string;
  title: string;
  content: string;
  latitude: number;
  longitude: number;
  poiName: string;
  photos: string[];
  mood: string;
  tags: string[];
  visitedAt?: number;
}

/**
 * 更新节点输入参数（所有字段可选）
 */
export interface UpdateNodeInput {
  travelId?: string;
  title?: string;
  content?: string;
  latitude?: number;
  longitude?: number;
  poiName?: string;
  photos?: string[];
  mood?: string;
  tags?: string[];
  visitedAt?: number;
}

/**
 * 数据服务接口定义
 *
 * 这是 Service Layer 的统一接口，上层（Feature/Pages）通过此接口访问数据
 * 不直接依赖 Repository 层
 *
 * 实现类：
 * - MockDataService: 模拟数据实现（开发阶段使用）
 * - DataServiceStub: 数据库占位实现（返回空数据，不报错）
 * - DataService: 真实数据库实现（待实现）
 */
export interface IDataService {
  // ==================== Travel 相关 ====================

  /**
   * 获取所有旅行
   */
  getAllTravels(): Promise<Trip[]>;

  /**
   * 根据 ID 获取旅行
   */
  getTravelById(travelId: string): Promise<Trip | null>;

  /**
   * 创建新旅行
   */
  createTravel(travel: CreateTravelInput): Promise<Trip>;

  /**
   * 更新旅行
   */
  updateTravel(travelId: string, data: UpdateTravelInput): Promise<Trip>;

  /**
   * 获取单条路线的本地 Replay 配置
   */
  getTripReplayPreferences(travelId: string): Promise<ReplayTripPreferences>;

  /**
   * 仅更新单条路线的本地 Replay 配置，不进入云同步逻辑
   */
  updateTripReplayPreferences(travelId: string, data: ReplayTripPreferences): Promise<ReplayTripPreferences>;

  /**
   * 删除旅行
   */
  deleteTravel(travelId: string): Promise<void>;

  // ==================== MemoryNode 相关 ====================

  /**
   * 根据旅行 ID 获取节点
   */
  getNodesByTravelId(travelId: string): Promise<MemoryNode[]>;

  /**
   * 根据 ID 获取节点
   */
  getNodeById(nodeId: string): Promise<MemoryNode | null>;

  /**
   * 创建新节点
   */
  createNode(node: CreateNodeInput): Promise<MemoryNode>;

  /**
   * 更新节点
   */
  updateNode(nodeId: string, data: UpdateNodeInput): Promise<MemoryNode>;

  /**
   * 删除节点
   */
  deleteNode(nodeId: string): Promise<void>;

  /**
   * 重新排序节点（仅更新本地数据库）
   */
  reorderNodes(travelId: string, nodeIds: string[]): Promise<void>;

  /**
   * 将指定旅行下所有节点的 nodeOrder 同步到云端
   * 应在 TripEditPage 点击保存时调用
   */
  syncNodeOrdersToCloud(travelId: string): Promise<void>;

  /**
   * 修改节点的 visitedAt 后，按 visitedAt ASC 重排该路线所有节点的 nodeOrder，并同步到云
   */
  sortNodesByVisitedAt(travelId: string): Promise<void>;
}
