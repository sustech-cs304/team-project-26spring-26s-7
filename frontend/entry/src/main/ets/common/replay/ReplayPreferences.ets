import { ReplayBgmId, ReplayMusicCatalog } from './ReplayMusicCatalog'
import { ReplayFilterId, ReplayTransitionType } from './ReplayEffectOptions'
import { ReplayStyleKitCatalog, ReplayStyleKitId } from './ReplayStyleKit'

export interface ReplayPreferencesState {
  styleKitId: ReplayStyleKitId
  bgmId: ReplayBgmId
  filterId: ReplayFilterId
  transitionType: ReplayTransitionType
  enableRipple: boolean
  enableBlurOverlay: boolean
}

export class ReplayPreferences {
  static readonly STYLE_KIT_KEY: string = 'replayStyleKitId'
  static readonly BGM_KEY: string = 'replayBgmId'
  static readonly FILTER_KEY: string = 'replayFilterId'
  static readonly TRANSITION_KEY: string = 'replayTransitionType'
  static readonly ENABLE_RIPPLE_KEY: string = 'replayEnableRipple'
  static readonly ENABLE_BLUR_OVERLAY_KEY: string = 'replayEnableBlurOverlay'
  static readonly VERSION_KEY: string = 'replayPreferencesVersion'

  static initializeDefaults(): void {
    ReplayPreferences.ensureDefault<ReplayStyleKitId>(
      ReplayPreferences.STYLE_KIT_KEY,
      ReplayStyleKitCatalog.DEFAULT_ID
    )
    ReplayPreferences.ensureDefault<ReplayBgmId>(
      ReplayPreferences.BGM_KEY,
      ReplayMusicCatalog.DEFAULT_ID
    )
    ReplayPreferences.ensureDefault<ReplayFilterId>(
      ReplayPreferences.FILTER_KEY,
      ReplayFilterId.NONE
    )
    ReplayPreferences.ensureDefault<ReplayTransitionType>(
      ReplayPreferences.TRANSITION_KEY,
      ReplayTransitionType.FADE
    )
    ReplayPreferences.ensureDefault<boolean>(ReplayPreferences.ENABLE_RIPPLE_KEY, false)
    ReplayPreferences.ensureDefault<boolean>(ReplayPreferences.ENABLE_BLUR_OVERLAY_KEY, false)
    ReplayPreferences.ensureDefault<number>(ReplayPreferences.VERSION_KEY, 0)
  }

  static getState(): ReplayPreferencesState {
    ReplayPreferences.initializeDefaults()
    return {
      styleKitId: ReplayPreferences.getStyleKitId(),
      bgmId: ReplayPreferences.getBgmId(),
      filterId: ReplayPreferences.getFilterId(),
      transitionType: ReplayPreferences.getTransitionType(),
      enableRipple: ReplayPreferences.getEnableRipple(),
      enableBlurOverlay: ReplayPreferences.getEnableBlurOverlay()
    }
  }

  static getStyleKitId(): ReplayStyleKitId {
    ReplayPreferences.initializeDefaults()
    return AppStorage.get<ReplayStyleKitId>(ReplayPreferences.STYLE_KIT_KEY) ??
      ReplayStyleKitCatalog.DEFAULT_ID
  }

  static setStyleKitId(value: ReplayStyleKitId): void {
    AppStorage.setOrCreate(ReplayPreferences.STYLE_KIT_KEY, value)
    ReplayPreferences.bumpVersion()
  }

  static getBgmId(): ReplayBgmId {
    ReplayPreferences.initializeDefaults()
    return AppStorage.get<ReplayBgmId>(ReplayPreferences.BGM_KEY) ??
      ReplayMusicCatalog.DEFAULT_ID
  }

  static setBgmId(value: ReplayBgmId): void {
    AppStorage.setOrCreate(ReplayPreferences.BGM_KEY, value)
    ReplayPreferences.bumpVersion()
  }

  static getFilterId(): ReplayFilterId {
    ReplayPreferences.initializeDefaults()
    return AppStorage.get<ReplayFilterId>(ReplayPreferences.FILTER_KEY) ??
      ReplayFilterId.NONE
  }

  static setFilterId(value: ReplayFilterId): void {
    AppStorage.setOrCreate(ReplayPreferences.FILTER_KEY, value)
    ReplayPreferences.bumpVersion()
  }

  static getTransitionType(): ReplayTransitionType {
    ReplayPreferences.initializeDefaults()
    return AppStorage.get<ReplayTransitionType>(ReplayPreferences.TRANSITION_KEY) ??
      ReplayTransitionType.FADE
  }

  static setTransitionType(value: ReplayTransitionType): void {
    AppStorage.setOrCreate(ReplayPreferences.TRANSITION_KEY, value)
    ReplayPreferences.bumpVersion()
  }

  static getEnableRipple(): boolean {
    ReplayPreferences.initializeDefaults()
    return AppStorage.get<boolean>(ReplayPreferences.ENABLE_RIPPLE_KEY) ?? false
  }

  static setEnableRipple(value: boolean): void {
    AppStorage.setOrCreate(ReplayPreferences.ENABLE_RIPPLE_KEY, value)
    ReplayPreferences.bumpVersion()
  }

  static getEnableBlurOverlay(): boolean {
    ReplayPreferences.initializeDefaults()
    return AppStorage.get<boolean>(ReplayPreferences.ENABLE_BLUR_OVERLAY_KEY) ?? false
  }

  static setEnableBlurOverlay(value: boolean): void {
    AppStorage.setOrCreate(ReplayPreferences.ENABLE_BLUR_OVERLAY_KEY, value)
    ReplayPreferences.bumpVersion()
  }

  private static bumpVersion(): void {
    const version = AppStorage.get<number>(ReplayPreferences.VERSION_KEY) ?? 0
    AppStorage.setOrCreate(ReplayPreferences.VERSION_KEY, version + 1)
  }

  private static ensureDefault<T>(key: string, value: T): void {
    if (AppStorage.get<T>(key) === undefined) {
      AppStorage.setOrCreate(key, value)
    }
  }
}
