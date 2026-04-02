import { router } from '@kit.ArkUI'
import { MapComponent, mapCommon, map } from '@kit.MapKit'
import { AsyncCallback } from '@kit.BasicServicesKit'
import { AppColors, AppDimens, Position } from '../../../common'
import { ReplayNode, ReplayRoute } from '../../../common'
import { ReplayPhotoCard } from '../components/ReplayPhotoCard'
import { ReplayProgressBar } from '../components/ReplayProgressBar'
import { PhotoCardOverlay } from '../components/PhotoCardOverlay'

/**
 * P07 旅程回放页 — 全屏沉浸式动画回放
 * 路由参数：{ tripId: string }
 *
 * 动画逻辑：
 * - 每个节点停留 5 秒
 * - 节点之间移动 1.5 秒
 * - 离散步进进度条，只能在节点位置停留
 */
@Entry
@Component
struct TripReplayPage {
  // 播放状态
  @State isPlaying: boolean = false
  @State currentNodeIndex: number = 0
  @State playbackSpeed: string = '1x'
  @State progress: number = 0
  @State isCardVisible: boolean = true

  // 路线数据
  @State routeName: string = '深圳三日游'
  @State replayRoute: ReplayRoute | null = null

  // UI 状态
  @State showOverlay: boolean = false
  @State overlayNode: ReplayNode | null = null

  // 速度选项
  private speeds: string[] = ['0.5x', '1x', '2x']

  // 定时器
  private playTimer: number = -1

  // 常量定义
  private readonly STAY_DURATION: number = 5000   // 5 秒停留
  private readonly MOVE_DURATION: number = 1500  // 1.5 秒移动

  // 硬编码的模拟数据（后续由 RouteGenerator 生成）
  private mockRoute: ReplayRoute = new ReplayRoute()

  // 地图配置
  private mapOptions: mapCommon.MapOptions = {
    position: {
      target: { latitude: 22.5268, longitude: 113.9455 },
      zoom: 13
    }
  }
  private mapController?: map.MapComponentController

  // 地图组件回调
  private mapCallback: AsyncCallback<map.MapComponentController> = async (err, controller) => {
    if (!err && controller) {
      this.mapController = controller
      await this.drawRouteAndMarkers()
    }
  }

  aboutToAppear(): void {
    // 初始化模拟数据
    this.mockRoute.id = 'trip_001'
    this.mockRoute.name = '深圳三日游'
    this.mockRoute.totalDistance = 128
    this.mockRoute.duration = 72
    this.mockRoute.nodes = [
      new ReplayNode(
        'node_1',
        22.5268, 113.9455,
        $r('app.media.photo_2'),
        '深圳湾公园',
        '今天来到深圳湾公园，海边的日落真美。微风拂面，海浪轻轻拍打着礁石，远处的深圳湾大桥在夕阳下闪闪发光。和好朋友一起散步、拍照，度过了一个美好的下午。',
        '深圳湾日落，海风很温柔…',
        1710504000000,
        0
      ),
      new ReplayNode(
        'node_2',
        22.5348, 113.9735,
        $r('app.media.photo_5'),
        '世界之窗',
        '世界之窗一日游！一天之内环游世界，看到了埃菲尔铁塔、金字塔、泰姬陵……每个微缩景观都做得非常精致。虽然走得有点累，但是很开心！',
        '微缩世界，一日环游…',
        1710590400000,
        1
      ),
      new ReplayNode(
        'node_3',
        22.5965, 113.9785,
        $r('app.media.photo_4'),
        '南方科技大学',
        '回到校园，春天的南科大格外美丽。荔枝花开满了枝头，图书馆前的草坪上有很多同学在读书、聊天。新学期开始了，加油！',
        '校园春色，荔枝花开…',
        1710676800000,
        2
      )
    ]

    // 加载模拟数据（后续替换为从 RDB 加载）
    this.replayRoute = this.mockRoute
    this.routeName = this.mockRoute.name
  }

  aboutToDisappear(): void {
    this.stopPlay()
  }

  /**
   * 停止播放，清理定时器
   */
  private stopPlay(): void {
    this.isPlaying = false
    if (this.playTimer !== -1) {
      clearTimeout(this.playTimer)
      this.playTimer = -1
    }
  }

  /**
   * 播放/暂停切换
   */
  private togglePlay(): void {
    if (this.isPlaying) {
      this.stopPlay()
    } else {
      this.startPlay()
    }
  }

  /**
   * 开始播放
   */
  private startPlay(): void {
    this.isPlaying = true
    this.playSequence()
  }

  /**
   * 播放序列（递归调用）
   */
  private playSequence(): void {
    if (!this.isPlaying || !this.replayRoute) {
      return
    }

    const nodeCount = this.replayRoute.nodes.length
    if (this.currentNodeIndex >= nodeCount) {
      this.isPlaying = false
      return
    }

    // 显示当前节点卡片
    this.isCardVisible = true

    // 设置定时器：5 秒后移动到下一节点
    this.playTimer = setTimeout(() => {
      if (!this.isPlaying) return

      const nextIndex = this.currentNodeIndex + 1
      if (nextIndex >= nodeCount) {
        // 播放完成
        this.isPlaying = false
        return
      }

      // 移动到下一节点
      this.moveToNode(nextIndex)

      // 递归调用，继续播放序列
      this.playSequence()
    }, this.getStayDuration())
  }

  /**
   * 获取停留时长（根据速度）
   */
  private getStayDuration(): number {
    if (this.playbackSpeed === '0.5x') {
      return this.STAY_DURATION * 2
    }
    if (this.playbackSpeed === '2x') {
      return this.STAY_DURATION / 2
    }
    return this.STAY_DURATION
  }

  /**
   * 获取移动时长（根据速度）
   */
  private getMoveDuration(): number {
    if (this.playbackSpeed === '0.5x') {
      return this.MOVE_DURATION * 2
    }
    if (this.playbackSpeed === '2x') {
      return this.MOVE_DURATION / 2
    }
    return this.MOVE_DURATION
  }

  /**
   * 绘制轨迹和节点标记
   */
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

    // 绘制轨迹折线
    await this.mapController.addPolyline({
      points: positions,
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

    // 添加节点标记
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
  }

  /**
   * 移动到指定节点
   */
  private moveToNode(index: number): void {
    if (!this.replayRoute || !this.mapController) {
      return
    }

    if (index < 0 || index >= this.replayRoute.nodes.length) {
      return
    }

    this.currentNodeIndex = index
    this.progress = (index / (this.replayRoute.nodes.length - 1)) * 100

    // 隐藏卡片（移动过程中不显示）
    this.isCardVisible = false

    // 计算相机方位角
    const prevIndex = Math.max(0, index - 1)
    const fromNode = this.replayRoute.nodes[prevIndex]
    const targetNode = this.replayRoute.nodes[index]
    const bearing = this.calculateBearing(
      fromNode.position.latitude,
      fromNode.position.longitude,
      targetNode.position.latitude,
      targetNode.position.longitude
    )

    // 相机动画移动到目标节点
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
  }

  /**
   * 计算两点之间的方位角
   */
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

  /**
   * 跳转到指定节点（通过进度条）
   */
  private jumpToNode(index: number): void {
    // 跳转时暂停播放
    this.stopPlay()
    this.moveToNode(index)
  }

  /**
   * 上一节点
   */
  private goToPrevNode(): void {
    if (this.currentNodeIndex > 0) {
      this.jumpToNode(this.currentNodeIndex - 1)
    }
  }

  /**
   * 下一节点
   */
  private goToNextNode(): void {
    if (this.replayRoute && this.currentNodeIndex < this.replayRoute.nodes.length - 1) {
      this.jumpToNode(this.currentNodeIndex + 1)
    }
  }

  /**
   * 切换播放速度
   */
  private cycleSpeed(): void {
    const currentIndex = this.speeds.indexOf(this.playbackSpeed)
    this.playbackSpeed = this.speeds[(currentIndex + 1) % this.speeds.length]
  }

  /**
   * 显示照片卡片展开覆盖层
   */
  private showOverlayCard(node: ReplayNode): void {
    this.overlayNode = node
    this.showOverlay = true
  }

  /**
   * 关闭覆盖层
   */
  private hideOverlayCard(): void {
    this.showOverlay = false
    this.overlayNode = null
  }

  build() {
    Stack() {
      // 全屏地图
      MapComponent({ mapOptions: this.mapOptions, mapCallback: this.mapCallback })
        .width('100%')
        .height('100%')

      // 照片卡片（使用新组件）
      if (this.isCardVisible && this.replayRoute && this.currentNodeIndex < this.replayRoute.nodes.length) {
        ReplayPhotoCard({
          node: this.replayRoute.nodes[this.currentNodeIndex],
          isExpanded: false,
          onExpand: (node: ReplayNode) => {
            this.showOverlayCard(node)
          }
        })
        .position({ x: '50%', y: '35%' })
        .translate({ x: -140, y: -90 })  // 居中偏移
      }

      // 底部控制栏
      Column() {
        // 进度条（使用新组件）
        ReplayProgressBar({
          value: this.progress,
          nodeCount: this.replayRoute ? this.replayRoute.nodes.length : 3,
          nodeLabels: this.replayRoute ? this.replayRoute.nodes.map(n => {
            const d = new Date(n.timestamp)
            return `${d.getMonth() + 1}.${d.getDate()}`
          }) : ['03.15', '03.16', '03.17'],
          onChange: (index: number) => {
            this.jumpToNode(index)
          }
        })
        .width('100%')

        // 控制按钮
        Row() {
          // 上一节点
          Text('◄◄')
            .fontSize(AppDimens.FONT_LG)
            .fontColor('#FFFFFF')
            .padding(AppDimens.PADDING_MD)
            .onClick(() => this.goToPrevNode())

          // 播放/暂停按钮
          Text(this.isPlaying ? '⏸' : '▶')
            .fontSize(28)
            .fontColor('#FFFFFF')
            .backgroundColor(AppColors.PRIMARY)
            .borderRadius(28)
            .width(56)
            .height(56)
            .textAlign(TextAlign.Center)
            .onClick(() => this.togglePlay())

          // 下一节点
          Text('►►')
            .fontSize(AppDimens.FONT_LG)
            .fontColor('#FFFFFF')
            .padding(AppDimens.PADDING_MD)
            .onClick(() => this.goToNextNode())

          Blank()

          // 速度切换
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

      // 照片卡片展开覆盖层
      if (this.showOverlay && this.overlayNode) {
        PhotoCardOverlay({
          isVisible: this.showOverlay,
          currentNode: this.overlayNode,
          onClose: () => {
            this.hideOverlayCard()
          }
        })
      }

      // 退出按钮 (左上角，最上层) - 放在最后确保在最上层
      Row() {
        Text('✕')
          .fontSize(AppDimens.FONT_XL)
          .fontColor('#FFFFFF')
          .backgroundColor('#00000066')
          .borderRadius(20)
          .width(40)
          .height(40)
          .textAlign(TextAlign.Center)
          .onClick(() => router.back())
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Start)
      .alignItems(VerticalAlign.Top)
      .padding({ left: 16, top: 48 })
      .zIndex(1000)
    }
    .width('100%')
    .height('100%')
  }
}
