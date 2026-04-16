import { router, promptAction } from '@kit.ArkUI'
import { AppColors, AppDimens, RouterUrls, getDataService } from '../../../common'
import { RouterParam } from '../../../common'

const DOMAIN = 0x0000
const TAG = 'NodeDetailPage'

/**
 * P04 节点详情页
 * 路由参数：{ nodeId: string }
 */
@Entry
@Component
export struct NodeDetailPage {
  @State title: string = ''
  @State poiName: string = ''
  @State date: string = ''
  @State mood: string = ''
  @State tags: string[] = []
  @State content: string = ''
  @State photos: string[] = []
  @State tripName: string = ''
  @State tripId: string = ''
  @State nodeId: string = ''
  @State isLoading: boolean = false
  @State selectedPhotoIndex: number = 0

  private dataService = getDataService()

  private bumpTravelDataVersion(): void {
    const version = (AppStorage.get('travelDataVersion') as number) || 0
    AppStorage.setOrCreate('travelDataVersion', version + 1)
  }

  aboutToAppear(): void {
    const params = router.getParams() as RouterParam
    if (params?.nodeId) {
      this.nodeId = params.nodeId
      this.loadNodeDetail()
    }
  }

  private formatDate(timestamp: number): string {
    const date = new Date(timestamp)
    const year = date.getFullYear().toString()
    const month = (date.getMonth() + 1).toString().padStart(2, '0')
    const day = date.getDate().toString().padStart(2, '0')
    return `${year}.${month}.${day}`
  }

  private getDisplayContent(): string {
    const trimmed = this.content.trim()
    return trimmed.length > 0 ? trimmed : '这条节点还没有补充正文内容。'
  }

  private async loadNodeDetail(): Promise<void> {
    if (!this.nodeId) {
      return
    }

    this.isLoading = true
    try {
      const node = await this.dataService.getNodeById(this.nodeId)
      if (!node) {
        promptAction.showToast({ message: '未找到对应记忆节点' })
        return
      }

      this.title = node.title
      this.poiName = node.poiName
      this.date = this.formatDate(node.createdAt)
      this.mood = node.mood
      this.tags = node.tags
      this.content = node.content
      this.photos = node.photos
      this.selectedPhotoIndex = 0
      this.tripId = node.travelId

      const trip = await this.dataService.getTravelById(node.travelId)
      this.tripName = trip ? trip.name : ''
    } catch (_) {
      promptAction.showToast({ message: '加载节点详情失败' })
    } finally {
      this.isLoading = false
    }
  }

  private async deleteCurrentNode(): Promise<void> {
    if (!this.nodeId) {
      return
    }
    try {
      await this.dataService.deleteNode(this.nodeId)
      this.bumpTravelDataVersion()
      promptAction.showToast({ message: '记忆节点已删除' })
      router.back()
    } catch (_) {
      promptAction.showToast({ message: '删除节点失败' })
    }
  }

  private handleDelete(): void {
    AlertDialog.show({
      title: '删除记忆',
      message: `确定要删除「${this.title}」吗？此操作不可撤销。`,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '删除',
        fontColor: AppColors.DANGER,
        action: () => {
          this.deleteCurrentNode()
        }
      }
    })
  }

  @Builder
  private buildPhotoHero() {
    Column() {
      Stack() {
        if (this.photos.length > 0) {
          Image(this.photos[this.selectedPhotoIndex])
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        } else {
          Column() {
            Text('📷')
              .fontSize(46)
            Text('这条节点还没有照片')
              .fontSize(AppDimens.FONT_MD)
              .fontColor('#E9F3FF')
              .margin({ top: 8 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#3C5C83')
        }

        Column() {
          Row() {
            Blank()
            Text(this.photos.length > 0 ? `${this.selectedPhotoIndex + 1} / ${this.photos.length}` : '暂无照片')
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.CARD_BG)
              .backgroundColor('#66000000')
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .borderRadius(14)
          }
          .width('100%')

          Blank()

          Text(this.poiName.length > 0 ? this.poiName : '未命名地点')
            .fontSize(AppDimens.FONT_MD)
            .fontColor(AppColors.CARD_BG)
            .backgroundColor('#66000000')
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .borderRadius(16)
        }
        .width('100%')
        .height('100%')
        .padding(AppDimens.PADDING_MD)
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height(280)
      .clip(true)

      if (this.photos.length > 1) {
        Row({ space: 10 }) {
          ForEach(this.photos, (photo: string, index: number) => {
            Stack() {
              Image(photo)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)
            }
            .width(68)
            .height(68)
            .borderRadius(AppDimens.RADIUS_MD)
            .clip(true)
            .border({
              width: this.selectedPhotoIndex === index ? 2 : 0,
              color: this.selectedPhotoIndex === index ? AppColors.PRIMARY : 'transparent'
            })
            .onClick(() => { this.selectedPhotoIndex = index })
          })
        }
        .width('100%')
        .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 12, bottom: 4 })
      }
    }
    .width('100%')
    .backgroundColor(AppColors.CARD_BG)
  }

  @Builder
  private buildInfoCard() {
    Column() {
      Text(this.title.length > 0 ? this.title : '未命名记忆')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.TEXT_PRIMARY)
        .width('100%')

      Row({ space: 8 }) {
        Text(`📍 ${this.poiName}`)
          .fontSize(AppDimens.FONT_SM)
          .fontColor(AppColors.TEXT_SECONDARY)
          .backgroundColor(AppColors.BACKGROUND)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(14)
        Text(this.date)
          .fontSize(AppDimens.FONT_SM)
          .fontColor(AppColors.TEXT_SECONDARY)
          .backgroundColor(AppColors.BACKGROUND)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(14)
        if (this.mood.length > 0) {
          Text(this.mood)
            .fontSize(AppDimens.FONT_SM)
            .backgroundColor('#FFF4E5')
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(14)
        }
      }
      .margin({ top: 12 })

      if (this.tags.length > 0) {
        Row({ space: 8 }) {
          ForEach(this.tags, (tag: string) => {
            Text(`#${tag}`)
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.PRIMARY)
              .backgroundColor(AppColors.PRIMARY + '12')
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .borderRadius(14)
          })
        }
        .margin({ top: 12 })
      }
    }
    .width('100%')
    .padding(AppDimens.PADDING_LG)
    .backgroundColor(AppColors.CARD_BG)
    .borderRadius(AppDimens.RADIUS_LG)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      Row() {
        Text('←')
          .fontSize(AppDimens.FONT_XL)
          .fontColor(AppColors.TEXT_PRIMARY)
          .onClick(() => router.back())
          .padding(AppDimens.PADDING_MD)
        Blank()
        Text('编辑')
          .fontSize(AppDimens.FONT_MD)
          .fontColor(AppColors.PRIMARY)
          .padding(AppDimens.PADDING_MD)
          .onClick(() => {
            router.pushUrl({
              url: RouterUrls.NODE_EDIT,
              params: { nodeId: this.nodeId } as RouterParam
            })
          })
        Text('删除')
          .fontSize(AppDimens.FONT_MD)
          .fontColor(AppColors.DANGER)
          .padding(AppDimens.PADDING_MD)
          .onClick(() => this.handleDelete())
      }
      .width('100%')
      .height(56)
      .backgroundColor(AppColors.CARD_BG)

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
          Text('正在加载节点详情...')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_HINT)
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column() {
            this.buildPhotoHero()

            Column() {
              this.buildInfoCard()

              Column() {
                Text('正文')
                  .fontSize(AppDimens.FONT_MD)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(AppColors.TEXT_PRIMARY)
                  .width('100%')
                Text(this.getDisplayContent())
                  .fontSize(AppDimens.FONT_MD)
                  .fontColor(AppColors.TEXT_PRIMARY)
                  .lineHeight(24)
                  .margin({ top: 12 })
                  .width('100%')
              }
              .width('100%')
              .padding(AppDimens.PADDING_LG)
              .margin({ top: 14 })
              .backgroundColor(AppColors.CARD_BG)
              .borderRadius(AppDimens.RADIUS_LG)
              .alignItems(HorizontalAlign.Start)

              if (this.tripName.length > 0) {
                Row() {
                  Column() {
                    Text('所属旅行')
                      .fontSize(AppDimens.FONT_SM)
                      .fontColor(AppColors.TEXT_HINT)
                    Text(this.tripName)
                      .fontSize(AppDimens.FONT_LG)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(AppColors.TEXT_PRIMARY)
                      .margin({ top: 6 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  Text('查看 Track >')
                    .fontSize(AppDimens.FONT_SM)
                    .fontColor(AppColors.PRIMARY)
                }
                .width('100%')
                .padding(AppDimens.PADDING_LG)
                .margin({ top: 14, bottom: 24 })
                .backgroundColor(AppColors.CARD_BG)
                .borderRadius(AppDimens.RADIUS_LG)
                .onClick(() => {
                  router.pushUrl({
                    url: RouterUrls.TRIP_DETAIL,
                    params: { tripId: this.tripId } as RouterParam
                  })
                })
              }
            }
            .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 16 })
          }
          .padding({ bottom: 24 })
        }
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.BACKGROUND)
  }
}
