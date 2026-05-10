import {
  AppColors,
  AppDimens,
  ReplayBgmId,
  ReplayFilterCatalog,
  ReplayFilterId,
  ReplayFilterOption,
  ReplayMusicCatalog,
  ReplayMusicOption,
  ReplayPreferences,
  ReplayStyleKitCatalog,
  ReplayStyleKitId,
  ReplayStyleKitOption,
  ReplayTransitionCatalog,
  ReplayTransitionOption,
  ReplayTransitionType
} from '../../../common'

enum ReplaySettingsTab {
  STYLE = 0,
  MUSIC = 1,
  DISPLAY = 2,
  EFFECTS = 3,
  TRANSITION = 4
}

@Component
export struct ReplaySettingsSheet {
  @Prop isVisible: boolean = false
  @Prop selectedStyleKitId: ReplayStyleKitId = ReplayStyleKitCatalog.DEFAULT_ID
  @Prop selectedBgmId: ReplayBgmId = ReplayMusicCatalog.DEFAULT_ID
  @Prop selectedFilterId: ReplayFilterId = ReplayFilterId.NONE
  @Prop selectedTransitionType: ReplayTransitionType = ReplayTransitionType.FADE
  @Prop enableRouteAnimation: boolean = false
  @Prop enableBlurOverlay: boolean = false

  @State private activeTab: ReplaySettingsTab = ReplaySettingsTab.STYLE
  @State private activeStyleKitId: ReplayStyleKitId = ReplayStyleKitCatalog.DEFAULT_ID
  @State private activeBgmId: ReplayBgmId = ReplayMusicCatalog.DEFAULT_ID
  @State private activeFilterId: ReplayFilterId = ReplayFilterId.NONE
  @State private activeTransitionType: ReplayTransitionType = ReplayTransitionType.FADE
  @State private activeEnableRouteAnimation: boolean = false
  @State private activeEnableBlurOverlay: boolean = false
  @State private feedbackKey: string = ''

  onClose?: () => void
  onStyleChange?: (styleKitId: ReplayStyleKitId) => void
  onBgmChange?: (bgmId: ReplayBgmId) => void
  onFilterChange?: (filterId: ReplayFilterId) => void
  onTransitionChange?: (transitionType: ReplayTransitionType) => void
  onRouteAnimationToggle?: (enabled: boolean) => void
  onBlurOverlayToggle?: (enabled: boolean) => void

  aboutToAppear(): void {
    this.activeStyleKitId = this.selectedStyleKitId
    this.activeBgmId = this.selectedBgmId
    this.activeFilterId = this.selectedFilterId
    this.activeTransitionType = this.selectedTransitionType
    this.activeEnableRouteAnimation = this.enableRouteAnimation
    this.activeEnableBlurOverlay = this.enableBlurOverlay
  }

  private close(): void {
    if (this.onClose) {
      this.onClose()
    }
  }

  private triggerOptionFeedback(key: string): void {
    this.feedbackKey = key
    setTimeout(() => {
      if (this.feedbackKey === key) {
        this.feedbackKey = ''
      }
    }, 180)
  }

  private isHighlighted(key: string, selected: boolean): boolean {
    return selected || this.feedbackKey === key
  }

  private getCardBackground(key: string, selected: boolean): string {
    return this.isHighlighted(key, selected) ? 'rgba(24, 144, 255, 0.08)' : AppColors.CARD_BG
  }

  private getCardBorderColor(key: string, selected: boolean): string {
    return this.isHighlighted(key, selected) ? AppColors.PRIMARY : AppColors.DIVIDER
  }

  private getCardBorderWidth(key: string, selected: boolean): number {
    return this.isHighlighted(key, selected) ? 2 : 1
  }

  private getCardScale(key: string): number {
    return this.feedbackKey === key ? 0.985 : 1
  }

  private getToggleCardBackground(enabled: boolean): string {
    return enabled ? 'rgba(24, 144, 255, 0.08)' : AppColors.CARD_BG
  }

  private getToggleCardBorderColor(enabled: boolean): string {
    return enabled ? AppColors.PRIMARY : AppColors.DIVIDER
  }

  private getToggleCardBorderWidth(enabled: boolean): number {
    return enabled ? 2 : 1
  }

  private selectStyleKit(styleKitId: ReplayStyleKitId): void {
    this.activeStyleKitId = styleKitId
    this.triggerOptionFeedback(`style:${styleKitId}`)
    ReplayPreferences.setStyleKitId(styleKitId)
    if (this.onStyleChange) {
      this.onStyleChange(styleKitId)
    }
  }

  private selectBgm(bgmId: ReplayBgmId): void {
    this.activeBgmId = bgmId
    this.triggerOptionFeedback(`music:${bgmId}`)
    ReplayPreferences.setBgmId(bgmId)
    if (this.onBgmChange) {
      this.onBgmChange(bgmId)
    }
  }

  private selectFilter(filterId: ReplayFilterId): void {
    this.activeFilterId = filterId
    this.triggerOptionFeedback(`filter:${filterId}`)
    ReplayPreferences.setFilterId(filterId)
    if (this.onFilterChange) {
      this.onFilterChange(filterId)
    }
  }

  private selectTransition(transitionType: ReplayTransitionType): void {
    this.activeTransitionType = transitionType
    this.triggerOptionFeedback(`transition:${transitionType}`)
    ReplayPreferences.setTransitionType(transitionType)
    if (this.onTransitionChange) {
      this.onTransitionChange(transitionType)
    }
  }

  private toggleRouteAnimation(): void {
    const nextValue = !this.activeEnableRouteAnimation
    this.activeEnableRouteAnimation = nextValue
    ReplayPreferences.setEnableRouteAnimation(nextValue)
    if (this.onRouteAnimationToggle) {
      this.onRouteAnimationToggle(nextValue)
    }
  }

  private toggleBlurOverlay(): void {
    const nextValue = !this.activeEnableBlurOverlay
    this.activeEnableBlurOverlay = nextValue
    ReplayPreferences.setEnableBlurOverlay(nextValue)
    if (this.onBlurOverlayToggle) {
      this.onBlurOverlayToggle(nextValue)
    }
  }

  @Builder
  private buildTabButton(tab: ReplaySettingsTab, title: string) {
    Text(title)
      .fontSize(AppDimens.FONT_MD)
      .fontWeight(this.activeTab === tab ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.activeTab === tab ? AppColors.TEXT_PRIMARY : AppColors.TEXT_HINT)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor(this.activeTab === tab ? AppColors.BACKGROUND : 'transparent')
      .borderRadius(16)
      .onClick(() => {
        this.activeTab = tab
      })
  }

  @Builder
  private buildStyleCard(item: ReplayStyleKitOption) {
    Row({ space: 12 }) {
      Blank()
        .width(36)
        .height(36)
        .backgroundColor(item.previewColor)
        .borderRadius(10)

      Column() {
        Text(item.title)
          .fontSize(AppDimens.FONT_MD)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_PRIMARY)
          .width('100%')
        Text(item.subtitle)
          .fontSize(AppDimens.FONT_SM)
          .fontColor(AppColors.TEXT_HINT)
          .width('100%')
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(this.activeStyleKitId === item.id ? '当前使用' : '点击选择')
        .fontSize(AppDimens.FONT_SM)
        .fontColor(this.activeStyleKitId === item.id ? AppColors.PRIMARY : AppColors.TEXT_HINT)
    }
    .width('100%')
    .padding(AppDimens.PADDING_MD)
    .backgroundColor(this.getCardBackground(`style:${item.id}`, this.activeStyleKitId === item.id))
    .borderRadius(16)
    .border({
      width: this.getCardBorderWidth(`style:${item.id}`, this.activeStyleKitId === item.id),
      color: this.getCardBorderColor(`style:${item.id}`, this.activeStyleKitId === item.id)
    })
    .scale({
      x: this.getCardScale(`style:${item.id}`),
      y: this.getCardScale(`style:${item.id}`)
    })
    .animation({ duration: 160, curve: Curve.EaseOut })
    .onClick(() => {
      this.selectStyleKit(item.id)
    })
  }

  @Builder
  private buildMusicCard(item: ReplayMusicOption) {
    Row({ space: 12 }) {
      Column() {
        Text(item.title)
          .fontSize(AppDimens.FONT_MD)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_PRIMARY)
          .width('100%')
        Text(item.subtitle)
          .fontSize(AppDimens.FONT_SM)
          .fontColor(AppColors.TEXT_HINT)
          .width('100%')
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(this.activeBgmId === item.id ? '当前使用' : '点击选择')
        .fontSize(AppDimens.FONT_SM)
        .fontColor(this.activeBgmId === item.id ? AppColors.PRIMARY : AppColors.TEXT_HINT)
    }
    .width('100%')
    .padding(AppDimens.PADDING_MD)
    .backgroundColor(this.getCardBackground(`music:${item.id}`, this.activeBgmId === item.id))
    .borderRadius(16)
    .border({
      width: this.getCardBorderWidth(`music:${item.id}`, this.activeBgmId === item.id),
      color: this.getCardBorderColor(`music:${item.id}`, this.activeBgmId === item.id)
    })
    .scale({
      x: this.getCardScale(`music:${item.id}`),
      y: this.getCardScale(`music:${item.id}`)
    })
    .animation({ duration: 160, curve: Curve.EaseOut })
    .onClick(() => {
      this.selectBgm(item.id)
    })
  }

  @Builder
  private buildFilterCard(item: ReplayFilterOption) {
    Row({ space: 12 }) {
      Blank()
        .width(36)
        .height(36)
        .backgroundColor(item.previewColor)
        .borderRadius(10)

      Column() {
        Text(item.title)
          .fontSize(AppDimens.FONT_MD)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_PRIMARY)
          .width('100%')
        Text(item.subtitle)
          .fontSize(AppDimens.FONT_SM)
          .fontColor(AppColors.TEXT_HINT)
          .width('100%')
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(this.activeFilterId === item.id ? '当前使用' : '点击选择')
        .fontSize(AppDimens.FONT_SM)
        .fontColor(this.activeFilterId === item.id ? AppColors.PRIMARY : AppColors.TEXT_HINT)
    }
    .width('100%')
    .padding(AppDimens.PADDING_MD)
    .backgroundColor(this.getCardBackground(`filter:${item.id}`, this.activeFilterId === item.id))
    .borderRadius(16)
    .border({
      width: this.getCardBorderWidth(`filter:${item.id}`, this.activeFilterId === item.id),
      color: this.getCardBorderColor(`filter:${item.id}`, this.activeFilterId === item.id)
    })
    .scale({
      x: this.getCardScale(`filter:${item.id}`),
      y: this.getCardScale(`filter:${item.id}`)
    })
    .animation({ duration: 160, curve: Curve.EaseOut })
    .onClick(() => {
      this.selectFilter(item.id)
    })
  }

  @Builder
  private buildTransitionCard(item: ReplayTransitionOption) {
    Row({ space: 12 }) {
      Column() {
        Text(item.title)
          .fontSize(AppDimens.FONT_MD)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_PRIMARY)
          .width('100%')
        Text(item.subtitle)
          .fontSize(AppDimens.FONT_SM)
          .fontColor(AppColors.TEXT_HINT)
          .width('100%')
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(this.activeTransitionType === item.id ? '当前使用' : '点击选择')
        .fontSize(AppDimens.FONT_SM)
        .fontColor(this.activeTransitionType === item.id ? AppColors.PRIMARY : AppColors.TEXT_HINT)
    }
    .width('100%')
    .padding(AppDimens.PADDING_MD)
    .backgroundColor(this.getCardBackground(`transition:${item.id}`, this.activeTransitionType === item.id))
    .borderRadius(16)
    .border({
      width: this.getCardBorderWidth(`transition:${item.id}`, this.activeTransitionType === item.id),
      color: this.getCardBorderColor(`transition:${item.id}`, this.activeTransitionType === item.id)
    })
    .scale({
      x: this.getCardScale(`transition:${item.id}`),
      y: this.getCardScale(`transition:${item.id}`)
    })
    .animation({ duration: 160, curve: Curve.EaseOut })
    .onClick(() => {
      this.selectTransition(item.id)
    })
  }

  @Builder
  private buildRouteTrailToggleCard() {
    Row({ space: 12 }) {
      Column() {
        Text('路线留痕')
          .fontSize(AppDimens.FONT_MD)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_PRIMARY)
          .width('100%')
        Text('显示未走过路线底线，并用双层高亮轨迹持续点亮已经走过的路段。')
          .fontSize(AppDimens.FONT_SM)
          .fontColor(AppColors.TEXT_HINT)
          .width('100%')
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(this.activeEnableRouteAnimation ? '已开启' : '已关闭')
        .fontSize(AppDimens.FONT_SM)
        .fontColor(this.activeEnableRouteAnimation ? AppColors.PRIMARY : AppColors.TEXT_HINT)
    }
    .width('100%')
    .padding(AppDimens.PADDING_MD)
    .backgroundColor(this.getToggleCardBackground(this.activeEnableRouteAnimation))
    .borderRadius(16)
    .border({
      width: this.getToggleCardBorderWidth(this.activeEnableRouteAnimation),
      color: this.getToggleCardBorderColor(this.activeEnableRouteAnimation)
    })
    .scale({ x: 1, y: 1 })
    .animation({ duration: 160, curve: Curve.EaseOut })
    .onClick(() => {
      this.toggleRouteAnimation()
    })
  }

  @Builder
  private buildBlurOverlayToggleCard() {
    Row({ space: 12 }) {
      Column() {
        Text('玻璃详情层')
          .fontSize(AppDimens.FONT_MD)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_PRIMARY)
          .width('100%')
        Text('展开照片详情时使用更通透的半透明面板。')
          .fontSize(AppDimens.FONT_SM)
          .fontColor(AppColors.TEXT_HINT)
          .width('100%')
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(this.activeEnableBlurOverlay ? '已开启' : '已关闭')
        .fontSize(AppDimens.FONT_SM)
        .fontColor(this.activeEnableBlurOverlay ? AppColors.PRIMARY : AppColors.TEXT_HINT)
    }
    .width('100%')
    .padding(AppDimens.PADDING_MD)
    .backgroundColor(this.getToggleCardBackground(this.activeEnableBlurOverlay))
    .borderRadius(16)
    .border({
      width: this.getToggleCardBorderWidth(this.activeEnableBlurOverlay),
      color: this.getToggleCardBorderColor(this.activeEnableBlurOverlay)
    })
    .scale({ x: 1, y: 1 })
    .animation({ duration: 160, curve: Curve.EaseOut })
    .onClick(() => {
      this.toggleBlurOverlay()
    })
  }

  @Builder
  private buildStyleTab() {
    Column({ space: 12 }) {
      Text('主题会立即作用到照片卡片、进度条、控制栏和回放详情层。')
        .fontSize(AppDimens.FONT_SM)
        .fontColor(AppColors.TEXT_HINT)
        .width('100%')

      ForEach(ReplayStyleKitCatalog.list(), (item: ReplayStyleKitOption) => {
        this.buildStyleCard(item)
      })
    }
    .width('100%')
  }

  @Builder
  private buildMusicTab() {
    Column({ space: 12 }) {
      Text('切换音乐后会立刻重载播放器，确保当前只播放一首歌。')
        .fontSize(AppDimens.FONT_SM)
        .fontColor(AppColors.TEXT_HINT)
        .width('100%')

      ForEach(ReplayMusicCatalog.list(), (item: ReplayMusicOption) => {
        this.buildMusicCard(item)
      })
    }
    .width('100%')
  }

  @Builder
  private buildDisplayTab() {
    Column({ space: 12 }) {
      Text('这里集中控制地图和照片详情层的展示方式，方便快速切换。')
        .fontSize(AppDimens.FONT_SM)
        .fontColor(AppColors.TEXT_HINT)
        .width('100%')

      this.buildRouteTrailToggleCard()
      this.buildBlurOverlayToggleCard()
    }
    .width('100%')
  }

  @Builder
  private buildEffectsTab() {
    Column({ space: 12 }) {
      Text('滤镜会立即作用到照片卡片与全屏详情，选中后会立刻反馈。')
        .fontSize(AppDimens.FONT_SM)
        .fontColor(AppColors.TEXT_HINT)
        .width('100%')

      ForEach(ReplayFilterCatalog.list(), (item: ReplayFilterOption) => {
        this.buildFilterCard(item)
      })
    }
    .width('100%')
  }

  @Builder
  private buildTransitionTab() {
    Column({ space: 12 }) {
      Text('转场只作用于回放卡片，地图镜头移动节奏保持稳定。')
        .fontSize(AppDimens.FONT_SM)
        .fontColor(AppColors.TEXT_HINT)
        .width('100%')

      ForEach(ReplayTransitionCatalog.list(), (item: ReplayTransitionOption) => {
        this.buildTransitionCard(item)
      })
    }
    .width('100%')
  }

  build() {
    if (this.isVisible) {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#00000066')
          .onClick(() => this.close())

        Column() {
          Row() {
            Text('回放设置')
              .fontSize(AppDimens.FONT_LG)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.TEXT_PRIMARY)
              .layoutWeight(1)

            Text('关闭')
              .fontSize(AppDimens.FONT_MD)
              .fontColor(AppColors.PRIMARY)
              .onClick(() => this.close())
          }
          .width('100%')

          Row({ space: 8 }) {
            this.buildTabButton(ReplaySettingsTab.STYLE, '风格')
            this.buildTabButton(ReplaySettingsTab.MUSIC, '音乐')
            this.buildTabButton(ReplaySettingsTab.DISPLAY, '显示')
            this.buildTabButton(ReplaySettingsTab.EFFECTS, '效果')
            this.buildTabButton(ReplaySettingsTab.TRANSITION, '转场')
          }
          .width('100%')
          .margin({ top: 16 })

          Scroll() {
            Column() {
              if (this.activeTab === ReplaySettingsTab.STYLE) {
                this.buildStyleTab()
              } else if (this.activeTab === ReplaySettingsTab.MUSIC) {
                this.buildMusicTab()
              } else if (this.activeTab === ReplaySettingsTab.DISPLAY) {
                this.buildDisplayTab()
              } else if (this.activeTab === ReplaySettingsTab.EFFECTS) {
                this.buildEffectsTab()
              } else {
                this.buildTransitionTab()
              }
            }
            .width('100%')
            .padding({ top: 16, bottom: 24 })
          }
          .layoutWeight(1)
          .width('100%')
        }
        .width('100%')
        .height('64%')
        .padding(AppDimens.PADDING_LG)
        .backgroundColor(AppColors.BACKGROUND)
        .borderRadius({ topLeft: 24, topRight: 24 })
        .position({ x: 0, y: '36%' })
      }
      .width('100%')
      .height('100%')
      .zIndex(998)
    }
  }
}
