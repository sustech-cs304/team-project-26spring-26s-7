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
import { TravelRepository } from '../data/TravelRepository';
import { MemoryNodeRepository } from '../data/MemoryNodeRepository';
import type { IDataService, CreateTravelInput, UpdateTravelInput, CreateNodeInput, UpdateNodeInput } from './IDataService';
import type { Trip, MemoryNode } from './types';
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

  constructor() {
    this.travelRepo = new TravelRepository();
    this.nodeRepo = new MemoryNodeRepository();
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
          startDate: trips[i].startDate,
          endDate: trips[i].endDate,
          nodeIds: nodeIds,
          totalDistance: this.calculateTotalDistance(nodes),
          createdAt: trips[i].createdAt,
          updatedAt: trips[i].updatedAt
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
        startDate: trip.startDate,
        endDate: trip.endDate,
        nodeIds: nodeIds,
        totalDistance: this.calculateTotalDistance(nodes),
        createdAt: trip.createdAt,
        updatedAt: trip.updatedAt
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
      startDate: travel.startDate,
      endDate: travel.endDate
    };
    const id = await this.travelRepo.createTravel(repoInput);
    const created = await this.getTravelById(id);
    if (!created) {
      throw new Error('Failed to retrieve created travel');
    }
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
    if (data.startDate !== undefined) {
      repoInput.startDate = data.startDate;
    }
    if (data.endDate !== undefined) {
      repoInput.endDate = data.endDate;
    }
    await this.travelRepo.updateTravel(travelId, repoInput);
    const updated = await this.getTravelById(travelId);
    if (!updated) {
      throw new Error('Failed to retrieve updated travel');
    }
    return updated;
  }

  async deleteTravel(travelId: string): Promise<void> {
    await this.travelRepo.deleteTravel(travelId);
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
    return created;
  }

  async updateNode(nodeId: string, data: UpdateNodeInput): Promise<MemoryNode> {
    // 如果更新了照片，先获取旧照片列表以便清理
    let oldPhotos: string[] = [];
    if (data.photos !== undefined) {
      const oldNode = await this.nodeRepo.getNodeById(nodeId);
      if (oldNode) {
        oldPhotos = [...oldNode.photos];
      }
    }

    const repoInput: RepoUpdateNodeInput = {};
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
    await this.nodeRepo.updateNode(nodeId, repoInput);

    // 清理被移除的照片
    if (data.photos !== undefined) {
      const removedPhotos = oldPhotos.filter((photo: string) => !data.photos!.includes(photo));
      if (removedPhotos.length > 0) {
        await PhotoPickerUtil.deletePhotos(removedPhotos);
        logger.info(TAG, `Cleaned ${removedPhotos.length} removed photos for node ${nodeId}`);
      }
    }

    const updated = await this.nodeRepo.getNodeById(nodeId);
    if (!updated) {
      throw new Error('Failed to retrieve updated node');
    }
    return updated;
  }

  async deleteNode(nodeId: string): Promise<void> {
    // 先获取节点的照片列表
    const node = await this.nodeRepo.getNodeById(nodeId);
    if (node && node.photos.length > 0) {
      // 清理沙箱照片
      await PhotoPickerUtil.deletePhotos(node.photos);
      logger.info(TAG, `Cleaned ${node.photos.length} photos for deleted node ${nodeId}`);
    }
    // 删除数据库记录
    await this.nodeRepo.deleteNode(nodeId);
  }

  async reorderNodes(travelId: string, nodeIds: string[]): Promise<void> {
    await this.nodeRepo.reorderNodes(travelId, nodeIds);
  }
}
