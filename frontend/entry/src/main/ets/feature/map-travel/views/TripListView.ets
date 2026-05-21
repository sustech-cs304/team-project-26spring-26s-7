import { router, promptAction } from '@kit.ArkUI'
import { AppColors, AppDimens, RouterUrls, getDataService } from '../../../common'
import { RouterParam } from '../../../common'
import type { Trip, MemoryNode } from '../../../common'

interface TripCardItem {
  trip: Trip
  coverPhoto: string
  hasCoverPhoto: boolean
}

@Component
export struct TripListView {
  @StorageLink('appThemeVersion') themeVersion: number = 0
  @State trips: Trip[] = []
  @State tripCardItems: TripCardItem[] = []
  @State searchKeyword: string = ''
  @State isLoading: boolean = false
  @Watch('onTravelDataVersionChange')
  @StorageLink('travelDataVersion') travelDataVersion: number = 0
  @StorageLink('activeTabIndex') activeTabIndex: number = 0
  @State longPressedTripId: string = ''

  private dataService = getDataService()

  aboutToAppear(): void {
    this.loadTrips()
  }

  private onTravelDataVersionChange(): void {
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

  private normalizeSearchKeyword(value: string): string {
    return value.trim().toLowerCase()
  }

  private getFilteredTripCards(): TripCardItem[] {
    const keyword = this.normalizeSearchKeyword(this.searchKeyword)
    if (keyword.length === 0) {
      return this.tripCardItems
    }

    return this.tripCardItems.filter((item: TripCardItem) => {
      const trip = item.trip
      const searchFields: string[] = [
        trip.name,
        trip.description ?? '',
        this.formatDateRange(trip.startDate, trip.endDate)
      ]

      return searchFields.some((field: string) => field.toLowerCase().indexOf(keyword) >= 0)
    })
  }

  private async mapTripToCardItem(trip: Trip): Promise<TripCardItem> {
    const nodes: MemoryNode[] = await this.dataService.getNodesByTravelId(trip.id)
    let coverPhoto = ''

    for (const node of nodes) {
      if (node.photos.length > 0) {
        coverPhoto = node.photos[0]
        break
      }
    }

    return {
      trip,
      coverPhoto,
      hasCoverPhoto: coverPhoto.length > 0
    }
  }

  private async loadTrips(): Promise<void> {
    this.isLoading = true
    try {
      const trips = await this.dataService.getAllTravels()
      const cardItems: TripCardItem[] = []
      for (const trip of trips) {
        cardItems.push(await this.mapTripToCardItem(trip))
      }
      this.trips = trips
      this.tripCardItems = cardItems
    } catch (_) {
      this.trips = []
      this.tripCardItems = []
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
    .backgroundColor(AppDimens.SURFACE_TINT)
    .border({ width: 1, color: AppDimens.GLASS_BORDER })
    .borderRadius(24)
    .shadow({ radius: 12, color: AppDimens.SHADOW_SOFT, offsetY: 4 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildTripCoverCard(item: TripCardItem) {
    Stack() {
      // 1. 底层图片
      if (item.hasCoverPhoto) {
        Image(item.coverPhoto)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      } else {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#374151')
      }

      // 2. 黑色渐变遮罩层（关键：防止白底背景）
      // 从透明过渡到深色，范围扩大，确保文字区域在深色范围内
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Bottom,
          // 0%处完全透明，50%处开始变暗，100%处达到0.8透明度的黑
          colors: [['#00000000', 0.0], ['#00000033', 0.5], ['#000000CC', 1.0]]
        })

      // 3. 内容层
      Column() {
        Blank()

        // 标题增加微弱阴影，增强在浅色图片上的可读性
        Text(item.trip.name)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .width('100%')
          .maxLines(2)
          .textShadow({ radius: 4, color: '#44000000', offsetX: 1, offsetY: 1 })
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.longPressedTripId === item.trip.id) {
          Row({ space: 12 }) {
            this.buildGlassButton('查看路线', () => this.openTripDetail(item.trip.id))
            this.buildGlassButton('编辑', () => this.openTripEdit(item.trip.id))
          }
          .width('100%')
          .margin({ top: 16 })
          .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
        }
      }
      .width('100%')
      .height('100%')
      .padding(AppDimens.PADDING_LG)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(210)
    .borderRadius(AppDimens.RADIUS_LG)
    .clip(true)
    .shadow({ radius: 18, color: '#33000000', offsetY: 8 })
    .onClick(() => {
      this.longPressedTripId = this.longPressedTripId === item.trip.id ? '' : item.trip.id
    })
  }

  // 封装的玻璃质感按钮
  @Builder
  private buildGlassButton(text: string, onClick: () => void) {
    Button() {
      Text(text)
        .fontSize(AppDimens.FONT_SM)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
    }
    .layoutWeight(1)
    .height(38)
    .onClick(onClick)
    // 玻璃感核心设置：
    // 1. 半透明白色背景
    .backgroundColor('#22FFFFFF')
    // 2. 背景模糊（API 9+ 支持）
    .backgroundBlurStyle(BlurStyle.Thin, { colorMode: ThemeColorMode.SYSTEM, adaptiveColor: AdaptiveColor.DEFAULT })
    // 3. 高亮半透明边框，模拟玻璃边缘
    .border({ width: 0.8, color: '#55FFFFFF' })
    .borderRadius(19)
    // 4. 点击时的缩放反馈
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
  }

  build() {
    Column() {
      Column() {
        Text('旅途')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_PRIMARY)
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
            .fontColor(AppColors.TEXT_ON_PRIMARY)
            .backgroundColor(AppDimens.CTA_DARK)
            .onClick(() => this.openTripEdit())
        }
        .width('100%')
        .margin({ top: 18 })

        this.buildSearchInput()
      }
      .width('100%')
      .padding({ left: 0, right: 0, top: 12, bottom: 8 })
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
      } else if (this.getFilteredTripCards().length === 0) {
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
          ForEach(this.getFilteredTripCards(), (item: TripCardItem) => {
            ListItem() {
              this.buildTripCoverCard(item)
            }
          }, (item: TripCardItem) => `${item.trip.id}-${item.coverPhoto}-${item.trip.updatedAt}`)
          ListItem() {
            Column()
              .width('100%')
              .height(76)
              .backgroundColor(AppColors.BACKGROUND)
          }
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ top: 16, bottom: 12 })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: AppDimens.PADDING_MD, bottom: 0 })
    .backgroundColor(AppColors.BACKGROUND)
  }
}
