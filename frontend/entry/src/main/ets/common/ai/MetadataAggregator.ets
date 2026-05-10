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
import { PhotoMetadata, JourneyMetadata } from './PhotoMetadata';
import { MemoryNode } from '../service/types';
import { getDataService } from '../ServiceConfig';

const TAG = 'MetadataAggregator';

/**
 * 元数据聚合器
 * 聚合 MemoryNode 或 Trip 的照片元数据，生成发送给后端的请求结构
 *
 * 当前支持 MemoryNode 级聚合，后续可扩展为 Trip 级聚合
 */
export class MetadataAggregator {
  /**
   * 聚合单个 MemoryNode 的元数据
   * @param nodeId 记忆节点 ID
   * @returns 旅程元数据结构 (用于发送给 AI Gateway)
   *
   * 流程：
   * 1. 从 RDB 获取 MemoryNode 数据
   * 2. 根据 photos 字段查询 photo_metadata 表
   * 3. 聚合所有照片的标签
   * 4. 计算 POI、距离、时长等信息
   */
  async aggregateFromNode(nodeId: string): Promise<JourneyMetadata> {
    logger.info(TAG, `Aggregating metadata for node: ${nodeId}`);

    // 从数据库获取 MemoryNode
    const dataService = getDataService();
    const node = await dataService.getNodeById(nodeId);

    if (!node) {
      logger.error(TAG, `Node not found: ${nodeId}`);
      throw new Error(`MemoryNode ${nodeId} not found`);
    }

    // TODO: 从 photo_metadata 表获取照片元数据
    // 当前使用模拟数据
    const aggregatedTags: string[] = [];
    let photoCount = 0;

    if (node.photos && node.photos.length > 0) {
      photoCount = node.photos.length;
      // TODO: 实际应从 PhotoMetadataRepository 查询
      // const metadataRepo = new PhotoMetadataRepository();
      // for (const photoPath of node.photos) {
      //   const metadata = await metadataRepo.getByPath(photoPath);
      //   aggregatedTags.push(...metadata.sceneTags, ...metadata.objectTags);
      // }

      // 模拟标签聚合
      aggregatedTags.push('nature', 'outdoor', 'scenery');
    }

    // 构建旅程元数据
    const journeyMetadata: JourneyMetadata = {
      poiList: node.poiName ? [node.poiName] : ['未命名地点'],
      totalDistanceKm: 0,  // 单节点距离为 0
      durationHours: 0,    // 单节点时长为 0，后续 Trip 聚合时计算
      tags: this.deduplicateTags(aggregatedTags),
      photoCount: photoCount
    };

    logger.debug(TAG, `Aggregated metadata: ${JSON.stringify(journeyMetadata)}`);
    return journeyMetadata;
  }

  /**
   * 聚合整个 Trip 的元数据 (扩展点)
   * @param tripId 旅行 ID
   * @returns 旅程元数据结构
   *
   * TODO: 实现 Trip 级聚合
   * 流程：
   * 1. 获取 Trip 下所有 MemoryNode
   * 2. 聚合所有节点的 POI、照片元数据
   * 3. 计算总距离和时长
   */
  async aggregateFromTrip(tripId: string): Promise<JourneyMetadata> {
    logger.info(TAG, `Aggregating metadata for trip: ${tripId}`);

    // TODO: 实现 Trip 级聚合
    // 当前返回模拟数据
    const journeyMetadata: JourneyMetadata = {
      poiList: ['杭州', '西湖', '灵隐寺'],
      totalDistanceKm: 45,
      durationHours: 8,
      tags: ['nature', 'temple', 'lake', 'scenery'],
      photoCount: 20
    };

    logger.info(TAG, `Trip aggregation not implemented, returning mock data`);
    return journeyMetadata;
  }

  /**
   * 去重标签
   * @param tags 标签数组
   * @returns 去重后的标签数组
   */
  private deduplicateTags(tags: string[]): string[] {
    const uniqueTags: Set<string> = new Set(tags);
    return Array.from(uniqueTags);
  }

  /**
   * 计算两个坐标之间的距离 (公里)
   * 使用 Haversine 公式
   *
   * TODO: Trip 级聚合时用于计算节点间距离
   */
  private calculateDistance(
    lat1: number,
    lon1: number,
    lat2: number,
    lon2: number
  ): number {
    const R = 6371; // 地球半径 (公里)
    const dLat = this.toRad(lat2 - lat1);
    const dLon = this.toRad(lon2 - lon1);
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
              Math.cos(this.toRad(lat1)) * Math.cos(this.toRad(lat2)) *
              Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  }

  private toRad(deg: number): number {
    return deg * (Math.PI / 180);
  }
}