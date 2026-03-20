import { router } from '@kit.ArkUI'
import { RouterUrls, AppColors, AppDimens } from '../common/Constants'

/**
 * P-Login 登录页 — 华为账号一键登录
 */
@Entry
@Component
struct LoginPage {
  @State isLoggingIn: boolean = false

  private handleHuaweiLogin(): void {
    this.isLoggingIn = true
    // TODO: 调用 HarmonyOS Account Kit 进行华为账号登录
    // 登录成功后跳转主页
    setTimeout(() => {
      this.isLoggingIn = false
      router.replaceUrl({ url: RouterUrls.MAIN })
    }, 1000)
  }

  build() {
    Column() {
      Blank()

      // 品牌区域
      Column() {
        Text('📍')
          .fontSize(56)
        Text('TravelPin')
          .fontSize(AppDimens.FONT_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_PRIMARY)
          .margin({ top: 12 })
        Text('钉住每一段旅途记忆')
          .fontSize(AppDimens.FONT_MD)
          .fontColor(AppColors.TEXT_SECONDARY)
          .margin({ top: 8 })
      }

      Blank()

      // 登录按钮区域
      Column() {
        Button(this.isLoggingIn ? '登录中...' : '华为账号一键登录')
          .width('80%')
          .height(48)
          .fontSize(AppDimens.FONT_LG)
          .backgroundColor(AppColors.PRIMARY)
          .enabled(!this.isLoggingIn)
          .onClick(() => this.handleHuaweiLogin())

        Text('登录即代表同意《用户协议》和《隐私政策》')
          .fontSize(AppDimens.FONT_SM)
          .fontColor(AppColors.TEXT_HINT)
          .margin({ top: 16 })
      }
      .margin({ bottom: 60 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.BACKGROUND)
    .justifyContent(FlexAlign.Center)
  }
}
