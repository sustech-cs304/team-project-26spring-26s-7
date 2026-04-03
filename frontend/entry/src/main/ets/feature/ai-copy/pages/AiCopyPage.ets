import { router, promptAction } from '@kit.ArkUI'
import { AppColors, AppDimens } from '../../../common'

/**
 * 文案风格选项接口
 */
interface StyleOption {
  value: string
  label: string
  icon: string
}

/**
 * AI 文案生成页面
 * 提供文案风格选择、长度选择、提示词输入功能
 */
@Entry
@Component
export struct AiCopyPage {
  // 页面状态
  @State selectedStyle: string = 'poetic'
  @State selectedLength: number = 100
  @State userPrompt: string = ''
  @State isGenerating: boolean = false
  @State generatedCopy: string = ''

  // 文案风格选项 (5 种)
  private styleOptions: StyleOption[] = [
    { value: 'poetic', label: '诗意盎然', icon: '🌸' },
    { value: 'factual', label: '客观纪实', icon: '📝' },
    { value: 'casual', label: '生活随笔', icon: '☕' },
    { value: 'minimal', label: '极简主义', icon: '✨' },
    { value: 'social', label: '社交媒体', icon: '📱' }
  ]

  // 文章长度选项
  private lengthOptions: number[] = [50, 100, 200]

  /**
   * 生成文案
   */
  private handleGenerate(): void {
    this.isGenerating = true

    // 模拟生成延迟 (占位实现)
    setTimeout(() => {
      this.generatedCopy = `[AI 文案生成 - 占位]\n\n风格：${this.selectedStyle}\n长度：${this.selectedLength}字\n提示词：${this.userPrompt || '无'}\n\n这是 AI 生成的文案内容占位符。后续将接入 AI Gateway API 实现真实生成。`
      this.isGenerating = false
      promptAction.showToast({ message: '文案已生成' })
    }, 1500)
  }

  /**
   * 复制文案
   */
  private handleCopy(): void {
    if (this.generatedCopy) {
      promptAction.showToast({ message: '文案已复制到剪贴板 (占位)' })
    }
  }

  build() {
    Column() {
      // 头部栏
      Row() {
        Text('←')
          .fontSize(AppDimens.FONT_XL)
          .fontColor(AppColors.TEXT_PRIMARY)
          .onClick(() => router.back())
          .padding(AppDimens.PADDING_MD)

        Text('AI 助手')
          .fontSize(AppDimens.FONT_LG)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)

        // 复制按钮 (生成后显示)
        if (this.generatedCopy) {
          Text('复制')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.PRIMARY)
            .padding(AppDimens.PADDING_MD)
            .onClick(() => this.handleCopy())
        }
      }
      .width('100%')
      .height(56)
      .backgroundColor(AppColors.CARD_BG)

      // 内容区域
      Scroll() {
        Column() {
          // 文案风格选择
          Column() {
            Text('文章风格')
              .fontSize(AppDimens.FONT_MD)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)
              .margin({ bottom: 12 })

            // 风格选项网格
            Grid() {
              ForEach(this.styleOptions, (style: StyleOption) => {
                GridItem() {
                  Column() {
                    Text(style.icon)
                      .fontSize(28)
                    Text(style.label)
                      .fontSize(AppDimens.FONT_SM)
                      .fontColor(this.selectedStyle === style.value ? AppColors.PRIMARY : AppColors.TEXT_SECONDARY)
                      .margin({ top: 4 })
                  }
                  .width('100%')
                  .height(70)
                  .justifyContent(FlexAlign.Center)
                  .backgroundColor(this.selectedStyle === style.value ? AppColors.PRIMARY + '20' : AppColors.BACKGROUND)
                  .borderRadius(AppDimens.RADIUS_SM)
                  .border({
                    width: 2,
                    color: this.selectedStyle === style.value ? AppColors.PRIMARY : 'transparent'
                  })
                  .onClick(() => { this.selectedStyle = style.value })
                }
              })
            }
            .columnsTemplate('1fr 1fr')
            .columnsGap(8)
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_SM)
          .margin({ bottom: 12 })

          // 文章长度选择
          Column() {
            Text('生成长度')
              .fontSize(AppDimens.FONT_MD)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)
              .margin({ bottom: 12 })

            Row({ space: 12 }) {
              ForEach(this.lengthOptions, (length: number) => {
                Text(`${length}字`)
                  .fontSize(AppDimens.FONT_MD)
                  .padding({ left: 20, right: 20, top: 8, bottom: 8 })
                  .backgroundColor(this.selectedLength === length ? AppColors.PRIMARY : AppColors.BACKGROUND)
                  .fontColor(this.selectedLength === length ? Color.White : AppColors.TEXT_SECONDARY)
                  .borderRadius(AppDimens.RADIUS_SM)
                  .onClick(() => { this.selectedLength = length })
              })
            }
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_SM)
          .margin({ bottom: 12 })

          // 额外提示词输入
          Column() {
            Text('额外提示词 (可选)')
              .fontSize(AppDimens.FONT_MD)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)
              .margin({ bottom: 8 })

            TextArea({
              placeholder: '在这里输入你的想法，例如：今天玩得很开心，看到了美丽的风景...',
              text: this.userPrompt
            })
              .fontSize(AppDimens.FONT_MD)
              .padding(AppDimens.PADDING_MD)
              .height(100)
              .backgroundColor(AppColors.BACKGROUND)
              .borderRadius(AppDimens.RADIUS_SM)
              .onChange((value: string) => { this.userPrompt = value })
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_SM)
          .margin({ bottom: 12 })

          // 生成按钮
          Button(this.isGenerating ? '生成中...' : '生成文案')
            .fontSize(AppDimens.FONT_LG)
            .width('100%')
            .height(50)
            .backgroundColor(AppColors.PRIMARY)
            .fontColor(Color.White)
            .enabled(!this.isGenerating)
            .onClick(() => this.handleGenerate())
            .margin({ bottom: 12 })

          // 生成结果展示
          if (this.generatedCopy) {
            Column() {
              Text('生成结果')
                .fontSize(AppDimens.FONT_MD)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppColors.TEXT_PRIMARY)
                .margin({ bottom: 8 })

              Scroll() {
                Text(this.generatedCopy)
                  .fontSize(AppDimens.FONT_MD)
                  .fontColor(AppColors.TEXT_PRIMARY)
                  .lineHeight(1.8)
              }
              .width('100%')
              .height(150)
              .padding(AppDimens.PADDING_MD)
              .backgroundColor(AppColors.BACKGROUND)
              .borderRadius(AppDimens.RADIUS_SM)
            }
            .width('100%')
            .padding(AppDimens.PADDING_MD)
            .backgroundColor(AppColors.CARD_BG)
            .borderRadius(AppDimens.RADIUS_SM)
          }
        }
        .padding(AppDimens.PADDING_MD)
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.BACKGROUND)
  }
}
