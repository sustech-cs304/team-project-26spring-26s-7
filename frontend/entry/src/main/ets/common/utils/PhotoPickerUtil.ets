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
import { BusinessError } from '@ohos.base';
import { logger } from './Logger';

const TAG = 'PhotoPickerUtil';

/**
 * 照片选择工具类
 * 封装鸿蒙系统相册选择 API
 */
export class PhotoPickerUtil {
  /**
   * 从系统相册选择图片
   * @param maxCount 最大选择数量，默认 9 张
   * @returns Promise<string[]> 选中的图片 URI 数组
   */
  static async pickImages(maxCount: number = 9): Promise<string[]> {
    const photoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
    photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    photoSelectOptions.maxSelectNumber = maxCount;

    const photoViewPicker = new photoAccessHelper.PhotoViewPicker();
    try {
      const result = await photoViewPicker.select(photoSelectOptions);
      logger.info(TAG, `pickImages success, count=${result.photoUris.length}`);
      return result.photoUris;
    } catch (err) {
      const error = err as BusinessError;
      logger.error(TAG, `pickImages failed: code=${error.code}, message=${error.message}`);
      // ArkTS 要求 throw 必须是 Error 类型
      throw new Error(`PhotoPickerUtil.pickImages failed: ${error.message}`);
    }
  }
}
