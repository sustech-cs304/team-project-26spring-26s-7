import { AppColors, AppDimens } from '../../../common'

/**
 * 单次"coach mark"高亮气泡（方案 B）。
 *
 * 用法：在页面 Stack 顶层放一个 CoachMarkOverlay({ storageKey: 'coachMarkXxxSeenV1', title, message })
 * 组件内部读 @StorageLink(storageKey) 自决是否渲染；显示后用户点"知道了"或
 * 蒙层任意处，组件把 flag 写 true 进 PersistentStorage，下次不再弹。
 *
 * 不用 spotlight clip-path（HMOS 没好用的非 axis-aligned clip 减法）；
 * 改成半透明蒙层 + 居中卡片 + emoji + 标题 + 描述 + CTA 按钮，
 * 形态像 iOS 第一次进新页的提示卡。可选传 emoji 渲染图标。
 */
@Component
export struct CoachMarkOverlay {
  @Prop storageKey: string = ''
  @Prop emoji: string = '👋'
  @Prop title: string = ''
  @Prop message: string = ''
  @Prop ctaLabel: string = '知道了'

  // 用 @StorageLink 包一个动态 key 不行（ArkUI 装饰器是编译时绑定）。
  // 这里用 @State 维护 visible 状态，aboutToAppear 时从 AppStorage 拉一次值；
  // dismiss 时 AppStorage.set + visible=false，PersistentStorage 自动持久化。
  @State visible: boolean = false

  aboutToAppear(): void {
    const seen = AppStorage.get<boolean>(this.storageKey) ?? false
    this.visible = !seen
  }

  private dismiss(): void {
    AppStorage.setOrCreate(this.storageKey, true)
    this.visible = false
  }

  build() {
    if (this.visible) {
      Stack({ alignContent: Alignment.Center }) {
        // 半透明黑色蒙层 — 点任意处都关
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#99000000')
          .onClick(() => this.dismiss())

        // 居中提示卡片
        Column({ space: 12 }) {
          Text(this.emoji)
            .fontSize(56)
            .margin({ bottom: 4 })
          Text(this.title)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.TEXT_PRIMARY)
            .textAlign(TextAlign.Center)
          Text(this.message)
            .fontSize(AppDimens.FONT_MD)
            .fontColor(AppColors.TEXT_SECONDARY)
            .textAlign(TextAlign.Center)
            .lineHeight(22)
            .margin({ left: 8, right: 8 })

          Button(this.ctaLabel)
            .width('80%')
            .height(44)
            .fontSize(AppDimens.FONT_MD)
            .fontColor(AppColors.TEXT_ON_PRIMARY)
            .backgroundColor(AppColors.PRIMARY)
            .borderRadius(22)
            .margin({ top: 16 })
            .onClick(() => this.dismiss())
        }
        .width('82%')
        .padding({ left: 24, right: 24, top: 28, bottom: 24 })
        .backgroundColor(AppColors.CARD_BG)
        .borderRadius(AppDimens.RADIUS_LG)
        .shadow({ radius: 24, color: '#33000000', offsetY: 8 })
      }
      .width('100%')
      .height('100%')
      .zIndex(9999)
    }
  }
}
