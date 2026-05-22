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

import { fileIo as fs } from '@kit.CoreFileKit'
import { common } from '@kit.AbilityKit'
import { logger } from '../../../common/utils/Logger'
import { ImageSanitizer } from '../../../common/utils/ImageSanitizer'
import { SharePhoto } from './ShareService'
import {
  SharePhotoIssue,
  SharePreflightErrorCode,
} from '../types/ShareTypes'

const TAG = 'SharePhotoHelper'

export interface SharePhotoBatchResult {
  photos: SharePhoto[]
  issues: SharePhotoIssue[]
}

/**
 * 把 MemoryNode.photos 里那些"可能带 file:// 前缀 / 可能不存在 / 可能是
 * cloud key 而不是本地路径"的字符串，过滤成可以喂给 multipart 上传的
 * 真实沙箱文件路径。
 *
 * 业务逻辑：
 *   - 跳过 cloud-only 的 key（如 "users/.../xxx.jpg"）
 *   - 去掉 file:// 前缀
 *   - 校验文件确实存在
 *   - 推断 contentType（按扩展名）
 */
export class SharePhotoHelper {
  /**
   * 把任意路径字符串数组归一化成 SharePhoto 列表。
   * 不存在或不是本地文件的条目会被丢弃。
   */
  static toSharePhotos(rawPaths: string[]): SharePhoto[] {
    const out: SharePhoto[] = []
    for (let i = 0; i < rawPaths.length; i++) {
      const raw = rawPaths[i]
      if (!raw) continue
      // 跳过云端引用（cloud key 形如 "users/{uid}/..."）
      if (raw.startsWith('users/') || raw.startsWith('cloud://')) {
        logger.warn(TAG, `skip cloud-only ref: ${raw}`)
        continue
      }
      const realPath = raw.startsWith('file://') ? raw.substring(7) : raw
      if (!fs.accessSync(realPath)) {
        logger.warn(TAG, `skip missing file: ${realPath}`)
        continue
      }
      const filename = SharePhotoHelper.basename(realPath)
      const contentType = SharePhotoHelper.guessMime(filename)
      out.push({ filePath: realPath, filename, contentType })
    }
    return out
  }

  static async toSanitizedSharePhotos(
    ctx: common.UIAbilityContext,
    rawPaths: string[]
  ): Promise<SharePhoto[]> {
    const localPhotos = SharePhotoHelper.toSharePhotos(rawPaths)
    const out: SharePhoto[] = []
    for (let i = 0; i < localPhotos.length; i++) {
      const sanitizedPath = await ImageSanitizer.sanitizeForUpload(ctx, localPhotos[i].filePath)
      if (!sanitizedPath) {
        logger.warn(TAG, `skip unsanitized file: ${localPhotos[i].filePath}`)
        continue
      }
      out.push({
        filePath: sanitizedPath,
        filename: SharePhotoHelper.basename(sanitizedPath),
        contentType: 'image/jpeg',
        cleanupPath: sanitizedPath,
      })
    }
    return out
  }

  static async prepareSharePhotos(
    ctx: common.UIAbilityContext,
    nodeId: string,
    rawPaths: string[]
  ): Promise<SharePhotoBatchResult> {
    const photos: SharePhoto[] = []
    const issues: SharePhotoIssue[] = []

    for (let i = 0; i < rawPaths.length; i++) {
      const raw = rawPaths[i]
      if (!raw) {
        continue
      }
      if (SharePhotoHelper.isCloudOnlyPath(raw)) {
        issues.push({
          nodeId,
          rawPath: raw,
          reason: SharePreflightErrorCode.CLOUD_ONLY_PHOTO,
          message: '该照片只有云端引用，当前设备没有可直接上传的本地副本',
        })
        continue
      }

      const realPath = raw.startsWith('file://') ? raw.substring(7) : raw
      if (!fs.accessSync(realPath)) {
        issues.push({
          nodeId,
          rawPath: raw,
          reason: SharePreflightErrorCode.LOCAL_PHOTO_MISSING,
          message: '该照片在当前设备上找不到本地文件',
        })
        continue
      }

      const sanitizedPath = await ImageSanitizer.sanitizeForUpload(ctx, realPath)
      if (!sanitizedPath) {
        issues.push({
          nodeId,
          rawPath: raw,
          reason: SharePreflightErrorCode.PHOTO_SANITIZE_FAILED,
          message: '该照片在分享前 EXIF 清洗失败',
        })
        continue
      }

      photos.push({
        filePath: sanitizedPath,
        filename: SharePhotoHelper.basename(sanitizedPath),
        contentType: 'image/jpeg',
        cleanupPath: sanitizedPath,
      })
    }

    return { photos, issues }
  }

  /**
   * Demo helper —— 把 resources/base/media/ 里打包的 photo_N.jpg 复制到沙箱
   * 缓存目录，返回可以喂给 multipart 上传的 SharePhoto 列表。
   *
   * 用于"还没接真实数据的时候直接做联调测试"场景。
   *
   * @param ctx          UIAbilityContext (一般在 aboutToAppear 里通过 getContext(this) 拿)
   * @param resources    $r('app.media.photo_1') 等资源引用列表
   * @param filenames    与 resources 一一对应的文件名（带扩展名）
   */
  static async stageBundledMedia(
    ctx: common.UIAbilityContext,
    resources: Resource[],
    filenames: string[]
  ): Promise<SharePhoto[]> {
    const out: SharePhoto[] = []
    const cacheDir = ctx.cacheDir
    for (let i = 0; i < resources.length; i++) {
      const res = resources[i]
      const filename = filenames[i] || `bundled_${i}.jpg`
      const targetPath = `${cacheDir}/share_demo_${filename}`
      try {
        // resourceManager.getMediaContent(resource) 返回 Uint8Array
        const buf = await ctx.resourceManager.getMediaContent(res)
        const file = fs.openSync(
          targetPath,
          fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC
        )
        fs.writeSync(file.fd, buf.buffer)
        fs.closeSync(file)
        out.push({
          filePath: targetPath,
          filename,
          contentType: SharePhotoHelper.guessMime(filename),
          cleanupPath: targetPath,
        })
        logger.info(TAG, `staged ${filename} -> ${targetPath} (${buf.byteLength} bytes)`)
      } catch (e) {
        logger.error(TAG, `stageBundledMedia ${filename}: ${JSON.stringify(e)}`)
      }
    }
    return out
  }

  static cleanupTemporaryPhotos(photos: SharePhoto[]): void {
    for (let i = 0; i < photos.length; i++) {
      const cleanupPath = photos[i].cleanupPath
      if (!cleanupPath) {
        continue
      }
      ImageSanitizer.deleteSanitized(cleanupPath)
    }
  }

  private static basename(p: string): string {
    const i = p.lastIndexOf('/')
    return i >= 0 ? p.substring(i + 1) : p
  }

  private static isCloudOnlyPath(raw: string): boolean {
    return raw.startsWith('users/') || raw.startsWith('cloud://')
  }

  private static guessMime(filename: string): string {
    const lower = filename.toLowerCase()
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg'
    if (lower.endsWith('.png')) return 'image/png'
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic'
    if (lower.endsWith('.webp')) return 'image/webp'
    return 'application/octet-stream'
  }
}
