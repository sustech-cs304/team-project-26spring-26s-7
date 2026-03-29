import { router } from '@kit.ArkUI'
import { AppColors, AppDimens, RouterUrls } from '../../../common'
import { TripSummary, RouterParam } from '../../../common'

/**
 * 旅行列表 Tab 内容视图
 * 展示所有旅行路线卡片
 *
 * 注意：当前使用硬编码模拟数据
 * 数据层集成后，可通过 getDataService() 获取真实数据
 */
@Component
export struct TripListView {
  // 模拟数据（数据层完成前使用）
  @State trips: TripSummary[] = [
    new TripSummary('1', '深圳三日游', '2026.03.15 ~ 03.17', '5', '128'),
    new TripSummary('2', '广州周末', '2026.03.01 ~ 03.02', '3', '45'),
    new TripSummary('3', '珠海一日行', '2026.02.20', '4', '67'),
  ]

  @State newTripName: string = ''

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
          .onClick(() => {
            // TODO: 数据层完成后实现创建旅行逻辑
            // 当前仅用于 UI 展示
          })
      }
      .width('100%')
      .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: AppDimens.PADDING_MD })

      // 空数据状态（当 trips.length === 0 时显示）
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
