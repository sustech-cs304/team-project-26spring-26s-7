import { router } from '@kit.ArkUI'
import { RouterUrls, AppColors, AppDimens } from '../common/Constants'

/**
 * P01 启动页 — 品牌展示 + 自动跳转
 */
@Entry
@Component
struct Index {
  private timeoutId: number = -1

  aboutToAppear(): void {
    this.timeoutId = setTimeout(() => {
      // TODO: 检查登录态，已登录跳 MainPage，未登录跳 LoginPage
      const isLoggedIn = false
      router.replaceUrl({
        url: isLoggedIn ? RouterUrls.MAIN : RouterUrls.LOGIN
      })
    }, 1500)
  }

  aboutToDisappear(): void {
    clearTimeout(this.timeoutId)
  }

  build() {
    Column() {
      Blank()

      // App Logo 占位
      Column() {
        Text('📍')
          .fontSize(64)
        Text('TravelPin')
          .fontSize(AppDimens.FONT_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.PRIMARY)
          .margin({ top: 12 })
        Text('记录每一处足迹')
          .fontSize(AppDimens.FONT_MD)
          .fontColor(AppColors.TEXT_HINT)
          .margin({ top: 8 })
      }

      Blank()

      // 加载指示器
      LoadingProgress()
        .width(36)
        .height(36)
        .color(AppColors.PRIMARY)
        .margin({ bottom: 80 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.CARD_BG)
    .justifyContent(FlexAlign.Center)
  }
}
