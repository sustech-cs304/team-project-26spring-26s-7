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

import { common } from '@kit.AbilityKit';
import { AppColors, AppDimens, PhotoPickerUtil } from '../../../common';

/**
 * 照片选择器组件
 *
 * 功能：
 * 1. 显示已选照片网格（最多 9 张）
 * 2. 添加/删除照片操作
 * 3. 调用 PhotoPickerUtil 实现沙箱存储
 *
 * 使用方式：
 * @Link photos: string[]  // 双向绑定到父组件的照片数组
 * PhotoSelector({ photos: $photos, maxPhotos: 9 })
 */
@Component
export struct PhotoSelector {
  /** 已选照片路径数组（双向绑定） */
  @Link photos: string[];
  /** 最大照片数量 */
  @Prop maxPhotos: number = 9;
  /** 每行显示的照片数量 */
  private readonly COLUMNS: number = 4;
  /** 照片单元格大小 */
  private readonly CELL_SIZE: number = 80;
  /** 单元格间距 */
  private readonly CELL_GAP: number = 8;

  /**
   * 处理照片选择
   */
  private async handlePickPhoto(): Promise<void> {
    // 检查是否已达到最大数量
    if (this.photos.length >= this.maxPhotos) {
      return;
    }

    try {
      // 获取 UIAbilityContext
      const context = getContext(this) as common.UIAbilityContext;

      // 计算剩余可选数量
      const remainingCount = this.maxPhotos - this.photos.length;

      // 调用照片选择工具
      const newPaths = await PhotoPickerUtil.pickAndSavePhotos(context, remainingCount);

      if (newPaths.length > 0) {
        // 添加新选择的照片
        this.photos = [...this.photos, ...newPaths];
      }
    } catch (err) {
      console.error(`PhotoSelector handlePickPhoto failed: ${JSON.stringify(err)}`);
    }
  }

  /**
   * 删除指定位置的照片
   */
  private handleRemovePhoto(index: number): void {
    if (index >= 0 && index < this.photos.length) {
      // 从数组中移除
      const newPhotos = [...this.photos];
      newPhotos.splice(index, 1);
      this.photos = newPhotos;
    }
  }

  /**
   * 渲染单个照片单元格
   */
  @Builder
  PhotoCell(photoPath: string, index: number) {
    Stack() {
      // 照片缩略图
      Image(photoPath)
        .width(this.CELL_SIZE)
        .height(this.CELL_SIZE)
        .objectFit(ImageFit.Cover)
        .borderRadius(AppDimens.RADIUS_SM)

      // 删除按钮（右上角）
      Text('×')
        .fontSize(16)
        .fontColor('#FFFFFF')
        .backgroundColor('rgba(0, 0, 0, 0.6)')
        .width(20)
        .height(20)
        .borderRadius(10)
        .textAlign(TextAlign.Center)
        .position({ x: this.CELL_SIZE - 10, y: -10 })
        .onClick(() => this.handleRemovePhoto(index))
    }
    .width(this.CELL_SIZE)
    .height(this.CELL_SIZE)
  }

  /**
   * 渲染添加按钮
   */
  @Builder
  AddButton() {
    Column() {
      Text('+')
        .fontSize(28)
        .fontColor(AppColors.TEXT_HINT)
      Text('添加')
        .fontSize(AppDimens.FONT_SM)
        .fontColor(AppColors.TEXT_HINT)
    }
    .width(this.CELL_SIZE)
    .height(this.CELL_SIZE)
    .backgroundColor(AppColors.BACKGROUND)
    .borderRadius(AppDimens.RADIUS_SM)
    .justifyContent(FlexAlign.Center)
    .onClick(() => this.handlePickPhoto())
  }

  build() {
    Column() {
      // 标题行
      Row() {
        Text('照片')
          .fontSize(AppDimens.FONT_MD)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_PRIMARY)

        Text(`${this.photos.length}/${this.maxPhotos}`)
          .fontSize(AppDimens.FONT_SM)
          .fontColor(AppColors.TEXT_SECONDARY)
          .margin({ left: 8 })
      }
      .width('100%')
      .margin({ bottom: 8 })

      // 照片网格
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        // 已选照片
        ForEach(this.photos, (photo: string, index: number) => {
          Column() {
            this.PhotoCell(photo, index)
          }
          .margin({ right: this.CELL_GAP, bottom: this.CELL_GAP })
        })

        // 添加按钮（未满时显示）
        if (this.photos.length < this.maxPhotos) {
          Column() {
            this.AddButton()
          }
          .margin({ right: this.CELL_GAP, bottom: this.CELL_GAP })
        }
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}