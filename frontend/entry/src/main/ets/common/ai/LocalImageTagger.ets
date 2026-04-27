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
import { textRecognition } from '@kit.CoreVisionKit';
import { logger } from '../utils/Logger';
import { PhotoMetadata, VisualKitResult } from './PhotoMetadata';

const TAG = 'LocalImageTagger';
const OCR_TEXT_MAX_LENGTH: number = 80;

/**
 * 实际进入 prompt 的 EXIF 字段集合
 * 砍掉了 Orientation/ExposureTime/FNumber/ISOSpeedRatings/FocalLength/Make/Model，
 * 因为 prompt 已经不展示这些字段，再抽就是纯浪费 ~50ms/张
 */
const EXIF_PROPERTY_KEYS: string[] = [
  'DateTimeOriginal',
  'GPSLatitude',
  'GPSLongitude',
  'GPSLatitudeRef',
  'GPSLongitudeRef'
];

/**
 * 本地图片元数据提取器
 *
 * 使用 @kit.ImageKit 在端侧读取 EXIF/像素信息，照片不出设备。
 * 提取出的字段（拍摄时间、GPS、相机、曝光参数等）会被聚合成纯文本描述
 * 喂给 LLM，从而保留"图片信息进入 prompt"的能力但不上传图片本体。
 */
export class LocalImageTagger {
  /**
   * 提取单张照片的元数据
   * @param photoPath 照片沙箱路径（file:// 或绝对路径）
   */
  async extractMetadata(photoPath: string): Promise<PhotoMetadata> {
    logger.info(TAG, `Extracting metadata for: ${photoPath}`);

    const result: PhotoMetadata = {
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
    let imageSource: image.ImageSource | undefined;

    try {
      file = fileIo.openSync(realPath, fileIo.OpenMode.READ_ONLY);
      imageSource = image.createImageSource(file.fd);

      // 像素尺寸 -> 构图标签
      try {
        const imageInfo = await imageSource.getImageInfo();
        if (imageInfo && imageInfo.size) {
          const w = imageInfo.size.width;
          const h = imageInfo.size.height;
          result.imageWidth = w;
          result.imageHeight = h;
          if (w > h * 1.3) {
            result.sceneTags.push('横幅构图');
          } else if (h > w * 1.3) {
            result.sceneTags.push('竖幅构图');
          } else {
            result.sceneTags.push('方形构图');
          }
        }
      } catch (infoErr) {
        logger.warn(TAG, `getImageInfo failed: ${JSON.stringify(infoErr)}`);
      }

      // 批量读取 EXIF 字段
      const exif = await this.readExifBatch(imageSource);

      // 拍摄时间
      const dateTimeOriginal = exif.get('DateTimeOriginal');
      if (dateTimeOriginal) {
        result.dateTimeOriginal = dateTimeOriginal;
        const timeTag = this.parseTimeOfDay(dateTimeOriginal);
        if (timeTag.length > 0) {
          result.timeTags.push(timeTag);
        }
      }

      // GPS：DMS + ref 转十进制
      const lat = this.parseGps(exif.get('GPSLatitude'), exif.get('GPSLatitudeRef'));
      const lon = this.parseGps(exif.get('GPSLongitude'), exif.get('GPSLongitudeRef'));
      if (lat !== undefined) {
        result.gpsLatitude = lat;
      }
      if (lon !== undefined) {
        result.gpsLongitude = lon;
      }

      // 端侧画面内容识别：OCR（拍到招牌/菜单/路牌时给 prompt 补充语义）
      // 主体分割暂时停用：分割只能给"主体数量"，对文案生成贡献小，单张额外耗时 ~150ms 不划算
      // 已知宽高时缩到 720 长边再解，未知宽高时按原图解（不传 desiredSize 避免被压成方图）
      let pixelMap: image.PixelMap | undefined;
      try {
        const desired = this.computeDecodeSize(result.imageWidth, result.imageHeight, 720);
        if (desired) {
          const decodingOptions: image.DecodingOptions = { desiredSize: desired };
          pixelMap = await imageSource.createPixelMap(decodingOptions);
        } else {
          pixelMap = await imageSource.createPixelMap();
        }
      } catch (decodeErr) {
        logger.warn(TAG, `createPixelMap failed (skip OCR): ${JSON.stringify(decodeErr)}`);
      }

      if (pixelMap) {
        try {
          const ocrText = await this.runOcr(pixelMap);
          if (ocrText.length > 0) {
            result.ocrText = ocrText;
          }
        } catch (ocrErr) {
          logger.warn(TAG, `OCR failed: ${JSON.stringify(ocrErr)}`);
        }

        try {
          await pixelMap.release();
        } catch (_) {
          // ignore
        }
      }

      logger.info(
        TAG,
        `Extracted: time=[${result.timeTags.join(',')}], ` +
          `gps=(${result.gpsLatitude ?? '-'},${result.gpsLongitude ?? '-'}), ` +
          `ocr=${result.ocrText ? '(' + result.ocrText.length + 'chars)' : '-'}`
      );
      return result;
    } catch (err) {
      logger.error(TAG, `extractMetadata failed: ${JSON.stringify(err)}`);
      return result;
    } finally {
      if (imageSource) {
        try {
          imageSource.release();
        } catch (_) {
          // ignore
        }
      }
      if (file) {
        try {
          fileIo.closeSync(file);
        } catch (_) {
          // ignore
        }
      }
    }
  }

  /** 批量提取 */
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
            ...metadata.timeTags,
            ...metadata.objectTags,
            ...metadata.colorTags
          ],
          success: true
        });
      } catch (err) {
        const errorMsg = `Failed to extract ${path}: ${JSON.stringify(err)}`;
        logger.error(TAG, errorMsg);
        results.push({ photoPath: path, tags: [], success: false, error: errorMsg });
      }
    }
    return results;
  }

  async isKitAvailable(): Promise<boolean> {
    return true;
  }

  /**
   * 逐键调用 getImageProperty，吞掉 "属性不存在" 错误。
   * 不少手机 / 截图照片只有少数 EXIF 字段。
   */
  private async readExifBatch(source: image.ImageSource): Promise<Map<string, string>> {
    const out: Map<string, string> = new Map();
    for (const key of EXIF_PROPERTY_KEYS) {
      try {
        const value = await source.getImageProperty(key);
        if (value && value.length > 0 && value !== 'default_exif_value') {
          out.set(key, value);
        }
      } catch (err) {
        logger.debug(TAG, `EXIF ${key} not available: ${JSON.stringify(err)}`);
      }
    }
    return out;
  }

  /**
   * 解析 EXIF GPS：HarmonyOS 返回 "deg, min, sec" 或纯小数字符串
   */
  private parseGps(raw: string | undefined, ref: string | undefined): number | undefined {
    if (!raw || raw.length === 0) {
      return undefined;
    }
    const trimmed = raw.trim();
    let decimal: number = NaN;

    if (trimmed.indexOf(',') >= 0) {
      const parts = trimmed.split(',').map((p: string) => Number(p.trim()));
      if (parts.length >= 3 && parts.every((n: number) => !isNaN(n))) {
        decimal = parts[0] + parts[1] / 60 + parts[2] / 3600;
      }
    } else {
      const single = Number(trimmed);
      if (!isNaN(single)) {
        decimal = single;
      }
    }

    if (isNaN(decimal)) {
      return undefined;
    }

    const refUpper = (ref || '').trim().toUpperCase();
    if (refUpper === 'S' || refUpper === 'W') {
      decimal = -decimal;
    }
    // 保留 6 位小数（≈10cm 量级）
    return Math.round(decimal * 1000000) / 1000000;
  }

  /**
   * 等比缩放出一个不超过 maxEdge 的解码尺寸；
   * 宽高未知时返回 undefined，调用方应改用原图解码
   */
  private computeDecodeSize(
    width: number | undefined,
    height: number | undefined,
    maxEdge: number
  ): image.Size | undefined {
    if (!width || !height || width <= 0 || height <= 0) {
      return undefined;
    }
    const longer = Math.max(width, height);
    if (longer <= maxEdge) {
      return { width: width, height: height };
    }
    const ratio = maxEdge / longer;
    return {
      width: Math.max(1, Math.round(width * ratio)),
      height: Math.max(1, Math.round(height * ratio))
    };
  }

  /**
   * 端侧 OCR：textRecognition.recognizeText
   * 返回截断后的整段识别文本，没识别到时返回空串
   * 不同 SDK 版本返回结构略有差异，按 .value -> .text -> .blocks[].value 顺序兜底
   */
  private async runOcr(pixelMap: image.PixelMap): Promise<string> {
    const visionInfo: textRecognition.VisionInfo = { pixelMap: pixelMap };
    const recognitionResult = await textRecognition.recognizeText(visionInfo);
    const record = recognitionResult as Object as Record<string, Object>;

    let raw = '';

    const valueField = record['value'];
    if (typeof valueField === 'string' && valueField.length > 0) {
      raw = valueField as string;
    }

    if (raw.length === 0) {
      const textField = record['text'];
      if (typeof textField === 'string' && textField.length > 0) {
        raw = textField as string;
      }
    }

    if (raw.length === 0) {
      const blocksField = record['blocks'];
      if (Array.isArray(blocksField)) {
        const pieces: string[] = [];
        for (const b of (blocksField as Object[])) {
          const blockRec = b as Object as Record<string, Object>;
          const bv = blockRec['value'];
          const bt = blockRec['text'];
          if (typeof bv === 'string' && bv.length > 0) {
            pieces.push(bv as string);
          } else if (typeof bt === 'string' && bt.length > 0) {
            pieces.push(bt as string);
          }
        }
        if (pieces.length > 0) {
          raw = pieces.join('\n');
        }
      }
    }

    logger.info(TAG, `OCR raw length=${raw.length}, available keys=${Object.keys(record).join(',')}`);

    if (raw.length === 0) {
      return '';
    }

    // 多行合并成一行，去掉重复空白
    const compact = raw.replace(/\s+/g, ' ').trim();
    if (compact.length <= OCR_TEXT_MAX_LENGTH) {
      return compact;
    }
    return compact.substring(0, OCR_TEXT_MAX_LENGTH) + '…';
  }

  /** 从 EXIF 时间字符串解析时段（"YYYY:MM:DD HH:MM:SS"） */
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
      }
      if (hour >= 8 && hour < 11) {
        return '上午';
      }
      if (hour >= 11 && hour < 14) {
        return '中午';
      }
      if (hour >= 14 && hour < 17) {
        return '下午';
      }
      if (hour >= 17 && hour < 19) {
        return '傍晚';
      }
      if (hour >= 19 && hour < 22) {
        return '夜晚';
      }
      return '深夜';
    } catch (_) {
      return '';
    }
  }
}
