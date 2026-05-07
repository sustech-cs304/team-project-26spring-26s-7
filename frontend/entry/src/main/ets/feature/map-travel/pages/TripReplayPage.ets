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
  @State enableRipple: boolean = false
  @State enableBlurOverlay: boolean = false
  @State currentStyleKit: ReplayStyleKit = ReplayStyleKitCatalog.getById(ReplayStyleKitCatalog.DEFAULT_ID)

  @State movingIconVisible: boolean = false
  @State movingIconScreenX: number = 0
  @State movingIconScreenY: number = 0

  @State rippleVisible: boolean = false
  @State rippleCenterX: number = 180
  @State rippleCenterY: number = 320
  @State rippleScale: number = 0.2
  @State rippleOpacity: number = 0.42

  private speeds: string[] = ['0.5x', '1x', '2x']
  private playTimer: number = -1
  private readonly FADE_IN_DURATION: number = 2000
  private readonly STAY_DURATION: number = 3000
  private readonly FADE_OUT_DURATION: number = 1000
  private readonly MOVE_DURATION: number = 1500
  @State private currentPhase: number = PHASE_IDLE

  private mapOptions: mapCommon.MapOptions = {
    position: {
      target: DEFAULT_REPLAY_CENTER,
      zoom: 13
    },
    padding: {
      left: 0,
      right: 0,
      top: 0,
      bottom: 320
    }
  }
  private mapController?: map.MapComponentController
  private routeRendered: boolean = false
  private dataService = getDataService()
  private pauseAfterReload: boolean = false

  private mapCallback: AsyncCallback<map.MapComponentController> = async (err, controller) => {
    if (!err && controller) {
      this.mapController = controller
      await this.drawRouteAndMarkers()
    }
  }

  private avPlayer: media.AVPlayer | undefined = undefined
  @State private isAudioPlaying: boolean = false

  private async initAndPlayMusic(): Promise<void> {
    try {
      const uiContext = this.getUIContext()
      const context = uiContext.getHostContext() as common.UIAbilityContext
      if (!context) {
        return
      }

      const avPlayer: media.AVPlayer = await media.createAVPlayer()
      this.regAVPlayerCallback(avPlayer)
      this.avPlayer = avPlayer

      const selectedTrack = ReplayMusicCatalog.getById(this.selectedBgmId)
      const fileDescriptor = await context.resourceManager.getRawFd(selectedTrack.filename)
      avPlayer.fdSrc = {
        fd: fileDescriptor.fd,
        offset: fileDescriptor.offset,
        length: fileDescriptor.length
      }
    } catch (err) {
      console.error('TripReplayPage: initAndPlayMusic failed', JSON.stringify(err))
    }
  }

  private async reloadMusic(): Promise<void> {
    this.pauseAfterReload = !this.isAudioPlaying
    await this.stopMusic()
    await this.initAndPlayMusic()
  }

  private regAVPlayerCallback(avPlayer: media.AVPlayer): void {
    avPlayer.on('error', () => {
      avPlayer.reset()
    })

    avPlayer.on('stateChange', (state: media.AVPlayerState) => {
      switch (state) {
        case 'initialized':
          void avPlayer.prepare()
          break
        case 'prepared':
          void avPlayer.play()
          break
        case 'playing':
          this.isAudioPlaying = true
          if (this.pauseAfterReload) {
            this.pauseAfterReload = false
            avPlayer.pause()
          }
          break
        case 'paused':
          this.isAudioPlaying = false
          break
        case 'completed':
          avPlayer.seek(0)
          void avPlayer.play()
          break
        case 'stopped':
          avPlayer.reset()
          break
        case 'released':
          this.avPlayer = undefined
          this.isAudioPlaying = false
          break
      }
    })
  }

  private async updateMusicSpeed(_speed: string): Promise<void> {
    console.info(`TripReplayPage: playback speed ${_speed}, audio speed is left unchanged`)
  }

  private toggleMusic(): void {
    if (!this.avPlayer) {
      return
    }
    if (this.isAudioPlaying) {
      this.avPlayer.pause()
    } else {
      void this.avPlayer.play()
    }
  }

  private async stopMusic(): Promise<void> {
    if (this.avPlayer) {
      try {
        await this.avPlayer.stop()
        this.avPlayer.release()
      } catch (err) {
        console.error('TripReplayPage: stopMusic failed', JSON.stringify(err))
      } finally {
        this.avPlayer = undefined
        this.isAudioPlaying = false
      }
    }
  }

  aboutToAppear(): void {
    ReplayPreferences.initializeDefaults()
    const params = router.getParams() as RouterParam
    if (params?.tripId) {
      this.currentTripId = params.tripId
      void this.loadReplayData(params.tripId)
    } else {
      promptAction.showToast({ message: '缺少旅行 ID 参数' })
    }
  }

  aboutToDisappear(): void {
    this.stopPlay()
    void this.stopMusic()
  }

  private applyReplayPreferences(preferences: ReplayTripPreferences): void {
    const fallback = ReplayPreferences.getState()
    this.selectedStyleKitId = (preferences.replayStyleKitId as ReplayStyleKitId) || fallback.styleKitId
    this.selectedBgmId = (preferences.replayBgmId as ReplayBgmId) || fallback.bgmId
    this.selectedFilterId = (preferences.replayFilterId as ReplayFilterId) || fallback.filterId
    this.selectedTransitionType = (preferences.replayTransitionType as ReplayTransitionType) || fallback.transitionType
    this.enableRipple = preferences.replayEnableRipple ?? fallback.enableRipple
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
    this.triggerRippleIfNeeded()

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
    if (!this.mapController || !this.replayRoute || this.routeRendered) {
      return
    }

    const positions: mapCommon.LatLng[] = []
    for (const node of this.replayRoute.nodes) {
      positions.push({
        latitude: node.position.latitude,
        longitude: node.position.longitude
      })
    }

    if (positions.length === 0) {
      return
    }

    if (positions.length > 1) {
      await this.mapController.addPolyline({
        points: positions,
        clickable: false,
        visible: true,
        width: this.currentStyleKit.mapPolylineWidth,
        zIndex: 5,
        geodesic: true,
        gradient: false,
        jointType: mapCommon.JointType.ROUND,
        startCap: mapCommon.CapStyle.ROUND,
        endCap: mapCommon.CapStyle.ROUND
      })
    }

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

    const latitudeOffset = 0.0025
    if (positions.length > 1) {
      const bearing = this.calculateBearing(
        positions[0].latitude,
        positions[0].longitude,
        positions[1].latitude,
        positions[1].longitude
      )
      const cameraUpdate = map.newCameraPosition({
        target: {
          latitude: positions[0].latitude + latitudeOffset,
          longitude: positions[0].longitude
        },
        zoom: 15,
        bearing: bearing,
        tilt: 45
      })
      this.mapController.animateCamera(cameraUpdate, 1000)
    } else {
      const cameraUpdate = map.newCameraPosition({
        target: {
          latitude: positions[0].latitude + latitudeOffset,
          longitude: positions[0].longitude
        },
        zoom: 15
      })
      this.mapController.animateCamera(cameraUpdate, 500)
    }
    this.routeRendered = true
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

    if (prevIndex !== index) {
      this.startMovingIconAnimation(fromNode.position, targetNode.position)
    }

    const cameraUpdate = map.newCameraPosition({
      target: {
        latitude: targetNode.position.latitude,
        longitude: targetNode.position.longitude
      },
      zoom: 15,
      bearing: bearing,
      tilt: 45
    })
    this.mapController.animateCamera(cameraUpdate, this.getMoveDuration())
    setTimeout(() => {
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
      this.movingIconScreenX = startPos.positionX
      this.movingIconScreenY = startPos.positionY
    }

    const duration = this.getMoveDuration()
    const intervalMs = 50
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
        this.movingIconScreenX = screenPos.positionX
        this.movingIconScreenY = screenPos.positionY
      }
      currentStep++
    }, intervalMs)
  }

  private triggerRippleIfNeeded(): void {
    if (!this.enableRipple || !this.replayRoute || !this.mapController) {
      return
    }
    const currentNode = this.replayRoute.nodes[this.currentNodeIndex]
    const projection = this.mapController.getProjection()
    if (projection) {
      const point = projection.toScreenLocation({
        latitude: currentNode.position.latitude,
        longitude: currentNode.position.longitude
      })
      this.rippleCenterX = point.positionX
      this.rippleCenterY = point.positionY - 12
    }

    this.rippleVisible = true
    this.rippleScale = 0.2
    this.rippleOpacity = 0.42
    animateTo({
      duration: 900,
      curve: Curve.EaseOut,
      onFinish: () => {
        this.rippleVisible = false
      }
    }, () => {
      this.rippleScale = 1.8
      this.rippleOpacity = 0
    })
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

  private jumpToNode(index: number): void {
    this.stopPlay()
    if (!this.replayRoute || index < 0 || index >= this.replayRoute.nodes.length) {
      return
    }

    this.isCardVisible = false
    this.currentNodeIndex = index
    const lastIndex = this.replayRoute.nodes.length - 1
    this.progress = lastIndex === 0 ? 100 : (index / lastIndex) * 100
    this.currentPhase = PHASE_IDLE

    const targetNode = this.replayRoute.nodes[index]
    if (this.mapController) {
      const cameraUpdate = map.newCameraPosition({
        target: {
          latitude: targetNode.position.latitude,
          longitude: targetNode.position.longitude
        },
        zoom: 15,
        tilt: 45
      })
      this.mapController.animateCamera(cameraUpdate, 500)
    }

    setTimeout(() => {
      this.prepareCardEnterState()
      this.isCardVisible = true
      this.triggerRippleIfNeeded()
      animateTo({
        duration: 320,
        curve: Curve.EaseOut
      }, () => {
        this.cardOpacity = 1
        this.cardScale = 1
        this.cardTranslateX = 0
      })
    }, 500)
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

  private getEffectSummaryChips(): string[] {
    const chips: string[] = []
    chips.push(`滤镜 ${this.selectedFilterId === ReplayFilterId.NONE ? '原片' : '已启用'}`)
    if (this.enableRipple) {
      chips.push('节点波纹')
    }
    if (this.enableBlurOverlay) {
      chips.push('玻璃详情层')
    }
    return chips
  }

  @Builder
  private buildRipple() {
    if (this.rippleVisible) {
      Stack() {
        Column()
          .width(84)
          .height(84)
          .borderRadius(42)
          .border({ width: 2, color: this.currentStyleKit.rippleColor })
          .opacity(this.rippleOpacity)
          .scale({ x: this.rippleScale, y: this.rippleScale })

        Column()
          .width(84)
          .height(84)
          .borderRadius(42)
          .border({ width: 1, color: this.currentStyleKit.rippleColor })
          .opacity(this.rippleOpacity * 0.72)
          .scale({ x: this.rippleScale * 0.72, y: this.rippleScale * 0.72 })
      }
      .width(84)
      .height(84)
      .position({ x: this.rippleCenterX - 42, y: this.rippleCenterY - 42 })
      .zIndex(40)
    }
  }

  @Builder
  private buildEffectChips() {
    Column() {
      Row() {
        ForEach(this.getEffectSummaryChips(), (chip: string) => {
          Text(chip)
            .fontSize(AppDimens.FONT_SM)
            .fontColor('#FFFFFF')
            .backgroundColor('rgba(0, 0, 0, 0.42)')
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(14)
            .margin({ left: 8 })
        })
      }
      .justifyContent(FlexAlign.End)
      .width('100%')
    }
    .width('100%')
    .position({ x: 0, y: 96 })
    .padding({ right: 16 })
    .zIndex(100)
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
            .color('#FFFFFF')
          Text('加载中...')
            .fontSize(AppDimens.FONT_MD)
            .fontColor('#FFFFFF')
            .margin({ top: 8 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#00000044')
      }

      if (!this.isLoading && !this.replayRoute) {
        Column() {
          Text('📷')
            .fontSize(48)
          Text('暂无回放数据')
            .fontSize(AppDimens.FONT_LG)
            .fontColor('#FFFFFF')
            .margin({ top: 16 })
          Text('请先添加旅行节点')
            .fontSize(AppDimens.FONT_MD)
            .fontColor('#FFFFFFCC')
            .margin({ top: 8 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }

      this.buildRipple()

      if (this.movingIconVisible) {
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
        .position({ x: '50%', y: '35%' })
        .translate({ x: -140 + this.cardTranslateX, y: -90 })
        .scale({ x: this.cardScale, y: this.cardScale })
        .opacity(this.cardOpacity)
      }

      Column() {
        ReplayProgressBar({
          value: this.progress,
          nodeCount: this.replayRoute ? this.replayRoute.nodes.length : 0,
          nodeLabels: this.replayRoute ? this.replayRoute.nodes.map((node: ReplayNode) => {
            return this.formatShortDate(node.timestamp)
          }) : [],
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
            .onClick(() => this.goToPrevNode())

          Blank()
            .layoutWeight(1)

          if (this.isPlaying) {
            SymbolGlyph($r('sys.symbol.pause_fill'))
              .fontSize(28)
              .fontColor([this.currentStyleKit.controlPrimaryColor])
              .padding({ left: AppDimens.PADDING_SM, right: AppDimens.PADDING_SM })
              .onClick(() => this.togglePlay())
          } else {
            SymbolGlyph($r('sys.symbol.play_fill'))
              .fontSize(28)
              .fontColor([this.currentStyleKit.controlPrimaryColor])
              .padding({ left: AppDimens.PADDING_SM, right: AppDimens.PADDING_SM })
              .onClick(() => this.togglePlay())
          }

          Text(this.playbackSpeed)
            .fontSize(AppDimens.FONT_MD)
            .fontColor(this.currentStyleKit.controlMutedColor)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .onClick(() => {
              void this.cycleSpeed()
            })

          Blank()
            .layoutWeight(1)

          SymbolGlyph($r('sys.symbol.forward_end_fill'))
            .fontSize(22)
            .fontColor([this.currentStyleKit.controlPrimaryColor])
            .padding(AppDimens.PADDING_MD)
            .onClick(() => this.goToNextNode())
        }
        .width('100%')
        .height(60)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding({ left: AppDimens.PADDING_LG, right: AppDimens.PADDING_LG, top: 12, bottom: 36 })
      .backgroundColor(this.currentStyleKit.controlBarBackground)
      .border({ width: 1, color: this.currentStyleKit.controlBarBorderColor })
      .position({ x: 0, y: '82%' })
      .zIndex(90)

      Stack() {
        SymbolGlyph($r('sys.symbol.arrow_left'))
          .fontSize(AppDimens.FONT_XL)
          .fontColor([Color.White])
      }
      .width(40)
      .height(40)
      .backgroundColor('rgba(0, 0, 0, 0.7)')
      .borderRadius(20)
      .onClick(() => router.back())
      .position({ x: 16, y: 48 })
      .zIndex(100)

      Stack() {
        SymbolGlyph($r('sys.symbol.music'))
          .fontSize(20)
          .fontColor([this.isAudioPlaying ? Color.White : '#999999'])
      }
      .width(40)
      .height(40)
      .backgroundColor(this.isAudioPlaying ? 'rgba(0, 0, 0, 0.7)' : 'rgba(0, 0, 0, 0.4)')
      .borderRadius(20)
      .onClick(() => this.toggleMusic())
      .position({ x: '100%', y: 48 })
      .translate({ x: -56 })
      .zIndex(100)

      Stack() {
        SymbolGlyph($r('sys.symbol.gearshape'))
          .fontSize(20)
          .fontColor([Color.White])
      }
      .width(40)
      .height(40)
      .backgroundColor('rgba(0, 0, 0, 0.7)')
      .borderRadius(20)
      .onClick(() => this.openSettingsSheet())
      .position({ x: '100%', y: 48 })
      .translate({ x: -104 })
      .zIndex(100)

      this.buildEffectChips()

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
          enableRipple: this.enableRipple,
          enableBlurOverlay: this.enableBlurOverlay,
          onClose: () => {
            this.closeSettingsSheet()
          },
          onStyleChange: (styleKitId: ReplayStyleKitId) => {
            this.selectedStyleKitId = styleKitId
            this.currentStyleKit = ReplayStyleKitCatalog.getById(styleKitId)
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
          onRippleToggle: (enabled: boolean) => {
            this.enableRipple = enabled
            void this.persistReplayPreferences({
              replayEnableRipple: enabled
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
