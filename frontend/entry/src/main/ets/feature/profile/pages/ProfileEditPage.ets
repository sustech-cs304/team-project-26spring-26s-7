import { router, promptAction } from '@kit.ArkUI'
import { AppColors, AppDimens, AuthService, ImageCensorService, RouterUrls } from '../../../common'
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN = 0x0000;
const TAG = 'ProfileEditPage';

/**
 * P09 编辑个人资料页
 * 修改昵称、头像、个性签名
 */
@Entry
@Component
struct ProfileEditPage {
  @StorageLink('appThemeVersion') themeVersion: number = 0
  @State nickname: string = 'ItsMapPin 用户'
  @State avatar: string = ''
  @State bio: string = ''
  @State isSaving: boolean = false
  @State isCheckingAvatar: boolean = false
  @State saveProgressText: string = ''

  aboutToAppear(): void {
    this.loadProfile()
  }

  onPageShow(): void {
    const cropApplied = AppStorage.get('avatarCropApplied') as boolean
    if (!cropApplied) {
      return
    }

    const cropPath = (AppStorage.get('avatarCropPath') as string) || ''
    AppStorage.setOrCreate('avatarCropApplied', false)
    AppStorage.setOrCreate('avatarCropPath', '')
    if (cropPath.length > 0) {
      void this.auditSelectedAvatar(cropPath)
    }
  }

  private async loadProfile(): Promise<void> {
    try {
      const effective = await AuthService.getEffectiveProfile()
      if (effective) {
        this.nickname = effective.displayName
        // 本地沙箱路径需加 file:// 前缀，华为 HTTP URL 直接使用
        this.avatar = effective.avatarUrl && !effective.avatarUrl.startsWith('http')
          ? `file://${effective.avatarUrl}` : effective.avatarUrl
        this.bio = effective.bio
      } else {
        const status = await AuthService.getAuthStatus()
        this.nickname = status.user?.displayName ?? 'ItsMapPin 用户'
        this.avatar = status.user?.avatarUrl ?? ''
      }
    } catch (_) {
      // 读取失败时保留默认值
    }
  }

  private isNetworkOnline(): boolean {
    return (AppStorage.get('networkOnline') as boolean) ?? false
  }

  private async handlePickAvatar(): Promise<void> {
    if (this.isCheckingAvatar) {
      promptAction.showToast({ message: '头像正在审核中，请稍候' })
      return
    }

    if (!this.isNetworkOnline()) {
      promptAction.showToast({ message: '当前无网络，无法更换头像' })
      return
    }

    let candidatePath = ''
    try {
      const photoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = 1;

      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const result = await photoPicker.select(photoSelectOptions);

      if (result.photoUris && result.photoUris.length > 0) {
        const uri = result.photoUris[0];
        const context = getContext(this);

        // 确保目录存在
        const sandboxDir = context.filesDir + '/photos';
        try {
          fs.mkdirSync(sandboxDir, true);
        } catch (_) {
          // 目录已存在时会报错，忽略
        }

        const fileName = `avatar_${Date.now()}.jpg`;
        const targetPath = `${sandboxDir}/${fileName}`;
        candidatePath = targetPath;

        // 打开源文件并复制到沙箱
        const sourceFile = fs.openSync(uri, fs.OpenMode.READ_ONLY);
        const targetFile = fs.openSync(targetPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);

        const bufferSize = 4096;
        const buffer = new ArrayBuffer(bufferSize);

        try {
          let readLen = fs.readSync(sourceFile.fd, buffer);
          while (readLen > 0) {
            fs.writeSync(targetFile.fd, buffer.slice(0, readLen));
            readLen = fs.readSync(sourceFile.fd, buffer);
          }
        } finally {
          fs.closeSync(sourceFile);
          fs.closeSync(targetFile);
        }

        router.pushUrl({
          url: RouterUrls.PROFILE_AVATAR_CROP,
          params: { sourcePath: targetPath }
        })
        candidatePath = ''
      }
    } catch (err) {
      if (candidatePath.length > 0) {
        this.deleteAvatarCandidate(candidatePath);
      }
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, `Avatar pick failed: ${error?.code ?? 'unknown'} - ${error?.message ?? error}`);
      if ((err as Error).message === 'IMAGE_CENSOR_NETWORK_ERROR') {
        AlertDialog.show({
          title: '头像审核失败',
          message: '图片安全审核服务暂不可用，请检查网络后重试。',
          primaryButton: {
            value: '我知道了',
            action: () => {}
          }
        })
      } else {
        promptAction.showToast({ message: '选择头像失败，请重试' });
      }
    } finally {
      this.isCheckingAvatar = false
    }
  }

  private async auditSelectedAvatar(candidatePath: string): Promise<void> {
    if (this.isCheckingAvatar) {
      this.deleteAvatarCandidate(candidatePath)
      return
    }

    this.isCheckingAvatar = true
    try {
      promptAction.showToast({ message: '正在审核头像安全性...' })
      const auditResult = await ImageCensorService.checkLocalImage(candidatePath)
      if (!auditResult.is_safe) {
        this.deleteAvatarCandidate(candidatePath)
        this.showAvatarViolationDialog(auditResult.conclusion)
        return
      }

      this.avatar = candidatePath
      promptAction.showToast({ message: '头像已选择' })
    } catch (err) {
      this.deleteAvatarCandidate(candidatePath)
      const error = err as BusinessError
      hilog.warn(DOMAIN, TAG, `Avatar audit failed: ${error?.code ?? 'unknown'} - ${error?.message ?? error}`)
      if ((err as Error).message === 'IMAGE_CENSOR_NETWORK_ERROR') {
        AlertDialog.show({
          title: '头像审核失败',
          message: '图片安全审核服务暂不可用，请检查网络后重试。',
          primaryButton: {
            value: '我知道了',
            action: () => {}
          }
        })
      } else {
        promptAction.showToast({ message: '头像审核失败，请重试' })
      }
    } finally {
      this.isCheckingAvatar = false
    }
  }

  private showAvatarViolationDialog(conclusion: string): void {
    const detail = conclusion && conclusion.length > 0 ? `：${conclusion}` : ''
    AlertDialog.show({
      title: '图片违规',
      message: `该头像未通过图片安全审核${detail}，请选择其他图片。`,
      primaryButton: {
        value: '我知道了',
        action: () => {}
      }
    })
  }

  private deleteAvatarCandidate(path: string): void {
    try {
      fs.unlinkSync(path.startsWith('file://') ? path.substring(7) : path)
    } catch (_) {
      // Best effort cleanup for rejected or failed avatar candidates.
    }
  }

  private bumpProfileVersion(): void {
    const version = AppStorage.get<number>('profile_version') ?? 0
    AppStorage.setOrCreate('profile_version', version + 1)
  }

  private async handleSave(): Promise<void> {
    if (!this.isNetworkOnline()) {
      promptAction.showToast({ message: '当前无网络，请在联网后保存资料' })
      return
    }

    if (this.nickname.trim().length === 0) {
      promptAction.showToast({ message: '昵称不能为空' })
      return
    }

    this.isSaving = true
    this.saveProgressText = '正在审核并保存资料...'

    try {
      await AuthService.saveLocalProfile({
        displayName: this.nickname.trim(),
        avatarPath: this.avatar,
        bio: this.bio.trim(),
        userModified: true  // 标记为用户主动修改，登录时不再被华为账号覆盖
      })
      // 写一个递增版本号，让 ProfileView 检测到返回事件并刷新
      this.bumpProfileVersion()
      promptAction.showToast({ message: '保存成功' })
      router.back()
    } catch (err) {
      const error = err as BusinessError;
      promptAction.showToast({ message: error.message || '保存失败，请重试' });
    } finally {
      this.isSaving = false
      this.saveProgressText = ''
    }
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
          .fontColor(this.isSaving || this.isCheckingAvatar ? AppColors.TEXT_HINT : AppColors.PRIMARY)
          .padding(AppDimens.PADDING_MD)
          .enabled(!this.isSaving && !this.isCheckingAvatar)
          .onClick(() => this.handleSave())
      }
      .width('100%')
      .height(56)
      .backgroundColor(AppColors.CARD_BG)

      if (this.isSaving) {
        Row() {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(AppColors.PRIMARY)
          Text(this.saveProgressText)
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_SECONDARY)
            .margin({ left: 8 })
        }
        .width('100%')
        .height(40)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(AppColors.CARD_BG)
      }

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
                Column() {
                  if (this.avatar) {
                    Image(this.avatar.startsWith('file://') || this.avatar.startsWith('http')
                      ? this.avatar : `file://${this.avatar}`)
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

                if (this.isCheckingAvatar) {
                  Row() {
                    LoadingProgress()
                      .width(16)
                      .height(16)
                      .color(AppColors.PRIMARY)
                    Text('正在审核头像...')
                      .fontSize(AppDimens.FONT_SM)
                      .fontColor(AppColors.PRIMARY)
                      .margin({ left: 6 })
                  }
                  .margin({ top: 8 })
                  .justifyContent(FlexAlign.Center)
                }
              }
              .width(140)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
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
              .fontColor(AppColors.INPUT_TEXT)
              .placeholderColor(AppColors.INPUT_PLACEHOLDER)
              .caretColor(AppColors.INPUT_CARET)
              .backgroundColor(AppColors.INPUT_BG)
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
              .fontColor(AppColors.INPUT_TEXT)
              .placeholderColor(AppColors.INPUT_PLACEHOLDER)
              .caretColor(AppColors.INPUT_CARET)
              .backgroundColor(AppColors.INPUT_BG)
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
