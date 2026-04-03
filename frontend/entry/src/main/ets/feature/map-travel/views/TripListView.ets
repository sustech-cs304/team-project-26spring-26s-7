import { router, promptAction } from '@kit.ArkUI'
import { AppColors, AppDimens, RouterUrls, getDataService } from '../../../common'
import { TripSummary, RouterParam } from '../../../common'
import type { Trip } from '../../../common'

/**
 * 旅行列表 Tab 内容视图
 * 展示所有旅行路线卡片
 *
 */
@Component
export struct TripListView {
  @State trips: TripSummary[] = []
  @State isLoading: boolean = false

  private dataService = getDataService()

  aboutToAppear(): void {
    this.loadTrips()
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

  private mapTripToSummary(trip: Trip): TripSummary {
    return new TripSummary(
      trip.id,
      trip.name,
      this.formatDateRange(trip.startDate, trip.endDate),
      trip.nodeIds.length.toString(),
      trip.totalDistance.toString()
    )
  }

  private async loadTrips(): Promise<void> {
    this.isLoading = true
    try {
      const trips = await this.dataService.getAllTravels()
      this.trips = trips.map((trip: Trip) => this.mapTripToSummary(trip))
    } catch (err) {
      promptAction.showToast({ message: '加载旅行列表失败' })
    } finally {
      this.isLoading = false
    }
  }

  private async handleCreateTrip(): Promise<void> {
    try {
      const now = Date.now()
      const createdTrip = await this.dataService.createTravel({
        name: `新旅行 ${this.formatDate(now)}`,
        description: '',
        coverPhoto: '',
        startDate: now,
        endDate: now,
        nodeIds: [],
        totalDistance: 0
      })
      await this.loadTrips()
      promptAction.showToast({ message: '已创建新旅行' })
      router.pushUrl({
        url: RouterUrls.TRIP_DETAIL,
        params: { tripId: createdTrip.id } as RouterParam
      })
    } catch (err) {
      promptAction.showToast({ message: '创建旅行失败' })
    }
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Text('我的旅行')
          .fontSize(AppDimens.FONT_XL)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_PRIMARY)
        Blank()
        Button('+ 新建')
          .height(32)
          .fontSize(AppDimens.FONT_SM)
          .backgroundColor(AppColors.PRIMARY)
          .onClick(() => { this.handleCreateTrip() })
      }
      .width('100%')
      .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: AppDimens.PADDING_MD })

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
          Text('正在加载旅行数据...')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_HINT)
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.trips.length === 0) {
        Column() {
          Text('🧳')
            .fontSize(48)
          Text('还没有旅行记录')
            .fontSize(AppDimens.FONT_MD)
            .fontColor(AppColors.TEXT_HINT)
            .margin({ top: 8 })
          Text('点击右上角「+ 新建」开始第一段旅行')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_HINT)
            .margin({ top: 4 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 12 }) {
          ForEach(this.trips, (trip: TripSummary) => {
            ListItem() {
              Column() {
                // 封面图占位
                Stack() {
                  Column() {
                    Text('🖼')
                      .fontSize(32)
                  }
                  .justifyContent(FlexAlign.Center)
                }
                .width('100%')
                .height(140)
                .backgroundColor(AppColors.BACKGROUND)
                .borderRadius({ topLeft: AppDimens.RADIUS_MD, topRight: AppDimens.RADIUS_MD })

                // 旅行信息
                Column() {
                  Text(trip.name)
                    .fontSize(AppDimens.FONT_LG)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(AppColors.TEXT_PRIMARY)
                  Text(trip.dateRange)
                    .fontSize(AppDimens.FONT_SM)
                    .fontColor(AppColors.TEXT_HINT)
                    .margin({ top: 4 })
                  Row() {
                    Text('📍 ' + trip.nodeCount + ' 个节点')
                      .fontSize(AppDimens.FONT_SM)
                      .fontColor(AppColors.TEXT_SECONDARY)
                    Text('· ' + trip.distance + ' km')
                      .fontSize(AppDimens.FONT_SM)
                      .fontColor(AppColors.TEXT_SECONDARY)
                      .margin({ left: 8 })
                  }
                  .margin({ top: 4 })
                }
                .width('100%')
                .padding(12)
                .alignItems(HorizontalAlign.Start)
              }
              .backgroundColor(AppColors.CARD_BG)
              .borderRadius(AppDimens.RADIUS_MD)
              .shadow({ radius: 4, color: '#0000000D', offsetY: 2 })
              .onClick(() => {
                router.pushUrl({
                  url: RouterUrls.TRIP_DETAIL,
                  params: { tripId: trip.id } as RouterParam
                })
              })
            }
          })
        }
        .layoutWeight(1)
        .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 12 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.BACKGROUND)
  }
}
