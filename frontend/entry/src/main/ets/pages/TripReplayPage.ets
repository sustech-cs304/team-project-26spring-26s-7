import { router } from '@kit.ArkUI'
import { MapComponent, mapCommon, map } from '@kit.MapKit'
import { AsyncCallback } from '@kit.BasicServicesKit'
import { AppColors, AppDimens } from '../common'
import { RouterParam } from '../common'

/**
 * P07 旅程回放页 — 全屏沉浸式动画回放
 * 路由参数: { tripId: string }
 */
@Entry
@Component
struct TripReplayPage {
  @State isPlaying: boolean = false
  @State currentNodeIndex: number = 0
  @State playbackSpeed: string = '1x'
  @State progress: number = 0
  @State currentPlace: string = '深圳湾公园'
  @State currentNote: string = '"海边的日落真美..."'

  private speeds: string[] = ['0.5x', '1x', '2x']
  private playTimer: number = -1

  // 轨迹节点（模拟数据）
  private routePoints: mapCommon.LatLng[] = [
    { latitude: 22.5268, longitude: 113.9455 },
    { latitude: 22.5348, longitude: 113.9735 },
    { latitude: 22.5965, longitude: 113.9785 },
  ]
  private nodeNames: string[] = ['深圳湾公园', '世界之窗', '南方科技大学']
  private nodeNotes: string[] = ['"海边的日落真美..."', '"微缩世界，一日环游"', '"校园春色，荔枝花开"']

  private mapOptions: mapCommon.MapOptions = {
    position: {
      target: { latitude: 22.5268, longitude: 113.9455 },
      zoom: 13
    }
  }
  private mapController?: map.MapComponentController

  private mapCallback: AsyncCallback<map.MapComponentController> = async (err, controller) => {
    if (!err && controller) {
      this.mapController = controller
      // 绘制完整轨迹折线
      await controller.addPolyline({
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
      // 添加所有节点标记
      for (const point of this.routePoints) {
        await controller.addMarker({
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
    }
  }

  aboutToAppear(): void {
    const params = router.getParams() as RouterParam
    if (params?.tripId) {
      // TODO: 从 RDB 加载真实旅行轨迹数据
    }
  }

  aboutToDisappear(): void {
    clearInterval(this.playTimer)
  }

  /** 飞到指定节点 */
  private flyToNode(index: number): void {
    if (!this.mapController || index < 0 || index >= this.routePoints.length) {
      return
    }
    this.currentNodeIndex = index
    this.currentPlace = this.nodeNames[index]
    this.currentNote = this.nodeNotes[index]
    this.progress = (index / (this.routePoints.length - 1)) * 100

    let cameraUpdate = map.newCameraPosition({
      target: this.routePoints[index],
      zoom: 15
    })
    this.mapController.animateCamera(cameraUpdate, 800)
  }

  private togglePlay(): void {
    this.isPlaying = !this.isPlaying
    if (this.isPlaying) {
      // 自动按节点步进
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
        Text('📷 ' + this.currentPlace)
          .fontSize(AppDimens.FONT_LG)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
        Text(this.currentNote)
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
          Text('03.15')
            .fontSize(AppDimens.FONT_SM)
            .fontColor('#FFFFFFCC')
          Slider({ value: this.progress, min: 0, max: 100 })
            .layoutWeight(1)
            .trackColor('#FFFFFF33')
            .selectedColor(AppColors.PRIMARY)
            .margin({ left: 8, right: 8 })
            .onChange((value: number) => {
              const index = Math.round((value / 100) * (this.routePoints.length - 1))
              this.flyToNode(index)
            })
          Text('03.17')
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
              if (this.currentNodeIndex < this.routePoints.length - 1) {
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
