import { AppDimens } from '../../../common'
import { ReplayNode } from '../../../common'

/**
 * 回放照片卡片组件
 * 现代简约风格，悬浮于节点上方
 * 包含：照片 + 标题 + 文字缩略（带省略号）
 */
@Component
export struct ReplayPhotoCard {
  @Prop node: ReplayNode | null = null
  @State isExpanded: boolean = false

  // 点击展开回调
  onExpand?: (node: ReplayNode) => void

  /**
   * 显示卡片
   * @param node 要展示的回放节点
   */
  showNode(node: ReplayNode): void {
    this.node = node
    this.isExpanded = false
  }

  /**
   * 隐藏卡片
   */
  hide(): void {
    this.node = null
  }

  build() {
    if (this.node) {
      Column() {
        // 照片区域
        Image(this.node.photoUri)
          .width(280)
          .height(180)
          .objectFit(ImageFit.Cover)
          .borderRadius({ topLeft: 12, topRight: 12, bottomLeft: 0, bottomRight: 0 })

        // 文字信息区域
        Column() {
          // 标题
          Text(this.node.title)
            .fontSize(AppDimens.FONT_MD)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          // 文字缩略
          Text(this.node.noteShort)
            .fontSize(AppDimens.FONT_SM)
            .fontColor('#FFFFFFCC')
            .margin({ top: 4 })
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .padding(AppDimens.PADDING_MD)
        .backgroundColor('rgba(0, 0, 0, 0.6)')
        .borderRadius({ bottomLeft: 12, bottomRight: 12 })
      }
      .width(280)
      .shadow({ radius: 12, color: '#00000060', offsetY: 8, offsetX: 0 })
      .onClick(() => {
        if (this.onExpand && this.node) {
          this.onExpand(this.node)
        }
      })
    }
  }
}
