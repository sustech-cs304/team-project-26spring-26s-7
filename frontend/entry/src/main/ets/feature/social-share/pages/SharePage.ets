import { router, promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { http } from '@kit.NetworkKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { image } from '@kit.ImageKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { fileIo as fs, fileUri } from '@kit.CoreFileKit'
import { AppColors, AppDimens, getDataService, ReplayPreferences, RouterParam, SharePlatform } from '../../../common'
import type { MemoryNode, Trip } from '../../../common'
import { ShareErrorMapper } from '../services/ShareErrorMapper'
import { SharePhoto, ShareService } from '../services/ShareService'
import { SharePhotoBatchResult, SharePhotoHelper } from '../services/SharePhotoHelper'
import { SharePreflight } from '../services/SharePreflight'
import { SystemShareService, SystemSharePayload, SystemShareImagePayload } from '../services/SystemShareService'
import {
  ReplaceLink,
  ReplayPrefsForShare,
  SharePhotoIssue,
  SharePublishNode,
  SharePublishRequest,
} from '../types/ShareTypes'

const KIND_RDB: string = 'rdb'
const KIND_DEMO: string = 'demo'
const KIND_ERROR: string = 'error'

const POSTER_DOMAIN: number = 0x0000
const POSTER_TAG: string = 'SharePoster'

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
  @State loadingMessage: string = '正在生成分享链接...'
  // 页面已被导航走（aboutToDisappear 后）时设 false。
  // 所有 await 之后的 toast / 状态更新都要 gate 一下，避免用户已经离开还弹"链接已生成"。
  private isPageActive: boolean = true
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
  // v0.5.2: 后端 v0.7.1 起返回 coverPhotoUrl，客户端做系统分享时把它
  // fetch 成 ArrayBuffer 当作 thumbnail 塞进 SharedData，让 QQ 这类不会
  // 主动抓 OG meta 的接收方也能渲染卡片。
  private coverPhotoUrl: string = ''

  private expiryOptions: ExpiryOption[] = [
    new ExpiryOption('5 分钟（测试）', 0, 5),
    new ExpiryOption('1 天', 24, 0),
    new ExpiryOption('7 天', 168, 0),
    new ExpiryOption('30 天', 720, 0),
  ]

  private sharePlatforms: SharePlatform[] = [
    new SharePlatform('W', '微信'),
    new SharePlatform('Q', 'QQ'),
    // v1.1：海报分享 — 后端合成带 QR 的图，转发给微信/QQ/微博/邮件，
    // 接收方扫码就能跳到分享链接，绕过国内对 trycloudflare 域的卡片渲染拒绝
    new SharePlatform('P', '海报'),
    new SharePlatform('C', '复制链接'),
  ]

  aboutToAppear(): void {
    this.isPageActive = true
    const params = router.getParams() as RouterParam
    if (params && params.tripId) {
      this.currentTripId = params.tripId
    }
    this.syncSelectedExpiryFromStorage()
    // v1.0.5：开始读盘加载用户的回放偏好（fire-and-forget，不阻塞 UI）。
    // publishShare 里会再 await 一次防止刚开页面立即点分享的 race。
    const ctxEarly = getContext(this) as common.UIAbilityContext
    if (ctxEarly) {
      void ReplayPreferences.ensureLoaded(ctxEarly)
    }
    void this.publishShare()
  }

  aboutToDisappear(): void {
    // 用户离开分享页（点返回 / 切走）。所有 in-flight 的 async 流程（publish、海报、分享）
    // 完成后都会先检查 isPageActive，发现是 false 就静默退出，不再 toast / 不再改状态。
    this.isPageActive = false
  }

  /** 仅当页面还在前台时弹 toast；async 完成时检查，避免"已经返回了还弹链接已生成" */
  private safeToast(message: string, duration?: number): void {
    if (!this.isPageActive) {
      return
    }
    if (duration !== undefined) {
      promptAction.showToast({ message, duration })
    } else {
      promptAction.showToast({ message })
    }
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
    this.loadingMessage = '正在生成分享链接...'
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

      // v1.0：把当前 AppStorage 里的回放偏好（用户在 ReplaySettingsSheet 调过的设置）
      // 顺路上传，让 /sreplay 页面与发布者本机的视觉风格保持一致。
      // ReplayPreferencesState 字段名 / 值都是 ArkTS enum 字符串 value，与
      // ReplayPrefsForShare wire 字段一一对应。
      // v1.0.5：兜底再 await 一次 ensureLoaded —— aboutToAppear 是 fire-and-forget，
      // "刚进 SharePage 立即点分享"那条路径可能磁盘还没读完。
      const ctxForPrefs = getContext(this) as common.UIAbilityContext
      if (ctxForPrefs) {
        await ReplayPreferences.ensureLoaded(ctxForPrefs)
      }
      const replayState = ReplayPreferences.getState()
      const replayPrefs: ReplayPrefsForShare = {
        styleKitId: replayState.styleKitId,
        bgmId: replayState.bgmId,
        filterId: replayState.filterId,
        transitionType: replayState.transitionType,
        enableBlurOverlay: replayState.enableBlurOverlay,
        enableRouteAnimation: replayState.enableRouteAnimation,
        enableRipple: replayState.enableRipple,
      }

      const result = await this.shareService.publish(
        req, photos, hours, minutes, replace, replayPrefs)
      // 用户在 publish 期间已经退出页面 → 不要弹任何 toast、也别折腾状态
      if (!this.isPageActive) {
        return
      }
      if (result.ok && result.data) {
        this.shareUrl = result.data.url
        this.copyText = `我刚分享了一段旅行：${req.tripName}\n${result.data.url}`
        this.lastLink = {
          shortCode: result.data.shortCode,
          expirySec: result.data.expiresAt,
          sig: result.data.sig,
        }
        this.coverPhotoUrl = result.data.coverPhotoUrl ? result.data.coverPhotoUrl : ''
        this.hasLastLink = true
        this.isLoading = false
        const toast = isReplacing
          ? `已替换为新链接（原链接已失效，有效期：${opt.label}）`
          : `分享链接已生成（有效期：${opt.label}）`
        this.safeToast(toast)
      } else {
        this.errorMsg = ShareErrorMapper.formatPublishResult(result)
        this.isLoading = false
      }
    } catch (e) {
      if (this.isPageActive) {
        this.errorMsg = `异常：${JSON.stringify(e)}`
        this.isLoading = false
      }
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
      if (!trip.isPublic) {
        return {
          kind: KIND_ERROR,
          message: '当前路线仍为私密，请先设为公开后再分享',
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
    if (!latest.isPublic) {
      return {
        kind: KIND_ERROR,
        message: '当前路线仍为私密，请先设为公开后再分享',
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
    if (platform === '海报') {
      await this.handleShareAsPoster()
      return
    }
    // 微信 / QQ / 其它：先尝试系统分享面板（让 OS 把 URL + 标题 + 摘要 +
    // 缩略图字节投递给目标 app）。
    //
    // 注意：实测过的情况——
    // 微信和 QQ 卡片标题/摘要直接来自 SystemSharePayload.title/description，
    //   它们**不**会回头去 scrape URL 的 og:meta。所以服务端把 og:description
    //   写得再丰富，对系统分享面板的卡片也没用，必须在这里把摘要构造好。
    // 微信用户**手动粘贴 URL** 时会回去 fetch og:meta（那条路 og:description
    //   是有用的）；这两条路要分别建好。
    const ctx = getContext(this) as common.UIAbilityContext
    const thumbnail = await this.fetchCoverThumbnail()
    const description = this.buildShareDescription()
    const payload: SystemSharePayload = {
      url: this.shareUrl,
      title: this.currentTripName
        ? `${this.currentTripName} - ItsMapPin`
        : 'ItsMapPin 分享',
      description,
      thumbnail,
    }
    const ok = await SystemShareService.share(ctx, payload)
    if (ok) {
      // 面板已打开，后面用户怎么选 / 是否取消由系统决定 —— UI 不再 toast
      return
    }
    // 系统分享不可用 → 走老的剪贴板回退路径，告诉用户去 app 里粘贴
    try {
      const text = `${this.copyText}\n${this.shareUrl}`
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
      const board = pasteboard.getSystemPasteboard()
      await board.setData(data)
      this.safeToast(`系统分享不可用，已复制内容，请前往${platform}粘贴`)
    } catch (e) {
      this.safeToast(`分享失败：${JSON.stringify(e)}`)
    }
  }

  private retry(): void {
    void this.publishShare()
  }

  /**
   * v1.1：分享海报。
   *
   * 流程：
   *   1. 拉取后端合成的 750×1334 JPG（含 QR + 封面 + 标题 + 路线预览）
   *   2. 写到 app cacheDir，得到 `file://${absPath}` URI
   *   3. systemShare with general.image UTD
   *
   * 用户在面板选微信/QQ/微博/邮件等任意 app 接收 — 都能直接看图，扫码跳回
   * /s/{code}。绕过国内对 trycloudflare 域名的链接卡片渲染拒绝。
   *
   * 任意一步失败 → toast 提示，不再走兜底（毕竟"复制链接"按钮就是兜底）。
   */
  private async handleShareAsPoster(): Promise<void> {
    if (!this.lastLink) {
      promptAction.showToast({ message: '请等链接生成后再分享海报' })
      return
    }
    const link = this.lastLink
    const ctx = getContext(this) as common.UIAbilityContext

    // 用 isLoading + 动态文案持续显示进度（toast 1.5s 会消失，看不见后续步骤）
    this.loadingMessage = '正在生成海报...'
    this.isLoading = true
    promptAction.showToast({ message: '正在生成海报…', duration: 1500 })
    hilog.info(POSTER_DOMAIN, POSTER_TAG, `step1: fetchPoster code=${link.shortCode}`)

    let bytes: Uint8Array | undefined
    try {
      bytes = await this.shareService.fetchPoster(
        link.shortCode, link.expirySec, link.sig)
    } catch (e) {
      hilog.error(POSTER_DOMAIN, POSTER_TAG, `fetchPoster threw: ${JSON.stringify(e)}`)
    }
    if (!bytes || bytes.byteLength === 0) {
      hilog.error(POSTER_DOMAIN, POSTER_TAG, `fetchPoster returned empty`)
      this.isLoading = false
      this.safeToast('海报生成失败，请检查网络后重试')
      return
    }
    // fetchPoster 期间用户已退出 → 静默放弃
    if (!this.isPageActive) {
      this.isLoading = false
      return
    }
    hilog.info(POSTER_DOMAIN, POSTER_TAG, `step2: got ${bytes.byteLength}B`)

    // 把字节写到沙箱 cacheDir
    const filePath = `${ctx.cacheDir}/poster-${link.shortCode}.jpg`
    try {
      const file = fs.openSync(
        filePath,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC
      )
      fs.writeSync(file.fd, bytes.buffer)
      fs.closeSync(file)
    } catch (e) {
      hilog.error(POSTER_DOMAIN, POSTER_TAG, `write file failed: ${JSON.stringify(e)}`)
      this.isLoading = false
      this.safeToast(`海报保存失败：${JSON.stringify(e)}`)
      return
    }
    hilog.info(POSTER_DOMAIN, POSTER_TAG, `step3: wrote to ${filePath}`)

    // Share Kit 接收方 app 需要规范的 URI，不能裸 file://${absPath}
    let shareUri = ''
    try {
      shareUri = fileUri.getUriFromPath(filePath)
    } catch (e) {
      hilog.error(POSTER_DOMAIN, POSTER_TAG, `getUriFromPath failed: ${JSON.stringify(e)}, fallback to manual file://`)
      shareUri = `file://${filePath}`
    }
    hilog.info(POSTER_DOMAIN, POSTER_TAG, `step4: uri=${shareUri}`)

    // 缩略图 ≤ 100KB，避免 IPC 超限
    const thumb = await this.shrinkBytesForIpc(bytes)
    hilog.info(POSTER_DOMAIN, POSTER_TAG, `step5: thumb=${thumb?.byteLength ?? 0}B`)

    const payload: SystemShareImagePayload = {
      fileUri: shareUri,
      title: this.currentTripName
        ? `${this.currentTripName} - ItsMapPin`
        : 'ItsMapPin 分享',
      description: this.buildShareDescription(),
      thumbnail: thumb,
    }
    hilog.info(POSTER_DOMAIN, POSTER_TAG, `step6: calling shareImage`)
    const ok = await SystemShareService.shareImage(ctx, payload)
    hilog.info(POSTER_DOMAIN, POSTER_TAG, `step7: shareImage returned ${ok}`)
    this.isLoading = false
    if (!ok) {
      this.safeToast('系统分享面板未能打开，请重试')
    }
  }

  /**
   * v1.0.3：根据 cachedReq 的 trip 数据构造分享卡片摘要。
   *
   * 微信 / QQ 系统分享面板**不**会回头读 og:meta，它就直接用
   * SystemSharePayload.description 渲染卡片副标题。所以这里得把卡片该
   * 看到的"几个节点 / 多远 / 路线 / mood"都串好。
   *
   * 输出形如：
   *   "5 节点 · 12.5km  上海外滩 → 南京西路 → 静安寺  #惬意"
   * 与后端 _build_share_description 字段顺序对齐（手动粘贴 URL 时微信
   * 走 og:meta 的那条路，看到的也是同样格式，体验一致）。
   *
   * 字段缺省的兜底：没有 cachedReq → "ItsMapPin 旅行回放"。
   */
  private buildShareDescription(): string {
    const req = this.cachedReq
    if (!req || req.nodes.length === 0) {
      return 'ItsMapPin 旅行回放'
    }
    const parts: string[] = []
    // ① 节点数 + 总距离
    const chip: string[] = []
    chip.push(`${req.nodes.length} 节点`)
    if (req.totalDistance > 0) {
      chip.push(`${req.totalDistance.toFixed(1)}km`)
    }
    parts.push(chip.join(' · '))

    // ② 路线预览：前 3 个节点 POI / title，超 8 字省略
    const names: string[] = []
    const limit = Math.min(3, req.nodes.length)
    for (let i = 0; i < limit; i++) {
      const n = req.nodes[i]
      let name = (n.poiName || n.title || '').trim()
      if (name.length === 0) continue
      if (name.length > 8) name = name.substring(0, 8) + '…'
      names.push(name)
    }
    if (names.length > 0) {
      let preview = names.join(' → ')
      if (req.nodes.length > 3) preview += ' → …'
      parts.push(preview)
    }

    // ③ 首节点 mood
    let mood = (req.nodes[0].mood || '').trim()
    if (mood.length > 6) mood = mood.substring(0, 6)
    if (mood.length > 0) {
      parts.push(`#${mood}`)
    }

    return parts.join('  ')
  }

  /**
   * 把后端返回的 coverPhotoUrl fetch 成 Uint8Array，给 systemShare 当
   * thumbnail 用（HMOS SharedRecord.thumbnail 类型是 Uint8Array，不是
   * ArrayBuffer，所以这里包一层）。任何失败都返 undefined，调用方 share
   * 时直接不带缩略图，不让分享按钮卡住。
   */
  /**
   * 把 JPEG/PNG 字节压到 ≤ 100KB 用于 systemShare 缩略图。
   * 失败或缩放后仍太大 → 返回 undefined，让面板不带缩略图。
   */
  private async shrinkBytesForIpc(input: Uint8Array): Promise<Uint8Array | undefined> {
    const MAX_BYTES = 100 * 1024
    if (input.byteLength <= MAX_BYTES) {
      return input
    }
    let source: image.ImageSource | undefined
    let pixelMap: image.PixelMap | undefined
    let packer: image.ImagePacker | undefined
    try {
      source = image.createImageSource(input.buffer)
      pixelMap = await source.createPixelMap({
        desiredSize: { width: 320, height: 320 },
      })
      packer = image.createImagePacker()
      const packed = await packer.packing(pixelMap, {
        format: 'image/jpeg',
        quality: 50,
      })
      if (packed.byteLength > MAX_BYTES) {
        return undefined
      }
      return new Uint8Array(packed)
    } catch (_) {
      return undefined
    } finally {
      try { await pixelMap?.release() } catch (_) {}
      try { await source?.release() } catch (_) {}
      try { await packer?.release() } catch (_) {}
    }
  }

  /**
   * 拉取封面并压缩成 ≤ 100KB 的 JPEG 供 systemShare 走 IPC 投递。
   *
   * 直接传原图会触发 HMOS systemShare 的 IPC 数据上限（约 200KB 实测），
   * 报 code=1003702002 "IPC data is oversized"，整个分享面板调起失败。
   *
   * 流程：HTTP 拿 cover.jpg → ImageKit 解码 → 320x320 内缩放 + JPEG quality 50
   * → 体积通常 < 30KB。任何步骤失败都返回 undefined，让 systemShare 不带缩略图
   * 调起（链接卡片由微信/QQ 回头抓 og:meta，仍能正常渲染）。
   */
  private async fetchCoverThumbnail(): Promise<Uint8Array | undefined> {
    if (!this.coverPhotoUrl) {
      return undefined
    }
    const MAX_THUMB_BYTES = 100 * 1024  // IPC 安全余量
    const httpReq = http.createHttp()
    let rawBuf: ArrayBuffer | undefined
    try {
      const resp = await httpReq.request(this.coverPhotoUrl, {
        method: http.RequestMethod.GET,
        readTimeout: 3000,
        connectTimeout: 3000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
      })
      if (resp.responseCode === 200 && resp.result instanceof ArrayBuffer) {
        rawBuf = resp.result as ArrayBuffer
      }
    } catch (e) {
      return undefined
    } finally {
      httpReq.destroy()
    }
    if (!rawBuf) {
      return undefined
    }

    // 原图已经够小：直接返回，省一次编解码
    if (rawBuf.byteLength <= MAX_THUMB_BYTES) {
      return new Uint8Array(rawBuf)
    }

    // 用 ImageKit 缩放 + 重编码到 JPEG ≤ ~30KB
    let source: image.ImageSource | undefined
    let pixelMap: image.PixelMap | undefined
    let packer: image.ImagePacker | undefined
    try {
      source = image.createImageSource(rawBuf)
      pixelMap = await source.createPixelMap({
        desiredSize: { width: 320, height: 320 },
      })
      packer = image.createImagePacker()
      const packed = await packer.packing(pixelMap, {
        format: 'image/jpeg',
        quality: 50,
      })
      if (packed.byteLength > MAX_THUMB_BYTES) {
        // 极端情况：缩放后还是太大 → 放弃缩略图
        return undefined
      }
      return new Uint8Array(packed)
    } catch (_) {
      return undefined
    } finally {
      try { await pixelMap?.release() } catch (_) {}
      try { await source?.release() } catch (_) {}
      try { await packer?.release() } catch (_) {}
    }
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
                Text(this.loadingMessage)
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
