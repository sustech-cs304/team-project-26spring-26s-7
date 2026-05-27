import { common } from '@kit.AbilityKit'
import { router, promptAction } from '@kit.ArkUI'
import { BusinessError } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AuthService, RouterUrls, AppColors, AppDimens, SyncManager } from '../common'

const DOMAIN = 0x0000
const TAG = 'LoginPage'

/**
 * P-Login 登录页 — 华为账号一键登录
 */
@Entry
@Component
struct LoginPage {
  @StorageLink('appThemeVersion') themeVersion: number = 0
  @State isLoggingIn: boolean = false
  @State loginProgressText: string = ''

  private async handleHuaweiLogin(): Promise<void> {
    if (this.isLoggingIn) {
      return
    }

    this.isLoggingIn = true
    this.loginProgressText = '正在登录...'
    try {
      const hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext
      hilog.info(DOMAIN, TAG, 'handleHuaweiLogin: start')
      await AuthService.signInWithHuaweiID(hostContext)
      hilog.info(DOMAIN, TAG, 'handleHuaweiLogin: signInWithHuaweiID done')
      // 登录后立即触发 restoreSession，把云端 profile 拉到 RDB 缓存
      await AuthService.restoreSession()
      hilog.info(DOMAIN, TAG, 'handleHuaweiLogin: restoreSession done')
      this.loginProgressText = '正在拉取云端数据...'
      const syncCompleted = await this.pullCloudAfterLogin()
      promptAction.showToast({
        message: syncCompleted ? '登录成功，云端数据已同步' : '登录成功，云端同步失败，可稍后手动下载'
      })
      router.replaceUrl({ url: RouterUrls.MAIN })
    } catch (err) {
      const error = err as Error
      const businessError = err as BusinessError
      hilog.error(DOMAIN, TAG, `handleHuaweiLogin failed, code=${businessError.code}, message=${error.message}`)
      promptAction.showToast({ message: error.message || '登录失败，请重试' })
    } finally {
      this.isLoggingIn = false
      this.loginProgressText = ''
    }
  }

  private async pullCloudAfterLogin(): Promise<boolean> {
    try {
      await SyncManager.pullAllCloudToLocal()
      AppStorage.setOrCreate('networkJustReconnected', false)
      return true
    } catch (_) {
      return false
    }
  }

  build() {
    // #226: 外层包 Scroll，确保桌面窗口极端缩小时仍可上下滚动；
    // 内层 Column constraintSize 保证内容不少于窗口高度，从而保留 Blank() 居中效果
    Scroll() {
      Column() {
        Blank()

        // 品牌区域
        Column() {
          Text('📍')
            .fontSize(56)
          Text('ItsMapPin')
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
          Button(this.isLoggingIn ? '处理中...' : '华为账号一键登录')
            .width('80%')
            .height(48)
            .fontSize(AppDimens.FONT_LG)
            .backgroundColor(AppColors.PRIMARY)
            .enabled(!this.isLoggingIn)
            .onClick(() => this.handleHuaweiLogin())

          Row() {
            if (this.isLoggingIn) {
              LoadingProgress()
                .width(18)
                .height(18)
                .color(AppColors.PRIMARY)
              Text(this.loginProgressText)
                .fontSize(AppDimens.FONT_SM)
                .fontColor(AppColors.TEXT_SECONDARY)
                .margin({ left: 8 })
            }
          }
          .width('80%')
          .height(28)
          .justifyContent(FlexAlign.Center)
          .margin({ top: 10 })

          Text('登录即代表同意《用户协议》和《隐私政策》')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_HINT)
            .margin({ top: 16 })
        }
        .margin({ bottom: 60 })
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .backgroundColor(AppColors.BACKGROUND)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .backgroundColor(AppColors.BACKGROUND)
  }
}
