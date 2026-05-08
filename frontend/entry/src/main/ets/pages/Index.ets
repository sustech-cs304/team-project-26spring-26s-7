import { router } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { AuthService, RouterUrls, AppColors, AppDimens, ConsentManager } from '../common'

/**
 * P01 启动页
 * 流程：品牌展示 → (首次)隐私协议同意弹窗 → 登录态判断 → 跳主页/登录页
 *
 * 隐私协议弹窗是 AppGallery 上架强制项：
 *  - 用户必须主动点"同意"才能进入主功能
 *  - 不同意则退出应用，不能让用户绕开
 */
@Entry
@Component
struct Index {
  @StorageLink('appThemeVersion') themeVersion: number = 0
  @State showPrivacyDialog: boolean = false
  private timeoutId: number = -1
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext

  aboutToAppear(): void {
    this.timeoutId = setTimeout(async () => {
      const agreed = await ConsentManager.isAppPrivacyAgreed(this.context)
      if (!agreed) {
        this.showPrivacyDialog = true
        return
      }
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

  private async handleAgree(): Promise<void> {
    await ConsentManager.setAppPrivacyAgreed(this.context)
    this.showPrivacyDialog = false
    await this.routeForward()
  }

  private handleDisagree(): void {
    // 拒绝即退出，不能让用户绕过隐私协议
    this.context.terminateSelf()
  }

  build() {
    Stack() {
      Column() {
        Blank()

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

      if (this.showPrivacyDialog) {
        this.PrivacyDialog()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  PrivacyDialog() {
    Column() {
      Column() {
        Text($r('app.string.privacy_dialog_title'))
          .fontSize(AppDimens.FONT_LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_PRIMARY)
          .margin({ bottom: 16 })

        Scroll() {
          Text($r('app.string.privacy_dialog_content'))
            .fontSize(AppDimens.FONT_MD)
            .fontColor(AppColors.TEXT_PRIMARY)
            .lineHeight(22)
            .textAlign(TextAlign.Start)
        }
        .height(280)
        .scrollBar(BarState.Auto)
        .margin({ bottom: 20 })

        Row() {
          Button($r('app.string.privacy_dialog_disagree'))
            .layoutWeight(1)
            .fontSize(AppDimens.FONT_MD)
            .fontColor(AppColors.TEXT_HINT)
            .backgroundColor(AppColors.CARD_BG)
            .borderRadius(8)
            .borderWidth(1)
            .borderColor(AppColors.DIVIDER)
            .height(44)
            .onClick(() => this.handleDisagree())

          Button($r('app.string.privacy_dialog_agree'))
            .layoutWeight(1)
            .fontSize(AppDimens.FONT_MD)
            .fontColor(Color.White)
            .backgroundColor(AppColors.PRIMARY)
            .borderRadius(8)
            .height(44)
            .margin({ left: 12 })
            .onClick(() => this.handleAgree())
        }
        .width('100%')
      }
      .padding(24)
      .backgroundColor(AppColors.CARD_BG)
      .borderRadius(16)
      .width('86%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0,0,0,0.5)')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
