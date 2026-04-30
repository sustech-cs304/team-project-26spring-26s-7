import { router } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { promptAction } from '@kit.ArkUI'
import { AppColors, AppDimens } from '../../../common'
import { SharePlatform, RouterParam } from '../../../common'
import { ShareService, SharePhoto } from '../services/ShareService'
import { SharePhotoHelper } from '../services/SharePhotoHelper'
import { SharePublishRequest, SharePublishNode } from '../types/ShareTypes'

/**
 * P08 分享页 — 真机联调版（v2）
 *
 * 行为：
 *   - 进入页面后自动调后端 POST /api/v1/share/publish 发布分享，
 *     成功后 shareUrl 显示真实链接；失败显示状态。
 *   - tripId 来自路由参数（从其它页面跳转过来时带上）。
 *   - 当前 demo：用打包在 resources/base/media 里的 photo_1/photo_2.jpg
 *     作为示例照片；trip 元数据是固定 demo trip。
 *     等数据层稳定后把 buildDemoTrip + stageBundledMedia 替换为
 *     从 RdbDataService 读取真实 trip + 真实照片路径即可（详见
 *     references/documents/social-share/前端接入实现说明.md）。
 *
 * 路由参数：{ tripId?: string }
 */
@Entry
@Component
export struct SharePage {
  @StorageLink('appThemeVersion') themeVersion: number = 0
  @State shareUrl: string = ''
  @State expireDays: number = 7
  @State copyText: string = ''
  @State isLoading: boolean = true
  @State errorMsg: string = ''

  private shareService: ShareService = new ShareService()
  private currentTripId: string = ''

  private sharePlatforms: SharePlatform[] = [
    new SharePlatform('💬', '微信'),
    new SharePlatform('🔴', '微博'),
    new SharePlatform('📋', '复制链接'),
  ]

  aboutToAppear(): void {
    const params = router.getParams() as RouterParam
    this.currentTripId = (params && params.tripId) ? params.tripId : 'trip_demo_001'
    this.publishShare()
  }

  /**
   * 主流程：组装请求 → 调后端 → 更新 UI
   */
  private async publishShare(): Promise<void> {
    this.isLoading = true
    this.errorMsg = ''

    try {
      const ctx = getContext(this) as common.UIAbilityContext

      // 1. 组装 trip 元数据 — demo 阶段用固定结构；接 RDB 后从 RdbDataService 取
      const trip = this.buildDemoTrip(this.currentTripId)

      // 2. 准备照片 — demo 阶段用打包资源；接 RDB 后用 SharePhotoHelper.toSharePhotos(node.photos)
      const photos: SharePhoto[] = await SharePhotoHelper.stageBundledMedia(
        ctx,
        [$r('app.media.photo_1'), $r('app.media.photo_2')],
        ['demo_photo_1.jpg', 'demo_photo_2.jpg']
      )
      // photoCount 必须等于实际照片数 — 没拿到照片就把 photoCount 清零，避免 40001
      if (photos.length === 0) {
        for (let i = 0; i < trip.nodes.length; i++) {
          trip.nodes[i].photoCount = 0
        }
      }

      // 3. 调后端
      const result = await this.shareService.publish(trip, photos, this.expireDays * 24)

      if (result.ok && result.data) {
        this.shareUrl = result.data.url
        this.copyText = `我刚分享了一段旅行：${trip.tripName}\n${result.data.url}`
        this.isLoading = false
        promptAction.showToast({ message: '分享链接已生成' })
      } else {
        this.errorMsg = `${result.errorMessage || '生成失败'}${result.errorDetail ? '\n' + result.errorDetail : ''}`
        this.isLoading = false
      }
    } catch (e) {
      this.errorMsg = `异常：${JSON.stringify(e)}`
      this.isLoading = false
    }
  }

  /**
   * Demo trip 元数据 — 后续替换为 RdbDataService.getTravelById(tripId)
   * + getNodesByTravelId(tripId) 的真实数据。
   */
  private buildDemoTrip(tripId: string): SharePublishRequest {
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
      tripId: tripId,
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
