import { router } from '@kit.ArkUI'
import { AppColors, AppDimens } from '../../../common'
import { SharePlatform, RouterParam } from '../../../common'

/**
 * P08 分享页 — 生成链接 + 平台选择
 * 路由参数：{ tripId: string }
 */
@Entry
@Component
export struct SharePage {
  @StorageLink('appThemeVersion') themeVersion: number = 0
  @State shareUrl: string = 'https://tp.app/s/xK9mNz'
  @State expireDays: number = 7
  @State copyText: string = ''

  private sharePlatforms: SharePlatform[] = [
    new SharePlatform('💬', '微信'),
    new SharePlatform('🔴', '微博'),
    new SharePlatform('📋', '复制链接'),
  ]

  aboutToAppear(): void {
    const params = router.getParams() as RouterParam
    if (params?.tripId) {
      // TODO: 生成 HMAC-SHA256 签名链接
    }
  }

  private handleCopyLink(): void {
    // TODO: 复制到剪贴板
  }

  private handleShare(platform: string): void {
    // TODO: 调用系统分享能力，将 shareUrl + copyText 发送到对应平台
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
