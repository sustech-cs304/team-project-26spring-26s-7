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

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { logger } from './Logger';

const TAG = 'ConsentManager';
const STORE_NAME = 'ai_consent_v1';

/** 偏好键 / AppStorage 键 */
const KEY_CLOUD_TAGGING_ENABLED = 'aiCloudTaggingEnabled';
const KEY_CLOUD_TAGGING_PROMPTED = 'aiCloudTaggingPrompted';
const KEY_APP_PRIVACY_AGREED = 'appPrivacyAgreed';
const KEY_APP_PRIVACY_VERSION = 'appPrivacyVersion';

/** 隐私协议当前版本号；变更后需让用户重新同意 */
const CURRENT_PRIVACY_VERSION = 1;

/**
 * AI 云端能力的同意状态管理
 *
 * 拆成两个独立标志：
 *   - prompted：是否已经向用户展示过 JIT 同意对话框（避免重复打扰）
 *   - enabled：用户是否同意把照片送到云端做内容识别
 *
 * 持久化走 @kit.ArkData preferences；运行时同步到 AppStorage 方便页面订阅。
 * 默认值都是 false：满足 AppGallery"默认不收集敏感个人信息"的合规期待。
 */
export class ConsentManager {
  private static loaded: boolean = false;

  /** 首次访问前必须调用一次（建议在使用消费方页面 aboutToAppear 里执行） */
  static async ensureLoaded(context: common.UIAbilityContext): Promise<void> {
    if (ConsentManager.loaded) {
      return;
    }
    try {
      const store = await preferences.getPreferences(context, { name: STORE_NAME });
      const enabled = await store.get(KEY_CLOUD_TAGGING_ENABLED, false) as boolean;
      const prompted = await store.get(KEY_CLOUD_TAGGING_PROMPTED, false) as boolean;
      AppStorage.setOrCreate(KEY_CLOUD_TAGGING_ENABLED, enabled);
      AppStorage.setOrCreate(KEY_CLOUD_TAGGING_PROMPTED, prompted);
      ConsentManager.loaded = true;
      logger.info(TAG, `Loaded consent: enabled=${enabled}, prompted=${prompted}`);
    } catch (err) {
      logger.error(TAG, `ensureLoaded failed: ${JSON.stringify(err)}`);
      // 加载失败按"未同意"处理，宁可退化也不悄悄上传
      AppStorage.setOrCreate(KEY_CLOUD_TAGGING_ENABLED, false);
      AppStorage.setOrCreate(KEY_CLOUD_TAGGING_PROMPTED, false);
      ConsentManager.loaded = true;
    }
  }

  /** 用户是否已同意把照片用于云端内容识别 */
  static isCloudTaggingEnabled(): boolean {
    return (AppStorage.get(KEY_CLOUD_TAGGING_ENABLED) as boolean) === true;
  }

  /** 是否曾经被询问过（同意或拒绝都算） */
  static hasPrompted(): boolean {
    return (AppStorage.get(KEY_CLOUD_TAGGING_PROMPTED) as boolean) === true;
  }

  /**
   * 设置页调用：仅切换"是否开启"开关本身，不代表 JIT 已知情。
   * 关键差别：开启时强制把 prompted 复位为 false，这样下次走 AI 上传仍要弹 JIT。
   * 关闭时保留 prompted 现状（用户已经做出过明确选择）。
   */
  static async setCloudTaggingEnabled(
    context: common.UIAbilityContext,
    enabled: boolean
  ): Promise<void> {
    AppStorage.setOrCreate(KEY_CLOUD_TAGGING_ENABLED, enabled);
    if (enabled) {
      AppStorage.setOrCreate(KEY_CLOUD_TAGGING_PROMPTED, false);
    }
    try {
      const store = await preferences.getPreferences(context, { name: STORE_NAME });
      await store.put(KEY_CLOUD_TAGGING_ENABLED, enabled);
      if (enabled) {
        await store.put(KEY_CLOUD_TAGGING_PROMPTED, false);
      }
      await store.flush();
      logger.info(TAG, `Settings toggle: enabled=${enabled}`);
    } catch (err) {
      logger.error(TAG, `persist failed: ${JSON.stringify(err)}`);
    }
  }

  /**
   * AI 页 JIT 对话框调用：用户作出明确同意/拒绝后写入。
   * 同意 -> enabled=true, prompted=true
   * 拒绝 -> enabled=false, prompted=true（已明确，不再打扰）
   */
  static async recordPromptResult(
    context: common.UIAbilityContext,
    agreed: boolean
  ): Promise<void> {
    AppStorage.setOrCreate(KEY_CLOUD_TAGGING_ENABLED, agreed);
    AppStorage.setOrCreate(KEY_CLOUD_TAGGING_PROMPTED, true);
    try {
      const store = await preferences.getPreferences(context, { name: STORE_NAME });
      await store.put(KEY_CLOUD_TAGGING_ENABLED, agreed);
      await store.put(KEY_CLOUD_TAGGING_PROMPTED, true);
      await store.flush();
      logger.info(TAG, `JIT prompt result: agreed=${agreed}`);
    } catch (err) {
      logger.error(TAG, `persist failed: ${JSON.stringify(err)}`);
    }
  }

  // ==================== 应用级隐私协议（首启强制弹窗） ====================

  /**
   * 用户是否已经同意当前版本的应用隐私协议。
   * AppGallery 上架要求首启必须强制弹窗，用户同意才能进入主功能。
   */
  static async isAppPrivacyAgreed(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const store = await preferences.getPreferences(context, { name: STORE_NAME });
      const agreed = await store.get(KEY_APP_PRIVACY_AGREED, false) as boolean;
      const version = await store.get(KEY_APP_PRIVACY_VERSION, 0) as number;
      // 协议升版需重新同意
      return agreed === true && version >= CURRENT_PRIVACY_VERSION;
    } catch (err) {
      logger.error(TAG, `isAppPrivacyAgreed failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  /** 用户点击"同意并继续"后调用 */
  static async setAppPrivacyAgreed(context: common.UIAbilityContext): Promise<void> {
    try {
      const store = await preferences.getPreferences(context, { name: STORE_NAME });
      await store.put(KEY_APP_PRIVACY_AGREED, true);
      await store.put(KEY_APP_PRIVACY_VERSION, CURRENT_PRIVACY_VERSION);
      await store.flush();
      AppStorage.setOrCreate(KEY_APP_PRIVACY_AGREED, true);
      logger.info(TAG, `App privacy agreed at version ${CURRENT_PRIVACY_VERSION}`);
    } catch (err) {
      logger.error(TAG, `setAppPrivacyAgreed failed: ${JSON.stringify(err)}`);
    }
  }

  /** 注销账号或重置时调用：清除所有同意状态 */
  static async clearAllConsents(context: common.UIAbilityContext): Promise<void> {
    try {
      const store = await preferences.getPreferences(context, { name: STORE_NAME });
      await store.clear();
      await store.flush();
      AppStorage.setOrCreate(KEY_CLOUD_TAGGING_ENABLED, false);
      AppStorage.setOrCreate(KEY_CLOUD_TAGGING_PROMPTED, false);
      AppStorage.setOrCreate(KEY_APP_PRIVACY_AGREED, false);
      ConsentManager.loaded = false;
      logger.info(TAG, 'All consents cleared');
    } catch (err) {
      logger.error(TAG, `clearAllConsents failed: ${JSON.stringify(err)}`);
    }
  }
}

export const KEY_AI_CLOUD_TAGGING_ENABLED: string = KEY_CLOUD_TAGGING_ENABLED;
export const KEY_AI_CLOUD_TAGGING_PROMPTED: string = KEY_CLOUD_TAGGING_PROMPTED;
export const KEY_APP_PRIVACY_AGREED_EXPORT: string = KEY_APP_PRIVACY_AGREED;
