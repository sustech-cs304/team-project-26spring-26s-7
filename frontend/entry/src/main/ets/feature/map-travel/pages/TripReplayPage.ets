import { router, promptAction } from '@kit.ArkUI'
import { MapComponent, mapCommon, map } from '@kit.MapKit'
import { AsyncCallback } from '@kit.BasicServicesKit'
import { common } from '@kit.AbilityKit'
import { media } from '@kit.MediaKit'
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
  @StorageLink('appThemeVersion') themeVersion: number = 0
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
      bottom: 320  // 底部留出空间给控制栏，避免重叠（增加以避开右侧节点标签和白色播放区域）
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

  // 音频播放器
  private avPlayer: media.AVPlayer | undefined = undefined
  @State private isAudioPlaying: boolean = false

  /**
   * 初始化并播放背景音乐
   */
  private async initAndPlayMusic(): Promise<void> {
    try {
      // 使用 getUIContext().getHostContext() 获取 Context
      const uiContext = this.getUIContext()
      const context = uiContext.getHostContext() as common.UIAbilityContext

      if (!context) {
        console.error('TripReplayPage: 无法获取 UIAbilityContext')
        return
      }

      // 创建 AVPlayer 实例
      const avPlayer: media.AVPlayer = await media.createAVPlayer()
      if (!avPlayer) {
        console.error('TripReplayPage: 创建 AVPlayer 失败')
        return
      }

      // 注册回调
      this.regAVPlayerCallback(avPlayer)
      this.avPlayer = avPlayer

      // 获取 rawfile 的文件描述符
      const fileDescriptor = await context.resourceManager.getRawFd('South-East-Traveling.mp3')

      // 设置播放源（触发 initialized 状态）
      avPlayer.fdSrc = {
        fd: fileDescriptor.fd,
        offset: fileDescriptor.offset,
        length: fileDescriptor.length
      }

      console.info('TripReplayPage: 背景音乐初始化完成')
    } catch (err) {
      console.error('TripReplayPage: 播放音乐失败', JSON.stringify(err))
    }
  }

  /**
   * 注册 AVPlayer 回调
   */
  private regAVPlayerCallback(avPlayer: media.AVPlayer): void {
    // 错误回调
    avPlayer.on('error', (err) => {
      console.error('TripReplayPage: AVPlayer 错误', JSON.stringify(err))
      avPlayer.reset()
    })

    // 状态变化回调
    avPlayer.on('stateChange', (state: media.AVPlayerState) => {
      console.info('TripReplayPage: AVPlayer 状态变化', state)
      console.info('TripReplayPage: 当前 fdSrc:', JSON.stringify(avPlayer.fdSrc))

      switch (state) {
        case 'initialized':
          // 设置播放源后触发，调用 prepare
          console.info('TripReplayPage: 状态 initialized，开始 prepare')
          avPlayer.prepare()
            .then(() => {
              console.info('TripReplayPage: AVPlayer prepare 完成')
            })
            .catch(() => {
              console.error('TripReplayPage: AVPlayer prepare 失败')
            })
          break
        case 'prepared':
          // prepare 完成后可以播放
          console.info('TripReplayPage: 状态 prepared，开始 play')
          avPlayer.play()
            .then(() => {
              console.info('TripReplayPage: AVPlayer play 调用成功')
            })
            .catch(() => {
              console.error('TripReplayPage: AVPlayer play 调用失败')
            })
          break
        case 'playing':
          this.isAudioPlaying = true
          console.info('TripReplayPage: 音乐播放中')
          break
        case 'paused':
          this.isAudioPlaying = false
          console.info('TripReplayPage: 音乐暂停')
          break
        case 'completed':
          // 播放完成，重新播放（循环）
          console.info('TripReplayPage: 音乐播放完成，重新开始')
          avPlayer.seek(0)
          avPlayer.play()
          break
        case 'stopped':
          console.info('TripReplayPage: 音乐停止')
          avPlayer.reset()
          break
        case 'released':
          this.avPlayer = undefined
          this.isAudioPlaying = false
          console.info('TripReplayPage: 音乐播放器已释放')
          break
      }
    })
  }

  /**
   * 根据倍速调整音乐播放速度
   * 注：当前 SDK 版本中 AVPlayer 可能不支持 speed 属性
   */
  private async updateMusicSpeed(_speed: string): Promise<void> {
    // TODO: 待实现 - 需要找到正确的 API 来设置播放速度
    // 当前 SDK 版本中 AVPlayer 的 speed 属性可能不可用
    console.info(`TripReplayPage: 倍速调整为 ${_speed} (音乐倍速功能待实现)`)
  }

  private toggleMusic(): void {
    if (!this.avPlayer) {
      return
    }
    if (this.isAudioPlaying) {
      this.avPlayer.pause()
    } else {
      this.avPlayer.play()
    }
  }

  /**
   * 停止背景音乐
   */
  private async stopMusic(): Promise<void> {
    if (this.avPlayer) {
      try {
        await this.avPlayer.stop()
        this.avPlayer.release()
        this.avPlayer = undefined
        this.isAudioPlaying = false
        console.info('TripReplayPage: 背景音乐已停止')
      } catch (err) {
        console.error('TripReplayPage: 停止音乐失败', JSON.stringify(err))
      }
    }
  }

  aboutToAppear(): void {
    // 进入页面即播放背景音乐
    this.initAndPlayMusic()

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
    this.stopMusic()
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
  private async cycleSpeed(): Promise<void> {
    const currentIndex = this.speeds.indexOf(this.playbackSpeed)
    this.playbackSpeed = this.speeds[(currentIndex + 1) % this.speeds.length]
    // 同步调整音乐播放速度
    await this.updateMusicSpeed(this.playbackSpeed)
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
          SymbolGlyph($r('sys.symbol.figure_walk'))
            .fontSize(32)
            .fontColor([Color.White])
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

        // 控制按钮 - 播放键绝对居中，严格对称布局
        // 布局：使用 Row 一次性布局所有元素，避免负 margin 层级问题
        Row() {
          // 左侧：上一节点
          SymbolGlyph($r('sys.symbol.backward_end_fill'))
            .fontSize(22)
            .fontColor([Color.Black])
            .padding(AppDimens.PADDING_MD)
            .onClick(() => this.goToPrevNode())

          // 中间占位
          Blank()
            .layoutWeight(1)

          // 播放键
          if (this.isPlaying) {
            SymbolGlyph($r('sys.symbol.pause_fill'))
              .fontSize(28)
              .fontColor([Color.Black])
              .padding({ left: AppDimens.PADDING_SM, right: AppDimens.PADDING_SM })
              .onClick(() => this.togglePlay())
          } else {
            SymbolGlyph($r('sys.symbol.play_fill'))
              .fontSize(28)
              .fontColor([Color.Black])
              .padding({ left: AppDimens.PADDING_SM, right: AppDimens.PADDING_SM })
              .onClick(() => this.togglePlay())
          }

          // 倍速按钮
          Text(this.playbackSpeed)
            .fontSize(AppDimens.FONT_MD)
            .fontColor('#333333')  // 黑色字体
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .onClick(() => this.cycleSpeed())

          // 右侧占位
          Blank()
            .layoutWeight(1)

          // 右侧：下一节点
          SymbolGlyph($r('sys.symbol.forward_end_fill'))
            .fontSize(22)
            .fontColor([Color.Black])
            .padding(AppDimens.PADDING_MD)
            .onClick(() => this.goToNextNode())
        }
        .width('100%')
        .height(60)  // 固定高度
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding({ left: AppDimens.PADDING_LG, right: AppDimens.PADDING_LG, top: 12, bottom: 36 })
      .backgroundColor('#FFFFFF')  // 白色背景
      .position({ x: 0, y: '82%' })
      .zIndex(90)  // 设置较高的 zIndex 确保按钮可点击

      // 退出按钮 (左上角) - 使用 Stack 绝对定位
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
      .width(40)
      .height(40)
      .position({ x: 16, y: 48 })
      .zIndex(100)

      // 音乐开关按钮 (右上角)
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
