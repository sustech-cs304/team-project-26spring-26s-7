import { router, promptAction } from '@kit.ArkUI'
import { AppColors, AppDimens, RouterUrls, getDataService } from '../../../common'
import { RouterParam } from '../../../common'
import type { MemoryNode } from '../../../common'

interface TripNodeItem {
  id: string
  title: string
  poiName: string
  createdAt: number
  photoCount: number
  contentPreview: string
}

@Entry
@Component
export struct TripEditPage {
  @State tripId: string = ''
  @State title: string = ''
  @State isPublic: boolean = false
  @State isEditMode: boolean = false
  @State isLoading: boolean = false
  @State isSaving: boolean = false
  @State nodes: TripNodeItem[] = []

  private dataService = getDataService()

  private bumpTravelDataVersion(): void {
    const version = (AppStorage.get('travelDataVersion') as number) || 0
    AppStorage.setOrCreate('travelDataVersion', version + 1)
  }

  aboutToAppear(): void {
    const params = router.getParams() as RouterParam
    if (params?.tripId) {
      this.tripId = params.tripId
      this.isEditMode = true
      this.loadTrip()
    }
  }

  onPageShow(): void {
    if (this.tripId.length > 0) {
      this.loadNodesOnly()
    }
  }

  private formatDate(timestamp: number): string {
    const date = new Date(timestamp)
    const year = date.getFullYear().toString()
    const month = (date.getMonth() + 1).toString().padStart(2, '0')
    const day = date.getDate().toString().padStart(2, '0')
    return `${year}.${month}.${day}`
  }

  private formatDateRange(): string {
    if (this.nodes.length === 0) {
      return '保存后即可继续向 Track 中添加节点'
    }

    const sortedNodes = [...this.nodes].sort((left: TripNodeItem, right: TripNodeItem) => left.createdAt - right.createdAt)
    const start = this.formatDate(sortedNodes[0].createdAt)
    const end = this.formatDate(sortedNodes[sortedNodes.length - 1].createdAt)
    return start === end ? start : `${start} ~ ${end}`
  }

  private mapNode(node: MemoryNode): TripNodeItem {
    return {
      id: node.id,
      title: node.title,
      poiName: node.poiName,
      createdAt: node.createdAt,
      photoCount: node.photos.length,
      contentPreview: node.content.trim().length > 0 ? node.content : '还没有补充正文'
    }
  }

  private async loadNodesOnly(): Promise<void> {
    if (this.tripId.length === 0) {
      this.nodes = []
      return
    }

    try {
      const nodes = await this.dataService.getNodesByTravelId(this.tripId)
      this.nodes = nodes.map((node: MemoryNode) => this.mapNode(node))
    } catch (_) {
      promptAction.showToast({ message: '加载 Track 节点失败' })
    }
  }

  private async loadTrip(): Promise<void> {
    if (this.tripId.length === 0) {
      return
    }

    this.isLoading = true
    try {
      const trip = await this.dataService.getTravelById(this.tripId)
      if (!trip) {
        promptAction.showToast({ message: '未找到对应 Track' })
        return
      }

      this.title = trip.name
      this.isPublic = trip.isPublic
      await this.loadNodesOnly()
    } catch (_) {
      promptAction.showToast({ message: '加载 Track 信息失败' })
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

  private handleAddNode(): void {
    if (this.tripId.length === 0) {
      promptAction.showToast({ message: '请先保存 Track，再添加节点' })
      return
    }

    router.pushUrl({
      url: RouterUrls.NODE_EDIT,
      params: { tripId: this.tripId } as RouterParam
    })
  }

  private async moveNode(index: number, offset: number): Promise<void> {
    const targetIndex = index + offset
    if (targetIndex < 0 || targetIndex >= this.nodes.length) {
      return
    }

    const nextNodes = [...this.nodes]
    const temp = nextNodes[index]
    nextNodes[index] = nextNodes[targetIndex]
    nextNodes[targetIndex] = temp
    this.nodes = nextNodes

    try {
      await this.dataService.reorderNodes(this.tripId, nextNodes.map((item: TripNodeItem) => item.id))
      this.bumpTravelDataVersion()
    } catch (_) {
      promptAction.showToast({ message: '节点排序失败' })
      await this.loadNodesOnly()
    }
  }

  private async handleSave(): Promise<void> {
    const trimmedTitle = this.title.trim()
    if (trimmedTitle.length === 0) {
      promptAction.showToast({ message: '请先填写 Track 标题' })
      return
    }

    this.isSaving = true
    try {
      if (this.isEditMode && this.tripId.length > 0) {
        await this.dataService.updateTravel(this.tripId, {
          name: trimmedTitle,
          isPublic: this.isPublic
        })
        this.bumpTravelDataVersion()
        promptAction.showToast({ message: 'Track 已更新' })
        router.back()
        return
      }

      const now = Date.now()
      const createdTrip = await this.dataService.createTravel({
        name: trimmedTitle,
        description: '',
        coverPhoto: '',
        isPublic: this.isPublic,
        startDate: now,
        endDate: now,
        nodeIds: [],
        totalDistance: 0
      })

      this.bumpTravelDataVersion()
      promptAction.showToast({ message: 'Track 已创建，可继续添加节点' })
      router.replaceUrl({
        url: RouterUrls.TRIP_EDIT,
        params: { tripId: createdTrip.id } as RouterParam
      })
    } catch (_) {
      promptAction.showToast({ message: '保存 Track 失败' })
    } finally {
      this.isSaving = false
    }
  }

  @Builder
  private buildVisibilityCard() {
    Column() {
      Text('可见范围')
        .fontSize(AppDimens.FONT_MD)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColors.TEXT_PRIMARY)
        .width('100%')

      Row({ space: 10 }) {
        Text('私密')
          .fontSize(AppDimens.FONT_MD)
          .fontColor(!this.isPublic ? AppColors.CARD_BG : AppColors.TEXT_SECONDARY)
          .backgroundColor(!this.isPublic ? '#A55B00' : AppColors.BACKGROUND)
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .borderRadius(18)
          .onClick(() => { this.isPublic = false })
        Text('公开')
          .fontSize(AppDimens.FONT_MD)
          .fontColor(this.isPublic ? AppColors.CARD_BG : AppColors.TEXT_SECONDARY)
          .backgroundColor(this.isPublic ? '#167D3E' : AppColors.BACKGROUND)
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .borderRadius(18)
          .onClick(() => { this.isPublic = true })
      }
      .margin({ top: 12 })

      Text(this.isPublic ? '分享时默认允许他人查看这条旅行路线。' : '仅自己可见，适合先整理未完成的旅行内容。')
        .fontSize(AppDimens.FONT_SM)
        .fontColor(AppColors.TEXT_HINT)
        .lineHeight(20)
        .width('100%')
        .margin({ top: 12 })
    }
    .width('100%')
    .padding(AppDimens.PADDING_MD)
    .backgroundColor(AppColors.CARD_BG)
    .borderRadius(AppDimens.RADIUS_MD)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildNodeCard(item: TripNodeItem, index: number) {
    Column() {
      Row() {
        Column() {
          Text(item.title)
            .fontSize(AppDimens.FONT_MD)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_PRIMARY)
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`📍 ${item.poiName}`)
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_SECONDARY)
            .margin({ top: 4 })
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(item.contentPreview)
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_HINT)
            .lineHeight(20)
            .margin({ top: 8 })
            .width('100%')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column({ space: 8 }) {
          Button('↑')
            .width(32)
            .height(28)
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_PRIMARY)
            .backgroundColor(AppColors.BACKGROUND)
            .enabled(index > 0)
            .onClick(() => { this.moveNode(index, -1) })
          Button('↓')
            .width(32)
            .height(28)
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_PRIMARY)
            .backgroundColor(AppColors.BACKGROUND)
            .enabled(index < this.nodes.length - 1)
            .onClick(() => { this.moveNode(index, 1) })
        }
        .margin({ left: 12 })
      }
      .width('100%')

      Row() {
        Text(`${this.formatDate(item.createdAt)} · ${item.photoCount} 张图`)
          .fontSize(AppDimens.FONT_SM)
          .fontColor(AppColors.TEXT_HINT)
        Blank()
        Text('查看节点 >')
          .fontSize(AppDimens.FONT_SM)
          .fontColor(AppColors.PRIMARY)
      }
      .width('100%')
      .margin({ top: 12 })
      .onClick(() => this.openNodeDetail(item.id))
    }
    .width('100%')
    .padding(AppDimens.PADDING_MD)
    .backgroundColor(AppColors.CARD_BG)
    .borderRadius(AppDimens.RADIUS_MD)
    .shadow({ radius: 4, color: '#0000000D', offsetY: 2 })
  }

  build() {
    Column() {
      Row() {
        Text('←')
          .fontSize(AppDimens.FONT_XL)
          .fontColor(AppColors.TEXT_PRIMARY)
          .padding(AppDimens.PADDING_MD)
          .onClick(() => router.back())
        Text(this.isEditMode ? '编辑 Track' : '新建 Track')
          .fontSize(AppDimens.FONT_LG)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
        Text(this.isSaving ? '保存中...' : '保存')
          .fontSize(AppDimens.FONT_MD)
          .fontColor(AppColors.PRIMARY)
          .padding(AppDimens.PADDING_MD)
          .onClick(() => this.handleSave())
      }
      .width('100%')
      .height(56)
      .backgroundColor(AppColors.CARD_BG)

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
          Text('正在加载 Track...')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_HINT)
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column() {
            Column() {
              Text(this.isEditMode ? '整理这一段旅行' : '先创建一个新的旅行容器')
                .fontSize(28)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppColors.TEXT_PRIMARY)
                .width('100%')
              Text('标题、可见范围和节点顺序会共同决定这条 Track 的浏览体验。')
                .fontSize(AppDimens.FONT_MD)
                .fontColor(AppColors.TEXT_SECONDARY)
                .lineHeight(22)
                .width('100%')
                .margin({ top: 8 })

              Row({ space: 18 }) {
                Column() {
                  Text(this.nodes.length.toString())
                    .fontSize(AppDimens.FONT_XL)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(AppColors.TEXT_PRIMARY)
                  Text('节点数量')
                    .fontSize(AppDimens.FONT_SM)
                    .fontColor(AppColors.TEXT_HINT)
                    .margin({ top: 4 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Column() {
                  Text(this.isPublic ? '公开' : '私密')
                    .fontSize(AppDimens.FONT_XL)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(AppColors.TEXT_PRIMARY)
                  Text('当前状态')
                    .fontSize(AppDimens.FONT_SM)
                    .fontColor(AppColors.TEXT_HINT)
                    .margin({ top: 4 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .margin({ top: 18 })
            }
            .width('100%')
            .padding(AppDimens.PADDING_LG)
            .backgroundColor(AppColors.CARD_BG)
            .borderRadius(AppDimens.RADIUS_LG)
            .alignItems(HorizontalAlign.Start)

            Column() {
              Text('Track 标题')
                .fontSize(AppDimens.FONT_MD)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppColors.TEXT_PRIMARY)
              TextInput({ placeholder: '例如：清明杭州 City Walk', text: this.title })
                .width('100%')
                .margin({ top: 10 })
                .backgroundColor(AppColors.BACKGROUND)
                .onChange((value: string) => { this.title = value })
            }
            .width('100%')
            .padding(AppDimens.PADDING_MD)
            .margin({ top: 14 })
            .backgroundColor(AppColors.CARD_BG)
            .borderRadius(AppDimens.RADIUS_MD)
            .alignItems(HorizontalAlign.Start)

            Column() {
              this.buildVisibilityCard()
            }
            .width('100%')
            .margin({ top: 14 })

            Column() {
              Row() {
                Column() {
                  Text('关联节点')
                    .fontSize(AppDimens.FONT_MD)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(AppColors.TEXT_PRIMARY)
                  Text(this.formatDateRange())
                    .fontSize(AppDimens.FONT_SM)
                    .fontColor(AppColors.TEXT_HINT)
                    .margin({ top: 4 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Button(this.tripId.length > 0 ? '添加节点' : '先保存')
                  .height(34)
                  .fontSize(AppDimens.FONT_SM)
                  .backgroundColor(AppColors.PRIMARY)
                  .onClick(() => this.handleAddNode())
              }
              .width('100%')

              if (this.nodes.length === 0) {
                Column() {
                  Text('还没有加入节点')
                    .fontSize(AppDimens.FONT_MD)
                    .fontColor(AppColors.TEXT_PRIMARY)
                  Text('创建后可以从地图、节点列表或这里继续往 Track 中补内容。')
                    .fontSize(AppDimens.FONT_SM)
                    .fontColor(AppColors.TEXT_HINT)
                    .lineHeight(20)
                    .margin({ top: 8 })
                }
                .width('100%')
                .padding({ top: 16, bottom: 8 })
                .alignItems(HorizontalAlign.Start)
              } else {
                Column({ space: 10 }) {
                  ForEach(this.nodes, (item: TripNodeItem, index: number) => {
                    this.buildNodeCard(item, index)
                  }, (item: TripNodeItem) => item.id)
                }
                .width('100%')
                .margin({ top: 16 })
              }
            }
            .width('100%')
            .padding(AppDimens.PADDING_MD)
            .margin({ top: 14, bottom: 24 })
            .backgroundColor(AppColors.CARD_BG)
            .borderRadius(AppDimens.RADIUS_MD)
            .alignItems(HorizontalAlign.Start)
          }
          .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 16 })
        }
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.BACKGROUND)
  }
}
