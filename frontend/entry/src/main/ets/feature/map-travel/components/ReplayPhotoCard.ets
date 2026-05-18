import {
  AppDimens,
  ReplayFilterCatalog,
  ReplayFilterId,
  ReplayNode,
  ReplayStyleKit,
  ReplayStyleKitCatalog
} from '../../../common'

@Component
export struct ReplayPhotoCard {
  @Prop node: ReplayNode | null = null
  @Prop isPlaying: boolean = true
  @Prop isExpanded: boolean = false
  @Prop styleKit: ReplayStyleKit = ReplayStyleKitCatalog.getById(ReplayStyleKitCatalog.DEFAULT_ID)
  @Prop filterId: ReplayFilterId = ReplayFilterId.NONE
  @State currentPhotoIndex: number = 0

  onExpand?: (node: ReplayNode) => void

  showNode(node: ReplayNode): void {
    this.node = node
    this.currentPhotoIndex = 0
  }

  hide(): void {
    this.node = null
  }

  private getFilterImageOpacity(): number {
    return ReplayFilterCatalog.getById(this.filterId)
      .imageOpacity
  }

  private getFilterOverlayColor(): string {
    return ReplayFilterCatalog.getById(this.filterId)
      .overlayColor
  }

  @Builder
  private buildPhotoTile(photo: string) {
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
    .width(280)
    .height(180)
    .backgroundColor(this.styleKit.cardPhotoBackground)
  }

  @Builder
  PhotoArea() {
    if (this.node && this.node.photos.length > 0) {
      Swiper() {
        ForEach(this.node.photos, (photo: string) => {
          this.buildPhotoTile(photo)
        })
      }
      .width(280)
      .height(180)
      .autoPlay(false)
      .index(this.currentPhotoIndex)
      .loop(false)
      .cachedCount(2)
      .onChange((index: number) => {
        this.currentPhotoIndex = index
      })
      .indicator(
        this.node.photos.length > 1
          ? Indicator.dot()
              .itemWidth(6)
              .itemHeight(6)
              .selectedItemWidth(6)
              .selectedItemHeight(6)
              .color(this.styleKit.progressTrackColor)
              .selectedColor(this.styleKit.progressBlockColor)
          : false
      )
      .borderRadius({ topLeft: AppDimens.RADIUS_SM, topRight: AppDimens.RADIUS_SM, bottomLeft: 0, bottomRight: 0 })
    } else {
      Column() {
        Text('📷')
          .fontSize(36)
        Text('暂无照片')
          .fontSize(AppDimens.FONT_SM)
          .fontColor(this.styleKit.cardMutedColor)
          .margin({ top: 8 })
      }
      .width(280)
      .height(180)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.styleKit.cardPhotoBackground)
      .borderRadius({ topLeft: AppDimens.RADIUS_SM, topRight: AppDimens.RADIUS_SM, bottomLeft: 0, bottomRight: 0 })
    }
  }

  build() {
    if (this.node) {
      Column() {
        this.PhotoArea()

        Column() {
          Text(this.node.title)
            .fontSize(AppDimens.FONT_MD)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.styleKit.cardTitleColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (this.node.tags.length > 0) {
            Row() {
              ForEach(this.node.tags.slice(0, 3), (tag: string) => {
                Text(tag)
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(this.styleKit.cardTagTextColor)
                  .backgroundColor(this.styleKit.cardTagBackground)
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .borderRadius(12)
                  .margin({ right: 4 })
              })
            }
            .margin({ top: 6 })
          }

          if (this.node.noteShort.length > 0) {
            Text(this.node.noteShort)
              .fontSize(AppDimens.FONT_SM)
              .fontColor(this.styleKit.cardBodyColor)
              .lineHeight(18)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 8 })
          }

          if (this.node.photos.length > 0) {
            Text(`${this.node.photos.length} 张照片`)
              .fontSize(AppDimens.FONT_SM)
              .fontColor(this.styleKit.cardMutedColor)
              .margin({ top: 6 })
          }

          if (!this.isPlaying && this.node.photos.length > 1) {
            Text('左右滑动查看更多照片')
              .fontSize(AppDimens.FONT_SM)
              .fontColor(this.styleKit.cardMutedColor)
              .margin({ top: 6 })
          }
        }
        .width('100%')
        .padding(AppDimens.PADDING_MD)
        .backgroundColor(this.styleKit.cardContentBackground)
        .borderRadius({ bottomLeft: AppDimens.RADIUS_SM, bottomRight: AppDimens.RADIUS_SM })
      }
      .width(280)
      .shadow({ radius: 18, color: AppDimens.SHADOW_SOFT, offsetY: 7 })
      .border({ width: 1, color: this.styleKit.overlayPanelBorderColor })
      .onClick(() => {
        if (this.onExpand && this.node) {
          this.onExpand(this.node)
        }
      })
    }
  }
}
