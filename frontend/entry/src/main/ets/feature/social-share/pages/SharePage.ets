import { router, promptAction } from '@kit.ArkUI'
import { AppColors, AppDimens } from '../../../common'
import { SharePlatform, RouterParam, getDataService, logger } from '../../../common'
import { HttpClient, ShareEndpoints } from '../../../common'

interface ShareGenerateResponseData {
  url?: string
  expiresAt?: number
  oneTime?: boolean
  accessScope?: string
}

interface ShareGenerateApiResponse {
  code?: number
  data?: ShareGenerateResponseData
  url?: string
}

/**
 * P08 分享页 — 生成链接 + 平台选择
 * 路由参数：{ tripId: string }
 */
@Entry
@Component
export struct SharePage {
  private static readonly PUBLIC_LINK_EXPIRE_DAYS: number = 7
  private static readonly PRIVATE_LINK_EXPIRE_DAYS: number = 1

  @State shareUrl: string = ''
  @State expireDays: number = 7
  @State copyText: string = ''
  @State isLoading: boolean = true
  @State tripId: string = ''
  @State tripIsPublic: boolean = false

  private dataService = getDataService()
  private httpClient = new HttpClient()

  private sharePlatforms: SharePlatform[] = [
    new SharePlatform('💬', '微信'),
    new SharePlatform('🔴', '微博'),
    new SharePlatform('📋', '复制链接'),
  ]

  aboutToAppear(): void {
    const params = router.getParams() as RouterParam
    if (params?.tripId) {
      this.tripId = params.tripId
      void this.loadTripShareInfo()
      return
    }
    this.isLoading = false
    promptAction.showToast({ message: '缺少旅行信息，无法分享' })
  }

  private handleCopyLink(): void {
    if (!this.shareUrl) {
      promptAction.showToast({ message: '分享链接尚未生成' })
      return
    }
    promptAction.showToast({ message: this.tripIsPublic ? '链接已复制' : '一次性私密链接已复制' })
  }

  private handleShare(platform: string): void {
    if (platform === '复制链接') {
      this.handleCopyLink()
      return
    }
    if (!this.shareUrl) {
      promptAction.showToast({ message: '请先生成分享链接' })
      return
    }
    promptAction.showToast({
      message: this.tripIsPublic
        ? `已准备分享到${platform}`
        : `已准备分享到${platform}（私密一次性链接）`
    })
  }

  private extractSignedUrl(response: ShareGenerateApiResponse | undefined): string {
    if (!response) {
      return ''
    }
    // 兼容两种返回结构：{ data: { url } } 与 { url }
    return response.data?.url ?? response.url ?? ''
  }

  private async loadTripShareInfo(): Promise<void> {
    this.isLoading = true
    try {
      const trip = await this.dataService.getTravelById(this.tripId)
      if (!trip) {
        promptAction.showToast({ message: '旅行不存在或无访问权限' })
        router.back()
        return
      }
      this.tripIsPublic = trip.isPublic
      this.expireDays = trip.isPublic
        ? SharePage.PUBLIC_LINK_EXPIRE_DAYS
        : SharePage.PRIVATE_LINK_EXPIRE_DAYS
      this.copyText = `和你分享我的旅行「${trip.name}」`
      await this.requestSignedShareLink()
    } catch (error) {
      logger.error('SharePage', `loadTripShareInfo failed: ${JSON.stringify(error)}`)
      promptAction.showToast({ message: '加载旅行信息失败' })
    } finally {
      this.isLoading = false
    }
  }

  private async requestSignedShareLink(): Promise<void> {
    if (!this.tripId) {
      this.shareUrl = ''
      return
    }
    const isOneTime = !this.tripIsPublic
    const scope = this.tripIsPublic ? 'public' : 'private_limited'
    const response = await this.httpClient.post<ShareGenerateApiResponse>(
      `${ShareEndpoints.GENERATE}/${this.tripId}`,
      {
        expireDays: this.expireDays,
        oneTime: isOneTime,
        accessScope: scope
      }
    )
    this.shareUrl = this.extractSignedUrl(response.data)
    if (!this.shareUrl) {
      promptAction.showToast({ message: '后端未返回有效签名链接，分享已禁用' })
    }
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
            Text(this.tripIsPublic ? '公开旅行：链接在有效期内可访问' : '私密旅行：仅生成一次性受限链接')
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_HINT)
              .margin({ top: 4 })
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
            Text('有效期：' + this.expireDays + ' 天')
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_HINT)
              .margin({ top: 4 })
            if (this.isLoading) {
              LoadingProgress()
                .width(24)
                .height(24)
                .margin({ top: 8 })
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
              .backgroundColor(AppColors.BACKGROUND)
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
