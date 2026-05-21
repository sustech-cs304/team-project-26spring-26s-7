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
  shadowColor: string
  mapPolylineColor: string
  mapPolylineWidth: number
  routePendingColor: string
  routePendingWidth: number
  routeVisitedGlowColor: string
  routeVisitedGlowWidth: number
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
    controlBarBorderColor: 'rgba(255, 106, 26, 0.10)',
    controlPrimaryColor: '#1A1A1A',
    controlMutedColor: '#6B7280',
    progressTrackColor: '#E8E2DA',
    progressSelectedColor: '#FF6A1A',
    progressBlockColor: '#FFF7F0',
    progressLabelColor: '#364152',
    cardPhotoBackground: '#2D3748',
    cardContentBackground: 'rgba(255, 255, 255, 0.92)',
    cardTitleColor: '#111827',
    cardBodyColor: '#4B5563',
    cardMutedColor: '#6B7280',
    cardTagTextColor: '#C2571A',
    cardTagBackground: 'rgba(255, 106, 26, 0.10)',
    overlayMaskColor: 'rgba(14, 18, 24, 0.52)',
    overlayPanelBackground: '#FFFFFF',
    overlayPanelBorderColor: 'rgba(17, 24, 39, 0.06)',
    overlayTextColor: '#111827',
    overlaySecondaryTextColor: '#5B6472',
    moodTextColor: '#D9485F',
    moodBackgroundColor: 'rgba(217, 72, 95, 0.10)',
    shadowColor: '#14101820',
    mapPolylineColor: '#FF6A1A',
    mapPolylineWidth: 4,
    routePendingColor: 'rgba(255, 106, 26, 0.22)',
    routePendingWidth: 32,
    routeVisitedGlowColor: 'rgba(255, 106, 26, 0.30)',
    routeVisitedGlowWidth: 36,
    routeVisitedColor: '#FF6A1A',
    routeVisitedWidth: 24
  },
  {
    id: ReplayStyleKitId.DARK_NIGHT,
    title: '暗夜蓝',
    subtitle: '深色卡片与冷色路线，更适合夜景和城市回放',
    previewColor: '#182235',
    pageMaskColor: 'rgba(6, 10, 18, 0.24)',
    controlBarBackground: 'rgba(12, 20, 33, 0.94)',
    controlBarBorderColor: 'rgba(255, 138, 69, 0.18)',
    controlPrimaryColor: '#EAF4FF',
    controlMutedColor: '#9CB4CC',
    progressTrackColor: '#7A94B0',
    progressSelectedColor: '#FF8A45',
    progressBlockColor: '#EAF4FF',
    progressLabelColor: '#D4E6F8',
    cardPhotoBackground: '#0D1420',
    cardContentBackground: 'rgba(8, 15, 25, 0.90)',
    cardTitleColor: '#F5FAFF',
    cardBodyColor: '#CBDBEB',
    cardMutedColor: '#97A8BA',
    cardTagTextColor: '#FFB37A',
    cardTagBackground: 'rgba(255, 138, 69, 0.16)',
    overlayMaskColor: 'rgba(2, 6, 12, 0.72)',
    overlayPanelBackground: 'rgba(10, 18, 28, 0.94)',
    overlayPanelBorderColor: 'rgba(142, 208, 255, 0.12)',
    overlayTextColor: '#F5FAFF',
    overlaySecondaryTextColor: '#B0C5D9',
    moodTextColor: '#FFB38A',
    moodBackgroundColor: 'rgba(255, 179, 138, 0.12)',
    shadowColor: '#66000000',
    mapPolylineColor: '#FF8A45',
    mapPolylineWidth: 5,
    routePendingColor: 'rgba(255, 138, 69, 0.22)',
    routePendingWidth: 32,
    routeVisitedGlowColor: 'rgba(255, 179, 122, 0.30)',
    routeVisitedGlowWidth: 36,
    routeVisitedColor: '#FFB37A',
    routeVisitedWidth: 24
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
    shadowColor: 'rgba(70, 42, 20, 0.20)',
    mapPolylineColor: '#B56B36',
    mapPolylineWidth: 5,
    routePendingColor: 'rgba(181, 107, 54, 0.28)',
    routePendingWidth: 32,
    routeVisitedGlowColor: 'rgba(181, 107, 54, 0.35)',
    routeVisitedGlowWidth: 36,
    routeVisitedColor: '#B56B36',
    routeVisitedWidth: 24
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
