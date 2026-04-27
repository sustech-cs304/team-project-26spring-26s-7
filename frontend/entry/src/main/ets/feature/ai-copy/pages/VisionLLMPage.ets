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

import { router } from '@kit.ArkUI';
import { AppColors, AppDimens } from '../../../common';
import { VisionLLMTest } from '../components/VisionLLMTest';

/**
 * 视觉 LLM 分析页面
 * 提供图片选择和视觉 LLM 分析功能
 */
@Entry
@Component
export struct VisionLLMPage {
  @StorageLink('appThemeVersion') themeVersion: number = 0
  aboutToAppear(): void {
    console.log('VisionLLMPage loaded');
  }

  build() {
    Column() {
      // 头部栏
      Row() {
        Text('←')
          .fontSize(AppDimens.FONT_XL)
          .fontColor(AppColors.TEXT_PRIMARY)
          .onClick(() => router.back())
          .padding(AppDimens.PADDING_MD)

        Text('视觉 LLM 分析')
          .fontSize(AppDimens.FONT_LG)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .backgroundColor(AppColors.CARD_BG)

      // 内容区域
      Scroll() {
        Column() {
          // 使用说明
          Column() {
            Text('功能介绍')
              .fontSize(AppDimens.FONT_MD)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)
              .margin({ bottom: 8 })

            Text('此功能可以调用视觉 LLM（如 Qwen-VL）分析图片内容。您可以上传图片并提问，AI 会描述图片内容或回答相关问题。')
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_SECONDARY)
              .lineHeight(1.6)
              .margin({ bottom: 8 })

            Text('API 端点: http://172.18.35.215:8000/v1/chat/completions/image')
              .fontSize(AppDimens.FONT_XS)
              .fontColor(AppColors.TEXT_SECONDARY)
              .textAlign(TextAlign.Start)
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_SM)
          .margin({ bottom: 16 })

          // 测试组件
          // 注意：实际使用时需要传入 context
          VisionLLMTest()
        }
        .padding(AppDimens.PADDING_MD)
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.BACKGROUND)
  }
}
