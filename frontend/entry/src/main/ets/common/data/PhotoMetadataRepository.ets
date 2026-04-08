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
import { RdbHelper } from './RdbHelper';
import { logger } from '../utils/Logger';
import { PhotoMetadata } from '../ai/PhotoMetadata';

const TAG = 'PhotoMetadataRepo';

/**
 * 照片元数据仓库
 * 管理 photo_metadata 表的 CRUD 操作
 */
export class PhotoMetadataRepository {
  private rdbHelper: RdbHelper;

  constructor() {
    this.rdbHelper = RdbHelper.getInstance();
  }

  /**
   * 插入或更新照片元数据
   * @param metadata 照片元数据
   */
  async upsert(metadata: PhotoMetadata): Promise<void> {
    logger.info(TAG, `Upserting metadata for: ${metadata.photoPath}`);

    const store = await this.rdbHelper.getStore();

    const valueBucket: rdb.ValuesBucket = {
      photo_path: metadata.photoPath,
      scene_tags: JSON.stringify(metadata.sceneTags),
      object_tags: JSON.stringify(metadata.objectTags),
      color_tags: JSON.stringify(metadata.colorTags),
      time_tags: JSON.stringify(metadata.timeTags),
      emotion_tags: JSON.stringify(metadata.emotionTags),
      extracted_at: metadata.extractedAt,
      sensitivity: 'S2'
    };

    // 使用 REPLACE 语义（插入或替换）
    const result = await store.insert('photo_metadata', valueBucket, rdb.ConflictResolution.ON_CONFLICT_REPLACE);

    logger.debug(TAG, `Upsert result: ${result}`);
  }

  /**
   * 根据照片路径获取元数据
   * @param photoPath 照片沙箱路径
   * @returns 照片元数据，不存在则返回 undefined
   */
  async getByPath(photoPath: string): Promise<PhotoMetadata | undefined> {
    logger.info(TAG, `Getting metadata for: ${photoPath}`);

    const store = await this.rdbHelper.getStore();

    const predicates = new rdb.RdbPredicates('photo_metadata');
    predicates.equalTo('photo_path', photoPath);

    const resultSet = await store.query(predicates);

    try {
      if (resultSet.goToFirstRow()) {
        const metadata: PhotoMetadata = {
          photoPath: resultSet.getString(resultSet.getColumnIndex('photo_path')),
          sceneTags: this.parseJsonArray(resultSet.getString(resultSet.getColumnIndex('scene_tags'))),
          objectTags: this.parseJsonArray(resultSet.getString(resultSet.getColumnIndex('object_tags'))),
          colorTags: this.parseJsonArray(resultSet.getString(resultSet.getColumnIndex('color_tags'))),
          timeTags: this.parseJsonArray(resultSet.getString(resultSet.getColumnIndex('time_tags'))),
          emotionTags: this.parseJsonArray(resultSet.getString(resultSet.getColumnIndex('emotion_tags'))),
          extractedAt: resultSet.getLong(resultSet.getColumnIndex('extracted_at'))
        };
        logger.debug(TAG, `Found metadata: ${JSON.stringify(metadata)}`);
        return metadata;
      }

      logger.info(TAG, `No metadata found for: ${photoPath}`);
      return undefined;
    } finally {
      resultSet.close();
    }
  }

  /**
   * 批量获取多张照片的元数据
   * @param photoPaths 照片路径数组
   * @returns 元数据 Map (路径 -> 元数据)
   */
  async getBatch(photoPaths: string[]): Promise<Map<string, PhotoMetadata>> {
    logger.info(TAG, `Batch getting ${photoPaths.length} photos metadata`);

    const resultMap = new Map<string, PhotoMetadata>();

    if (photoPaths.length === 0) {
      return resultMap;
    }

    const store = await this.rdbHelper.getStore();

    const predicates = new rdb.RdbPredicates('photo_metadata');
    predicates.in('photo_path', photoPaths);

    const resultSet = await store.query(predicates);

    try {
      while (resultSet.goToNextRow()) {
        const metadata: PhotoMetadata = {
          photoPath: resultSet.getString(resultSet.getColumnIndex('photo_path')),
          sceneTags: this.parseJsonArray(resultSet.getString(resultSet.getColumnIndex('scene_tags'))),
          objectTags: this.parseJsonArray(resultSet.getString(resultSet.getColumnIndex('object_tags'))),
          colorTags: this.parseJsonArray(resultSet.getString(resultSet.getColumnIndex('color_tags'))),
          timeTags: this.parseJsonArray(resultSet.getString(resultSet.getColumnIndex('time_tags'))),
          emotionTags: this.parseJsonArray(resultSet.getString(resultSet.getColumnIndex('emotion_tags'))),
          extractedAt: resultSet.getLong(resultSet.getColumnIndex('extracted_at'))
        };
        resultMap.set(metadata.photoPath, metadata);
      }
    } finally {
      resultSet.close();
    }

    logger.debug(TAG, `Found ${resultMap.size} metadata records`);
    return resultMap;
  }

  /**
   * 删除照片元数据
   * @param photoPath 照片沙箱路径
   */
  async delete(photoPath: string): Promise<void> {
    logger.info(TAG, `Deleting metadata for: ${photoPath}`);

    const store = await this.rdbHelper.getStore();

    const predicates = new rdb.RdbPredicates('photo_metadata');
    predicates.equalTo('photo_path', photoPath);

    const result = await store.delete(predicates);
    logger.debug(TAG, `Delete result: ${result}`);
  }

  /**
   * 检查照片元数据是否存在
   * @param photoPath 照片沙箱路径
   * @returns 是否存在
   */
  async exists(photoPath: string): Promise<boolean> {
    const metadata = await this.getByPath(photoPath);
    return metadata !== undefined;
  }

  /**
   * 解析 JSON 数组字段
   * @param jsonString JSON 字符串
   * @returns 字符串数组
   */
  private parseJsonArray(jsonString: string): string[] {
    try {
      if (!jsonString || jsonString === '') {
        return [];
      }
      return JSON.parse(jsonString) as string[];
    } catch (err) {
      logger.error(TAG, `Failed to parse JSON array: ${jsonString}`);
      return [];
    }
  }
}