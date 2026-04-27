import { router, promptAction } from '@kit.ArkUI'
import { MapComponent, mapCommon, map, site } from '@kit.MapKit'
import { AsyncCallback } from '@kit.BasicServicesKit'
import { image } from '@kit.ImageKit'
import { fileIo } from '@kit.CoreFileKit'
import { AppColors, AppDimens, RouterUrls, getDataService, logger, TravelSpecialValues } from '../../../common'
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
  photoCount: number
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

const MARKER_SIZE = 286
const SINGLE_INNER_R = 107
const SINGLE_OUTER_R = 116
const CLUSTER_INNER_R = 116
const CLUSTER_OUTER_R = 125
const TIP_HEIGHT = 50

interface PhotoData {
  buffer: ArrayBuffer
  width: number
  height: number
}

/**
 * 聚合图层参数 + 自定义图标绘制
 * BGRA_8888 buffer + 照片像素合成
 * 单节点 → 封面照片圆形裁剪 / 蓝色占位圆 + 白色描边
 * 聚合组 → 彩色圆形 + 白色描边
 */
class NodeClusterOverlayParams implements mapCommon.ClusterOverlayParams {
  clusterItems: mapCommon.ClusterItem[] = []
  distance: number = 50

  private nodeLookup: Map<string, LoadedNodeData[]> = new Map()
  private photoCache: Map<string, PhotoData> = new Map()

  constructor(
    clusterItems: mapCommon.ClusterItem[],
    distance: number,
    nodeLookup: Map<string, LoadedNodeData[]>,
    photoCache: Map<string, PhotoData>
  ) {
    this.clusterItems = clusterItems
    this.distance = distance
    this.nodeLookup = nodeLookup
    this.photoCache = photoCache
  }

  async getCustomIcon(clusterItems: mapCommon.ClusterItem[]): Promise<image.PixelMap> {
    const cx = MARKER_SIZE / 2

    if (clusterItems.length === 1) {
      // 水滴形：圆心贴顶，尖角在画布垂直中心 → 对准地图坐标
      const cy = SINGLE_OUTER_R
      const tipY = 2 * SINGLE_OUTER_R + TIP_HEIGHT
      const canvasW = MARKER_SIZE
      const canvasH = 2 * tipY
      const buffer = new ArrayBuffer(canvasW * canvasH * 4)
      const view = new Uint8Array(buffer)
      this.fillSingleIcon(view, canvasW, cx, cy, clusterItems[0], tipY)

      const pixelMap = await image.createPixelMap(buffer, {
        size: { width: canvasW, height: canvasH },
        pixelFormat: image.PixelMapFormat.BGRA_8888
      })
      return pixelMap
    } else {
      const size = MARKER_SIZE
      const cy = size / 2
      const buffer = new ArrayBuffer(size * size * 4)
      const view = new Uint8Array(buffer)
      this.fillClusterIcon(view, size, cx, cy, clusterItems.length)

      const pixelMap = await image.createPixelMap(buffer, {
        size: { width: size, height: size },
        pixelFormat: image.PixelMapFormat.BGRA_8888
      })
      return pixelMap
    }
  }

  // BGRA_8888 layout: view[idx]=B, [idx+1]=G, [idx+2]=R, [idx+3]=A
  // 参数语义为 R,G,B,A — 内部按 BGRA 顺序写入 buffer
  private setPixel(view: Uint8Array, idx: number, r: number, g: number, b: number, a: number): void {
    view[idx] = b
    view[idx + 1] = g
    view[idx + 2] = r
    view[idx + 3] = a
  }

  private fillSingleIcon(view: Uint8Array, canvasW: number, cx: number, cy: number,
    item: mapCommon.ClusterItem, tipY: number): void {
    const key = this.posKey(item.position.latitude, item.position.longitude)
    const nodes = this.nodeLookup.get(key)
    const coverPath = nodes && nodes.length > 0 ? nodes[0].coverPhoto : ''
    const photoData = coverPath.length > 0 ? this.photoCache.get(coverPath) : undefined

    const R = SINGLE_OUTER_R
    const d = tipY - cy
    const tangentY = cy + R * R / d
    const K = Math.sqrt(d * d - R * R)

    // 白色描边 + 尖角（只遍历内容区域 0 ~ tipY）
    for (let y = 0; y < tipY; y++) {
      for (let x = 0; x < canvasW; x++) {
        const dx = x - cx
        const dy = y - cy
        const dist = Math.sqrt(dx * dx + dy * dy)
        const idx = (y * canvasW + x) * 4

        if (dist > SINGLE_INNER_R && dist <= SINGLE_OUTER_R) {
          this.setPixel(view, idx, 0xFF, 0xFF, 0xFF, 0xFF)
        } else if (y > tangentY && y < tipY) {
          const halfW = R * (tipY - y) / K
          if (Math.abs(dx) <= halfW) {
            this.setPixel(view, idx, 0xFF, 0xFF, 0xFF, 0xFF)
          }
        }
      }
    }

    if (photoData) {
      // 中心裁剪映射（cover 模式）：短边铺满圆直径，长边居中裁剪
      const photoView = new Uint8Array(photoData.buffer)
      const pw = photoData.width
      const ph = photoData.height
      const photoCx = pw / 2
      const photoCy = ph / 2

      for (let y = 0; y < tipY; y++) {
        for (let x = 0; x < canvasW; x++) {
          const dx = x - cx
          const dy = y - cy
          const dist = Math.sqrt(dx * dx + dy * dy)
          if (dist <= SINGLE_INNER_R) {
            const photoX = Math.round(photoCx + dx)
            const photoY = Math.round(photoCy + dy)
            if (photoX >= 0 && photoX < pw && photoY >= 0 && photoY < ph) {
              const markerIdx = (y * canvasW + x) * 4
              const photoIdx = (photoY * pw + photoX) * 4
              view[markerIdx] = photoView[photoIdx]
              view[markerIdx + 1] = photoView[photoIdx + 1]
              view[markerIdx + 2] = photoView[photoIdx + 2]
              view[markerIdx + 3] = 0xFF
            }
          }
        }
      }
    } else {
      // 无封面照片：蓝色填充
      for (let y = 0; y < tipY; y++) {
        for (let x = 0; x < canvasW; x++) {
          const dist = Math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy))
          if (dist <= SINGLE_INNER_R) {
            const idx = (y * canvasW + x) * 4
            this.setPixel(view, idx, 0x6B, 0xB5, 0xE8, 0xFF)
          }
        }
      }
    }
  }

  private fillClusterIcon(view: Uint8Array, size: number, cx: number, cy: number,
    count: number): void {
    // 目标色值按 R,G,B 定义，传给 setPixel(r,g,b,a) 内部自动转 BGRA
    let r: number = 0x4A; let g: number = 0x90; let b: number = 0xD9 // #4A90D9 蓝
    if (count >= 10) {
      r = 0xF4; g = 0x43; b = 0x36 // #F44336 红
    } else if (count >= 5) {
      r = 0xFF; g = 0x98; b = 0x00 // #FF9800 橙
    }

    for (let y = 0; y < size; y++) {
      for (let x = 0; x < size; x++) {
        const dist = Math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy))
        const idx = (y * size + x) * 4
        if (dist <= CLUSTER_INNER_R) {
          this.setPixel(view, idx, r, g, b, 0xFF)
        } else if (dist <= CLUSTER_OUTER_R) {
          this.setPixel(view, idx, 0xFF, 0xFF, 0xFF, 0xFF)
        }
      }
    }
  }

  private posKey(lat: number, lng: number): string {
    return `${lat.toFixed(6)},${lng.toFixed(6)}`
  }
}

/**
 * 地图主页 Tab 内容视图
 * 使用 HarmonyOS Map Kit 展示真实地图 + 记忆节点 Marker
 */
@Component
export struct MapHomeView {
  @StorageLink('appThemeVersion') themeVersion: number = 0
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

  // 聚合图层
  private clusterOverlay?: map.ClusterOverlay
  private nodeLookup: Map<string, LoadedNodeData[]> = new Map()
  private photoCache: Map<string, PhotoData> = new Map()

  // 节点预览卡片状态
  @State previewVisible: boolean = false
  @State previewNodeId: string = ''
  @State previewTitle: string = ''
  @State previewPoi: string = ''
  @State previewPhoto: string = ''
  @State previewPhotoCount: number = 0
  @State previewTags: string[] = []

  // 聚合预览列表状态
  @State clusterPreviewVisible: boolean = false
  @State clusterPreviewNodes: LoadedNodeData[] = []

  private mapCallback: AsyncCallback<map.MapComponentController> = async (err, controller) => {
    if (!err && controller) {
      this.mapController = controller
      await this.syncMarkers()
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
      // 加载不属于任何旅行的节点
      const uncategorizedNodes = await this.dataService.getNodesByTravelId(TravelSpecialValues.UNCATEGORIZED_TRAVEL_ID)
      for (const node of uncategorizedNodes) {
        nodes.push(this.mapNode(node))
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
      coverPhoto: node.photos.length > 0 ? node.photos[0] : '',
      photoCount: node.photos.length
    }
  }

  private findLoadedNodeById(nodeId: string): LoadedNodeData | undefined {
    return this.loadedNodes.find((node: LoadedNodeData) => node.id === nodeId)
  }

  private positionKey(lat: number, lng: number): string {
    return `${lat.toFixed(6)},${lng.toFixed(6)}`
  }

  private async preloadPhotos(nodes: LoadedNodeData[]): Promise<void> {
    this.releasePhotoCache()
    const diameter = 2 * SINGLE_INNER_R
    for (const node of nodes) {
      if (node.coverPhoto.length > 0 && !this.photoCache.has(node.coverPhoto)) {
        try {
          const file = fileIo.openSync(node.coverPhoto, fileIo.OpenMode.READ_ONLY)
          const stat = fileIo.statSync(node.coverPhoto)
          const buf = new ArrayBuffer(stat.size)
          fileIo.readSync(file.fd, buf)
          fileIo.closeSync(file)
          const src = image.createImageSource(buf)
          const info = await src.getImageInfo()
          const shortSide = Math.min(info.size.width, info.size.height)
          const scale = diameter / shortSide
          const targetW = Math.round(info.size.width * scale)
          const targetH = Math.round(info.size.height * scale)
          const pm = await src.createPixelMap({ desiredSize: { width: targetW, height: targetH } })
          const pixelBuf = new ArrayBuffer(pm.getPixelBytesNumber())
          await pm.readPixelsToBuffer(pixelBuf)
          pm.release()
          this.photoCache.set(node.coverPhoto, { buffer: pixelBuf, width: targetW, height: targetH })
        } catch (e) {
          logger.warn('MapHomeView', `preload photo failed: ${node.coverPhoto}`)
        }
      }
    }
  }

  private releasePhotoCache(): void {
    this.photoCache.clear()
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
    this.previewPhotoCount = 0
    this.previewTags = []
    this.clusterPreviewVisible = false
    this.clusterPreviewNodes = []
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

  /** 在地图上同步记忆节点 Marker（使用 ClusterOverlay 聚合）
   *
   * 【全量同步模式】每次都移除所有旧图层后重新创建
   * 优点：简单可靠，不易产生状态不一致
   * 缺点：节点数较多时性能开销略高
   *
   * 【增量同步优化点】未来可优化为：
   * 1. 比较新旧 nodeIds 差异，仅移除消失的节点、添加新增的节点
   * 2. ClusterOverlay 支持 addItem() 单个添加，但移除需整体 remove() 后重建
   * 3. 增量模式需维护 nodeIds 与 ClusterOverlay 的映射关系
   */
  private async syncMarkers(): Promise<void> {
    if (!this.mapController) {
      return
    }

    // === 清理阶段：移除所有旧图层 ===

    // 移除旧的聚合图层
    if (this.clusterOverlay) {
      try {
        await this.clusterOverlay.remove()
      } catch (_) {}
      this.clusterOverlay = undefined
    }

    // 清理旧的传统 Marker（兼容保留）
    for (const marker of this.mapMarkers) {
      try {
        marker.remove()
      } catch (_) {}
    }
    this.mapMarkers = []
    this.markerNodeIds = []

    // 清理搜索目标 Marker
    if (this.selectedSearchMarker) {
      try {
        this.selectedSearchMarker.remove()
      } catch (_) {}
      this.selectedSearchMarker = undefined
    }

    // 重置查找映射
    this.nodeLookup.clear()

    // === 构建阶段：创建新图层 ===
    await this.preloadPhotos(this.loadedNodes)

    // 构建 ClusterItem 数组 + 填充 nodeLookup
    const clusterItems: mapCommon.ClusterItem[] = []
    for (const node of this.mapNodes) {
      const loadedNode = this.findLoadedNodeById(node.id)
      if (loadedNode) {
        const key = this.positionKey(node.latitude, node.longitude)
        const existing = this.nodeLookup.get(key)
        if (existing) {
          existing.push(loadedNode)
        } else {
          this.nodeLookup.set(key, [loadedNode])
        }
      }
      clusterItems.push({
        position: { latitude: node.latitude, longitude: node.longitude }
      })
    }

    // 创建聚合图层
    if (clusterItems.length > 0) {
      const params = new NodeClusterOverlayParams(clusterItems, 50, this.nodeLookup, this.photoCache)
      this.clusterOverlay = await this.mapController.addClusterOverlay(params)
      this.setupClusterEventListeners()
    }

    // === 重建独立标记（搜索目的地，不受聚合影响） ===
    if (this.hasSelectedSearchResult && this.selectedSearchType === 'site') {
      await this.updateSelectedSearchMarker(
        this.selectedSearchLatitude,
        this.selectedSearchLongitude,
        this.selectedSearchTitle,
        this.selectedSearchSubtitle.length > 0 ? this.selectedSearchSubtitle : this.selectedSearchTitle
      )
    }
  }

  /** 监听聚合图层点击事件 */
  private setupClusterEventListeners(): void {
    if (!this.clusterOverlay) {
      return
    }

    // 单个标记点击 → 显示预览卡片
    this.clusterOverlay.on('markerClusterClick', (info: map.MarkerClusterInfo) => {
      const items = info.clusterItems
      if (items.length === 1) {
        const key = this.positionKey(items[0].position.latitude, items[0].position.longitude)
        const nodes = this.nodeLookup.get(key)
        if (nodes && nodes.length > 0) {
          const node = nodes[0]
          this.previewNodeId = node.id
          this.previewTitle = node.title
          this.previewPoi = node.poiName
          this.previewPhoto = node.coverPhoto
          this.previewPhotoCount = node.photoCount
          this.previewTags = node.tags.slice(0, 3)
          this.previewVisible = true
          this.clusterPreviewVisible = false
        }
      }
    })

    // 聚合组点击 → 显示列表 + 相机放大
    this.clusterOverlay.on('click', (items: mapCommon.ClusterItem[]) => {
      if (items.length > 1) {
        // 计算中心点
        let sumLat = 0, sumLng = 0
        for (const item of items) {
          sumLat += item.position.latitude
          sumLng += item.position.longitude
        }
        const centerLat = sumLat / items.length
        const centerLng = sumLng / items.length

        // 收集该聚合内的所有节点
        const clusterNodes: LoadedNodeData[] = []
        for (const item of items) {
          const key = this.positionKey(item.position.latitude, item.position.longitude)
          const nodes = this.nodeLookup.get(key)
          if (nodes) {
            clusterNodes.push(...nodes)
          }
        }

        // 显示聚合预览列表
        this.previewVisible = false
        this.clusterPreviewNodes = clusterNodes
        this.clusterPreviewVisible = true

        // 相机放大 2 级
        if (this.mapController) {
          const currentCamera = this.mapController.getCameraPosition()
          const newZoom = Math.min((currentCamera.zoom ?? 12) + 2, 20)
          const cameraUpdate = map.newCameraPosition({
            target: { latitude: centerLat, longitude: centerLng },
            zoom: newZoom
          })
          this.mapController.animateCamera(cameraUpdate, 400)
        }
      }
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

          if (this.hasSelectedSearchResult) {
            Text('用该地址新建记忆')
              .fontSize(AppDimens.FONT_MD)
              .fontColor(AppColors.TEXT_ON_PRIMARY)
              .backgroundColor(AppColors.PRIMARY)
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .borderRadius(20)
              .margin({ left: 8 })
              .shadow({ radius: 4, color: '#1890FF33', offsetY: 2 })
              .onClick(() => this.navigateToCreateNodeFromSearch())
          }

          Text('筛选')
            .fontSize(AppDimens.FONT_MD)
            .fontColor(this.showFilter ? AppColors.TEXT_ON_PRIMARY : AppColors.PRIMARY)
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
                .fontColor(this.selectedFilterTime === label ? AppColors.TEXT_ON_PRIMARY : AppColors.TEXT_SECONDARY)
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
                .fontColor(this.selectedFilterTag === label ? AppColors.TEXT_ON_PRIMARY : AppColors.TEXT_SECONDARY)
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
          .fontColor(AppColors.TEXT_ON_PRIMARY)
          .backgroundColor(AppColors.PRIMARY)
          .borderRadius(26)
          .shadow({ radius: 6, color: '#1890FF66', offsetY: 3 })
          .onClick(() => {
            router.pushUrl({ url: RouterUrls.NODE_EDIT })
          })
      }
      .position({ x: '80%', y: '60%' })

      // 底部节点预览卡片（增强版：80x80 封面 + 照片数量徽章 + 标签行）
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
                    .fontSize(28)
                }
                .width('100%')
                .height('100%')
                .justifyContent(FlexAlign.Center)
                .backgroundColor('#6BB5E8')
              }
              // 照片数量徽章
              if (this.previewPhotoCount > 1) {
                Text(`${this.previewPhotoCount}张`)
                  .fontSize(10)
                  .fontColor('#FFFFFF')
                  .backgroundColor('#000000AA')
                  .padding({ left: 4, right: 4, top: 2, bottom: 2 })
                  .borderRadius(4)
                  .position({ x: 56, y: 64 })
              }
            }
            .width(80)
            .height(80)
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
              // 标签行
              if (this.previewTags.length > 0) {
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(this.previewTags.slice(0, 3), (tag: string) => {
                    Text(tag)
                      .fontSize(10)
                      .fontColor(AppColors.PRIMARY)
                      .backgroundColor('#4A90D920')
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .borderRadius(8)
                      .margin({ right: 4 })
                  })
                }
                .margin({ top: 6 })
              }
              Text('点击查看详情 >')
                .fontSize(AppDimens.FONT_SM)
                .fontColor(AppColors.PRIMARY)
                .margin({ top: 6 })
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

      // 聚合展开列表（点击聚合标记后显示）
      if (this.clusterPreviewVisible) {
        Column() {
          Column()
            .width('100%')
            .layoutWeight(1)
            .onClick(() => { this.clusterPreviewVisible = false })

          Column() {
            Text(`此处有 ${this.clusterPreviewNodes.length} 个记忆节点`)
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_HINT)
              .margin({ bottom: 8 })

            Scroll() {
              Row({ space: 12 }) {
                ForEach(this.clusterPreviewNodes, (node: LoadedNodeData) => {
                  Column() {
                    Stack() {
                      if (node.coverPhoto.length > 0) {
                        Image(node.coverPhoto)
                          .width(60)
                          .height(60)
                          .objectFit(ImageFit.Cover)
                          .borderRadius(AppDimens.RADIUS_SM)
                      } else {
                        Column() {
                          Text('📷')
                            .fontSize(20)
                        }
                        .width(60)
                        .height(60)
                        .backgroundColor(AppColors.BACKGROUND)
                        .borderRadius(AppDimens.RADIUS_SM)
                        .justifyContent(FlexAlign.Center)
                      }
                    }
                    .width(60)
                    .height(60)
                    Text(node.title)
                      .fontSize(12)
                      .fontColor(AppColors.TEXT_PRIMARY)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width(60)
                      .textAlign(TextAlign.Center)
                      .margin({ top: 4 })
                  }
                  .onClick(() => {
                    this.clusterPreviewVisible = false
                    router.pushUrl({
                      url: RouterUrls.NODE_DETAIL,
                      params: { nodeId: node.id } as RouterParam
                    })
                  })
                })
              }
              .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD })
            }
            .scrollable(ScrollDirection.Horizontal)
            .width('100%')
            .height(100)
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius({ topLeft: AppDimens.RADIUS_LG, topRight: AppDimens.RADIUS_LG })
          .shadow({ radius: 8, color: '#0000001A', offsetY: -2 })
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
  }
}
