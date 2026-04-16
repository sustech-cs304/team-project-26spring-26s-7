import { router, promptAction } from '@kit.ArkUI'
import { AppColors, AppDimens, RouterUrls, getDataService } from '../../../common'
import { RouterParam } from '../../../common'
import type { MemoryNode, Trip } from '../../../common'

interface NodeFeedItem {
  id: string
  title: string
  poiName: string
  content: string
  coverPhoto: string
  createdAt: number
  tripName: string
  tripIsPublic: boolean
}

@Component
export struct NodeListView {
  @State nodes: NodeFeedItem[] = []
  @State totalTripCount: number = 0
  @State isLoading: boolean = false
  @Watch('onTravelDataVersionChange')
  @StorageLink('travelDataVersion') travelDataVersion: number = 0

  private dataService = getDataService()

  aboutToAppear(): void {
    this.loadNodes()
  }

  onPageShow(): void {
    this.loadNodes()
  }

  private onTravelDataVersionChange(): void {
    this.loadNodes()
  }

  private formatDate(timestamp: number): string {
    const date = new Date(timestamp)
    const year = date.getFullYear().toString()
    const month = (date.getMonth() + 1).toString().padStart(2, '0')
    const day = date.getDate().toString().padStart(2, '0')
    return `${year}.${month}.${day}`
  }

  private formatTime(timestamp: number): string {
    const date = new Date(timestamp)
    const hours = date.getHours().toString().padStart(2, '0')
    const minutes = date.getMinutes().toString().padStart(2, '0')
    return `${hours}:${minutes}`
  }

  private getPreviewText(content: string, poiName: string): string {
    const trimmed = content.trim()
    if (trimmed.length > 0) {
      return trimmed
    }
    return poiName.length > 0 ? `在 ${poiName} 留下的一段记忆` : '还没有补充正文'
  }

  private mapNodeToFeedItem(node: MemoryNode, trip: Trip): NodeFeedItem {
    return {
      id: node.id,
      title: node.title,
      poiName: node.poiName,
      content: this.getPreviewText(node.content, node.poiName),
      coverPhoto: node.photos.length > 0 ? node.photos[0] : '',
      createdAt: node.createdAt,
      tripName: trip.name,
      tripIsPublic: trip.isPublic
    }
  }

  private async loadNodes(): Promise<void> {
    this.isLoading = true
    try {
      const trips = await this.dataService.getAllTravels()
      const feedItems: NodeFeedItem[] = []
      for (const trip of trips) {
        const nodes = await this.dataService.getNodesByTravelId(trip.id)
        for (const node of nodes) {
          feedItems.push(this.mapNodeToFeedItem(node, trip))
        }
      }
      feedItems.sort((left: NodeFeedItem, right: NodeFeedItem) => right.createdAt - left.createdAt)
      this.nodes = feedItems
      this.totalTripCount = trips.length
    } catch (_) {
      this.nodes = []
      promptAction.showToast({ message: '加载节点列表失败' })
    } finally {
      this.isLoading = false
    }
  }

  private openNodeDetail(nodeId: string): void {
    router.pushUrl({
      url: RouterUrls.NODE_DETAIL,
      params: { nodeId } as RouterParam
    })
  }

  private openNodeEdit(): void {
    router.pushUrl({ url: RouterUrls.NODE_EDIT })
  }

  @Builder
  private buildHeaderCard() {
    Column() {
      Text('节点')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.TEXT_PRIMARY)
        .width('100%')
      Text('按时间回看每一次停留，把地点记忆串成可浏览的内容流。')
        .fontSize(AppDimens.FONT_MD)
        .fontColor(AppColors.TEXT_SECONDARY)
        .lineHeight(22)
        .margin({ top: 8 })
        .width('100%')

      Row({ space: 12 }) {
        Column() {
          Text(this.nodes.length.toString())
            .fontSize(AppDimens.FONT_XL)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.TEXT_PRIMARY)
          Text('记忆节点')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_HINT)
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column() {
          Text(this.totalTripCount.toString())
            .fontSize(AppDimens.FONT_XL)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.TEXT_PRIMARY)
          Text('所属 Track')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_HINT)
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button('新建节点')
          .height(38)
          .fontSize(AppDimens.FONT_SM)
          .backgroundColor(AppColors.PRIMARY)
          .onClick(() => this.openNodeEdit())
      }
      .width('100%')
      .margin({ top: 18 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(AppDimens.PADDING_LG)
    .backgroundColor(AppColors.CARD_BG)
    .borderRadius(AppDimens.RADIUS_LG)
    .shadow({ radius: 10, color: '#00000012', offsetY: 4 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildNodeCard(item: NodeFeedItem) {
    Row() {
      Stack() {
        if (item.coverPhoto.length > 0) {
          Image(item.coverPhoto)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        } else {
          Column() {
            Text('📍')
              .fontSize(24)
            Text('无封面')
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_HINT)
              .margin({ top: 6 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#EAF4FF')
        }
      }
      .width(92)
      .height(92)
      .borderRadius(AppDimens.RADIUS_MD)
      .clip(true)

      Column() {
        Row() {
          Text(item.title)
            .fontSize(AppDimens.FONT_LG)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_PRIMARY)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(item.tripIsPublic ? '公开' : '私密')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(item.tripIsPublic ? '#167D3E' : '#A55B00')
            .backgroundColor(item.tripIsPublic ? '#E8F5E9' : '#FFF4E5')
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .borderRadius(12)
        }
        .width('100%')

        Text(`📍 ${item.poiName}`)
          .fontSize(AppDimens.FONT_SM)
          .fontColor(AppColors.TEXT_SECONDARY)
          .margin({ top: 6 })
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(item.content)
          .fontSize(AppDimens.FONT_SM)
          .fontColor(AppColors.TEXT_SECONDARY)
          .lineHeight(20)
          .margin({ top: 8 })
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row() {
          Text(`${this.formatDate(item.createdAt)} ${this.formatTime(item.createdAt)}`)
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_HINT)
          Text(`· ${item.tripName}`)
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.PRIMARY)
            .margin({ left: 8 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .margin({ top: 10 })
      }
      .layoutWeight(1)
      .margin({ left: 12 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(AppDimens.PADDING_MD)
    .backgroundColor(AppColors.CARD_BG)
    .borderRadius(AppDimens.RADIUS_MD)
    .shadow({ radius: 6, color: '#0000000F', offsetY: 2 })
    .alignItems(VerticalAlign.Top)
    .onClick(() => this.openNodeDetail(item.id))
  }

  build() {
    Column() {
      this.buildHeaderCard()

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
          Text('正在整理时间线...')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_HINT)
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.nodes.length === 0) {
        Column() {
          Text('还没有节点内容')
            .fontSize(AppDimens.FONT_LG)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_PRIMARY)
          Text('从地图或这里开始，记录你的第一个地点记忆。')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_HINT)
            .margin({ top: 8 })
          Button('立即新建')
            .margin({ top: 20 })
            .backgroundColor(AppColors.PRIMARY)
            .onClick(() => this.openNodeEdit())
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 12 }) {
          ForEach(this.nodes, (item: NodeFeedItem) => {
            ListItem() {
              this.buildNodeCard(item)
            }
          }, (item: NodeFeedItem) => item.id)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ top: 16, bottom: 8 })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: AppDimens.PADDING_MD })
    .backgroundColor(AppColors.BACKGROUND)
  }
}
