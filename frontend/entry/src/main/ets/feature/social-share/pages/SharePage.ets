import { router, promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { AppColors, AppDimens, getDataService, RouterParam, SharePlatform } from '../../../common'
import type { MemoryNode, Trip } from '../../../common'
import { ShareErrorMapper } from '../services/ShareErrorMapper'
import { SharePhoto, ShareService } from '../services/ShareService'
import { SharePhotoBatchResult, SharePhotoHelper } from '../services/SharePhotoHelper'
import { SharePreflight } from '../services/SharePreflight'
import {
  ReplaceLink,
  SharePhotoIssue,
  SharePublishNode,
  SharePublishRequest,
} from '../types/ShareTypes'

const KIND_RDB: string = 'rdb'
const KIND_DEMO: string = 'demo'
const KIND_ERROR: string = 'error'

interface TripResolution {
  kind: string
  trip?: Trip
  nodes?: MemoryNode[]
  message?: string
}

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

@Entry
@Component
export struct SharePage {
  @StorageLink('appThemeVersion') themeVersion: number = 0
  @StorageLink('shareLinkExpiryDays') expireDays: number = 7
  @State shareUrl: string = ''
  @State copyText: string = ''
  @State isLoading: boolean = true
  @State errorMsg: string = ''
  @State currentTripName: string = ''
  @State selectedExpiryIdx: number = 2
  @State hasLastLink: boolean = false

  private shareService: ShareService = new ShareService()
  private currentTripId: string = ''
  private cachedReq: SharePublishRequest | null = null
  private cachedNodes: MemoryNode[] = []
  private useDemoPhotos: boolean = false
  private lastLink: ReplaceLink | null = null

  private expiryOptions: ExpiryOption[] = [
    new ExpiryOption('5 分钟（测试）', 0, 5),
    new ExpiryOption('1 天', 24, 0),
    new ExpiryOption('7 天', 168, 0),
    new ExpiryOption('30 天', 720, 0),
  ]

  private sharePlatforms: SharePlatform[] = [
    new SharePlatform('W', '微信'),
    new SharePlatform('B', '微博'),
    new SharePlatform('C', '复制链接'),
  ]

  aboutToAppear(): void {
    const params = router.getParams() as RouterParam
    if (params && params.tripId) {
      this.currentTripId = params.tripId
    }
    this.syncSelectedExpiryFromStorage()
    void this.publishShare()
  }

  private syncSelectedExpiryFromStorage(): void {
    if (this.expireDays === 1) {
      this.selectedExpiryIdx = 1
    } else if (this.expireDays === 30) {
      this.selectedExpiryIdx = 3
    } else {
      this.selectedExpiryIdx = 2
    }
  }

  private onPickExpiry(idx: number): void {
    if (this.isLoading || idx === this.selectedExpiryIdx) {
      return
    }
    this.selectedExpiryIdx = idx
    void this.publishShare()
  }

  private async publishShare(): Promise<void> {
    this.isLoading = true
    this.errorMsg = ''
    this.shareUrl = ''
    let photos: SharePhoto[] = []
    let preflightIssues: SharePhotoIssue[] = []

    try {
      const ctx = getContext(this) as common.UIAbilityContext
      const req = await this.ensureCachedRequest()
      if (!req) {
        this.isLoading = false
        return
      }

      if (this.useDemoPhotos) {
        photos = await SharePhotoHelper.stageBundledMedia(
          ctx,
          [$r('app.media.photo_1'), $r('app.media.photo_2')],
          ['demo_photo_1.jpg', 'demo_photo_2.jpg']
        )
        this.alignDemoPhotoCounts(req, photos.length)
      } else {
        const prepared = await this.collectPhotosAlignCount(ctx, req, this.cachedNodes)
        photos = prepared.photos
        preflightIssues = prepared.issues
      }

      const opt = this.expiryOptions[this.selectedExpiryIdx]
      const hours = opt.hours > 0 ? opt.hours : 168
      const minutes = opt.minutes > 0 ? opt.minutes : undefined
      const replace = this.lastLink !== null ? this.lastLink : undefined
      const isReplacing = replace !== undefined

      const preflight = SharePreflight.validatePublish(
        req,
        photos,
        hours,
        preflightIssues
      )
      if (!preflight.ok) {
        this.errorMsg = ShareErrorMapper.formatPreflight(preflight)
        this.isLoading = false
        return
      }

      const result = await this.shareService.publish(req, photos, hours, minutes, replace)
      if (result.ok && result.data) {
        this.shareUrl = result.data.url
        this.copyText = `我刚分享了一段旅行：${req.tripName}\n${result.data.url}`
        this.lastLink = {
          shortCode: result.data.shortCode,
          expirySec: result.data.expiresAt,
          sig: result.data.sig,
        }
        this.hasLastLink = true
        this.isLoading = false
        const toast = isReplacing
          ? `已替换为新链接（原链接已失效，有效期：${opt.label}）`
          : `分享链接已生成（有效期：${opt.label}）`
        promptAction.showToast({ message: toast })
      } else {
        this.errorMsg = ShareErrorMapper.formatPublishResult(result)
        this.isLoading = false
      }
    } catch (e) {
      this.errorMsg = `异常：${JSON.stringify(e)}`
      this.isLoading = false
    } finally {
      SharePhotoHelper.cleanupTemporaryPhotos(photos)
    }
  }

  private async ensureCachedRequest(): Promise<SharePublishRequest | null> {
    if (this.cachedReq !== null) {
      return this.cachedReq
    }

    const resolved = await this.resolveTrip()
    if (resolved.kind === KIND_ERROR) {
      this.errorMsg = resolved.message ?? '加载失败'
      return null
    }

    if (resolved.kind === KIND_RDB && resolved.trip && resolved.nodes) {
      this.cachedReq = this.buildRequestFromRdb(resolved.trip, resolved.nodes)
      this.cachedNodes = resolved.nodes
      this.useDemoPhotos = false
      this.currentTripName = resolved.trip.name
      return this.cachedReq
    }

    this.cachedReq = this.buildDemoTrip()
    this.cachedNodes = []
    this.useDemoPhotos = true
    this.currentTripName = this.cachedReq.tripName
    return this.cachedReq
  }

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
      return { kind: KIND_RDB, trip, nodes }
    }

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
    return { kind: KIND_RDB, trip: latest, nodes }
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

  private buildRequestFromRdb(trip: Trip, nodes: MemoryNode[]): SharePublishRequest {
    const reqNodes: SharePublishNode[] = []
    for (let i = 0; i < nodes.length; i++) {
      const node = nodes[i]
      reqNodes.push({
        id: node.id,
        title: node.title,
        content: node.content,
        poiName: node.poiName,
        photoCount: node.photos.length,
        mood: node.mood,
        tags: node.tags,
        visitedAt: node.visitedAt !== undefined ? node.visitedAt : node.createdAt,
        nodeOrder: node.nodeOrder !== undefined ? node.nodeOrder : i,
        latitude: node.latitude,
        longitude: node.longitude,
      })
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

  private async collectPhotosAlignCount(
    ctx: common.UIAbilityContext,
    req: SharePublishRequest,
    nodes: MemoryNode[]
  ): Promise<SharePhotoBatchResult> {
    const out: SharePhoto[] = []
    const issues: SharePhotoIssue[] = []
    for (let i = 0; i < nodes.length; i++) {
      const prepared = await SharePhotoHelper.prepareSharePhotos(ctx, nodes[i].id, nodes[i].photos)
      req.nodes[i].photoCount = prepared.photos.length
      for (let j = 0; j < prepared.photos.length; j++) {
        out.push(prepared.photos[j])
      }
      for (let j = 0; j < prepared.issues.length; j++) {
        issues.push(prepared.issues[j])
      }
    }
    return { photos: out, issues }
  }

  private alignDemoPhotoCounts(req: SharePublishRequest, photoTotal: number): void {
    let remaining = photoTotal
    for (let i = 0; i < req.nodes.length; i++) {
      if (remaining > 0) {
        req.nodes[i].photoCount = 1
        remaining--
      } else {
        req.nodes[i].photoCount = 0
      }
    }
  }

  private buildDemoTrip(): SharePublishRequest {
    const node0: SharePublishNode = {
      id: 'node_demo_001',
      title: '红树林公园',
      content: '下午到达海边步道，天气很清爽，适合散步和拍照。',
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
      content: '傍晚灯光亮起后，湖边和草坪都很适合停留。',
      poiName: '深圳人才公园',
      photoCount: 1,
      mood: '放松',
      tags: ['夜景', 'demo'],
      visitedAt: 1714300000000,
      nodeOrder: 1,
      latitude: 22.5181,
      longitude: 113.9322,
    }
    return {
      tripId: 'trip_demo_001',
      tripName: '深圳周末骑行 Demo',
      totalDistance: 12.5,
      coverIndex: 0,
      createdAt: Date.now(),
      nodes: [node0, node1],
    }
  }

  private async handleCopyLink(): Promise<void> {
    if (!this.shareUrl) {
      promptAction.showToast({ message: '链接还没有生成' })
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
      promptAction.showToast({ message: '链接还没有生成' })
      return
    }
    if (platform === '复制链接') {
      await this.handleCopyLink()
      return
    }
    try {
      const text = `${this.copyText}\n${this.shareUrl}`
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
      const board = pasteboard.getSystemPasteboard()
      await board.setData(data)
      promptAction.showToast({ message: `已复制内容，请前往${platform}粘贴` })
    } catch (e) {
      promptAction.showToast({ message: `分享失败：${JSON.stringify(e)}` })
    }
  }

  private retry(): void {
    void this.publishShare()
  }

  build() {
    Column() {
      Row() {
        Text('<')
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
          Column() {
            Text('分享链接')
              .fontSize(AppDimens.FONT_MD)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)

            Text('有效期')
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_HINT)
              .margin({ top: 12 })
            Row({ space: 8 }) {
              ForEach(this.expiryOptions, (opt: ExpiryOption, idx: number) => {
                Text(opt.label)
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(idx === this.selectedExpiryIdx ? Color.White : AppColors.TEXT_SECONDARY)
                  .backgroundColor(idx === this.selectedExpiryIdx ? AppColors.PRIMARY : AppColors.INPUT_BG)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .borderRadius(16)
                  .opacity(this.isLoading ? 0.5 : 1.0)
                  .onClick(() => this.onPickExpiry(idx))
              })
            }
            .margin({ top: 6 })

            if (this.hasLastLink) {
              Text('切换其它有效期会自动撤销当前链接')
                .fontSize(AppDimens.FONT_SM)
                .fontColor(AppColors.TEXT_HINT)
                .margin({ top: 6 })
            }

            if (this.isLoading) {
              Row() {
                LoadingProgress().width(20).height(20)
                Text('正在生成分享链接...')
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
                  .onClick(() => { void this.handleCopyLink() })
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

          Column() {
            Text('分享文案')
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
                .onClick(() => { void this.handleShare(platform.name) })
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
