/*
 * Help & Feedback Page
 *
 * 用户从 ProfileView → 设置 → "帮助与客服" 进入，
 * 填表后 POST /api/v1/feedback 到 share-service 收件。
 *
 * 字段：
 *   - category: 必选 (bug / feature / experience / other)
 *   - content : 必填正文 (2 ~ 2000 chars)
 *   - contact : 可选（邮箱/微信/QQ），不填则不需要回访
 *
 * 鉴权：跟 share publish 一致，先 AiTokenManager.tryGetShareToken() 拿 Bearer；
 *      拿不到也允许提交（后端 ALLOW_DEV_UID_HEADER=1 时仍可，正式上线时禁掉）。
 */
import { router, promptAction } from '@kit.ArkUI'
import { http } from '@kit.NetworkKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppColors, AppDimens, AiTokenManager, API_BASE_URL } from '../common'

const DOMAIN: number = 0x0000
const TAG: string = 'HelpFeedbackPage'

interface CategoryOption {
  value: string
  label: string
  icon: string
}

/** POST /api/v1/feedback body. ArkTS 严格模式禁止 Record<> 直接挂 object literal，
 *  必须用显式 interface。contact 可选，未填时不发字段。 */
interface FeedbackBody {
  category: string
  content: string
  app_version: string
  contact?: string
}

/** 发请求时的 HTTP header 容器；同样需要显式接口。Authorization 可选。 */
interface FeedbackHeaders {
  'Content-Type': string
  'Authorization'?: string
}

@Entry
@Component
struct HelpFeedbackPage {
  @StorageLink('appThemeVersion') themeVersion: number = 0
  @State selectedCategory: string = 'bug'
  @State content: string = ''
  @State contact: string = ''
  @State isSubmitting: boolean = false

  private categories: CategoryOption[] = [
    { value: 'bug',        label: '问题反馈', icon: '🐞' },
    { value: 'feature',    label: '功能建议', icon: '💡' },
    { value: 'experience', label: '体验吐槽', icon: '💬' },
    { value: 'other',      label: '其它',     icon: '📝' },
  ]

  build() {
    Column() {
      // 顶部栏
      Row() {
        Text('‹')
          .fontSize(28)
          .fontColor(AppColors.TEXT_PRIMARY)
          .width(40)
          .height(44)
          .textAlign(TextAlign.Center)
          .onClick(() => router.back())

        Text('帮助与客服')
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

      Scroll() {
        Column({ space: 16 }) {
          // 介绍
          Column() {
            Text('我们很重视你的每一条反馈')
              .fontSize(AppDimens.FONT_MD)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)
            Text('收到后我们会在 3 个工作日内查看；如果留了联系方式，需要时会联系你确认细节。')
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_SECONDARY)
              .lineHeight(20)
              .margin({ top: 6 })
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_SM)
          .alignItems(HorizontalAlign.Start)

          // 分类
          Column() {
            Text('反馈类型')
              .fontSize(AppDimens.FONT_MD)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)
              .margin({ bottom: 12 })

            Row({ space: 8 }) {
              ForEach(this.categories, (opt: CategoryOption) => {
                this.categoryChip(opt)
              })
            }
            .width('100%')
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_SM)
          .alignItems(HorizontalAlign.Start)

          // 正文
          Column() {
            Row() {
              Text('内容')
                .fontSize(AppDimens.FONT_MD)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppColors.TEXT_PRIMARY)
              Blank()
              Text(`${this.content.length}/2000`)
                .fontSize(AppDimens.FONT_SM)
                .fontColor(this.content.length > 2000 ? AppColors.DANGER : AppColors.TEXT_HINT)
            }
            .width('100%')
            .margin({ bottom: 12 })

            TextArea({ placeholder: '请描述你遇到的问题或建议（必填，最多 2000 字）', text: this.content })
              .placeholderColor(AppColors.TEXT_HINT)
              .placeholderFont({ size: AppDimens.FONT_SM })
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_PRIMARY)
              .backgroundColor(AppColors.BACKGROUND)
              .borderRadius(AppDimens.RADIUS_SM)
              .padding(12)
              .width('100%')
              .height(160)
              .maxLength(2000)
              .onChange((v: string) => { this.content = v })
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_SM)
          .alignItems(HorizontalAlign.Start)

          // 联系方式（可选）
          Column() {
            Row() {
              Text('联系方式')
                .fontSize(AppDimens.FONT_MD)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppColors.TEXT_PRIMARY)
              Blank()
              Text('可选')
                .fontSize(AppDimens.FONT_SM)
                .fontColor(AppColors.TEXT_HINT)
            }
            .width('100%')
            .margin({ bottom: 12 })

            TextInput({ placeholder: '邮箱 / 微信号 / QQ，留空则不需要回访', text: this.contact })
              .placeholderColor(AppColors.TEXT_HINT)
              .placeholderFont({ size: AppDimens.FONT_SM })
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_PRIMARY)
              .backgroundColor(AppColors.BACKGROUND)
              .borderRadius(AppDimens.RADIUS_SM)
              .padding(12)
              .width('100%')
              .height(44)
              .maxLength(200)
              .onChange((v: string) => { this.contact = v })
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_SM)
          .alignItems(HorizontalAlign.Start)

          // 提交按钮
          Button(this.isSubmitting ? '提交中...' : '提交反馈')
            .width('100%')
            .height(48)
            .fontSize(AppDimens.FONT_MD)
            .fontWeight(FontWeight.Medium)
            .backgroundColor(this.canSubmit() ? AppColors.PRIMARY : AppColors.DIVIDER)
            .fontColor(this.canSubmit() ? Color.White : AppColors.TEXT_HINT)
            .enabled(this.canSubmit())
            .onClick(() => this.handleSubmit())

          // 其它支持渠道
          Column() {
            Text('其它支持渠道')
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_HINT)
              .margin({ bottom: 8 })
            Text('邮箱：hello@itsmappin.top')
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_SECONDARY)
            Text('官网：https://itsmappin.top')
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_SECONDARY)
              .margin({ top: 4 })
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .alignItems(HorizontalAlign.Start)
        }
        .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 12, bottom: 24 })
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.BACKGROUND)
  }

  @Builder
  categoryChip(opt: CategoryOption) {
    Column({ space: 4 }) {
      Text(opt.icon).fontSize(20)
      Text(opt.label)
        .fontSize(AppDimens.FONT_SM)
        .fontColor(this.selectedCategory === opt.value ? Color.White : AppColors.TEXT_PRIMARY)
    }
    .layoutWeight(1)
    .height(60)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.selectedCategory === opt.value ? AppColors.PRIMARY : AppColors.BACKGROUND)
    .borderRadius(AppDimens.RADIUS_SM)
    .onClick(() => { this.selectedCategory = opt.value })
  }

  private canSubmit(): boolean {
    if (this.isSubmitting) return false
    const trimmed = this.content.trim()
    if (trimmed.length < 2 || trimmed.length > 2000) return false
    return true
  }

  private async handleSubmit(): Promise<void> {
    if (!this.canSubmit()) {
      promptAction.showToast({ message: '请填写反馈内容（至少 2 个字符）' })
      return
    }
    this.isSubmitting = true
    try {
      const shareToken: string | null = await AiTokenManager.tryGetShareToken()
      const httpReq = http.createHttp()
      try {
        // ArkTS 严格模式：带连字符的字段 ('Content-Type') 只能在 object literal
        // 初始化时设；后续不能 headers['Authorization'] = ... (arkts-no-props-by-index).
        // 走三元一次赋值齐两套 headers，避免 bracket 修改。
        const headers: FeedbackHeaders = shareToken
          ? { 'Content-Type': 'application/json', 'Authorization': `Bearer ${shareToken}` }
          : { 'Content-Type': 'application/json' }
        const body: FeedbackBody = {
          category: this.selectedCategory,
          content: this.content.trim(),
          app_version: '1.0.0',
        }
        if (this.contact.trim().length > 0) {
          body.contact = this.contact.trim()
        }
        // 显式类型避免 ArkTS 严格模式 arkts-no-untyped-obj-literals 误报
        const options: http.HttpRequestOptions = {
          method: http.RequestMethod.POST,
          header: headers,
          extraData: JSON.stringify(body),
          readTimeout: 10000,
          connectTimeout: 10000,
          expectDataType: http.HttpDataType.OBJECT,
        }
        const resp = await httpReq.request(`${API_BASE_URL}/api/v1/feedback`, options)
        if (resp.responseCode === 200 || resp.responseCode === 201) {
          promptAction.showToast({ message: '反馈提交成功，感谢！', duration: 2000 })
          // 清空表单，留两秒让 toast 看完再返回
          this.content = ''
          this.contact = ''
          setTimeout(() => router.back(), 1200)
        } else if (resp.responseCode === 429) {
          promptAction.showToast({ message: '提交太快了，请稍后再试' })
        } else {
          hilog.warn(DOMAIN, TAG, `submit feedback non-2xx: ${resp.responseCode}, body=${JSON.stringify(resp.result)}`)
          promptAction.showToast({ message: `提交失败（HTTP ${resp.responseCode}），请稍后再试` })
        }
      } finally {
        httpReq.destroy()
      }
    } catch (e) {
      const be = e as BusinessError
      hilog.error(DOMAIN, TAG, `submit feedback error: ${be?.message ?? JSON.stringify(e)}`)
      promptAction.showToast({ message: '网络异常，请稍后再试' })
    } finally {
      this.isSubmitting = false
    }
  }
}
