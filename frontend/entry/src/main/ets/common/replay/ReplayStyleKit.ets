export enum ReplayStyleKitId {
  MINIMAL_WHITE = 'minimal_white',
  DARK_NIGHT = 'dark_night',
  VINTAGE_FILM = 'vintage_film'
}

export interface ReplayStyleKitOption {
  id: ReplayStyleKitId
  title: string
  subtitle: string
  previewColor: string
}

export class ReplayStyleKitCatalog {
  static readonly DEFAULT_ID: ReplayStyleKitId = ReplayStyleKitId.MINIMAL_WHITE

  static list(): ReplayStyleKitOption[] {
    return [
      {
        id: ReplayStyleKitId.MINIMAL_WHITE,
        title: '极简白',
        subtitle: '沿用当前默认回放样式',
        previewColor: '#F5F5F5'
      },
      {
        id: ReplayStyleKitId.DARK_NIGHT,
        title: '暗夜蓝',
        subtitle: '深色卡片与冷色路线氛围',
        previewColor: '#1A1A1A'
      },
      {
        id: ReplayStyleKitId.VINTAGE_FILM,
        title: '复古胶片',
        subtitle: '暖纸质感与复古回放卡片',
        previewColor: '#D9C2A3'
      }
    ]
  }
}
