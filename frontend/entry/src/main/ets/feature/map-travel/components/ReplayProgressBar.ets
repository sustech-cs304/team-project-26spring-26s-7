import { AppDimens, ReplayStyleKit, ReplayStyleKitCatalog } from '../../../common'

@Component
export struct ReplayProgressBar {
  @Prop value: number = 0
  @Prop nodeCount: number = 0
  @Prop styleKit: ReplayStyleKit = ReplayStyleKitCatalog.getById(ReplayStyleKitCatalog.DEFAULT_ID)

  onChange?: (index: number) => void

  private readonly MAX_VISIBLE_MARKERS: number = 8
  private readonly CURRENT_MARKER_SIZE: number = 12
  private readonly DEFAULT_MARKER_SIZE: number = 8
  private readonly TRACK_EDGE_INSET: number = 4

  private getCurrentIndex(): number {
    if (this.nodeCount <= 1) {
      return 0
    }
    return Math.round((this.value / 100) * (this.nodeCount - 1))
  }

  private shouldShowMarkers(): boolean {
    return this.nodeCount >= 2 && this.nodeCount <= this.MAX_VISIBLE_MARKERS
  }

  private buildMarkerIndexes(): number[] {
    const indexes: number[] = []
    for (let i = 0; i < this.nodeCount; i++) {
      indexes.push(i)
    }
    return indexes
  }

  @Builder
  private buildMarkerLayer() {
    if (this.shouldShowMarkers()) {
      Row() {
        ForEach(this.buildMarkerIndexes(), (index: number) => {
          Column()
            .width(index === this.getCurrentIndex() ? this.CURRENT_MARKER_SIZE : this.DEFAULT_MARKER_SIZE)
            .height(index === this.getCurrentIndex() ? this.CURRENT_MARKER_SIZE : this.DEFAULT_MARKER_SIZE)
            .borderRadius(index === this.getCurrentIndex()
              ? this.CURRENT_MARKER_SIZE / 2
              : this.DEFAULT_MARKER_SIZE / 2)
            .backgroundColor(index <= this.getCurrentIndex()
              ? this.styleKit.progressSelectedColor
              : this.styleKit.progressTrackColor)
        })
      }
      .width('100%')
      .padding({
        left: this.TRACK_EDGE_INSET,
        right: this.TRACK_EDGE_INSET
      })
      .justifyContent(FlexAlign.SpaceBetween)
      .hitTestBehavior(HitTestMode.None)
    }
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        Slider({
          value: this.value,
          min: 0,
          max: 100,
          step: this.nodeCount > 1 ? 100 / (this.nodeCount - 1) : 1
        })
          .width('100%')
          .trackColor(this.styleKit.progressTrackColor)
          .selectedColor(this.styleKit.progressSelectedColor)
          .blockColor(this.styleKit.progressSelectedColor)
          .blockSize({ width: 18, height: 18 })
          .trackThickness(4)
          .onChange((value: number) => {
            const index = this.nodeCount > 1
              ? Math.round((value / 100) * (this.nodeCount - 1))
              : 0
            if (this.onChange) {
              this.onChange(index)
            }
          })

        this.buildMarkerLayer()
      }
      .width('100%')
      .height(28)
      .margin({ top: 6 })
    }
    .width('100%')
    .backgroundColor(AppDimens.SURFACE_TINT)
    .backgroundBlurStyle(BlurStyle.Thin, { colorMode: ThemeColorMode.SYSTEM, adaptiveColor: AdaptiveColor.DEFAULT })
    .border({ width: 1, color: AppDimens.GLASS_BORDER })
    .borderRadius(20)
    .padding({ left: AppDimens.PADDING_SM, right: AppDimens.PADDING_SM, top: 8, bottom: 8 })
  }
}
