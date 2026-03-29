import { router } from '@kit.ArkUI'
import { AppColors, AppDimens, RouterUrls } from '../../common'
import { TripSummary, RouterParam } from '../../common'

/**
 * 旅行列表 Tab 内容视图
 * 展示所有旅行路线卡片
 */
@Component
export struct TripListView {
  @State trips: TripSummary[] = [
    new TripSummary('1', '深圳三日游', '2026.03.15 ~ 03.17', '5', '128'),
    new TripSummary('2', '广州周末', '2026.03.01 ~ 03.02', '3', '45'),
    new TripSummary('3', '珠海一日行', '2026.02.20', '4', '67'),
  ]

  @State showCreateDialog: boolean = false
  @State newTripName: string = ''

  dialogController: CustomDialogController = new CustomDialogController({
    builder: CreateTripDialog({
      tripName: this.newTripName,
      onConfirm: (name: string) => {
        const newId = (this.trips.length + 1).toString()
        const newTrip = new TripSummary(newId, name, '今天', '0', '0')
        this.trips = [newTrip, ...this.trips]
        router.pushUrl({
          url: RouterUrls.TRIP_DETAIL,
          params: { tripId: newId } as RouterParam
        })
      }
    }),
    autoCancel: true
  })

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
          .onClick(() => this.dialogController.open())
      }
      .width('100%')
      .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: AppDimens.PADDING_MD })

      // 旅行卡片列表
      if (this.trips.length === 0) {
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
                // TODO: 替换为真实封面图

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

/**
 * 新建旅行对话框
 */
@CustomDialog
struct CreateTripDialog {
  controller: CustomDialogController = new CustomDialogController({ builder: undefined })
  @State tripName: string = ''
  onConfirm: (name: string) => void = () => {}

  build() {
    Column() {
      Text('新建旅行')
        .fontSize(AppDimens.FONT_XL)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.TEXT_PRIMARY)

      TextInput({ placeholder: '旅行名称，如「深圳三日游」' })
        .onChange((value: string) => { this.tripName = value })
        .margin({ top: 16 })

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .fontSize(AppDimens.FONT_MD)
          .backgroundColor(AppColors.BACKGROUND)
          .fontColor(AppColors.TEXT_SECONDARY)
          .onClick(() => this.controller.close())
        Button('创建')
          .layoutWeight(1)
          .height(40)
          .fontSize(AppDimens.FONT_MD)
          .backgroundColor(AppColors.PRIMARY)
          .enabled(this.tripName.length > 0)
          .onClick(() => {
            this.onConfirm(this.tripName)
            this.controller.close()
          })
      }
      .width('100%')
      .margin({ top: 24 })
    }
    .padding(AppDimens.PADDING_LG)
    .width('90%')
  }
}
