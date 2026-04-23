import { router, promptAction } from '@kit.ArkUI'
import { MapComponent, mapCommon, map } from '@kit.MapKit'
import { AsyncCallback } from '@kit.BasicServicesKit'
import { AppColors, AppDimens, RouterUrls, getDataService } from '../../../common'
import { RouterParam } from '../../../common'
import type { MemoryNode } from '../../../common'

interface RemovableOverlay {
  remove: () => void
}

interface TimelineNodeCard {
  id: string
  date: string
  title: string
  place: string
  summary: string
  photoCount: number
  mood: string
  tags: string[]
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

  @State timelineNodes: TimelineNodeCard[] = []

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

  private mapNodeToTimelineNode(node: MemoryNode): TimelineNodeCard {
    const trimmedTitle = node.title.trim()
    const trimmedPlace = node.poiName.trim()
    const trimmedContent = node.content.trim()
    return {
      id: node.id,
      date: this.formatShortDate(node.createdAt),
      title: trimmedTitle.length > 0 ? trimmedTitle : (trimmedPlace.length > 0 ? trimmedPlace : '未命名节点'),
      place: trimmedPlace.length > 0 ? trimmedPlace : '未命名地点',
      summary: trimmedContent,
      photoCount: node.photos.length,
      mood: node.mood,
      tags: [...node.tags]
    }
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

  @Builder
  private buildRouteHero() {
    Stack() {
      MapComponent({ mapOptions: this.mapOptions, mapCallback: this.mapCallback })
        .width('100%')
        .height('100%')

      Column() {
        Text(this.tripName || '旅行详情')
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor('#000000')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .width('100%')
      .padding({ left: AppDimens.PADDING_LG, right: AppDimens.PADDING_LG, top: 14, bottom: 14 })
      .backgroundColor('#00000055')
      .alignItems(HorizontalAlign.Start)
      .position({ x: 0, y: 0 })
    }
    .width('100%')
    .height(232)
    .borderRadius(24)
    .clip(true)
  }

  @Builder
  private buildTripSummary() {
    Column() {
      Row({ space: 10 }) {
        Column() {
          Text(this.nodeCount.toString())
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.TEXT_PRIMARY)
            .width('100%')
          Text('节点')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_HINT)
            .margin({ top: 4 })
        }
        .layoutWeight(10)
        .padding({ left: 12, right: 12, top: 14, bottom: 14 })
        .backgroundColor(AppColors.BACKGROUND)
        .borderRadius(16)
        .alignItems(HorizontalAlign.Start)

        Column() {
          Row({ space: 4 }) {
            Text(this.totalDistance.toString())
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.TEXT_PRIMARY)
            Text('km')
              .fontSize(AppDimens.FONT_MD)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_SECONDARY)
              .margin({ top: 5 })
          }
          .width('100%')
          .alignItems(VerticalAlign.Bottom)
          Text('距离')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_HINT)
            .margin({ top: 4 })
        }
        .layoutWeight(12)
        .padding({ left: 12, right: 12, top: 14, bottom: 14 })
        .backgroundColor(AppColors.BACKGROUND)
        .borderRadius(16)
        .alignItems(HorizontalAlign.Start)

        Column() {
          Text(this.isPublic ? '公开' : '私密')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.isPublic ? AppColors.SUCCESS : '#A55B00')
            .width('100%')
          Text('可见性')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_HINT)
            .margin({ top: 4 })
        }
        .layoutWeight(9)
        .padding({ left: 12, right: 12, top: 14, bottom: 14 })
        .backgroundColor(AppColors.BACKGROUND)
        .borderRadius(16)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppDimens.PADDING_LG)
    .backgroundColor(AppColors.CARD_BG)
    .borderRadius(20)
    .margin({ top: 14 })
    .shadow({ radius: 10, color: '#00000012', offsetY: 4 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildTimelineItem(node: TimelineNodeCard, index: number) {
    Column() {
      Row() {
        Text(node.date)
          .fontSize(AppDimens.FONT_SM)
          .fontColor(AppColors.TEXT_HINT)
          .backgroundColor(AppColors.BACKGROUND)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(12)

        Blank()

        if (node.photoCount > 0) {
          Text(`${node.photoCount} 张照片`)
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.PRIMARY)
            .backgroundColor(AppColors.PRIMARY + '12')
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .borderRadius(12)
        }
      }
      .width('100%')

      Text(node.title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.TEXT_PRIMARY)
        .width('100%')
        .margin({ top: 12 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(node.place)
        .fontSize(AppDimens.FONT_SM)
        .fontColor(AppColors.TEXT_SECONDARY)
        .lineHeight(21)
        .width('100%')
        .margin({ top: 6 })
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (node.summary.length > 0 && node.summary !== node.title) {
        Text(node.summary)
          .fontSize(AppDimens.FONT_SM)
          .fontColor(AppColors.TEXT_HINT)
          .lineHeight(20)
          .width('100%')
          .margin({ top: 8 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      if (node.mood.length > 0 || node.tags.length > 0) {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          if (node.mood.length > 0) {
            Text(node.mood)
              .fontSize(AppDimens.FONT_SM)
              .backgroundColor('#FFF3E8')
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .borderRadius(12)
              .margin({ right: 8, top: 10, bottom: 2 })
          }

          ForEach(node.tags.slice(0, 3), (tag: string) => {
            Text(`#${tag}`)
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.PRIMARY)
              .backgroundColor(AppColors.PRIMARY + '12')
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .borderRadius(12)
              .margin({ right: 8, top: 10, bottom: 2 })
          })
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor(AppColors.CARD_BG)
    .borderRadius(18)
    .border({ width: 1, color: '#EEF2F8' })
    .shadow({ radius: 4, color: '#0000000A', offsetY: 2 })
    .margin({ bottom: index < this.timelineNodes.length - 1 ? 10 : 0 })
    .onClick(() => {
      router.pushUrl({
        url: RouterUrls.NODE_DETAIL,
        params: { nodeId: node.id } as RouterParam
      })
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
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
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
                Text('正在整理路线内容...')
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(AppColors.TEXT_HINT)
                  .margin({ top: 12 })
              }
              .width('100%')
              .height(232)
              .justifyContent(FlexAlign.Center)
              .backgroundColor(AppColors.CARD_BG)
              .borderRadius(24)
            }
            if (!this.isLoading) {
              this.buildRouteHero()
            }

            if (!this.isLoading) {
              this.buildTripSummary()
            }

            if (!this.isLoading) {
              Row({ space: 12 }) {
                Button('播放路线')
                  .layoutWeight(1)
                  .height(46)
                  .fontSize(AppDimens.FONT_MD)
                  .backgroundColor(AppColors.PRIMARY)
                  .borderRadius(16)
                  .onClick(() => {
                    router.pushUrl({
                      url: RouterUrls.TRIP_REPLAY,
                      params: { tripId: this.tripId } as RouterParam
                    })
                  })
                Button('分享路线')
                  .layoutWeight(1)
                  .height(46)
                  .fontSize(AppDimens.FONT_MD)
                  .backgroundColor('#FF8C00')
                  .borderRadius(16)
                  .onClick(() => {
                    router.pushUrl({
                      url: RouterUrls.SHARE,
                      params: { tripId: this.tripId } as RouterParam
                    })
                  })
              }
              .width('100%')
              .margin({ top: 16 })

              Column() {
                Row() {
                  Column() {
                    Text('路线节点')
                      .fontSize(AppDimens.FONT_LG)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(AppColors.TEXT_PRIMARY)
                    Text('按顺序查看这次旅行的每一站')
                      .fontSize(AppDimens.FONT_SM)
                      .fontColor(AppColors.TEXT_HINT)
                      .margin({ top: 6 })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  Text(`${this.timelineNodes.length} 个节点`)
                    .fontSize(AppDimens.FONT_SM)
                    .fontColor(AppColors.TEXT_SECONDARY)
                    .backgroundColor(AppColors.BACKGROUND)
                    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                    .borderRadius(14)
                }
                .width('100%')

                if (this.timelineNodes.length === 0) {
                  Column() {
                    Text('这条路线还没有节点')
                      .fontSize(AppDimens.FONT_MD)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(AppColors.TEXT_PRIMARY)
                    Text('添加节点后，这里会按时间顺序展示路线内容。')
                      .fontSize(AppDimens.FONT_SM)
                      .fontColor(AppColors.TEXT_HINT)
                      .margin({ top: 8 })
                  }
                  .width('100%')
                  .padding({ top: 28, bottom: 12 })
                  .alignItems(HorizontalAlign.Start)
                } else {
                  Column() {
                    ForEach(this.timelineNodes, (node: TimelineNodeCard, index: number) => {
                      this.buildTimelineItem(node, index)
                    })
                  }
                  .width('100%')
                  .margin({ top: 14 })
                }
              }
              .width('100%')
              .padding(AppDimens.PADDING_MD)
              .margin({ top: 16 })
              .backgroundColor(AppColors.CARD_BG)
              .borderRadius(20)
              .shadow({ radius: 8, color: '#0000000D', offsetY: 3 })
            }
          }
          .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 12, bottom: 24 })
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
