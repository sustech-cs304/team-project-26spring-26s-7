import { router, promptAction } from '@kit.ArkUI'
import { MapComponent, mapCommon, map, site } from '@kit.MapKit'
import { AsyncCallback } from '@kit.BasicServicesKit'
import { AppColors, AppDimens, RouterUrls, getDataService, logger } from '../../../common'
import { MapNodeInfo, RouterParam } from '../../../common'
import type { MemoryNode } from '../../../common'

interface LoadedNodeData {
  id: string
  title: string
  poiName: string
  latitude: number
  longitude: number
  createdAt: number
  tags: string[]
  coverPhoto: string
}

interface HomeSearchResult {
  id: string
  title: string
  subtitle: string
  latitude: number
  longitude: number
  type: 'node' | 'site'
  coverPhoto?: string
}

interface SiteLike {
  name?: string
  formatAddress?: string
  location?: mapCommon.LatLng
}

interface SearchByTextResultLike {
  sites?: SiteLike[]
}

const DEFAULT_MAP_CENTER: mapCommon.LatLng = {
  latitude: 22.55,
  longitude: 113.96
}

/**
 * 地图主页 Tab 内容视图
 * 使用 HarmonyOS Map Kit 展示真实地图 + 记忆节点 Marker
 */
@Component
export struct MapHomeView {
  @State showFilter: boolean = false
  @State selectedFilterTime: string = '全部'
  @State selectedFilterTag: string = '全部'
  @State isLoadingNodes: boolean = false
  @State mapNodes: MapNodeInfo[] = []
  @State searchKeyword: string = ''
  @State searchResults: HomeSearchResult[] = []
  @State isSearching: boolean = false
  @State hasSelectedSearchResult: boolean = false
  @State selectedSearchType: string = ''
  @State selectedSearchTitle: string = ''
  @State selectedSearchSubtitle: string = ''
  @State selectedSearchLatitude: number = 0
  @State selectedSearchLongitude: number = 0
  @Watch('onTravelDataVersionChange')
  @StorageLink('travelDataVersion') travelDataVersion: number = 0
  @Watch('onTabRefresh')
  @StorageLink('tabRefreshToken') tabRefreshToken: number = 0
  @StorageLink('activeTabIndex') activeTabIndex: number = 0

  // 地图配置：默认中心为深圳
  private mapOptions: mapCommon.MapOptions = {
    position: {
      target: DEFAULT_MAP_CENTER,
      zoom: 12
    }
  }

  private mapController?: map.MapComponentController
  private markerNodeIds: string[] = []
  private mapMarkers: map.Marker[] = []
  private selectedSearchMarker?: map.Marker
  private loadedNodes: LoadedNodeData[] = []
  private dataService = getDataService()
  private searchToken: number = 0

  // 节点预览卡片状态
  @State previewVisible: boolean = false
  @State previewNodeId: string = ''
  @State previewTitle: string = ''
  @State previewPoi: string = ''
  @State previewPhoto: string = ''

  private mapCallback: AsyncCallback<map.MapComponentController> = async (err, controller) => {
    if (!err && controller) {
      this.mapController = controller
      await this.syncMarkers()
      this.setupMarkerClickListener()
      this.setupMapLongClickListener()
    }
  }

  aboutToAppear(): void {
    this.loadNodes()
  }

  private onTravelDataVersionChange(): void {
    this.loadNodes()
  }

  private onTabRefresh(): void {
    if (this.activeTabIndex === 0) {
      this.loadNodes()
    }
  }

  private async loadNodes(): Promise<void> {
    this.isLoadingNodes = true
    try {
      const travels = await this.dataService.getAllTravels()
      const nodes: LoadedNodeData[] = []
      for (const travel of travels) {
        const tripNodes = await this.dataService.getNodesByTravelId(travel.id)
        for (const node of tripNodes) {
          nodes.push(this.mapNode(node))
        }
      }

      this.loadedNodes = nodes
      this.applyFilters()
      await this.syncMarkers()
    } catch (err) {
      promptAction.showToast({ message: '加载地图节点失败' })
    } finally {
      this.isLoadingNodes = false
    }
  }

  private mapNode(node: MemoryNode): LoadedNodeData {
    return {
      id: node.id,
      title: node.title,
      poiName: node.poiName,
      latitude: node.latitude,
      longitude: node.longitude,
      createdAt: node.createdAt,
      tags: node.tags,
      coverPhoto: node.photos.length > 0 ? node.photos[0] : ''
    }
  }

  private findLoadedNodeById(nodeId: string): LoadedNodeData | undefined {
    return this.loadedNodes.find((node: LoadedNodeData) => node.id === nodeId)
  }

  private getSearchCenter(): mapCommon.LatLng {
    if (this.mapNodes.length > 0) {
      return {
        latitude: this.mapNodes[0].latitude,
        longitude: this.mapNodes[0].longitude
      }
    }
    return DEFAULT_MAP_CENTER
  }

  private normalizeText(value: string): string {
    return value.trim().toLowerCase()
  }

  private formatSearchSubtitle(primary: string, secondary: string): string {
    const first = primary.trim()
    const second = secondary.trim()
    if (first.length === 0) {
      return second
    }
    if (second.length === 0) {
      return first
    }
    return `${first} · ${second}`
  }

  private matchesKeyword(node: LoadedNodeData, keyword: string): boolean {
    const haystack = `${node.title} ${node.poiName} ${node.tags.join(' ')}`.toLowerCase()
    return haystack.includes(keyword)
  }

  private buildNodeSearchResults(keyword: string): HomeSearchResult[] {
    const results: HomeSearchResult[] = []
    for (const node of this.loadedNodes) {
      if (!this.matchesKeyword(node, keyword)) {
        continue
      }
      results.push({
        id: node.id,
        title: node.title,
        subtitle: node.poiName,
        latitude: node.latitude,
        longitude: node.longitude,
        type: 'node',
        coverPhoto: node.coverPhoto
      })
      if (results.length >= 8) {
        break
      }
    }
    return results
  }

  private buildSiteSearchResult(item: SiteLike, index: number): HomeSearchResult | null {
    if (!item.location) {
      return null
    }
    const title = item.name ?? '未知地点'
    const subtitle = item.formatAddress ?? item.name ?? ''
    return {
      id: `site-${index}-${item.location.latitude}-${item.location.longitude}`,
      title,
      subtitle,
      latitude: item.location.latitude,
      longitude: item.location.longitude,
      type: 'site'
    }
  }

  private shouldShowSearchFailureToast(error: Object): boolean {
    const serialized = JSON.stringify(error)
    return !serialized.includes('1002603001')
  }

  private clearSelectedSearchState(): void {
    this.hasSelectedSearchResult = false
    this.selectedSearchType = ''
    this.selectedSearchTitle = ''
    this.selectedSearchSubtitle = ''
    this.selectedSearchLatitude = 0
    this.selectedSearchLongitude = 0
    this.previewVisible = false
    this.previewNodeId = ''
    this.previewTitle = ''
    this.previewPoi = ''
    this.previewPhoto = ''
    if (this.selectedSearchMarker) {
      try {
        this.selectedSearchMarker.remove()
      } catch (_) {}
      this.selectedSearchMarker = undefined
    }
  }

  private async updateSelectedSearchMarker(latitude: number, longitude: number, title: string, subtitle: string): Promise<void> {
    if (!this.mapController) {
      return
    }
    if (this.selectedSearchMarker) {
      try {
        this.selectedSearchMarker.remove()
      } catch (_) {}
      this.selectedSearchMarker = undefined
    }
    const marker = await this.mapController.addMarker({
      position: { latitude, longitude },
      icon: $r('app.media.search_destination_marker'),
      rotation: 0,
      visible: true,
      zIndex: 3,
      alpha: 1,
      anchorU: 0.5,
      anchorV: 1,
      clickable: true,
      draggable: false,
      flat: false
    })
    marker.setTitle(title)
    marker.setSnippet(subtitle)
    this.selectedSearchMarker = marker
  }

  private async handleSearchInputChange(value: string): Promise<void> {
    this.searchKeyword = value
    this.clearSelectedSearchState()
    const keyword = this.normalizeText(value)
    this.searchToken += 1
    this.isSearching = false
    if (keyword.length === 0) {
      this.searchResults = []
      return
    }

    const localResults = this.buildNodeSearchResults(keyword)
    this.searchResults = localResults
    await this.searchSites(value.trim(), localResults)
  }

  private async searchSites(keyword: string, localResults: HomeSearchResult[]): Promise<void> {
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
      const merged = [...localResults]
      const sites = result.sites ?? []
      for (let index = 0; index < sites.length; index++) {
        const mapped = this.buildSiteSearchResult(sites[index], index)
        if (!mapped) {
          continue
        }
        const duplicated = merged.some((item: HomeSearchResult) =>
          Math.abs(item.latitude - mapped.latitude) < 0.0001 &&
          Math.abs(item.longitude - mapped.longitude) < 0.0001
        )
        if (!duplicated) {
          merged.push(mapped)
        }
        if (merged.length >= 8) {
          break
        }
      }
      this.searchResults = merged
    } catch (error) {
      if (currentToken !== this.searchToken) {
        return
      }
      logger.warn('MapHomeView', `searchByText failed: ${JSON.stringify(error)}`)
      this.searchResults = localResults
      if (this.shouldShowSearchFailureToast(error as Object)) {
        promptAction.showToast({ message: '地点搜索失败，请稍后重试' })
      }
    } finally {
      if (currentToken === this.searchToken) {
        this.isSearching = false
      }
    }
  }

  private navigateToCreateNodeFromSearch(): void {
    if (!this.hasSelectedSearchResult) {
      return
    }
    const latitude = this.selectedSearchLatitude
    const longitude = this.selectedSearchLongitude
    const poiName = this.selectedSearchSubtitle.length > 0
      ? this.selectedSearchSubtitle
      : this.selectedSearchTitle
    this.clearSelectedSearchState()
    this.searchKeyword = ''
    this.searchResults = []
    router.pushUrl({
      url: RouterUrls.NODE_EDIT,
      params: {
        latitude,
        longitude,
        poiName
      } as RouterParam
    })
  }

  private async selectSearchResult(item: HomeSearchResult): Promise<void> {
    this.searchKeyword = item.title
    this.searchResults = []
    this.searchToken += 1
    this.isSearching = false
    this.previewVisible = false
    this.hasSelectedSearchResult = true
    this.selectedSearchType = item.type
    this.selectedSearchTitle = item.title
    this.selectedSearchSubtitle = item.subtitle
    this.selectedSearchLatitude = item.latitude
    this.selectedSearchLongitude = item.longitude

    if (!this.mapController) {
      return
    }

    if (item.type === 'site') {
      await this.updateSelectedSearchMarker(item.latitude, item.longitude, item.title,
        item.subtitle.length > 0 ? item.subtitle : item.title)
    } else if (this.selectedSearchMarker) {
      try {
        this.selectedSearchMarker.remove()
      } catch (_) {}
      this.selectedSearchMarker = undefined
    }

    const cameraUpdate = map.newCameraPosition({
      target: { latitude: item.latitude, longitude: item.longitude },
      zoom: 15
    })
    this.mapController.animateCamera(cameraUpdate, 400)

    if (item.type === 'node') {
      this.previewNodeId = item.id
      this.previewTitle = item.title
      this.previewPoi = item.subtitle
      this.previewPhoto = item.coverPhoto ?? ''
      this.previewVisible = true
    }
  }

  private getTimeThreshold(): number {
    const now = Date.now()
    if (this.selectedFilterTime === '近 7 天') {
      return now - 7 * 24 * 60 * 60 * 1000
    }
    if (this.selectedFilterTime === '近 30 天') {
      return now - 30 * 24 * 60 * 60 * 1000
    }
    if (this.selectedFilterTime === '近一年') {
      return now - 365 * 24 * 60 * 60 * 1000
    }
    return 0
  }

  private applyFilters(): void {
    const threshold = this.getTimeThreshold()
    const filteredNodes = this.loadedNodes.filter((node: LoadedNodeData) => {
      const matchesTime = threshold === 0 || node.createdAt >= threshold
      const matchesTag = this.selectedFilterTag === '全部' || node.tags.includes(this.selectedFilterTag)
      return matchesTime && matchesTag
    })

    this.mapNodes = filteredNodes.map((node: LoadedNodeData) =>
      new MapNodeInfo(node.id, node.title, node.poiName, node.latitude, node.longitude)
    )
  }

  /** 在地图上同步记忆节点 Marker */
  private async syncMarkers(): Promise<void> {
    if (!this.mapController) {
      return
    }

    // Re-render markers from source of truth to avoid stale cache causing missing pins.
    for (const marker of this.mapMarkers) {
      try {
        marker.remove()
      } catch (_) {}
    }
    this.mapMarkers = []
    this.markerNodeIds = []

    if (this.selectedSearchMarker) {
      try {
        this.selectedSearchMarker.remove()
      } catch (_) {}
      this.selectedSearchMarker = undefined
    }

    for (const node of this.mapNodes) {
      const markerPosition: mapCommon.LatLng = {
        latitude: node.latitude,
        longitude: node.longitude
      }
      const markerOptions: mapCommon.MarkerOptions = {
        position: markerPosition,
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
      const marker = await this.mapController.addMarker(markerOptions)
      marker.setTitle(node.title)
      marker.setSnippet(node.poiName)
      this.mapMarkers.push(marker)
      this.markerNodeIds.push(node.id)
    }

    if (this.hasSelectedSearchResult && this.selectedSearchType === 'site') {
      await this.updateSelectedSearchMarker(
        this.selectedSearchLatitude,
        this.selectedSearchLongitude,
        this.selectedSearchTitle,
        this.selectedSearchSubtitle.length > 0 ? this.selectedSearchSubtitle : this.selectedSearchTitle
      )
    }
  }

  /** 监听 Marker 点击事件，弹出预览卡片 */
  private setupMarkerClickListener(): void {
    if (!this.mapController) {
      return
    }
    this.mapController.on('markerClick', (marker: map.Marker) => {
      const position = marker.getPosition()
      if (this.hasSelectedSearchResult && this.selectedSearchType === 'site' &&
        Math.abs(this.selectedSearchLatitude - position.latitude) < 0.0001 &&
        Math.abs(this.selectedSearchLongitude - position.longitude) < 0.0001) {
        return true
      }
      for (const node of this.mapNodes) {
        if (Math.abs(node.latitude - position.latitude) < 0.0001 &&
          Math.abs(node.longitude - position.longitude) < 0.0001) {
          const loadedNode = this.findLoadedNodeById(node.id)
          this.previewNodeId = node.id
          this.previewTitle = node.title
          this.previewPoi = node.poiName
          this.previewPhoto = loadedNode ? loadedNode.coverPhoto : ''
          this.previewVisible = true
          break
        }
      }
      return true
    })
  }

  /** 监听地图长按，快捷创建节点并自动填入坐标 */
  private setupMapLongClickListener(): void {
    if (!this.mapController) {
      return
    }
    const navigateToNodeEdit = (position: mapCommon.LatLng): void => {
      router.pushUrl({
        url: RouterUrls.NODE_EDIT,
        params: {
          latitude: position.latitude,
          longitude: position.longitude
        } as RouterParam
      })
    }
    this.mapController.on('mapLongClick', navigateToNodeEdit)
  }

  /** 飞回到所有节点的中心视野 */
  private flyToCenter(): void {
    if (!this.mapController) {
      return
    }

    const target: mapCommon.LatLng = this.mapNodes.length > 0 ? {
      latitude: this.mapNodes[0].latitude,
      longitude: this.mapNodes[0].longitude
    } : DEFAULT_MAP_CENTER

    const cameraUpdate = map.newCameraPosition({
      target: target,
      zoom: 12
    })
    this.mapController.animateCamera(cameraUpdate, 500)
  }

  private updateFilters(timeLabel?: string, tagLabel?: string): void {
    if (timeLabel) {
      this.selectedFilterTime = timeLabel
    }
    if (tagLabel) {
      this.selectedFilterTag = tagLabel
    }
    this.applyFilters()
    this.syncMarkers()
  }

  build() {
    Stack() {
      // 真实地图组件
      MapComponent({ mapOptions: this.mapOptions, mapCallback: this.mapCallback })
        .width('100%')
        .height('100%')

      if (this.isLoadingNodes) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
          Text('正在加载地图节点...')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_HINT)
            .margin({ top: 12 })
        }
        .padding(16)
        .backgroundColor(AppColors.CARD_BG)
        .borderRadius(AppDimens.RADIUS_MD)
        .position({ x: '25%', y: '45%' })
      }

      // 搜索栏 (顶部浮动)
      Column() {
        Row() {
          TextInput({ placeholder: '搜索地点、标签...', text: this.searchKeyword })
            .layoutWeight(1)
            .height(40)
            .backgroundColor(AppColors.CARD_BG)
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

          if (this.hasSelectedSearchResult) {
            Text('用该地址新建记忆')
              .fontSize(AppDimens.FONT_MD)
              .fontColor(AppColors.CARD_BG)
              .backgroundColor(AppColors.PRIMARY)
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .borderRadius(20)
              .margin({ left: 8 })
              .shadow({ radius: 4, color: '#1890FF33', offsetY: 2 })
              .onClick(() => this.navigateToCreateNodeFromSearch())
          }

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

        if (!this.isSearching && !this.hasSelectedSearchResult && this.searchKeyword.trim().length > 0 && this.searchResults.length === 0) {
          Text('未找到相关地点或记忆')
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
            ForEach(this.searchResults, (item: HomeSearchResult) => {
              Column() {
                Text(item.title)
                  .fontSize(AppDimens.FONT_MD)
                  .fontColor(AppColors.TEXT_PRIMARY)
                  .width('100%')
                Text(item.subtitle)
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
            ForEach(['全部', '近 7 天', '近 30 天', '近一年'], (label: string) => {
              Text(label)
                .fontSize(AppDimens.FONT_SM)
                .fontColor(this.selectedFilterTime === label ? AppColors.CARD_BG : AppColors.TEXT_SECONDARY)
                .backgroundColor(this.selectedFilterTime === label ? AppColors.PRIMARY : AppColors.BACKGROUND)
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .borderRadius(14)
                .onClick(() => { this.updateFilters(label, undefined) })
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
                .onClick(() => { this.updateFilters(undefined, label) })
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

      // 右下角操作按钮（回到地图原点）
      Column({ space: 12 }) {
        Button() {
          Stack() {
            Text('⌖')
              .fontSize(32)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.PRIMARY)
          }
          .width('100%')
          .height('100%')
          .alignContent(Alignment.Center)
        }
        .width(48)
        .height(48)
        .backgroundColor(AppColors.CARD_BG)
        .borderRadius(24)
        .padding(0)
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
            Stack() {
              if (this.previewPhoto.length > 0) {
                Image(this.previewPhoto)
                  .width('100%')
                  .height('100%')
                  .objectFit(ImageFit.Cover)
              } else {
                Column() {
                  Text('📷')
                    .fontSize(24)
                }
                .width('100%')
                .height('100%')
                .justifyContent(FlexAlign.Center)
              }
            }
            .width(64)
            .height(64)
            .backgroundColor(AppColors.BACKGROUND)
            .borderRadius(AppDimens.RADIUS_SM)
            .clip(true)

            Column() {
              Text(this.previewTitle)
                .fontSize(AppDimens.FONT_LG)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppColors.TEXT_PRIMARY)
                .width('100%')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text('📍 ' + this.previewPoi)
                .fontSize(AppDimens.FONT_SM)
                .fontColor(AppColors.TEXT_SECONDARY)
                .margin({ top: 4 })
                .width('100%')
                .maxLines(2)
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
