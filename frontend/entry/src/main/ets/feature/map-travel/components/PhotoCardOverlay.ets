import { AppDimens, AppColors } from '../../../common'
import { ReplayNode } from '../../../common'

/**
 * 照片卡片展开覆盖层
 * 底部半屏模态框，展示大图和完整文字笔记
 */
@Component
export struct PhotoCardOverlay {
  @State isVisible: boolean = false
  @State currentNode: ReplayNode | null = null

  // 关闭回调
  onClose?: () => void

  /**
   * 显示覆盖层
   * @param node 要展示的回放节点
   */
  show(node: ReplayNode): void {
    this.currentNode = node
    this.isVisible = true
  }

  /**
   * 隐藏覆盖层
   */
  hide(): void {
    this.isVisible = false
    // 延迟清空数据，等待动画完成
    setTimeout(() => {
      if (!this.isVisible) {
        this.currentNode = null
      }
    }, 300)

    // 调用关闭回调
    if (this.onClose) {
      this.onClose()
    }
  }

  build() {
    if (this.isVisible && this.currentNode) {
      Stack() {
        // 半透明遮罩背景
        Blank()
          .backgroundColor('rgba(0, 0, 0, 0.5)')
          .width('100%')
          .height('100%')
          .onClick(() => this.hide())

        // 底部半屏卡片
        Column() {
          // 顶部关闭指示条
          Row() {
            Blank()
              .width(40)
              .height(4)
              .backgroundColor('#CCCCCC')
              .borderRadius(2)
          }
          .width('100%')
          .padding({ top: 12, bottom: 8 })

          // 大图展示
          Image(this.currentNode.photoUri)
            .width('100%')
            .height(250)
            .objectFit(ImageObjectFit.Cover)
            .borderRadius({ topLeft: 16, topRight: 16 })

          // 标题
          Text(this.currentNode.title)
            .fontSize(AppDimens.FONT_LG)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.TEXT_PRIMARY)
            .margin({ top: 16, bottom: 8 })
            .width('100%')

          // 完整文字笔记（可滚动）
          Scroll() {
            Text(this.currentNode.note)
              .fontSize(AppDimens.FONT_MD)
              .fontColor(AppColors.TEXT_SECONDARY)
              .lineHeight(28)
              .width('100%')
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: AppDimens.PADDING_LG, right: AppDimens.PADDING_LG, top: 8, bottom: AppDimens.PADDING_LG })

          // 时间戳
          Text(this.formatTimestamp(this.currentNode.timestamp))
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_HINT)
            .margin({ bottom: AppDimens.PADDING_MD })
        }
        .width('100%')
        .height('65%')
        .backgroundColor(AppColors.CARD_BG)
        .borderRadius({ topLeft: 20, topRight: 20 })
        .position({ x: 0, y: '35%' })
        .shadow({ radius: 16, color: '#00000040', offsetY: -4 })
      }
      .width('100%')
      .height('100%')
      .zIndex(999)
    }
  }

  /**
   * 格式化时间戳为可读格式
   */
  private formatTimestamp(timestamp: number): string {
    const date = new Date(timestamp)
    const year = date.getFullYear()
    const month = String(date.getMonth() + 1).padStart(2, '0')
    const day = String(date.getDate()).padStart(2, '0')
    const hour = String(date.getHours()).padStart(2, '0')
    return `${year}.${month}.${day} ${hour}:00`
  }
}
