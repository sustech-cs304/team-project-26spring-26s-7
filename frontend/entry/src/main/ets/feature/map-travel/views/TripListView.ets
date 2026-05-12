import { router, promptAction } from '@kit.ArkUI'
import { AppColors, AppDimens, RouterUrls, getDataService } from '../../../common'
import { RouterParam } from '../../../common'
import type { Trip } from '../../../common'

@Component
export struct TripListView {
  @StorageLink('appThemeVersion') themeVersion: number = 0
  @State trips: Trip[] = []
  @State searchKeyword: string = ''
  @State isLoading: boolean = false
  @Watch('onTravelDataVersionChange')
  @StorageLink('travelDataVersion') travelDataVersion: number = 0
  @Watch('onTabRefresh')
  @StorageLink('tabRefreshToken') tabRefreshToken: number = 0
  @StorageLink('activeTabIndex') activeTabIndex: number = 0

  private dataService = getDataService()

  aboutToAppear(): void {
    this.loadTrips()
  }

  private onTravelDataVersionChange(): void {
    this.loadTrips()
  }

  private onTabRefresh(): void {
    if (this.activeTabIndex === 1) {
      this.loadTrips()
    }
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

  private getTripDescription(trip: Trip): string {
    const description = trip.description ?? ''
    return description.length > 0 ? description : '用这条 Track 串起路线、节点顺序和分享范围。'
  }

  private normalizeSearchKeyword(value: string): string {
    return value.trim().toLowerCase()
  }

  private getFilteredTrips(): Trip[] {
    const keyword = this.normalizeSearchKeyword(this.searchKeyword)
    if (keyword.length === 0) {
      return this.trips
    }

    return this.trips.filter((trip: Trip) => {
      const searchFields: string[] = [
        trip.name,
        trip.description ?? '',
        this.getVisibilityLabel(trip),
        this.formatDateRange(trip.startDate, trip.endDate)
      ]

      return searchFields.some((field: string) => field.toLowerCase().indexOf(keyword) >= 0)
    })
  }

  private async loadTrips(): Promise<void> {
    this.isLoading = true
    try {
      this.trips = await this.dataService.getAllTravels()
    } catch (_) {
      promptAction.showToast({ message: '加载旅行列表失败' })
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

  private openTripEdit(tripId?: string): void {
    if (tripId) {
      router.pushUrl({
        url: RouterUrls.TRIP_EDIT,
        params: { tripId } as RouterParam
      })
      return
    }
    router.pushUrl({ url: RouterUrls.TRIP_EDIT })
  }

  private getVisibilityLabel(trip: Trip): string {
    return trip.isPublic ? '公开' : '私密'
  }

  private getVisibilityColor(trip: Trip): string {
    return trip.isPublic ? '#167D3E' : '#A55B00'
  }

  private getVisibilityBackground(trip: Trip): string {
    return trip.isPublic ? '#E8F5E9' : '#FFF4E5'
  }

  @Builder
  private buildSearchInput() {
    Row({ space: 8 }) {
      TextInput({ placeholder: '搜索旅行名称', text: this.searchKeyword })
        .layoutWeight(1)
        .fontColor(AppColors.INPUT_TEXT)
        .placeholderColor(AppColors.INPUT_PLACEHOLDER)
        .caretColor(AppColors.INPUT_CARET)
        .backgroundColor('#00000000')
        .onChange((value: string) => {
          this.searchKeyword = value
        })

      if (this.searchKeyword.length > 0) {
        Button() {
          Text('×')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_HINT)
        }
        .width(28)
        .height(28)
        .padding(0)
        .backgroundColor('#F0F1F4')
        .borderRadius(14)
        .onClick(() => {
          this.searchKeyword = ''
        })
      }
    }
    .width('100%')
    .margin({ top: 16 })
    .padding({ left: 12, right: 10 })
    .backgroundColor(AppColors.INPUT_BG)
    .borderRadius(22)
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column() {
      Column() {
        Text('旅行 Track')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_PRIMARY)
          .width('100%')

        Text('按旅行维度组织路线、节点和分享范围。')
          .fontSize(AppDimens.FONT_MD)
          .fontColor(AppColors.TEXT_SECONDARY)
          .margin({ top: 8 })
          .width('100%')

        Row({ space: 12 }) {
          Column() {
            Text(this.trips.length.toString())
              .fontSize(AppDimens.FONT_XL)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.TEXT_PRIMARY)
            Text('条 Track')
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_HINT)
              .margin({ top: 4 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Button('新建 Track')
            .height(38)
            .fontSize(AppDimens.FONT_SM)
            .backgroundColor(AppColors.PRIMARY)
            .onClick(() => this.openTripEdit())
        }
        .width('100%')
        .margin({ top: 18 })

        this.buildSearchInput()
      }
      .width('100%')
      .padding(AppDimens.PADDING_LG)
      .backgroundColor(AppColors.CARD_BG)
      .borderRadius(AppDimens.RADIUS_LG)
      .shadow({ radius: 10, color: '#00000012', offsetY: 4 })
      .alignItems(HorizontalAlign.Start)

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
          Text('还没有 Track')
            .fontSize(AppDimens.FONT_LG)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_PRIMARY)
          Text('先创建一条旅行，再逐步把节点补进去。')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_HINT)
            .margin({ top: 8 })
          Button('创建第一条 Track')
            .margin({ top: 20 })
            .backgroundColor(AppColors.PRIMARY)
            .onClick(() => this.openTripEdit())
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.getFilteredTrips().length === 0) {
        Column() {
          Text('没有找到匹配的旅行')
            .fontSize(AppDimens.FONT_LG)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_PRIMARY)
          Text('试试更换关键词，或者检查旅行名称和描述')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_HINT)
            .margin({ top: 8 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 12 }) {
          ForEach(this.getFilteredTrips(), (trip: Trip) => {
            ListItem() {
              Column() {
                Row() {
                  Column() {
                    Text(trip.name)
                      .fontSize(AppDimens.FONT_LG)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(AppColors.TEXT_PRIMARY)
                      .width('100%')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.formatDateRange(trip.startDate, trip.endDate))
                      .fontSize(AppDimens.FONT_SM)
                      .fontColor(AppColors.TEXT_HINT)
                      .margin({ top: 6 })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  Text(this.getVisibilityLabel(trip))
                    .fontSize(AppDimens.FONT_SM)
                    .fontColor(this.getVisibilityColor(trip))
                    .backgroundColor(this.getVisibilityBackground(trip))
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .borderRadius(14)
                }
                .width('100%')

                Text(this.getTripDescription(trip))
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(AppColors.TEXT_SECONDARY)
                  .lineHeight(20)
                  .width('100%')
                  .margin({ top: 14 })

                Row() {
                  Text(`📍 ${trip.nodeIds.length} 个节点`)
                    .fontSize(AppDimens.FONT_SM)
                    .fontColor(AppColors.TEXT_SECONDARY)
                  Text(`路 ${trip.totalDistance} km`)
                    .fontSize(AppDimens.FONT_SM)
                    .fontColor(AppColors.TEXT_SECONDARY)
                    .margin({ left: 8 })
                  Text(`路 ${trip.isPublic ? '所有人可查看' : '仅自己可查看'}`)
                    .fontSize(AppDimens.FONT_SM)
                    .fontColor(AppColors.TEXT_HINT)
                    .margin({ left: 8 })
                }
                .width('100%')
                .margin({ top: 12 })

                Row({ space: 10 }) {
                  Button('查看路线')
                    .layoutWeight(1)
                    .height(34)
                    .fontSize(AppDimens.FONT_SM)
                    .backgroundColor(AppColors.PRIMARY)
                    .onClick(() => this.openTripDetail(trip.id))
                  Button('编辑')
                    .layoutWeight(1)
                    .height(34)
                    .fontSize(AppDimens.FONT_SM)
                    .fontColor(AppColors.PRIMARY)
                    .backgroundColor('#EAF4FF')
                    .onClick(() => this.openTripEdit(trip.id))
                }
                .width('100%')
                .margin({ top: 16 })
              }
              .backgroundColor(AppColors.CARD_BG)
              .borderRadius(AppDimens.RADIUS_MD)
              .padding(AppDimens.PADDING_MD)
              .shadow({ radius: 4, color: '#0000000D', offsetY: 2 })
            }
          }, (trip: Trip) => `${trip.id}-${trip.nodeIds.length}-${trip.totalDistance}`)
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
