import { router } from '@kit.ArkUI'
import { AppColors, AppDimens, RouterUrls } from '../common'

/**
 * 个人中心 Tab 内容视图
 * 用户信息、同步状态、设置入口
 */
@Component
export struct ProfileView {
  @State lastSyncTime: string = '2 分钟前'
  @State pendingCount: number = 3
  @State isSyncing: boolean = false
  @State exifStrip: boolean = true
  @State wifiOnlySync: boolean = true
  @State shareLinkExpiry: string = '7天'

  private handleSync(): void {
    this.isSyncing = true
    // TODO: 触发 SyncManager 立即同步
    setTimeout(() => {
      this.isSyncing = false
      this.lastSyncTime = '刚刚'
      this.pendingCount = 0
    }, 2000)
  }

  private handleLogout(): void {
    AlertDialog.show({
      title: '退出登录',
      message: '退出后本地数据不会丢失，但需要重新登录才能同步。',
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '退出',
        fontColor: AppColors.DANGER,
        action: () => {
          // TODO: 清除 Account Kit 登录态
          router.replaceUrl({ url: RouterUrls.LOGIN })
        }
      }
    })
  }

  private showPrivacySettings(): void {
    AlertDialog.show({
      title: '隐私与安全',
      message: `EXIF 元数据自动剥离: ${this.exifStrip ? '已开启' : '已关闭'}\n\n所有照片在上传或分享前会自动移除位置、设备等敏感信息。\n\nAI 文案仅使用文本元数据，不会上传照片到云端。`,
      confirm: {
        value: '关闭',
        action: () => {}
      }
    })
  }

  private showStorageSettings(): void {
    AlertDialog.show({
      title: '流量与存储',
      message: `仅 Wi-Fi 同步: ${this.wifiOnlySync ? '已开启' : '已关闭'}\n\n开启后，蜂窝网络下仅加载缩略图，照片原图和批量同步将延迟到 Wi-Fi 环境下进行。`,
      confirm: {
        value: '关闭',
        action: () => {}
      }
    })
  }

  private showExpirySettings(): void {
    ActionSheet.show({
      title: '分享链接默认有效期',
      message: '选择通过链接分享旅行时的默认有效期',
      sheets: [
        { title: '1 天', action: () => { this.shareLinkExpiry = '1天' } },
        { title: '7 天', action: () => { this.shareLinkExpiry = '7天' } },
        { title: '30 天', action: () => { this.shareLinkExpiry = '30天' } },
      ]
    })
  }

  private showAbout(): void {
    AlertDialog.show({
      title: '关于 TravelPin',
      message: 'TravelPin v1.0.0\n\n基于 HarmonyOS 的地理位置旅行日记应用\n\n南方科技大学 · 软件工程 · 第7组',
      confirm: {
        value: '关闭',
        action: () => {}
      }
    })
  }

  @Builder
  settingItem(title: string, subtitle: string = '', action: () => void = () => {}) {
    Row() {
      Text(title)
        .fontSize(AppDimens.FONT_MD)
        .fontColor(AppColors.TEXT_PRIMARY)
      Blank()
      if (subtitle.length > 0) {
        Text(subtitle)
          .fontSize(AppDimens.FONT_SM)
          .fontColor(AppColors.TEXT_HINT)
          .margin({ right: 4 })
      }
      Text('>')
        .fontSize(AppDimens.FONT_MD)
        .fontColor(AppColors.TEXT_HINT)
    }
    .width('100%')
    .height(52)
    .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD })
    .backgroundColor(AppColors.CARD_BG)
    .onClick(action)
  }

  build() {
    Scroll() {
      Column() {
        // 用户信息卡片
        Row() {
          Column() {
            Text('👤')
              .fontSize(32)
          }
          .width(56)
          .height(56)
          .backgroundColor(AppColors.BACKGROUND)
          .borderRadius(28)
          .justifyContent(FlexAlign.Center)

          Column() {
            Text('TravelPin 用户')
              .fontSize(AppDimens.FONT_LG)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)
            Text('华为账号已登录')
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_HINT)
              .margin({ top: 4 })
          }
          .margin({ left: 12 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding(AppDimens.PADDING_LG)
        .backgroundColor(AppColors.CARD_BG)

        // 同步状态卡片
        Column() {
          Row() {
            Text('☁️ 同步状态')
              .fontSize(AppDimens.FONT_MD)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)
            Blank()
            if (this.isSyncing) {
              LoadingProgress()
                .width(16)
                .height(16)
                .color(AppColors.PRIMARY)
            }
          }
          .width('100%')

          Row() {
            Column() {
              Text(`上次同步: ${this.lastSyncTime}`)
                .fontSize(AppDimens.FONT_SM)
                .fontColor(AppColors.TEXT_SECONDARY)
              Text(`待同步: ${this.pendingCount} 项`)
                .fontSize(AppDimens.FONT_SM)
                .fontColor(this.pendingCount > 0 ? AppColors.PRIMARY : AppColors.TEXT_HINT)
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Button(this.isSyncing ? '同步中...' : '立即同步')
              .height(32)
              .fontSize(AppDimens.FONT_SM)
              .backgroundColor(AppColors.PRIMARY)
              .enabled(!this.isSyncing)
              .onClick(() => this.handleSync())
          }
          .width('100%')
          .margin({ top: 12 })
        }
        .width('100%')
        .padding(AppDimens.PADDING_MD)
        .margin({ top: 12 })
        .backgroundColor(AppColors.CARD_BG)
        .borderRadius(AppDimens.RADIUS_MD)

        // 设置列表
        Column() {
          Text('⚙️ 设置')
            .fontSize(AppDimens.FONT_MD)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_PRIMARY)
            .padding({ left: AppDimens.PADDING_MD, top: AppDimens.PADDING_MD, bottom: 8 })
            .width('100%')

          this.settingItem('隐私与安全', this.exifStrip ? 'EXIF 剥离已开启' : '', () => this.showPrivacySettings())
          Divider().color(AppColors.DIVIDER)
          this.settingItem('流量与存储', this.wifiOnlySync ? '仅 Wi-Fi' : '', () => this.showStorageSettings())
          Divider().color(AppColors.DIVIDER)
          this.settingItem('分享链接默认有效期', this.shareLinkExpiry, () => this.showExpirySettings())
          Divider().color(AppColors.DIVIDER)
          this.settingItem('关于 TravelPin', 'v1.0.0', () => this.showAbout())
        }
        .margin({ top: 12 })
        .backgroundColor(AppColors.CARD_BG)
        .borderRadius(AppDimens.RADIUS_MD)

        // 退出登录
        Text('退出登录')
          .fontSize(AppDimens.FONT_MD)
          .fontColor(AppColors.DANGER)
          .textAlign(TextAlign.Center)
          .width('100%')
          .height(52)
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_MD)
          .margin({ top: 24, bottom: 24 })
          .onClick(() => this.handleLogout())
      }
      .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.BACKGROUND)
  }
}
