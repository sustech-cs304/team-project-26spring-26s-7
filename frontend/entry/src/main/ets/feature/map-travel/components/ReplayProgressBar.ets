import { AppDimens, ReplayStyleKit, ReplayStyleKitCatalog } from '../../../common'

@Component
export struct ReplayProgressBar {
  @Prop value: number = 0
  @Prop nodeCount: number = 0
  @Prop nodeLabels: string[] = []
  @Prop styleKit: ReplayStyleKit = ReplayStyleKitCatalog.getById(ReplayStyleKitCatalog.DEFAULT_ID)

  onChange?: (index: number) => void

  build() {
    Column() {
      if (this.nodeLabels.length > 0) {
        Row() {
          ForEach(this.nodeLabels, (label: string, index: number) => {
            Text(label)
              .fontSize(AppDimens.FONT_SM)
              .fontColor(this.styleKit.progressLabelColor)
              .layoutWeight(1)
              .textAlign(index === 0 ? TextAlign.Start : (index === this.nodeLabels.length - 1 ? TextAlign.End : TextAlign.Center))
          })
        }
        .width('100%')
      }

      Row() {
        Slider({
          value: this.value,
          min: 0,
          max: 100,
          step: this.nodeCount > 1 ? 100 / (this.nodeCount - 1) : 1
        })
          .layoutWeight(1)
          .trackColor(this.styleKit.progressTrackColor)
          .selectedColor(this.styleKit.progressSelectedColor)
          .blockColor(this.styleKit.progressBlockColor)
          .onChange((value: number) => {
            const index = this.nodeCount > 1
              ? Math.round((value / 100) * (this.nodeCount - 1))
              : 0
            if (this.onChange) {
              this.onChange(index)
            }
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: 8 })
    }
    .width('100%')
  }
}
