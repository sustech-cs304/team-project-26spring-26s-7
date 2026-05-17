import { router, promptAction } from '@kit.ArkUI'
import { AppColors, AppDimens, RouterUrls, TravelSpecialValues, getDataService } from '../../../common'
import { RouterParam } from '../../../common'
import type { MemoryNode, Trip } from '../../../common'

interface NodeFeedItem {
  id: string
  title: string
  poiName: string
  content: string
  coverPhoto: string
  createdAt: number
  travelId: string
  tripName: string
  tripIsPublic: boolean
}

@Component
export struct NodeListView {
  private static readonly BULK_SHEET_HEADER_HEIGHT: number = 92
  private static readonly BULK_SHEET_ITEM_HEIGHT: number = 72

  @StorageLink('appThemeVersion') themeVersion: number = 0
  @State nodes: NodeFeedItem[] = []
  @State searchKeyword: string = ''
  @State availableTrips: Trip[] = []
  @State totalTripCount: number = 0
  @State isLoading: boolean = false
  @State isManageMode: boolean = false
  @State selectedNodeIds: string[] = []
  @State showBulkTripSelector: boolean = false
  @State isBulkOperating: boolean = false
  @Watch('onTravelDataVersionChange')
  @StorageLink('travelDataVersion') travelDataVersion: number = 0
  @StorageLink('activeTabIndex') activeTabIndex: number = 0

  private dataService = getDataService()

  aboutToAppear(): void {
    this.syncBulkToolbarVisibility()
    this.loadNodes()
  }

  aboutToDisappear(): void {
    AppStorage.setOrCreate('nodeBulkActionMode', false)
  }

  private syncBulkToolbarVisibility(): void {
    AppStorage.setOrCreate('nodeBulkActionMode', this.isManageMode)
  }

  private onTravelDataVersionChange(): void {
    if (this.isBulkOperating) {
      return
    }
    this.loadNodes()
  }

  private formatDate(timestamp: number): string {
    const date = new Date(timestamp)
    const year = date.getFullYear().toString()
    const month = (date.getMonth() + 1).toString().padStart(2, '0')
    const day = date.getDate().toString().padStart(2, '0')
    return `${year}.${month}.${day}`
  }

  private formatTime(timestamp: number): string {
    const date = new Date(timestamp)
    const hours = date.getHours().toString().padStart(2, '0')
    const minutes = date.getMinutes().toString().padStart(2, '0')
    return `${hours}:${minutes}`
  }

  private getPreviewText(content: string, _poiName: string): string {
    const trimmed = content.trim()
    if (trimmed.length > 0) {
      return trimmed
    }
    return ''
  }

  private mapNodeToFeedItem(node: MemoryNode, trip: Trip): NodeFeedItem {
    return {
      id: node.id,
      title: node.title,
      poiName: node.poiName,
      content: this.getPreviewText(node.content, node.poiName),
      coverPhoto: node.photos.length > 0 ? node.photos[0] : '',
      createdAt: node.createdAt,
      travelId: node.travelId,
      tripName: trip.name,
      tripIsPublic: trip.isPublic
    }
  }

  private async appendTripNodes(feedItems: NodeFeedItem[], trip: Trip): Promise<void> {
    const nodes = await this.dataService.getNodesByTravelId(trip.id)
    for (const node of nodes) {
      feedItems.push(this.mapNodeToFeedItem(node, trip))
    }
  }

  private buildUncategorizedTrip(): Trip {
    return {
      id: TravelSpecialValues.UNCATEGORIZED_TRAVEL_ID,
      name: TravelSpecialValues.UNCATEGORIZED_TRAVEL_NAME,
      description: '',
      coverPhoto: '',
      isPublic: false,
      startDate: 0,
      endDate: 0,
      nodeIds: [],
      totalDistance: 0,
      createdAt: 0,
      updatedAt: 0,
      ownerUid: '',
      cloudId: '',
      syncStatus: 'synced',
      deletedAt: 0,
      lastSyncedAt: 0,
      version: 1
    }
  }

  private normalizeSearchKeyword(value: string): string {
    return value.trim().toLowerCase()
  }

  private getFilteredNodes(): NodeFeedItem[] {
    const keyword = this.normalizeSearchKeyword(this.searchKeyword)
    if (keyword.length === 0) {
      return this.nodes
    }

    return this.nodes.filter((item: NodeFeedItem) => {
      const searchFields: string[] = [
        item.title,
        item.poiName,
        item.content,
        item.tripName
      ]

      return searchFields.some((field: string) => field.toLowerCase().indexOf(keyword) >= 0)
    })
  }

  private isAllFilteredNodesSelected(): boolean {
    const filteredNodes = this.getFilteredNodes()
    return filteredNodes.length > 0 &&
      filteredNodes.every((item: NodeFeedItem) => this.isNodeSelected(item.id))
  }

  @Builder
  private buildSearchInput() {
    Row({ space: 8 }) {
      TextInput({ placeholder: '搜索节点、地点或旅行', text: this.searchKeyword })
        .layoutWeight(1)
        .defaultFocus(false)
        .fontColor(AppColors.INPUT_TEXT)
        .placeholderColor(AppColors.INPUT_PLACEHOLDER)
        .caretColor(AppColors.INPUT_CARET)
        .backgroundColor('#00000000')
        .onChange((value: string) => {
          this.searchKeyword = value
        })
      if (false) {
        Text('搜索节点、地点或旅行')
          .layoutWeight(1)
          .height(40)
          .fontSize(AppDimens.FONT_MD)
          .fontColor(AppColors.INPUT_PLACEHOLDER)
          .textAlign(TextAlign.Start)
          .onClick(() => {
            this.searchKeyword = this.searchKeyword
          })
      }

      if (this.searchKeyword.length > 0) {
        Button() {
          Text('×')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_HINT)
        }
        .width(28)
        .height(28)
        .padding(0)
        .backgroundColor('#F0F1F4')
        .borderRadius(14)
        .onClick(() => {
          this.searchKeyword = ''
        })
      }
    }
    .width('100%')
    .margin({ top: 16 })
    .padding({ left: 12, right: 10 })
    .backgroundColor(AppDimens.SURFACE_TINT)
    .border({ width: 1, color: AppDimens.GLASS_BORDER })
    .borderRadius(24)
    .shadow({ radius: 12, color: AppDimens.SHADOW_SOFT, offsetY: 4 })
    .alignItems(VerticalAlign.Center)
  }

  private async loadNodes(): Promise<void> {
    this.isLoading = true
    try {
      const trips = await this.dataService.getAllTravels()
      this.availableTrips = trips
      const feedItems: NodeFeedItem[] = []
      for (const trip of trips) {
        await this.appendTripNodes(feedItems, trip)
      }
      await this.appendTripNodes(feedItems, this.buildUncategorizedTrip())
      feedItems.sort((left: NodeFeedItem, right: NodeFeedItem) => right.createdAt - left.createdAt)
      this.nodes = feedItems
      this.totalTripCount = trips.length
      this.selectedNodeIds = this.selectedNodeIds.filter((nodeId: string) =>
        feedItems.some((item: NodeFeedItem) => item.id === nodeId))
      if (this.selectedNodeIds.length === 0) {
        this.isManageMode = false
      }
    } catch (_) {
      this.nodes = []
      this.availableTrips = []
      this.selectedNodeIds = []
      this.isManageMode = false
      promptAction.showToast({ message: '加载节点列表失败' })
    } finally {
      this.isLoading = false
    }
  }

  private openNodeDetail(nodeId: string): void {
    router.pushUrl({
      url: RouterUrls.NODE_DETAIL,
      params: { nodeId } as RouterParam
    })
  }

  private openNodeEdit(): void {
    router.pushUrl({ url: RouterUrls.NODE_EDIT })
  }

  private bumpTravelDataVersion(): void {
    const version = (AppStorage.get('travelDataVersion') as number) || 0
    AppStorage.setOrCreate('travelDataVersion', version + 1)
  }

  private enterManageMode(): void {
    this.isManageMode = true
    this.selectedNodeIds = []
    this.syncBulkToolbarVisibility()
  }

  private exitManageMode(): void {
    this.isManageMode = false
    this.selectedNodeIds = []
    this.showBulkTripSelector = false
    this.syncBulkToolbarVisibility()
  }

  private isNodeSelected(nodeId: string): boolean {
    return this.selectedNodeIds.indexOf(nodeId) >= 0
  }

  private toggleNodeSelection(nodeId: string): void {
    if (!this.isManageMode) {
      this.openNodeDetail(nodeId)
      return
    }

    if (this.isNodeSelected(nodeId)) {
      this.selectedNodeIds = this.selectedNodeIds.filter((id: string) => id !== nodeId)
      if (this.selectedNodeIds.length === 0) {
        this.exitManageMode()
      }
      return
    }

    this.selectedNodeIds = [...this.selectedNodeIds, nodeId]
  }

  private toggleSelectAll(): void {
    const filteredNodes = this.getFilteredNodes()
    if (filteredNodes.length === 0) {
      return
    }

    if (this.isAllFilteredNodesSelected()) {
      this.exitManageMode()
      return
    }

    this.isManageMode = true
    this.selectedNodeIds = filteredNodes.map((item: NodeFeedItem) => item.id)
  }

  private getSelectedCountText(): string {
    return `已选择 ${this.selectedNodeIds.length} 个节点`
  }

  private getBulkTripSelectorListHeight(): number {
    if (this.availableTrips.length === 0) {
      return 0
    }
    return Math.min(360, this.availableTrips.length * NodeListView.BULK_SHEET_ITEM_HEIGHT)
  }

  private getBulkTripSelectorHeight(): number {
    const bodyHeight = this.availableTrips.length > 0 ? this.getBulkTripSelectorListHeight() + 72 : 144
    return Math.min(560, NodeListView.BULK_SHEET_HEADER_HEIGHT + bodyHeight + 24)
  }

  private openBulkTripSelector(): void {
    if (this.selectedNodeIds.length === 0 || this.isBulkOperating) {
      return
    }
    this.showBulkTripSelector = true
  }

  private closeBulkTripSelector(): void {
    if (this.isBulkOperating) {
      return
    }
    this.showBulkTripSelector = false
  }

  private applyLocalTripInfoToSelectedNodes(travelId: string, selectedIds: string[]): void {
    let nextTripName: string = TravelSpecialValues.UNCATEGORIZED_TRAVEL_NAME
    let nextTripIsPublic: boolean = false

    if (travelId !== TravelSpecialValues.UNCATEGORIZED_TRAVEL_ID) {
      const targetTrip = this.availableTrips.find((trip: Trip) => trip.id === travelId)
      if (targetTrip) {
        nextTripName = targetTrip.name
        nextTripIsPublic = targetTrip.isPublic
      }
    }

    this.nodes = this.nodes.map((item: NodeFeedItem) => {
      if (selectedIds.indexOf(item.id) < 0) {
        return item
      }
      return {
        id: item.id,
        title: item.title,
        poiName: item.poiName,
        content: item.content,
        coverPhoto: item.coverPhoto,
        createdAt: item.createdAt,
        travelId: travelId,
        tripName: nextTripName,
        tripIsPublic: nextTripIsPublic
      }
    })
  }

  private async applyBulkMoveToTrip(travelId: string): Promise<void> {
    if (this.selectedNodeIds.length === 0 || this.isBulkOperating) {
      return
    }

    this.isBulkOperating = true
    try {
      const selectedIds = this.selectedNodeIds.slice()
      this.applyLocalTripInfoToSelectedNodes(travelId, selectedIds)
      this.selectedNodeIds = selectedIds
      this.showBulkTripSelector = false
      for (const nodeId of selectedIds) {
        await this.dataService.updateNode(nodeId, { travelId })
        this.bumpTravelDataVersion()
      }
      this.bumpTravelDataVersion()
      promptAction.showToast({ message: '批量加入旅行成功' })
      this.exitManageMode()
      await this.loadNodes()
    } catch (_) {
      await this.loadNodes()
      promptAction.showToast({ message: '批量加入旅行失败' })
    } finally {
      this.isBulkOperating = false
    }
  }

  private confirmBulkDelete(): void {
    if (this.selectedNodeIds.length === 0 || this.isBulkOperating) {
      return
    }

    AlertDialog.show({
      title: '批量删除节点',
      message: `确认删除已选中的 ${this.selectedNodeIds.length} 个节点吗？删除后将无法恢复。`,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '删除',
        fontColor: AppColors.DANGER,
        action: () => {
          void this.handleBulkDelete()
        }
      }
    })
  }

  private async handleBulkDelete(): Promise<void> {
    if (this.selectedNodeIds.length === 0 || this.isBulkOperating) {
      return
    }

    this.isBulkOperating = true
    try {
      for (const nodeId of this.selectedNodeIds) {
        await this.dataService.deleteNode(nodeId)
      }
      this.bumpTravelDataVersion()
      promptAction.showToast({ message: '批量删除成功' })
      this.exitManageMode()
      await this.loadNodes()
    } catch (_) {
      promptAction.showToast({ message: '批量删除失败' })
    } finally {
      this.isBulkOperating = false
    }
  }

  @Builder
  private buildHeaderCard() {
    Column() {
      Row() {
        Text('节点')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_PRIMARY)
          .layoutWeight(1)

        Row({ space: 8 }) {
          Button(this.isManageMode ? '完成' : '选择')
            .width(58)
            .height(32)
            .padding(0)
            .fontSize(AppDimens.FONT_SM)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.isManageMode ? AppColors.TEXT_ON_PRIMARY : AppDimens.CTA_DARK)
            .backgroundColor(this.isManageMode ? AppDimens.CTA_DARK : '#F8F9FB')
            .border({ width: 1, color: AppDimens.CTA_DARK })
            .borderRadius(16)
            .enabled(this.nodes.length > 0)
            .opacity(this.nodes.length > 0 ? 1 : 0.45)
            .onClick(() => {
              if (this.isManageMode) {
                this.exitManageMode()
              } else {
                this.enterManageMode()
              }
            })

          Button('+')
            .width(32)
            .height(32)
            .padding(0)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.TEXT_ON_PRIMARY)
            .backgroundColor(AppColors.PRIMARY)
            .borderRadius(16)
            .onClick(() => this.openNodeEdit())
        }
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 12 }) {
        Column() {
          Text(this.nodes.length.toString())
            .fontSize(AppDimens.FONT_XL)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.TEXT_PRIMARY)
          Text('记忆节点')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_HINT)
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column() {
          Text(this.totalTripCount.toString())
            .fontSize(AppDimens.FONT_XL)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.TEXT_PRIMARY)
          Text('所属 Track')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_HINT)
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .margin({ top: 18 })
      .alignItems(VerticalAlign.Top)

      this.buildSearchInput()

      if (this.isManageMode) {
        Text(this.getSelectedCountText())
          .fontSize(AppDimens.FONT_SM)
          .fontColor(AppColors.PRIMARY)
          .margin({ top: 12 })
          .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 0, right: 0, top: 12, bottom: 8 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildNodeCard(item: NodeFeedItem) {
    Row() {
      if (this.isManageMode) {
        Stack() {
          Circle()
            .width(24)
            .height(24)
            .fill(this.isNodeSelected(item.id) ? AppDimens.CTA_DARK : AppColors.CARD_BG)
            .stroke(this.isNodeSelected(item.id) ? AppDimens.CTA_DARK : AppColors.DIVIDER)
            .strokeWidth(2)
          if (this.isNodeSelected(item.id)) {
            Text('V')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.TEXT_ON_PRIMARY)
          }
        }
        .width(28)
        .height(108)
        .alignContent(Alignment.Center)
      }

      Stack() {
        if (item.coverPhoto.length > 0) {
          Image(item.coverPhoto)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        } else {
          Column() {
            Text('NO PHOTO')
              .fontSize(AppDimens.FONT_XS)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_HINT)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor(AppDimens.PHOTO_SURFACE)
        }
      }
      .width(108)
      .height(108)
      .borderRadius(22)
      .clip(true)
      .margin({ left: this.isManageMode ? 8 : 0 })

      Column() {
        Text(item.title.length > 0 ? item.title : '未命名记忆')
          .fontSize(AppDimens.FONT_LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_PRIMARY)
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(item.poiName.length > 0 ? item.poiName : '未命名地点')
          .fontSize(AppDimens.FONT_SM)
          .fontColor(AppColors.TEXT_SECONDARY)
          .lineHeight(18)
          .margin({ top: 8 })
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Blank()

        Text(`${this.formatDate(item.createdAt)} ${this.formatTime(item.createdAt)}`)
          .fontSize(AppDimens.FONT_SM)
          .fontColor(AppColors.TEXT_HINT)
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row() {
          Text('所属旅行')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_HINT)

          Text(item.tripName)
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.PRIMARY)
            .layoutWeight(1)
            .margin({ left: 8 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .margin({ top: 4 })
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .height(108)
      .margin({ left: 12 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(AppDimens.PADDING_MD)
    .backgroundColor(this.isNodeSelected(item.id) ? AppDimens.ACCENT_SOFT_BG : AppDimens.SURFACE_TINT)
    .backgroundBlurStyle(BlurStyle.Thin, { colorMode: ThemeColorMode.SYSTEM, adaptiveColor: AdaptiveColor.DEFAULT })
    .borderRadius(AppDimens.RADIUS_LG)
    .border({
      width: this.isNodeSelected(item.id) ? 1.5 : 1,
      color: this.isNodeSelected(item.id) ? '#FFB37A' : AppDimens.GLASS_BORDER
    })
    .shadow({ radius: 18, color: AppDimens.SHADOW_SOFT, offsetY: 7 })
    .alignItems(VerticalAlign.Top)
    .onClick(() => this.toggleNodeSelection(item.id))
  }

  @Builder
  private buildBulkActionBar() {
    Row({ space: 12 }) {
      Button('加入旅行')
        .layoutWeight(1)
        .height(46)
        .fontSize(AppDimens.FONT_MD)
        .fontColor(AppColors.TEXT_ON_PRIMARY)
        .backgroundColor(AppDimens.CTA_DARK)
        .enabled(!this.isBulkOperating && this.selectedNodeIds.length > 0)
        .opacity(!this.isBulkOperating && this.selectedNodeIds.length > 0 ? 1 : 0.55)
        .onClick(() => this.openBulkTripSelector())

      Button(this.isBulkOperating ? '处理中...' : '批量删除')
        .layoutWeight(1)
        .height(46)
        .fontSize(AppDimens.FONT_MD)
        .backgroundColor(AppColors.DANGER)
        .enabled(!this.isBulkOperating && this.selectedNodeIds.length > 0)
        .opacity(!this.isBulkOperating && this.selectedNodeIds.length > 0 ? 1 : 0.55)
        .onClick(() => this.confirmBulkDelete())
    }
    .width('100%')
    .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 10, bottom: 10 })
    .backgroundColor(AppColors.BACKGROUND)
    .shadow({ radius: 18, color: AppDimens.SHADOW_FLOAT, offsetY: -6 })
  }

  @Builder
  private buildBulkTripSelector() {
    Column() {
      Row() {
        Column() {
          Text('加入旅行')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.TEXT_PRIMARY)
          Text(`把已选的 ${this.selectedNodeIds.length} 个节点归到同一个旅行中`)
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_HINT)
            .margin({ top: 6 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button('关闭')
          .height(34)
          .fontSize(AppDimens.FONT_SM)
          .fontColor(AppColors.TEXT_PRIMARY)
          .backgroundColor(AppDimens.PHOTO_SURFACE)
          .onClick(() => this.closeBulkTripSelector())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Button(TravelSpecialValues.UNCATEGORIZED_TRAVEL_NAME)
        .width('100%')
        .height(48)
        .margin({ top: 16 })
        .fontSize(AppDimens.FONT_MD)
        .fontColor(AppColors.TEXT_PRIMARY)
        .backgroundColor(AppDimens.PHOTO_SURFACE)
        .onClick(() => {
          void this.applyBulkMoveToTrip(TravelSpecialValues.UNCATEGORIZED_TRAVEL_ID)
        })

      if (this.availableTrips.length > 0) {
        List({ space: 10 }) {
          ForEach(this.availableTrips, (trip: Trip) => {
            ListItem() {
              Row() {
                Column() {
                  Text(trip.name)
                    .fontSize(AppDimens.FONT_MD)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(AppColors.TEXT_PRIMARY)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Text(trip.isPublic ? '公开旅行' : '私密旅行')
                    .fontSize(AppDimens.FONT_SM)
                    .fontColor(AppColors.TEXT_HINT)
                    .margin({ top: 6 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Text('加入')
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(AppColors.PRIMARY)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 16, bottom: 16 })
              .backgroundColor(AppDimens.PHOTO_SURFACE)
              .borderRadius(AppDimens.RADIUS_MD)
              .onClick(() => {
                void this.applyBulkMoveToTrip(trip.id)
              })
            }
          }, (trip: Trip) => trip.id)
        }
        .width('100%')
        .height(this.getBulkTripSelectorListHeight())
        .margin({ top: 14 })
      } else {
        Column() {
          Text('还没有可选旅行')
            .fontSize(AppDimens.FONT_MD)
            .fontColor(AppColors.TEXT_PRIMARY)
          Text('也可以先把这些节点放到“未分类”里。')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_HINT)
            .margin({ top: 8 })
        }
        .width('100%')
        .height(120)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .padding(AppDimens.PADDING_LG)
    .backgroundColor(AppDimens.SURFACE_TINT)
    .border({ width: 1, color: AppDimens.GLASS_BORDER })
    .borderRadius({ topLeft: 24, topRight: 24 })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        this.buildHeaderCard()

        if (this.isLoading) {
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
            Text('正在整理时间线...')
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_HINT)
              .margin({ top: 12 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.nodes.length === 0) {
          Column() {
            Text('还没有节点内容')
              .fontSize(AppDimens.FONT_LG)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)
            Text('从地图或这里开始，记录你的第一条地点记忆。')
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_HINT)
              .margin({ top: 8 })
            Button('立即新建')
              .margin({ top: 20 })
              .backgroundColor(AppColors.PRIMARY)
              .onClick(() => this.openNodeEdit())
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.getFilteredNodes().length === 0) {
          Column() {
            Text('没有找到匹配的节点')
              .fontSize(AppDimens.FONT_LG)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)
            Text('试试搜索节点标题、地点、内容或所属旅行')
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_HINT)
              .margin({ top: 8 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 12 }) {
            ForEach(this.getFilteredNodes(), (item: NodeFeedItem) => {
              ListItem() {
                this.buildNodeCard(item)
              }
            }, (item: NodeFeedItem) => `${item.id}-${item.travelId}-${item.tripName}`)
            if (!this.isManageMode) {
              ListItem() {
                Column()
                  .width('100%')
                  .height(76)
                  .backgroundColor(AppColors.BACKGROUND)
              }
            }
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ top: 16, bottom: this.isManageMode ? 76 : 12 })
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: AppDimens.PADDING_MD, bottom: 0 })
      .backgroundColor(AppColors.BACKGROUND)

      if (this.isManageMode && this.getFilteredNodes().length > 0) {
        this.buildBulkActionBar()
      }

      if (this.showBulkTripSelector) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#55000000')
          .onClick(() => this.closeBulkTripSelector())

        Column() {
          this.buildBulkTripSelector()
        }
        .width('100%')
        .height(this.getBulkTripSelectorHeight())
      }
    }
    .width('100%')
    .height('100%')
  }
}
