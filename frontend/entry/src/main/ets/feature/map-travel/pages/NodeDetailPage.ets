import { router, promptAction } from '@kit.ArkUI'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppColors, AppDimens, RouterUrls, TravelSpecialValues, getDataService, PhotoPickerUtil } from '../../../common'
import { RouterParam } from '../../../common'
import type { MemoryNode, Trip } from '../../../common'
import { CoachMarkOverlay } from '../../onboarding/components/CoachMarkOverlay'

const DOMAIN = 0x0000
const TAG = 'NodeDetailPage'

interface NodeDetailCardItem {
  id: string
  title: string
  poiName: string
  date: string
  content: string
  mood: string
  tags: string[]
  photos: string[]
  tripId: string
  tripName: string
  sortTime: number
}

/**
 * P04 节点详情页
 * 路由参数：{ nodeId: string }
 */
@Entry
@Component
export struct NodeDetailPage {
  @StorageLink('appThemeVersion') themeVersion: number = 0
  @Watch('onTravelDataVersionChange')
  @StorageLink('travelDataVersion') travelDataVersion: number = 0
  @State pageWidth: number = 0
  @State pageHeight: number = 0
  @State title: string = ''
  @State poiName: string = ''
  @State date: string = ''
  @State mood: string = ''
  @State tags: string[] = []
  @State content: string = ''
  @State photos: string[] = []
  @State photoRenderVersion: number = 0
  @State tripName: string = ''
  @State tripId: string = ''
  @State nodeId: string = ''
  @State isLoading: boolean = false
  @State selectedPhotoIndex: number = 0
  @State pageVisible: boolean = false
  @State showFullPhoto: boolean = false
  @State showActionMenu: boolean = false
  @State showTripSelector: boolean = false
  @State availableTrips: Trip[] = []
  @State pendingTripId: string = ''
  @State isMovingTrip: boolean = false
  @State sourceTripId: string = ''
  @State sourceTripCoverPhoto: string = ''
  @State sourceTripNodeIds: string[] = []
  @State activeTripNodeIndex: number = -1
  @State swipeHintVisible: boolean = true
  @State nodeBackgroundPhoto: string = ''
  @State swipeNodes: NodeDetailCardItem[] = []

  private dataService = getDataService()

  private clamp(value: number, min: number, max: number): number {
    return Math.min(Math.max(value, min), max)
  }

  private updatePageSize(width: number, height: number): void {
    if (width > 0) {
      this.pageWidth = width
    }
    if (height > 0) {
      this.pageHeight = height
    }
  }

  private getPhotoHeroHeight(): number {
    const availableWidth = this.pageWidth > 0 ? this.pageWidth : 360
    const baseRatio = this.pageWidth >= 960 ? 0.32 : (this.pageWidth >= 640 ? 0.4 : 0.72)
    const desiredHeight = availableWidth * baseRatio
    const maxHeight = this.pageHeight > 0 ? Math.max(260, this.pageHeight * 0.42) : 360
    return this.clamp(desiredHeight, 200, maxHeight)
  }

  private bumpTravelDataVersion(): void {
    const version = (AppStorage.get('travelDataVersion') as number) || 0
    AppStorage.setOrCreate('travelDataVersion', version + 1)
  }

  aboutToAppear(): void {
    const params = router.getParams() as RouterParam
    if (params?.nodeId) {
      this.nodeId = params.nodeId
      this.sourceTripId = params.tripId ?? ''
      this.loadNodeDetail()
      this.loadAvailableTrips()
      if (this.sourceTripId.length > 0) {
        this.loadSourceTripContext()
      } else {
        this.loadAllNodeContext()
      }
    }
  }

  onPageShow(): void {
    this.pageVisible = true
    // 从子页面返回时重新加载节点数据（首次加载由 aboutToAppear 处理）
  }

  onPageHide(): void {
    this.pageVisible = false
  }

  onDisappear(): void {
  }

  private onTravelDataVersionChange(): void {
    if (this.nodeId && !this.isLoading) {
      this.loadNodeDetail()
      this.loadAvailableTrips()
      if (this.sourceTripId.length > 0) {
        this.loadSourceTripContext()
      } else {
        this.loadAllNodeContext()
      }
    }
  }

  private async loadAvailableTrips(): Promise<void> {
    try {
      this.availableTrips = await this.dataService.getAllTravels()
    } catch (_) {
      this.availableTrips = []
    }
  }

  private formatDate(timestamp: number): string {
    const date = new Date(timestamp)
    const year = date.getFullYear().toString()
    const month = (date.getMonth() + 1).toString().padStart(2, '0')
    const day = date.getDate().toString().padStart(2, '0')
    return `${year}.${month}.${day}`
  }

  private getDisplayContent(): string {
    const trimmed = this.content.trim()
    return trimmed.length > 0 ? trimmed : '这条节点还没有补充正文内容。'
  }

  private mapNodeToDetailCard(node: MemoryNode, tripName: string): NodeDetailCardItem {
    return {
      id: node.id,
      title: node.title,
      poiName: node.poiName,
      date: this.formatDate(node.visitedAt || node.createdAt),
      content: node.content,
      mood: node.mood,
      tags: [...node.tags],
      photos: [...node.photos],
      tripId: node.travelId,
      tripName: tripName,
      sortTime: node.visitedAt || node.createdAt
    }
  }

  private applyCardItem(item: NodeDetailCardItem): void {
    this.nodeId = item.id
    this.title = item.title
    this.poiName = item.poiName
    this.date = item.date
    this.mood = item.mood
    this.tags = [...item.tags]
    this.content = item.content
    this.photos = [...item.photos]
    this.tripId = item.tripId
    this.tripName = item.tripName
    this.nodeBackgroundPhoto = item.photos.length > 0 ? item.photos[0] : ''
    this.selectedPhotoIndex = 0
    this.photoRenderVersion += 1
  }

  private async loadNodeDetail(): Promise<void> {
    if (!this.nodeId) {
      return
    }

    this.isLoading = true
    try {
      const node = await this.dataService.getNodeById(this.nodeId)
      if (!node) {
        promptAction.showToast({ message: '未找到对应记忆节点' })
        return
      }

      this.title = node.title
      this.poiName = node.poiName
      this.date = this.formatDate(node.visitedAt || node.createdAt)
      this.mood = node.mood
      this.tags = node.tags
      this.content = node.content
      this.photos = [...node.photos]
      this.nodeBackgroundPhoto = node.photos.length > 0 ? node.photos[0] : ''
      this.photoRenderVersion += 1
      this.selectedPhotoIndex = 0
      const photoExists: boolean[] = []
      for (let i = 0; i < node.photos.length; i++) {
        photoExists.push(PhotoPickerUtil.photoExists(node.photos[i]))
      }
      hilog.info(DOMAIN, TAG, `loadNodeDetail photos=${JSON.stringify(node.photos)}, exists=${JSON.stringify(photoExists)}`)
      this.tripId = node.travelId

      const trip = await this.dataService.getTravelById(node.travelId)
      this.tripName = trip ? trip.name : ''
    } catch (_) {
      promptAction.showToast({ message: '加载节点详情失败' })
    } finally {
      this.isLoading = false
    }
  }

  private async deleteCurrentNode(): Promise<void> {
    if (!this.nodeId) {
      return
    }
    try {
      await this.dataService.deleteNode(this.nodeId)
      this.bumpTravelDataVersion()
      promptAction.showToast({ message: '记忆节点已删除' })
      router.back()
    } catch (_) {
      promptAction.showToast({ message: '删除节点失败' })
    }
  }

  private handleDelete(): void {
    this.showActionMenu = false
    AlertDialog.show({
      title: '删除记忆',
      message: `确定要删除「${this.title}」吗？此操作不可撤销。`,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '删除',
        fontColor: AppColors.DANGER,
        action: () => {
          this.deleteCurrentNode()
        }
      }
    })
  }

  private openEditPage(): void {
    this.showActionMenu = false
    router.pushUrl({
      url: RouterUrls.NODE_EDIT,
      params: { nodeId: this.nodeId } as RouterParam
    })
  }

  private openTripSelector(): void {
    this.showActionMenu = false
    this.pendingTripId = this.tripId
    this.showTripSelector = true
    if (this.availableTrips.length === 0) {
      this.loadAvailableTrips()
    }
  }

  private closeTripSelector(): void {
    this.showTripSelector = false
    this.pendingTripId = ''
  }

  private getTripSelectorHeight(): number {
    return Math.min(520, Math.max(220, this.availableTrips.length * 72 + 120))
  }

  private getPendingTrip(): Trip | undefined {
    return this.availableTrips.find((trip: Trip) => trip.id === this.pendingTripId)
  }

  private selectPendingTrip(tripId: string): void {
    this.pendingTripId = tripId
  }

  private async confirmMoveToTrip(): Promise<void> {
    const trip = this.getPendingTrip()
    if (!trip || !this.nodeId || this.isMovingTrip || trip.id === this.tripId) {
      this.closeTripSelector()
      return
    }

    this.isMovingTrip = true
    try {
      this.tripId = trip.id
      this.tripName = trip.name
      this.showTripSelector = false
      await this.dataService.updateNode(this.nodeId, { travelId: trip.id })
      this.bumpTravelDataVersion()
      promptAction.showToast({ message: '已加入旅行' })
    } catch (_) {
      await this.loadNodeDetail()
      promptAction.showToast({ message: '加入旅行失败' })
    } finally {
      this.isMovingTrip = false
    }
  }

  @Builder
  private buildGlassActionButton(label: string, tint: string, action: () => void) {
    Text(label)
      .fontSize(AppDimens.FONT_MD)
      .fontWeight(FontWeight.Medium)
      .fontColor(tint)
      .width('100%')
      .height(50)
      .textAlign(TextAlign.Center)
      .backgroundColor(label === '删除' ? '#18FF6A1A' : '#22FFFFFF')
      .backgroundBlurStyle(BlurStyle.Thin, { colorMode: ThemeColorMode.SYSTEM, adaptiveColor: AdaptiveColor.DEFAULT })
      .border({ width: 0.8, color: label === '删除' ? '#55FF6A1A' : '#55FFFFFF' })
      .borderRadius(25)
      .shadow({ radius: 16, color: AppDimens.SHADOW_SOFT, offsetY: 6 })
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
      .onClick(action)
  }

  private async loadSourceTripContext(): Promise<void> {
    const targetTripId = this.sourceTripId.length > 0 ? this.sourceTripId : this.tripId
    if (targetTripId.length === 0) {
      this.sourceTripNodeIds = []
      this.swipeNodes = []
      this.sourceTripCoverPhoto = ''
      this.activeTripNodeIndex = -1
      return
    }

    try {
      const trip = await this.dataService.getTravelById(targetTripId)
      const nodes: MemoryNode[] = await this.dataService.getNodesByTravelId(targetTripId)
      nodes.sort((left: MemoryNode, right: MemoryNode) => (left.nodeOrder ?? 0) - (right.nodeOrder ?? 0))
      this.sourceTripNodeIds = nodes.map((node: MemoryNode) => node.id)
      this.swipeNodes = nodes.map((node: MemoryNode) => this.mapNodeToDetailCard(node, trip ? trip.name : ''))
      this.activeTripNodeIndex = this.sourceTripNodeIds.indexOf(this.nodeId)
      let coverPhoto = trip?.coverPhoto ?? ''
      if (coverPhoto.length === 0) {
        const coverNode = nodes.find((node: MemoryNode) => node.photos.length > 0)
        coverPhoto = coverNode ? coverNode.photos[0] : ''
      }
      this.sourceTripCoverPhoto = coverPhoto
    } catch (_) {
      this.sourceTripNodeIds = []
      this.swipeNodes = []
      this.sourceTripCoverPhoto = ''
      this.activeTripNodeIndex = -1
    }
  }

  private async loadAllNodeContext(): Promise<void> {
    try {
      const trips = await this.dataService.getAllTravels()
      const items: NodeDetailCardItem[] = []
      for (const trip of trips) {
        const nodes: MemoryNode[] = await this.dataService.getNodesByTravelId(trip.id)
        nodes.sort((left: MemoryNode, right: MemoryNode) => (left.nodeOrder ?? 0) - (right.nodeOrder ?? 0))
        for (const node of nodes) {
          items.push(this.mapNodeToDetailCard(node, trip.name))
        }
      }
      const uncategorizedNodes: MemoryNode[] =
        await this.dataService.getNodesByTravelId(TravelSpecialValues.UNCATEGORIZED_TRAVEL_ID)
      for (const node of uncategorizedNodes) {
        items.push(this.mapNodeToDetailCard(node, TravelSpecialValues.UNCATEGORIZED_TRAVEL_NAME))
      }
      items.sort((left: NodeDetailCardItem, right: NodeDetailCardItem) => right.sortTime - left.sortTime)
      this.swipeNodes = items
      this.sourceTripNodeIds = items.map((item: NodeDetailCardItem) => item.id)
      this.activeTripNodeIndex = this.sourceTripNodeIds.indexOf(this.nodeId)
    } catch (_) {
      this.swipeNodes = []
      this.sourceTripNodeIds = []
      this.activeTripNodeIndex = -1
    }
  }

  private canSwipeTripNodes(): boolean {
    return this.sourceTripNodeIds.length > 1 && this.activeTripNodeIndex >= 0
  }

  private switchTripNodeByIndex(index: number): void {
    if (!this.canSwipeTripNodes() || index === this.activeTripNodeIndex ||
      index < 0 || index >= this.sourceTripNodeIds.length) {
      return
    }

    this.nodeId = this.sourceTripNodeIds[index]
    this.activeTripNodeIndex = index
    this.selectedPhotoIndex = 0
    this.showActionMenu = false
    this.showTripSelector = false
    this.swipeHintVisible = false
    const item = this.swipeNodes[index]
    if (item) {
      this.applyCardItem(item)
    } else {
      this.loadNodeDetail()
    }
  }

  @Builder
  private buildActionMenuSheet() {
    Column() {
      Column()
        .width('100%')
        .layoutWeight(1)
        .onClick(() => { this.showActionMenu = false })

      Column({ space: 12 }) {
        Text('更多操作')
          .fontSize(AppDimens.FONT_LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_PRIMARY)
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ bottom: 4 })

        this.buildGlassActionButton('加入旅行', AppColors.PRIMARY_DARK, () => this.openTripSelector())
        this.buildGlassActionButton('编辑', AppColors.PRIMARY_DARK, () => this.openEditPage())
        this.buildGlassActionButton('删除', AppColors.DANGER, () => this.handleDelete())
        this.buildGlassActionButton('取消', AppColors.TEXT_SECONDARY, () => { this.showActionMenu = false })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 20, bottom: 28 })
      .backgroundColor(AppDimens.SURFACE_TINT)
      .backgroundBlurStyle(BlurStyle.Thin)
      .border({ width: 1, color: AppDimens.GLASS_BORDER })
      .borderRadius({ topLeft: AppDimens.RADIUS_LG, topRight: AppDimens.RADIUS_LG })
      .shadow({ radius: 26, color: AppDimens.SHADOW_FLOAT, offsetY: -8 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#22000000')
  }

  @Builder
  private buildTripSelectorSheet() {
    Column() {
      Column()
        .width('100%')
        .layoutWeight(1)
        .onClick(() => this.closeTripSelector())

      Column() {
        Row() {
          Text('选择旅行')
            .fontSize(AppDimens.FONT_LG)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.TEXT_PRIMARY)
          Blank()
          Text(this.isMovingTrip ? '加入中...' : '确定')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.PRIMARY)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .backgroundColor(AppDimens.SURFACE_TINT)
            .backgroundBlurStyle(BlurStyle.Thin)
            .border({ width: 1, color: AppDimens.GLASS_BORDER })
            .borderRadius(18)
            .enabled(!this.isMovingTrip && this.pendingTripId.length > 0 && this.pendingTripId !== this.tripId)
            .opacity(!this.isMovingTrip && this.pendingTripId.length > 0 && this.pendingTripId !== this.tripId ? 1 : 0.55)
            .onClick(() => {
              void this.confirmMoveToTrip()
            })
          Text('关闭')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_SECONDARY)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .backgroundColor(AppDimens.SURFACE_TINT)
            .backgroundBlurStyle(BlurStyle.Thin)
            .border({ width: 1, color: AppDimens.GLASS_BORDER })
            .borderRadius(18)
            .width(0)
            .height(0)
            .enabled(!this.isMovingTrip && this.pendingTripId.length > 0)
            .opacity(0)
            .onClick(() => {
              void this.confirmMoveToTrip()
            })
        }
        .width('100%')

        Row({ space: 10 }) {
          Button('取消')
            .layoutWeight(1)
            .height(42)
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_SECONDARY)
            .backgroundColor(AppDimens.PHOTO_SURFACE)
            .borderRadius(21)
            .onClick(() => this.closeTripSelector())

          Button(this.isMovingTrip ? '加入中...' : '确定加入')
            .layoutWeight(1)
            .height(42)
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_ON_PRIMARY)
            .backgroundColor('#00000000')
            .borderRadius(21)
            .layoutWeight(0)
            .width(0)
            .height(0)
            .enabled(!this.isMovingTrip && this.pendingTripId.length > 0)
            .opacity(0)
            .onClick(() => {
              void this.confirmMoveToTrip()
            })
        }
        .width('100%')
        .height(0)
        .opacity(0)
        .margin({ top: 14 })

        if (this.availableTrips.length === 0) {
          Column() {
            Text('暂无可加入的旅行')
              .fontSize(AppDimens.FONT_MD)
              .fontColor(AppColors.TEXT_SECONDARY)
          }
          .width('100%')
          .height(120)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 10 }) {
              ForEach(this.availableTrips, (trip: Trip) => {
                Row() {
                  Column() {
                    Text(trip.name)
                      .fontSize(AppDimens.FONT_MD)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(AppColors.TEXT_PRIMARY)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(`${trip.nodeIds.length} notes`)
                      .fontSize(AppDimens.FONT_SM)
                      .fontColor(AppColors.TEXT_HINT)
                      .margin({ top: 4 })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  if (trip.id === this.pendingTripId) {
                    Text('当前')
                      .fontSize(AppDimens.FONT_SM)
                      .fontColor(AppColors.PRIMARY)
                      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                      .backgroundColor(AppDimens.ACCENT_SOFT_BG)
                      .borderRadius(14)
                  }
                }
                .width('100%')
                .padding({ left: 14, right: 14, top: 12, bottom: 12 })
                .backgroundColor(trip.id === this.pendingTripId ? AppDimens.ACCENT_SOFT_BG : AppDimens.SURFACE_TINT)
                .backgroundBlurStyle(BlurStyle.Thin)
                .border({ width: 1, color: trip.id === this.pendingTripId ? AppColors.PRIMARY : AppDimens.GLASS_BORDER })
                .borderRadius(22)
                .shadow({ radius: 14, color: AppDimens.SHADOW_SOFT, offsetY: 5 })
                .onClick(() => this.selectPendingTrip(trip.id))
              })
            }
            .width('100%')
          }
          .scrollBar(BarState.Off)
          .width('100%')
          .height(Math.min(360, this.availableTrips.length * 82))
          .margin({ top: 16 })
        }
      }
      .width('100%')
      .height(this.getTripSelectorHeight())
      .padding({ left: 18, right: 18, top: 20, bottom: 28 })
      .backgroundColor(AppDimens.SURFACE_TINT)
      .backgroundBlurStyle(BlurStyle.Thin)
      .border({ width: 1, color: AppDimens.GLASS_BORDER })
      .borderRadius({ topLeft: AppDimens.RADIUS_LG, topRight: AppDimens.RADIUS_LG })
      .shadow({ radius: 26, color: AppDimens.SHADOW_FLOAT, offsetY: -8 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#22000000')
  }

  @Builder
  private buildUnifiedActionSheet() {
    if (this.showTripSelector) {
      this.buildTripSelectorSheet()
    } else {
      this.buildActionMenuSheet()
    }
  }

  @Builder
  private buildMemoryCard(item?: NodeDetailCardItem) {
    Column() {
      if (this.canSwipeTripNodes()) {
        Text('上下滑动切换节点')
          .fontSize(AppDimens.FONT_SM)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppDimens.CTA_DARK)
          .padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .backgroundColor('#22FFFFFF')
          .backgroundBlurStyle(BlurStyle.Thin, { colorMode: ThemeColorMode.SYSTEM, adaptiveColor: AdaptiveColor.DEFAULT })
          .border({ width: 0.8, color: '#55FFFFFF' })
          .borderRadius(16)
          .margin({ bottom: 12 })
          .opacity(this.swipeHintVisible ? 1 : 0.7)
      }

      Stack({ alignContent: Alignment.TopEnd }) {
        if ((item ? item.photos : this.photos).length > 0) {
          Swiper() {
            ForEach(item ? item.photos : this.photos, (photo: string, index: number) => {
              Stack() {
                Image(`${photo}?v=${this.photoRenderVersion}`)
                  .width('100%')
                  .height('100%')
                  .objectFit(ImageFit.Contain)
              }
              .width('100%')
              .height('100%')
              .backgroundColor(AppDimens.PHOTO_SURFACE)
              .onClick(() => {
                this.selectedPhotoIndex = index
                this.showFullPhoto = true
              })
            })
          }
          .width('100%')
          .height(Math.max(220, this.getPhotoHeroHeight()))
          .index(this.selectedPhotoIndex)
          .loop(false)
          .autoPlay(false)
          .onChange((index: number) => {
            this.selectedPhotoIndex = index
          })
        } else {
          Column() {
            Text('NO PHOTO')
              .fontSize(AppDimens.FONT_SM)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_HINT)
            Text('这条节点还没有照片')
              .fontSize(AppDimens.FONT_MD)
              .fontColor(AppColors.TEXT_HINT)
              .margin({ top: 8 })
          }
          .width('100%')
          .height(Math.max(180, this.getPhotoHeroHeight() * 0.64))
          .justifyContent(FlexAlign.Center)
          .backgroundColor(AppDimens.PHOTO_SURFACE)
        }

        if ((item ? item.photos : this.photos).length > 0) {
          Text(`${this.selectedPhotoIndex + 1} / ${(item ? item.photos : this.photos).length}`)
            .fontSize(AppDimens.FONT_SM)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_ON_PRIMARY)
            .backgroundColor('#66000000')
            .backgroundBlurStyle(BlurStyle.Thin, { colorMode: ThemeColorMode.SYSTEM, adaptiveColor: AdaptiveColor.DEFAULT })
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .border({ width: 0.8, color: AppDimens.GLASS_BORDER })
            .borderRadius(16)
            .margin({ top: 14, right: 14 })
        }
      }
      .width('100%')
      .backgroundColor(AppDimens.PHOTO_SURFACE)
      .clip(true)
      .borderRadius(24)

      Column() {
        Text((item ? item.title : this.title).length > 0 ? (item ? item.title : this.title) : '未命名记忆')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_PRIMARY)
          .width('100%')
          .lineHeight(32)

        Row({ space: 8 }) {
          Text('地点')
            .fontSize(AppDimens.FONT_XS)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppDimens.CTA_DARK)
            .padding({ left: 9, right: 9, top: 5, bottom: 5 })
            .backgroundColor(AppDimens.ACCENT_SOFT_BG)
            .borderRadius(12)

          Text((item ? item.poiName : this.poiName).length > 0 ? (item ? item.poiName : this.poiName) : '未命名地点')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_SECONDARY)
            .lineHeight(20)
            .layoutWeight(1)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
          .width('100%')
          .margin({ top: 10 })
          .alignItems(VerticalAlign.Center)

        Text(item ? (item.content.trim().length > 0 ? item.content.trim() : '这条节点还没有补充正文内容。') : this.getDisplayContent())
          .fontSize(AppDimens.FONT_MD)
          .fontColor(AppColors.TEXT_PRIMARY)
          .lineHeight(24)
          .margin({ top: 18 })
          .width('100%')

        if ((item ? item.tags : this.tags).length > 0) {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(item ? item.tags : this.tags, (tag: string) => {
              Text(`#${tag}`)
                .fontSize(AppDimens.FONT_SM)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppDimens.CTA_DARK)
                .backgroundColor(AppDimens.ACCENT_SOFT_BG)
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .borderRadius(14)
                .margin({ right: 8, bottom: 8 })
            })
          }
          .width('100%')
          .margin({ top: 18 })
        }

        Row() {
          Text(item ? item.date : this.date)
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_HINT)
            .layoutWeight(1)

          if ((item ? item.tripName : this.tripName).length > 0) {
            Text('所属旅行')
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_HINT)

            Text(item ? item.tripName : this.tripName)
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppDimens.CTA_DARK)
              .fontWeight(FontWeight.Medium)
              .margin({ left: 8 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%')
        .margin({ top: 18 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          const targetTripId = item ? item.tripId : this.tripId
          if (targetTripId.length > 0) {
            router.pushUrl({
              url: RouterUrls.TRIP_DETAIL,
              params: { tripId: targetTripId } as RouterParam
            })
          }
        })
      }
      .width('100%')
      .padding({ top: 18, bottom: 2 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 18, bottom: 18 })
    .backgroundColor(AppDimens.SURFACE_TINT)
    .backgroundBlurStyle(BlurStyle.Thin, { colorMode: ThemeColorMode.SYSTEM, adaptiveColor: AdaptiveColor.DEFAULT })
    .border({ width: 1, color: '#66FFFFFF' })
    .borderRadius(AppDimens.RADIUS_LG)
    .shadow({ radius: 28, color: AppDimens.SHADOW_FLOAT, offsetY: 10 })
    .clip(true)
  }

  build() {
    Stack() {
      if (this.nodeBackgroundPhoto.length > 0) {
        Image(this.nodeBackgroundPhoto)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .blur(34)
          .opacity(0.46)
      }

      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.nodeBackgroundPhoto.length > 0 ? '#55F3F4F6' : AppColors.BACKGROUND)

      Column() {
        Row() {
        Text('←')
          .fontSize(AppDimens.FONT_XL)
          .fontColor(AppColors.TEXT_PRIMARY)
          .onClick(() => router.back())
          .width(40)
          .height(40)
          .textAlign(TextAlign.Center)
          .backgroundColor('#66FFFFFF')
          .backgroundBlurStyle(BlurStyle.Thin, { colorMode: ThemeColorMode.SYSTEM, adaptiveColor: AdaptiveColor.DEFAULT })
          .border({ width: 0.8, color: '#88FFFFFF' })
          .borderRadius(20)
        Blank()
        // 三个真正的圆点 (Circle Shape) 代替 ASCII '...'，Stack 默认居中——
        // 之前 Text('...') 走 baseline 渲染，视觉上贴底不居中。
        Stack() {
          Row({ space: 4 }) {
            Circle({ width: 4, height: 4 }).fill(AppColors.TEXT_SECONDARY)
            Circle({ width: 4, height: 4 }).fill(AppColors.TEXT_SECONDARY)
            Circle({ width: 4, height: 4 }).fill(AppColors.TEXT_SECONDARY)
          }
        }
        .width(40)
        .height(40)
        .backgroundColor('#66FFFFFF')
        .backgroundBlurStyle(BlurStyle.Thin, { colorMode: ThemeColorMode.SYSTEM, adaptiveColor: AdaptiveColor.DEFAULT })
        .border({ width: 0.8, color: '#88FFFFFF' })
        .borderRadius(20)
        .onClick(() => {
          this.showActionMenu = !this.showActionMenu
          this.showTripSelector = false
        })
        Text('编辑')
          .fontSize(AppDimens.FONT_MD)
          .fontColor('#00000000')
          .padding(0)
          .width(0)
          .height(0)
          .onClick(() => {
            router.pushUrl({
              url: RouterUrls.NODE_EDIT,
              params: { nodeId: this.nodeId } as RouterParam
            })
          })
        Text('删除')
          .fontSize(AppDimens.FONT_MD)
          .fontColor('#00000000')
          .padding(0)
          .width(0)
          .height(0)
          .onClick(() => this.handleDelete())
        }
        .width('100%')
        .height(64)
        .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 12 })
        .backgroundColor('#00000000')

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
          Text('正在加载节点详情...')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_HINT)
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.swipeNodes.length > 1 && this.activeTripNodeIndex >= 0) {
        Swiper() {
          ForEach(this.swipeNodes, (item: NodeDetailCardItem) => {
            Scroll() {
              Column() {
                this.buildMemoryCard(item)
              }
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Start)
              .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 16, bottom: 24 })
              .width('100%')
            }
            .width('100%')
            .height('100%')
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring)
            .nestedScroll({
              scrollForward: NestedScrollMode.SELF_FIRST,
              scrollBackward: NestedScrollMode.SELF_FIRST
            })
          }, (item: NodeDetailCardItem) => item.id)
        }
        .layoutWeight(1)
        .vertical(true)
        .index(this.activeTripNodeIndex)
        .loop(false)
        .indicator(false)
        .nestedScroll(SwiperNestedScrollMode.SELF_FIRST)
        .onChange((index: number) => {
          this.switchTripNodeByIndex(index)
        })
      } else {
        Scroll() {
          Column() {
            this.buildMemoryCard()
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Start)
          .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 16, bottom: 24 })
          .height('100%')
        }
        .layoutWeight(1)
      }
      }
      .justifyContent(FlexAlign.Start)
      .width('100%')
      .height('100%')
      .backgroundColor('#00000000')

      if (this.showActionMenu) {
        this.buildActionMenuSheet()
      }

      if (this.showTripSelector) {
        this.buildTripSelectorSheet()
      }

      // 第一次打开节点详情时给一个 coach mark 介绍这页能做什么
      CoachMarkOverlay({
        storageKey: 'coachMarkNodeDetailSeenV1',
        emoji: '📝',
        title: '这是节点详情',
        message: '在这里可以看 / 改照片和文字，左右滑切换同一段旅程的其他节点。右上角"…"还能换归属旅程或删除节点。',
        ctaLabel: '明白了'
      })
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_, value) => {
      this.updatePageSize(Number(value.width), Number(value.height))
    })
    .bindContentCover(this.showFullPhoto, this.buildFullPhotoViewer(), {
      modalTransition: undefined,
      onDisappear: () => { this.showFullPhoto = false }
    })
  }

  @Builder
  private buildFullPhotoViewer() {
    Column() {
      Row() {
        Text('←')
          .fontSize(AppDimens.FONT_XL)
          .fontColor(Color.White)
          .padding(AppDimens.PADDING_MD)
          .onClick(() => { this.showFullPhoto = false })
        Blank()
        Text(`${this.selectedPhotoIndex + 1} / ${this.photos.length}`)
          .fontSize(AppDimens.FONT_MD)
          .fontColor(Color.White)
          .padding(AppDimens.PADDING_MD)
      }
      .width('100%')
      .height(56)

      if (this.photos.length > 0) {
        Swiper() {
          ForEach(this.photos, (photo: string) => {
            Stack() {
              Image(`${photo}?v=${this.photoRenderVersion}`)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Contain)
            }
            .width('100%')
            .height('100%')
          })
        }
        .width('100%')
        .layoutWeight(1)
        .index(this.selectedPhotoIndex)
        .loop(false)
        .autoPlay(false)
        .onChange((index: number) => {
          this.selectedPhotoIndex = index
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}
