import { router, promptAction } from '@kit.ArkUI'
import { MapComponent, mapCommon, map } from '@kit.MapKit'
import { AsyncCallback } from '@kit.BasicServicesKit'
import { common } from '@kit.AbilityKit'
import { media } from '@kit.MediaKit'
import {
  AppColors,
  AppDimens,
  ReplayBgmId,
  ReplayFilterId,
  ReplayMusicCatalog,
  ReplayPreferences,
  ReplayStyleKit,
  ReplayStyleKitCatalog,
  ReplayStyleKitId,
  ReplayTransitionType,
  getDataService
} from '../../../common'
import type { ReplayTripPreferences } from '../../../common'
import { RouterParam, ReplayNode, ReplayRoute, Position } from '../../../common'
import type { MemoryNode } from '../../../common'
import { ReplayPhotoCard } from '../components/ReplayPhotoCard'
import { ReplayProgressBar } from '../components/ReplayProgressBar'
import { PhotoCardOverlay } from '../components/PhotoCardOverlay'
import { ReplaySettingsSheet } from '../components/ReplaySettingsSheet'

const DEFAULT_REPLAY_CENTER: mapCommon.LatLng = {
  latitude: 22.55,
  longitude: 113.96
}

const PHASE_IDLE = 0
const PHASE_ENTER = 1
const PHASE_STAYING = 2
const PHASE_EXIT = 3
const PHASE_MOVING = 4

interface RemovableOverlay {
  remove: () => void
}

interface CameraTargetOffset {
  latOffset: number
  lngOffset: number
}

@Entry
@Component
export struct TripReplayPage {
  @StorageLink('appThemeVersion') themeVersion: number = 0
  @StorageLink('replayPreferencesVersion') replayPreferencesVersion: number = 0

  @State isPlaying: boolean = false
  @State currentNodeIndex: number = 0
  @State playbackSpeed: string = '1x'
  @State progress: number = 0
  @State isCardVisible: boolean = true
  @State isLoading: boolean = false
  @State cardOpacity: number = 1
  @State cardScale: number = 1
  @State cardTranslateX: number = 0

  @State routeName: string = '旅程回放'
  @State replayRoute: ReplayRoute | null = null
  @State currentTripId: string = ''

  @State showOverlay: boolean = false
  @State overlayNode: ReplayNode | null = null
  @State showSettingsSheet: boolean = false

  @State selectedStyleKitId: ReplayStyleKitId = ReplayStyleKitCatalog.DEFAULT_ID
  @State selectedBgmId: ReplayBgmId = ReplayMusicCatalog.DEFAULT_ID
  @State selectedFilterId: ReplayFilterId = ReplayFilterId.NONE
  @State selectedTransitionType: ReplayTransitionType = ReplayTransitionType.FADE
  @State enableRouteAnimation: boolean = true
  @State enableBlurOverlay: boolean = false
  @State currentStyleKit: ReplayStyleKit = ReplayStyleKitCatalog.getById(ReplayStyleKitCatalog.DEFAULT_ID)

  @State movingIconVisible: boolean = false
  @State movingIconScreenX: number = 0
  @State movingIconScreenY: number = 0

  private speeds: string[] = ['0.5x', '1x', '2x']
  private playTimer: number = -1
  private readonly FADE_IN_DURATION: number = 2000
  private readonly STAY_DURATION: number = 3000
  private readonly FADE_OUT_DURATION: number = 1000
  private readonly MOVE_DURATION: number = 1500
  @State private currentPhase: number = PHASE_IDLE
  @State private cameraBearing: number = 0

  private mapOptions: mapCommon.MapOptions = {
    position: {
      target: DEFAULT_REPLAY_CENTER,
      zoom: 13
    },
    zoomControlsEnabled: false,
    compassControlsEnabled: false,
    // HMOS MapKit 的 padding 经实测对 animateCamera(newCameraPosition({target}))
    // 不生效（只在 fitBounds 类操作时收紧视野），所以这里干脆置 0，
    // 钉子的屏幕位置改由相机目标偏移（cameraTargetOffsetForBearingZoom）控制。
    padding: {
      left: 0,
      right: 0,
      top: 0,
      bottom: 0
    }
  }
  private mapController?: map.MapComponentController
  private routeRendered: boolean = false
  private dataService = getDataService()
  private musicGeneration: number = 0
  private shouldAudioPlay: boolean = false
  private isPageActive: boolean = false
  private manualJumpGeneration: number = 0
  private routeTrailGeneration: number = 0
  private routeOverlayUpdateGeneration: number = 0
  private routePoints: mapCommon.LatLng[] = []
  private staticRouteOverlay?: RemovableOverlay
  private pendingRouteOverlay?: RemovableOverlay
  private visitedRouteGlowOverlay?: RemovableOverlay
  private visitedRouteCoreOverlay?: RemovableOverlay
  private lastTrailSampleLat?: number
  private lastTrailSampleLng?: number

  private mapCallback: AsyncCallback<map.MapComponentController> = async (err, controller) => {
    if (!err && controller) {
      this.mapController = controller
      await this.drawRouteAndMarkers()
    }
  }

  private avPlayer: media.AVPlayer | undefined = undefined
  @State private isAudioPlaying: boolean = false

  private isCurrentMusicPlayer(avPlayer: media.AVPlayer, generation: number): boolean {
    return this.isPageActive && this.avPlayer === avPlayer && this.musicGeneration === generation
  }

  private async initMusic(shouldPlay: boolean): Promise<void> {
    const generation = this.musicGeneration
    try {
      const uiContext = this.getUIContext()
      const context = uiContext.getHostContext() as common.UIAbilityContext
      if (!context || !this.isPageActive) {
        return
      }

      const avPlayer: media.AVPlayer = await media.createAVPlayer()
      if (generation !== this.musicGeneration || !this.isPageActive) {
        avPlayer.release()
        return
      }

      this.regAVPlayerCallback(avPlayer, generation)
      this.avPlayer = avPlayer
      this.shouldAudioPlay = shouldPlay

      const selectedTrack = ReplayMusicCatalog.getById(this.selectedBgmId)
      const fileDescriptor = await context.resourceManager.getRawFd(selectedTrack.filename)
      if (!this.isCurrentMusicPlayer(avPlayer, generation)) {
        avPlayer.release()
        return
      }

      avPlayer.fdSrc = {
        fd: fileDescriptor.fd,
        offset: fileDescriptor.offset,
        length: fileDescriptor.length
      }
    } catch (err) {
      console.error('TripReplayPage: initMusic failed', JSON.stringify(err))
    }
  }

  private async reloadMusic(): Promise<void> {
    const shouldPlay = this.isAudioPlaying
    await this.stopMusic()
    if (this.isPageActive) {
      this.musicGeneration += 1
      await this.initMusic(shouldPlay)
    }
  }

  private regAVPlayerCallback(avPlayer: media.AVPlayer, generation: number): void {
    avPlayer.on('error', () => {
      if (this.isCurrentMusicPlayer(avPlayer, generation)) {
        avPlayer.reset()
        this.isAudioPlaying = false
      }
    })

    avPlayer.on('stateChange', (state: media.AVPlayerState) => {
      if (!this.isCurrentMusicPlayer(avPlayer, generation)) {
        return
      }

      switch (state) {
        case 'initialized':
          void avPlayer.prepare()
          break
        case 'prepared':
          if (this.shouldAudioPlay) {
            void avPlayer.play()
          }
          break
        case 'playing':
          if (this.shouldAudioPlay) {
            this.isAudioPlaying = true
          } else {
            avPlayer.pause()
          }
          break
        case 'paused':
          this.isAudioPlaying = false
          break
        case 'completed':
          avPlayer.seek(0)
          if (this.shouldAudioPlay) {
            void avPlayer.play()
          }
          break
        case 'stopped':
          this.isAudioPlaying = false
          break
        case 'released':
          this.avPlayer = undefined
          this.isAudioPlaying = false
          this.shouldAudioPlay = false
          break
      }
    })
  }

  private async updateMusicSpeed(_speed: string): Promise<void> {
    console.info(`TripReplayPage: playback speed ${_speed}, audio speed is left unchanged`)
  }

  private toggleMusic(): void {
    if (!this.avPlayer) {
      this.shouldAudioPlay = true
      void this.initMusic(true)
      return
    }
    if (this.isAudioPlaying) {
      this.shouldAudioPlay = false
      this.avPlayer.pause()
    } else {
      this.shouldAudioPlay = true
      void this.avPlayer.play()
    }
  }

  private async stopMusic(): Promise<void> {
    this.musicGeneration += 1
    this.shouldAudioPlay = false
    const avPlayer = this.avPlayer
    this.avPlayer = undefined
    this.isAudioPlaying = false

    if (avPlayer) {
      try {
        await avPlayer.stop()
      } catch (err) {
        console.error('TripReplayPage: stopMusic failed', JSON.stringify(err))
      } finally {
        avPlayer.release()
      }
    }
  }

  aboutToAppear(): void {
    this.isPageActive = true
    // v1.0.5：先把 in-memory 默认值兜上，再 fire-and-forget 读盘覆盖。
    // 读盘完会 setOrCreate AppStorage，绑定的 selectedXxxId 自动刷新。
    ReplayPreferences.initializeDefaults()
    const ctxEarly = getContext(this) as common.UIAbilityContext
    if (ctxEarly) {
      void ReplayPreferences.ensureLoaded(ctxEarly)
    }
    const params = router.getParams() as RouterParam
    if (params?.tripId) {
      this.currentTripId = params.tripId
      void this.loadReplayData(params.tripId)
    } else {
      promptAction.showToast({ message: '缺少旅行 ID 参数' })
    }
  }

  aboutToDisappear(): void {
    this.isPageActive = false
    this.stopPlay()
    this.routeTrailGeneration += 1
    this.clearRouteOverlays()
    void this.stopMusic()
  }

  private applyReplayPreferences(preferences: ReplayTripPreferences): void {
    const fallback = ReplayPreferences.getState()
    this.selectedStyleKitId = (preferences.replayStyleKitId as ReplayStyleKitId) || fallback.styleKitId
    this.selectedBgmId = (preferences.replayBgmId as ReplayBgmId) || fallback.bgmId
    this.selectedFilterId = (preferences.replayFilterId as ReplayFilterId) || fallback.filterId
    this.selectedTransitionType = (preferences.replayTransitionType as ReplayTransitionType) || fallback.transitionType
    this.enableRouteAnimation = preferences.replayEnableRouteAnimation ?? fallback.enableRouteAnimation
    this.enableBlurOverlay = preferences.replayEnableBlurOverlay ?? fallback.enableBlurOverlay
    this.currentStyleKit = ReplayStyleKitCatalog.getById(this.selectedStyleKitId)
  }

  private async persistReplayPreferences(data: ReplayTripPreferences): Promise<void> {
    if (this.currentTripId.length === 0) {
      return
    }
    try {
      await this.dataService.updateTripReplayPreferences(this.currentTripId, data)
    } catch (err) {
      console.error('persistReplayPreferences failed', JSON.stringify(err))
    }
  }

  private formatShortDate(timestamp: number): string {
    const date = new Date(timestamp)
    const month = (date.getMonth() + 1).toString().padStart(2, '0')
    const day = date.getDate().toString().padStart(2, '0')
    return `${month}.${day}`
  }

  private async loadReplayData(tripId: string): Promise<void> {
    this.isLoading = true
    try {
      const replayPreferences = await this.dataService.getTripReplayPreferences(tripId)
      this.applyReplayPreferences(replayPreferences)

      const nodes = await this.dataService.getNodesByTravelId(tripId)
      if (nodes.length === 0) {
        promptAction.showToast({ message: '当前旅行还没有可回放的节点' })
        return
      }

      this.replayRoute = this.convertToReplayRoute(nodes, tripId)
      this.routeName = `旅程回放 (${nodes.length} 个节点)`
      this.currentNodeIndex = 0
      this.progress = 0
      this.routeRendered = false
      this.routePoints = []
      this.clearRouteOverlays()
      this.routeTrailGeneration += 1
      this.resetCardTransform(true)

      if (nodes.length > 0) {
        this.mapOptions = {
          position: {
            target: {
              latitude: nodes[0].latitude,
              longitude: nodes[0].longitude
            },
            zoom: 13
          }
        }
      }

      await this.drawRouteAndMarkers()
      await this.reloadMusic()
    } catch (err) {
      promptAction.showToast({ message: '加载回放数据失败' })
      console.error('loadReplayData failed', JSON.stringify(err))
    } finally {
      this.isLoading = false
    }
  }

  private convertToReplayRoute(nodes: MemoryNode[], tripId: string): ReplayRoute {
    const route = new ReplayRoute()
    route.id = tripId
    route.name = '旅程回放'
    route.totalDistance = 0
    const nodeCount = nodes.length
    const displayTimePerNode = this.FADE_IN_DURATION + this.STAY_DURATION + this.FADE_OUT_DURATION
    const totalMoveTime = (nodeCount - 1) * this.MOVE_DURATION
    route.duration = (nodeCount * displayTimePerNode + totalMoveTime) / 1000
    route.nodes = nodes.map((node: MemoryNode, index: number): ReplayNode => {
      return new ReplayNode(
        node.id,
        node.latitude,
        node.longitude,
        node.photos,
        node.title,
        node.content || '',
        this.truncateTextSmart(node.content || node.title, 42),
        node.createdAt,
        index,
        node.mood || '',
        node.tags || []
      )
    })
    return route
  }

  private truncateTextSmart(text: string, maxLen: number): string {
    if (!text) {
      return ''
    }
    if (text.length <= maxLen) {
      return text
    }
    return `${text.slice(0, maxLen)}...`
  }

  private stopPlay(): void {
    this.isPlaying = false
    this.currentPhase = PHASE_IDLE
    if (this.playTimer !== -1) {
      clearTimeout(this.playTimer)
      this.playTimer = -1
    }
    this.resetCardTransform(true)
  }

  private togglePlay(): void {
    if (this.isPlaying) {
      this.stopPlay()
    } else {
      this.startPlay()
    }
  }

  private startPlay(): void {
    if (!this.replayRoute || this.replayRoute.nodes.length === 0) {
      return
    }
    this.isPlaying = true
    this.playSequence()
  }

  private playSequence(): void {
    if (!this.isPlaying || !this.replayRoute) {
      return
    }

    const nodeCount = this.replayRoute.nodes.length
    if (this.currentNodeIndex >= nodeCount) {
      this.isPlaying = false
      this.currentPhase = PHASE_IDLE
      return
    }

    this.currentPhase = PHASE_ENTER
    this.prepareCardEnterState()
    this.isCardVisible = true
    animateTo({
      duration: this.getFadeInDuration(),
      curve: Curve.EaseInOut,
      onFinish: () => {
        if (!this.isPlaying) {
          return
        }
        this.currentPhase = PHASE_STAYING
        this.playTimer = setTimeout(() => {
          if (!this.isPlaying) {
            return
          }
          this.currentPhase = PHASE_EXIT
          this.animateCardExit(() => {
            const nextIndex = this.currentNodeIndex + 1
            if (nextIndex >= nodeCount) {
              this.isPlaying = false
              this.currentPhase = PHASE_IDLE
              this.isCardVisible = false
              return
            }

            this.currentPhase = PHASE_MOVING
            this.isCardVisible = false
            this.moveToNode(nextIndex)
            this.playTimer = setTimeout(() => {
              if (this.isPlaying) {
                this.playSequence()
              }
            }, this.getMoveDuration())
          })
        }, this.getStayDuration())
      }
    }, () => {
      this.cardOpacity = 1
      this.cardScale = 1
      this.cardTranslateX = 0
    })
  }

  private prepareCardEnterState(): void {
    switch (this.selectedTransitionType) {
      case ReplayTransitionType.SLIDE:
        this.cardOpacity = 0
        this.cardScale = 1
        this.cardTranslateX = 30
        break
      case ReplayTransitionType.SCALE:
        this.cardOpacity = 0
        this.cardScale = 0.92
        this.cardTranslateX = 0
        break
      default:
        this.cardOpacity = 0
        this.cardScale = 1
        this.cardTranslateX = 0
        break
    }
  }

  private animateCardExit(onFinish: () => void): void {
    animateTo({
      duration: this.getFadeOutDuration(),
      curve: Curve.EaseInOut,
      onFinish: onFinish
    }, () => {
      switch (this.selectedTransitionType) {
        case ReplayTransitionType.SLIDE:
          this.cardOpacity = 0
          this.cardTranslateX = -32
          this.cardScale = 1
          break
        case ReplayTransitionType.SCALE:
          this.cardOpacity = 0
          this.cardScale = 1.06
          this.cardTranslateX = 0
          break
        default:
          this.cardOpacity = 0
          this.cardScale = 1
          this.cardTranslateX = 0
          break
      }
    })
  }

  private resetCardTransform(showCard: boolean): void {
    this.isCardVisible = showCard
    this.cardOpacity = 1
    this.cardScale = 1
    this.cardTranslateX = 0
  }

  private getFadeInDuration(): number {
    if (this.playbackSpeed === '0.5x') {
      return this.FADE_IN_DURATION * 2
    }
    if (this.playbackSpeed === '2x') {
      return this.FADE_IN_DURATION / 2
    }
    return this.FADE_IN_DURATION
  }

  private getFadeOutDuration(): number {
    if (this.playbackSpeed === '0.5x') {
      return this.FADE_OUT_DURATION * 2
    }
    if (this.playbackSpeed === '2x') {
      return this.FADE_OUT_DURATION / 2
    }
    return this.FADE_OUT_DURATION
  }

  private getStayDuration(): number {
    if (this.playbackSpeed === '0.5x') {
      return this.STAY_DURATION * 2
    }
    if (this.playbackSpeed === '2x') {
      return this.STAY_DURATION / 2
    }
    return this.STAY_DURATION
  }

  private getMoveDuration(): number {
    if (this.playbackSpeed === '0.5x') {
      return this.MOVE_DURATION * 2
    }
    if (this.playbackSpeed === '2x') {
      return this.MOVE_DURATION / 2
    }
    return this.MOVE_DURATION
  }

  private async drawRouteAndMarkers(): Promise<void> {
    if (!this.mapController || !this.replayRoute) {
      return
    }

    const positions: mapCommon.LatLng[] = []
    for (const node of this.replayRoute.nodes) {
      positions.push({
        latitude: node.position.latitude,
        longitude: node.position.longitude
      })
    }

    this.routePoints = positions
    if (positions.length === 0) {
      return
    }

    if (!this.routeRendered) {
      for (const point of positions) {
        await this.mapController.addMarker({
          position: point,
          visible: true,
          clickable: false,
          draggable: false,
          flat: false,
          rotation: 0,
          zIndex: 10,
          alpha: 1,
          anchorU: 0.5,
          anchorV: 1
        })
      }

      if (positions.length > 1) {
        const bearing = this.calculateBearing(
          positions[0].latitude,
          positions[0].longitude,
          positions[1].latitude,
          positions[1].longitude
        )
        this.cameraBearing = bearing
        // #221: 初始 zoom 按节点 0 -> 1 段长动态算, 避免短路线刚进来就一片空白
        const initialZoom = this.replayZoomForIndex(0)
        const initialOffset = this.cameraTargetOffsetForBearingZoom(positions[0].latitude, initialZoom, bearing)
        const cameraUpdate = map.newCameraPosition({
          target: {
            latitude: positions[0].latitude + initialOffset.latOffset,
            longitude: positions[0].longitude + initialOffset.lngOffset
          },
          zoom: initialZoom,
          bearing: bearing,
          tilt: 45
        })
        this.mapController.animateCamera(cameraUpdate, 1000)
      } else {
        const singleZoom = 15
        const singleOffset = this.cameraTargetOffsetForBearingZoom(positions[0].latitude, singleZoom, 0)
        const cameraUpdate = map.newCameraPosition({
          target: {
            latitude: positions[0].latitude + singleOffset.latOffset,
            longitude: positions[0].longitude + singleOffset.lngOffset
          },
          zoom: singleZoom
        })
        this.mapController.animateCamera(cameraUpdate, 500)
      }
      this.routeRendered = true
    }

    await this.refreshRouteOverlays()
  }

  private clearRouteOverlays(): void {
    this.staticRouteOverlay?.remove()
    this.pendingRouteOverlay?.remove()
    this.visitedRouteGlowOverlay?.remove()
    this.visitedRouteCoreOverlay?.remove()
    this.staticRouteOverlay = undefined
    this.pendingRouteOverlay = undefined
    this.visitedRouteGlowOverlay = undefined
    this.visitedRouteCoreOverlay = undefined
    this.lastTrailSampleLat = undefined
    this.lastTrailSampleLng = undefined
  }

  private async addRoutePolyline(
    points: mapCommon.LatLng[],
    color: number,
    width: number,
    zIndex: number
  ): Promise<RemovableOverlay | undefined> {
    if (!this.mapController || points.length < 2) {
      return undefined
    }
    return await this.mapController.addPolyline({
      points: points,
      clickable: false,
      visible: true,
      color: color,
      width: width,
      zIndex: zIndex,
      geodesic: true,
      gradient: false,
      jointType: mapCommon.JointType.ROUND,
      startCap: mapCommon.CapStyle.ROUND,
      endCap: mapCommon.CapStyle.ROUND
    }) as RemovableOverlay
  }

  private clampColorChannel(value: number): number {
    return Math.max(0, Math.min(255, Math.round(value)))
  }

  private toMapColor(color: string): number {
    const value = color.trim()
    if (value.startsWith('#')) {
      const hex = value.substring(1)
      if (hex.length === 6) {
        return 0xFF000000 + parseInt(hex, 16)
      }
      if (hex.length === 8) {
        return parseInt(hex, 16)
      }
    }

    if (value.startsWith('rgba(') && value.endsWith(')')) {
      const rgba = value.substring(5, value.length - 1).split(',')
      if (rgba.length === 4) {
        const red = this.clampColorChannel(Number(rgba[0].trim()))
        const green = this.clampColorChannel(Number(rgba[1].trim()))
        const blue = this.clampColorChannel(Number(rgba[2].trim()))
        const alpha = this.clampColorChannel(Number(rgba[3].trim()) * 255)
        return alpha * 0x1000000 + red * 0x10000 + green * 0x100 + blue
      }
    }

    if (value.startsWith('rgb(') && value.endsWith(')')) {
      const rgb = value.substring(4, value.length - 1).split(',')
      if (rgb.length === 3) {
        const red = this.clampColorChannel(Number(rgb[0].trim()))
        const green = this.clampColorChannel(Number(rgb[1].trim()))
        const blue = this.clampColorChannel(Number(rgb[2].trim()))
        return 0xFF000000 + red * 0x10000 + green * 0x100 + blue
      }
    }

    return 0xFF1890FF
  }

  private shouldSkipTrailSample(latitude: number, longitude: number): boolean {
    if (this.lastTrailSampleLat === undefined || this.lastTrailSampleLng === undefined) {
      return false
    }
    const latDelta = latitude - this.lastTrailSampleLat
    const lngDelta = longitude - this.lastTrailSampleLng
    const distanceSq = latDelta * latDelta + lngDelta * lngDelta
    return distanceSq < 1e-10
  }

  private async replaceVisitedRouteOverlays(points: mapCommon.LatLng[]): Promise<void> {
    const updateGeneration = ++this.routeOverlayUpdateGeneration
    const overlays = await Promise.all([
      this.addRoutePolyline(
        points,
        this.toMapColor(this.currentStyleKit.routeVisitedGlowColor),
        this.currentStyleKit.routeVisitedGlowWidth,
        6
      ),
      this.addRoutePolyline(
        points,
        this.toMapColor(this.currentStyleKit.routeVisitedColor),
        this.currentStyleKit.routeVisitedWidth,
        7
      )
    ])
    const nextGlowOverlay = overlays[0]
    const nextCoreOverlay = overlays[1]

    if (updateGeneration !== this.routeOverlayUpdateGeneration) {
      nextGlowOverlay?.remove()
      nextCoreOverlay?.remove()
      return
    }

    this.visitedRouteGlowOverlay?.remove()
    this.visitedRouteCoreOverlay?.remove()
    this.visitedRouteGlowOverlay = nextGlowOverlay
    this.visitedRouteCoreOverlay = nextCoreOverlay
  }

  private async refreshRouteOverlays(): Promise<void> {
    this.clearRouteOverlays()
    if (this.routePoints.length < 2) {
      return
    }

    if (!this.enableRouteAnimation) {
      this.staticRouteOverlay = await this.addRoutePolyline(
        this.routePoints,
        this.toMapColor(this.currentStyleKit.mapPolylineColor),
        this.currentStyleKit.mapPolylineWidth,
        5
      )
      return
    }

    this.pendingRouteOverlay = await this.addRoutePolyline(
      this.routePoints,
      this.toMapColor(this.currentStyleKit.routePendingColor),
      this.currentStyleKit.routePendingWidth,
      4
    )
    await this.syncVisitedRouteToNodeIndex(this.currentNodeIndex)
  }

  private async syncVisitedRouteToNodeIndex(index: number): Promise<void> {
    if (!this.enableRouteAnimation || this.routePoints.length < 2) {
      this.routeOverlayUpdateGeneration += 1
      this.visitedRouteGlowOverlay?.remove()
      this.visitedRouteCoreOverlay?.remove()
      this.visitedRouteGlowOverlay = undefined
      this.visitedRouteCoreOverlay = undefined
      this.lastTrailSampleLat = undefined
      this.lastTrailSampleLng = undefined
      return
    }

    if (index <= 0) {
      this.routeOverlayUpdateGeneration += 1
      this.visitedRouteGlowOverlay?.remove()
      this.visitedRouteCoreOverlay?.remove()
      this.visitedRouteGlowOverlay = undefined
      this.visitedRouteCoreOverlay = undefined
      this.lastTrailSampleLat = undefined
      this.lastTrailSampleLng = undefined
      return
    }

    const visitedPoints = this.routePoints.slice(0, Math.min(index + 1, this.routePoints.length))
    const lastPoint = visitedPoints[visitedPoints.length - 1]
    this.lastTrailSampleLat = lastPoint.latitude
    this.lastTrailSampleLng = lastPoint.longitude
    await this.replaceVisitedRouteOverlays(visitedPoints)
  }

  private async syncVisitedRouteToMovingPosition(index: number, latitude: number, longitude: number): Promise<void> {
    if (!this.enableRouteAnimation || this.routePoints.length < 2) {
      return
    }
    if (this.shouldSkipTrailSample(latitude, longitude)) {
      return
    }

    const visitedPoints = this.routePoints.slice(0, Math.max(1, Math.min(index, this.routePoints.length)))
    visitedPoints.push({
      latitude: latitude,
      longitude: longitude
    })
    if (visitedPoints.length < 2) {
      return
    }

    this.lastTrailSampleLat = latitude
    this.lastTrailSampleLng = longitude
    await this.replaceVisitedRouteOverlays(visitedPoints)
  }

  private moveToNode(index: number): void {
    if (!this.replayRoute || !this.mapController) {
      return
    }
    if (index < 0 || index >= this.replayRoute.nodes.length) {
      return
    }

    this.currentNodeIndex = index
    const lastIndex = this.replayRoute.nodes.length - 1
    this.progress = lastIndex === 0 ? 100 : (index / lastIndex) * 100

    const prevIndex = Math.max(0, index - 1)
    const fromNode = this.replayRoute.nodes[prevIndex]
    const targetNode = this.replayRoute.nodes[index]
    const bearing = this.calculateBearing(
      fromNode.position.latitude,
      fromNode.position.longitude,
      targetNode.position.latitude,
      targetNode.position.longitude
    )
    this.cameraBearing = bearing

    if (prevIndex !== index) {
      this.startMovingIconAnimation(fromNode.position, targetNode.position)
    }

    this.routeTrailGeneration += 1
    const generation = this.routeTrailGeneration

    // #221: 按段长动态 zoom, 短路线自动放大, animateCamera 会平滑过渡
    const dynamicZoom = this.replayZoomForIndex(index)
    const offset = this.cameraTargetOffsetForBearingZoom(targetNode.position.latitude, dynamicZoom, bearing)
    const cameraUpdate = map.newCameraPosition({
      target: {
        latitude: targetNode.position.latitude + offset.latOffset,
        longitude: targetNode.position.longitude + offset.lngOffset
      },
      zoom: dynamicZoom,
      bearing: bearing,
      tilt: 45
    })
    this.mapController.animateCamera(cameraUpdate, this.getMoveDuration())
    setTimeout(() => {
      if (generation === this.routeTrailGeneration) {
        void this.syncVisitedRouteToNodeIndex(index)
      }
      this.movingIconVisible = false
    }, this.getMoveDuration())
  }

  private startMovingIconAnimation(fromPos: Position, toPos: Position): void {
    this.movingIconVisible = true
    const projection = this.mapController?.getProjection()
    if (projection) {
      const startPos = projection.toScreenLocation({
        latitude: fromPos.latitude,
        longitude: fromPos.longitude
      })
      this.movingIconScreenX = px2vp(startPos.positionX)
      this.movingIconScreenY = px2vp(startPos.positionY)
    }

    const duration = this.getMoveDuration()
    const intervalMs = this.playbackSpeed === '0.5x' ? 100 : 80
    const steps = Math.floor(duration / intervalMs)
    let currentStep = 0

    const timer = setInterval(() => {
      if (!this.movingIconVisible || currentStep >= steps || !this.mapController) {
        clearInterval(timer)
        return
      }

      const progress = currentStep / steps
      const currentLat = fromPos.latitude + (toPos.latitude - fromPos.latitude) * progress
      const currentLng = fromPos.longitude + (toPos.longitude - fromPos.longitude) * progress
      const proj = this.mapController.getProjection()
      if (proj) {
        const screenPos = proj.toScreenLocation({
          latitude: currentLat,
          longitude: currentLng
        })
        this.movingIconScreenX = px2vp(screenPos.positionX)
        this.movingIconScreenY = px2vp(screenPos.positionY)
      }
      if (this.enableRouteAnimation) {
        void this.syncVisitedRouteToMovingPosition(this.currentNodeIndex, currentLat, currentLng)
      }
      currentStep++
    }, intervalMs)
  }

  private calculateBearing(fromLat: number, fromLng: number, toLat: number, toLng: number): number {
    const dLon = (toLng - fromLng) * Math.PI / 180
    const lat1 = fromLat * Math.PI / 180
    const lat2 = toLat * Math.PI / 180
    const y = Math.sin(dLon) * Math.cos(lat2)
    const x = Math.cos(lat1) * Math.sin(lat2) -
      Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLon)
    const bearing = Math.atan2(y, x) * 180 / Math.PI
    return (bearing + 360) % 360
  }

  /** #221: 段距离 → 推荐 zoom。
   * 原先所有 moveToNode 都用固定 zoom=15 (~4.4m/px @ lat 22.5)。
   * 当两节点相距 100m 时, 段在屏幕上只有 ~22px, 几乎看不到。
   * 这里按段长阶梯放大, 让段大约占屏幕 30-40% 宽。
   * AMap-side animateCamera 会平滑过渡 zoom, 视觉效果像"段越短越拉近"。
   */
  private haversineMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
    const R = 6378137
    const toRad = (d: number): number => d * Math.PI / 180
    const dLat = toRad(lat2 - lat1)
    const dLng = toRad(lng2 - lng1)
    const sinDLat = Math.sin(dLat / 2)
    const sinDLng = Math.sin(dLng / 2)
    const a = sinDLat * sinDLat + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * sinDLng * sinDLng
    return 2 * R * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  }

  private replayZoomForSegment(distMeters: number): number {
    // 比 #221 初版整体多放大一档：把段的两个钉子推得更开，避免一屏里
    // 多个节点视觉上挤在一起。这里只影响 zoom，不影响钉子的屏幕落点
    // (cameraTargetOffsetForBearingZoom 的偏移随 mPerPx 自动等比缩放)。
    if (distMeters > 8000) return 13
    if (distMeters > 3000) return 14
    if (distMeters > 1000) return 15
    if (distMeters > 400)  return 16
    if (distMeters > 150)  return 17
    return 18
  }

  /** 为给定节点 index 算合适 zoom。
   * 优先看当前 → 下一节点的段长（决定即将进入的视觉感觉），如果是最后一个节点
   * 就回退看 prev → 当前。短路线 / 单节点情况兜底 15。
   */
  private replayZoomForIndex(index: number): number {
    if (!this.replayRoute) return 15
    const nodes = this.replayRoute.nodes
    if (nodes.length < 2) return 15
    let from: Position
    let to: Position
    if (index < nodes.length - 1) {
      from = nodes[index].position
      to = nodes[index + 1].position
    } else {
      from = nodes[index - 1].position
      to = nodes[index].position
    }
    return this.replayZoomForSegment(this.haversineMeters(from.latitude, from.longitude, to.latitude, to.longitude))
  }

  /** 计算到达节点 index 时"前向"运镜 bearing，跟自动播放 moveToNode 保持一致。
   * 一般用 nodes[index-1] → nodes[index] 段的方向；index=0 没有 prev 段，
   * 退回 nodes[0] → nodes[1] (跟初始绘制保持一致)。
   */
  private bearingForReplayIndex(index: number): number {
    if (!this.replayRoute || this.replayRoute.nodes.length < 2) return 0
    const nodes = this.replayRoute.nodes
    const fromIdx = index >= 1 ? index - 1 : 0
    const toIdx = index >= 1 ? index : 1
    return this.calculateBearing(
      nodes[fromIdx].position.latitude,
      nodes[fromIdx].position.longitude,
      nodes[toIdx].position.latitude,
      nodes[toIdx].position.longitude
    )
  }

  /** 让钉子在屏幕上始终落在视觉中心下方约 vpShiftSouth vp（默认 150）。
   *
   * 推导：假设 HMOS map 是把整张地图按 bearing 顺时针旋转屏幕坐标系
   * 而不是绕世界垂直轴转相机（screen-rotation 约定，跟标准 CW-from-north
   * 相机模型差一个 east 分量符号）。要使钉子落在屏幕正下方 (0, +h)，相机
   * target 需要在世界坐标里相对节点偏移 (−h sin B, +h cos B) (east, north)。
   *
   * 注意：Web Mercator 公式给的 m/px 是逻辑像素(HMOS 的 vp)，不要再 vp2px,
   * 否则相机会被推到节点几公里外、钉子和路线全部移出视野。
   */
  private cameraTargetOffsetForBearingZoom(
    lat: number,
    zoom: number,
    bearing: number,
    vpShiftSouth: number = 150
  ): CameraTargetOffset {
    const cosLat = Math.cos(lat * Math.PI / 180)
    const mPerPx = (cosLat * 2 * Math.PI * 6378137) / (256 * Math.pow(2, zoom))
    const meters = vpShiftSouth * mPerPx
    const bearingRad = bearing * Math.PI / 180
    const deltaNorthMeters = meters * Math.cos(bearingRad)
    const deltaEastMeters = -meters * Math.sin(bearingRad)
    return {
      latOffset: deltaNorthMeters / 110540,
      lngOffset: deltaEastMeters / (110540 * cosLat)
    }
  }

  private resetCameraToNorth(): void {
    if (!this.mapController || !this.replayRoute) {
      return
    }
    this.cameraBearing = 0
    const node = this.replayRoute.nodes[this.currentNodeIndex]
    // #221 跟进：指北重置也按当前段长动态 zoom，跟自动回放的视觉保持一致
    const dynamicZoom = this.replayZoomForIndex(this.currentNodeIndex)
    const offset = this.cameraTargetOffsetForBearingZoom(node.position.latitude, dynamicZoom, 0)
    const cameraUpdate = map.newCameraPosition({
      target: {
        latitude: node.position.latitude + offset.latOffset,
        longitude: node.position.longitude + offset.lngOffset
      },
      zoom: dynamicZoom,
      bearing: 0,
      tilt: 0
    })
    this.mapController.animateCamera(cameraUpdate, 400)
  }

  private jumpToNode(index: number): void {
    this.stopPlay()
    if (!this.replayRoute || index < 0 || index >= this.replayRoute.nodes.length) {
      return
    }
    this.performManualJump(index)
  }

  private performManualJump(index: number): void {
    if (!this.replayRoute) {
      return
    }

    this.manualJumpGeneration += 1
    this.routeTrailGeneration += 1
    const generation = this.manualJumpGeneration
    this.isCardVisible = false
    this.cardOpacity = 1
    this.cardScale = 1
    this.cardTranslateX = 0
    this.currentNodeIndex = index
    const lastIndex = this.replayRoute.nodes.length - 1
    this.progress = lastIndex === 0 ? 100 : (index / lastIndex) * 100
    this.currentPhase = PHASE_IDLE
    void this.syncVisitedRouteToNodeIndex(index)

    const targetNode = this.replayRoute.nodes[index]
    if (this.mapController) {
      // #221 跟进：手动点上/下一节点 / 拖进度条触发的跳转，跟自动播放
      // moveToNode 完全对齐——按段长动态 zoom，并把 bearing 也算出来
      // 显式 set 到 newCameraPosition（之前不传 bearing 会让 map 用旧 bearing
      // 而我的 offset 又按当前 cameraBearing 算，连按几次就累积出旋转偏移）。
      const dynamicZoom = this.replayZoomForIndex(index)
      const segmentBearing = this.bearingForReplayIndex(index)
      this.cameraBearing = segmentBearing
      const offset = this.cameraTargetOffsetForBearingZoom(targetNode.position.latitude, dynamicZoom, segmentBearing)
      const cameraUpdate = map.newCameraPosition({
        target: {
          latitude: targetNode.position.latitude + offset.latOffset,
          longitude: targetNode.position.longitude + offset.lngOffset
        },
        zoom: dynamicZoom,
        bearing: segmentBearing,
        tilt: 45
      })
      this.mapController.animateCamera(cameraUpdate, 420)
    }

    setTimeout(() => {
      if (generation !== this.manualJumpGeneration || !this.replayRoute || this.currentNodeIndex !== index) {
        return
      }
      this.showManualJumpCard()
    }, 420)
  }

  private showManualJumpCard(): void {
    this.cardOpacity = 0
    this.cardScale = 1
    this.cardTranslateX = 0
    this.isCardVisible = true
    animateTo({
      duration: 220,
      curve: Curve.EaseOut
    }, () => {
      this.cardOpacity = 1
      this.cardScale = 1
      this.cardTranslateX = 0
    })
  }

  private goToPrevNode(): void {
    if (this.currentNodeIndex > 0) {
      this.jumpToNode(this.currentNodeIndex - 1)
    }
  }

  private goToNextNode(): void {
    if (this.replayRoute && this.currentNodeIndex < this.replayRoute.nodes.length - 1) {
      this.jumpToNode(this.currentNodeIndex + 1)
    }
  }

  private async cycleSpeed(): Promise<void> {
    const currentIndex = this.speeds.indexOf(this.playbackSpeed)
    this.playbackSpeed = this.speeds[(currentIndex + 1) % this.speeds.length]
    await this.updateMusicSpeed(this.playbackSpeed)
  }

  private showOverlayCard(node: ReplayNode): void {
    this.overlayNode = node
    this.showOverlay = true
  }

  private hideOverlayCard(): void {
    this.showOverlay = false
    this.overlayNode = null
  }

  private openSettingsSheet(): void {
    this.showSettingsSheet = true
  }

  private closeSettingsSheet(): void {
    this.showSettingsSheet = false
  }

  build() {
    Stack() {
      MapComponent({ mapOptions: this.mapOptions, mapCallback: this.mapCallback })
        .width('100%')
        .height('100%')

      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.currentStyleKit.pageMaskColor)

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(AppColors.PRIMARY)
          Text('加载中...')
            .fontSize(AppDimens.FONT_MD)
            .fontColor(AppColors.TEXT_ON_PRIMARY)
            .margin({ top: 8 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#22000000')
      }

      if (!this.isLoading && !this.replayRoute) {
        Column() {
          Text('📷')
            .fontSize(48)
          Text('暂无回放数据')
            .fontSize(AppDimens.FONT_LG)
            .fontColor(AppColors.TEXT_ON_PRIMARY)
            .margin({ top: 16 })
          Text('请先添加旅行节点')
            .fontSize(AppDimens.FONT_MD)
            .fontColor(AppColors.TEXT_HINT)
            .margin({ top: 8 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }

      if (this.movingIconVisible && !this.enableRouteAnimation) {
        Column() {
          SymbolGlyph($r('sys.symbol.figure_walk'))
            .fontSize(32)
            .fontColor([Color.White])
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.currentStyleKit.progressSelectedColor)
        .borderRadius(22)
        .shadow({ radius: 6, color: this.currentStyleKit.shadowColor, offsetY: 2 })
        .position({ x: this.movingIconScreenX - 22, y: this.movingIconScreenY - 44 })
        .zIndex(50)
      }

      if (this.isCardVisible && this.replayRoute && this.currentNodeIndex < this.replayRoute.nodes.length) {
        ReplayPhotoCard({
          node: this.replayRoute.nodes[this.currentNodeIndex],
          isPlaying: this.isPlaying,
          isExpanded: false,
          styleKit: this.currentStyleKit,
          filterId: this.selectedFilterId,
          onExpand: (node: ReplayNode) => {
            this.showOverlayCard(node)
          }
        })
        // 卡片在上、定位钉在下：卡片贴顶部安全区下方固定锚定；
        // 钉子通过 cameraTargetOffsetForBearingZoom 推到屏幕视觉中心下方约
        // 200vp 处（即屏幕下三分之一），bearing 旋转下也始终落在屏幕正下方。
        .position({ x: '50%', y: 96 })
        .translate({ x: -140 + this.cardTranslateX, y: 0 })
        .scale({ x: this.cardScale, y: this.cardScale })
        .opacity(this.cardOpacity)
        .zIndex(70)
      }

      Column() {
        ReplayProgressBar({
          value: this.progress,
          nodeCount: this.replayRoute ? this.replayRoute.nodes.length : 0,
          styleKit: this.currentStyleKit,
          onChange: (index: number) => {
            this.jumpToNode(index)
          }
        })
        .width('100%')

        Row() {
          SymbolGlyph($r('sys.symbol.backward_end_fill'))
            .fontSize(22)
            .fontColor([this.currentStyleKit.controlPrimaryColor])
            .padding(AppDimens.PADDING_MD)
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
            .onClick(() => this.goToPrevNode())

          Blank()
            .layoutWeight(1)

          if (this.isPlaying) {
            SymbolGlyph($r('sys.symbol.pause_fill'))
              .fontSize(28)
              .fontColor([this.currentStyleKit.controlPrimaryColor])
              .padding({ left: AppDimens.PADDING_SM, right: AppDimens.PADDING_SM })
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
              .onClick(() => this.togglePlay())
          } else {
            SymbolGlyph($r('sys.symbol.play_fill'))
              .fontSize(28)
              .fontColor([this.currentStyleKit.controlPrimaryColor])
              .padding({ left: AppDimens.PADDING_SM, right: AppDimens.PADDING_SM })
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
              .onClick(() => this.togglePlay())
          }

          Text(this.playbackSpeed)
            .fontSize(AppDimens.FONT_MD)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.currentStyleKit.controlMutedColor)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor('#22FFFFFF')
            .backgroundBlurStyle(BlurStyle.Thin, { colorMode: ThemeColorMode.SYSTEM, adaptiveColor: AdaptiveColor.DEFAULT })
            .border({ width: 0.8, color: '#55FFFFFF' })
            .borderRadius(16)
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
            .onClick(() => {
              void this.cycleSpeed()
            })

          Blank()
            .layoutWeight(1)

          SymbolGlyph($r('sys.symbol.forward_end_fill'))
            .fontSize(22)
            .fontColor([this.currentStyleKit.controlPrimaryColor])
            .padding(AppDimens.PADDING_MD)
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
            .onClick(() => this.goToNextNode())
        }
        .width('100%')
        .height(60)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding({ left: AppDimens.PADDING_LG, right: AppDimens.PADDING_LG, top: 12, bottom: 36 })
      .backgroundColor(this.currentStyleKit.controlBarBackground)
      .backgroundBlurStyle(BlurStyle.Thin, { colorMode: ThemeColorMode.SYSTEM, adaptiveColor: AdaptiveColor.DEFAULT })
      .border({ width: 1, color: this.currentStyleKit.controlBarBorderColor })
      .borderRadius({ topLeft: AppDimens.RADIUS_LG, topRight: AppDimens.RADIUS_LG })
      .shadow({ radius: 26, color: AppDimens.SHADOW_FLOAT, offsetY: -8 })
      .position({ x: 0, y: '82%' })
      .zIndex(90)

      Stack() {
        SymbolGlyph($r('sys.symbol.arrow_left'))
          .fontSize(AppDimens.FONT_XL)
          .fontColor([Color.White])
      }
      .width(40)
      .height(40)
      .backgroundColor('#4D111111')
      .backgroundBlurStyle(BlurStyle.Thin, { colorMode: ThemeColorMode.SYSTEM, adaptiveColor: AdaptiveColor.DEFAULT })
      .border({ width: 0.8, color: '#66FFFFFF' })
      .borderRadius(20)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
      .onClick(() => router.back())
      .position({ x: 16, y: 24 })
      .zIndex(100)

      Stack() {
        SymbolGlyph($r('sys.symbol.music'))
          .fontSize(20)
          .fontColor([this.isAudioPlaying ? Color.White : '#999999'])
      }
      .width(40)
      .height(40)
      .backgroundColor('#4D111111')
      .backgroundBlurStyle(BlurStyle.Thin, { colorMode: ThemeColorMode.SYSTEM, adaptiveColor: AdaptiveColor.DEFAULT })
      .border({ width: 0.8, color: '#66FFFFFF' })
      .borderRadius(20)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
      .onClick(() => this.toggleMusic())
      .position({ x: '100%', y: 24 })
      .translate({ x: -56 })
      .zIndex(100)

      Stack() {
        SymbolGlyph($r('sys.symbol.gearshape'))
          .fontSize(20)
          .fontColor([Color.White])
      }
      .width(40)
      .height(40)
      .backgroundColor('#4D111111')
      .backgroundBlurStyle(BlurStyle.Thin, { colorMode: ThemeColorMode.SYSTEM, adaptiveColor: AdaptiveColor.DEFAULT })
      .border({ width: 0.8, color: '#66FFFFFF' })
      .borderRadius(20)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
      .onClick(() => this.openSettingsSheet())
      .position({ x: '100%', y: 24 })
      .translate({ x: -104 })
      .zIndex(100)

      Stack() {
        SymbolGlyph($r('sys.symbol.arrow_up'))
          .fontSize(20)
          .fontColor([Color.White])
          .rotate({ angle: -this.cameraBearing })
      }
      .width(40)
      .height(40)
      .backgroundColor('#4D111111')
      .backgroundBlurStyle(BlurStyle.Thin, { colorMode: ThemeColorMode.SYSTEM, adaptiveColor: AdaptiveColor.DEFAULT })
      .border({ width: 0.8, color: '#66FFFFFF' })
      .borderRadius(20)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
      .onClick(() => this.resetCameraToNorth())
      .position({ x: 16, y: '74%' })
      .zIndex(100)

      if (this.showOverlay && this.overlayNode) {
        PhotoCardOverlay({
          isVisible: this.showOverlay,
          currentNode: this.overlayNode,
          styleKit: this.currentStyleKit,
          filterId: this.selectedFilterId,
          useBlurOverlay: this.enableBlurOverlay,
          onClose: () => {
            this.hideOverlayCard()
          }
        })
      }

      if (this.showSettingsSheet) {
        ReplaySettingsSheet({
          isVisible: this.showSettingsSheet,
          selectedStyleKitId: this.selectedStyleKitId,
          selectedBgmId: this.selectedBgmId,
          selectedFilterId: this.selectedFilterId,
          selectedTransitionType: this.selectedTransitionType,
          enableRouteAnimation: this.enableRouteAnimation,
          enableBlurOverlay: this.enableBlurOverlay,
          onClose: () => {
            this.closeSettingsSheet()
          },
          onStyleChange: (styleKitId: ReplayStyleKitId) => {
            this.selectedStyleKitId = styleKitId
            this.currentStyleKit = ReplayStyleKitCatalog.getById(styleKitId)
            void this.refreshRouteOverlays()
            void this.persistReplayPreferences({
              replayStyleKitId: styleKitId
            })
          },
          onBgmChange: (bgmId: ReplayBgmId) => {
            this.selectedBgmId = bgmId
            void this.persistReplayPreferences({
              replayBgmId: bgmId
            })
            void this.reloadMusic()
          },
          onFilterChange: (filterId: ReplayFilterId) => {
            this.selectedFilterId = filterId
            void this.persistReplayPreferences({
              replayFilterId: filterId
            })
          },
          onTransitionChange: (transitionType: ReplayTransitionType) => {
            this.selectedTransitionType = transitionType
            void this.persistReplayPreferences({
              replayTransitionType: transitionType
            })
          },
          onRouteAnimationToggle: (enabled: boolean) => {
            this.enableRouteAnimation = enabled
            this.routeTrailGeneration += 1
            void this.refreshRouteOverlays()
            void this.persistReplayPreferences({
              replayEnableRouteAnimation: enabled
            })
          },
          onBlurOverlayToggle: (enabled: boolean) => {
            this.enableBlurOverlay = enabled
            void this.persistReplayPreferences({
              replayEnableBlurOverlay: enabled
            })
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
