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

import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { AppColors, AppDimens, VisionLLMClient, VisionLLMRequest, PhotoPickerUtil, logger } from '../../../common';

const TAG = 'VisionLLMTest';

/**
 * 视觉 LLM 测试组件
 * 用于测试图像 LLM 调用功能
 */
@Component
export struct VisionLLMTest {
  // 组件状态
  @State imagePath: string = '';
  @State question: string = '这张图里有什么？';
  @State isGenerating: boolean = false;
  @State result: string = '';
  @State error: string = '';

  // 客户端实例
  private client: VisionLLMClient = new VisionLLMClient();

  /**
   * 选择图片
   */
  private async handleSelectImage(): Promise<void> {
    try {
      logger.info(TAG, 'Starting photo selection for Vision LLM');

      // 获取 UIContext 和 HostContext
      const uicontext = this.getUIContext();
      logger.info(TAG, `UIContext obtained: ${uicontext ? 'success' : 'failed'}`);

      const context = uicontext.getHostContext() as common.UIAbilityContext;
      logger.info(TAG, `HostContext obtained: ${context ? 'success' : 'failed'}`);

      if (!context) {
        logger.error(TAG, 'Failed to get UIAbilityContext');
        promptAction.showToast({ message: '无法获取应用上下文，请重试' });
        return;
      }

      // 调用照片选择工具，只选择1张图片
      logger.info(TAG, 'Calling PhotoPickerUtil.pickAndSavePhotos...');
      const newPaths = await PhotoPickerUtil.pickAndSavePhotos(context, 1);
      logger.info(TAG, `pickAndSavePhotos returned: ${newPaths.length} photos`);

      if (newPaths.length > 0) {
        this.imagePath = newPaths[0];
        logger.info(TAG, `Selected image path: ${this.imagePath}`);
        promptAction.showToast({ message: '图片选择成功' });
      } else {
        logger.info(TAG, 'No photo selected');
        promptAction.showToast({ message: '未选择图片' });
      }
    } catch (err) {
      const errorMsg = `选择图片失败: ${JSON.stringify(err)}`;
      logger.error(TAG, errorMsg);
      promptAction.showToast({ message: errorMsg });
    }
  }

  /**
   * 调用视觉 LLM
   */
  private async handleAskImage(): Promise<void> {
    if (!this.imagePath) {
      promptAction.showToast({ message: '请先选择图片' });
      return;
    }

    if (!this.question.trim()) {
      promptAction.showToast({ message: '请输入问题' });
      return;
    }

    this.isGenerating = true;
    this.result = '';
    this.error = '';

    try {
      const request: VisionLLMRequest = {
        imagePath: this.imagePath,
        question: this.question,
        modelName: 'Qwen-VL-Chat-Int4',
        temperature: 1.0,
        topP: 0.8
      };

      const response = await this.client.askImage(request);

      if (response.statusCode === 200 && response.data) {
        this.result = response.data.content;
        promptAction.showToast({ message: '分析成功' });
      } else {
        this.error = response.error || '请求失败';
        promptAction.showToast({ message: `分析失败: ${this.error}` });
      }
    } catch (err) {
      const errorMsg = `调用异常: ${JSON.stringify(err)}`;
      this.error = errorMsg;
      promptAction.showToast({ message: errorMsg });
    } finally {
      this.isGenerating = false;
    }
  }

  /**
   * 清空结果
   */
  private handleClear(): void {
    this.imagePath = '';
    this.question = '这张图里有什么？';
    this.result = '';
    this.error = '';
  }

  build() {
    Column() {
      // 标题
      Text('视觉 LLM 测试')
        .fontSize(AppDimens.FONT_XL)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.TEXT_PRIMARY)
        .margin({ bottom: 24 })

      // 图片选择区域
      Column() {
        Text('选择图片')
          .fontSize(AppDimens.FONT_MD)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_PRIMARY)
          .margin({ bottom: 8 })

        if (this.imagePath) {
          // 显示图片预览
          Column({ space: 8 }) {
            Image(this.imagePath)
              .width(120)
              .height(120)
              .objectFit(ImageFit.Contain)
              .borderRadius(AppDimens.RADIUS_SM)
              .backgroundColor(AppColors.BACKGROUND)
              .interpolation(ImageInterpolation.High)

            Text(`已选择: ${this.imagePath.substring(this.imagePath.lastIndexOf('/') + 1)}`)
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_SECONDARY)
          }
          .justifyContent(FlexAlign.Center)
          .margin({ bottom: 8 })
        }

        Button('选择图片')
          .fontSize(AppDimens.FONT_MD)
          .width('100%')
          .height(40)
          .backgroundColor(AppColors.PRIMARY)
          .fontColor(Color.White)
          .onClick(() => this.handleSelectImage())
          .margin({ bottom: 12 })
      }
      .width('100%')
      .padding(AppDimens.PADDING_MD)
      .backgroundColor(AppColors.CARD_BG)
      .borderRadius(AppDimens.RADIUS_SM)
      .margin({ bottom: 16 })

      // 问题输入区域
      Column() {
        Text('输入问题')
          .fontSize(AppDimens.FONT_MD)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_PRIMARY)
          .margin({ bottom: 8 })

        TextInput({ placeholder: '请输入关于图片的问题...', text: this.question })
          .fontSize(AppDimens.FONT_MD)
          .padding(AppDimens.PADDING_MD)
          .height(60)
          .backgroundColor(AppColors.BACKGROUND)
          .borderRadius(AppDimens.RADIUS_SM)
          .onChange((value: string) => { this.question = value })
          .margin({ bottom: 12 })
      }
      .width('100%')
      .padding(AppDimens.PADDING_MD)
      .backgroundColor(AppColors.CARD_BG)
      .borderRadius(AppDimens.RADIUS_SM)
      .margin({ bottom: 16 })

      // 操作按钮
      Row({ space: 12 }) {
        Button(this.isGenerating ? '分析中...' : '开始分析')
          .fontSize(AppDimens.FONT_MD)
          .layoutWeight(1)
          .height(45)
          .backgroundColor(AppColors.PRIMARY)
          .fontColor(Color.White)
          .enabled(!this.isGenerating && this.imagePath.length > 0)
          .onClick(() => this.handleAskImage())

        Button('清空')
          .fontSize(AppDimens.FONT_MD)
          .layoutWeight(1)
          .height(45)
          .backgroundColor(AppColors.BACKGROUND)
          .fontColor(AppColors.TEXT_SECONDARY)
          .enabled(!this.isGenerating)
          .onClick(() => this.handleClear())
      }
      .width('100%')
      .margin({ bottom: 16 })

      // 结果展示区域
      if (this.result) {
        Column() {
          Text('分析结果')
            .fontSize(AppDimens.FONT_MD)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_PRIMARY)
            .margin({ bottom: 8 })

          Scroll() {
            Text(this.result)
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_PRIMARY)
              .lineHeight(24)
          }
          .width('100%')
          .height(200)
          .padding(AppDimens.PADDING_MD)
          .backgroundColor(AppColors.BACKGROUND)
          .borderRadius(AppDimens.RADIUS_SM)
        }
        .width('100%')
        .padding(AppDimens.PADDING_MD)
        .backgroundColor(AppColors.CARD_BG)
        .borderRadius(AppDimens.RADIUS_SM)
        .margin({ bottom: 16 })
      }

      // 错误展示
      if (this.error) {
        Column() {
          Text('错误信息')
            .fontSize(AppDimens.FONT_SM)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.Red)
            .margin({ bottom: 4 })

          Text(this.error)
            .fontSize(AppDimens.FONT_SM)
            .fontColor(Color.Red)
            .lineHeight(22)
        }
        .width('100%')
        .padding(AppDimens.PADDING_MD)
        .backgroundColor(Color.Red + '10')
        .borderRadius(AppDimens.RADIUS_SM)
        .border({ width: 1, color: Color.Red })
      }

      // 使用说明
      Column() {
        Text('使用说明')
          .fontSize(AppDimens.FONT_SM)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_SECONDARY)
          .margin({ bottom: 4 })

        Text('1. 点击"选择图片"按钮选择一张图片\n2. 输入关于图片的问题\n3. 点击"开始分析"按钮调用视觉 LLM\n4. 查看分析结果')
          .fontSize(AppDimens.FONT_XS)
          .fontColor(AppColors.TEXT_SECONDARY)
          .lineHeight(24)
      }
      .width('100%')
      .padding(AppDimens.PADDING_MD)
      .backgroundColor(AppColors.CARD_BG)
      .borderRadius(AppDimens.RADIUS_SM)
      .margin({ top: 16 })
    }
    .width('100%')
    .padding(AppDimens.PADDING_MD)
    .backgroundColor(AppColors.BACKGROUND)
  }
}