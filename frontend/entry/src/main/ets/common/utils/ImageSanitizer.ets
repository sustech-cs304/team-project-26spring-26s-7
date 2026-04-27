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
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { logger } from './Logger';

const TAG = 'ImageSanitizer';
const SANITIZED_DIR_NAME = 'photos_sanitized';
const REPACK_QUALITY = 90;
const REPACK_LONG_EDGE = 1600;

/**
 * 上传前的图片清洗工具
 *
 * 把沙箱里的原图重新解码 → 重新编码 JPEG，得到一份不含 EXIF 的副本。
 * 用于送往云端 AI 服务时的"敏感信息剥离"环节，确保 GPS、相机型号、
 * Author 等元数据不会随图离开端侧。
 *
 * 调用约束：
 * - 端侧 LocalImageTagger 应该在 sanitize 之前先把 EXIF 抽出来送进 prompt，
 *   这样上传出去的图本体就不再含元数据，prompt 里却保留了"拍摄时间/GPS"
 *   等用户已经知情同意的字段。
 */
export class ImageSanitizer {
  /**
   * 把原图重新编码成不含 EXIF 的 JPEG 副本
   * @param context UIAbilityContext，用于定位临时目录
   * @param sourcePath 源图沙箱路径（可带 file:// 前缀）
   * @returns 清洗后副本的绝对路径（不含 file:// 前缀，方便 multipart 复用）；失败返回空串
   */
  static async sanitizeForUpload(
    context: common.UIAbilityContext,
    sourcePath: string
  ): Promise<string> {
    const realSrc = sourcePath.startsWith('file://') ? sourcePath.substring(7) : sourcePath;

    let srcFd: fs.File | undefined;
    let imageSource: image.ImageSource | undefined;
    let pixelMap: image.PixelMap | undefined;
    let packer: image.ImagePacker | undefined;
    let outFd: fs.File | undefined;

    try {
      const dir = ImageSanitizer.ensureSanitizedDir(context);
      const targetPath = `${dir}/${ImageSanitizer.generateName()}`;

      srcFd = fs.openSync(realSrc, fs.OpenMode.READ_ONLY);
      imageSource = image.createImageSource(srcFd.fd);

      // 解码：长边缩到 1600，避免上传体积过大
      const decodingOptions: image.DecodingOptions = {};
      try {
        const info = await imageSource.getImageInfo();
        if (info && info.size && info.size.width > 0 && info.size.height > 0) {
          const desired = ImageSanitizer.computeDesiredSize(
            info.size.width,
            info.size.height,
            REPACK_LONG_EDGE
          );
          if (desired) {
            decodingOptions.desiredSize = desired;
          }
        }
      } catch (infoErr) {
        logger.warn(TAG, `getImageInfo failed: ${JSON.stringify(infoErr)}`);
      }

      pixelMap = await imageSource.createPixelMap(decodingOptions);

      // 重新编码 JPEG，只写像素，不带 EXIF
      packer = image.createImagePacker();
      const packOpts: image.PackingOption = {
        format: 'image/jpeg',
        quality: REPACK_QUALITY
      };
      const buf: ArrayBuffer = await packer.packing(pixelMap, packOpts);

      outFd = fs.openSync(targetPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      fs.writeSync(outFd.fd, buf);

      logger.info(
        TAG,
        `Sanitized: ${realSrc} -> ${targetPath} (${buf.byteLength} bytes, EXIF stripped)`
      );
      return targetPath;
    } catch (err) {
      logger.error(TAG, `sanitizeForUpload failed: ${JSON.stringify(err)}`);
      return '';
    } finally {
      if (pixelMap) {
        try {
          await pixelMap.release();
        } catch (_) {}
      }
      if (packer) {
        try {
          await packer.release();
        } catch (_) {}
      }
      if (imageSource) {
        try {
          imageSource.release();
        } catch (_) {}
      }
      if (outFd) {
        try {
          fs.closeSync(outFd);
        } catch (_) {}
      }
      if (srcFd) {
        try {
          fs.closeSync(srcFd);
        } catch (_) {}
      }
    }
  }

  /**
   * 删除单个清洗副本（推理结束后立即调用，避免临时图长时间留存）
   */
  static deleteSanitized(sanitizedPath: string): void {
    if (!sanitizedPath || sanitizedPath.length === 0) {
      return;
    }
    try {
      fs.unlinkSync(sanitizedPath);
    } catch (err) {
      logger.warn(TAG, `deleteSanitized failed: ${JSON.stringify(err)}`);
    }
  }

  /** 一次清空 sanitized 目录（建议 App 启动时跑一次兜底） */
  static purgeAll(context: common.UIAbilityContext): void {
    try {
      const dir = `${context.filesDir}/${SANITIZED_DIR_NAME}`;
      if (!fs.accessSync(dir)) {
        return;
      }
      const list = fs.listFileSync(dir);
      for (const name of list) {
        try {
          fs.unlinkSync(`${dir}/${name}`);
        } catch (_) {}
      }
    } catch (err) {
      logger.warn(TAG, `purgeAll failed: ${JSON.stringify(err)}`);
    }
  }

  private static ensureSanitizedDir(context: common.UIAbilityContext): string {
    const dir = `${context.filesDir}/${SANITIZED_DIR_NAME}`;
    try {
      fs.mkdirSync(dir, true);
    } catch (_) {
      // 已存在
    }
    return dir;
  }

  private static generateName(): string {
    const ts = Date.now();
    const rnd = Math.floor(Math.random() * 100000);
    return `san_${ts}_${rnd}.jpg`;
  }

  private static computeDesiredSize(
    width: number,
    height: number,
    maxEdge: number
  ): image.Size | undefined {
    const longer = Math.max(width, height);
    if (longer <= maxEdge) {
      return undefined;
    }
    const ratio = maxEdge / longer;
    return {
      width: Math.max(1, Math.round(width * ratio)),
      height: Math.max(1, Math.round(height * ratio))
    };
  }
}
