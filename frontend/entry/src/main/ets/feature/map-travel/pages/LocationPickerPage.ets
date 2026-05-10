import { router, promptAction } from '@kit.ArkUI'
import { MapComponent, mapCommon, map, site } from '@kit.MapKit'
import { AsyncCallback } from '@kit.BasicServicesKit'
import {
  AppColors,
  AppDimens,
  getStoredPreferredMapCenter,
  logger,
  requestCurrentLocation,
  savePreferredMapCenter
} from '../../../common'

interface SearchLocation {
  name: string
  address: string
  latitude: number
  longitude: number
}

interface SiteLike {
  name?: string
  formatAddress?: string
  location?: mapCommon.LatLng
}

interface ReverseGeocodePoiLike {
  name?: string
}

interface ReverseGeocodeResultLike {
  addressDescription?: string
  pois?: ReverseGeocodePoiLike[]
}

interface SearchByTextResultLike {
  sites?: SiteLike[]
}

@Entry
@Component
struct LocationPickerPage {
  @StorageLink('appThemeVersion') themeVersion: number = 0
  @State selectedLat: number = 0
  @State selectedLng: number = 0
  @State hasSelected: boolean = false
  @State poiName: string = ''
  @State searchKeyword: string = ''
  @State searchResults: SearchLocation[] = []
  @State isSearching: boolean = false
  @State isLocating: boolean = false

  private readonly defaultCenter: mapCommon.LatLng = this.getInitialCenter()
  private searchToken: number = 0

  private mapOptions: mapCommon.MapOptions = {
    position: {
      target: this.defaultCenter,
      zoom: 12
    }
  }

  private mapController?: map.MapComponentController
  private currentMarker?: map.Marker

  private mapCallback: AsyncCallback<map.MapComponentController> = async (err, controller) => {
    if (!err && controller) {
      this.mapController = controller
      this.setupMapClickListener()
      await this.applyStoredCenter()
    }
  }

  private getInitialCenter(): mapCommon.LatLng {
    const preferred = getStoredPreferredMapCenter()
    return {
      latitude: preferred.latitude,
      longitude: preferred.longitude
    }
  }

  private async applyStoredCenter(): Promise<void> {
    if (!this.mapController || this.hasSelected) {
      return
    }
    const preferred = getStoredPreferredMapCenter()
    const cameraUpdate = map.newCameraPosition({
      target: { latitude: preferred.latitude, longitude: preferred.longitude },
      zoom: 12
    })
    this.mapController.animateCamera(cameraUpdate, 300)
  }

  private normalizeText(value: string): string {
    return value.trim().toLowerCase()
  }

  private getSearchCenter(): mapCommon.LatLng {
    if (this.hasSelected) {
      return { latitude: this.selectedLat, longitude: this.selectedLng }
    }
    const preferred = getStoredPreferredMapCenter()
    return {
      latitude: preferred.latitude,
      longitude: preferred.longitude
    }
  }

  private formatLocationLabel(name: string, address: string): string {
    const trimmedName = name.trim()
    const trimmedAddress = address.trim()
    if (trimmedName.length === 0) {
      return trimmedAddress
    }
    if (trimmedAddress.length === 0) {
      return trimmedName
    }
    return `${trimmedName} · ${trimmedAddress}`
  }

  private mapSiteToSearchLocation(item: SiteLike): SearchLocation | null {
    if (!item.location) {
      return null
    }
    return {
      name: item.name ?? '未知地点',
      address: item.formatAddress ?? item.name ?? '',
      latitude: item.location.latitude,
      longitude: item.location.longitude
    }
  }

  private getReverseGeocodeLabel(result: ReverseGeocodeResultLike, latitude: number, longitude: number): string {
    const firstPoi = result.pois && result.pois.length > 0 ? result.pois[0] : undefined
    if (firstPoi?.name) {
      return this.formatLocationLabel(firstPoi.name, result.addressDescription ?? '')
    }
    if (result.addressDescription && result.addressDescription.trim().length > 0) {
      return result.addressDescription
    }
    return `${latitude.toFixed(4)}, ${longitude.toFixed(4)}`
  }

  private async reverseGeocodeLocation(latitude: number, longitude: number): Promise<string> {
    try {
      const result = await site.reverseGeocode(this.getUIContext().getHostContext(), {
        location: { latitude, longitude },
        language: 'zh-CN',
        radius: 200
      }) as ReverseGeocodeResultLike
      return this.getReverseGeocodeLabel(result, latitude, longitude)
    } catch (error) {
      logger.warn('LocationPickerPage', `reverseGeocode failed: ${JSON.stringify(error)}`)
      promptAction.showToast({ message: '地址解析失败，已保留坐标选点' })
      return `${latitude.toFixed(4)}, ${longitude.toFixed(4)}`
    }
  }

  private async searchByKeyword(keyword: string): Promise<void> {
    const currentToken = ++this.searchToken
    this.isSearching = true
    try {
      const result = await site.searchByText(this.getUIContext().getHostContext(), {
        query: keyword,
        location: this.getSearchCenter(),
        radius: 10000,
        language: 'zh-CN'
      }) as SearchByTextResultLike
      if (currentToken !== this.searchToken) {
        return
      }
      const sites = result.sites ?? []
      const mapped: SearchLocation[] = []
      for (let index = 0; index < sites.length; index++) {
        const item = this.mapSiteToSearchLocation(sites[index])
        if (item) {
          mapped.push(item)
        }
        if (mapped.length >= 8) {
          break
        }
      }
      this.searchResults = mapped
    } catch (error) {
      if (currentToken !== this.searchToken) {
        return
      }
      logger.warn('LocationPickerPage', `searchByText failed: ${JSON.stringify(error)}`)
      this.searchResults = []
      if (this.shouldShowSearchFailureToast(error as Object)) {
        promptAction.showToast({ message: '地点搜索失败，请稍后重试' })
      }
    } finally {
      if (currentToken === this.searchToken) {
        this.isSearching = false
      }
    }
  }

  private shouldShowSearchFailureToast(error: Object): boolean {
    const serialized = JSON.stringify(error)
    return !serialized.includes('1002603001')
  }

  private tryParseCoordinateKeyword(keyword: string): SearchLocation | null {
    const matched = keyword.match(/^\s*(-?\d+(\.\d+)?)\s*[,，]\s*(-?\d+(\.\d+)?)\s*$/)
    if (!matched) {
      return null
    }
    const latitude = Number(matched[1])
    const longitude = Number(matched[3])
    if (Number.isNaN(latitude) || Number.isNaN(longitude)) {
      return null
    }
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
      return null
    }
    return {
      name: 'Coordinate Input',
      address: `${latitude.toFixed(6)}, ${longitude.toFixed(6)}`,
      latitude,
      longitude
    }
  }

  private handleSearchInputChange(value: string): void {
    this.searchKeyword = value
    const keyword = this.normalizeText(value)
    this.searchToken += 1
    this.isSearching = false
    if (keyword.length === 0) {
      this.searchResults = []
      return
    }

    const coordinateMatch = this.tryParseCoordinateKeyword(keyword)
    if (coordinateMatch) {
      this.searchResults = [coordinateMatch]
      return
    }

    this.searchByKeyword(value.trim())
  }

  private async selectSearchResult(item: SearchLocation): Promise<void> {
    this.searchKeyword = item.name
    this.searchResults = []
    this.searchToken += 1
    this.isSearching = false
    await this.selectLocation(item.latitude, item.longitude, this.formatLocationLabel(item.name, item.address))
  }

  private async selectLocation(latitude: number, longitude: number, label: string, animate: boolean = true): Promise<void> {
    this.selectedLat = latitude
    this.selectedLng = longitude
    this.poiName = label
    this.hasSelected = true

    if (!this.mapController) {
      return
    }

    if (this.currentMarker) {
      try {
        this.currentMarker.remove()
      } catch (_) {}
      this.currentMarker = undefined
    }

    const markerOptions: mapCommon.MarkerOptions = {
      position: { latitude, longitude },
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
    if (animate) {
      const cameraUpdate = map.newCameraPosition({
        target: { latitude, longitude },
        zoom: 14
      })
      this.mapController.animateCamera(cameraUpdate, 300)
    }
  }

  private async recenterToCurrentLocation(): Promise<void> {
    if (this.isLocating) {
      return
    }
    const hostContext = this.getUIContext().getHostContext()
    if (!hostContext) {
      promptAction.showToast({ message: '当前无法获取页面上下文' })
      return
    }
    this.isLocating = true
    try {
      const current = await requestCurrentLocation(hostContext)
      if (!current) {
        promptAction.showToast({ message: '定位失败，已保留当前地图位置' })
        return
      }
      const label = `${current.latitude.toFixed(4)}, ${current.longitude.toFixed(4)}`
      savePreferredMapCenter(current.latitude, current.longitude, '当前位置', 'device')
      await this.selectLocation(current.latitude, current.longitude, label)
    } finally {
      this.isLocating = false
    }
  }

  private setupMapClickListener(): void {
    if (!this.mapController) {
      return
    }
    this.mapController.on('mapClick', async (position: mapCommon.LatLng) => {
      const label = await this.reverseGeocodeLocation(position.latitude, position.longitude)
      await this.selectLocation(position.latitude, position.longitude, label)
    })
  }

  private handleConfirm(): void {
    AppStorage.setOrCreate('pickedLatitude', this.selectedLat)
    AppStorage.setOrCreate('pickedLongitude', this.selectedLng)
    AppStorage.setOrCreate('pickedPoiName', this.poiName)
    AppStorage.setOrCreate('locationPicked', true)
    savePreferredMapCenter(this.selectedLat, this.selectedLng, this.poiName, 'picked')
    router.back()
  }

  build() {
    Stack() {
      MapComponent({ mapOptions: this.mapOptions, mapCallback: this.mapCallback })
        .width('100%')
        .height('100%')

      Column() {
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

        Row() {
          TextInput({ placeholder: '搜索地点名称', text: this.searchKeyword })
            .layoutWeight(1)
            .height(40)
            .fontColor(AppColors.INPUT_TEXT)
            .placeholderColor(AppColors.INPUT_PLACEHOLDER)
            .caretColor(AppColors.INPUT_CARET)
            .backgroundColor(AppColors.INPUT_BG)
            .borderRadius(20)
            .padding({ left: 14, right: 14 })
            .onChange((value: string) => this.handleSearchInputChange(value))
          if (this.searchKeyword.length > 0) {
            Text('清空')
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.PRIMARY)
              .margin({ left: 10 })
              .onClick(() => this.handleSearchInputChange(''))
          }
        }
        .width('100%')
        .margin({ top: 10 })

        if (this.isSearching) {
          Text('搜索中...')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_SECONDARY)
            .backgroundColor(AppColors.CARD_BG)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(AppDimens.RADIUS_SM)
            .margin({ top: 8 })
            .alignSelf(ItemAlign.Start)
        }

        if (!this.isSearching && this.searchKeyword.trim().length > 0 && this.searchResults.length === 0) {
          Text('未找到相关地点，可继续输入坐标或直接点地图')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_SECONDARY)
            .backgroundColor(AppColors.CARD_BG)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(AppDimens.RADIUS_SM)
            .margin({ top: 8 })
            .alignSelf(ItemAlign.Start)
        }

        if (this.searchResults.length > 0) {
          Column() {
            ForEach(this.searchResults, (item: SearchLocation) => {
              Column() {
                Text(item.name)
                  .fontSize(AppDimens.FONT_MD)
                  .fontColor(AppColors.TEXT_PRIMARY)
                  .width('100%')
                Text(item.address)
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(AppColors.TEXT_SECONDARY)
                  .width('100%')
                  .margin({ top: 4 })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .onClick(() => this.selectSearchResult(item))
            })
          }
          .width('100%')
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_SM)
          .margin({ top: 8 })
          .shadow({ radius: 6, color: '#0000001A', offsetY: 2 })
        }
      }
      .width('100%')
      .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 12 })
      .position({ x: 0, y: 0 })

      Column() {
        Button(this.isLocating ? '定位中...' : '⌖')
          .width(48)
          .height(48)
          .fontSize(this.isLocating ? AppDimens.FONT_SM : 24)
          .fontColor(AppColors.PRIMARY)
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(24)
          .shadow({ radius: 4, color: '#0000001A', offsetY: 2 })
          .enabled(!this.isLocating)
          .onClick(() => this.recenterToCurrentLocation())
      }
      .position({ x: '82%', y: '72%' })

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
              .maxLines(2)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Button('确认选点')
            .fontSize(AppDimens.FONT_MD)
            .fontColor(AppColors.TEXT_ON_PRIMARY)
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
