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

export interface ReplayStyleKit {
  id: ReplayStyleKitId
  title: string
  subtitle: string
  previewColor: string
  pageMaskColor: string
  controlBarBackground: string
  controlBarBorderColor: string
  controlPrimaryColor: string
  controlMutedColor: string
  progressTrackColor: string
  progressSelectedColor: string
  progressBlockColor: string
  progressLabelColor: string
  cardPhotoBackground: string
  cardContentBackground: string
  cardTitleColor: string
  cardBodyColor: string
  cardMutedColor: string
  cardTagTextColor: string
  cardTagBackground: string
  overlayMaskColor: string
  overlayPanelBackground: string
  overlayPanelBorderColor: string
  overlayTextColor: string
  overlaySecondaryTextColor: string
  moodTextColor: string
  moodBackgroundColor: string
  rippleColor: string
  shadowColor: string
  mapPolylineColor: string
  mapPolylineWidth: number
  routePendingColor: string
  routePendingWidth: number
  routeVisitedColor: string
  routeVisitedWidth: number
}

const STYLE_KITS: ReplayStyleKit[] = [
  {
    id: ReplayStyleKitId.MINIMAL_WHITE,
    title: '极简白',
    subtitle: '明亮留白，保留当前回放的轻量气质',
    previewColor: '#F4F5F7',
    pageMaskColor: 'rgba(0, 0, 0, 0.16)',
    controlBarBackground: 'rgba(255, 255, 255, 0.96)',
    controlBarBorderColor: 'rgba(24, 144, 255, 0.10)',
    controlPrimaryColor: '#1A1A1A',
    controlMutedColor: '#6B7280',
    progressTrackColor: '#D8E2EF',
    progressSelectedColor: '#1890FF',
    progressBlockColor: '#FFFFFF',
    progressLabelColor: '#364152',
    cardPhotoBackground: '#2D3748',
    cardContentBackground: 'rgba(255, 255, 255, 0.92)',
    cardTitleColor: '#111827',
    cardBodyColor: '#4B5563',
    cardMutedColor: '#6B7280',
    cardTagTextColor: '#1565C0',
    cardTagBackground: 'rgba(21, 101, 192, 0.10)',
    overlayMaskColor: 'rgba(14, 18, 24, 0.52)',
    overlayPanelBackground: '#FFFFFF',
    overlayPanelBorderColor: 'rgba(17, 24, 39, 0.06)',
    overlayTextColor: '#111827',
    overlaySecondaryTextColor: '#5B6472',
    moodTextColor: '#D9485F',
    moodBackgroundColor: 'rgba(217, 72, 95, 0.10)',
    rippleColor: 'rgba(24, 144, 255, 0.28)',
    shadowColor: 'rgba(15, 23, 42, 0.18)',
    mapPolylineColor: '#1890FF',
    mapPolylineWidth: 4,
    routePendingColor: 'rgba(24, 144, 255, 0.22)',
    routePendingWidth: 4,
    routeVisitedColor: '#1890FF',
    routeVisitedWidth: 6
  },
  {
    id: ReplayStyleKitId.DARK_NIGHT,
    title: '暗夜蓝',
    subtitle: '深色卡片与冷色路线，更适合夜景和城市回放',
    previewColor: '#182235',
    pageMaskColor: 'rgba(6, 10, 18, 0.24)',
    controlBarBackground: 'rgba(12, 20, 33, 0.94)',
    controlBarBorderColor: 'rgba(110, 187, 255, 0.18)',
    controlPrimaryColor: '#EAF4FF',
    controlMutedColor: '#9CB4CC',
    progressTrackColor: 'rgba(255, 255, 255, 0.14)',
    progressSelectedColor: '#67B7FF',
    progressBlockColor: '#EAF4FF',
    progressLabelColor: '#D4E6F8',
    cardPhotoBackground: '#0D1420',
    cardContentBackground: 'rgba(8, 15, 25, 0.90)',
    cardTitleColor: '#F5FAFF',
    cardBodyColor: '#CBDBEB',
    cardMutedColor: '#97A8BA',
    cardTagTextColor: '#8ED0FF',
    cardTagBackground: 'rgba(93, 173, 226, 0.16)',
    overlayMaskColor: 'rgba(2, 6, 12, 0.72)',
    overlayPanelBackground: 'rgba(10, 18, 28, 0.94)',
    overlayPanelBorderColor: 'rgba(142, 208, 255, 0.12)',
    overlayTextColor: '#F5FAFF',
    overlaySecondaryTextColor: '#B0C5D9',
    moodTextColor: '#FFB38A',
    moodBackgroundColor: 'rgba(255, 179, 138, 0.12)',
    rippleColor: 'rgba(103, 183, 255, 0.30)',
    shadowColor: 'rgba(0, 0, 0, 0.34)',
    mapPolylineColor: '#67B7FF',
    mapPolylineWidth: 5,
    routePendingColor: 'rgba(103, 183, 255, 0.20)',
    routePendingWidth: 5,
    routeVisitedColor: '#A8D8FF',
    routeVisitedWidth: 7
  },
  {
    id: ReplayStyleKitId.VINTAGE_FILM,
    title: '复古胶片',
    subtitle: '暖棕和纸感质地，让回放更像旅行手账',
    previewColor: '#CDB090',
    pageMaskColor: 'rgba(53, 34, 18, 0.18)',
    controlBarBackground: 'rgba(244, 232, 213, 0.95)',
    controlBarBorderColor: 'rgba(124, 74, 34, 0.14)',
    controlPrimaryColor: '#5A3B24',
    controlMutedColor: '#8A6B50',
    progressTrackColor: 'rgba(125, 95, 62, 0.18)',
    progressSelectedColor: '#A8612D',
    progressBlockColor: '#FFF7EB',
    progressLabelColor: '#6E4B2F',
    cardPhotoBackground: '#4B372A',
    cardContentBackground: 'rgba(245, 236, 220, 0.94)',
    cardTitleColor: '#4E3424',
    cardBodyColor: '#6C5340',
    cardMutedColor: '#8E735C',
    cardTagTextColor: '#8C4C21',
    cardTagBackground: 'rgba(140, 76, 33, 0.12)',
    overlayMaskColor: 'rgba(44, 26, 15, 0.58)',
    overlayPanelBackground: 'rgba(249, 241, 228, 0.96)',
    overlayPanelBorderColor: 'rgba(115, 78, 45, 0.10)',
    overlayTextColor: '#4E3424',
    overlaySecondaryTextColor: '#6D5642',
    moodTextColor: '#B15C3A',
    moodBackgroundColor: 'rgba(177, 92, 58, 0.12)',
    rippleColor: 'rgba(177, 92, 58, 0.26)',
    shadowColor: 'rgba(70, 42, 20, 0.20)',
    mapPolylineColor: '#B56B36',
    mapPolylineWidth: 5,
    routePendingColor: 'rgba(181, 107, 54, 0.18)',
    routePendingWidth: 5,
    routeVisitedColor: '#B56B36',
    routeVisitedWidth: 7
  }
]

export class ReplayStyleKitCatalog {
  static readonly DEFAULT_ID: ReplayStyleKitId = ReplayStyleKitId.MINIMAL_WHITE

  static list(): ReplayStyleKitOption[] {
    const options: ReplayStyleKitOption[] = []
    for (const item of STYLE_KITS) {
      options.push({
        id: item.id,
        title: item.title,
        subtitle: item.subtitle,
        previewColor: item.previewColor
      })
    }
    return options
  }

  static getById(id: ReplayStyleKitId): ReplayStyleKit {
    return STYLE_KITS.find((item: ReplayStyleKit) => item.id === id) ??
      STYLE_KITS[0]
  }
}
