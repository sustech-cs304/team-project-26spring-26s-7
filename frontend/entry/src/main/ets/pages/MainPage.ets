import { AppColors, AppDimens } from '../common/Constants'
import { MapHomeView } from '../views/MapHomeView'
import { TripListView } from '../views/TripListView'
import { ProfileView } from '../views/ProfileView'

/**
 * 主框架页 — 底部 TabBar 容器
 * 包含三个 Tab: 地图 / 旅行 / 我的
 */
@Entry
@Component
struct MainPage {
  @State currentTabIndex: number = 0

  private tabIcons: string[] = ['🗺', '📋', '👤']
  private tabTitles: string[] = ['地图', '旅行', '我的']

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

      TabContent() {
        TripListView()
      }
      .tabBar(this.tabBuilder('旅行', 1))

      TabContent() {
        ProfileView()
      }
      .tabBar(this.tabBuilder('我的', 2))
    }
    .scrollable(false)
    .barHeight(56)
    .onChange((index: number) => {
      this.currentTabIndex = index
    })
  }
}
