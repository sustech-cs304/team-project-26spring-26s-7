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

import { systemShare } from '@kit.ShareKit'
import { common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { logger } from '../../../common/utils/Logger'

const TAG = 'SystemShareService'

/**
 * 调起系统分享面板时给到 ShareKit 的载荷。
 * url        —— 限时分享 URL（必填，会作为 hyperlink 主体）
 * title      —— 在分享卡片头部显示的标题，如 "深圳湾骑行 - TravelPin"
 * description —— 摘要，如 "4 个节点 · 12.5km · 始于红树林"
 * thumbnail  —— 可选，封面图字节（推荐 ≤ 200KB 的 JPEG/WebP）。
 *               注意：HMOS SharedRecord.thumbnail 类型是 Uint8Array，
 *               不是 ArrayBuffer；从 http 返回的 ArrayBuffer 要 new Uint8Array(buf) 包一层。
 *               QQ 等不会主动 fetch URL 的 OG meta，必须靠这个字节
 *               才能在卡片里渲染封面图。微信会自己抓 OG meta，但有
 *               thumbnail 也无妨（即时显示 + 减一次抓取）。
 */
export interface SystemSharePayload {
  url: string
  title: string
  description: string
  thumbnail?: Uint8Array
}

/**
 * v1.1：海报（图片）分享载荷。把后端 /share/{code}/poster.jpg 写到 app
 * cacheDir 后调用 share() — 接收方 app 看到的是一张图，图上印着扫描可
 * 跳转到分享链接的 QR 码。
 *
 * fileUri      —— 必填，本地文件 URI，格式 'file:///data/storage/...'
 *                 调用方需先把 poster bytes 写到沙箱再传入；
 *                 SystemShareService 不负责写文件。
 * title / description / thumbnail —— 同 SystemSharePayload，作为 SharedRecord
 *                                    的字段；微信/QQ 显示卡片时可能用到。
 */
export interface SystemShareImagePayload {
  fileUri: string
  title: string
  description: string
  thumbnail?: Uint8Array
}

/**
 * 系统分享适配层 —— 包住 `@kit.ShareKit.systemShare`。
 *
 * 设计目标：
 *   1. 调用方不感知 ShareKit 的具体类型；只构造 `SystemSharePayload` 即可
 *   2. 任何运行时失败（API 不在、用户取消、面板挂掉）一律返回 false，
 *      让调用方走剪贴板回退路径，保证"分享"按钮永远有响应
 *   3. 不抛异常，失败信息走 logger；UI 自己决定如何提示
 *
 * 注意 ShareKit 是 API 12+（HarmonyOS NEXT）才有；老版本编译期就会报错。
 * 若团队需要兼容更老的设备，可考虑把整个文件 wrap 在 try-catch 的 require
 * 风格里，但目前项目其它 feature（如 MapKit）也用了 NEXT 才有的 kit，
 * 这里假设最低 API 12 是可接受前提。
 */
export class SystemShareService {

  /**
   * 调起系统分享面板。
   *
   * @returns true  系统面板成功打开（用户后续选择由 OS 接管）
   *          false 当前设备/系统不支持 / 调用失败 — 调用方应回退到剪贴板
   */
  static async share(
    ctx: common.UIAbilityContext,
    payload: SystemSharePayload
  ): Promise<boolean> {
    const hasThumb = payload.thumbnail !== undefined && payload.thumbnail.byteLength > 0
    logger.info(TAG, `share() url=${payload.url} title="${payload.title}" thumb=${hasThumb ? payload.thumbnail!.byteLength + 'B' : 'no'}`)
    try {
      // utd 选择对哪些 app 出现在分享面板里影响很大：
      //   - 'general.hyperlink' 是 URL+描述文字 的标准 UTD，QQ/微信/微博/
      //     浏览器/邮件等多数应用都注册了这个类型作为分享接收意图
      //   - 'general.url' 是裸 URL，部分接收方（包括早期 HMOS 微信）不会
      //     在面板里出现 — 改成 hyperlink 提升兼容性
      //   - 同时附加一份 'general.text' 副本：那些只声明了"接收文本"的 app
      //     也能看见这次分享（兜底）
      const data = new systemShare.SharedData({
        utd: 'general.hyperlink',
        content: payload.url,
        title: payload.title,
        description: payload.description,
        thumbnail: payload.thumbnail,    // QQ 卡片预览的关键
      })
      // 文本副本：标题 + 摘要 + URL，纯文本接收方就这一份
      const textBlob = `${payload.title}\n${payload.description}\n${payload.url}`
      try {
        data.addRecord({
          utd: 'general.text',
          content: textBlob,
          title: payload.title,
          description: payload.description,
        })
      } catch (recordErr) {
        // addRecord 在某些 SDK 版本可能不存在；不致命，主 record 已可用
        logger.warn(TAG, `addRecord(general.text) failed: ${JSON.stringify(recordErr)}`)
      }

      const controller = new systemShare.ShareController(data)

      // SharePreviewMode.DETAIL 让面板顶部显示标题 + 摘要 + URL，
      // 视觉效果接近一张卡片。SelectionMode.SINGLE = 用户选一个目标即结束。
      await controller.show(ctx, {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE,
      })

      logger.info(TAG, 'systemShare panel shown successfully')
      return true
    } catch (e) {
      const be = e as BusinessError
      const code = be && be.code !== undefined ? be.code : 'n/a'
      const msg = be && be.message ? be.message : JSON.stringify(e)
      logger.error(TAG, `systemShare failed: code=${code} message=${msg}`)
      return false
    }
  }

  /**
   * v1.1：调起系统分享面板，分享一张图片（带 QR 码的海报）。
   *
   * 与 share()（hyperlink）相对的另一条路。设计用于微信以外的目标：
   * 接收方看到的是图本身，图上印着扫码跳转的 QR — 比依赖 og:meta 渲染
   * 链接卡片更稳。
   *
   * 大致流程：
   *   1. 调用方先把 poster bytes 写到 app cacheDir（一般是
   *      `${ctx.cacheDir}/poster-{shortCode}.jpg`）
   *   2. 传入 `file://${absPath}` 作为 fileUri
   *   3. 系统面板里 receiver app（微信/QQ/微博/相册...）以图片形式接收
   *
   * @returns true 系统面板成功打开；false 失败（调用方走兜底）
   */
  static async shareImage(
    ctx: common.UIAbilityContext,
    payload: SystemShareImagePayload
  ): Promise<boolean> {
    const hasThumb = payload.thumbnail !== undefined && payload.thumbnail.byteLength > 0
    logger.info(TAG, `shareImage() uri=${payload.fileUri} title="${payload.title}" thumb=${hasThumb ? payload.thumbnail!.byteLength + 'B' : 'no'}`)
    try {
      // general.image 是图片标准 UTD；'uri' 字段（非 'content'）指向本地文件
      const data = new systemShare.SharedData({
        utd: 'general.image',
        uri: payload.fileUri,
        title: payload.title,
        description: payload.description,
        thumbnail: payload.thumbnail,
      })
      const controller = new systemShare.ShareController(data)
      await controller.show(ctx, {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE,
      })
      logger.info(TAG, 'shareImage panel shown successfully')
      return true
    } catch (e) {
      const be = e as BusinessError
      const code = be && be.code !== undefined ? be.code : 'n/a'
      const msg = be && be.message ? be.message : JSON.stringify(e)
      logger.error(TAG, `shareImage failed: code=${code} message=${msg}`)
      return false
    }
  }
}
