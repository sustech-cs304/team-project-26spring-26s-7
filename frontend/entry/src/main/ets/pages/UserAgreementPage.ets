import { router } from '@kit.ArkUI'
import { webview } from '@kit.ArkWeb'
import { AppColors, AppDimens } from '../common'

@Entry
@Component
struct UserAgreementPage {
  @StorageLink('appThemeVersion') themeVersion: number = 0
  private controller: webview.WebviewController = new webview.WebviewController()

  build() {
    Column() {
      Row() {
        Text('‹')
          .fontSize(28)
          .fontColor(AppColors.TEXT_PRIMARY)
          .width(40)
          .height(44)
          .textAlign(TextAlign.Center)
          .onClick(() => router.back())

        Text('用户协议')
          .fontSize(AppDimens.FONT_LG)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_PRIMARY)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Blank().width(40)
      }
      .width('100%')
      .height(48)
      .backgroundColor(AppColors.CARD_BG)

      Web({ src: $rawfile('user_agreement.html'), controller: this.controller })
        .layoutWeight(1)
        .width('100%')
        .darkMode(WebDarkMode.Auto)
        .domStorageAccess(false)
        .javaScriptAccess(false)
        .fileAccess(false)
        .onlineImageAccess(false)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.BACKGROUND)
  }
}
