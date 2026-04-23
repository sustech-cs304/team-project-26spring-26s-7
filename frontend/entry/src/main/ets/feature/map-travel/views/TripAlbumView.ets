import { router, promptAction } from '@kit.ArkUI'
import { AppColors, AppDimens, RouterUrls, getDataService } from '../../../common'
import { RouterParam } from '../../../common'
import type { Trip, MemoryNode } from '../../../common'

interface TripAlbumItem {
  tripId: string
  name: string
  dateRange: string
  nodeCount: string
  distance: string
  coverPhoto: string
  hasCoverPhoto: boolean
  coverHeight: number
}

/**
 * 旅行相册 Tab 内容视图
 * 双列瀑布流展示每次旅行封面（首节点首图）
 */
@Component
export struct TripAlbumView {
  @State leftColumnItems: TripAlbumItem[] = []
  @State rightColumnItems: TripAlbumItem[] = []
  @State isLoading: boolean = false
  @Watch('onTravelDataVersionChange')
  @StorageLink('travelDataVersion') travelDataVersion: number = 0

  private dataService = getDataService()

  aboutToAppear(): void {
    this.loadAlbum()
  }

  onPageShow(): void {
    this.loadAlbum()
  }

  private onTravelDataVersionChange(): void {
    this.loadAlbum()
  }

  private formatDate(timestamp: number): string {
    const date = new Date(timestamp)
    const year = date.getFullYear().toString()
    const month = (date.getMonth() + 1).toString().padStart(2, '0')
    const day = date.getDate().toString().padStart(2, '0')
    return `${year}.${month}.${day}`
  }

  private formatDateRange(startDate: number, endDate: number): string {
    const start = this.formatDate(startDate)
    const end = this.formatDate(endDate)
    return start === end ? start : `${start} ~ ${end}`
  }

  private pickCoverHeight(index: number): number {
    const heights: number[] = [156, 188, 170, 204]
    return heights[index % heights.length]
  }

  private async mapTripToAlbumItem(trip: Trip, index: number): Promise<TripAlbumItem> {
    const nodes = await this.dataService.getNodesByTravelId(trip.id)
    const firstNode: MemoryNode | undefined = nodes.length > 0 ? nodes[0] : undefined
    const firstPhoto = firstNode && firstNode.photos.length > 0 ? firstNode.photos[0] : ''

    return {
      tripId: trip.id,
      name: trip.name,
      dateRange: this.formatDateRange(trip.startDate, trip.endDate),
      nodeCount: nodes.length.toString(),
      distance: trip.totalDistance.toString(),
      coverPhoto: firstPhoto,
      hasCoverPhoto: firstPhoto.length > 0,
      coverHeight: this.pickCoverHeight(index)
    }
  }

  private splitToColumns(items: TripAlbumItem[]): void {
    const leftItems: TripAlbumItem[] = []
    const rightItems: TripAlbumItem[] = []
    let leftHeight: number = 0
    let rightHeight: number = 0

    for (const item of items) {
      const estimatedHeight = item.coverHeight + 82
      if (leftHeight <= rightHeight) {
        leftItems.push(item)
        leftHeight += estimatedHeight
      } else {
        rightItems.push(item)
        rightHeight += estimatedHeight
      }
    }

    this.leftColumnItems = leftItems
    this.rightColumnItems = rightItems
  }

  private async loadAlbum(): Promise<void> {
    this.isLoading = true
    try {
      const trips = await this.dataService.getAllTravels()
      const albumItems: TripAlbumItem[] = []
      for (let index = 0; index < trips.length; index++) {
        albumItems.push(await this.mapTripToAlbumItem(trips[index], index))
      }
      this.splitToColumns(albumItems)
    } catch (err) {
      this.leftColumnItems = []
      this.rightColumnItems = []
      promptAction.showToast({ message: '加载旅行相册失败' })
    } finally {
      this.isLoading = false
    }
  }

  private openTripDetail(tripId: string): void {
    router.pushUrl({
      url: RouterUrls.TRIP_DETAIL,
      params: { tripId } as RouterParam
    })
  }

  @Builder
  private buildAlbumCard(item: TripAlbumItem) {
    Column() {
      Stack() {
        if (item.hasCoverPhoto) {
          Image(item.coverPhoto)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        } else {
          Column() {
            Text('暂无封面')
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_HINT)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor(AppColors.BACKGROUND)
        }
      }
      .width('100%')
      .height(item.coverHeight)
      .clip(true)

      Column() {
        Text(item.name)
          .fontSize(AppDimens.FONT_MD)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(item.dateRange)
          .fontSize(AppDimens.FONT_SM)
          .fontColor(AppColors.TEXT_HINT)
          .margin({ top: 4 })

        Text(item.nodeCount + ' 个节点 · ' + item.distance + ' km')
          .fontSize(AppDimens.FONT_SM)
          .fontColor(AppColors.TEXT_SECONDARY)
          .margin({ top: 4 })
      }
      .width('100%')
      .padding(10)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .backgroundColor(AppColors.CARD_BG)
    .borderRadius(AppDimens.RADIUS_MD)
    .shadow({ radius: 4, color: '#00000012', offsetY: 2 })
    .clip(true)
    .onClick(() => {
      this.openTripDetail(item.tripId)
    })
  }

  build() {
    Column() {
      Row() {
        Text('旅行相册')
          .fontSize(AppDimens.FONT_XL)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_PRIMARY)
        Blank()
      }
      .width('100%')
      .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: AppDimens.PADDING_MD })

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
          Text('正在加载旅行相册...')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_HINT)
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.leftColumnItems.length + this.rightColumnItems.length === 0) {
        Column() {
          Text('还没有旅行记录')
            .fontSize(AppDimens.FONT_MD)
            .fontColor(AppColors.TEXT_HINT)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Row({ space: 12 }) {
            Column({ space: 12 }) {
              ForEach(this.leftColumnItems, (item: TripAlbumItem) => {
                this.buildAlbumCard(item)
              })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Column({ space: 12 }) {
              ForEach(this.rightColumnItems, (item: TripAlbumItem) => {
                this.buildAlbumCard(item)
              })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 12, bottom: 16 })
        }
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.BACKGROUND)
  }
}
