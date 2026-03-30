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

import { PhotoPickerUtil } from '../../../common';
import { AppColors, AppDimens } from '../../../common';
import { promptAction } from '@kit.ArkUI';

/**
 * 照片选择器组件
 *
 * 功能：
 * - 展示已选照片网格
 * - "+" 按钮触发相册选择
 * - 支持删除已选照片
 *
 * @param photos 照片列表（通过 Link 与父组件共享状态）
 * @param onPhotosChange 照片变化回调
 * @param maxPhotos 最大选择数量，默认 9 张
 */
@Component
export struct PhotoSelector {
  @Link photos: string[];
  onPhotosChange?: (photos: string[]) => void;
  maxPhotos: number = 9;

  /**
   * 处理添加照片
   */
  async handleAddPhoto(): Promise<void> {
    const remaining = this.maxPhotos - this.photos.length;
    if (remaining <= 0) {
      promptAction.showToast({
        message: `最多可选择${this.maxPhotos}张照片`,
        duration: 2000
      });
      return;
    }

    try {
      const newPhotos = await PhotoPickerUtil.pickImages(remaining);
      this.photos = [...this.photos, ...newPhotos];
      this.onPhotosChange?.(this.photos);
    } catch (err) {
      promptAction.showToast({
        message: '选择照片失败',
        duration: 2000
      });
    }
  }

  /**
   * 处理删除照片
   * @param index 要删除的照片索引
   */
  handleDeletePhoto(index: number): void {
    this.photos.splice(index, 1);
    this.onPhotosChange?.(this.photos);
  }

  /**
   * 预览照片
   * @param uri 照片 URI
   */
  handlePreviewPhoto(uri: string): void {
    // TODO: 后续可实现全屏查看预览
    promptAction.showToast({
      message: '预览功能待实现',
      duration: 1500
    });
  }

  @Builder
  PhotoItem(photoUri: string, index: number) {
    Stack() {
      Image(photoUri)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .onClick(() => this.handlePreviewPhoto(photoUri))

      // 删除按钮（使用 Text 代替系统资源）
      Text('×')
        .fontSize(20)
        .fontColor('#FFFFFF')
        .backgroundColor('#FF4D4F')
        .width(20)
        .height(20)
        .textAlign(TextAlign.Center)
        .position({ x: '85%', y: '5%' })
        .onClick(() => this.handleDeletePhoto(index))
    }
    .width(80)
    .height(80)
    .borderRadius(AppDimens.RADIUS_SM)
    .backgroundColor(AppColors.CARD_BG)
  }

  @Builder
  AddButton() {
    Column() {
      Text('+')
        .fontSize(28)
        .fontColor(AppColors.TEXT_HINT)
      Text('添加照片')
        .fontSize(AppDimens.FONT_SM)
        .fontColor(AppColors.TEXT_HINT)
        .margin({ top: 4 })
    }
    .width(80)
    .height(80)
    .backgroundColor(AppColors.BACKGROUND)
    .borderRadius(AppDimens.RADIUS_SM)
    .justifyContent(FlexAlign.Center)
    .onClick(() => this.handleAddPhoto())
  }

  build() {
    Column() {
      Text('照片')
        .fontSize(AppDimens.FONT_MD)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColors.TEXT_PRIMARY)
        .width('100%')

      // 照片网格布局
      Flex({ wrap: FlexWrap.Wrap }) {
        // 已选照片
        ForEach(this.photos, (photoUri: string, index: number) => {
          this.PhotoItem(photoUri, index)
        })

        // 添加按钮（未达到上限时显示）
        if (this.photos.length < this.maxPhotos) {
          this.AddButton()
        }
      }
      .margin({ top: 8 })
      .width('100%')
    }
    .width('100%')
    .padding(AppDimens.PADDING_MD)
    .backgroundColor(AppColors.CARD_BG)
    .borderRadius(AppDimens.RADIUS_SM)
    .alignItems(HorizontalAlign.Start)
  }
}
