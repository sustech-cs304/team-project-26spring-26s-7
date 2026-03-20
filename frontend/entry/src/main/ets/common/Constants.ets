/**
 * 应用全局常量
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
}

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

export class RouterUrls {
  static readonly INDEX: string = 'pages/Index'
  static readonly LOGIN: string = 'pages/LoginPage'
  static readonly MAIN: string = 'pages/MainPage'
  static readonly NODE_EDIT: string = 'pages/NodeEditPage'
  static readonly NODE_DETAIL: string = 'pages/NodeDetailPage'
  static readonly TRIP_DETAIL: string = 'pages/TripDetailPage'
  static readonly TRIP_REPLAY: string = 'pages/TripReplayPage'
  static readonly SHARE: string = 'pages/SharePage'
}
