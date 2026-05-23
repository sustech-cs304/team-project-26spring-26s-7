import { AppColors, AppDimens, AppTheme } from '../common'
import { MapHomeView } from '../feature/map-travel/views/MapHomeView'
import { TripListView } from '../feature/map-travel/views/TripListView'
import { NodeListView } from '../feature/map-travel/views/NodeListView'
import { ProfileView } from '../feature/profile/views/ProfileView'

@Entry
@Component
struct MainPage {
  @StorageLink('appThemeVersion') themeVersion: number = 0
  @State currentTabIndex: number = 0
  @State tabBarWidth: number = 0
  @State tabDragOffset: number = 0
  @State isTabDragging: boolean = false
  @Watch('onNetworkDialogTokenChange')
  @StorageLink('networkDialogToken') networkDialogToken: number = 0
  @StorageLink('networkDialogMessage') networkDialogMessage: string = ''
  @StorageLink('networkDialogTitle') networkDialogTitle: string = ''
  @StorageLink('nodeBulkActionMode') nodeBulkActionMode: boolean = false

  private tabTitles: string[] = ['地图', '旅途', '节点', '设置']
  private readonly tabIconSize: number = 22

  private onNetworkDialogTokenChange(): void {
    if (this.networkDialogToken <= 0 || this.networkDialogMessage.length <= 0) {
      return
    }
    this.getUIContext().showAlertDialog({
      title: this.networkDialogTitle,
      message: this.networkDialogMessage,
      primaryButton: {
        value: 'OK',
        action: () => {}
      }
    })
  }

  private switchTab(index: number): void {
    if (index !== 2) {
      AppStorage.setOrCreate('nodeBulkActionMode', false)
    }
    this.currentTabIndex = index
    this.tabDragOffset = 0
    this.isTabDragging = false
    AppStorage.setOrCreate('activeTabIndex', index)
  }

  private getTabSlotWidth(): number {
    return this.tabBarWidth > 0 ? this.tabBarWidth / 4 : 0
  }

  private clampTabDragOffset(offset: number): number {
    const slotWidth = this.getTabSlotWidth()
    if (slotWidth <= 0) {
      return 0
    }

    const minOffset = -this.currentTabIndex * slotWidth
    const maxOffset = (3 - this.currentTabIndex) * slotWidth
    return Math.max(minOffset, Math.min(maxOffset, offset))
  }

  private getIndicatorX(): number {
    const slotWidth = this.getTabSlotWidth()
    if (slotWidth <= 0) return 0

    const shrinkFactor = 0.8
    const centeringOffset = (slotWidth * (1 - shrinkFactor)) / 2

    return (this.currentTabIndex * slotWidth) + this.clampTabDragOffset(this.tabDragOffset) + centeringOffset
  }

  private finishTabDrag(): void {
    const slotWidth = this.getTabSlotWidth()
    if (slotWidth <= 0) {
      this.tabDragOffset = 0
      this.isTabDragging = false
      return
    }

    const movedSlots = Math.round(this.clampTabDragOffset(this.tabDragOffset) / slotWidth)
    const nextIndex = Math.max(0, Math.min(3, this.currentTabIndex + movedSlots))
    this.switchTab(nextIndex)
  }

  private getTabBarBackground(): string {
    return AppTheme.isDarkMode() ? '#731E2420' : '#80FFFFFF'
  }

  private getTabIndicatorBackground(): string {
    if (this.isTabDragging) {
      return AppTheme.isDarkMode() ? '#44FFFFFF' : '#F2FFFFFF'
    }
    return AppTheme.isDarkMode() ? '#38FFFFFF' : '#DFFFFFFF'
  }

  private getTabShadowColor(): string {
    return AppTheme.isDarkMode() ? '#CC000000' : '#38101820'
  }

  private getTabGlassBorderColor(): string {
    return AppTheme.isDarkMode() ? '#4DFFFFFF' : '#B8FFFFFF'
  }

  private getTabIndicatorBorderColor(): string {
    return AppTheme.isDarkMode() ? '#66FFFFFF' : '#FFFFFFFF'
  }

  private getSelectedTabColor(): string {
    return AppTheme.isDarkMode() ? '#FFFFFF' : '#101412'
  }

  private getTabIconColor(isSelected: boolean): string {
    if (isSelected) {
      return this.getSelectedTabColor()
    }
    return AppTheme.isDarkMode() ? '#F0EDE7' : '#30342F'
  }

  @Builder
  private buildSlidingIndicator() {
    Row()
      .width(this.getTabSlotWidth() * 0.8)
      .height(40)
      .backgroundColor(this.getTabIndicatorBackground())
      .backgroundBlurStyle(BlurStyle.Thin, { colorMode: ThemeColorMode.SYSTEM, adaptiveColor: AdaptiveColor.DEFAULT })
      .border({ width: 0.8, color: this.getTabIndicatorBorderColor() })
      .borderRadius(20)
      .shadow({
        radius: 12,
        color: this.getTabShadowColor(),
        offsetY: 4
      })
      .position({
        x: this.getIndicatorX(),
        y: 8
      })
      .animation({ duration: this.isTabDragging ? 0 : 250, curve: Curve.EaseInOut })
  }
  @Builder
  private buildTabIcon(index: number, isSelected: boolean) {
    if (index === 0) {
      SymbolGlyph($r('sys.symbol.map_badge_local'))
        .fontSize(this.tabIconSize)
        .fontWeight(FontWeight.Bold)
        .fontColor([this.getTabIconColor(isSelected)])
    } else if (index === 1) {
      SymbolGlyph($r('sys.symbol.point_bottomleft_forward_to_point_topright_scurvepath'))
        .fontSize(this.tabIconSize)
        .fontWeight(FontWeight.Bold)
        .fontColor([this.getTabIconColor(isSelected)])
    } else if (index === 2) {
      SymbolGlyph($r('sys.symbol.local_fill'))
        .fontSize(this.tabIconSize)
        .fontWeight(FontWeight.Bold)
        .fontColor([this.getTabIconColor(isSelected)])
    } else {
      SymbolGlyph($r('sys.symbol.gearshape'))
        .fontSize(this.tabIconSize)
        .fontWeight(FontWeight.Bold)
        .fontColor([this.getTabIconColor(isSelected)])
    }
  }

  @Builder
  private buildTabItem(index: number) {
    Row({ space: this.currentTabIndex === index ? 6 : 0 }) {
      this.buildTabIcon(index, this.currentTabIndex === index)

      if (this.currentTabIndex === index) {
        Text(this.tabTitles[index])
          .fontSize(AppDimens.FONT_SM)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.getSelectedTabColor())
      }
    }
    .height(56)
    .layoutWeight(1)
    .padding({
      left: 8,
      right: 8
    })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.switchTab(index))
  }

  @Builder
  private buildFloatingTabBar() {
    Column() {
      Stack() {
        this.buildSlidingIndicator()

        Row() {
          ForEach([0, 1, 2, 3], (index: number) => {
            this.buildTabItem(index)
          })
        }
        .width('100%')
        .height(56)
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .width('100%')
      .height(56)
      .backgroundColor(this.getTabBarBackground())
      .backgroundBlurStyle(BlurStyle.Thin, { colorMode: ThemeColorMode.SYSTEM, adaptiveColor: AdaptiveColor.DEFAULT })
      .border({ width: 0.8, color: this.getTabGlassBorderColor() })
      .borderRadius(28)
      .shadow({ radius: 24, color: this.getTabShadowColor(), offsetY: 10 })
      .onAreaChange((_, value) => {
        this.tabBarWidth = Number(value.width)
      })
      .gesture(
        PanGesture({ direction: PanDirection.Horizontal })
          .onActionStart(() => {
            this.isTabDragging = true
          })
          .onActionUpdate((event: GestureEvent) => {
            this.tabDragOffset = this.clampTabDragOffset(event.offsetX)
          })
          .onActionEnd(() => {
            this.finishTabDrag()
          })
          .onActionCancel(() => {
            this.tabDragOffset = 0
            this.isTabDragging = false
          })
      )
    }
    .width('100%')
    .height(66)
    .padding({ left: 12, right: 12, top: 4, bottom: 6 })
    .backgroundColor('#00000000')
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Tabs({ barPosition: BarPosition.End, index: this.currentTabIndex }) {
        TabContent() {
          MapHomeView()
        }

        TabContent() {
          TripListView()
        }

        TabContent() {
          NodeListView()
        }

        TabContent() {
          ProfileView()
        }
      }
      .scrollable(false)
      .barHeight(0)
      .barBackgroundColor('#00000000')
      .onChange((index: number) => this.switchTab(index))

      if (!this.nodeBulkActionMode) {
        this.buildFloatingTabBar()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.BACKGROUND)
  }
}
