import { router } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { promptAction } from '@kit.ArkUI'
import { AppColors, AppDimens, getDataService } from '../../../common'
import { SharePlatform, RouterParam } from '../../../common'
import type { Trip, MemoryNode } from '../../../common'
import { ShareService, SharePhoto } from '../services/ShareService'
import { SharePhotoHelper } from '../services/SharePhotoHelper'
import { SharePublishRequest, SharePublishNode } from '../types/ShareTypes'

/**
 * P08 分享页 — 真机联调版（v0.2，接通 RDB 真实数据）
 *
 * 行为：
 *   1. 解析 tripId：优先用路由参数；没传就取 RDB 里 createdAt 最新的那条 trip
 *   2. 用 RdbDataService 拉真 trip + nodes，按 nodeOrder 排序
 *   3. 把 MemoryNode.photos[] 里的本地沙箱路径过滤成可上传的文件列表
 *      （SharePhotoHelper.toSharePhotos 自动剥 file://、跳过云端引用、校验存在）
 *   4. 按"幸存"照片数重新对齐每个节点的 photoCount，确保后端 §4.3 校验通过
 *   5. 调 ShareService.publish 拿到签名 URL → 显示给用户复制 / 分享
 *   6. 如果 RDB 里完全没有 trip，回落到 demo 模式（用 resources/base/media/photo_*.jpg）
 *
 * 路由参数：{ tripId?: string } —— 不传也能跑（自动选最新 trip 或 demo）
 */
@Entry
@Component
export struct SharePage {
  @StorageLink('appThemeVersion') themeVersion: number = 0
  @State shareUrl: string = ''
  @State copyText: string = ''
  @State isLoading: boolean = true
  @State errorMsg: string = ''
  @State currentTripName: string = ''
  // 默认选第 2 项 = "7 天"，与 v0.3 默认行为一致
  @State selectedExpiryIdx: number = 2

  private shareService: ShareService = new ShareService()
  private currentTripId: string = ''

  /**
   * 过期时长选项 — 第一档刻意做得很短，方便联调时 5 分钟内观察
   * 链接到期 + 后端 lazy delete 触发的整个生命周期。
   * 后端 (核心约束)：MIN=60s, MAX=720h。改这里前确认后端能接住。
   */
  private expiryOptions: ExpiryOption[] = [
    new ExpiryOption('5 分钟（测试）', 0, 5),
    new ExpiryOption('1 天',          24, 0),
    new ExpiryOption('7 天',         168, 0),
    new ExpiryOption('30 天',        720, 0),
  ]

  // ---- 缓存：第一次 publish 解析出的真数据复用给"换档重传" ----
  // ArkTS 不允许 @State 持有泛型/可空类型；用 private + 配 hasCachedTrip flag。
  private cachedReq: SharePublishRequest | null = null
  private cachedPhotos: SharePhoto[] = []

  private sharePlatforms: SharePlatform[] = [
    new SharePlatform('💬', '微信'),
    new SharePlatform('🔴', '微博'),
    new SharePlatform('📋', '复制链接'),
  ]

  aboutToAppear(): void {
    const params = router.getParams() as RouterParam
    if (params && params.tripId) {
      this.currentTripId = params.tripId
    }
    this.publishShare()
  }

  /** 用户切换有效期档 — 立即用新档位重新生成（同一份 trip + 同一组照片） */
  private onPickExpiry(idx: number): void {
    if (this.isLoading) return
    if (idx === this.selectedExpiryIdx) return
    this.selectedExpiryIdx = idx
    this.publishShare()
  }

  /**
   * 主流程：选 trip → 组请求 → 调后端 → 更新 UI
   */
  private async publishShare(): Promise<void> {
    this.isLoading = true
    this.errorMsg = ''
    this.shareUrl = ''

    try {
      const ctx = getContext(this) as common.UIAbilityContext

      // ---- step 1: 解析 trip 数据 + 准备照片（首次：从 RDB 取；后续：复用缓存） ----
      // 切换有效期档不需要重新读 RDB / 重新 stage demo 照片，只是换 expiry
      // 重发 publish 而已。这能让 5 分钟测试模式下的"切档 → 看新链接"快很多。
      if (!this.cachedReq) {
        const resolved = await this.resolveTrip()
        if (resolved.kind === KIND_ERROR) {
          this.errorMsg = resolved.message ? resolved.message : '加载失败'
          this.isLoading = false
          return
        }

        let req: SharePublishRequest
        let photos: SharePhoto[]

        if (resolved.kind === KIND_RDB && resolved.trip && resolved.nodes) {
          // 真实 RDB 数据
          req = this.buildRequestFromRdb(resolved.trip, resolved.nodes)
          photos = this.collectPhotosAlignCount(req, resolved.nodes)
          this.currentTripName = resolved.trip.name
        } else {
          // RDB 空 → demo
          req = this.buildDemoTrip()
          photos = await SharePhotoHelper.stageBundledMedia(
            ctx,
            [$r('app.media.photo_1'), $r('app.media.photo_2')],
            ['demo_photo_1.jpg', 'demo_photo_2.jpg']
          )
          // 没拿到照片就把 photoCount 全部清零，避免后端 §4.3 校验失败
          if (photos.length === 0) {
            for (let i = 0; i < req.nodes.length; i++) {
              req.nodes[i].photoCount = 0
            }
          }
          this.currentTripName = req.tripName
        }

        this.cachedReq = req
        this.cachedPhotos = photos
      }

      // ---- step 2: 用当前选中的有效期档调后端 ----
      const opt = this.expiryOptions[this.selectedExpiryIdx]
      const hours = opt.hours > 0 ? opt.hours : 168
      const minutes = opt.minutes > 0 ? opt.minutes : undefined

      const result = await this.shareService.publish(
        this.cachedReq, this.cachedPhotos, hours, minutes
      )

      if (result.ok && result.data) {
        this.shareUrl = result.data.url
        this.copyText = `我刚分享了一段旅行：${this.cachedReq.tripName}\n${result.data.url}`
        this.isLoading = false
        promptAction.showToast({
          message: `分享链接已生成（有效期：${opt.label}）`
        })
      } else {
        this.errorMsg = (result.errorMessage || '生成失败') +
          (result.errorDetail ? '\n' + result.errorDetail : '')
        this.isLoading = false
      }
    } catch (e) {
      this.errorMsg = `异常：${JSON.stringify(e)}`
      this.isLoading = false
    }
  }

  /**
   * 决定要分享哪个 trip：
   *   - 路由参数有 tripId  → 必须能在 RDB 中查到，否则 error
   *   - 路由参数没有 tripId → 取 RDB 里 createdAt 最新的那条
   *   - RDB 是空的           → 走 demo
   */
  private async resolveTrip(): Promise<TripResolution> {
    const ds = getDataService()

    if (this.currentTripId) {
      const trip = await ds.getTravelById(this.currentTripId)
      if (!trip) {
        return {
          kind: KIND_ERROR,
          message: `路线 ${this.currentTripId} 不存在`,
        }
      }
      const nodes = await this.loadAndSortNodes(this.currentTripId)
      return { kind: KIND_RDB, trip: trip, nodes: nodes }
    }

    // 没传 tripId：拉所有 trip 取最新
    const allTrips = await ds.getAllTravels()
    if (allTrips.length === 0) {
      return { kind: KIND_DEMO }
    }
    let latest: Trip = allTrips[0]
    for (let i = 1; i < allTrips.length; i++) {
      if (allTrips[i].createdAt > latest.createdAt) {
        latest = allTrips[i]
      }
    }
    this.currentTripId = latest.id
    const nodes = await this.loadAndSortNodes(latest.id)
    return { kind: KIND_RDB, trip: latest, nodes: nodes }
  }

  private async loadAndSortNodes(tripId: string): Promise<MemoryNode[]> {
    const ds = getDataService()
    const nodes = await ds.getNodesByTravelId(tripId)
    nodes.sort((a: MemoryNode, b: MemoryNode) => {
      const ao = a.nodeOrder !== undefined ? a.nodeOrder : 0
      const bo = b.nodeOrder !== undefined ? b.nodeOrder : 0
      return ao - bo
    })
    return nodes
  }

  /**
   * 把 RDB 的 Trip + MemoryNode[] 转成 P08 API 规范 §4.2 的 SharePublishRequest。
   * photoCount 这里先填实际数组长度，下一步 collectPhotosAlignCount 会按"幸存"
   * 文件数把它修正到准确值。
   */
  private buildRequestFromRdb(trip: Trip, nodes: MemoryNode[]): SharePublishRequest {
    const reqNodes: SharePublishNode[] = []
    for (let i = 0; i < nodes.length; i++) {
      const n = nodes[i]
      const reqNode: SharePublishNode = {
        id: n.id,
        title: n.title,
        content: n.content,
        poiName: n.poiName,
        photoCount: n.photos.length,
        mood: n.mood,
        tags: n.tags,
        visitedAt: n.visitedAt !== undefined ? n.visitedAt : n.createdAt,
        nodeOrder: n.nodeOrder !== undefined ? n.nodeOrder : i,
        latitude: n.latitude,
        longitude: n.longitude,
      }
      reqNodes.push(reqNode)
    }
    return {
      tripId: trip.id,
      tripName: trip.name,
      totalDistance: trip.totalDistance,
      coverIndex: 0,
      createdAt: trip.createdAt,
      nodes: reqNodes,
    }
  }

  /**
   * 扫一遍所有节点的 photos[]，把可上传文件挑出来，并把 req.nodes[i].photoCount
   * 改成"幸存"数（云端引用 / 不存在文件会被剔除）。这样 sum(photoCount) 一定等于
   * 实际上传的 photo_N 数量，后端不会报 INVALID_PHOTO_COUNT。
   */
  private collectPhotosAlignCount(
    req: SharePublishRequest,
    nodes: MemoryNode[]
  ): SharePhoto[] {
    const out: SharePhoto[] = []
    for (let i = 0; i < nodes.length; i++) {
      const survived = SharePhotoHelper.toSharePhotos(nodes[i].photos)
      req.nodes[i].photoCount = survived.length
      for (let j = 0; j < survived.length; j++) {
        out.push(survived[j])
      }
    }
    return out
  }

  /**
   * Demo trip — RDB 是空的时候用，配合 SharePhotoHelper.stageBundledMedia
   * 把 resources/base/media/photo_1.jpg / photo_2.jpg 拷到沙箱再上传。
   */
  private buildDemoTrip(): SharePublishRequest {
    const node0: SharePublishNode = {
      id: 'node_demo_001',
      title: '红树林公园',
      content: '下午三点到达，阳光正好，远远看见白鹭栖息。',
      poiName: '深圳湾红树林',
      photoCount: 1,
      mood: '惬意',
      tags: ['骑行', '日落', 'demo'],
      visitedAt: 1714200000000,
      nodeOrder: 0,
      latitude: 22.5231,
      longitude: 113.9432,
    }
    const node1: SharePublishNode = {
      id: 'node_demo_002',
      title: '人才公园',
      content: '傍晚的灯光很美，市民在草坪上放风筝。',
      poiName: '深圳人才公园',
      photoCount: 1,
      mood: '感动',
      tags: ['夜景', 'demo'],
      visitedAt: 1714300000000,
      nodeOrder: 1,
      latitude: 22.5181,
      longitude: 113.9322,
    }
    return {
      tripId: 'trip_demo_001',
      tripName: '深圳湾周末骑行 · Demo',
      totalDistance: 12.5,
      coverIndex: 0,
      createdAt: Date.now(),
      nodes: [node0, node1],
    }
  }

  private async handleCopyLink(): Promise<void> {
    if (!this.shareUrl) {
      promptAction.showToast({ message: '链接还没生成好' })
      return
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.shareUrl)
      const board = pasteboard.getSystemPasteboard()
      await board.setData(data)
      promptAction.showToast({ message: '链接已复制' })
    } catch (e) {
      promptAction.showToast({ message: `复制失败：${JSON.stringify(e)}` })
    }
  }

  private async handleShare(platform: string): Promise<void> {
    if (!this.shareUrl) {
      promptAction.showToast({ message: '链接还没生成好' })
      return
    }
    if (platform === '复制链接') {
      await this.handleCopyLink()
      return
    }
    // 微信 / 微博：暂时也走复制 + 文案，到端口能接 systemShare 后再换
    try {
      const text = `${this.copyText}\n${this.shareUrl}`
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
      const board = pasteboard.getSystemPasteboard()
      await board.setData(data)
      promptAction.showToast({ message: `已复制，前往${platform}粘贴` })
    } catch (e) {
      promptAction.showToast({ message: `分享失败：${JSON.stringify(e)}` })
    }
  }

  private retry(): void {
    this.publishShare()
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Text('←')
          .fontSize(AppDimens.FONT_XL)
          .fontColor(AppColors.TEXT_PRIMARY)
          .onClick(() => router.back())
          .padding(AppDimens.PADDING_MD)
        Text('分享旅行')
          .fontSize(AppDimens.FONT_LG)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .backgroundColor(AppColors.CARD_BG)

      Scroll() {
        Column() {
          // 分享链接区域
          Column() {
            Text('🔗 分享链接')
              .fontSize(AppDimens.FONT_MD)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)

            // —— 有效期选择器（4 档，第一档为短测试档） ——
            Text('有效期')
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_HINT)
              .margin({ top: 12 })
            Row({ space: 8 }) {
              ForEach(this.expiryOptions, (opt: ExpiryOption, idx: number) => {
                Text(opt.label)
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(idx === this.selectedExpiryIdx
                             ? Color.White
                             : AppColors.TEXT_SECONDARY)
                  .backgroundColor(idx === this.selectedExpiryIdx
                                   ? AppColors.PRIMARY
                                   : AppColors.INPUT_BG)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .borderRadius(16)
                  .opacity(this.isLoading ? 0.5 : 1.0)
                  .onClick(() => this.onPickExpiry(idx))
              })
            }
            .margin({ top: 6 })

            if (this.isLoading) {
              Row() {
                LoadingProgress().width(20).height(20)
                Text('正在生成签名链接…')
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(AppColors.TEXT_HINT)
                  .margin({ left: 8 })
              }
              .margin({ top: 12 })
            } else if (this.errorMsg) {
              Text(this.errorMsg)
                .fontSize(AppDimens.FONT_SM)
                .fontColor(Color.Red)
                .margin({ top: 8 })
              Text('点击重试')
                .fontSize(AppDimens.FONT_SM)
                .fontColor(AppColors.PRIMARY)
                .margin({ top: 6 })
                .onClick(() => this.retry())
            } else {
              if (this.currentTripName) {
                Text(this.currentTripName)
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(AppColors.TEXT_SECONDARY)
                  .margin({ top: 12 })
              }
              Row() {
                Text(this.shareUrl)
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(AppColors.PRIMARY)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text('复制')
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(AppColors.PRIMARY)
                  .padding({ left: 12 })
                  .onClick(() => this.handleCopyLink())
              }
              .margin({ top: 8 })
              Text('当前有效期：' + this.expiryOptions[this.selectedExpiryIdx].label)
                .fontSize(AppDimens.FONT_SM)
                .fontColor(AppColors.TEXT_HINT)
                .margin({ top: 4 })
            }
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_MD)
          .alignItems(HorizontalAlign.Start)

          // 文案编辑区
          Column() {
            Text('✏️ 分享文案')
              .fontSize(AppDimens.FONT_MD)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)
            TextArea({ placeholder: '写点什么分享给朋友...', text: this.copyText })
              .onChange((value: string) => { this.copyText = value })
              .height(100)
              .margin({ top: 8 })
              .fontColor(AppColors.INPUT_TEXT)
              .placeholderColor(AppColors.INPUT_PLACEHOLDER)
              .caretColor(AppColors.INPUT_CARET)
              .backgroundColor(AppColors.INPUT_BG)
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .margin({ top: 12 })
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_MD)
          .alignItems(HorizontalAlign.Start)

          // 分享平台
          Column() {
            Text('分享到')
              .fontSize(AppDimens.FONT_MD)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)
            Row({ space: 24 }) {
              ForEach(this.sharePlatforms, (platform: SharePlatform) => {
                Column() {
                  Text(platform.icon)
                    .fontSize(32)
                  Text(platform.name)
                    .fontSize(AppDimens.FONT_SM)
                    .fontColor(AppColors.TEXT_SECONDARY)
                    .margin({ top: 4 })
                }
                .onClick(() => this.handleShare(platform.name))
              })
            }
            .margin({ top: 12 })
            .justifyContent(FlexAlign.Center)
            .width('100%')
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .margin({ top: 12, bottom: 24 })
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_MD)
          .alignItems(HorizontalAlign.Start)
        }
        .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 12 })
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.BACKGROUND)
  }
}

// ---- TripResolution: 单 interface 加 kind 字段，避开 ArkTS 严格模式
// 对联合类型 / 字面量类型的限制 ----
const KIND_RDB: string = 'rdb'
const KIND_DEMO: string = 'demo'
const KIND_ERROR: string = 'error'

interface TripResolution {
  kind: string                 // KIND_RDB / KIND_DEMO / KIND_ERROR
  trip?: Trip
  nodes?: MemoryNode[]
  message?: string
}

/**
 * 有效期选项 — minutes 优先于 hours：哪个 > 0 就用哪个发往后端。
 * （hours, minutes 都 > 0 是非法配置；这里依靠选项数组的人工填写保证不会出现。）
 */
class ExpiryOption {
  label: string = ''
  hours: number = 0
  minutes: number = 0

  constructor(label: string, hours: number, minutes: number) {
    this.label = label
    this.hours = hours
    this.minutes = minutes
  }
}
