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

/**
 * 应用 UI 颜色和主题定义
 */
export class AppColors {
  static readonly PRIMARY: string = '#1890FF'
  static readonly PRIMARY_DARK: string = '#0050B3'
  static readonly BACKGROUND: string = '#F5F6F8'
  static readonly CARD_BG: string = '#FFFFFF'
  static readonly TEXT_PRIMARY: string = '#1A1A1A'
  static readonly TEXT_SECONDARY: string = '#666666'
  static readonly TEXT_HINT: string = '#999999'
  static readonly DIVIDER: string = '#E8E8E8'
  static readonly DANGER: string = '#FF4D4F'
  static readonly SUCCESS: string = '#52C41A'
  static readonly PLACEHOLDER_BG: string = '#D6E8F5'
  static readonly PLACEHOLDER_TEXT: string = '#8EB4D6'
  static readonly PLACEHOLDER_BG_DARK: string = '#2E4A6A'
  static readonly PLACEHOLDER_TEXT_LIGHT: string = '#A8C4DE'
}

/**
 * 应用尺寸和间距定义
 */
export class AppDimens {
  static readonly PADDING_SM: number = 8
  static readonly PADDING_MD: number = 16
  static readonly PADDING_LG: number = 24
  static readonly RADIUS_SM: number = 8
  static readonly RADIUS_MD: number = 12
  static readonly RADIUS_LG: number = 16
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

/**
 * 路由 URL 常量
 */
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
  static readonly PROFILE_EDIT: string = 'feature/profile/pages/ProfileEditPage'
}
