import {
  AppDimens,
  ReplayFilterCatalog,
  ReplayFilterId,
  ReplayNode,
  ReplayStyleKit,
  ReplayStyleKitId,
  ReplayStyleKitCatalog
} from '../../../common'

@Component
export struct PhotoCardOverlay {
  @State isVisible: boolean = false
  @State currentNode: ReplayNode | null = null
  @Prop styleKit: ReplayStyleKit = ReplayStyleKitCatalog.getById(ReplayStyleKitCatalog.DEFAULT_ID)
  @Prop filterId: ReplayFilterId = ReplayFilterId.NONE
  @Prop useBlurOverlay: boolean = false

  onClose?: () => void

  private getFilterImageOpacity(): number {
    return ReplayFilterCatalog.getById(this.filterId)
      .imageOpacity
  }

  private getFilterOverlayColor(): string {
    return ReplayFilterCatalog.getById(this.filterId)
      .overlayColor
  }

  show(node: ReplayNode): void {
    this.currentNode = node
    this.isVisible = true
  }

  hide(): void {
    this.isVisible = false
    setTimeout(() => {
      if (!this.isVisible) {
        this.currentNode = null
      }
    }, 300)

    if (this.onClose) {
      this.onClose()
    }
  }

  @Builder
  PhotoSwiper() {
    if (this.currentNode && this.currentNode.photos.length > 0) {
      Swiper() {
        ForEach(this.currentNode.photos, (photo: string) => {
          Stack() {
            Image(photo)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Contain)
              .opacity(this.getFilterImageOpacity())

            Column()
              .width('100%')
              .height('100%')
              .backgroundColor(this.getFilterOverlayColor())
          }
          .width('100%')
          .height(250)
          .backgroundColor(this.styleKit.cardPhotoBackground)
        })
      }
      .width('100%')
      .height(250)
      .autoPlay(true)
      .interval(3000)
      .indicator(
        this.currentNode.photos.length > 1
          ? Indicator.dot()
              .itemWidth(8)
              .itemHeight(8)
              .selectedItemWidth(8)
              .selectedItemHeight(8)
              .color(this.styleKit.progressTrackColor)
              .selectedColor(this.styleKit.progressBlockColor)
          : false
      )
      .borderRadius({ topLeft: 16, topRight: 16 })
    } else {
      Column() {
        Text('📷')
          .fontSize(48)
        Text('暂无照片')
          .fontSize(AppDimens.FONT_MD)
          .fontColor(this.styleKit.cardMutedColor)
          .margin({ top: 8 })
      }
      .width('100%')
      .height(250)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.styleKit.cardPhotoBackground)
      .borderRadius({ topLeft: 16, topRight: 16 })
    }
  }

  private getOverlayBackground(): string {
    if (!this.useBlurOverlay) {
      return this.styleKit.overlayPanelBackground
    }
    if (this.styleKit.id === ReplayStyleKitCatalog.DEFAULT_ID) {
      return 'rgba(255, 255, 255, 0.82)'
    }
    if (this.styleKit.id === ReplayStyleKitId.DARK_NIGHT) {
      return 'rgba(13, 20, 32, 0.84)'
    }
    return 'rgba(249, 241, 228, 0.84)'
  }

  build() {
    if (this.isVisible && this.currentNode) {
      Stack() {
        Column() {
          Blank()
            .backgroundColor(this.styleKit.overlayMaskColor)
            .width('100%')
            .height('100%')
        }
        .width('100%')
        .height('100%')
        .onClick(() => this.hide())

        Column() {
          Row() {
            Blank()
              .width(40)
              .height(4)
              .backgroundColor(this.styleKit.controlMutedColor)
              .borderRadius(2)
          }
          .width('100%')
          .padding({ top: 12, bottom: 8 })

          this.PhotoSwiper()

          Text(this.currentNode.title)
            .fontSize(AppDimens.FONT_LG)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.styleKit.overlayTextColor)
            .width('100%')
            .margin({ top: 16, bottom: 8 })

          Row() {
            if (this.currentNode.mood) {
              Text(this.currentNode.mood)
                .fontSize(AppDimens.FONT_SM)
                .fontColor(this.styleKit.moodTextColor)
                .backgroundColor(this.styleKit.moodBackgroundColor)
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .borderRadius(12)
            }

            if (this.currentNode.tags.length > 0) {
              ForEach(this.currentNode.tags, (tag: string) => {
                Text(tag)
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(this.styleKit.cardTagTextColor)
                  .backgroundColor(this.styleKit.cardTagBackground)
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .borderRadius(12)
                  .margin({ left: 6 })
              })
            }

            Blank()

            if (this.currentNode.photos.length > 0) {
              Row({ space: 4 }) {
                Text('▧')
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(this.styleKit.overlaySecondaryTextColor)
                Text(this.currentNode.photos.length.toString())
                  .fontSize(AppDimens.FONT_SM)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.styleKit.overlaySecondaryTextColor)
              }
              .backgroundColor(this.styleKit.cardTagBackground)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .borderRadius(12)
            }
          }
          .width('100%')
          .margin({ bottom: 8 })

          Scroll() {
            Column() {
              Text(this.currentNode.note)
                .fontSize(AppDimens.FONT_MD)
                .fontColor(this.styleKit.overlaySecondaryTextColor)
                .lineHeight(28)
                .width('100%')

              Text(this.formatTimestamp(this.currentNode.timestamp))
                .fontSize(AppDimens.FONT_SM)
                .fontColor(this.styleKit.cardMutedColor)
                .margin({ top: 16 })
            }
            .width('100%')
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: AppDimens.PADDING_LG, right: AppDimens.PADDING_LG, top: 8, bottom: AppDimens.PADDING_LG })
        }
        .width('100%')
        .height('65%')
        .backgroundColor(this.getOverlayBackground())
        .border({ width: 1, color: this.styleKit.overlayPanelBorderColor })
        .borderRadius({ topLeft: 20, topRight: 20 })
        .position({ x: 0, y: '35%' })
        .shadow({ radius: 16, color: this.styleKit.shadowColor, offsetY: -4 })
      }
      .width('100%')
      .height('100%')
      .zIndex(999)
    }
  }

  private formatTimestamp(timestamp: number): string {
    const date = new Date(timestamp)
    const year = date.getFullYear()
    const month = String(date.getMonth() + 1).padStart(2, '0')
    const day = String(date.getDate()).padStart(2, '0')
    const hour = String(date.getHours()).padStart(2, '0')
    return `${year}.${month}.${day} ${hour}:00`
  }
}
