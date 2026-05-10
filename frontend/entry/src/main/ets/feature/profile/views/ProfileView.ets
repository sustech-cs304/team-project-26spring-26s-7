import { router, promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import {
  AppColors,
  AppDimens,
  AuthService,
  RouterUrls,
  RdbDataService,
  SyncManager,
  ConsentManager,
  OfflineMapService
} from '../../../common'

/**
 * 个人中心 Tab 内容视图
 */
@Component
export struct ProfileView {
  @StorageLink('appThemeVersion') themeVersion: number = 0
  @State displayName: string = 'TravelPin 用户'
  @State avatarUrl: string = ''
  @State avatarLoadFailed: boolean = false
  @State loginStatusText: string = '华为账号已登录'
  @State cloudStatusText: string = '云存储未连接'
  @State lastSyncTime: string = '未同步'
  @State lastPushTime: string = '未上传'
  @State lastPullTime: string = '未下载'
  @State pendingCount: number = 0
  @State isSyncing: boolean = false
  /** 上传 AI 云端打标签前自动剥 EXIF：当前实现已在 ImageSanitizer 中强制开启，UI 仅展示状态 */
  @State exifStripAlwaysOn: boolean = true
  /** AI 云端打标签开关，绑定 ConsentManager 持久化的同意状态 */
  @StorageLink('aiCloudTaggingEnabled') aiCloudTaggingEnabled: boolean = false
  @State wifiOnlySync: boolean = true
  @Watch('onShareLinkExpiryChanged')
  @StorageLink('shareLinkExpiryDays') shareLinkExpiryDays: number = 7
  @State shareLinkExpiry: string = '7 天'
  @StorageLink('networkJustReconnected') networkJustReconnected: boolean = false
  @Watch('onTabRefresh')
  @StorageLink('tabRefreshToken') tabRefreshToken: number = 0
  @StorageLink('activeTabIndex') activeTabIndex: number = 0

  aboutToAppear(): void {
    this.syncShareLinkExpiryFromStorage()
    void this.loadAuthStatus()
    const uiContext = this.getUIContext()
    const ctx = uiContext.getHostContext() as common.UIAbilityContext
    if (ctx) {
      ConsentManager.ensureLoaded(ctx)
    }
  }

  onPageShow(): void {
    this.syncShareLinkExpiryFromStorage()
    void this.loadAuthStatus()
  }

  private onTabRefresh(): void {
    if (this.activeTabIndex === 3) {
      this.syncShareLinkExpiryFromStorage()
      void this.loadAuthStatus()
    }
  }

  private syncShareLinkExpiryFromStorage(): void {
    const days = AppStorage.get<number>('shareLinkExpiryDays') ?? 7
    this.shareLinkExpiry = `${days} 天`
  }

  private onShareLinkExpiryChanged(): void {
    this.shareLinkExpiry = `${this.shareLinkExpiryDays} 天`
  }

  private formatSyncTime(timestamp: number): string {
    if (timestamp <= 0) {
      return '未同步'
    }
    const diff = Date.now() - timestamp
    if (diff < 60 * 1000) {
      return '刚刚'
    }
    const minutes = Math.floor(diff / (60 * 1000))
    if (minutes < 60) {
      return `${minutes} 分钟前`
    }
    const hours = Math.floor(minutes / 60)
    if (hours < 24) {
      return `${hours} 小时前`
    }
    const days = Math.floor(hours / 24)
    return `${days} 天前`
  }

  private async loadAuthStatus(): Promise<void> {
    try {
      const effective = await AuthService.getEffectiveProfile()
      if (effective) {
        this.displayName = effective.displayName
        this.avatarUrl = effective.avatarUrl
        this.avatarLoadFailed = false
      } else {
        const status = await AuthService.getAuthStatus()
        this.displayName = status.user?.displayName ?? 'TravelPin 用户'
        this.avatarUrl = status.user?.avatarUrl ?? ''
        this.avatarLoadFailed = false
      }

      const status = await AuthService.getAuthStatus()
      this.loginStatusText = status.isLoggedIn ? '华为账号已登录' : '未登录'
      this.cloudStatusText = status.cloudStatusText

      const syncStatus = await new RdbDataService().getSyncStatus()
      this.pendingCount = syncStatus.pendingCount
      this.lastSyncTime = this.formatSyncTime(syncStatus.lastSyncTime)
      this.lastPushTime = this.formatSyncTime(syncStatus.lastPushTime ?? 0)
      this.lastPullTime = this.formatSyncTime(syncStatus.lastPullTime ?? 0)
      this.isSyncing = syncStatus.isSyncing
    } catch (_) {
      this.loginStatusText = '登录状态获取失败'
      this.cloudStatusText = '云存储暂不可用'
    }
  }

  private async runPushSync(): Promise<void> {
    this.isSyncing = true
    try {
      await SyncManager.pushAllLocalToCloud()
      AppStorage.setOrCreate('networkJustReconnected', false)
      await this.loadAuthStatus()
    } finally {
      this.isSyncing = false
    }
  }

  private async runPullSync(): Promise<void> {
    this.isSyncing = true
    try {
      await SyncManager.pullAllCloudToLocal()
      AppStorage.setOrCreate('networkJustReconnected', false)
      await this.loadAuthStatus()
      const partialFailure = AppStorage.get('syncPartialFailure') as boolean
      const failedCount = AppStorage.get('syncFailedNodeCount') as number
      if (partialFailure && failedCount > 0) {
        promptAction.showToast({ message: `下载完成，但有 ${failedCount} 个节点图片下载失败` })
      } else {
        promptAction.showToast({ message: '云端数据下载完成' })
      }
    } catch (_) {
      promptAction.showToast({ message: '云端数据下载失败，请重试' })
    } finally {
      this.isSyncing = false
    }
  }

  private handleLogout(): void {
    AlertDialog.show({
      title: '退出登录',
      message: '退出后本地数据不会丢失，但需要重新登录后才能继续同步。',
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '退出',
        fontColor: AppColors.DANGER,
        action: async () => {
          try {
            await AuthService.signOut()
            promptAction.showToast({ message: '已退出登录' })
            router.replaceUrl({ url: RouterUrls.LOGIN })
          } catch (_) {
            promptAction.showToast({ message: '退出登录失败，请重试' })
          }
        }
      }
    })
  }

  private handleDeleteAccount(): void {
    // 第一步：风险提示
    AlertDialog.show({
      title: '注销账号',
      message: '注销账号将永久删除您的所有云端数据（旅行记录、照片、记忆节点等），此操作不可恢复。是否继续？',
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '我已知晓，继续',
        fontColor: AppColors.DANGER,
        action: () => this.confirmDeleteAccount()
      }
    })
  }

  private confirmDeleteAccount(): void {
    // 第二步：最终确认
    AlertDialog.show({
      title: '最终确认',
      message: '请再次确认注销账号。点击确认后将立即开始删除数据，此操作不可撤销。',
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '确认注销',
        fontColor: AppColors.DANGER,
        action: () => { void this.performDeleteAccount() }
      }
    })
  }

  private async performDeleteAccount(): Promise<void> {
    if (this.isSyncing) {
      promptAction.showToast({ message: '同步进行中，请稍后再试' })
      return
    }
    this.isSyncing = true
    try {
      promptAction.showToast({ message: '正在注销账号，请稍候…' })
      await AuthService.deleteAccount()
      const uiContext = this.getUIContext()
      const ctx = uiContext.getHostContext() as common.UIAbilityContext
      if (ctx) {
        await ConsentManager.clearAllConsents(ctx)
      }
      promptAction.showToast({ message: '账号已注销' })
      router.replaceUrl({ url: RouterUrls.LOGIN })
    } catch (err) {
      promptAction.showToast({ message: '注销失败，请检查网络后重试' })
    } finally {
      this.isSyncing = false
    }
  }

  private showPrivacySettings(): void {
    const cloudOn = this.aiCloudTaggingEnabled
    const message =
      `📷 EXIF 自动剥离：始终开启\n` +
      `任何离开本设备的照片副本都会先去掉 GPS、相机型号等敏感字段，原图保留在本机。\n\n` +
      `🤖 AI 云端识别画面内容：${cloudOn ? '已开启' : '已关闭'}\n` +
      (cloudOn
        ? '生成文案时，会把首张照片以剥离 EXIF 后的副本上传至 Qwen-VL 模型，让模型直接看图写文案，推理结束云端立即删除。\n首次上传前会单独询问。'
        : '当前仅使用端侧 EXIF / OCR 元数据生成文案，照片本体不会上传。\n开启后第一次生成时会再次确认是否同意上传。') +
      `\n\n点击下方按钮可切换 AI 云端识别开关。`
    AlertDialog.show({
      title: '隐私与安全',
      message: message,
      primaryButton: {
        value: cloudOn ? '关闭云端识别' : '开启云端识别',
        action: () => this.toggleCloudTagging()
      },
      secondaryButton: {
        value: '关闭',
        action: () => {}
      }
    })
  }

  private async toggleCloudTagging(): Promise<void> {
    const uiContext = this.getUIContext()
    const ctx = uiContext.getHostContext() as common.UIAbilityContext
    if (!ctx) {
      promptAction.showToast({ message: '无法获取应用上下文' })
      return
    }
    const next = !this.aiCloudTaggingEnabled
    await ConsentManager.setCloudTaggingEnabled(ctx, next)
    promptAction.showToast({
      message: next ? '已开启 AI 云端识别' : '已关闭 AI 云端识别'
    })
  }

  private showStorageSettings(): void {
    AlertDialog.show({
      title: '流量与存储',
      message:
        `仅 Wi-Fi 同步：${this.wifiOnlySync ? '已开启' : '已关闭'}\n\n` +
        '开启后，蜂窝网络下仅加载缩略图，原图和批量同步会延后到 Wi-Fi 环境执行。',
      confirm: {
        value: '关闭',
        action: () => {}
      }
    })
  }

  private showExpirySettings(): void {
    ActionSheet.show({
      title: '分享链接默认有效期',
      message: '选择通过链接分享路线时的默认有效期。',
      sheets: [
        { title: '1 天', action: () => { this.shareLinkExpiryDays = 1 } },
        { title: '7 天', action: () => { this.shareLinkExpiryDays = 7 } },
        { title: '30 天', action: () => { this.shareLinkExpiryDays = 30 } },
      ]
    })
  }

  private showOfflineMapGuide(): void {
    const launchAndMark = async () => {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const result = await OfflineMapService.getInstance().openPetalMapsForDownload(context)
      if (result.notInstalled) {
        AlertDialog.show({
          title: '未找到花瓣地图',
          message:
            '离线地图需要先通过花瓣地图下载数据。\n请从华为应用市场安装花瓣地图后重试。\n\n' +
            '安装后进入 我的 → 离线地图 → 地图资源管理 → 地区列表，\n下载"全球基础包"和常用城市地图。\n\n' +
            '本应用使用华为 Map Kit，下载完成后断网时地图会自动可用。'
        })
        return
      }
      if (!result.launched) {
        promptAction.showToast({ message: '跳转失败，请稍后重试' })
        return
      }
      try {
        await OfflineMapService.getInstance().markAsDownloaded(context)
      } catch (_) {}
    }
    AlertDialog.show({
      title: '离线地图下载',
      message:
        '本应用使用华为 Map Kit，在手机已下载离线地图时会自动优先加载本地数据。\n\n' +
        '操作步骤：\n' +
        '1. 点击下方"确定"跳转至花瓣地图\n' +
        '2. 依次进入 我的 → 离线地图 → 地图资源管理 → 地区列表\n' +
        '3. 先下载"全球基础包"，再按需下载常用城市的离线地图包\n' +
        '4. 完成后返回本应用即可',
      primaryButton: {
        value: '确定，去下载',
        action: () => { launchAndMark() }
      },
      secondaryButton: {
        value: '取消',
        action: () => {}
      }
    })
  }

  private showAbout(): void {
    AlertDialog.show({
      title: '关于 TravelPin',
      message:
        'TravelPin v1.0.0\n\n' +
        '基于 HarmonyOS 的地理位置旅行日记应用。\n\n' +
        '南方科技大学 软件工程课程 第 7 组',
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

  private resolveAvatarUrl(url: string): string {
    return url && (url.startsWith('file://') || url.startsWith('http')) ? url : `file://${url}`
  }

  build() {
    Scroll() {
      Column() {
        Row() {
          Column() {
            if (this.avatarUrl.length > 0 && !this.avatarLoadFailed) {
              Image(this.resolveAvatarUrl(this.avatarUrl))
                .width(56)
                .height(56)
                .borderRadius(28)
                .onError(() => {
                  this.avatarLoadFailed = true
                })
            } else {
              Text('👤')
                .fontSize(32)
            }
          }
          .width(56)
          .height(56)
          .backgroundColor(AppColors.BACKGROUND)
          .borderRadius(28)
          .justifyContent(FlexAlign.Center)

          Column() {
            Text(this.displayName)
              .fontSize(AppDimens.FONT_LG)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)
            Text(this.loginStatusText)
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_HINT)
              .margin({ top: 4 })
          }
          .margin({ left: 12 })
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Text('编辑')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.PRIMARY)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .onClick(() => {
              router.pushUrl({ url: RouterUrls.PROFILE_EDIT })
            })
        }
        .width('100%')
        .padding(AppDimens.PADDING_LG)
        .backgroundColor(AppColors.CARD_BG)

        Column() {
          Row() {
            Text('同步状态')
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

          if (this.networkJustReconnected) {
            Row() {
              Text('网络已恢复，离线期间的更改不会自动同步，请手动点击同步按钮上传到云端。')
                .fontSize(AppDimens.FONT_SM)
                .fontColor(AppColors.TEXT_PRIMARY)
                .layoutWeight(1)
              Text('知道了')
                .fontSize(AppDimens.FONT_SM)
                .fontColor(AppColors.PRIMARY)
                .margin({ left: 8 })
                .onClick(() => {
                  AppStorage.setOrCreate('networkJustReconnected', false)
                })
            }
            .width('100%')
            .padding(AppDimens.PADDING_SM)
            .margin({ top: 12 })
            .backgroundColor('#FFF7E6')
            .borderRadius(AppDimens.RADIUS_SM)
          }

          Row() {
            Column() {
              Text(`云状态：${this.cloudStatusText}`)
                .fontSize(AppDimens.FONT_SM)
                .fontColor(this.cloudStatusText === '云存储已连接' ? AppColors.SUCCESS : AppColors.TEXT_SECONDARY)
              Text(`上次同步：${this.lastSyncTime}`)
                .fontSize(AppDimens.FONT_SM)
                .fontColor(AppColors.TEXT_SECONDARY)
                .margin({ top: 4 })
              Text(`最近上传：${this.lastPushTime}`)
                .fontSize(AppDimens.FONT_SM)
                .fontColor(AppColors.TEXT_SECONDARY)
                .margin({ top: 4 })
              Text(`最近下载：${this.lastPullTime}`)
                .fontSize(AppDimens.FONT_SM)
                .fontColor(AppColors.TEXT_SECONDARY)
                .margin({ top: 4 })
              Text(`待同步：${this.pendingCount} 项`)
                .fontSize(AppDimens.FONT_SM)
                .fontColor(this.pendingCount > 0 ? AppColors.PRIMARY : AppColors.TEXT_HINT)
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Row() {
              Button(this.isSyncing ? '上传中...' : '上传本地')
                .height(32)
                .fontSize(AppDimens.FONT_SM)
                .backgroundColor(AppColors.PRIMARY)
                .enabled(!this.isSyncing)
                .onClick(() => { void this.runPushSync() })

              Button(this.isSyncing ? '下载中...' : '下载云端')
                .height(32)
                .fontSize(AppDimens.FONT_SM)
                .backgroundColor(AppColors.SUCCESS)
                .enabled(!this.isSyncing)
                .margin({ left: 8 })
                .onClick(() => { void this.runPullSync() })
            }
            .margin({ top: 12 })
          }
          .width('100%')
          .margin({ top: 12 })
        }
        .width('100%')
        .padding(AppDimens.PADDING_MD)
        .margin({ top: 12 })
        .backgroundColor(AppColors.CARD_BG)
        .borderRadius(AppDimens.RADIUS_MD)

        Column() {
          Text('设置')
            .fontSize(AppDimens.FONT_MD)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_PRIMARY)
            .padding({ left: AppDimens.PADDING_MD, top: AppDimens.PADDING_MD, bottom: 8 })
            .width('100%')

          this.settingItem(
            '隐私与安全',
            this.aiCloudTaggingEnabled ? '云端识别 已开启 · EXIF 自动剥离' : 'EXIF 自动剥离 · 云端识别 已关闭',
            () => this.showPrivacySettings()
          )
          Divider().color(AppColors.DIVIDER)
          this.settingItem('流量与存储', this.wifiOnlySync ? '仅 Wi-Fi' : '', () => this.showStorageSettings())
          Divider().color(AppColors.DIVIDER)
          this.settingItem('分享链接默认有效期', this.shareLinkExpiry, () => this.showExpirySettings())
          Divider().color(AppColors.DIVIDER)
          this.settingItem('离线地图', '下载全球基础包', () => this.showOfflineMapGuide())
          this.settingItem('用户协议', '', () => router.pushUrl({ url: RouterUrls.USER_AGREEMENT }))
          Divider().color(AppColors.DIVIDER)
          this.settingItem('隐私政策', '', () => router.pushUrl({ url: RouterUrls.PRIVACY_POLICY }))
          Divider().color(AppColors.DIVIDER)
          this.settingItem('关于 TravelPin', 'v1.0.0', () => this.showAbout())
        }
        .margin({ top: 12 })
        .backgroundColor(AppColors.CARD_BG)
        .borderRadius(AppDimens.RADIUS_MD)

        Text('退出登录')
          .fontSize(AppDimens.FONT_MD)
          .fontColor(AppColors.DANGER)
          .textAlign(TextAlign.Center)
          .width('100%')
          .height(52)
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_MD)
          .margin({ top: 24 })
          .onClick(() => this.handleLogout())

        Text('注销账号')
          .fontSize(AppDimens.FONT_MD)
          .fontColor(AppColors.DANGER)
          .textAlign(TextAlign.Center)
          .width('100%')
          .height(52)
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_MD)
          .margin({ top: 12, bottom: 24 })
          .onClick(() => this.handleDeleteAccount())
      }
      .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.BACKGROUND)
  }
}
