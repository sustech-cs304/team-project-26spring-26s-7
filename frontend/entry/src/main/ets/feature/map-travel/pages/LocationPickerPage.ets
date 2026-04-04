import { router } from '@kit.ArkUI'
import { MapComponent, mapCommon, map } from '@kit.MapKit'
import { AsyncCallback } from '@kit.BasicServicesKit'
import { AppColors, AppDimens } from '../../../common'

/**
 * 地图选点页面
 * 用户点击地图放置标记，确认后将坐标通过 AppStorage 传回 NodeEditPage
 */
@Entry
@Component
struct LocationPickerPage {
  @State selectedLat: number = 0
  @State selectedLng: number = 0
  @State hasSelected: boolean = false
  @State poiName: string = ''

  private mapOptions: mapCommon.MapOptions = {
    position: {
      target: { latitude: 22.55, longitude: 113.96 },
      zoom: 12
    }
  }

  private mapController?: map.MapComponentController
  private currentMarker?: map.Marker

  private mapCallback: AsyncCallback<map.MapComponentController> = async (err, controller) => {
    if (!err && controller) {
      this.mapController = controller
      this.setupMapClickListener()
    }
  }

  /** 监听地图点击事件，放置/移动标记 */
  private setupMapClickListener(): void {
    if (!this.mapController) {
      return
    }
    this.mapController.on('mapClick', async (position: mapCommon.LatLng) => {
      this.selectedLat = position.latitude
      this.selectedLng = position.longitude
      this.poiName = position.latitude.toFixed(4) + ', ' + position.longitude.toFixed(4)
      this.hasSelected = true

      // 移除旧标记
      if (this.currentMarker) {
        this.currentMarker.remove()
        this.currentMarker = undefined
      }

      // 添加新标记
      if (this.mapController) {
        let markerOptions: mapCommon.MarkerOptions = {
          position: { latitude: position.latitude, longitude: position.longitude },
          rotation: 0,
          visible: true,
          zIndex: 0,
          alpha: 1,
          anchorU: 0.5,
          anchorV: 1,
          clickable: false,
          draggable: false,
          flat: false
        }
        this.currentMarker = await this.mapController.addMarker(markerOptions)
      }
    })
  }

  /** 确认选点，写入 AppStorage 并返回 */
  private handleConfirm(): void {
    AppStorage.setOrCreate('pickedLatitude', this.selectedLat)
    AppStorage.setOrCreate('pickedLongitude', this.selectedLng)
    AppStorage.setOrCreate('pickedPoiName', this.poiName)
    AppStorage.setOrCreate('locationPicked', true)
    router.back()
  }

  build() {
    Stack() {
      // 全屏地图
      MapComponent({ mapOptions: this.mapOptions, mapCallback: this.mapCallback })
        .width('100%')
        .height('100%')

      // 顶部导航栏
      Row() {
        Button('< 返回')
          .fontSize(AppDimens.FONT_MD)
          .fontColor(AppColors.TEXT_PRIMARY)
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_SM)
          .height(36)
          .padding({ left: 12, right: 12 })
          .shadow({ radius: 4, color: '#0000001A', offsetY: 2 })
          .onClick(() => router.back())

        Text('选择位置')
          .fontSize(AppDimens.FONT_LG)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_PRIMARY)
          .margin({ left: 12 })
          .backgroundColor(AppColors.CARD_BG)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(AppDimens.RADIUS_SM)
          .shadow({ radius: 4, color: '#0000001A', offsetY: 2 })
      }
      .width('100%')
      .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 12 })
      .position({ x: 0, y: 0 })

      // 提示文字（未选点时）
      if (!this.hasSelected) {
        Text('点击地图选择一个位置')
          .fontSize(AppDimens.FONT_MD)
          .fontColor(AppColors.CARD_BG)
          .backgroundColor('#00000066')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .borderRadius(20)
          .position({ x: '50%', y: '50%' })
          .translate({ x: '-50%' })
      }

      // 底部信息栏 + 确认按钮
      if (this.hasSelected) {
        Row() {
          Column() {
            Text('已选位置')
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_SECONDARY)
            Text(this.poiName)
              .fontSize(AppDimens.FONT_MD)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)
              .margin({ top: 4 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Button('确认选点')
            .fontSize(AppDimens.FONT_MD)
            .fontColor(AppColors.CARD_BG)
            .backgroundColor(AppColors.PRIMARY)
            .borderRadius(AppDimens.RADIUS_SM)
            .height(40)
            .padding({ left: 20, right: 20 })
            .onClick(() => this.handleConfirm())
        }
        .width('100%')
        .padding(AppDimens.PADDING_MD)
        .backgroundColor(AppColors.CARD_BG)
        .borderRadius({ topLeft: AppDimens.RADIUS_LG, topRight: AppDimens.RADIUS_LG })
        .shadow({ radius: 8, color: '#0000001A', offsetY: -2 })
        .position({ x: 0, y: '100%' })
        .translate({ y: '-100%' })
      }
    }
    .width('100%')
    .height('100%')
  }
}