import { promptAction } from '@kit.ArkUI'
import { AppColors, AppDimens } from '../../../common'

/**
 * 旅行数据结构
 */
interface TravelData {
  name: string
  nodeCount: number
}

/**
 * AI 文案生成器组件
 * 负责调用 AI Gateway API 生成文案
 */
@Component
export struct AiCopyGenerator {
  // 输入参数
  @Prop style: string = 'poetic'
  @Prop length: number = 100
  @Prop userPrompt: string = ''
  @Prop travelData?: TravelData

  // 内部状态
  @State isGenerating: boolean = false
  @State generatedText: string = ''

  /**
   * 生成文案 (占位实现)
   * 后续接入 AI Gateway API: POST /api/v1/ai/generate
   */
  public async generate(): Promise<string> {
    this.isGenerating = true

    // 模拟 API 调用延迟
    await new Promise((resolve) => setTimeout(resolve, 1500))

    // 占位返回
    this.generatedText = `[AI 文案]\n风格：${this.style}\n长度：${this.length}字\n旅行：${this.travelData?.name || '未知'}`

    this.isGenerating = false
    promptAction.showToast({ message: '文案生成成功 (占位)' })

    return this.generatedText
  }

  build() {
    Column() {
      if (this.isGenerating) {
        LoadingProgress()
          .width(40)
          .height(40)
      } else if (this.generatedText) {
        Text(this.generatedText)
          .fontSize(AppDimens.FONT_MD)
          .fontColor(AppColors.TEXT_PRIMARY)
      }
    }
    .width('100%')
    .padding(16)
  }
}
