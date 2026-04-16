import { router, promptAction } from '@kit.ArkUI'
import { AppColors, AppDimens, RouterUrls } from '../../../common'

/**
 * P09 编辑个人资料页
 * 修改昵称、头像、个性签名
 */
@Entry
@Component
struct ProfileEditPage {
  @State nickname: string = 'TravelPin 用户'
  @State avatar: string = ''
  @State bio: string = ''
  @State isSaving: boolean = false

  aboutToAppear(): void {
    // TODO: 从 Preferences 加载用户资料
  }

  private handlePickAvatar(): void {
    // TODO: 调用系统 Photo Picker 选择头像
    promptAction.showToast({ message: '选择头像占位' })
  }

  private handleSave(): void {
    if (this.nickname.trim().length === 0) {
      promptAction.showToast({ message: '昵称不能为空' })
      return
    }

    this.isSaving = true

    // TODO: 保存到 Preferences / 同步到云端
    setTimeout(() => {
      this.isSaving = false
      promptAction.showToast({ message: '保存成功' })
      router.back()
    }, 1000)
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Text('←')
          .fontSize(AppDimens.FONT_XL)
          .fontColor(AppColors.TEXT_PRIMARY)
          .onClick(() => router.back())
          .padding(AppDimens.PADDING_MD)

        Text('编辑资料')
          .fontSize(AppDimens.FONT_LG)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)

        Text('保存')
          .fontSize(AppDimens.FONT_MD)
          .fontColor(this.isSaving ? AppColors.TEXT_HINT : AppColors.PRIMARY)
          .padding(AppDimens.PADDING_MD)
          .enabled(!this.isSaving)
          .onClick(() => this.handleSave())
      }
      .width('100%')
      .height(56)
      .backgroundColor(AppColors.CARD_BG)

      // 表单内容
      Scroll() {
        Column() {
          // 头像选择区
          Column() {
            Text('头像')
              .fontSize(AppDimens.FONT_MD)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)

            Row() {
              // 头像预览 / 添加按钮
              Column() {
                if (this.avatar) {
                  Image(this.avatar)
                    .width(80)
                    .height(80)
                    .borderRadius(40)
                } else {
                  Text('+')
                    .fontSize(32)
                    .fontColor(AppColors.TEXT_HINT)
                  Text('添加头像')
                    .fontSize(AppDimens.FONT_SM)
                    .fontColor(AppColors.TEXT_HINT)
                    .margin({ top: 4 })
                }
              }
              .width(80)
              .height(80)
              .backgroundColor(AppColors.BACKGROUND)
              .borderRadius(40)
              .justifyContent(FlexAlign.Center)
              .onClick(() => this.handlePickAvatar())
            }
            .margin({ top: 8 })
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_SM)
          .alignItems(HorizontalAlign.Start)

          // 昵称
          Column() {
            Text('昵称')
              .fontSize(AppDimens.FONT_MD)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)

            TextInput({ placeholder: '请输入昵称', text: this.nickname })
              .onChange((value: string) => { this.nickname = value })
              .margin({ top: 8 })
              .backgroundColor(AppColors.BACKGROUND)
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .margin({ top: 12 })
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_SM)
          .alignItems(HorizontalAlign.Start)

          // 个性签名
          Column() {
            Text('个性签名')
              .fontSize(AppDimens.FONT_MD)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)

            TextArea({ placeholder: '写点什么介绍自己...', text: this.bio })
              .onChange((value: string) => { this.bio = value })
              .height(100)
              .margin({ top: 8 })
              .backgroundColor(AppColors.BACKGROUND)
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .margin({ top: 12 })
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_SM)
          .alignItems(HorizontalAlign.Start)

          // 提示信息
          Column() {
            Text('💡 提示')
              .fontSize(AppDimens.FONT_SM)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.PRIMARY)

            Text('修改保存后，昵称和签名会在多设备间自动同步。')
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_HINT)
              .margin({ top: 4 })
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .margin({ top: 12 })
          .backgroundColor(AppColors.PRIMARY + '10')
          .borderRadius(AppDimens.RADIUS_SM)
          .alignItems(HorizontalAlign.Start)
        }
        .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 12 })
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.BACKGROUND)
  }
}
