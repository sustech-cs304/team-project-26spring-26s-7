export enum ReplayFilterId {
  NONE = 'none',
  FILM = 'film',
  WARM = 'warm',
  COOL = 'cool',
  MONO = 'mono'
}

export enum ReplayTransitionType {
  FADE = 'fade',
  SLIDE = 'slide',
  SCALE = 'scale'
}

export interface ReplayFilterOption {
  id: ReplayFilterId
  title: string
  subtitle: string
  previewColor: string
  overlayColor: string
  imageOpacity: number
}

export interface ReplayTransitionOption {
  id: ReplayTransitionType
  title: string
  subtitle: string
}

export interface ReplayEffectsState {
  enableRipple: boolean
  enableAdaptiveColor: boolean
  enableRouteAnimation: boolean
  enableBlurOverlay: boolean
  enableLottie: boolean
  enableParticles: boolean
}

const FILTER_OPTIONS: ReplayFilterOption[] = [
  {
    id: ReplayFilterId.NONE,
    title: '原片',
    subtitle: '保持照片原始观感',
    previewColor: '#FFFFFF',
    overlayColor: 'rgba(255, 255, 255, 0)',
    imageOpacity: 1
  },
  {
    id: ReplayFilterId.FILM,
    title: '胶片',
    subtitle: '柔和颗粒感，适合手账风格',
    previewColor: '#D9BE97',
    overlayColor: 'rgba(180, 131, 72, 0.16)',
    imageOpacity: 0.94
  },
  {
    id: ReplayFilterId.WARM,
    title: '暖阳',
    subtitle: '提升暖色氛围，适合日落与街景',
    previewColor: '#FFB26B',
    overlayColor: 'rgba(255, 155, 55, 0.18)',
    imageOpacity: 0.96
  },
  {
    id: ReplayFilterId.COOL,
    title: '冷调',
    subtitle: '压低饱和度，突出夜景和海风感',
    previewColor: '#73B7FF',
    overlayColor: 'rgba(68, 142, 255, 0.18)',
    imageOpacity: 0.95
  },
  {
    id: ReplayFilterId.MONO,
    title: '黑白',
    subtitle: '用高对比的单色质感强化纪实氛围',
    previewColor: '#6B7280',
    overlayColor: 'rgba(17, 24, 39, 0.30)',
    imageOpacity: 0.82
  }
]

const TRANSITION_OPTIONS: ReplayTransitionOption[] = [
  {
    id: ReplayTransitionType.FADE,
    title: '淡入淡出',
    subtitle: '平滑过渡，作为默认回放节奏'
  },
  {
    id: ReplayTransitionType.SLIDE,
    title: '横向滑入',
    subtitle: '卡片带有移动方向感，适合城市或行走主题'
  },
  {
    id: ReplayTransitionType.SCALE,
    title: '轻微缩放',
    subtitle: '以镜头推近的感觉切换节点'
  }
]

export class ReplayEffectsDefaults {
  static create(): ReplayEffectsState {
    return {
      enableRipple: false,
      enableAdaptiveColor: false,
      enableRouteAnimation: false,
      enableBlurOverlay: false,
      enableLottie: false,
      enableParticles: false
    }
  }
}

export class ReplayFilterCatalog {
  static readonly DEFAULT_ID: ReplayFilterId = ReplayFilterId.NONE

  static list(): ReplayFilterOption[] {
    return FILTER_OPTIONS
  }

  static getById(id: ReplayFilterId): ReplayFilterOption {
    return FILTER_OPTIONS.find((item: ReplayFilterOption) => item.id === id) ??
      FILTER_OPTIONS[0]
  }
}

export class ReplayTransitionCatalog {
  static readonly DEFAULT_ID: ReplayTransitionType = ReplayTransitionType.FADE

  static list(): ReplayTransitionOption[] {
    return TRANSITION_OPTIONS
  }

  static getById(id: ReplayTransitionType): ReplayTransitionOption {
    return TRANSITION_OPTIONS.find((item: ReplayTransitionOption) => item.id === id) ??
      TRANSITION_OPTIONS[0]
  }
}
