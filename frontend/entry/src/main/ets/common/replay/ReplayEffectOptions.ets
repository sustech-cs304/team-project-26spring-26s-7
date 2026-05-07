export enum ReplayFilterId {
  NONE = 'none'
}

export enum ReplayTransitionType {
  FADE = 'fade'
}

export interface ReplayEffectsState {
  enableRipple: boolean
  enableAdaptiveColor: boolean
  enableRouteAnimation: boolean
  enableBlurOverlay: boolean
  enableLottie: boolean
  enableParticles: boolean
}

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
