import { router, promptAction } from '@kit.ArkUI'
import { MapComponent, mapCommon, map } from '@kit.MapKit'
import { AsyncCallback } from '@kit.BasicServicesKit'
import { AppColors, AppDimens, getDataService } from '../../../common'
import { RouterParam, ReplayNode, ReplayRoute, Position } from '../../../common'
import type { MemoryNode } from '../../../common'
import { ReplayPhotoCard } from '../components/ReplayPhotoCard'
import { ReplayProgressBar } from '../components/ReplayProgressBar'
import { PhotoCardOverlay } from '../components/PhotoCardOverlay'

const DEFAULT_REPLAY_CENTER: mapCommon.LatLng = {
  latitude: 22.55,
  longitude: 113.96
}

// 播放阶段常量
const PHASE_IDLE = 0
const PHASE_FADE_IN = 1
const PHASE_STAYING = 2
const PHASE_FADE_OUT = 3
const PHASE_MOVING = 4

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
export struct TripReplayPage {
  // 播放状态
  @State isPlaying: boolean = false
  @State currentNodeIndex: number = 0
  @State playbackSpeed: string = '1x'
  @State progress: number = 0
  @State isCardVisible: boolean = true
  @State isLoading: boolean = false
  @State cardOpacity: number = 1  // 图文卡片透明度 (0-1)

  // 路线数据
  @State routeName: string = '旅程回放'
  @State replayRoute: ReplayRoute | null = null

  // UI 状态
  @State showOverlay: boolean = false
  @State overlayNode: ReplayNode | null = null

  // 移动图标状态
  @State movingIconVisible: boolean = false
  @State movingIconScreenX: number = 0
  @State movingIconScreenY: number = 0

  // 速度选项
  private speeds: string[] = ['0.5x', '1x', '2x']

  // 定时器
  private playTimer: number = -1

  // 常量定义 - 新播放流程
  // 展示阶段：2s淡入 + 3s停留 + 1s淡出 = 6s
  // 移动阶段：1.5s
  private readonly FADE_IN_DURATION: number = 2000      // 2s 淡入
  private readonly STAY_DURATION: number = 3000         // 3s 停留
  private readonly FADE_OUT_DURATION: number = 1000     // 1s 淡出
  private readonly MOVE_DURATION: number = 1500         // 1.5s 移动

  @State private currentPhase: number = PHASE_IDLE

  // 地图配置
  private mapOptions: mapCommon.MapOptions = {
    position: {
      target: DEFAULT_REPLAY_CENTER,
      zoom: 13
    },
    padding: {  // 设置地图内边距，将缩放按钮往上移
      left: 0,
      right: 0,
      top: 0,
      bottom: 240  // 底部留出空间给控制栏，避免重叠（增加以避开右侧节点标签）
    }
  }
  private mapController?: map.MapComponentController
  private routeRendered: boolean = false
  private dataService = getDataService()

  // 地图组件回调
  private mapCallback: AsyncCallback<map.MapComponentController> = async (err, controller) => {
    if (!err && controller) {
      this.mapController = controller
      await this.drawRouteAndMarkers()
    }
  }

  aboutToAppear(): void {
    const params = router.getParams() as RouterParam
    if (params?.tripId) {
      this.loadReplayData(params.tripId)
    } else {
      // 无 tripId 时显示提示
      promptAction.showToast({ message: '缺少旅行 ID 参数' })
    }
  }

  aboutToDisappear(): void {
    this.stopPlay()
  }

  /**
   * 格式化短日期 (MM.DD)
   */
  private formatShortDate(timestamp: number): string {
    const date = new Date(timestamp)
    const month = (date.getMonth() + 1).toString().padStart(2, '0')
    const day = date.getDate().toString().padStart(2, '0')
    return `${month}.${day}`
  }

  /**
   * 从数据库加载回放数据
   */
  private async loadReplayData(tripId: string): Promise<void> {
    this.isLoading = true
    try {
      const nodes = await this.dataService.getNodesByTravelId(tripId)
      if (nodes.length === 0) {
        promptAction.showToast({ message: '当前旅行还没有可回放的节点' })
        return
      }

      // 转换 MemoryNode[] -> ReplayRoute
      this.replayRoute = this.convertToReplayRoute(nodes, tripId)
      this.routeName = `旅程回放 (${nodes.length} 个节点)`
      this.currentNodeIndex = 0
      this.progress = 0
      this.routeRendered = false

      // 更新地图中心
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
    } catch (err) {
      promptAction.showToast({ message: '加载回放数据失败' })
      console.error('loadReplayData failed:', JSON.stringify(err))
    } finally {
      this.isLoading = false
    }
  }

  /**
   * 转换 MemoryNode[] -> ReplayRoute
   * 将数据库模型转换为回放专用模型
   */
  private convertToReplayRoute(nodes: MemoryNode[], tripId: string): ReplayRoute {
    const route = new ReplayRoute()
    route.id = tripId
    route.name = '旅程回放'
    route.totalDistance = 0  // TODO: 计算总距离
    // 计算总时长：每个节点展示(淡入+停留+淡出) + 节点间移动
    // 最后一个节点不需要移动
    const nodeCount = nodes.length
    const displayTimePerNode = this.FADE_IN_DURATION + this.STAY_DURATION + this.FADE_OUT_DURATION
    const totalMoveTime = (nodeCount - 1) * this.MOVE_DURATION
    route.duration = (nodeCount * displayTimePerNode + totalMoveTime) / 1000  // 转换为秒

    route.nodes = nodes.map((node: MemoryNode, index: number): ReplayNode => {
      return new ReplayNode(
        node.id,
        node.latitude,
        node.longitude,
        node.photos,  // 直接传递照片数组
        node.title,   // 使用节点标题
        node.content || '',
        this.truncateTextSmart(node.content || node.title, 30),
        node.createdAt,
        index,
        node.mood || '',      // 心情
        node.tags || []       // 标签数组
      )
    })

    return route
  }

  /**
   * 智能截断文本
   * 优先在逗号/句号处截断，保持语句完整性
   */
  private truncateTextSmart(text: string, maxLen: number): string {
    if (!text) return ''
    if (text.length <= maxLen) return text

    // 在 maxLen 范围内查找最后一个逗号或句号
    const searchRange = text.slice(0, maxLen)
    const breakChars = ['，', '。']

    let lastBreakIndex = -1
    for (const char of breakChars) {
      const idx = searchRange.lastIndexOf(char)
      if (idx > 0) {
        lastBreakIndex = Math.max(lastBreakIndex, idx)
      }
    }

    if (lastBreakIndex > 0) {
      return text.slice(0, lastBreakIndex + 1)
    }

    // 无断点时，仍按固定长度截断
    return text.slice(0, maxLen) + '…'
  }

  /**
   * 停止播放，清理定时器
   * 暂停时立即停止动画，恢复到完全显示状态
   */
  private stopPlay(): void {
    this.isPlaying = false
    this.currentPhase = PHASE_IDLE
    if (this.playTimer !== -1) {
      clearTimeout(this.playTimer)
      this.playTimer = -1
    }
    // 暂停时恢复到完全显示
    this.cardOpacity = 1
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
    if (!this.replayRoute || this.replayRoute.nodes.length === 0) {
      return
    }
    this.isPlaying = true
    this.playSequence()
  }

  /**
   * 播放序列（阶段化：淡入→停留→淡出→移动→下一节点）
   */
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

    // 阶段 1: 淡入 (0 -> 1)
    this.currentPhase = PHASE_FADE_IN
    this.cardOpacity = 0
    this.isCardVisible = true

    animateTo({
      duration: this.getFadeInDuration(),
      curve: Curve.EaseInOut,
      onFinish: () => {
        if (!this.isPlaying) return

        // 阶段 2: 停留展示
        this.currentPhase = PHASE_STAYING
        this.cardOpacity = 1

        this.playTimer = setTimeout(() => {
          if (!this.isPlaying) return

          // 阶段 3: 淡出 (1 -> 0)
          this.currentPhase = PHASE_FADE_OUT

          animateTo({
            duration: this.getFadeOutDuration(),
            curve: Curve.EaseInOut,
            onFinish: () => {
              if (!this.isPlaying) return

              this.cardOpacity = 0
              this.isCardVisible = false

              const nextIndex = this.currentNodeIndex + 1
              if (nextIndex >= nodeCount) {
                // 播放完成
                this.isPlaying = false
                this.currentPhase = PHASE_IDLE
                return
              }

              // 阶段 4: 移动到下一节点
              this.currentPhase = PHASE_MOVING
              this.moveToNode(nextIndex)

              // 移动完成后继续下一节点的播放序列
              this.playTimer = setTimeout(() => {
                if (this.isPlaying) {
                  this.playSequence()
                }
              }, this.getMoveDuration())
            }
          }, () => {
            this.cardOpacity = 0
          })
        }, this.getStayDuration())
      }
    }, () => {
      this.cardOpacity = 1
    })
  }

  /**
   * 获取淡入时长（根据速度）
   */
  private getFadeInDuration(): number {
    if (this.playbackSpeed === '0.5x') {
      return this.FADE_IN_DURATION * 2
    }
    if (this.playbackSpeed === '2x') {
      return this.FADE_IN_DURATION / 2
    }
    return this.FADE_IN_DURATION
  }

  /**
   * 获取淡出时长（根据速度）
   */
  private getFadeOutDuration(): number {
    if (this.playbackSpeed === '0.5x') {
      return this.FADE_OUT_DURATION * 2
    }
    if (this.playbackSpeed === '2x') {
      return this.FADE_OUT_DURATION / 2
    }
    return this.FADE_OUT_DURATION
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

    // 绘制轨迹折线（柔和蓝色渐变样式）
    if (positions.length > 1) {
      await this.mapController.addPolyline({
        points: positions,
        clickable: false,
        visible: true,
        width: 4,
        zIndex: 5,
        geodesic: true,  // 大地线，更真实
        gradient: false,
        jointType: mapCommon.JointType.ROUND,
        startCap: mapCommon.CapStyle.ROUND,
        endCap: mapCommon.CapStyle.ROUND
      })
    }

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

    // 移动相机到第一个节点（完整 3D 视角动画）
    // 相机 target.latitude 向北偏移，让红色标记显示在屏幕下方（照片卡片正下方）
    // zoom=15 时，1/4 屏幕 ≈ 0.0025 纬度
    const latitudeOffset = 0.0025
    if (positions.length > 1) {
      // 计算从第一个节点到第二个节点的方位角
      const bearing = this.calculateBearing(
        positions[0].latitude, positions[0].longitude,
        positions[1].latitude, positions[1].longitude
      )
      const cameraUpdate = map.newCameraPosition({
        target: {
          latitude: positions[0].latitude + latitudeOffset,  // 向北偏移
          longitude: positions[0].longitude                   // 不变，保持 x 中轴线
        },
        zoom: 15,
        bearing: bearing,
        tilt: 45
      })
      this.mapController.animateCamera(cameraUpdate, 1000)
    } else {
      // 单节点时使用默认视角
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

  /**
   * 移动到指定节点（播放流程中使用）
   * 不控制卡片显示，仅执行地图移动
   */
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

    // 强制刷新照片卡片数据
    this.forceRefreshCard()

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

    // 启动移动图标动画（仅在非首节点时）
    if (prevIndex !== index && this.mapController) {
      this.startMovingIconAnimation(fromNode.position, targetNode.position)
    }

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

    // 移动完成后隐藏移动图标
    setTimeout(() => {
      this.movingIconVisible = false
    }, this.getMoveDuration())
  }

  /**
   * 启动移动图标动画
   * 使用定时器每隔 50ms 更新图标位置，实现平滑移动效果
   */
  private startMovingIconAnimation(fromPos: Position, toPos: Position): void {
    this.movingIconVisible = true

    // 初始化图标在起点位置
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

      // 计算当前进度 (0 -> 1)
      const progress = currentStep / steps

      // 线性插值计算当前位置
      const currentLat = fromPos.latitude + (toPos.latitude - fromPos.latitude) * progress
      const currentLng = fromPos.longitude + (toPos.longitude - fromPos.longitude) * progress

      // 获取屏幕坐标
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

  /**
   * 强制刷新照片卡片数据（通过临时清空再赋值来触发状态更新）
   */
  private forceRefreshCard(): void {
    // 通过先隐藏再显示来强制刷新组件状态
    this.isCardVisible = false
    setTimeout(() => {
      this.isCardVisible = true
    }, 50)
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
   * 手动跳转：先隐藏旧图文，移动后显示新图文，无淡入淡出动画
   */
  private jumpToNode(index: number): void {
    // 跳转时暂停播放
    this.stopPlay()

    if (!this.replayRoute || index < 0 || index >= this.replayRoute.nodes.length) {
      return
    }

    // 步骤1: 立即隐藏当前图文卡片（避免显示旧内容）
    this.isCardVisible = false

    // 步骤2: 更新节点索引和进度
    this.currentNodeIndex = index
    const lastIndex = this.replayRoute.nodes.length - 1
    this.progress = lastIndex === 0 ? 100 : (index / lastIndex) * 100
    this.currentPhase = PHASE_IDLE

    // 步骤3: 移动相机到目标节点
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

    // 步骤4: 相机移动完成后，显示新节点的图文（直接显示，无动画）
    setTimeout(() => {
      this.cardOpacity = 1  // 直接设置不透明
      this.isCardVisible = true
    }, 500)  // 等待相机移动完成
  }

  /**
   * 上一节点
   * 手动切换：直接显示，无淡入淡出动画
   */
  private goToPrevNode(): void {
    if (this.currentNodeIndex > 0) {
      this.jumpToNode(this.currentNodeIndex - 1)
    }
  }

  /**
   * 下一节点
   * 手动切换：直接显示，无淡入淡出动画
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

      // 加载中状态
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
        .backgroundColor('#00000066')
      }

      // 无数据提示
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

      // 移动图标（节点间移动时显示）
      if (this.movingIconVisible) {
        Column() {
          Text('🚶')
            .fontSize(32)
            .fontColor('#FFFFFF')
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(AppColors.PRIMARY)
        .borderRadius(22)
        .shadow({ radius: 6, color: '#1890FF80', offsetY: 2 })
        .position({ x: this.movingIconScreenX - 22, y: this.movingIconScreenY - 44 })
        .zIndex(50)
      }

      // 照片卡片（使用新组件）
      if (this.isCardVisible && this.replayRoute && this.currentNodeIndex < this.replayRoute.nodes.length) {
        ReplayPhotoCard({
          node: this.replayRoute.nodes[this.currentNodeIndex],
          isPlaying: this.isPlaying,
          isExpanded: false,
          onExpand: (node: ReplayNode) => {
            this.showOverlayCard(node)
          }
        })
        .position({ x: '50%', y: '35%' })  // x: 50% 中轴线，y: 35% 中上位置
        .translate({ x: -140, y: -90 })  // 居中偏移
        .opacity(this.cardOpacity)  // 使用透明度动画
      }

      // 底部控制栏
      Column() {
        // 进度条（使用新组件）
        ReplayProgressBar({
          value: this.progress,
          nodeCount: this.replayRoute ? this.replayRoute.nodes.length : 0,
          nodeLabels: this.replayRoute ? this.replayRoute.nodes.map((_, index) => {
            return `${index + 1}`  // 显示节点序号：1, 2, 3...
          }) : [],
          onChange: (index: number) => {
            this.jumpToNode(index)
          }
        })
        .width('100%')

        // 控制按钮 - 播放键居中
        Row() {
          // 左侧：上一节点
          Text('◄◄')
            .fontSize(AppDimens.FONT_LG)
            .fontColor('#FFFFFF')
            .padding(AppDimens.PADDING_MD)
            .onClick(() => this.goToPrevNode())

          Blank()
            .layoutWeight(1)

          // 中间：播放/暂停按钮（居中）
          Text(this.isPlaying ? '⏸' : '▶')
            .fontSize(28)
            .fontColor('#FFFFFF')
            .backgroundColor(AppColors.PRIMARY)
            .borderRadius(28)
            .width(56)
            .height(56)
            .textAlign(TextAlign.Center)
            .onClick(() => this.togglePlay())

          Blank()
            .layoutWeight(1)

          // 右侧：下一节点
          Text('►►')
            .fontSize(AppDimens.FONT_LG)
            .fontColor('#FFFFFF')
            .padding(AppDimens.PADDING_MD)
            .onClick(() => this.goToNextNode())
        }
        .width('100%')
        .margin({ top: 8 })
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Center)

        // 速度切换按钮 - 黑字白底，位于进度条上方右侧
        Row() {
          Blank()
            .layoutWeight(1)

          Text(this.playbackSpeed)
            .fontSize(AppDimens.FONT_MD)
            .fontColor('#333333')  // 黑色字体
            .backgroundColor('#FFFFFF')  // 白色背景
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(16)
            .shadow({ radius: 4, color: '#00000020', offsetY: 2 })
            .onClick(() => this.cycleSpeed())
        }
        .width('100%')
        .margin({ top: 8, bottom: -4 })
      }
      .width('100%')
      .padding({ left: AppDimens.PADDING_LG, right: AppDimens.PADDING_LG, top: 12, bottom: 36 })
      .backgroundColor('#000000CC')
      .position({ x: 0, y: '82%' })

      // 退出按钮 (左上角) - 使用 Stack 绝对定位
      Stack() {
        Text('←')
          .fontSize(AppDimens.FONT_XL)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Bold)
          .backgroundColor('rgba(0, 0, 0, 0.7)')
          .borderRadius(20)
          .width(40)
          .height(40)
          .textAlign(TextAlign.Center)
          .onClick(() => router.back())
      }
      .width(40)
      .height(40)
      .position({ x: 16, y: 48 })
      .zIndex(100)

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
    }
    .width('100%')
    .height('100%')
  }
}