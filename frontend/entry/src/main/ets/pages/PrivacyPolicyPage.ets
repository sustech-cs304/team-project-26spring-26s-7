import { router } from '@kit.ArkUI'
import { webview } from '@kit.ArkWeb'
import { AppColors, AppDimens } from '../common'

/**
 * 直接加载 AGC 托管的隐私政策 HTML——上次审核被打回的根因之一是应用内本地
 * privacy_policy.html 跟 AGC 在线版本主体描述不一致（一边说"南方科技大学 ...
 * 7 组"、一边说"冉明东"）。改成直接 load AGC URL，**单一信息源**，开发者
 * 在 AGC 控制台改一次内容，app 内立刻同步，永远不会再出现"线上 / 线下版本
 * 不一致"的审核问题。
 *
 * 本地 rawfile/privacy_policy.html 保留作为备份参考（含合规更新后的文案），
 * 不再被 Web src 引用。
 */
const AGC_PRIVACY_URL: string = 'https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=1967100735216704704'

@Entry
@Component
struct PrivacyPolicyPage {
  @StorageLink('appThemeVersion') themeVersion: number = 0
  @State loadError: boolean = false
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

        Text('隐私政策')
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

      if (this.loadError) {
        // 离线 / 网络错误兜底——给用户一个手动重试入口和直访 URL
        Column({ space: 12 }) {
          Text('暂时无法加载隐私政策')
            .fontSize(AppDimens.FONT_MD)
            .fontColor(AppColors.TEXT_PRIMARY)
          Text('请检查网络后点"重试"，或在浏览器中打开下方网址查看：')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_SECONDARY)
            .textAlign(TextAlign.Center)
            .padding({ left: 24, right: 24 })
          Text(AGC_PRIVACY_URL)
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.PRIMARY)
            .padding({ left: 24, right: 24, top: 4, bottom: 12 })
            .textAlign(TextAlign.Center)
          Button('重试')
            .width(160)
            .height(40)
            .fontSize(AppDimens.FONT_MD)
            .backgroundColor(AppColors.PRIMARY)
            .onClick(() => { this.loadError = false })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        // AGC 托管的隐私政策 HTML，可能含 JS 渲染和外链图片，所以打开
        // domStorage / javaScript / onlineImage 权限；fileAccess 保持关闭。
        Web({ src: AGC_PRIVACY_URL, controller: this.controller })
          .layoutWeight(1)
          .width('100%')
          .darkMode(WebDarkMode.Auto)
          .domStorageAccess(true)
          .javaScriptAccess(true)
          .onlineImageAccess(true)
          .fileAccess(false)
          .onErrorReceive(() => { this.loadError = true })
          .onHttpErrorReceive(() => { this.loadError = true })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.BACKGROUND)
  }
}
