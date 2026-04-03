import { router, promptAction } from '@kit.ArkUI'
import { MapComponent, mapCommon, map } from '@kit.MapKit'
import { AsyncCallback } from '@kit.BasicServicesKit'
import { AppColors, AppDimens, getDataService } from '../../../common'
import { RouterParam } from '../../../common'
import type { MemoryNode } from '../../../common'

const DEFAULT_REPLAY_CENTER: mapCommon.LatLng = {
  latitude: 22.55,
  longitude: 113.96
}

/**
 * P07 旅程回放页 — 全屏沉浸式动画回放
 * 路由参数：{ tripId: string }
 */
@Entry
@Component
export struct TripReplayPage {
  @State isPlaying: boolean = false
  @State currentNodeIndex: number = 0
  @State playbackSpeed: string = '1x'
  @State progress: number = 0
  @State currentPlace: string = ''
  @State currentNote: string = ''
  @State isLoading: boolean = false

  private speeds: string[] = ['0.5x', '1x', '2x']
  private playTimer: number = -1

  private routePoints: mapCommon.LatLng[] = []
  private nodeNames: string[] = []
  private nodeNotes: string[] = []
  private tripDates: string[] = []

  private mapOptions: mapCommon.MapOptions = {
    position: {
      target: DEFAULT_REPLAY_CENTER,
      zoom: 13
    }
  }
  private mapController?: map.MapComponentController
  private routeRendered: boolean = false
  private dataService = getDataService()

  private mapCallback: AsyncCallback<map.MapComponentController> = async (err, controller) => {
    if (!err && controller) {
      this.mapController = controller
      await this.renderRoute()
    }
  }

  aboutToAppear(): void {
    const params = router.getParams() as RouterParam
    if (params?.tripId) {
      this.loadReplayData(params.tripId)
    }
  }

  aboutToDisappear(): void {
    clearInterval(this.playTimer)
  }

  private formatShortDate(timestamp: number): string {
    const date = new Date(timestamp)
    const month = (date.getMonth() + 1).toString().padStart(2, '0')
    const day = date.getDate().toString().padStart(2, '0')
    return `${month}.${day}`
  }

  private getLastNodeIndex(): number {
    return this.routePoints.length > 0 ? this.routePoints.length - 1 : 0
  }

  private async loadReplayData(tripId: string): Promise<void> {
    this.isLoading = true
    try {
      const nodes = await this.dataService.getNodesByTravelId(tripId)
      if (nodes.length === 0) {
        promptAction.showToast({ message: '当前旅行还没有可回放的节点' })
        return
      }

      this.routePoints = nodes.map((node: MemoryNode): mapCommon.LatLng => ({
        latitude: node.latitude,
        longitude: node.longitude
      }))
      this.nodeNames = nodes.map((node: MemoryNode) => node.poiName || node.title)
      this.nodeNotes = nodes.map((node: MemoryNode) => node.content ? `"${node.content}"` : `"${node.title}"`)
      this.tripDates = nodes.map((node: MemoryNode) => this.formatShortDate(node.createdAt))
      this.currentNodeIndex = 0
      this.currentPlace = this.nodeNames[0]
      this.currentNote = this.nodeNotes[0]
      this.progress = 0
      this.routeRendered = false
      await this.renderRoute()
    } catch (err) {
      promptAction.showToast({ message: '加载回放数据失败' })
    } finally {
      this.isLoading = false
    }
  }

  private async renderRoute(): Promise<void> {
    if (!this.mapController || this.routeRendered || this.routePoints.length === 0) {
      return
    }

    if (this.routePoints.length > 1) {
      await this.mapController.addPolyline({
        points: this.routePoints,
        clickable: false,
        visible: true,
        width: 6,
        zIndex: 5,
        geodesic: false,
        gradient: false,
        jointType: mapCommon.JointType.ROUND,
        startCap: mapCommon.CapStyle.ROUND,
        endCap: mapCommon.CapStyle.ROUND
      })
    }

    for (const point of this.routePoints) {
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

    const cameraUpdate = map.newCameraPosition({
      target: this.routePoints[0],
      zoom: 13
    })
    this.mapController.animateCamera(cameraUpdate, 300)
    this.routeRendered = true
  }

  /** 飞到指定节点 */
  private flyToNode(index: number): void {
    if (!this.mapController || index < 0 || index >= this.routePoints.length) {
      return
    }
    this.currentNodeIndex = index
    this.currentPlace = this.nodeNames[index]
    this.currentNote = this.nodeNotes[index]
    const denominator = this.getLastNodeIndex()
    this.progress = denominator === 0 ? 100 : (index / denominator) * 100

    const cameraUpdate = map.newCameraPosition({
      target: this.routePoints[index],
      zoom: 15
    })
    this.mapController.animateCamera(cameraUpdate, 800)
  }

  private togglePlay(): void {
    if (this.routePoints.length === 0) {
      return
    }

    this.isPlaying = !this.isPlaying
    if (this.isPlaying) {
      this.playTimer = setInterval(() => {
        const next = this.currentNodeIndex + 1
        if (next >= this.routePoints.length) {
          this.isPlaying = false
          clearInterval(this.playTimer)
          return
        }
        this.flyToNode(next)
      }, this.getIntervalMs())
    } else {
      clearInterval(this.playTimer)
    }
  }

  private getIntervalMs(): number {
    if (this.playbackSpeed === '0.5x') {
      return 4000
    }
    if (this.playbackSpeed === '2x') {
      return 1000
    }
    return 2000
  }

  private cycleSpeed(): void {
    const currentIndex = this.speeds.indexOf(this.playbackSpeed)
    this.playbackSpeed = this.speeds[(currentIndex + 1) % this.speeds.length]
  }

  build() {
    Stack() {
      // 全屏地图
      MapComponent({ mapOptions: this.mapOptions, mapCallback: this.mapCallback })
        .width('100%')
        .height('100%')

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }

      // 退出按钮 (左上角)
      Text('✕')
        .fontSize(AppDimens.FONT_XL)
        .fontColor('#FFFFFF')
        .backgroundColor('#00000066')
        .borderRadius(20)
        .width(40)
        .height(40)
        .textAlign(TextAlign.Center)
        .position({ x: 16, y: 48 })
        .onClick(() => router.back())

      // 当前节点信息卡片
      Column() {
        Text('📷 ' + (this.currentPlace || '暂无节点'))
          .fontSize(AppDimens.FONT_LG)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
        Text(this.currentNote || '添加节点后即可生成旅程回放')
          .fontSize(AppDimens.FONT_MD)
          .fontColor('#FFFFFFCC')
          .margin({ top: 4 })
      }
      .width('90%')
      .padding(AppDimens.PADDING_MD)
      .backgroundColor('#000000AA')
      .borderRadius(AppDimens.RADIUS_MD)
      .position({ x: '5%', y: '60%' })

      // 底部控制栏
      Column() {
        Row() {
          Text(this.tripDates.length > 0 ? this.tripDates[0] : '--.--')
            .fontSize(AppDimens.FONT_SM)
            .fontColor('#FFFFFFCC')
          Slider({ value: this.progress, min: 0, max: 100 })
            .layoutWeight(1)
            .trackColor('#FFFFFF33')
            .selectedColor(AppColors.PRIMARY)
            .margin({ left: 8, right: 8 })
            .onChange((value: number) => {
              if (this.routePoints.length === 0) {
                return
              }
              const index = Math.round((value / 100) * this.getLastNodeIndex())
              this.flyToNode(index)
            })
          Text(this.tripDates.length > 0 ? this.tripDates[this.getLastNodeIndex()] : '--.--')
            .fontSize(AppDimens.FONT_SM)
            .fontColor('#FFFFFFCC')
        }
        .width('100%')

        Row() {
          Text('◄◄')
            .fontSize(AppDimens.FONT_LG)
            .fontColor('#FFFFFF')
            .padding(AppDimens.PADDING_MD)
            .onClick(() => {
              if (this.currentNodeIndex > 0) {
                this.flyToNode(this.currentNodeIndex - 1)
              }
            })

          Text(this.isPlaying ? '⏸' : '▶')
            .fontSize(28)
            .fontColor('#FFFFFF')
            .backgroundColor(AppColors.PRIMARY)
            .borderRadius(28)
            .width(56)
            .height(56)
            .textAlign(TextAlign.Center)
            .onClick(() => this.togglePlay())

          Text('►►')
            .fontSize(AppDimens.FONT_LG)
            .fontColor('#FFFFFF')
            .padding(AppDimens.PADDING_MD)
            .onClick(() => {
              if (this.currentNodeIndex < this.getLastNodeIndex()) {
                this.flyToNode(this.currentNodeIndex + 1)
              }
            })

          Blank()

          Text(this.playbackSpeed)
            .fontSize(AppDimens.FONT_MD)
            .fontColor('#FFFFFF')
            .backgroundColor('#FFFFFF33')
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(16)
            .onClick(() => this.cycleSpeed())
        }
        .width('100%')
        .margin({ top: 8 })
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding({ left: AppDimens.PADDING_LG, right: AppDimens.PADDING_LG, top: 12, bottom: 36 })
      .backgroundColor('#000000CC')
      .position({ x: 0, y: '82%' })
    }
    .width('100%')
    .height('100%')
  }
}
