import { router } from '@kit.ArkUI'
import { MapComponent, mapCommon, map } from '@kit.MapKit'
import { AsyncCallback } from '@kit.BasicServicesKit'
import { AppColors, AppDimens, RouterUrls } from '../common/Constants'
import { MapNodeInfo, RouterParam } from '../model/DataModels'

/**
 * 地图主页 Tab 内容视图
 * 使用 HarmonyOS Map Kit 展示真实地图 + 记忆节点 Marker
 */
@Component
export struct MapHomeView {
  @State showFilter: boolean = false
  @State selectedFilterTime: string = '全部'
  @State selectedFilterTag: string = '全部'
  @State mapReady: boolean = false

  // 模拟记忆节点数据（真实坐标）
  private mockNodes: MapNodeInfo[] = [
    new MapNodeInfo('1', '深圳湾日落', '深圳湾公园', 22.5268, 113.9455),
    new MapNodeInfo('2', '世界之窗一日游', '世界之窗', 22.5348, 113.9735),
    new MapNodeInfo('3', '校园春色', '南方科技大学', 22.5965, 113.9785),
  ]

  // 地图配置：默认中心为深圳
  private mapOptions: mapCommon.MapOptions = {
    position: {
      target: { latitude: 22.55, longitude: 113.96 },
      zoom: 12
    }
  }

  private mapController?: map.MapComponentController
  private markers: map.Marker[] = []

  // 节点预览卡片状态
  @State previewVisible: boolean = false
  @State previewNodeId: string = ''
  @State previewTitle: string = ''
  @State previewPoi: string = ''

  private mapCallback: AsyncCallback<map.MapComponentController> = async (err, controller) => {
    if (!err && controller) {
      this.mapController = controller
      this.mapReady = true
      await this.addMarkers()
      this.setupMarkerClickListener()
    }
  }

  /** 在地图上添加所有记忆节点 Marker */
  private async addMarkers(): Promise<void> {
    if (!this.mapController) {
      return
    }
    for (const node of this.mockNodes) {
      let markerOptions: mapCommon.MarkerOptions = {
        position: { latitude: node.latitude, longitude: node.longitude },
        rotation: 0,
        visible: true,
        zIndex: 0,
        alpha: 1,
        anchorU: 0.5,
        anchorV: 1,
        clickable: true,
        draggable: false,
        flat: false
      }
      let marker = await this.mapController.addMarker(markerOptions)
      marker.setTitle(node.title)
      marker.setSnippet(node.poiName)
      this.markers.push(marker)
    }
  }

  /** 监听 Marker 点击事件，弹出预览卡片 */
  private setupMarkerClickListener(): void {
    if (!this.mapController) {
      return
    }
    this.mapController.on('markerClick', (marker: map.Marker) => {
      const position = marker.getPosition()
      for (const node of this.mockNodes) {
        if (Math.abs(node.latitude - position.latitude) < 0.0001 &&
          Math.abs(node.longitude - position.longitude) < 0.0001) {
          this.previewNodeId = node.id
          this.previewTitle = node.title
          this.previewPoi = node.poiName
          this.previewVisible = true
          break
        }
      }
      return true
    })
  }

  /** 飞回到所有节点的中心视野 */
  private flyToCenter(): void {
    if (!this.mapController) {
      return
    }
    let cameraUpdate = map.newCameraPosition({
      target: { latitude: 22.55, longitude: 113.96 },
      zoom: 12
    })
    this.mapController.animateCamera(cameraUpdate, 500)
  }

  build() {
    Stack() {
      // 真实地图组件
      MapComponent({ mapOptions: this.mapOptions, mapCallback: this.mapCallback })
        .width('100%')
        .height('100%')

      // 搜索栏 (顶部浮动)
      Row() {
        Row() {
          Text('🔍')
            .fontSize(16)
          Text('搜索地点、标签...')
            .fontSize(AppDimens.FONT_MD)
            .fontColor(AppColors.TEXT_HINT)
            .margin({ left: 8 })
        }
        .layoutWeight(1)
        .height(40)
        .padding({ left: 12, right: 12 })
        .backgroundColor(AppColors.CARD_BG)
        .borderRadius(20)
        .shadow({ radius: 4, color: '#0000001A', offsetY: 2 })

        Text('筛选')
          .fontSize(AppDimens.FONT_MD)
          .fontColor(this.showFilter ? AppColors.CARD_BG : AppColors.PRIMARY)
          .backgroundColor(this.showFilter ? AppColors.PRIMARY : AppColors.CARD_BG)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .borderRadius(20)
          .margin({ left: 8 })
          .shadow({ radius: 4, color: '#0000001A', offsetY: 2 })
          .onClick(() => { this.showFilter = !this.showFilter })
      }
      .width('100%')
      .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 8 })
      .position({ x: 0, y: 0 })

      // 筛选面板
      if (this.showFilter) {
        Column() {
          Text('时间范围')
            .fontSize(AppDimens.FONT_SM)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_PRIMARY)
          Row({ space: 8 }) {
            ForEach(['全部', '近7天', '近30天', '近一年'], (label: string) => {
              Text(label)
                .fontSize(AppDimens.FONT_SM)
                .fontColor(this.selectedFilterTime === label ? AppColors.CARD_BG : AppColors.TEXT_SECONDARY)
                .backgroundColor(this.selectedFilterTime === label ? AppColors.PRIMARY : AppColors.BACKGROUND)
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .borderRadius(14)
                .onClick(() => { this.selectedFilterTime = label })
            })
          }
          .margin({ top: 8 })

          Text('标签')
            .fontSize(AppDimens.FONT_SM)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_PRIMARY)
            .margin({ top: 12 })
          Row({ space: 8 }) {
            ForEach(['全部', '旅行', '美食', '风景', '打卡'], (label: string) => {
              Text(label)
                .fontSize(AppDimens.FONT_SM)
                .fontColor(this.selectedFilterTag === label ? AppColors.CARD_BG : AppColors.TEXT_SECONDARY)
                .backgroundColor(this.selectedFilterTag === label ? AppColors.PRIMARY : AppColors.BACKGROUND)
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .borderRadius(14)
                .onClick(() => { this.selectedFilterTag = label })
            })
          }
          .margin({ top: 8 })
        }
        .width('100%')
        .padding(AppDimens.PADDING_MD)
        .backgroundColor(AppColors.CARD_BG)
        .borderRadius({ bottomLeft: AppDimens.RADIUS_MD, bottomRight: AppDimens.RADIUS_MD })
        .shadow({ radius: 4, color: '#0000001A', offsetY: 4 })
        .position({ x: 0, y: 56 })
        .alignItems(HorizontalAlign.Start)
      }

      // 右下角操作按钮
      Column({ space: 12 }) {
        Button('◎')
          .width(44)
          .height(44)
          .fontSize(20)
          .fontColor(AppColors.PRIMARY)
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(22)
          .shadow({ radius: 4, color: '#0000001A', offsetY: 2 })
          .onClick(() => this.flyToCenter())

        Button('+')
          .width(52)
          .height(52)
          .fontSize(24)
          .fontColor(AppColors.CARD_BG)
          .backgroundColor(AppColors.PRIMARY)
          .borderRadius(26)
          .shadow({ radius: 6, color: '#1890FF66', offsetY: 3 })
          .onClick(() => {
            router.pushUrl({ url: RouterUrls.NODE_EDIT })
          })
      }
      .position({ x: '80%', y: '60%' })

      // 底部节点预览卡片
      if (this.previewVisible) {
        Column() {
          Column()
            .width('100%')
            .layoutWeight(1)
            .onClick(() => { this.previewVisible = false })

          Row() {
            Column() {
              Text('📷')
                .fontSize(24)
            }
            .width(64)
            .height(64)
            .backgroundColor(AppColors.BACKGROUND)
            .borderRadius(AppDimens.RADIUS_SM)
            .justifyContent(FlexAlign.Center)

            Column() {
              Text(this.previewTitle)
                .fontSize(AppDimens.FONT_LG)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppColors.TEXT_PRIMARY)
              Text('📍 ' + this.previewPoi)
                .fontSize(AppDimens.FONT_SM)
                .fontColor(AppColors.TEXT_SECONDARY)
                .margin({ top: 4 })
              Text('点击查看详情 >')
                .fontSize(AppDimens.FONT_SM)
                .fontColor(AppColors.PRIMARY)
                .margin({ top: 4 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 12 })
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius({ topLeft: AppDimens.RADIUS_LG, topRight: AppDimens.RADIUS_LG })
          .shadow({ radius: 8, color: '#0000001A', offsetY: -2 })
          .onClick(() => {
            this.previewVisible = false
            router.pushUrl({
              url: RouterUrls.NODE_DETAIL,
              params: { nodeId: this.previewNodeId } as RouterParam
            })
          })
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
  }
}
