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

import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { logger } from '../utils/Logger';
import { PhotoMetadata, VisualKitResult } from './PhotoMetadata';

const TAG = 'LocalImageTagger';

/**
 * 本地图片元数据提取器
 * 通过 EXIF 和图片属性在端侧提取照片信息，照片不出设备
 * 提取的文字描述将发送给 LLM 生成文案（而非上传照片）
 */
export class LocalImageTagger {
  /**
   * 提取单张照片的元数据
   * 通过 EXIF 信息提取时间、方向等特征，转化为文字标签
   * @param photoPath 照片沙箱路径（file:// 或绝对路径）
   * @returns 照片元数据结构
   */
  async extractMetadata(photoPath: string): Promise<PhotoMetadata> {
    logger.info(TAG, `Extracting metadata for: ${photoPath}`);

    const emptyResult: PhotoMetadata = {
      photoPath: photoPath,
      sceneTags: [],
      objectTags: [],
      colorTags: [],
      timeTags: [],
      emotionTags: [],
      extractedAt: Date.now()
    };

    const realPath = photoPath.startsWith('file://') ? photoPath.substring(7) : photoPath;
    let file: fileIo.File | undefined;

    try {
      file = fileIo.openSync(realPath, fileIo.OpenMode.READ_ONLY);
      const imageSource = image.createImageSource(file.fd);

      const sceneTags: string[] = [];
      const timeTags: string[] = [];

      // 提取图片尺寸信息
      try {
        const imageInfo = await imageSource.getImageInfo();
        if (imageInfo && imageInfo.size) {
          const w = imageInfo.size.width;
          const h = imageInfo.size.height;
          if (w > h * 1.3) {
            sceneTags.push('横幅构图');
          } else if (h > w * 1.3) {
            sceneTags.push('竖幅构图');
          } else {
            sceneTags.push('方形构图');
          }
        }
      } catch (infoErr) {
        logger.warn(TAG, `getImageInfo failed: ${infoErr}`);
      }

      // 提取 EXIF 时间信息
      try {
        const dateTime: string = await imageSource.getImageProperty('DateTimeOriginal');
        if (dateTime.length > 0 && dateTime !== 'default_exif_value') {
          const timeTag = this.parseTimeOfDay(dateTime);
          if (timeTag.length > 0) {
            timeTags.push(timeTag);
          }
        }
      } catch (exifErr) {
        logger.debug(TAG, `EXIF DateTimeOriginal not available: ${exifErr}`);
      }

      imageSource.release();

      const metadata: PhotoMetadata = {
        photoPath: photoPath,
        sceneTags: sceneTags,
        objectTags: [],
        colorTags: [],
        timeTags: timeTags,
        emotionTags: [],
        extractedAt: Date.now()
      };

      logger.info(TAG, `Extracted: scene=[${sceneTags.join(',')}], time=[${timeTags.join(',')}]`);
      return metadata;
    } catch (err) {
      logger.error(TAG, `extractMetadata failed: ${JSON.stringify(err)}`);
      return emptyResult;
    } finally {
      if (file) {
        fileIo.closeSync(file);
      }
    }
  }

  /**
   * 批量提取多张照片的元数据
   */
  async extractBatch(photoPaths: string[]): Promise<VisualKitResult[]> {
    logger.info(TAG, `Batch extracting ${photoPaths.length} photos`);

    const results: VisualKitResult[] = [];

    for (const path of photoPaths) {
      try {
        const metadata = await this.extractMetadata(path);
        results.push({
          photoPath: path,
          tags: [
            ...metadata.sceneTags,
            ...metadata.objectTags,
            ...metadata.colorTags
          ],
          success: true
        });
      } catch (err) {
        const errorMsg = `Failed to extract ${path}: ${JSON.stringify(err)}`;
        logger.error(TAG, errorMsg);
        results.push({
          photoPath: path,
          tags: [],
          success: false,
          error: errorMsg
        });
      }
    }

    return results;
  }

  /**
   * 检查图片分析能力是否可用
   * 当前基于 EXIF 提取，始终可用
   */
  async isKitAvailable(): Promise<boolean> {
    return true;
  }

  /**
   * 从 EXIF 日期时间字符串解析时段
   * EXIF 格式: "YYYY:MM:DD HH:MM:SS"
   */
  private parseTimeOfDay(dateTimeStr: string): string {
    try {
      const parts = dateTimeStr.split(' ');
      if (parts.length < 2) {
        return '';
      }
      const timeParts = parts[1].split(':');
      if (timeParts.length < 1) {
        return '';
      }
      const hour = Number(timeParts[0]);
      if (isNaN(hour)) {
        return '';
      }

      if (hour >= 5 && hour < 8) {
        return '清晨';
      } else if (hour >= 8 && hour < 11) {
        return '上午';
      } else if (hour >= 11 && hour < 14) {
        return '中午';
      } else if (hour >= 14 && hour < 17) {
        return '下午';
      } else if (hour >= 17 && hour < 19) {
        return '傍晚';
      } else if (hour >= 19 && hour < 22) {
        return '夜晚';
      } else {
        return '深夜';
      }
    } catch (_) {
      return '';
    }
  }
}
