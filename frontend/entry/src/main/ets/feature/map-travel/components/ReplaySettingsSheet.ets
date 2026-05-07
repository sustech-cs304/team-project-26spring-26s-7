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
  EFFECTS = 2,
  TRANSITION = 3
}

@Component
export struct ReplaySettingsSheet {
  @Prop isVisible: boolean = false
  @Prop selectedStyleKitId: ReplayStyleKitId = ReplayStyleKitCatalog.DEFAULT_ID
  @Prop selectedBgmId: ReplayBgmId = ReplayMusicCatalog.DEFAULT_ID
  @Prop selectedFilterId: ReplayFilterId = ReplayFilterId.NONE
  @Prop selectedTransitionType: ReplayTransitionType = ReplayTransitionType.FADE
  @Prop enableRipple: boolean = false
  @Prop enableBlurOverlay: boolean = false
  @State private activeTab: ReplaySettingsTab = ReplaySettingsTab.STYLE

  onClose?: () => void
  onStyleChange?: (styleKitId: ReplayStyleKitId) => void
  onBgmChange?: (bgmId: ReplayBgmId) => void
  onFilterChange?: (filterId: ReplayFilterId) => void
  onTransitionChange?: (transitionType: ReplayTransitionType) => void
  onRippleToggle?: (enabled: boolean) => void
  onBlurOverlayToggle?: (enabled: boolean) => void

  private close(): void {
    if (this.onClose) {
      this.onClose()
    }
  }

  private selectStyleKit(styleKitId: ReplayStyleKitId): void {
    ReplayPreferences.setStyleKitId(styleKitId)
    if (this.onStyleChange) {
      this.onStyleChange(styleKitId)
    }
  }

  private selectBgm(bgmId: ReplayBgmId): void {
    ReplayPreferences.setBgmId(bgmId)
    if (this.onBgmChange) {
      this.onBgmChange(bgmId)
    }
  }

  private selectFilter(filterId: ReplayFilterId): void {
    ReplayPreferences.setFilterId(filterId)
    if (this.onFilterChange) {
      this.onFilterChange(filterId)
    }
  }

  private selectTransition(transitionType: ReplayTransitionType): void {
    ReplayPreferences.setTransitionType(transitionType)
    if (this.onTransitionChange) {
      this.onTransitionChange(transitionType)
    }
  }

  private toggleRipple(): void {
    const nextValue = !this.enableRipple
    ReplayPreferences.setEnableRipple(nextValue)
    if (this.onRippleToggle) {
      this.onRippleToggle(nextValue)
    }
  }

  private toggleBlurOverlay(): void {
    const nextValue = !this.enableBlurOverlay
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
  private buildOptionFooter(selected: boolean) {
    Text(selected ? '当前使用' : '选择')
      .fontSize(AppDimens.FONT_SM)
      .fontColor(selected ? AppColors.PRIMARY : AppColors.TEXT_HINT)
  }

  @Builder
  private buildStyleTab() {
    Column({ space: 12 }) {
      Text('三套主题会即时作用到卡片、进度条、控制栏和回放详情层。')
        .fontSize(AppDimens.FONT_SM)
        .fontColor(AppColors.TEXT_HINT)
        .width('100%')

      ForEach(ReplayStyleKitCatalog.list(), (item: ReplayStyleKitOption) => {
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

          this.buildOptionFooter(this.selectedStyleKitId === item.id)
        }
        .width('100%')
        .padding(AppDimens.PADDING_MD)
        .backgroundColor(AppColors.CARD_BG)
        .borderRadius(16)
        .border({
          width: 1,
          color: this.selectedStyleKitId === item.id ? AppColors.PRIMARY : AppColors.DIVIDER
        })
        .onClick(() => {
          this.selectStyleKit(item.id)
        })
      })
    }
    .width('100%')
  }

  @Builder
  private buildMusicTab() {
    Column({ space: 12 }) {
      Text('本地曲库已经接入真实资源，切歌会即时重载播放器。')
        .fontSize(AppDimens.FONT_SM)
        .fontColor(AppColors.TEXT_HINT)
        .width('100%')

      ForEach(ReplayMusicCatalog.list(), (item: ReplayMusicOption) => {
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

          this.buildOptionFooter(this.selectedBgmId === item.id)
        }
        .width('100%')
        .padding(AppDimens.PADDING_MD)
        .backgroundColor(AppColors.CARD_BG)
        .borderRadius(16)
        .border({
          width: 1,
          color: this.selectedBgmId === item.id ? AppColors.PRIMARY : AppColors.DIVIDER
        })
        .onClick(() => {
          this.selectBgm(item.id)
        })
      })
    }
    .width('100%')
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

      this.buildOptionFooter(this.selectedFilterId === item.id)
    }
    .width('100%')
    .padding(AppDimens.PADDING_MD)
    .backgroundColor(AppColors.CARD_BG)
    .borderRadius(16)
    .border({
      width: 1,
      color: this.selectedFilterId === item.id ? AppColors.PRIMARY : AppColors.DIVIDER
    })
    .onClick(() => {
      this.selectFilter(item.id)
    })
  }

  @Builder
  private buildToggleCard(title: string, subtitle: string, enabled: boolean, onTap: () => void) {
    Row({ space: 12 }) {
      Column() {
        Text(title)
          .fontSize(AppDimens.FONT_MD)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_PRIMARY)
          .width('100%')
        Text(subtitle)
          .fontSize(AppDimens.FONT_SM)
          .fontColor(AppColors.TEXT_HINT)
          .width('100%')
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(enabled ? '已开启' : '已关闭')
        .fontSize(AppDimens.FONT_SM)
        .fontColor(enabled ? AppColors.PRIMARY : AppColors.TEXT_HINT)
    }
    .width('100%')
    .padding(AppDimens.PADDING_MD)
    .backgroundColor(AppColors.CARD_BG)
    .borderRadius(16)
    .border({
      width: 1,
      color: enabled ? AppColors.PRIMARY : AppColors.DIVIDER
    })
    .onClick(() => onTap())
  }

  @Builder
  private buildEffectsTab() {
    Column({ space: 12 }) {
      Text('滤镜会立即作用到照片卡片与全屏详情；波纹和玻璃面板默认保持保守配置。')
        .fontSize(AppDimens.FONT_SM)
        .fontColor(AppColors.TEXT_HINT)
        .width('100%')

      ForEach(ReplayFilterCatalog.list(), (item: ReplayFilterOption) => {
        this.buildFilterCard(item)
      })

      this.buildToggleCard(
        '节点波纹',
        '到达新节点时，在地图上叠加一层轻量扩散反馈。',
        this.enableRipple,
        () => this.toggleRipple()
      )

      this.buildToggleCard(
        '玻璃详情层',
        '展开照片详情时使用更通透的半透明面板。',
        this.enableBlurOverlay,
        () => this.toggleBlurOverlay()
      )
    }
    .width('100%')
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

      this.buildOptionFooter(this.selectedTransitionType === item.id)
    }
    .width('100%')
    .padding(AppDimens.PADDING_MD)
    .backgroundColor(AppColors.CARD_BG)
    .borderRadius(16)
    .border({
      width: 1,
      color: this.selectedTransitionType === item.id ? AppColors.PRIMARY : AppColors.DIVIDER
    })
    .onClick(() => {
      this.selectTransition(item.id)
    })
  }

  @Builder
  private buildTransitionTab() {
    Column({ space: 12 }) {
      Text('转场只作用于回放卡片，地图相机移动节奏保持原来的稳定实现。')
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
