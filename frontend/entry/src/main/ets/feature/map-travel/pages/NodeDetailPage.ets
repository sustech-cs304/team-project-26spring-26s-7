import { router, promptAction } from '@kit.ArkUI'
import { AppColors, AppDimens, RouterUrls, getDataService } from '../../../common'
import { RouterParam } from '../../../common'

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

  private dataService = getDataService()

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
      this.tripId = node.travelId

      const trip = await this.dataService.getTravelById(node.travelId)
      this.tripName = trip ? trip.name : ''
    } catch (err) {
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
      promptAction.showToast({ message: '记忆节点已删除' })
      router.back()
    } catch (err) {
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

  build() {
    Column() {
      // 顶部导航栏
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

      // 内容区
      Scroll() {
        Column() {
          if (this.isLoading) {
            Column() {
              LoadingProgress()
                .width(36)
                .height(36)
            }
            .width('100%')
            .height(200)
            .justifyContent(FlexAlign.Center)
          }

          // 照片轮播区
          if (this.photos.length > 0) {
            Swiper() {
              ForEach(this.photos, (photo: string) => {
                Image(photo)
                  .width('100%')
                  .height(240)
                  .objectFit(ImageFit.Cover)
              })
            }
            .width('100%')
            .height(240)
            .autoPlay(true)
            .interval(3000)
            .indicator(
              Indicator.dot()
                .itemWidth(8)
                .itemHeight(8)
                .selectedItemWidth(8)
                .selectedItemHeight(8)
                .color(AppColors.TEXT_HINT)
                .selectedColor(AppColors.PRIMARY)
            )
          } else {
            Stack() {
              Column() {
                Text('📷')
                  .fontSize(48)
                  .fontColor(AppColors.TEXT_HINT)
                Text('暂无照片')
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(AppColors.TEXT_HINT)
              }
              .justifyContent(FlexAlign.Center)
            }
            .width('100%')
            .height(240)
            .backgroundColor(AppColors.DIVIDER)
          }

          // 基本信息
          Column() {
            Text(this.title)
              .fontSize(AppDimens.FONT_XL)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.TEXT_PRIMARY)

            Row() {
              Text(`📍 ${this.poiName}`)
                .fontSize(AppDimens.FONT_MD)
                .fontColor(AppColors.TEXT_SECONDARY)
              Text(`· ${this.date}`)
                .fontSize(AppDimens.FONT_MD)
                .fontColor(AppColors.TEXT_HINT)
                .margin({ left: 8 })
            }
            .margin({ top: 8 })

            Row({ space: 8 }) {
              Text(this.mood)
                .fontSize(18)
              ForEach(this.tags, (tag: string) => {
                Text(`#${tag}`)
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(AppColors.PRIMARY)
                  .backgroundColor(AppColors.PRIMARY + '15')
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .borderRadius(12)
              })
            }
            .margin({ top: 12 })
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .alignItems(HorizontalAlign.Start)

          Divider()
            .color(AppColors.DIVIDER)
            .margin({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD })

          // 正文
          Text(this.content)
            .fontSize(AppDimens.FONT_MD)
            .fontColor(AppColors.TEXT_PRIMARY)
            .lineHeight(24)
            .padding(AppDimens.PADDING_MD)
            .width('100%')

          // 所属旅行
          if (this.tripName.length > 0) {
            Row() {
              Text('所属旅行')
                .fontSize(AppDimens.FONT_MD)
                .fontColor(AppColors.TEXT_SECONDARY)
              Blank()
              Text(this.tripName)
                .fontSize(AppDimens.FONT_MD)
                .fontColor(AppColors.PRIMARY)
              Text(' >')
                .fontColor(AppColors.TEXT_HINT)
            }
            .width('100%')
            .padding(AppDimens.PADDING_MD)
            .margin({ top: 12 })
            .backgroundColor(AppColors.CARD_BG)
            .borderRadius(AppDimens.RADIUS_SM)
            .onClick(() => {
              router.pushUrl({
                url: RouterUrls.TRIP_DETAIL,
                params: { tripId: this.tripId } as RouterParam
              })
            })
          }
        }
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.BACKGROUND)
  }
}
