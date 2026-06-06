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

import { ConfigurationConstant } from '@kit.AbilityKit'

export interface ThemePalette {
  readonly PRIMARY: string
  readonly PRIMARY_DARK: string
  readonly BACKGROUND: string
  readonly CARD_BG: string
  readonly TEXT_PRIMARY: string
  readonly TEXT_SECONDARY: string
  readonly TEXT_HINT: string
  readonly TEXT_ON_PRIMARY: string
  readonly DIVIDER: string
  readonly DANGER: string
  readonly SUCCESS: string
  readonly INPUT_BG: string
  readonly INPUT_TEXT: string
  readonly INPUT_PLACEHOLDER: string
  readonly INPUT_CARET: string
}

const LIGHT_THEME: ThemePalette = {
  PRIMARY: '#FF6A1A',
  PRIMARY_DARK: '#18221D',
  BACKGROUND: '#F4F5F6',
  CARD_BG: '#FFFFFF',
  TEXT_PRIMARY: '#1D1F1E',
  TEXT_SECONDARY: '#62645F',
  TEXT_HINT: '#9B9A93',
  TEXT_ON_PRIMARY: '#FFFFFF',
  DIVIDER: '#E7E8EA',
  DANGER: '#E0483E',
  SUCCESS: '#4F8C67',
  INPUT_BG: '#F2FFFFFF',
  INPUT_TEXT: '#1D1F1E',
  INPUT_PLACEHOLDER: '#A7A49C',
  INPUT_CARET: '#FF6A1A'
}

const DARK_THEME: ThemePalette = {
  PRIMARY: '#FF8A45',
  PRIMARY_DARK: '#EEF1E8',
  BACKGROUND: '#121513',
  CARD_BG: '#1E2420',
  TEXT_PRIMARY: '#F5F1EA',
  TEXT_SECONDARY: '#D2CCC2',
  TEXT_HINT: '#9F988E',
  TEXT_ON_PRIMARY: '#121513',
  DIVIDER: '#343A35',
  DANGER: '#FF7A70',
  SUCCESS: '#8ED0A6',
  INPUT_BG: '#CC2A302B',
  INPUT_TEXT: '#F5F1EA',
  INPUT_PLACEHOLDER: '#9F988E',
  INPUT_CARET: '#FF8A45'
}

export class AppTheme {
  static readonly COLOR_MODE_STORAGE_KEY: string = 'appColorMode'
  static readonly VERSION_STORAGE_KEY: string = 'appThemeVersion'

  static initialize(colorMode?: number): void {
    AppTheme.applyColorMode(colorMode, true)
  }

  static syncColorMode(colorMode?: number): void {
    AppTheme.applyColorMode(colorMode, false)
  }

  static isDarkMode(): boolean {
    return AppTheme.getColorMode() === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
  }

  static currentPalette(): ThemePalette {
    return AppTheme.isDarkMode() ? DARK_THEME : LIGHT_THEME
  }

  private static getColorMode(): number {
    return AppStorage.get<number>(AppTheme.COLOR_MODE_STORAGE_KEY) ??
      ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
  }

  private static applyColorMode(colorMode: number | undefined, forceRefresh: boolean): void {
    const normalizedColorMode = AppTheme.normalizeColorMode(colorMode)
    const previousColorMode = AppStorage.get<number>(AppTheme.COLOR_MODE_STORAGE_KEY)

    AppStorage.setOrCreate(AppTheme.COLOR_MODE_STORAGE_KEY, normalizedColorMode)

    if (forceRefresh || previousColorMode !== normalizedColorMode) {
      const currentVersion = AppStorage.get<number>(AppTheme.VERSION_STORAGE_KEY) ?? 0
      AppStorage.setOrCreate(AppTheme.VERSION_STORAGE_KEY, currentVersion + 1)
    }
  }

  private static normalizeColorMode(colorMode: number | undefined): number {
    return colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
  }
}

export class AppColors {
  static get PRIMARY(): string {
    return AppTheme.currentPalette().PRIMARY
  }

  static get PRIMARY_DARK(): string {
    return AppTheme.currentPalette().PRIMARY_DARK
  }

  static get BACKGROUND(): string {
    return AppTheme.currentPalette().BACKGROUND
  }

  static get CARD_BG(): string {
    return AppTheme.currentPalette().CARD_BG
  }

  static get TEXT_PRIMARY(): string {
    return AppTheme.currentPalette().TEXT_PRIMARY
  }

  static get TEXT_SECONDARY(): string {
    return AppTheme.currentPalette().TEXT_SECONDARY
  }

  static get TEXT_HINT(): string {
    return AppTheme.currentPalette().TEXT_HINT
  }

  static get DIVIDER(): string {
    return AppTheme.currentPalette().DIVIDER
  }

  static get TEXT_ON_PRIMARY(): string {
    return AppTheme.currentPalette().TEXT_ON_PRIMARY
  }

  static get DANGER(): string {
    return AppTheme.currentPalette().DANGER
  }

  static get SUCCESS(): string {
    return AppTheme.currentPalette().SUCCESS
  }

  static get INPUT_BG(): string {
    return AppTheme.currentPalette().INPUT_BG
  }

  static get INPUT_TEXT(): string {
    return AppTheme.currentPalette().INPUT_TEXT
  }

  static get INPUT_PLACEHOLDER(): string {
    return AppTheme.currentPalette().INPUT_PLACEHOLDER
  }

  static get INPUT_CARET(): string {
    return AppTheme.currentPalette().INPUT_CARET
  }
}

export class AppDimens {
  static readonly PADDING_SM: number = 8
  static readonly PADDING_MD: number = 16
  static readonly PADDING_LG: number = 24
  static readonly RADIUS_SM: number = 12
  static readonly RADIUS_MD: number = 18
  static readonly RADIUS_LG: number = 28
  static readonly RADIUS_PILL: number = 999
  static readonly FONT_XS: number = 10
  static readonly FONT_SM: number = 12
  static readonly FONT_MD: number = 14
  static readonly FONT_LG: number = 16
  static readonly FONT_XL: number = 20
  static readonly FONT_TITLE: number = 24
  static get SHADOW_SOFT(): string {
    return AppTheme.isDarkMode() ? '#66000000' : '#14101820'
  }

  static get SHADOW_FLOAT(): string {
    return AppTheme.isDarkMode() ? '#99000000' : '#24101820'
  }

  static get ACCENT_SOFT_BG(): string {
    return AppTheme.isDarkMode() ? '#33FF8A45' : '#1AFF6A1A'
  }

  static get SURFACE_TINT(): string {
    return AppTheme.isDarkMode() ? '#B8262B28' : '#EEFFFFFF'
  }

  static get GLASS_BORDER(): string {
    return AppTheme.isDarkMode() ? '#38FFFFFF' : '#B8FFFFFF'
  }

  static get CTA_DARK(): string {
    return AppTheme.isDarkMode() ? '#EAF0EA' : '#191919'
  }

  static get PHOTO_SURFACE(): string {
    return AppTheme.isDarkMode() ? '#202622' : '#F3F4F6'
  }
}

export class TravelSpecialValues {
  static readonly UNCATEGORIZED_TRAVEL_ID: string = '-1'
  static readonly UNCATEGORIZED_TRAVEL_NAME: string = '未分类节点'
}

export const DEFAULT_MAP_LATITUDE: number = 22.55
export const DEFAULT_MAP_LONGITUDE: number = 113.96

/**
 * 《人工智能生成合成内容标识办法》第四条要求：AI 生成的文本必须包含
 * "AI"或"人工智能" + "生成"或"合成" 两个要素的显式标识，位置在文本
 * 起始 / 末尾 / 中间皆可。这里固定用前缀写法："AI 生成 · {原文}"——
 * marker 内嵌到 content 字符串里，跟随存储 / 复制 / 分享 viewer 一起
 * 传播，也满足"提供下载、复制、导出功能时应当确保文件中含有显式标识"。
 *
 * 中间用居中点 "·" (U+00B7) 隔开，方便审计时按 marker 字符串精确识别。
 */
export const AI_GENERATED_MARKER: string = 'AI 生成 · '

export class RouterUrls {
  static readonly INDEX: string = 'pages/Index'
  static readonly LOGIN: string = 'pages/LoginPage'
  static readonly MAIN: string = 'pages/MainPage'
  static readonly NODE_EDIT: string = 'feature/map-travel/pages/NodeEditPage'
  static readonly NODE_DETAIL: string = 'feature/map-travel/pages/NodeDetailPage'
  static readonly TRIP_EDIT: string = 'feature/map-travel/pages/TripEditPage'
  static readonly TRIP_DETAIL: string = 'feature/map-travel/pages/TripDetailPage'
  static readonly TRIP_REPLAY: string = 'feature/map-travel/pages/TripReplayPage'
  static readonly LOCATION_PICKER: string = 'feature/map-travel/pages/LocationPickerPage'
  static readonly SHARE: string = 'feature/social-share/pages/SharePage'
  static readonly AI_COPY: string = 'feature/ai-copy/pages/AiCopyPage'
  static readonly VISION_LLM: string = 'feature/ai-copy/pages/VisionLLMPage'
  static readonly PROFILE_EDIT: string = 'feature/profile/pages/ProfileEditPage'
  static readonly PROFILE_AVATAR_CROP: string = 'feature/profile/pages/AvatarCropPage'
  static readonly USER_AGREEMENT: string = 'pages/UserAgreementPage'
  static readonly PRIVACY_POLICY: string = 'pages/PrivacyPolicyPage'
  static readonly HELP_FEEDBACK: string = 'pages/HelpFeedbackPage'
}
