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
  @State availableTrips: Trip[] = []
  @State totalTripCount: number = 0
  @State isLoading: boolean = false
  @State isManageMode: boolean = false
  @State selectedNodeIds: string[] = []
  @State showBulkTripSelector: boolean = false
  @State isBulkOperating: boolean = false
  @Watch('onTravelDataVersionChange')
  @StorageLink('travelDataVersion') travelDataVersion: number = 0
  @Watch('onTabRefresh')
  @StorageLink('tabRefreshToken') tabRefreshToken: number = 0
  @StorageLink('activeTabIndex') activeTabIndex: number = 0

  private dataService = getDataService()

  aboutToAppear(): void {
    this.loadNodes()
  }

  private onTravelDataVersionChange(): void {
    if (this.isBulkOperating) {
      return
    }
    this.loadNodes()
  }

  private onTabRefresh(): void {
    if (this.activeTabIndex === 2) {
      this.loadNodes()
    }
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

  private getPreviewText(content: string, poiName: string): string {
    const trimmed = content.trim()
    if (trimmed.length > 0) {
      return trimmed
    }
    return poiName.length > 0 ? `在 ${poiName} 留下的一段记忆` : '还没有补充正文'
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
  }

  private exitManageMode(): void {
    this.isManageMode = false
    this.selectedNodeIds = []
    this.showBulkTripSelector = false
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
    if (this.selectedNodeIds.length === this.nodes.length) {
      this.exitManageMode()
      return
    }
    this.isManageMode = true
    this.selectedNodeIds = this.nodes.map((item: NodeFeedItem) => item.id)
  }

  private getSelectedCountText(): string {
    return `已选 ${this.selectedNodeIds.length} 个节点`
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

        if (this.nodes.length > 0) {
          Button(this.isManageMode ? '完成' : '批量编辑')
            .height(36)
            .fontSize(AppDimens.FONT_SM)
            .fontColor(this.isManageMode ? AppColors.TEXT_PRIMARY : AppColors.PRIMARY)
            .backgroundColor(this.isManageMode ? '#F3F4F6' : '#EAF4FF')
            .onClick(() => {
              if (this.isManageMode) {
                this.exitManageMode()
              } else {
                this.enterManageMode()
              }
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text('按时间回看每一次停留，把地点记忆串成可浏览的内容流。')
        .fontSize(AppDimens.FONT_MD)
        .fontColor(AppColors.TEXT_SECONDARY)
        .lineHeight(22)
        .margin({ top: 8 })
        .width('100%')

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

        if (this.isManageMode) {
          Button(this.selectedNodeIds.length === this.nodes.length ? '取消全选' : '全选')
            .height(38)
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.PRIMARY)
            .backgroundColor('#EAF4FF')
            .onClick(() => this.toggleSelectAll())
        } else {
          Button('新建节点')
            .height(38)
            .fontSize(AppDimens.FONT_SM)
            .backgroundColor(AppColors.PRIMARY)
            .onClick(() => this.openNodeEdit())
        }
      }
      .width('100%')
      .margin({ top: 18 })
      .alignItems(VerticalAlign.Center)

      if (this.isManageMode) {
        Text(this.getSelectedCountText())
          .fontSize(AppDimens.FONT_SM)
          .fontColor(AppColors.PRIMARY)
          .margin({ top: 12 })
          .width('100%')
      }
    }
    .width('100%')
    .padding(AppDimens.PADDING_LG)
    .backgroundColor(AppColors.CARD_BG)
    .borderRadius(AppDimens.RADIUS_LG)
    .shadow({ radius: 10, color: '#00000012', offsetY: 4 })
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
            .fill(this.isNodeSelected(item.id) ? AppColors.PRIMARY : AppColors.CARD_BG)
            .stroke(this.isNodeSelected(item.id) ? AppColors.PRIMARY : AppColors.DIVIDER)
            .strokeWidth(2)
          if (this.isNodeSelected(item.id)) {
            Text('✓')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.TEXT_ON_PRIMARY)
          }
        }
        .width(28)
        .height(92)
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
            Text('📷')
              .fontSize(20)
              .opacity(0.4)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#F5F5F5')
        }
      }
      .width(92)
      .height(92)
      .borderRadius(AppDimens.RADIUS_MD)
      .clip(true)
      .margin({ left: this.isManageMode ? 8 : 0 })

      Column() {
        Row() {
          Text(item.title)
            .fontSize(AppDimens.FONT_LG)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_PRIMARY)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(item.tripIsPublic ? '公开' : '私密')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(item.tripIsPublic ? '#167D3E' : '#A55B00')
            .backgroundColor(item.tripIsPublic ? '#E8F5E9' : '#FFF4E5')
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .borderRadius(12)
        }
        .width('100%')

        Text(`📍 ${item.poiName}`)
          .fontSize(AppDimens.FONT_SM)
          .fontColor(AppColors.TEXT_SECONDARY)
          .margin({ top: 6 })
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(item.content)
          .fontSize(AppDimens.FONT_SM)
          .fontColor(AppColors.TEXT_SECONDARY)
          .lineHeight(20)
          .margin({ top: 8 })
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row() {
          Text(`${this.formatDate(item.createdAt)} ${this.formatTime(item.createdAt)}`)
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_HINT)
          Text(`· ${item.tripName}`)
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.PRIMARY)
            .margin({ left: 8 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .margin({ top: 10 })
      }
      .layoutWeight(1)
      .margin({ left: 12 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(AppDimens.PADDING_MD)
    .backgroundColor(this.isNodeSelected(item.id) ? '#F3F9FF' : AppColors.CARD_BG)
    .borderRadius(AppDimens.RADIUS_MD)
    .border({
      width: this.isNodeSelected(item.id) ? 1.5 : 0,
      color: this.isNodeSelected(item.id) ? '#B7DCFF' : AppColors.CARD_BG
    })
    .shadow({ radius: 6, color: '#0000000F', offsetY: 2 })
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
        .fontColor(AppColors.PRIMARY)
        .backgroundColor('#EAF4FF')
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
    .padding({ top: 12, bottom: 10 })
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
          Text(`把已选 ${this.selectedNodeIds.length} 个节点归到同一个旅行中`)
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
          .backgroundColor('#F3F4F6')
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
        .backgroundColor('#F7F8FA')
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
              .backgroundColor('#F7F8FA')
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
          Text('你也可以先把这些节点放到“未分类”里。')
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
    .backgroundColor(AppColors.CARD_BG)
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
            Text('从地图或这里开始，记录你的第一个地点记忆。')
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
        } else {
          List({ space: 12 }) {
            ForEach(this.nodes, (item: NodeFeedItem) => {
              ListItem() {
                this.buildNodeCard(item)
              }
            }, (item: NodeFeedItem) => `${item.id}-${item.travelId}-${item.tripName}`)
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ top: 16, bottom: 8 })
        }

        if (this.isManageMode && this.nodes.length > 0) {
          this.buildBulkActionBar()
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: AppDimens.PADDING_MD })
      .backgroundColor(AppColors.BACKGROUND)

      if (this.showBulkTripSelector) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#00000055')
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
