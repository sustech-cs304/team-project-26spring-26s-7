import { router } from '@kit.ArkUI'
import { AuthService, RouterUrls, AppColors, AppDimens } from '../common'

/**
 * P01 启动页
 * 流程：品牌展示 → 登录态判断 → 跳主页/登录页
 *
 * 关于首启隐私协议：
 *   我们已在 AppGallery Connect 上启用"标准化隐私声明托管服务"，
 *   AGC SDK 会在 app 启动前自动弹出平台托管的隐私同意弹窗（拉取注册的
 *   agreementId 对应的 HTML 渲染、自带 同意/不同意 按钮、不同意自动退出）。
 *   所以这里不再自己弹一遍——审核员看到双弹窗会判违规。
 */
@Entry
@Component
struct Index {
  @StorageLink('appThemeVersion') themeVersion: number = 0
  private timeoutId: number = -1

  aboutToAppear(): void {
    this.timeoutId = setTimeout(async () => {
      await this.routeForward()
    }, 1500)
  }

  aboutToDisappear(): void {
    clearTimeout(this.timeoutId)
  }

  private async routeForward(): Promise<void> {
    const isLoggedIn = await AuthService.isLoggedIn()
    router.replaceUrl({
      url: isLoggedIn ? RouterUrls.MAIN : RouterUrls.LOGIN
    })
  }

  build() {
    Column() {
      Blank()

      Column() {
        Text('📍')
          .fontSize(64)
        Text('ItsMapPin')
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
