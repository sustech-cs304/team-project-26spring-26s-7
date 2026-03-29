import { router } from '@kit.ArkUI'
import { MapComponent, mapCommon, map } from '@kit.MapKit'
import { AsyncCallback } from '@kit.BasicServicesKit'
import { AppColors, AppDimens, RouterUrls } from '../../../common'
import { TimelineNodeInfo, RouterParam } from '../../../common'

/**
 * P06 旅行详情页 — 路线地图 + 节点时间轴
 * 路由参数：{ tripId: string }
 */
@Entry
@Component
struct TripDetailPage {
  @State tripName: string = '深圳三日游'
  @State dateRange: string = '2026.03.15 ~ 03.17'
  @State nodeCount: number = 5
  @State totalDistance: number = 128
  @State tripId: string = ''
  @State showMenu: boolean = false

  @State timelineNodes: TimelineNodeInfo[] = [
    new TimelineNodeInfo('n1', '03.15', '深圳湾公园', '海边日落，风很温柔', '3'),
    new TimelineNodeInfo('n2', '03.16', '世界之窗', '微缩世界，一日环游', '5'),
    new TimelineNodeInfo('n3', '03.17', '南方科技大学', '校园春色，荔枝花开', '2'),
  ]

  // 旅行轨迹坐标点（模拟数据）
  private routePoints: mapCommon.LatLng[] = [
    { latitude: 22.5268, longitude: 113.9455 },
    { latitude: 22.5348, longitude: 113.9735 },
    { latitude: 22.5965, longitude: 113.9785 },
  ]

  private mapOptions: mapCommon.MapOptions = {
    position: {
      target: { latitude: 22.55, longitude: 113.96 },
      zoom: 11.5
    }
  }
  private mapController?: map.MapComponentController

  private mapCallback: AsyncCallback<map.MapComponentController> = async (err, controller) => {
    if (!err && controller) {
      this.mapController = controller
      await this.drawRoute()
    }
  }

  /** 在小地图上绘制轨迹折线 + 节点标记 */
  private async drawRoute(): Promise<void> {
    if (!this.mapController) {
      return
    }
    // 绘制轨迹折线
    await this.mapController.addPolyline({
      points: this.routePoints,
      clickable: false,
      visible: true,
      width: 8,
      zIndex: 5,
      geodesic: false,
      gradient: false,
      jointType: mapCommon.JointType.ROUND,
      startCap: mapCommon.CapStyle.ROUND,
      endCap: mapCommon.CapStyle.ROUND
    })
    // 添加节点标记
    for (const point of this.routePoints) {
      await this.mapController.addMarker({
        position: point,
        visible: true,
        clickable: false,
        draggable: false,
        flat: false,
        rotation: 0,
        zIndex: 10,
        alpha: 1,
        anchorU: 0.5,
        anchorV: 1
      })
    }
  }

  aboutToAppear(): void {
    const params = router.getParams() as RouterParam
    if (params?.tripId) {
      this.tripId = params.tripId
      // TODO: 从本地 RDB 加载旅行数据和关联节点
    }
  }

  private handleDeleteTrip(): void {
    AlertDialog.show({
      title: '删除旅行',
      message: '确定要删除「' + this.tripName + '」吗？此操作不可撤销。',
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '删除',
        fontColor: AppColors.DANGER,
        action: () => {
          // TODO: 从 RDB 删除旅行，排入同步队列
          router.back()
        }
      }
    })
  }

  build() {
    Stack() {
      Column() {
        // 顶部导航栏
        Row() {
          Text('←')
            .fontSize(AppDimens.FONT_XL)
            .fontColor(AppColors.TEXT_PRIMARY)
            .onClick(() => router.back())
            .padding(AppDimens.PADDING_MD)
          Text(this.tripName)
            .fontSize(AppDimens.FONT_LG)
            .fontWeight(FontWeight.Bold)
            .layoutWeight(1)
          Text('···')
            .fontSize(AppDimens.FONT_XL)
            .fontColor(AppColors.TEXT_SECONDARY)
            .padding(AppDimens.PADDING_MD)
            .onClick(() => { this.showMenu = !this.showMenu })
        }
        .width('100%')
        .height(56)
        .backgroundColor(AppColors.CARD_BG)

        Scroll() {
          Column() {
            // 路线地图（真实 MapComponent）
            MapComponent({ mapOptions: this.mapOptions, mapCallback: this.mapCallback })
              .width('100%')
              .height(200)
              .borderRadius(AppDimens.RADIUS_MD)
              .margin({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 12 })

            // 操作按钮
            Row({ space: 12 }) {
              Button('▶ 回放')
                .layoutWeight(1)
                .height(44)
                .fontSize(AppDimens.FONT_MD)
                .backgroundColor(AppColors.PRIMARY)
                .onClick(() => {
                  router.pushUrl({
                    url: RouterUrls.TRIP_REPLAY,
                    params: { tripId: this.tripId } as RouterParam
                  })
                })
              Button('↗ 分享')
                .layoutWeight(1)
                .height(44)
                .fontSize(AppDimens.FONT_MD)
                .backgroundColor('#FF8C00')
                .onClick(() => {
                  router.pushUrl({
                    url: RouterUrls.SHARE,
                    params: { tripId: this.tripId } as RouterParam
                  })
                })
            }
            .width('100%')
            .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 12 })

            // 统计信息
            Row() {
              Text('📍 ' + this.nodeCount + ' 个节点')
                .fontSize(AppDimens.FONT_MD)
                .fontColor(AppColors.TEXT_SECONDARY)
              Text('· ' + this.totalDistance + ' km')
                .fontSize(AppDimens.FONT_MD)
                .fontColor(AppColors.TEXT_SECONDARY)
                .margin({ left: 8 })
              Text('· ' + this.dateRange)
                .fontSize(AppDimens.FONT_MD)
                .fontColor(AppColors.TEXT_HINT)
                .margin({ left: 8 })
            }
            .width('100%')
            .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 16 })

            // 分隔标题
            Text('时间轴')
              .fontSize(AppDimens.FONT_MD)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)
              .padding({ left: AppDimens.PADDING_MD, top: 16, bottom: 8 })
              .width('100%')

            // 时间轴列表
            ForEach(this.timelineNodes, (node: TimelineNodeInfo, index: number) => {
              Row() {
                Column() {
                  Circle()
                    .width(10)
                    .height(10)
                    .fill(AppColors.PRIMARY)
                  if (index < this.timelineNodes.length - 1) {
                    Line()
                      .width(2)
                      .height(50)
                      .backgroundColor(AppColors.DIVIDER)
                  }
                }
                .width(30)
                .alignItems(HorizontalAlign.Center)

                Column() {
                  Text(node.date)
                    .fontSize(AppDimens.FONT_SM)
                    .fontColor(AppColors.TEXT_HINT)
                  Text(node.place)
                    .fontSize(AppDimens.FONT_LG)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(AppColors.TEXT_PRIMARY)
                    .margin({ top: 2 })
                  Text('📷 ' + node.photoCount + '张 · "' + node.summary + '"')
                    .fontSize(AppDimens.FONT_SM)
                    .fontColor(AppColors.TEXT_SECONDARY)
                    .margin({ top: 4 })
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                .padding({ left: 8, bottom: 16 })

                Text('>')
                  .fontSize(AppDimens.FONT_MD)
                  .fontColor(AppColors.TEXT_HINT)
              }
              .width('100%')
              .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD })
              .alignItems(VerticalAlign.Top)
              .onClick(() => {
                router.pushUrl({
                  url: RouterUrls.NODE_DETAIL,
                  params: { nodeId: node.id } as RouterParam
                })
              })
            })
          }
          .padding({ bottom: 24 })
        }
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.BACKGROUND)

      // 右上角下拉菜单
      if (this.showMenu) {
        Column()
          .width('100%')
          .height('100%')
          .onClick(() => { this.showMenu = false })

        Column() {
          Text('添加节点')
            .fontSize(AppDimens.FONT_MD)
            .fontColor(AppColors.TEXT_PRIMARY)
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .onClick(() => {
              this.showMenu = false
              router.pushUrl({
                url: RouterUrls.NODE_EDIT,
                params: { tripId: this.tripId } as RouterParam
              })
            })
          Divider().color(AppColors.DIVIDER)
          Text('编辑旅行')
            .fontSize(AppDimens.FONT_MD)
            .fontColor(AppColors.TEXT_PRIMARY)
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .onClick(() => {
              this.showMenu = false
              // TODO: 弹出编辑旅行名称/日期的对话框
            })
          Divider().color(AppColors.DIVIDER)
          Text('删除旅行')
            .fontSize(AppDimens.FONT_MD)
            .fontColor(AppColors.DANGER)
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .onClick(() => {
              this.showMenu = false
              this.handleDeleteTrip()
            })
        }
        .width(140)
        .backgroundColor(AppColors.CARD_BG)
        .borderRadius(AppDimens.RADIUS_SM)
        .shadow({ radius: 8, color: '#0000001A', offsetY: 4 })
        .position({ x: '55%', y: 56 })
      }
    }
  }
}
