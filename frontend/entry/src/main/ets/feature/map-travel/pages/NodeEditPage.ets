import { router, promptAction } from '@kit.ArkUI'
import { AppColors, AppDimens, RouterUrls, getDataService } from '../../../common'
import { RouterParam } from '../../../common'
import type { Trip } from '../../../common'
import { PhotoSelector } from '../components/PhotoSelector'

const NODE_TITLE_MAX_LENGTH: number = 20
const NODE_TITLE_WARNING_RATIO: number = 0.85
const NODE_CONTENT_MAX_LENGTH: number = 1000
const NODE_CONTENT_WARNING_RATIO: number = 0.85
const QUICK_TRIP_NAME_MAX_LENGTH: number = 40

@Entry
@Component
export struct NodeEditPage {
  @State title: string = ''
  @State content: string = ''
  @State poiName: string = '点击选择位置'
  @State mood: string = ''
  @State tags: string[] = []
  @State photos: string[] = []
  @State isEditMode: boolean = false
  @State isSaving: boolean = false
  @State tripId: string = ''
  @State nodeId: string = ''
  @State latitude: number = 0
  @State longitude: number = 0
  @State hasPickedLocation: boolean = false
  @State availableTrips: Trip[] = []
  @State showTripSelector: boolean = false
  @State showQuickTripCreator: boolean = false
  @State quickTripName: string = ''
  @State isCreatingQuickTrip: boolean = false

  private dataService = getDataService()

  private bumpTravelDataVersion(): void {
    const version = (AppStorage.get('travelDataVersion') as number) || 0
    AppStorage.setOrCreate('travelDataVersion', version + 1)
  }

  aboutToAppear(): void {
    const params = router.getParams() as RouterParam
    if (params?.nodeId && params.nodeId.length > 0) {
      this.isEditMode = true
      this.nodeId = params.nodeId
      this.loadNodeForEdit(params.nodeId)
    }

    if (params?.tripId) {
      this.tripId = params.tripId
    }

    if (typeof params?.latitude === 'number' && typeof params?.longitude === 'number') {
      this.latitude = params.latitude
      this.longitude = params.longitude
      this.poiName = params.poiName && params.poiName.trim().length > 0
        ? params.poiName
        : `${params.latitude.toFixed(4)}, ${params.longitude.toFixed(4)}`
      this.hasPickedLocation = true
    }

    this.loadAvailableTrips()
  }

  onPageShow(): void {
    const picked = AppStorage.get('locationPicked') as boolean
    if (picked) {
      this.latitude = (AppStorage.get('pickedLatitude') as number) || 0
      this.longitude = (AppStorage.get('pickedLongitude') as number) || 0
      this.poiName = (AppStorage.get('pickedPoiName') as string) || ''
      this.hasPickedLocation = true
      AppStorage.setOrCreate('locationPicked', false)
    }
  }

  private async loadAvailableTrips(): Promise<void> {
    try {
      const trips = await this.dataService.getAllTravels()
      this.availableTrips = trips

      // For create mode, default to latest trip when user does not choose.
      if (!this.isEditMode && this.tripId.length === 0 && trips.length > 0) {
        this.tripId = trips[0].id
      }
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

  private getCurrentTripName(): string {
    if (this.tripId.length > 0) {
      const selected = this.availableTrips.find((trip: Trip) => trip.id === this.tripId)
      if (selected) {
        return selected.name
      }
      return '当前旅行'
    }
    if (this.availableTrips.length === 0) {
      return '无可选旅行（保存时自动创建）'
    }
    return '请选择旅行'
  }

  private async loadNodeForEdit(nodeId: string): Promise<void> {
    try {
      const node = await this.dataService.getNodeById(nodeId)
      if (!node) {
        promptAction.showToast({ message: '未找到要编辑的节点' })
        return
      }

      this.tripId = node.travelId
      this.title = node.title
      this.content = node.content
      this.poiName = node.poiName
      this.mood = node.mood
      this.tags = [...node.tags]
      this.photos = [...node.photos]
      this.latitude = node.latitude
      this.longitude = node.longitude
      this.hasPickedLocation = true
      await this.loadAvailableTrips()
    } catch (_) {
      promptAction.showToast({ message: '加载节点数据失败' })
    }
  }

  private async resolveTargetTripId(): Promise<string> {
    if (this.tripId.length > 0) {
      return this.tripId
    }

    const existingTrips = await this.dataService.getAllTravels()
    if (existingTrips.length > 0) {
      // Default to latest trip when user did not choose.
      this.tripId = existingTrips[0].id
      return this.tripId
    }

    const now = Date.now()
    const createdTrip = await this.dataService.createTravel({
      name: `新旅行 ${this.formatDate(now)}`,
      description: '',
      coverPhoto: '',
      isPublic: false,
      startDate: now,
      endDate: now,
      nodeIds: [],
      totalDistance: 0
    })
    this.tripId = createdTrip.id
    await this.loadAvailableTrips()
    return this.tripId
  }

  private async handleSave(): Promise<void> {
    const trimmedTitle = this.title.trim()
    if (trimmedTitle.length === 0) {
      promptAction.showToast({ message: '请先填写标题' })
      return
    }

    if (trimmedTitle.length > NODE_TITLE_MAX_LENGTH) {
      promptAction.showToast({ message: `标题最多 ${NODE_TITLE_MAX_LENGTH} 字` })
      return
    }

    if (!this.hasPickedLocation) {
      promptAction.showToast({ message: '请先在地图上选择位置' })
      return
    }

    this.isSaving = true
    try {
      const targetTripId = await this.resolveTargetTripId()
      const poiValue = this.poiName.trim()
      const resolvedPoiName =
        (poiValue.length === 0 || poiValue === '点击选择位置' || poiValue === '获取位置中...')
          ? trimmedTitle
          : poiValue

      if (this.isEditMode && this.nodeId.length > 0) {
        await this.dataService.updateNode(this.nodeId, {
          travelId: targetTripId,
          title: trimmedTitle,
          content: this.content,
          latitude: this.latitude,
          longitude: this.longitude,
          poiName: resolvedPoiName,
          photos: this.photos,
          mood: this.mood,
          tags: this.tags
        })
        promptAction.showToast({ message: '记忆已更新' })
      } else {
        await this.dataService.createNode({
          travelId: targetTripId,
          title: trimmedTitle,
          content: this.content,
          latitude: this.latitude,
          longitude: this.longitude,
          poiName: resolvedPoiName,
          photos: this.photos,
          mood: this.mood,
          tags: this.tags
        })
        promptAction.showToast({ message: '记忆已保存' })
      }
      this.bumpTravelDataVersion()
      router.back()
    } catch (_) {
      promptAction.showToast({ message: '保存失败，请稍后重试' })
    } finally {
      this.isSaving = false
    }
  }

  private handleNavigateToAI(): void {
    router.pushUrl({
      url: RouterUrls.AI_COPY,
      params: {
        defaultPrompt: this.content,
        defaultTitle: this.title
      }
    })
  }

  private openTripSelector(): void {
    this.showQuickTripCreator = false
    this.quickTripName = ''
    this.showTripSelector = true
  }

  private closeTripSelector(): void {
    this.showTripSelector = false
    this.showQuickTripCreator = false
    this.quickTripName = ''
    this.isCreatingQuickTrip = false
  }

  private chooseTrip(trip: Trip): void {
    this.tripId = trip.id
    this.closeTripSelector()
  }

  private openQuickTripCreator(): void {
    this.showQuickTripCreator = true
    if (this.quickTripName.trim().length === 0) {
      this.quickTripName = `新旅行 ${this.formatDate(Date.now())}`
    }
  }

  private cancelQuickTripCreator(): void {
    this.showQuickTripCreator = false
    this.quickTripName = ''
  }

  private getTripSelectorListHeight(): number {
    if (this.availableTrips.length === 0) {
      return 0
    }
    return Math.min(336, this.availableTrips.length * 78)
  }

  private getTripSelectorHeight(): number {
    const headerHeight = 92
    const creatorHeight = this.showQuickTripCreator ? 116 : 0
    const bodyHeight = this.availableTrips.length > 0 ? this.getTripSelectorListHeight() : 132
    return Math.min(560, headerHeight + creatorHeight + bodyHeight + 28)
  }

  private async handleQuickCreateTrip(): Promise<void> {
    const name = this.quickTripName.trim()
    if (name.length === 0) {
      promptAction.showToast({ message: '请先填写旅行名称' })
      return
    }
    if (this.isCreatingQuickTrip) {
      return
    }

    this.isCreatingQuickTrip = true
    try {
      const now = Date.now()
      const createdTrip = await this.dataService.createTravel({
        name: name.length > QUICK_TRIP_NAME_MAX_LENGTH ? name.slice(0, QUICK_TRIP_NAME_MAX_LENGTH) : name,
        description: '',
        coverPhoto: '',
        isPublic: false,
        startDate: now,
        endDate: now,
        nodeIds: [],
        totalDistance: 0
      })
      this.bumpTravelDataVersion()
      await this.loadAvailableTrips()
      this.tripId = createdTrip.id
      promptAction.showToast({ message: '已新建并选中旅行' })
      this.closeTripSelector()
    } catch (_) {
      promptAction.showToast({ message: '新建旅行失败，请稍后重试' })
    } finally {
      this.isCreatingQuickTrip = false
    }
  }

  private updateContent(value: string): void {
    this.content = value.length > NODE_CONTENT_MAX_LENGTH
      ? value.slice(0, NODE_CONTENT_MAX_LENGTH)
      : value
  }

  private updateTitle(value: string): void {
    this.title = value.length > NODE_TITLE_MAX_LENGTH
      ? value.slice(0, NODE_TITLE_MAX_LENGTH)
      : value
  }

  private getTitleCounterColor(): string {
    if (this.title.length >= NODE_TITLE_MAX_LENGTH) {
      return AppColors.DANGER
    }
    if (this.title.length >= NODE_TITLE_MAX_LENGTH * NODE_TITLE_WARNING_RATIO) {
      return '#D97904'
    }
    return AppColors.TEXT_HINT
  }

  private getTitleBorderColor(): string {
    if (this.title.length >= NODE_TITLE_MAX_LENGTH) {
      return AppColors.DANGER
    }
    if (this.title.length >= NODE_TITLE_MAX_LENGTH * NODE_TITLE_WARNING_RATIO) {
      return '#F5B041'
    }
    return AppColors.DIVIDER
  }

  private getTitleHintText(): string {
    if (this.title.length >= NODE_TITLE_MAX_LENGTH) {
      return '已达到标题上限'
    }
    if (this.title.length >= NODE_TITLE_MAX_LENGTH * NODE_TITLE_WARNING_RATIO) {
      return '已接近标题上限'
    }
    return '标题会在达到上限后自动停止输入'
  }

  private getContentCounterColor(): string {
    if (this.content.length >= NODE_CONTENT_MAX_LENGTH) {
      return AppColors.DANGER
    }
    if (this.content.length >= NODE_CONTENT_MAX_LENGTH * NODE_CONTENT_WARNING_RATIO) {
      return '#D97904'
    }
    return AppColors.TEXT_HINT
  }

  private getContentBorderColor(): string {
    if (this.content.length >= NODE_CONTENT_MAX_LENGTH) {
      return AppColors.DANGER
    }
    if (this.content.length >= NODE_CONTENT_MAX_LENGTH * NODE_CONTENT_WARNING_RATIO) {
      return '#F5B041'
    }
    return AppColors.DIVIDER
  }

  private getContentHintText(): string {
    if (this.content.length >= NODE_CONTENT_MAX_LENGTH) {
      return '已达到正文上限'
    }
    if (this.content.length >= NODE_CONTENT_MAX_LENGTH * NODE_CONTENT_WARNING_RATIO) {
      return '已接近正文上限'
    }
    return '正文会在达到上限后自动停止输入'
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Text('<')
            .fontSize(AppDimens.FONT_XL)
            .fontColor(AppColors.TEXT_PRIMARY)
            .onClick(() => router.back())
            .padding(AppDimens.PADDING_MD)
          Text(this.isEditMode ? '编辑记忆' : '新建记忆')
            .fontSize(AppDimens.FONT_LG)
            .fontWeight(FontWeight.Bold)
            .layoutWeight(1)
          Text(this.isSaving ? '保存中...' : '保存')
            .fontSize(AppDimens.FONT_LG)
            .fontColor(AppColors.PRIMARY)
            .padding(AppDimens.PADDING_MD)
            .onClick(() => this.handleSave())
        }
        .width('100%')
        .height(56)
        .backgroundColor(AppColors.CARD_BG)

        Scroll() {
          Column() {
            // 位置信息
            Row() {
              Text('📍')
                .fontSize(18)
              Text(this.poiName)
                .fontSize(AppDimens.FONT_MD)
                .fontColor(AppColors.TEXT_SECONDARY)
                .margin({ left: 8 })
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text('重新选点 >')
                .fontSize(AppDimens.FONT_SM)
                .fontColor(AppColors.PRIMARY)
                .onClick(() => {
                  router.pushUrl({ url: RouterUrls.LOCATION_PICKER })
                })
            }
            .width('100%')
            .padding(AppDimens.PADDING_MD)
            .backgroundColor(AppColors.CARD_BG)
            .borderRadius(AppDimens.RADIUS_SM)
            .onClick(() => {
              router.pushUrl({ url: RouterUrls.LOCATION_PICKER })
            })

            Row() {
              Text('🧳')
                .fontSize(18)
              Column() {
                Text(this.getCurrentTripName())
                  .fontSize(AppDimens.FONT_MD)
                  .fontColor(AppColors.TEXT_SECONDARY)
                  .width('100%')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.isEditMode ? '切换所属旅行' : '选择旅行')
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(AppColors.TEXT_HINT)
                  .margin({ top: 4 })
              }
              .margin({ left: 8 })
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              Text('选择旅行 >')
                .fontSize(AppDimens.FONT_SM)
                .fontColor(AppColors.PRIMARY)
                .onClick(() => this.openTripSelector())
            }
            .width('100%')
            .padding(AppDimens.PADDING_MD)
            .margin({ top: 12 })
            .backgroundColor(AppColors.CARD_BG)
            .borderRadius(AppDimens.RADIUS_SM)
            .onClick(() => this.openTripSelector())

            // 照片选择区 (使用 PhotoSelector 组件)
            PhotoSelector({ photos: $photos, maxPhotos: 9 })
              .width('100%')
              .padding(AppDimens.PADDING_MD)
              .margin({ top: 12 })
              .backgroundColor(AppColors.CARD_BG)
              .borderRadius(AppDimens.RADIUS_SM)

            // 标题
            Column() {
              Text('标题')
                .fontSize(AppDimens.FONT_MD)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppColors.TEXT_PRIMARY)
              TextInput({ placeholder: '给这段记忆起个名字', text: this.title })
                .onChange((value: string) => { this.updateTitle(value) })
                .maxLength(NODE_TITLE_MAX_LENGTH)
                .margin({ top: 8 })
                .backgroundColor(AppColors.BACKGROUND)
                .border({
                  width: 1,
                  color: this.getTitleBorderColor()
                })
                .borderRadius(AppDimens.RADIUS_SM)
              Row() {
                Text(this.getTitleHintText())
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(this.getTitleCounterColor())
                Blank()
                Text(`${this.title.length}/${NODE_TITLE_MAX_LENGTH}`)
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(this.getTitleCounterColor())
              }
              .width('100%')
              .margin({ top: 8 })
            }
            .width('100%')
            .padding(AppDimens.PADDING_MD)
            .margin({ top: 12 })
            .backgroundColor(AppColors.CARD_BG)
            .borderRadius(AppDimens.RADIUS_SM)
            .alignItems(HorizontalAlign.Start)

            // 内容
            Column() {
              Text('内容')
                .fontSize(AppDimens.FONT_MD)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppColors.TEXT_PRIMARY)
              TextArea({ placeholder: '写下这一刻的感受...', text: this.content })
                .onChange((value: string) => { this.updateContent(value) })
                .maxLength(NODE_CONTENT_MAX_LENGTH)
                .height(120)
                .margin({ top: 8 })
                .backgroundColor(AppColors.BACKGROUND)
                .border({
                  width: 1,
                  color: this.getContentBorderColor()
                })
                .borderRadius(AppDimens.RADIUS_SM)
              Row() {
                Text(this.getContentHintText())
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(this.getContentCounterColor())
                Blank()
                Text(`${this.content.length}/${NODE_CONTENT_MAX_LENGTH}`)
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(this.getContentCounterColor())
              }
              .width('100%')
              .margin({ top: 8 })
            }
            .width('100%')
            .padding(AppDimens.PADDING_MD)
            .margin({ top: 12 })
            .backgroundColor(AppColors.CARD_BG)
            .borderRadius(AppDimens.RADIUS_SM)
            .alignItems(HorizontalAlign.Start)

            // AI 助手按钮
            Row() {
              Text('AI 助手')
                .fontSize(AppDimens.FONT_MD)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppColors.PRIMARY)
              Text('  帮你润色内容')
                .fontSize(AppDimens.FONT_SM)
                .fontColor(AppColors.TEXT_SECONDARY)
              Blank()
              Text('>')
                .fontSize(AppDimens.FONT_LG)
                .fontColor(AppColors.PRIMARY)
            }
            .width('100%')
            .padding(AppDimens.PADDING_MD)
            .backgroundColor(AppColors.PRIMARY + '10')
            .borderRadius(AppDimens.RADIUS_SM)
            .margin({ bottom: 12, top: 8 })
            .onClick(() => this.handleNavigateToAI())

            // 心情选择
            Column() {
              Text('心情')
                .fontSize(AppDimens.FONT_MD)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppColors.TEXT_PRIMARY)
              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                ForEach(['😊', '😢', '🤩', '😌', '🥰', '😤'], (emoji: string) => {
                  Text(emoji)
                    .fontSize(28)
                    .padding(8)
                    .borderRadius(AppDimens.RADIUS_SM)
                    .backgroundColor(this.mood === emoji ? AppColors.PRIMARY + '20' : 'transparent')
                    .border({
                      width: this.mood === emoji ? 1 : 0,
                      color: this.mood === emoji ? AppColors.PRIMARY : 'transparent'
                    })
                    .margin({ right: 12, bottom: 12 })
                    .onClick(() => {
                      this.mood = this.mood === emoji ? '' : emoji
                    })
                })
              }
              .margin({ top: 8 })
              Text(this.mood.length > 0 ? `当前已选：${this.mood}，再次点击可取消` : '未选择表情，可直接留空')
                .fontSize(AppDimens.FONT_SM)
                .fontColor(AppColors.TEXT_HINT)
            }
            .width('100%')
            .padding(AppDimens.PADDING_MD)
            .margin({ top: 12 })
            .backgroundColor(AppColors.CARD_BG)
            .borderRadius(AppDimens.RADIUS_SM)
            .alignItems(HorizontalAlign.Start)

            // 标签
            Column() {
              Text('标签')
                .fontSize(AppDimens.FONT_MD)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppColors.TEXT_PRIMARY)
              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                ForEach(['旅行', '美食', '风景', '打卡', '日常'], (tag: string) => {
                  Text(`#${tag}`)
                    .fontSize(AppDimens.FONT_SM)
                    .fontColor(this.tags.includes(tag) ? AppColors.CARD_BG : AppColors.PRIMARY)
                    .backgroundColor(this.tags.includes(tag) ? AppColors.PRIMARY : AppColors.PRIMARY + '15')
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .borderRadius(20)
                    .margin({ right: 8, bottom: 8 })
                    .onClick(() => {
                      if (this.tags.includes(tag)) {
                        this.tags = this.tags.filter(t => t !== tag)
                      } else {
                        this.tags = [...this.tags, tag]
                      }
                    })
                })
              }
              .margin({ top: 8 })
            }
            .width('100%')
            .padding(AppDimens.PADDING_MD)
            .margin({ top: 12, bottom: 24 })
            .backgroundColor(AppColors.CARD_BG)
            .borderRadius(AppDimens.RADIUS_SM)
            .alignItems(HorizontalAlign.Start)
          }
          .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 12 })
        }
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.BACKGROUND)

      // 旅行选择弹窗
      if (this.showTripSelector) {
        Column() {
          Column()
            .width('100%')
            .layoutWeight(1)
            .onClick(() => this.closeTripSelector())

          Column() {
            Row() {
              Column() {
                Text('选择旅行')
                  .fontSize(AppDimens.FONT_LG)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(AppColors.TEXT_PRIMARY)
                Text('把这条记忆放进合适的旅行里')
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(AppColors.TEXT_HINT)
                  .margin({ top: 6 })
              }
              .alignItems(HorizontalAlign.Start)

              Blank()

              Text(this.showQuickTripCreator ? '收起' : '+ 新建')
                .fontSize(AppDimens.FONT_MD)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppColors.PRIMARY)
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .backgroundColor(AppColors.PRIMARY + '12')
                .borderRadius(16)
                .onClick(() => {
                  if (this.showQuickTripCreator) {
                    this.cancelQuickTripCreator()
                  } else {
                    this.openQuickTripCreator()
                  }
                })
            }
            .width('100%')

            if (this.showQuickTripCreator) {
              Column() {
                TextInput({ placeholder: '输入旅行名称', text: this.quickTripName })
                  .onChange((value: string) => {
                    this.quickTripName = value.length > QUICK_TRIP_NAME_MAX_LENGTH
                      ? value.slice(0, QUICK_TRIP_NAME_MAX_LENGTH)
                      : value
                  })
                  .maxLength(QUICK_TRIP_NAME_MAX_LENGTH)
                  .backgroundColor(AppColors.CARD_BG)
                  .borderRadius(16)
                Row() {
                  Text(`${this.quickTripName.length}/${QUICK_TRIP_NAME_MAX_LENGTH}`)
                    .fontSize(AppDimens.FONT_SM)
                    .fontColor(AppColors.TEXT_HINT)
                  Blank()
                  Button('取消')
                    .height(34)
                    .fontSize(AppDimens.FONT_SM)
                    .fontColor(AppColors.TEXT_SECONDARY)
                    .backgroundColor(AppColors.CARD_BG)
                    .borderRadius(17)
                    .onClick(() => this.cancelQuickTripCreator())
                  Button(this.isCreatingQuickTrip ? '创建中...' : '创建')
                    .height(34)
                    .fontSize(AppDimens.FONT_SM)
                    .fontColor(AppColors.CARD_BG)
                    .backgroundColor(AppColors.PRIMARY)
                    .borderRadius(17)
                    .margin({ left: 8 })
                    .enabled(!this.isCreatingQuickTrip)
                    .onClick(() => this.handleQuickCreateTrip())
                }
                .width('100%')
                .margin({ top: 10 })
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 14, bottom: 14 })
              .margin({ top: 14, bottom: 12 })
              .backgroundColor(AppColors.BACKGROUND)
              .borderRadius(18)
              .alignItems(HorizontalAlign.Start)
            }

            if (this.availableTrips.length === 0) {
              Column() {
                Text('还没有旅行')
                  .fontSize(AppDimens.FONT_MD)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(AppColors.TEXT_PRIMARY)
                Text('先新建一个旅行，再把这条记忆保存进去。')
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(AppColors.TEXT_HINT)
                  .margin({ top: 8 })
                Button('新建旅行')
                  .height(38)
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(AppColors.CARD_BG)
                  .backgroundColor(AppColors.PRIMARY)
                  .borderRadius(19)
                  .margin({ top: 14 })
                  .onClick(() => this.openQuickTripCreator())
              }
              .width('100%')
              .height(132)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Start)
            } else {
              Scroll() {
                Column() {
                  ForEach(this.availableTrips, (trip: Trip) => {
                    Row() {
                      Column() {
                        Text(trip.name)
                          .fontSize(AppDimens.FONT_MD)
                          .fontWeight(FontWeight.Medium)
                          .fontColor(AppColors.TEXT_PRIMARY)
                          .width('100%')
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(`${trip.nodeIds.length} 个节点 · ${trip.isPublic ? '公开' : '私密'}`)
                          .fontSize(AppDimens.FONT_SM)
                          .fontColor(AppColors.TEXT_HINT)
                          .margin({ top: 6 })
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)

                      if (trip.id === this.tripId) {
                        Text('已选')
                          .fontSize(AppDimens.FONT_SM)
                          .fontColor(AppColors.PRIMARY)
                          .fontWeight(FontWeight.Medium)
                          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                          .backgroundColor(AppColors.PRIMARY + '12')
                          .borderRadius(12)
                      }
                    }
                    .width('100%')
                    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
                    .margin({ bottom: 10 })
                    .backgroundColor(trip.id === this.tripId ? AppColors.PRIMARY + '10' : AppColors.BACKGROUND)
                    .borderRadius(18)
                    .border({
                      width: trip.id === this.tripId ? 1 : 0,
                      color: trip.id === this.tripId ? AppColors.PRIMARY + '55' : 'transparent'
                    })
                    .onClick(() => this.chooseTrip(trip))
                  })
                }
                .width('100%')
              }
              .width('100%')
              .height(this.getTripSelectorListHeight())
            }
          }
          .width('100%')
          .height(this.getTripSelectorHeight())
          .padding({ left: 16, right: 16, top: 18, bottom: 24 })
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius({ topLeft: 26, topRight: 26 })
          .shadow({ radius: 12, color: '#00000014', offsetY: -2 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .justifyContent(FlexAlign.End)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.BACKGROUND)
  }
}
