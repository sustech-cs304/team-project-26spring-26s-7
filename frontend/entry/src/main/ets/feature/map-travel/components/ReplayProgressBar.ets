import { AppDimens, AppColors } from '../../../common'

/**
 * 离散步进进度条组件
 * 用于旅程回放，只能在节点之间跳转
 */
@Component
export struct ReplayProgressBar {
  @Prop value: number = 0          // 当前值 (0-100)
  @Prop nodeCount: number = 3      // 节点总数
  @Prop nodeLabels: string[] = []  // 节点标签（如日期）

  // 进度变化回调
  onChange?: (index: number) => void

  /**
   * 获取当前节点索引
   */
  get currentIndex(): number {
    return Math.round((this.value / 100) * (this.nodeCount - 1))
  }

  /**
   * 设置进度
   * @param index 节点索引
   */
  setProgress(index: number): void {
    if (this.nodeCount <= 1) {
      this.value = 0
      return
    }
    this.value = (index / (this.nodeCount - 1)) * 100
  }

  build() {
    Column() {
      // 节点标签行 - 显示节点序号 (1, 2, 3...)
      if (this.nodeLabels.length > 0) {
        Row() {
          ForEach(this.nodeLabels, (label: string, index: number) => {
            Text(label)
              .fontSize(AppDimens.FONT_SM)
              .fontColor('#333333')  // 黑色字体，清晰可读
              .layoutWeight(1)
              .textAlign(index === 0 ? TextAlign.Start : (index === this.nodeLabels.length - 1 ? TextAlign.End : TextAlign.Center))
          })
        }
        .width('100%')
      }

      // 进度条主体
      Row() {
        // 滑块区域
        Slider({
          value: this.value,
          min: 0,
          max: 100,
          step: this.nodeCount > 1 ? 100 / (this.nodeCount - 1) : 1
        })
          .layoutWeight(1)
          .trackColor('#FFFFFF33')
          .selectedColor('#1890FF')  // 主蓝色，更清晰
          .blockColor('#FFFFFF')     // 白色滑块
          .onChange((value: number) => {
            const index = Math.round((value / 100) * (this.nodeCount - 1))
            if (this.onChange) {
              this.onChange(index)
            }
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
  }
}
