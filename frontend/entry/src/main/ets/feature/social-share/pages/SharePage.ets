import { router } from '@kit.ArkUI'
import { AppColors, AppDimens } from '../../common'
import { ToneOption, SharePlatform, RouterParam } from '../../common'

/**
 * P08 分享页 — 生成链接 + AI 文案 + 平台选择
 * 路由参数：{ tripId: string }
 */
@Entry
@Component
struct SharePage {
  @State shareUrl: string = 'https://tp.app/s/xK9mNz'
  @State expireDays: number = 7
  @State copyText: string = ''
  @State aiGeneratedText: string = ''
  @State isGenerating: boolean = false
  @State selectedTone: string = 'poetic'

  private toneOptions: ToneOption[] = [
    new ToneOption('poetic', '诗意'),
    new ToneOption('adventurous', '探险'),
    new ToneOption('concise', '简洁'),
    new ToneOption('humorous', '幽默'),
  ]

  private sharePlatforms: SharePlatform[] = [
    new SharePlatform('💬', '微信'),
    new SharePlatform('🔴', '微博'),
    new SharePlatform('📋', '复制链接'),
  ]

  aboutToAppear(): void {
    const params = router.getParams() as RouterParam
    if (params?.tripId) {
      // TODO: 生成 HMAC-SHA256 签名链接
      // TODO: 加载旅行元数据用于 AI 文案
    }
  }

  private handleGenerateCopy(): void {
    this.isGenerating = true
    // TODO: 调用 AI Gateway，仅发送旅程元数据 (POI, 距离，时长)
    setTimeout(() => {
      this.aiGeneratedText = '三月的深圳，海风带着盐味和花香。128 公里的足迹串起五处记忆，从深圳湾的日落到南科大的春色，每一步都值得被记住。'
      this.isGenerating = false
    }, 1500)
  }

  private handleUseCopy(): void {
    this.copyText = this.aiGeneratedText
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
                // TODO: 复制到剪贴板
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
              .backgroundColor(AppColors.BACKGROUND)
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .margin({ top: 12 })
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_MD)
          .alignItems(HorizontalAlign.Start)

          // AI 辅助文案区
          Column() {
            Row() {
              Text('🤖 AI 辅助')
                .fontSize(AppDimens.FONT_MD)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppColors.TEXT_PRIMARY)
              Blank()
              Text('风格:')
                .fontSize(AppDimens.FONT_SM)
                .fontColor(AppColors.TEXT_SECONDARY)
            }
            .width('100%')

            // 风格选择
            Row({ space: 8 }) {
              ForEach(this.toneOptions, (option: ToneOption) => {
                Text(option.label)
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(this.selectedTone === option.key ? AppColors.CARD_BG : AppColors.PRIMARY)
                  .backgroundColor(this.selectedTone === option.key ? AppColors.PRIMARY : AppColors.PRIMARY + '15')
                  .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                  .borderRadius(16)
                  .onClick(() => { this.selectedTone = option.key })
              })
            }
            .margin({ top: 8 })

            // AI 生成结果
            if (this.isGenerating) {
              Row() {
                LoadingProgress()
                  .width(20)
                  .height(20)
                  .color(AppColors.PRIMARY)
                Text('AI 正在创作中...')
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(AppColors.TEXT_HINT)
                  .margin({ left: 8 })
              }
              .margin({ top: 12 })
            } else if (this.aiGeneratedText.length > 0) {
              Column() {
                Text('「' + this.aiGeneratedText + '」')
                  .fontSize(AppDimens.FONT_MD)
                  .fontColor(AppColors.TEXT_PRIMARY)
                  .fontStyle(FontStyle.Italic)
                  .lineHeight(22)
                Row({ space: 12 }) {
                  Text('采用此文案 ↑')
                    .fontSize(AppDimens.FONT_SM)
                    .fontColor(AppColors.PRIMARY)
                    .onClick(() => this.handleUseCopy())
                  Text('换一批 ↻')
                    .fontSize(AppDimens.FONT_SM)
                    .fontColor(AppColors.TEXT_SECONDARY)
                    .onClick(() => this.handleGenerateCopy())
                }
                .margin({ top: 8 })
              }
              .margin({ top: 12 })
              .padding(12)
              .backgroundColor(AppColors.BACKGROUND)
              .borderRadius(AppDimens.RADIUS_SM)
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }

            // 生成按钮
            Button(this.aiGeneratedText.length > 0 ? '重新生成' : '生成 AI 文案')
              .width('100%')
              .height(40)
              .fontSize(AppDimens.FONT_MD)
              .backgroundColor(AppColors.PRIMARY)
              .margin({ top: 12 })
              .enabled(!this.isGenerating)
              .onClick(() => this.handleGenerateCopy())
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
