import { AppColors, AppDimens } from '../common'
import { MapHomeView } from '../feature/map-travel/views/MapHomeView'
import { TripListView } from '../feature/map-travel/views/TripListView'
import { NodeListView } from '../feature/map-travel/views/NodeListView'
import { ProfileView } from '../feature/profile/views/ProfileView'

/**
 * 主框架页 — 底部 TabBar 容器
 * 包含四个 Tab: 地图 / 旅行 / 节点 / 我的
 */
@Entry
@Component
struct MainPage {
  @State currentTabIndex: number = 0
  @Watch('onNetworkDialogTokenChange')
  @StorageLink('networkDialogToken') networkDialogToken: number = 0
  @StorageLink('networkDialogMessage') networkDialogMessage: string = ''
  @StorageLink('networkDialogTitle') networkDialogTitle: string = ''

  private tabIcons: string[] = ['🗺', '🧳', '📝', '👤']
  private tabTitles: string[] = ['地图', '旅行', '节点', '我的']

  private onNetworkDialogTokenChange(): void {
    if (this.networkDialogToken <= 0 || this.networkDialogMessage.length <= 0) {
      return
    }
    this.getUIContext().showAlertDialog({
      title: this.networkDialogTitle,
      message: this.networkDialogMessage,
      primaryButton: {
        value: '我知道了',
        action: () => {}
      }
    })
  }

  @Builder
  tabBuilder(title: string, targetIndex: number) {
    Column() {
      Text(this.tabIcons[targetIndex])
        .fontSize(22)
      Text(title)
        .fontSize(AppDimens.FONT_SM)
        .fontColor(this.currentTabIndex === targetIndex ? AppColors.PRIMARY : AppColors.TEXT_HINT)
        .margin({ top: 2 })
    }
    .width('100%')
    .height(56)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Tabs({ barPosition: BarPosition.End, index: this.currentTabIndex }) {
      TabContent() {
        MapHomeView()
      }
      .tabBar(this.tabBuilder('地图', 0))
      .onWillShow(() => {
        AppStorage.setOrCreate('activeTabIndex', 0)
        AppStorage.setOrCreate('tabRefreshToken', Date.now())
      })

      TabContent() {
        TripListView()
      }
      .tabBar(this.tabBuilder('旅行', 1))
      .onWillShow(() => {
        AppStorage.setOrCreate('activeTabIndex', 1)
        AppStorage.setOrCreate('tabRefreshToken', Date.now())
      })

      TabContent() {
        NodeListView()
      }
      .tabBar(this.tabBuilder('节点', 2))
      .onWillShow(() => {
        AppStorage.setOrCreate('activeTabIndex', 2)
        AppStorage.setOrCreate('tabRefreshToken', Date.now())
      })

      TabContent() {
        ProfileView()
      }
      .tabBar(this.tabBuilder('我的', 3))
      .onWillShow(() => {
        AppStorage.setOrCreate('activeTabIndex', 3)
        AppStorage.setOrCreate('tabRefreshToken', Date.now())
      })
    }
    .scrollable(false)
    .barHeight(56)
    .onChange((index: number) => {
      this.currentTabIndex = index
    })
  }
}
