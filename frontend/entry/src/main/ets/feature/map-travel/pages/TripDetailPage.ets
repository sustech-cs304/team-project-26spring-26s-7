import { router, promptAction } from '@kit.ArkUI'
import { MapComponent, mapCommon, map } from '@kit.MapKit'
import { AsyncCallback } from '@kit.BasicServicesKit'
import { AppColors, AppDimens, RouterUrls, getDataService } from '../../../common'
import { TimelineNodeInfo, RouterParam } from '../../../common'
import type { MemoryNode } from '../../../common'

interface RemovableOverlay {
  remove: () => void
}

const DEFAULT_TRIP_CENTER: mapCommon.LatLng = {
  latitude: 22.55,
  longitude: 113.96
}

/**
 * P06 旅行详情页 — 路线地图 + 节点时间轴
 * 路由参数：{ tripId: string }
 */
@Entry
@Component
export struct TripDetailPage {
  @State tripName: string = ''
  @State dateRange: string = ''
  @State nodeCount: number = 0
  @State totalDistance: number = 0
  @State isPublic: boolean = false
  @State tripId: string = ''
  @State showMenu: boolean = false
  @State isLoading: boolean = false

  @State timelineNodes: TimelineNodeInfo[] = []

  private routePoints: mapCommon.LatLng[] = []
  private mapOptions: mapCommon.MapOptions = {
    position: {
      target: DEFAULT_TRIP_CENTER,
      zoom: 11.5
    }
  }
  private mapController?: map.MapComponentController
  private routeMarkers: map.Marker[] = []
  private routePolyline?: RemovableOverlay
  private dataService = getDataService()

  private bumpTravelDataVersion(): void {
    const version = (AppStorage.get('travelDataVersion') as number) || 0
    AppStorage.setOrCreate('travelDataVersion', version + 1)
  }

  private mapCallback: AsyncCallback<map.MapComponentController> = async (err, controller) => {
    if (!err && controller) {
      this.mapController = controller
      await this.drawRoute()
    }
  }

  aboutToAppear(): void {
    const params = router.getParams() as RouterParam
    if (params?.tripId) {
      this.tripId = params.tripId
      this.loadTripDetail()
    }
  }

  onPageShow(): void {
    if (this.tripId.length > 0) {
      this.loadTripDetail()
    }
  }

  private formatDate(timestamp: number): string {
    const date = new Date(timestamp)
    const year = date.getFullYear().toString()
    const month = (date.getMonth() + 1).toString().padStart(2, '0')
    const day = date.getDate().toString().padStart(2, '0')
    return `${year}.${month}.${day}`
  }

  private formatShortDate(timestamp: number): string {
    const date = new Date(timestamp)
    const month = (date.getMonth() + 1).toString().padStart(2, '0')
    const day = date.getDate().toString().padStart(2, '0')
    return `${month}.${day}`
  }

  private formatDateRange(startDate: number, endDate: number): string {
    const start = this.formatDate(startDate)
    const end = this.formatDate(endDate)
    return start === end ? start : `${start} ~ ${end}`
  }

  private mapNodeToTimelineNode(node: MemoryNode): TimelineNodeInfo {
    return new TimelineNodeInfo(
      node.id,
      this.formatShortDate(node.createdAt),
      node.poiName,
      node.content || node.title,
      node.photos.length.toString()
    )
  }

  private async loadTripDetail(): Promise<void> {
    if (!this.tripId) {
      return
    }

    this.isLoading = true
    try {
      const trip = await this.dataService.getTravelById(this.tripId)
      if (!trip) {
        promptAction.showToast({ message: '未找到对应旅行' })
        return
      }

      const nodes = await this.dataService.getNodesByTravelId(this.tripId)
      this.tripName = trip.name
      this.dateRange = this.formatDateRange(trip.startDate, trip.endDate)
      this.nodeCount = nodes.length
      this.totalDistance = trip.totalDistance
      this.isPublic = trip.isPublic
      this.timelineNodes = nodes.map((node: MemoryNode) => this.mapNodeToTimelineNode(node))
      this.routePoints = nodes.map((node: MemoryNode): mapCommon.LatLng => ({
        latitude: node.latitude,
        longitude: node.longitude
      }))
      await this.drawRoute()
    } catch (err) {
      promptAction.showToast({ message: '加载旅行详情失败' })
    } finally {
      this.isLoading = false
    }
  }

  /** 在小地图上绘制轨迹折线 + 节点标记 */
  private async drawRoute(): Promise<void> {
    if (!this.mapController || this.routePoints.length === 0) {
      return
    }

    for (const marker of this.routeMarkers) {
      try {
        marker.remove()
      } catch (_) {}
    }
    this.routeMarkers = []

    if (this.routePolyline) {
      try {
        this.routePolyline.remove()
      } catch (_) {}
      this.routePolyline = undefined
    }

    if (this.routePoints.length > 1) {
      this.routePolyline = await this.mapController.addPolyline({
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
      }) as RemovableOverlay
    }

    for (const point of this.routePoints) {
      const marker = await this.mapController.addMarker({
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
      this.routeMarkers.push(marker)
    }

    const cameraUpdate = map.newCameraPosition({
      target: this.routePoints[0],
      zoom: 11.5
    })
    this.mapController.animateCamera(cameraUpdate, 300)
  }

  private async deleteCurrentTrip(): Promise<void> {
    if (!this.tripId) {
      return
    }
    try {
      await this.dataService.deleteTravel(this.tripId)
      this.bumpTravelDataVersion()
      promptAction.showToast({ message: '旅行已删除' })
      router.back()
    } catch (err) {
      promptAction.showToast({ message: '删除旅行失败' })
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
          this.deleteCurrentTrip()
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
          Text(this.tripName || '旅行详情')
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
              Text('· ' + (this.isPublic ? '公开' : '私密'))
                .fontSize(AppDimens.FONT_MD)
                .fontColor(this.isPublic ? AppColors.SUCCESS : AppColors.TEXT_HINT)
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
              router.pushUrl({
                url: RouterUrls.TRIP_EDIT,
                params: { tripId: this.tripId } as RouterParam
              })
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
