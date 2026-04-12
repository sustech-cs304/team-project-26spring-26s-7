import { AppColors, AppDimens } from '../common'
import { MapHomeView } from '../feature/map-travel/views/MapHomeView'
import { TripListView } from '../feature/map-travel/views/TripListView'
import { TripAlbumView } from '../feature/map-travel/views/TripAlbumView'
import { ProfileView } from '../feature/profile/views/ProfileView'

/**
 * 主框架页 — 底部 TabBar 容器
 * 包含四个 Tab: 地图 / 旅行 / 相册 / 我的
 */
@Entry
@Component
struct MainPage {
  @State currentTabIndex: number = 0

  private tabIcons: string[] = ['🗺', '📋', '🖼', '👤']
  private tabTitles: string[] = ['地图', '旅行', '相册', '我的']

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
        TripAlbumView()
      }
      .tabBar(this.tabBuilder('相册', 2))

      TabContent() {
        ProfileView()
      }
      .tabBar(this.tabBuilder('我的', 3))
    }
    .scrollable(false)
    .barHeight(56)
    .onChange((index: number) => {
      this.currentTabIndex = index
    })
  }
}
