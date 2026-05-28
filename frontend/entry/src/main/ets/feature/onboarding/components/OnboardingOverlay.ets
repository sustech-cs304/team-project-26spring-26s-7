import { common } from '@kit.AbilityKit'
import { AppColors, AppDimens, OnboardingStore } from '../../../common'

/**
 * 首启 3 页轮播引导（方案 A 简版）。
 *
 * 显示条件：onboardingLoaded === true && onboardingSeen === false
 *   - onboardingLoaded：等到 OnboardingStore.ensureLoaded 读完磁盘前不弹，
 *     避免冷启动期间的"先弹一下又消失"闪烁
 *   - onboardingSeen：已经看过就永不再弹（看完 / 跳过 都算）
 *
 * dismiss 通过 OnboardingStore.markSeen 同时写 AppStorage 和 preferences 磁盘，
 * 下次冷启动 ensureLoaded 会读到 true 直接不弹。
 *
 * MainPage.aboutToAppear 负责 fire-and-forget 调 ensureLoaded(ctx)；本组件只读
 * 两个 @StorageLink 自决渲染。
 */
@Component
export struct OnboardingOverlay {
  @StorageLink('onboardingLoaded') loaded: boolean = false
  @StorageLink('onboardingSeenV1') seen: boolean = false
  @State currentSlide: number = 0
  private readonly totalSlides: number = 3

  private dismiss(): void {
    this.seen = true
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined
    if (ctx) {
      OnboardingStore.markSeen(ctx)
    }
  }

  private goNext(): void {
    if (this.currentSlide < this.totalSlides - 1) {
      this.currentSlide += 1
    } else {
      this.dismiss()
    }
  }

  @Builder
  private buildSlideOne() {
    Column() {
      Text('📍')
        .fontSize(96)
        .margin({ bottom: 24 })
      Text('ItsMapPin')
        .fontSize(36)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.TEXT_PRIMARY)
        .margin({ bottom: 12 })
      Text('把每段旅途留在地图上')
        .fontSize(AppDimens.FONT_MD)
        .fontColor(AppColors.TEXT_SECONDARY)
        .textAlign(TextAlign.Center)
        .margin({ left: 32, right: 32 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildSlideTwo() {
    Column({ space: 24 }) {
      Text('三步玩转 ItsMapPin')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.TEXT_PRIMARY)
        .margin({ bottom: 12 })

      this.buildBullet('🗺️', '在地图上打钉', '"+" 创建带照片和文字的记忆节点')
      this.buildBullet('🎬', '一键生成旅程回放', '运镜动画 + 背景音乐，把行程拍成短片')
      this.buildBullet('📤', '分享到微信', '生成专属链接，朋友点开就能看你的旅程')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 32, right: 32 })
  }

  @Builder
  private buildBullet(emoji: string, title: string, desc: string) {
    Row({ space: 16 }) {
      Text(emoji)
        .fontSize(36)
        .width(48)
        .textAlign(TextAlign.Center)
      Column({ space: 4 }) {
        Text(title)
          .fontSize(AppDimens.FONT_MD)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_PRIMARY)
        Text(desc)
          .fontSize(AppDimens.FONT_SM)
          .fontColor(AppColors.TEXT_SECONDARY)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
  }

  @Builder
  private buildSlideThree() {
    Column() {
      Text('🚀')
        .fontSize(80)
        .margin({ bottom: 24 })
      Text('准备好了吗？')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.TEXT_PRIMARY)
        .margin({ bottom: 12 })
      Text('从现在开始记录你的下一段旅程')
        .fontSize(AppDimens.FONT_MD)
        .fontColor(AppColors.TEXT_SECONDARY)
        .textAlign(TextAlign.Center)
        .margin({ left: 32, right: 32 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildPageDots() {
    Row({ space: 8 }) {
      ForEach([0, 1, 2], (i: number) => {
        Stack()
          .width(this.currentSlide === i ? 24 : 8)
          .height(8)
          .borderRadius(4)
          .backgroundColor(this.currentSlide === i ? AppColors.PRIMARY : AppColors.DIVIDER)
          .animation({ duration: 200, curve: Curve.EaseInOut })
      })
    }
    .margin({ bottom: 16 })
  }

  build() {
    if (this.loaded && !this.seen) {
      Stack({ alignContent: Alignment.Center }) {
        // 背景蒙层 — 全屏不透明卡片，挡住背后所有内容和点击
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(AppColors.BACKGROUND)

        Column() {
          // Skip 按钮（右上）
          Row() {
            Blank()
            Text('跳过')
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_SECONDARY)
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .onClick(() => this.dismiss())
          }
          .width('100%')
          .padding({ top: 24, right: 16 })

          // 中间轮播区
          Swiper() {
            this.buildSlideOne()
            this.buildSlideTwo()
            this.buildSlideThree()
          }
          .layoutWeight(1)
          .width('100%')
          .index(this.currentSlide)
          .loop(false)
          .indicator(false)
          .onChange((index: number) => {
            this.currentSlide = index
          })

          // 底部分页指示 + Next/Done 按钮
          this.buildPageDots()

          Button(this.currentSlide === this.totalSlides - 1 ? '开始记录我的旅程' : '下一步')
            .width('80%')
            .height(48)
            .fontSize(AppDimens.FONT_MD)
            .fontColor(AppColors.TEXT_ON_PRIMARY)
            .backgroundColor(AppColors.PRIMARY)
            .borderRadius(24)
            .onClick(() => this.goNext())
            .margin({ bottom: 40 })
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .zIndex(10000)
    }
  }
}
