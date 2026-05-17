import { AppColors, AppDimens } from '../common'
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

  private tabIcons: string[] = ['⌂', '⌁', '□', '○']
  private tabTitles: string[] = ['Map', 'Trips', 'Nodes', 'Me']

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

    // 1. 定义缩放系数（0.8 表示滑块宽度是格子的 80%）
    const shrinkFactor = 0.8
    // 2. 计算因为缩短而产生的左右空隙（居中偏移量）
    const centeringOffset = (slotWidth * (1 - shrinkFactor)) / 2

    // 3. 最终位置 = (当前索引 * 格子宽) + 拖拽偏移 + 居中补偿
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

  @Builder
  private buildSlidingIndicator() {
    Row()
    // 直接在这里写表达式，不要定义 const
      .width(this.getTabSlotWidth() * 0.8)
      .height(40) // 高度也稍微调小一点更精致
      .backgroundColor(this.isTabDragging ? '#EAEAEA' : '#F2F2F2')
      .borderRadius(20)
      .shadow({
        radius: 10,
        color: '#08000000',
        offsetY: 2
      })
      .position({
        x: this.getIndicatorX(),
        y: 8 // (56容器高度 - 40滑块高度) / 2 = 8，实现垂直居中
      })
      .animation({ duration: this.isTabDragging ? 0 : 250, curve: Curve.EaseInOut })
  }
  @Builder
  private buildTabItem(index: number) {
    Row({ space: this.currentTabIndex === index ? 6 : 0 }) {
      Text(this.tabIcons[index])
        .fontSize(this.currentTabIndex === index ? 18 : 20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.currentTabIndex === index ? AppColors.PRIMARY_DARK : AppColors.TEXT_HINT)

      if (this.currentTabIndex === index) {
        Text(this.tabTitles[index])
          .fontSize(AppDimens.FONT_SM)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.PRIMARY_DARK)
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
      .backgroundColor('#F8FFFFFF')
      .backgroundBlurStyle(BlurStyle.Thin)
      .borderRadius(28)
      .shadow({ radius: 14, color: '#18000000', offsetY: 4 })
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
