import { ReplayBgmId, ReplayMusicCatalog } from './ReplayMusicCatalog'
import { ReplayFilterId, ReplayTransitionType } from './ReplayEffectOptions'
import { ReplayStyleKitCatalog, ReplayStyleKitId } from './ReplayStyleKit'
import { preferences } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'
import { logger } from '../utils/Logger'

const TAG = 'ReplayPreferences'

// v1.0.5：偏好磁盘存储库名。改名等于丢历史，慎改。
const STORE_NAME = 'replay_preferences_v1'

export interface ReplayPreferencesState {
  styleKitId: ReplayStyleKitId
  bgmId: ReplayBgmId
  filterId: ReplayFilterId
  transitionType: ReplayTransitionType
  enableRipple: boolean
  enableRouteAnimation: boolean
  enableBlurOverlay: boolean
}

/**
 * 回放偏好的本地持久化 + 运行时缓存。
 *
 * v1.0.5 改造：
 *   - 之前只用 AppStorage（内存），app 重启就丢回默认。第一次分享会带着
 *     默认偏好走，用户在 ReplaySettingsSheet 调过的 kit/bgm/filter/etc.
 *     全部失效。
 *   - 现在走 @kit.ArkData preferences 真正持久化到磁盘，运行时同步进
 *     AppStorage 让 getter 仍是同步读（UI 不需要等异步）。
 *
 * 调用方式（与 ConsentManager 一致）：
 *   - 任何使用偏好的 UI 入口（SharePage / TripReplayPage / ReplaySettings 等）
 *     在 `aboutToAppear()` 里 fire-and-forget `ensureLoaded(ctx)`：开始读盘
 *   - 在真正用偏好值的 async 路径（如 publishShare）里再 `await ensureLoaded(ctx)`
 *     一次，防止"页面刚开就立刻分享"的 race
 *   - setter 仍是同步：先写 AppStorage（UI 立即响应），再 fire-and-forget 写盘
 */
export class ReplayPreferences {
  static readonly STYLE_KIT_KEY: string = 'replayStyleKitId'
  static readonly BGM_KEY: string = 'replayBgmId'
  static readonly FILTER_KEY: string = 'replayFilterId'
  static readonly TRANSITION_KEY: string = 'replayTransitionType'
  static readonly ENABLE_RIPPLE_KEY: string = 'replayEnableRipple'
  static readonly ENABLE_ROUTE_ANIMATION_KEY: string = 'replayEnableRouteAnimation'
  static readonly ENABLE_BLUR_OVERLAY_KEY: string = 'replayEnableBlurOverlay'
  static readonly VERSION_KEY: string = 'replayPreferencesVersion'

  /** 是否已经从磁盘读过；ensureLoaded 完成后置 true，再调直接 return。 */
  private static loaded: boolean = false
  /** 上次 ensureLoaded 拿到的 context；setter 用它做异步写盘。 */
  private static persistContext: common.UIAbilityContext | null = null
  /** 并发 ensureLoaded 调用合并到同一个 Promise，避免 race。 */
  private static loadingPromise: Promise<void> | null = null

  /**
   * 把磁盘上存的偏好读到 AppStorage 里。第一次调用执行真正的 IO，
   * 之后调用直接 return（仅刷新 persistContext 防止 context 失效）。
   */
  static async ensureLoaded(context: common.UIAbilityContext): Promise<void> {
    ReplayPreferences.persistContext = context
    if (ReplayPreferences.loaded) {
      return
    }
    if (ReplayPreferences.loadingPromise) {
      return ReplayPreferences.loadingPromise
    }
    ReplayPreferences.loadingPromise = ReplayPreferences._doLoad(context)
    return ReplayPreferences.loadingPromise
  }

  private static async _doLoad(context: common.UIAbilityContext): Promise<void> {
    try {
      const store = await preferences.getPreferences(context, { name: STORE_NAME })
      const styleKit = await store.get(
        ReplayPreferences.STYLE_KIT_KEY, ReplayStyleKitCatalog.DEFAULT_ID) as string
      const bgm = await store.get(
        ReplayPreferences.BGM_KEY, ReplayMusicCatalog.DEFAULT_ID) as string
      const filter = await store.get(
        ReplayPreferences.FILTER_KEY, ReplayFilterId.NONE) as string
      const transition = await store.get(
        ReplayPreferences.TRANSITION_KEY, ReplayTransitionType.FADE) as string
      const ripple = await store.get(ReplayPreferences.ENABLE_RIPPLE_KEY, false) as boolean
      const route = await store.get(ReplayPreferences.ENABLE_ROUTE_ANIMATION_KEY, true) as boolean
      const blur = await store.get(ReplayPreferences.ENABLE_BLUR_OVERLAY_KEY, false) as boolean

      AppStorage.setOrCreate(ReplayPreferences.STYLE_KIT_KEY, styleKit)
      AppStorage.setOrCreate(ReplayPreferences.BGM_KEY, bgm)
      AppStorage.setOrCreate(ReplayPreferences.FILTER_KEY, filter)
      AppStorage.setOrCreate(ReplayPreferences.TRANSITION_KEY, transition)
      AppStorage.setOrCreate(ReplayPreferences.ENABLE_RIPPLE_KEY, ripple)
      AppStorage.setOrCreate(ReplayPreferences.ENABLE_ROUTE_ANIMATION_KEY, route)
      AppStorage.setOrCreate(ReplayPreferences.ENABLE_BLUR_OVERLAY_KEY, blur)
      AppStorage.setOrCreate<number>(ReplayPreferences.VERSION_KEY, 0)

      ReplayPreferences.loaded = true
      logger.info(TAG, `loaded kit=${styleKit} bgm=${bgm} filter=${filter} ` +
        `transition=${transition} ripple=${ripple} route=${route} blur=${blur}`)
    } catch (err) {
      logger.error(TAG, `ensureLoaded failed: ${JSON.stringify(err)}`)
      // 读盘失败 → 走 in-memory 默认值兜底，标记已加载（避免无限重试）
      ReplayPreferences.initializeDefaults()
      ReplayPreferences.loaded = true
    } finally {
      ReplayPreferences.loadingPromise = null
    }
  }

  /** setter 调用：把单条 key 写盘。失败仅 log，不抛。 */
  private static _persistString(key: string, value: string): void {
    const ctx = ReplayPreferences.persistContext
    if (!ctx) { return }
    preferences.getPreferences(ctx, { name: STORE_NAME })
      .then(async (store) => {
        await store.put(key, value)
        await store.flush()
      })
      .catch((err: Error) => {
        logger.error(TAG, `persist ${key} failed: ${JSON.stringify(err)}`)
      })
  }

  private static _persistBoolean(key: string, value: boolean): void {
    const ctx = ReplayPreferences.persistContext
    if (!ctx) { return }
    preferences.getPreferences(ctx, { name: STORE_NAME })
      .then(async (store) => {
        await store.put(key, value)
        await store.flush()
      })
      .catch((err: Error) => {
        logger.error(TAG, `persist ${key} failed: ${JSON.stringify(err)}`)
      })
  }

  /** 仅做 AppStorage 兜底 — 当 ensureLoaded 还没被调过、UI 又同步要读时
   *  避免 undefined。真正的"上次用户选过的值"靠 ensureLoaded 从磁盘加载。 */
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
    ReplayPreferences.ensureDefault<boolean>(ReplayPreferences.ENABLE_ROUTE_ANIMATION_KEY, true)
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
      enableRouteAnimation: ReplayPreferences.getEnableRouteAnimation(),
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
    ReplayPreferences._persistString(ReplayPreferences.STYLE_KIT_KEY, value)
  }

  static getBgmId(): ReplayBgmId {
    ReplayPreferences.initializeDefaults()
    return AppStorage.get<ReplayBgmId>(ReplayPreferences.BGM_KEY) ??
      ReplayMusicCatalog.DEFAULT_ID
  }

  static setBgmId(value: ReplayBgmId): void {
    AppStorage.setOrCreate(ReplayPreferences.BGM_KEY, value)
    ReplayPreferences.bumpVersion()
    ReplayPreferences._persistString(ReplayPreferences.BGM_KEY, value)
  }

  static getFilterId(): ReplayFilterId {
    ReplayPreferences.initializeDefaults()
    return AppStorage.get<ReplayFilterId>(ReplayPreferences.FILTER_KEY) ??
      ReplayFilterId.NONE
  }

  static setFilterId(value: ReplayFilterId): void {
    AppStorage.setOrCreate(ReplayPreferences.FILTER_KEY, value)
    ReplayPreferences.bumpVersion()
    ReplayPreferences._persistString(ReplayPreferences.FILTER_KEY, value)
  }

  static getTransitionType(): ReplayTransitionType {
    ReplayPreferences.initializeDefaults()
    return AppStorage.get<ReplayTransitionType>(ReplayPreferences.TRANSITION_KEY) ??
      ReplayTransitionType.FADE
  }

  static setTransitionType(value: ReplayTransitionType): void {
    AppStorage.setOrCreate(ReplayPreferences.TRANSITION_KEY, value)
    ReplayPreferences.bumpVersion()
    ReplayPreferences._persistString(ReplayPreferences.TRANSITION_KEY, value)
  }

  static getEnableRipple(): boolean {
    ReplayPreferences.initializeDefaults()
    return AppStorage.get<boolean>(ReplayPreferences.ENABLE_RIPPLE_KEY) ?? false
  }

  static setEnableRipple(value: boolean): void {
    AppStorage.setOrCreate(ReplayPreferences.ENABLE_RIPPLE_KEY, value)
    ReplayPreferences.bumpVersion()
    ReplayPreferences._persistBoolean(ReplayPreferences.ENABLE_RIPPLE_KEY, value)
  }

  static getEnableRouteAnimation(): boolean {
    ReplayPreferences.initializeDefaults()
    return AppStorage.get<boolean>(ReplayPreferences.ENABLE_ROUTE_ANIMATION_KEY) ?? true
  }

  static setEnableRouteAnimation(value: boolean): void {
    AppStorage.setOrCreate(ReplayPreferences.ENABLE_ROUTE_ANIMATION_KEY, value)
    ReplayPreferences.bumpVersion()
    ReplayPreferences._persistBoolean(ReplayPreferences.ENABLE_ROUTE_ANIMATION_KEY, value)
  }

  static getEnableBlurOverlay(): boolean {
    ReplayPreferences.initializeDefaults()
    return AppStorage.get<boolean>(ReplayPreferences.ENABLE_BLUR_OVERLAY_KEY) ?? false
  }

  static setEnableBlurOverlay(value: boolean): void {
    AppStorage.setOrCreate(ReplayPreferences.ENABLE_BLUR_OVERLAY_KEY, value)
    ReplayPreferences.bumpVersion()
    ReplayPreferences._persistBoolean(ReplayPreferences.ENABLE_BLUR_OVERLAY_KEY, value)
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
