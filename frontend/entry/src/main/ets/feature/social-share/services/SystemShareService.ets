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
 * url     —— 限时分享 URL（必填，会作为 hyperlink 主体）
 * title   —— 在分享卡片头部显示的标题，如 "深圳湾骑行 - TravelPin"
 * description —— 摘要，如 "4 个节点 · 12.5km · 始于红树林"
 */
export interface SystemSharePayload {
  url: string
  title: string
  description: string
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
    try {
      // 'general.url' 是 Uniform Data Type 标准类型描述符，让接收方
      // （微信 / QQ / 微博 / 浏览器）按 hyperlink 处理 + 抓取 OG meta。
      const data = new systemShare.SharedData({
        utd: 'general.url',
        content: payload.url,
        title: payload.title,
        description: payload.description,
      })
      const controller = new systemShare.ShareController(data)

      // SharePreviewMode.DETAIL 让面板顶部显示标题 + 摘要 + URL，
      // 视觉效果接近一张卡片。SelectionMode.SINGLE 表示用户选一个目标即结束。
      await controller.show(ctx, {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE,
      })

      logger.info(TAG, 'systemShare panel shown successfully')
      return true
    } catch (e) {
      const be = e as BusinessError
      const msg = be && be.message ? be.message : JSON.stringify(e)
      logger.warn(TAG, `systemShare failed: ${msg}`)
      return false
    }
  }
}
