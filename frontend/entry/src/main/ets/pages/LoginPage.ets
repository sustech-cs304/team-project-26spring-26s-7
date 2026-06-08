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
  // 审核要求"明示同意"——默认未勾选；勾选了登录按钮才可点。
  @State hasConsented: boolean = false

  private async handleHuaweiLogin(): Promise<void> {
    if (this.isLoggingIn) {
      return
    }

    // 兜底守卫：即使 UI 出现 race 让按钮意外可点，没勾同意框也直接拦下。
    if (!this.hasConsented) {
      promptAction.showToast({ message: '请先勾选同意《用户协议》和《隐私政策》' })
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
        // margin top 32 — 跟上面"钉住每一段旅途记忆"留出明显呼吸距离，
        // 不然 Blank 居中后按钮会贴着 slogan，视觉上太挤。
        Column() {
          Button(this.isLoggingIn ? '处理中...' : '华为账号一键登录')
            .width('80%')
            .height(48)
            .fontSize(AppDimens.FONT_LG)
            .backgroundColor(AppColors.PRIMARY)
            // 必须勾选同意 + 没在登录中 才允许点
            .enabled(!this.isLoggingIn && this.hasConsented)
            .opacity(this.hasConsented ? 1 : 0.5)
            .onClick(() => this.handleHuaweiLogin())

          // 进度提示区——固定高度 24 / 上间距 6，保证布局稳定的同时
          // 让按钮跟下面同意框的整体距离从原 54vp 收紧到 ~32vp，
          // 不会出现"按钮孤零零悬在上面、同意行远在底下"的视感
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
          .height(24)
          .justifyContent(FlexAlign.Center)
          .margin({ top: 6 })

          // 审核要求："登录页提供空白复选框且用户自愿明确勾选"。
          // Checkbox 默认 hasConsented = false；未勾时按钮 disabled + opacity 0.5。
          // 文案从"登录即代表同意"改成"我已阅读并同意"，跟 opt-in 模型匹配。
          // 登录进行中 (isLoggingIn) 时 Checkbox 也 disable + 半透，避免用户
          // 点了登录又把同意取消、造成"已开始登录但已撤回同意"的不合理中间态。
          Row() {
            Checkbox({ name: 'loginConsent', group: 'loginConsent' })
              .select(this.hasConsented)
              .selectedColor(AppColors.PRIMARY)
              .width(18)
              .height(18)
              .enabled(!this.isLoggingIn)
              .onChange((value: boolean) => { this.hasConsented = value })
            Text('我已阅读并同意')
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_HINT)
              .margin({ left: 6 })
            Text('《用户协议》')
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.PRIMARY)
              .onClick(() => router.pushUrl({ url: RouterUrls.USER_AGREEMENT }))
            Text('和')
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_HINT)
            Text('《隐私政策》')
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.PRIMARY)
              .onClick(() => router.pushUrl({ url: RouterUrls.PRIVACY_POLICY }))
          }
          .opacity(this.isLoggingIn ? 0.6 : 1)
          .alignItems(VerticalAlign.Center)
          .margin({ top: 10 })
        }
        .margin({ top: 32, bottom: 60 })
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
