import {
  AppColors,
  AppDimens,
  ReplayBgmId,
  ReplayMusicCatalog,
  ReplayMusicOption,
  ReplayPreferences,
  ReplayStyleKitCatalog,
  ReplayStyleKitId,
  ReplayStyleKitOption
} from '../../../common'

enum ReplaySettingsTab {
  STYLE = 0,
  MUSIC = 1
}

@Component
export struct ReplaySettingsSheet {
  @Prop isVisible: boolean = false
  @Prop selectedStyleKitId: ReplayStyleKitId = ReplayStyleKitCatalog.DEFAULT_ID
  @Prop selectedBgmId: ReplayBgmId = ReplayMusicCatalog.DEFAULT_ID
  @State private activeTab: ReplaySettingsTab = ReplaySettingsTab.STYLE

  onClose?: () => void
  onStyleChange?: (styleKitId: ReplayStyleKitId) => void
  onBgmChange?: (bgmId: ReplayBgmId) => void

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
  private buildStyleTab() {
    Column({ space: 12 }) {
      Text('当前阶段先完成样式选择与保存，实际回放换肤将在 Phase 2 接入。')
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

          Text(this.selectedStyleKitId === item.id ? '当前使用' : '选择')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(this.selectedStyleKitId === item.id ? AppColors.PRIMARY : AppColors.TEXT_HINT)
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
      Text('当前阶段已接入本地曲库与即时切歌，路线级持久化会写入本地数据库。')
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

          Text(this.selectedBgmId === item.id ? '当前使用' : '选择')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(this.selectedBgmId === item.id ? AppColors.PRIMARY : AppColors.TEXT_HINT)
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
          }
          .width('100%')
          .margin({ top: 16 })

          Scroll() {
            Column() {
              if (this.activeTab === ReplaySettingsTab.STYLE) {
                this.buildStyleTab()
              } else {
                this.buildMusicTab()
              }
            }
            .width('100%')
            .padding({ top: 16, bottom: 24 })
          }
          .layoutWeight(1)
          .width('100%')
        }
        .width('100%')
        .height('58%')
        .padding(AppDimens.PADDING_LG)
        .backgroundColor(AppColors.BACKGROUND)
        .borderRadius({ topLeft: 24, topRight: 24 })
        .position({ x: 0, y: '42%' })
      }
      .width('100%')
      .height('100%')
      .zIndex(998)
    }
  }
}
