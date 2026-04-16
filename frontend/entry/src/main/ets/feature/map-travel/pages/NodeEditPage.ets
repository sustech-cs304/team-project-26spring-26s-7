import { router, promptAction } from '@kit.ArkUI'
import { AppColors, AppDimens, RouterUrls, getDataService } from '../../../common'
import { RouterParam } from '../../../common'
import type { Trip } from '../../../common'
import { PhotoSelector } from '../components/PhotoSelector'

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
    if (this.availableTrips.length === 0) {
      promptAction.showToast({ message: '暂无旅行，将在保存时自动创建' })
      return
    }
    this.showTripSelector = true
  }

  private chooseTrip(trip: Trip): void {
    this.tripId = trip.id
    this.showTripSelector = false
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
                .onChange((value: string) => { this.title = value })
                .margin({ top: 8 })
                .backgroundColor(AppColors.BACKGROUND)
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
                .onChange((value: string) => { this.content = value })
                .height(120)
                .margin({ top: 8 })
                .backgroundColor(AppColors.BACKGROUND)
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
              Row({ space: 16 }) {
                ForEach(['😊', '😢', '🤩', '😌', '🥰', '😤'], (emoji: string) => {
                  Text(emoji)
                    .fontSize(28)
                    .padding(8)
                    .borderRadius(AppDimens.RADIUS_SM)
                    .backgroundColor(this.mood === emoji ? AppColors.PRIMARY + '20' : 'transparent')
                    .onClick(() => { this.mood = emoji })
                })
              }
              .margin({ top: 8 })
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
              Row({ space: 8 }) {
                ForEach(['旅行', '美食', '风景', '打卡', '日常'], (tag: string) => {
                  Text(`#${tag}`)
                    .fontSize(AppDimens.FONT_SM)
                    .fontColor(this.tags.includes(tag) ? AppColors.CARD_BG : AppColors.PRIMARY)
                    .backgroundColor(this.tags.includes(tag) ? AppColors.PRIMARY : AppColors.PRIMARY + '15')
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .borderRadius(20)
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
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#66000000')
          .onClick(() => { this.showTripSelector = false })

        Column() {
          Text('选择旅行')
            .fontSize(AppDimens.FONT_LG)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.TEXT_PRIMARY)
            .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 16, bottom: 12 })
            .width('100%')

          Scroll() {
            Column() {
              ForEach(this.availableTrips, (trip: Trip) => {
                Row() {
                  Text(trip.name)
                    .fontSize(AppDimens.FONT_MD)
                    .fontColor(AppColors.TEXT_PRIMARY)
                    .layoutWeight(1)
                  if (trip.id === this.tripId) {
                    Text('已选')
                      .fontSize(AppDimens.FONT_SM)
                      .fontColor(AppColors.PRIMARY)
                  }
                }
                .width('100%')
                .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 14, bottom: 14 })
                .backgroundColor(AppColors.CARD_BG)
                .onClick(() => this.chooseTrip(trip))
              })
            }
          }
          .width('100%')
          .layoutWeight(1)
        }
        .width('100%')
        .height('45%')
        .backgroundColor(AppColors.CARD_BG)
        .borderRadius({ topLeft: AppDimens.RADIUS_LG, topRight: AppDimens.RADIUS_LG })
        .position({ x: 0, y: '100%' })
        .translate({ y: '-100%' })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.BACKGROUND)
  }
}