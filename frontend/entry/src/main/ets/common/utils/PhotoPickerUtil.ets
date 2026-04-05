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

import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { logger } from './Logger';

const TAG = 'PhotoPickerUtil';

/**
 * 照片选择与沙箱存储工具类
 *
 * 实现流程：
 * 1. PhotoViewPicker.select() - 拉起系统图库选择照片
 * 2. fs.copyFile() - 复制照片到应用沙箱私有目录
 * 3. 返回沙箱路径数组 - 存入数据库，永久可访问
 *
 * 优势：
 * - 应用私有目录，不依赖外部权限
 * - 应用重启后仍可访问照片
 * - Replay 功能可直接使用沙箱路径
 */
export class PhotoPickerUtil {
  /**
   * 选择照片并存储到沙箱
   * @param context UIAbilityContext
   * @param maxCount 最大选择数量（默认 9 张）
   * @returns 沙箱路径数组
   */
  static async pickAndSavePhotos(context: common.UIAbilityContext, maxCount: number = 9): Promise<string[]> {
    try {
      // Step 1: 拉起图库选择器
      const photoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = maxCount;

      const photoViewPicker = new photoAccessHelper.PhotoViewPicker();
      const selectResult = await photoViewPicker.select(photoSelectOptions);
      const uris = selectResult.photoUris;

      logger.info(TAG, `Selected ${uris.length} photos from gallery`);

      if (uris.length === 0) {
        return [];
      }

      // Step 2: 复制每张照片到沙箱
      const sandboxPaths: string[] = [];
      for (const uri of uris) {
        const sandboxPath = await PhotoPickerUtil.copyToSandbox(context, uri);
        if (sandboxPath.length > 0) {
          sandboxPaths.push(sandboxPath);
        }
      }

      logger.info(TAG, `Saved ${sandboxPaths.length} photos to sandbox`);
      return sandboxPaths;
    } catch (err) {
      const error = err as BusinessError;
      logger.error(TAG, `pickAndSavePhotos failed: code=${error.code}, msg=${error.message}`);
      return [];
    }
  }

  /**
   * 复制单张照片到沙箱目录
   * @param context UIAbilityContext
   * @param sourceUri Picker 返回的临时 URI
   * @returns 沙箱路径
   */
  private static async copyToSandbox(context: common.UIAbilityContext, sourceUri: string): Promise<string> {
    try {
      // 确保沙箱照片目录存在
      const sandboxDir = PhotoPickerUtil.getSandboxPhotoDir(context);
      PhotoPickerUtil.ensureDirectoryExists(sandboxDir);

      // 生成唯一文件名
      const fileName = PhotoPickerUtil.generateFileName();
      const targetPath = `${sandboxDir}/${fileName}`;

      // 打开源文件（临时 URI，只读权限）
      const sourceFile = fs.openSync(sourceUri, fs.OpenMode.READ_ONLY);

      // 创建目标文件
      const targetFile = fs.openSync(targetPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);

      // 复制文件内容
      const bufferSize = 4096;
      const buffer = new ArrayBuffer(bufferSize);
      let totalBytes = 0;

      let readLen = fs.readSync(sourceFile.fd, buffer);
      while (readLen > 0) {
        fs.writeSync(targetFile.fd, buffer.slice(0, readLen));
        totalBytes += readLen;
        readLen = fs.readSync(sourceFile.fd, buffer);
      }

      // 关闭文件
      fs.closeSync(sourceFile);
      fs.closeSync(targetFile);

      logger.info(TAG, `Copied photo to sandbox: ${targetPath} (${totalBytes} bytes)`);
      return targetPath;
    } catch (err) {
      const error = err as BusinessError;
      logger.error(TAG, `copyToSandbox failed: ${error.message}`);
      return '';
    }
  }

  /**
   * 获取沙箱照片目录路径
   */
  static getSandboxPhotoDir(context: common.UIAbilityContext): string {
    return `${context.filesDir}/photos`;
  }

  /**
   * 确保目录存在
   */
  private static ensureDirectoryExists(dirPath: string): void {
    try {
      // 尝试打开目录，如果不存在会抛出错误
      fs.accessSync(dirPath);
    } catch {
      // 目录不存在，创建它
      // 使用 mkdirSync 创建目录（递归创建父目录）
      const parentDir = dirPath.substring(0, dirPath.lastIndexOf('/'));
      try {
        fs.accessSync(parentDir);
      } catch {
        // 父目录也不存在，创建父目录
        fs.mkdirSync(parentDir, true);
      }
      // 创建目标目录
      fs.mkdirSync(dirPath, false);
      logger.info(TAG, `Created photo directory: ${dirPath}`);
    }
  }

  /**
   * 生成唯一文件名
   */
  private static generateFileName(): string {
    const timestamp = Date.now();
    const random = Math.floor(Math.random() * 1000);
    return `photo_${timestamp}_${random}.jpg`;
  }

  /**
   * 删除沙箱中的照片文件
   * @param sandboxPath 沙箱路径
   */
  static async deletePhoto(sandboxPath: string): Promise<boolean> {
    try {
      fs.unlinkSync(sandboxPath);
      logger.info(TAG, `Deleted photo: ${sandboxPath}`);
      return true;
    } catch (err) {
      const error = err as BusinessError;
      logger.error(TAG, `deletePhoto failed: ${error.message}`);
      return false;
    }
  }

  /**
   * 批量删除沙箱照片
   * @param sandboxPaths 沙箱路径数组
   */
  static async deletePhotos(sandboxPaths: string[]): Promise<void> {
    for (const path of sandboxPaths) {
      await PhotoPickerUtil.deletePhoto(path);
    }
    logger.info(TAG, `Deleted ${sandboxPaths.length} photos from sandbox`);
  }

  /**
   * 检查沙箱照片是否存在
   */
  static photoExists(sandboxPath: string): boolean {
    try {
      fs.accessSync(sandboxPath);
      return true;
    } catch {
      return false;
    }
  }
}