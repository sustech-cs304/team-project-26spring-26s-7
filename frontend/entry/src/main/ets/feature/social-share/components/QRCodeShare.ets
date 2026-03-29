import { promptAction } from '@kit.ArkUI'
import { AppColors, AppDimens } from '../../../common'

/**
 * 分享数据结构
 */
interface ShareData {
  tripId: string
  tripName: string
  nodeCount: number
  coverImage?: string
}

/**
 * 二维码分享组件
 * 负责生成分享链接和二维码展示
 */
@Component
export struct QRCodeShare {
  // 输入参数
  @Prop tripId: string = ''
  @Prop tripName: string = ''
  @Prop expireHours: number = 24

  // 内部状态
  @State shareUrl: string = ''
  @State qrCodeData: string = ''
  @State isGenerating: boolean = false

  /**
   * 生成分享链接 (占位实现)
   * 后续接入分享服务：生成 HMAC-SHA256 签名链接
   */
  public async generateShareLink(): Promise<string> {
    this.isGenerating = true

    // 模拟生成延迟
    await new Promise((resolve) => setTimeout(resolve, 1000))

    // 占位返回 - 后续调用后端 API 生成真实签名链接
    const shortCode = this.generateShortCode()
    this.shareUrl = `https://travelpin.example.com/share/${shortCode}`
    this.qrCodeData = `QR_CODE_FOR_${shortCode}`

    this.isGenerating = false
    promptAction.showToast({ message: '分享链接已生成 (占位)' })

    return this.shareUrl
  }

  /**
   * 生成短码 (占位)
   */
  private generateShortCode(): string {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    let result = ''
    for (let i = 0; i < 8; i++) {
      result += chars.charAt(Math.floor(Math.random() * chars.length))
    }
    return result
  }

  /**
   * 复制到剪贴板 (占位)
   */
  public copyToClipboard(): void {
    if (this.shareUrl) {
      promptAction.showToast({ message: '链接已复制 (占位)' })
    }
  }

  build() {
    Column() {
      if (this.isGenerating) {
        LoadingProgress()
          .width(40)
          .height(40)
      } else if (this.shareUrl) {
        Column() {
          // 二维码占位
          Column() {
            Text('📱')
              .fontSize(48)
            Text('二维码生成占位')
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_HINT)
              .margin({ top: 8 })
          }
          .width(120)
          .height(120)
          .backgroundColor(AppColors.BACKGROUND)
          .borderRadius(AppDimens.RADIUS_SM)
          .justifyContent(FlexAlign.Center)

          // 分享链接
          Text(this.shareUrl)
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.PRIMARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 12 })
        }
        .width('100%')
        .padding(16)
      }
    }
    .width('100%')
  }
}
