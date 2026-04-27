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
  PRIMARY: '#1890FF',
  PRIMARY_DARK: '#0050B3',
  BACKGROUND: '#F5F6F8',
  CARD_BG: '#FFFFFF',
  TEXT_PRIMARY: '#1A1A1A',
  TEXT_SECONDARY: '#666666',
  TEXT_HINT: '#999999',
  TEXT_ON_PRIMARY: '#FFFFFF',
  DIVIDER: '#E8E8E8',
  DANGER: '#FF4D4F',
  SUCCESS: '#52C41A',
  INPUT_BG: '#F5F6F8',
  INPUT_TEXT: '#1A1A1A',
  INPUT_PLACEHOLDER: '#999999',
  INPUT_CARET: '#1890FF'
}

const DARK_THEME: ThemePalette = {
  PRIMARY: '#69B1FF',
  PRIMARY_DARK: '#3C89E8',
  BACKGROUND: '#111418',
  CARD_BG: '#1B2128',
  TEXT_PRIMARY: '#F5F7FA',
  TEXT_SECONDARY: '#C4CCD4',
  TEXT_HINT: '#8B98A7',
  TEXT_ON_PRIMARY: '#F5F7FA',
  DIVIDER: '#2B333D',
  DANGER: '#FF7875',
  SUCCESS: '#95DE64',
  INPUT_BG: '#242B34',
  INPUT_TEXT: '#F5F7FA',
  INPUT_PLACEHOLDER: '#8B98A7',
  INPUT_CARET: '#69B1FF'
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
  static readonly RADIUS_SM: number = 8
  static readonly RADIUS_MD: number = 12
  static readonly RADIUS_LG: number = 16
  static readonly FONT_XS: number = 10
  static readonly FONT_SM: number = 12
  static readonly FONT_MD: number = 14
  static readonly FONT_LG: number = 16
  static readonly FONT_XL: number = 20
  static readonly FONT_TITLE: number = 24
}

export class TravelSpecialValues {
  static readonly UNCATEGORIZED_TRAVEL_ID: string = '-1'
  static readonly UNCATEGORIZED_TRAVEL_NAME: string = '未分类节点'
}

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
}
