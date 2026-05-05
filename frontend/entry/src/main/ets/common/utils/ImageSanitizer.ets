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

import { image } from '@kit.ImageKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { common } from '@kit.AbilityKit'
import { logger } from './Logger'

const TAG = 'ImageSanitizer'
const SANITIZED_DIR_NAME = 'photos_sanitized'
const REPACK_QUALITY = 90
const REPACK_LONG_EDGE = 1600

export class ImageSanitizer {
  static async sanitizeForUpload(
    context: common.UIAbilityContext,
    sourcePath: string
  ): Promise<string> {
    const realSrc = sourcePath.startsWith('file://') ? sourcePath.substring(7) : sourcePath

    let srcFd: fs.File | undefined
    let imageSource: image.ImageSource | undefined
    let pixelMap: image.PixelMap | undefined
    let packer: image.ImagePacker | undefined
    let outFd: fs.File | undefined

    try {
      const dir = ImageSanitizer.ensureSanitizedDir(context)
      const targetPath = `${dir}/${ImageSanitizer.generateName()}`

      srcFd = fs.openSync(realSrc, fs.OpenMode.READ_ONLY)
      imageSource = image.createImageSource(srcFd.fd)

      const decodingOptions: image.DecodingOptions = {}
      try {
        const info = await imageSource.getImageInfo()
        if (info && info.size && info.size.width > 0 && info.size.height > 0) {
          const desired = ImageSanitizer.computeDesiredSize(
            info.size.width,
            info.size.height,
            REPACK_LONG_EDGE
          )
          if (desired) {
            decodingOptions.desiredSize = desired
          }
        }
      } catch (infoErr) {
        logger.warn(TAG, `getImageInfo failed: ${JSON.stringify(infoErr)}`)
      }

      pixelMap = await imageSource.createPixelMap(decodingOptions)
      packer = image.createImagePacker()
      const packOpts: image.PackingOption = {
        format: 'image/jpeg',
        quality: REPACK_QUALITY
      }
      const buf: ArrayBuffer = await packer.packing(pixelMap, packOpts)

      outFd = fs.openSync(targetPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY)
      fs.writeSync(outFd.fd, buf)

      logger.info(TAG, `Sanitized: ${realSrc} -> ${targetPath} (${buf.byteLength} bytes)`)
      return targetPath
    } catch (err) {
      logger.error(TAG, `sanitizeForUpload failed: ${JSON.stringify(err)}`)
      return ''
    } finally {
      if (pixelMap) {
        try {
          await pixelMap.release()
        } catch (_) {}
      }
      if (packer) {
        try {
          await packer.release()
        } catch (_) {}
      }
      if (imageSource) {
        try {
          imageSource.release()
        } catch (_) {}
      }
      if (outFd) {
        try {
          fs.closeSync(outFd)
        } catch (_) {}
      }
      if (srcFd) {
        try {
          fs.closeSync(srcFd)
        } catch (_) {}
      }
    }
  }

  static deleteSanitized(sanitizedPath: string): void {
    if (!sanitizedPath) {
      return
    }
    try {
      fs.unlinkSync(sanitizedPath)
    } catch (err) {
      logger.warn(TAG, `deleteSanitized failed: ${JSON.stringify(err)}`)
    }
  }

  static purgeAll(context: common.UIAbilityContext): void {
    const dir = `${context.filesDir}/${SANITIZED_DIR_NAME}`
    try {
      fs.accessSync(dir)
    } catch (_) {
      return
    }
    try {
      const list = fs.listFileSync(dir)
      for (let i = 0; i < list.length; i++) {
        try {
          fs.unlinkSync(`${dir}/${list[i]}`)
        } catch (_) {}
      }
    } catch (err) {
      logger.warn(TAG, `purgeAll failed: ${JSON.stringify(err)}`)
    }
  }

  private static ensureSanitizedDir(context: common.UIAbilityContext): string {
    const dir = `${context.filesDir}/${SANITIZED_DIR_NAME}`
    try {
      fs.mkdirSync(dir, true)
    } catch (_) {}
    return dir
  }

  private static generateName(): string {
    const ts = Date.now()
    const rnd = Math.floor(Math.random() * 100000)
    return `san_${ts}_${rnd}.jpg`
  }

  private static computeDesiredSize(
    width: number,
    height: number,
    maxEdge: number
  ): image.Size | undefined {
    const longer = Math.max(width, height)
    if (longer <= maxEdge) {
      return undefined
    }
    const ratio = maxEdge / longer
    return {
      width: Math.max(1, Math.round(width * ratio)),
      height: Math.max(1, Math.round(height * ratio))
    }
  }
}
