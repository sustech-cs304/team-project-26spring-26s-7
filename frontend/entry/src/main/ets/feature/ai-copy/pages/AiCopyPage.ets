import { router, promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import {
  AppColors,
  AppDimens,
  AiGatewayClient,
  ImagesCopyRequest,
  AiCopyResponse,
  PhotoPickerUtil,
  ConsentManager,
  logger
} from '../../../common'

const TAG = 'AiCopyPage'

/**
 * 文案风格选项接口
 */
interface StyleOption {
  value: string
  label: string
  icon: string
}

/**
 * 文案长度选项接口
 */
interface LengthOption {
  value: string
  label: string
}

/**
 * AI 文案生成页面
 * 支持图片选择 + VisionLLM 分析生成旅行文案
 */
@Entry
@Component
export struct AiCopyPage {
  // 页面参数 (从路由传入)
  @State nodeId: string = ''
  @State tripId: string = ''

  // 图片选择状态：支持多张，沙箱路径
  @State imagePaths: string[] = []
  @State metadataSummary: string = ''
  @State isExtracting: boolean = false

  // 页面状态
  @State selectedStyle: string = 'poetic'
  @State selectedLength: string = 'medium'
  @State userPrompt: string = ''
  @State poiName: string = ''
  // 上下文 GPS / 心情 / 标签（从节点带入，作为元数据兜底）
  @State latitude: number = 0
  @State longitude: number = 0
  @State mood: string = ''
  @State nodeTags: string[] = []
  @State isGenerating: boolean = false
  @State generatedCopy: string = ''
  @State alternatives: string[] = []
  // 调试：实际发送给后端的 prompt
  @State debugPrompt: string = ''
  @State debugPromptExpanded: boolean = true
  @State isPreviewingPrompt: boolean = false
  // 云端打标签同意状态（来自 ConsentManager）
  @StorageProp('aiCloudTaggingEnabled') @Watch('onCloudTaggingChanged') cloudTaggingEnabled: boolean = false
  // JIT 同意对话框展示
  @State showConsentDialog: boolean = false
  @State pendingAfterConsent: string = ''  // 'generate' | 'preview' | ''
  private isCancelled: boolean = false
  private static readonly MAX_PHOTOS: number = 9

  private onCloudTaggingChanged(): void {
    logger.info(TAG, `cloudTaggingEnabled changed to ${this.cloudTaggingEnabled}`)
  }

  // 服务实例
  private aiClient: AiGatewayClient = new AiGatewayClient()

  // 文案风格选项 (4 种)
  private styleOptions: StyleOption[] = [
    { value: 'poetic', label: '诗意盎然', icon: '🌸' },
    { value: 'factual', label: '客观纪实', icon: '📝' },
    { value: 'casual', label: '生活随笔', icon: '☕' },
    { value: 'minimal', label: '极简主义', icon: '✨' }
  ]

  // 文章长度选项
  private lengthOptions: LengthOption[] = [
    { value: 'short', label: '短 (1~2句)' },
    { value: 'medium', label: '中 (3~5句)' },
    { value: 'long', label: '长 (6~10句)' }
  ]

  aboutToAppear(): void {
    // 先把同意状态从 preferences 加载到 AppStorage，后续读 cloudTaggingEnabled 就是同步的
    const uiContext = this.getUIContext();
    const ctx = uiContext.getHostContext() as common.UIAbilityContext;
    if (ctx) {
      ConsentManager.ensureLoaded(ctx);
    }

    const params = router.getParams() as Record<string, Object>;
    if (params) {
      this.nodeId = (params['nodeId'] as string) || '';
      this.tripId = (params['tripId'] as string) || '';
      this.poiName = (params['poiName'] as string) || '';
      this.latitude = (params['latitude'] as number) || 0;
      this.longitude = (params['longitude'] as number) || 0;
      this.mood = (params['mood'] as string) || '';
      const tagsParam = params['tags'];
      if (Array.isArray(tagsParam)) {
        this.nodeTags = (tagsParam as string[]).filter((s: string) => typeof s === 'string');
      }
      const userPromptParam = (params['defaultPrompt'] as string) || '';
      if (userPromptParam.length > 0) {
        this.userPrompt = userPromptParam;
      }

      // 优先用 photos 数组；否则回退到旧的 defaultPhoto 单图字段
      const photosParam = params['photos'];
      if (Array.isArray(photosParam)) {
        const arr = (photosParam as string[]).filter((s: string) => typeof s === 'string' && s.length > 0);
        if (arr.length > 0) {
          this.imagePaths = arr.slice(0, AiCopyPage.MAX_PHOTOS);
        }
      } else {
        const defaultPhoto = (params['defaultPhoto'] as string) || '';
        if (defaultPhoto.length > 0) {
          this.imagePaths = [defaultPhoto];
        }
      }

      if (this.imagePaths.length > 0) {
        this.refreshMetadataSummary();
      }
    }
  }

  /**
   * 端侧抽 EXIF 并展示给用户，让用户知道有哪些信息会进入 prompt
   */
  private async refreshMetadataSummary(): Promise<void> {
    if (this.imagePaths.length === 0) {
      this.metadataSummary = '';
      return;
    }
    this.isExtracting = true;
    try {
      const desc = await this.aiClient.describeImages(this.imagePaths);
      this.metadataSummary = desc;
    } catch (err) {
      logger.error(TAG, `describeImages failed: ${JSON.stringify(err)}`);
      this.metadataSummary = '';
    } finally {
      this.isExtracting = false;
    }
  }

  aboutToDisappear(): void {
    if (this.isGenerating) {
      this.isCancelled = true;
      this.isGenerating = false;
      logger.info(TAG, 'Page disappearing, generation cancelled');
    }
  }

  /**
   * 追加选择图片（最多 9 张）
   */
  private async handleSelectImage(): Promise<void> {
    try {
      const uiContext = this.getUIContext();
      const context = uiContext.getHostContext() as common.UIAbilityContext;
      if (!context) {
        promptAction.showToast({ message: '无法获取应用上下文' });
        return;
      }

      const remaining = AiCopyPage.MAX_PHOTOS - this.imagePaths.length;
      if (remaining <= 0) {
        promptAction.showToast({ message: `最多 ${AiCopyPage.MAX_PHOTOS} 张照片` });
        return;
      }
      const paths = await PhotoPickerUtil.pickAndSavePhotos(context, remaining);
      if (paths.length > 0) {
        this.imagePaths = [...this.imagePaths, ...paths].slice(0, AiCopyPage.MAX_PHOTOS);
        logger.info(TAG, `Selected ${paths.length} images, total=${this.imagePaths.length}`);
        await this.refreshMetadataSummary();
      }
    } catch (err) {
      logger.error(TAG, `选择图片失败: ${err}`);
      promptAction.showToast({ message: '选择图片失败' });
    }
  }

  private async handleRemoveImage(index: number): Promise<void> {
    if (index < 0 || index >= this.imagePaths.length) {
      return;
    }
    const removed = this.imagePaths[index];
    const next = this.imagePaths.slice();
    next.splice(index, 1);
    this.imagePaths = next;
    // 让被删掉的图释放元数据缓存槽位
    if (removed) {
      this.aiClient.invalidateMetadata(removed);
    }
    await this.refreshMetadataSummary();
  }

  /**
   * 生成文案 — 端侧批量抽 EXIF -> 文本 prompt -> LLM
   * 若 ProfileView 中开启了"云端识别画面内容"，且本次还没获取过同意，
   * 这里会先弹 JIT 对话框，用户同意后再继续。
   */
  private async handleGenerate(): Promise<void> {
    if (this.isGenerating) {
      return;
    }

    if (this.imagePaths.length === 0) {
      promptAction.showToast({ message: '请先选择至少一张图片' });
      return;
    }

    const isOnline = (AppStorage.get('networkOnline') as boolean) ?? false;
    if (!isOnline) {
      promptAction.showToast({ message: '当前无网络连接，请检查网络后重试' });
      return;
    }

    // 兜底：aboutToAppear 里的 ensureLoaded 是 fire-and-forget，
    // 如果用户进页面立刻点生成，可能还没加载完。这里 await 一次保证状态正确。
    const uiContextEarly = this.getUIContext();
    const ctxEarly = uiContextEarly.getHostContext() as common.UIAbilityContext;
    if (ctxEarly) {
      await ConsentManager.ensureLoaded(ctxEarly);
    }

    // 云端打标签开关开启 + 用户未明示过 -> 先 JIT 同意
    if (ConsentManager.isCloudTaggingEnabled() && !ConsentManager.hasPrompted()) {
      this.pendingAfterConsent = 'generate';
      this.showConsentDialog = true;
      return;
    }

    this.isGenerating = true;
    this.isCancelled = false;
    this.generatedCopy = '';
    this.alternatives = [];

    try {
      const uiContext = this.getUIContext();
      const ctx = uiContext.getHostContext() as common.UIAbilityContext;
      const cloudOn = ConsentManager.isCloudTaggingEnabled();

      const request: ImagesCopyRequest = {
        imagePaths: this.imagePaths,
        style: this.selectedStyle,
        lengthLevel: this.selectedLength,
        userPrompt: this.userPrompt || undefined,
        poiName: this.poiName || undefined,
        latitude: this.latitude !== 0 ? this.latitude : undefined,
        longitude: this.longitude !== 0 ? this.longitude : undefined,
        mood: this.mood || undefined,
        tags: this.nodeTags.length > 0 ? this.nodeTags : undefined,
        enableCloudTagging: cloudOn,
        context: cloudOn ? ctx : undefined
      };

      const response = await this.aiClient.generateCopyFromImages(request);
      // 不管成功失败都把构建好的 prompt 暴露出来调试
      this.debugPrompt = this.aiClient.getLastBatchPrompt();

      if (this.isCancelled) {
        logger.info(TAG, 'Generation cancelled by user');
        return;
      }

      if (response.statusCode === 200 && response.data) {
        const aiResponse: AiCopyResponse = response.data;
        if (aiResponse.code === 0 && aiResponse.data) {
          const text = aiResponse.data.generated_text || '';
          // 后端 query 撞敏感词时返回固定文本"抱歉，内容涉及敏感信息……"
          // 这种情况下不填到生成结果区，避免用户以为是文案
          if (text.startsWith('抱歉，内容涉及敏感信息')) {
            promptAction.showToast({
              message: '您的提示词或元数据可能含敏感内容，服务端拒绝生成。请调整后重试。',
              duration: 4000
            });
            this.generatedCopy = '';
          } else {
            this.generatedCopy = text;
            this.alternatives = aiResponse.data.alternatives || [];
            promptAction.showToast({ message: '文案已生成' });
          }
        } else {
          promptAction.showToast({ message: '生成失败，请重试' });
        }
      } else if (response.statusCode === 401) {
        promptAction.showToast({ message: 'AI 服务鉴权失败，请联系管理员' });
      } else if (response.statusCode === 429) {
        promptAction.showToast({ message: '请求过于频繁，请稍后再试（30 次/分钟）' });
      } else {
        promptAction.showToast({ message: response.error || '网络错误，请重试' });
      }
    } catch (err) {
      if (this.isCancelled) {
        return;
      }
      const errorMsg = `生成失败: ${JSON.stringify(err)}`;
      logger.error(TAG, errorMsg);
      promptAction.showToast({ message: '生成失败，请检查网络' });
    } finally {
      this.isGenerating = false;
    }
  }

  /**
   * 取消生成
   */
  private handleCancelGenerate(): void {
    this.isCancelled = true;
    this.isGenerating = false;
    promptAction.showToast({ message: '已取消生成' });
  }

  /**
   * 预览 prompt（不调 LLM）
   * 若开启了 cloud tagging 且未同意，先 JIT 同意；
   * 同意 / 已同意后才会真发出云端打标请求。
   */
  private async handlePreviewPrompt(): Promise<void> {
    if (this.imagePaths.length === 0) {
      promptAction.showToast({ message: '请先选择至少一张图片' });
      return;
    }
    if (this.isPreviewingPrompt) {
      return;
    }

    const uiContextEarly = this.getUIContext();
    const ctxEarly = uiContextEarly.getHostContext() as common.UIAbilityContext;
    if (ctxEarly) {
      await ConsentManager.ensureLoaded(ctxEarly);
    }

    // 开启云端打标时预览也会发请求，离线场景需要拦下，否则一卡 60 秒
    if (ConsentManager.isCloudTaggingEnabled()) {
      const isOnline = (AppStorage.get('networkOnline') as boolean) ?? false;
      if (!isOnline) {
        promptAction.showToast({ message: '当前无网络，预览将无法获取云端内容标签' });
        return;
      }
    }

    if (ConsentManager.isCloudTaggingEnabled() && !ConsentManager.hasPrompted()) {
      this.pendingAfterConsent = 'preview';
      this.showConsentDialog = true;
      return;
    }

    this.isPreviewingPrompt = true;
    try {
      const uiContext = this.getUIContext();
      const ctx = uiContext.getHostContext() as common.UIAbilityContext;
      const cloudOn = ConsentManager.isCloudTaggingEnabled();
      const request: ImagesCopyRequest = {
        imagePaths: this.imagePaths,
        style: this.selectedStyle,
        lengthLevel: this.selectedLength,
        userPrompt: this.userPrompt || undefined,
        poiName: this.poiName || undefined,
        latitude: this.latitude !== 0 ? this.latitude : undefined,
        longitude: this.longitude !== 0 ? this.longitude : undefined,
        mood: this.mood || undefined,
        tags: this.nodeTags.length > 0 ? this.nodeTags : undefined,
        enableCloudTagging: cloudOn,
        context: cloudOn ? ctx : undefined
      };
      const prompt = await this.aiClient.previewPromptForImages(request);
      this.debugPrompt = prompt;
      this.debugPromptExpanded = true;
      promptAction.showToast({ message: 'prompt 已生成，未发送' });
    } catch (err) {
      logger.error(TAG, `预览 prompt 失败: ${JSON.stringify(err)}`);
      promptAction.showToast({ message: '预览失败' });
    } finally {
      this.isPreviewingPrompt = false;
    }
  }

  /**
   * 用户在 JIT 对话框做选择后调用
   * agreed=true / false 都视作"明确表态"，会把 prompted 写 true，下次不再弹
   */
  private async handleConsentChoice(agreed: boolean): Promise<void> {
    this.showConsentDialog = false;
    const uiContext = this.getUIContext();
    const ctx = uiContext.getHostContext() as common.UIAbilityContext;
    if (!ctx) {
      promptAction.showToast({ message: '无法获取应用上下文' });
      return;
    }
    await ConsentManager.recordPromptResult(ctx, agreed);
    if (agreed) {
      promptAction.showToast({ message: '已同意，开始上传识别' });
    } else {
      promptAction.showToast({ message: '已选择不上传照片，仅使用 EXIF 元数据生成' });
    }
    const next = this.pendingAfterConsent;
    this.pendingAfterConsent = '';
    if (next === 'generate') {
      await this.handleGenerate();
    } else if (next === 'preview') {
      await this.handlePreviewPrompt();
    }
  }

  /**
   * 用户选择"稍后再说"——不写入 enabled / prompted，仅关闭对话框，
   * 下次还会再问。被打断的 generate / preview 不再续做。
   */
  private handleConsentDismiss(): void {
    this.showConsentDialog = false;
    this.pendingAfterConsent = '';
  }

  /**
   * 复制 debug prompt 到剪贴板
   */
  private async handleCopyPrompt(): Promise<void> {
    if (!this.debugPrompt) {
      return;
    }
    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.debugPrompt);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      await systemPasteboard.setData(pasteData);
      promptAction.showToast({ message: 'prompt 已复制' });
    } catch (err) {
      logger.error(TAG, `复制 prompt 失败: ${err}`);
      promptAction.showToast({ message: '复制失败' });
    }
  }

  /**
   * 复制文案到系统剪贴板
   */
  private async handleCopy(): Promise<void> {
    if (!this.generatedCopy) {
      return;
    }
    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.generatedCopy);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      await systemPasteboard.setData(pasteData);
      promptAction.showToast({ message: '文案已复制到剪贴板' });
    } catch (err) {
      logger.error(TAG, `复制失败: ${err}`);
      promptAction.showToast({ message: '复制失败，请手动复制' });
    }
  }

  /**
   * 将生成的文案应用到节点内容并返回
   */
  private handleApplyToNode(): void {
    if (!this.generatedCopy) {
      return;
    }
    AppStorage.setOrCreate('aiCopyApplied', true);
    AppStorage.setOrCreate('aiCopyContent', this.generatedCopy);
    promptAction.showToast({ message: '文案已应用' });
    router.back();
  }

  build() {
    Stack() {
      Column() {
        // 头部栏
      Row() {
        Text('←')
          .fontSize(AppDimens.FONT_XL)
          .fontColor(AppColors.TEXT_PRIMARY)
          .onClick(() => router.back())
          .padding(AppDimens.PADDING_MD)

        Text('AI 文案助手')
          .fontSize(AppDimens.FONT_LG)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)

        if (this.generatedCopy) {
          Text('复制')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.PRIMARY)
            .padding(AppDimens.PADDING_MD)
            .onClick(() => this.handleCopy())
        }
      }
      .width('100%')
      .height(56)
      .backgroundColor(AppColors.CARD_BG)

      // 内容区域
      Scroll() {
        Column() {
          // 图片选择区域（多图）
          Column() {
            Row() {
              Text('选择照片')
                .fontSize(AppDimens.FONT_MD)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppColors.TEXT_PRIMARY)
              Blank()
              Text(`${this.imagePaths.length}/${AiCopyPage.MAX_PHOTOS}`)
                .fontSize(AppDimens.FONT_SM)
                .fontColor(AppColors.TEXT_HINT)
            }
            .width('100%')
            .margin({ bottom: 12 })

            if (this.imagePaths.length === 0) {
              Column() {
                Text('+')
                  .fontSize(40)
                  .fontColor(AppColors.TEXT_HINT)
                Text('点击选择照片（最多 9 张）')
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(AppColors.TEXT_HINT)
                  .margin({ top: 4 })
              }
              .width('100%')
              .height(140)
              .justifyContent(FlexAlign.Center)
              .backgroundColor(AppColors.BACKGROUND)
              .borderRadius(AppDimens.RADIUS_SM)
              .border({ width: 1, color: AppColors.DIVIDER, style: BorderStyle.Dashed })
              .onClick(() => this.handleSelectImage())
            } else {
              Scroll() {
                Row({ space: 8 }) {
                  ForEach(this.imagePaths, (path: string, index: number) => {
                    Stack({ alignContent: Alignment.TopEnd }) {
                      Image(path)
                        .width(96)
                        .height(96)
                        .objectFit(ImageFit.Cover)
                        .borderRadius(AppDimens.RADIUS_SM)
                      Text('×')
                        .fontSize(14)
                        .fontColor(Color.White)
                        .width(22)
                        .height(22)
                        .textAlign(TextAlign.Center)
                        .backgroundColor('#80000000')
                        .borderRadius(11)
                        .margin(4)
                        .onClick(() => this.handleRemoveImage(index))
                    }
                  })
                  if (this.imagePaths.length < AiCopyPage.MAX_PHOTOS) {
                    Column() {
                      Text('+')
                        .fontSize(28)
                        .fontColor(AppColors.TEXT_HINT)
                    }
                    .width(96)
                    .height(96)
                    .justifyContent(FlexAlign.Center)
                    .alignItems(HorizontalAlign.Center)
                    .backgroundColor(AppColors.BACKGROUND)
                    .borderRadius(AppDimens.RADIUS_SM)
                    .border({ width: 1, color: AppColors.DIVIDER, style: BorderStyle.Dashed })
                    .onClick(() => this.handleSelectImage())
                  }
                }
              }
              .scrollable(ScrollDirection.Horizontal)
              .width('100%')
              .height(96)
            }

            // 端侧元数据摘要 —— 让用户知道有哪些信息会进入 prompt
            if (this.isExtracting) {
              Row({ space: 8 }) {
                LoadingProgress().width(16).height(16)
                Text('正在端侧识别照片元数据...')
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(AppColors.TEXT_HINT)
              }
              .width('100%')
              .margin({ top: 12 })
            } else if (this.metadataSummary.length > 0) {
              Column() {
                Text(
                  this.cloudTaggingEnabled
                    ? '已识别端侧元数据（点击生成时还会上传剥离 EXIF 后的副本到云端补充识别画面内容）'
                    : '已识别端侧元数据（仅文本进入 prompt，照片本体不会上传）'
                )
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(AppColors.PRIMARY)
                  .margin({ bottom: 6 })
                Text(this.metadataSummary)
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(AppColors.TEXT_SECONDARY)
                  .lineHeight(20)
              }
              .width('100%')
              .padding(10)
              .margin({ top: 12 })
              .backgroundColor(AppColors.PRIMARY + '10')
              .borderRadius(AppDimens.RADIUS_SM)
              .alignItems(HorizontalAlign.Start)
            }
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_SM)
          .margin({ bottom: 12 })
          .alignItems(HorizontalAlign.Start)

          // 文案风格选择
          Column() {
            Text('文章风格')
              .fontSize(AppDimens.FONT_MD)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)
              .margin({ bottom: 12 })

            Grid() {
              ForEach(this.styleOptions, (style: StyleOption) => {
                GridItem() {
                  Column() {
                    Text(style.icon)
                      .fontSize(28)
                    Text(style.label)
                      .fontSize(AppDimens.FONT_SM)
                      .fontColor(this.selectedStyle === style.value ? AppColors.PRIMARY : AppColors.TEXT_SECONDARY)
                      .margin({ top: 4 })
                  }
                  .width('100%')
                  .height(70)
                  .justifyContent(FlexAlign.Center)
                  .backgroundColor(this.selectedStyle === style.value ? AppColors.PRIMARY + '20' : AppColors.BACKGROUND)
                  .borderRadius(AppDimens.RADIUS_SM)
                  .border({
                    width: 2,
                    color: this.selectedStyle === style.value ? AppColors.PRIMARY : 'transparent'
                  })
                  .onClick(() => { this.selectedStyle = style.value })
                }
              })
            }
            .columnsTemplate('1fr 1fr')
            .columnsGap(8)
            .rowsGap(8)
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_SM)
          .margin({ bottom: 12 })

          // 文章长度选择
          Column() {
            Text('生成长度')
              .fontSize(AppDimens.FONT_MD)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)
              .margin({ bottom: 12 })

            Row({ space: 12 }) {
              ForEach(this.lengthOptions, (option: LengthOption) => {
                Text(option.label)
                  .fontSize(AppDimens.FONT_MD)
                  .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                  .backgroundColor(this.selectedLength === option.value ? AppColors.PRIMARY : AppColors.BACKGROUND)
                  .fontColor(this.selectedLength === option.value ? Color.White : AppColors.TEXT_SECONDARY)
                  .borderRadius(AppDimens.RADIUS_SM)
                  .onClick(() => { this.selectedLength = option.value })
              })
            }
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_SM)
          .margin({ bottom: 12 })

          // 地点名称输入（可选）
          Column() {
            Row() {
              Text('拍摄地点 (可选)')
                .fontSize(AppDimens.FONT_MD)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppColors.TEXT_PRIMARY)
              Blank()
              if (this.poiName.length > 0) {
                Text('清空')
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(AppColors.TEXT_HINT)
                  .onClick(() => { this.poiName = '' })
              }
            }
            .width('100%')
            .margin({ bottom: 8 })

            TextInput({ placeholder: '如：西湖、故宫、富士山...', text: this.poiName })
              .fontSize(AppDimens.FONT_MD)
              .padding(AppDimens.PADDING_MD)
              .height(48)
              .backgroundColor(AppColors.BACKGROUND)
              .borderRadius(AppDimens.RADIUS_SM)
              .onChange((value: string) => { this.poiName = value })
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_SM)
          .margin({ bottom: 12 })

          // 额外提示词输入
          Column() {
            Row() {
              Text('额外提示词 (可选)')
                .fontSize(AppDimens.FONT_MD)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppColors.TEXT_PRIMARY)
              Blank()
              if (this.userPrompt.length > 0) {
                Text('清空')
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(AppColors.TEXT_HINT)
                  .onClick(() => { this.userPrompt = '' })
              }
            }
            .width('100%')
            .margin({ bottom: 8 })

            TextArea({
              placeholder: '在这里输入你的想法，例如：今天玩得很开心，看到了美丽的风景...',
              text: this.userPrompt
            })
              .fontSize(AppDimens.FONT_MD)
              .padding(AppDimens.PADDING_MD)
              .height(100)
              .backgroundColor(AppColors.BACKGROUND)
              .borderRadius(AppDimens.RADIUS_SM)
              .onChange((value: string) => { this.userPrompt = value })
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_SM)
          .margin({ bottom: 12 })

          // 生成按钮
          if (this.isGenerating) {
            Row({ space: 12 }) {
              Button('生成中...')
                .fontSize(AppDimens.FONT_LG)
                .layoutWeight(1)
                .height(50)
                .backgroundColor(AppColors.TEXT_HINT)
                .fontColor(Color.White)
                .enabled(false)

              Button('取消')
                .fontSize(AppDimens.FONT_LG)
                .width(80)
                .height(50)
                .backgroundColor('#E53935')
                .fontColor(Color.White)
                .onClick(() => this.handleCancelGenerate())
            }
            .width('100%')
            .margin({ bottom: 12 })
          } else {
            Row({ space: 8 }) {
              Button(this.isPreviewingPrompt ? '预览中...' : '预览 prompt')
                .fontSize(AppDimens.FONT_MD)
                .height(50)
                .layoutWeight(1)
                .backgroundColor(AppColors.BACKGROUND)
                .fontColor(AppColors.PRIMARY)
                .border({ width: 1, color: AppColors.PRIMARY })
                .enabled(this.imagePaths.length > 0 && !this.isPreviewingPrompt)
                .onClick(() => this.handlePreviewPrompt())

              Button(this.imagePaths.length > 0 ? `生成（${this.imagePaths.length} 张）` : '生成文案')
                .fontSize(AppDimens.FONT_LG)
                .height(50)
                .layoutWeight(2)
                .backgroundColor(
                  this.imagePaths.length > 0 && !this.isPreviewingPrompt
                    ? AppColors.PRIMARY
                    : AppColors.TEXT_HINT
                )
                .fontColor(Color.White)
                .enabled(this.imagePaths.length > 0 && !this.isPreviewingPrompt)
                .onClick(() => this.handleGenerate())
            }
            .width('100%')
            .margin({ bottom: 12 })
          }

          // 调试：实际发送的 prompt
          if (this.debugPrompt.length > 0) {
            Column() {
              Row() {
                Text('🔧 实际 prompt（调试）')
                  .fontSize(AppDimens.FONT_MD)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(AppColors.TEXT_PRIMARY)
                Blank()
                Text(this.debugPromptExpanded ? '收起' : '展开')
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(AppColors.PRIMARY)
                  .padding({ left: 8, right: 8 })
                  .onClick(() => { this.debugPromptExpanded = !this.debugPromptExpanded })
                Text('复制')
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(AppColors.PRIMARY)
                  .padding({ left: 8, right: 8 })
                  .onClick(() => this.handleCopyPrompt())
              }
              .width('100%')
              .margin({ bottom: 8 })

              if (this.debugPromptExpanded) {
                Scroll() {
                  Text(this.debugPrompt)
                    .fontSize(12)
                    .fontColor(AppColors.TEXT_SECONDARY)
                    .lineHeight(18)
                    .width('100%')
                    .copyOption(CopyOptions.LocalDevice)
                }
                .width('100%')
                .constraintSize({ maxHeight: 260 })
                .padding(10)
                .backgroundColor('#0F000000')
                .borderRadius(AppDimens.RADIUS_SM)

                Text(`长度：${this.debugPrompt.length} 字符`)
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(AppColors.TEXT_HINT)
                  .margin({ top: 6 })
              }
            }
            .width('100%')
            .padding(AppDimens.PADDING_MD)
            .margin({ bottom: 12 })
            .backgroundColor(AppColors.CARD_BG)
            .borderRadius(AppDimens.RADIUS_SM)
            .alignItems(HorizontalAlign.Start)
          }

          // 生成结果展示
          if (this.generatedCopy) {
            Column() {
              Row() {
                Text('生成结果')
                  .fontSize(AppDimens.FONT_MD)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(AppColors.TEXT_PRIMARY)

                Blank()

                Text('复制')
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(AppColors.PRIMARY)
                  .padding({ left: 12, right: 4, top: 4, bottom: 4 })
                  .onClick(() => this.handleCopy())
              }
              .width('100%')
              .margin({ bottom: 8 })

              Scroll() {
                Text(this.generatedCopy)
                  .fontSize(AppDimens.FONT_MD)
                  .fontColor(AppColors.TEXT_PRIMARY)
                  .lineHeight(26)
                  .width('100%')
              }
              .width('100%')
              .constraintSize({ maxHeight: 300 })
              .padding(AppDimens.PADDING_MD)
              .backgroundColor(AppColors.BACKGROUND)
              .borderRadius(AppDimens.RADIUS_SM)
            }
            .width('100%')
            .padding(AppDimens.PADDING_MD)
            .backgroundColor(AppColors.CARD_BG)
            .borderRadius(AppDimens.RADIUS_SM)

            // 应用到节点按钮
            Button('应用到节点内容并返回')
              .fontSize(AppDimens.FONT_MD)
              .width('100%')
              .height(46)
              .backgroundColor(AppColors.PRIMARY)
              .fontColor(Color.White)
              .borderRadius(AppDimens.RADIUS_SM)
              .margin({ top: 12 })
              .onClick(() => this.handleApplyToNode())

            // 备选文案展示
            if (this.alternatives.length > 0) {
              Column() {
                Text('备选方案')
                  .fontSize(AppDimens.FONT_MD)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(AppColors.TEXT_PRIMARY)
                  .margin({ bottom: 8 })

                ForEach(this.alternatives, (alt: string, index: number) => {
                  Text(alt)
                    .fontSize(AppDimens.FONT_SM)
                    .fontColor(AppColors.TEXT_SECONDARY)
                    .lineHeight(22)
                    .width('100%')
                    .padding(AppDimens.PADDING_MD)
                    .backgroundColor(AppColors.BACKGROUND)
                    .borderRadius(AppDimens.RADIUS_SM)
                    .margin({ bottom: 4 })
                })
              }
              .width('100%')
              .padding(AppDimens.PADDING_MD)
              .backgroundColor(AppColors.CARD_BG)
              .borderRadius(AppDimens.RADIUS_SM)
              .margin({ top: 12 })
            }
          }
        }
        .padding(AppDimens.PADDING_MD)
      }
      .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.BACKGROUND)

      // JIT 同意对话框
      if (this.showConsentDialog) {
        Column() {
          Column()
            .width('100%')
            .layoutWeight(1)

          Column() {
            Row() {
              Text('🛡️ 隐私授权请求')
                .fontSize(AppDimens.FONT_LG)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppColors.TEXT_PRIMARY)
              Blank()
              Text('稍后再说')
                .fontSize(AppDimens.FONT_SM)
                .fontColor(AppColors.TEXT_HINT)
                .padding({ left: 12, right: 4, top: 4, bottom: 4 })
                .onClick(() => this.handleConsentDismiss())
            }
            .width('100%')
            .margin({ bottom: 12 })

            Text(
              '为了让 AI 更准确地识别照片画面内容（例如"猫"、"沙发"、"夕阳"），' +
              '需要把您选择的若干张照片以剥离 GPS / 设备信息后的副本上传至云端 Qwen-VL 模型进行内容识别。' +
              '\n\n• 上传副本不含 GPS、相机型号等敏感 EXIF；' +
              '\n• 推理结束后云端立即删除该副本，不进行持久化存储、不写入业务数据库、不记录原始图片内容或文件名；' +
              '\n• 您可以随时在"我的 → 隐私与安全"中关闭。' +
              '\n\n如果不同意，本次仍可生成文案，但仅基于元数据（拍摄时间、位置等），不上传任何照片。'
            )
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_SECONDARY)
              .lineHeight(20)
              .margin({ bottom: 16 })

            Row({ space: 12 }) {
              Button('不上传照片')
                .fontSize(AppDimens.FONT_MD)
                .layoutWeight(1)
                .height(44)
                .backgroundColor(AppColors.BACKGROUND)
                .fontColor(AppColors.TEXT_PRIMARY)
                .border({ width: 1, color: AppColors.DIVIDER })
                .onClick(() => this.handleConsentChoice(false))

              Button('同意上传')
                .fontSize(AppDimens.FONT_MD)
                .layoutWeight(1)
                .height(44)
                .backgroundColor(AppColors.PRIMARY)
                .fontColor(Color.White)
                .onClick(() => this.handleConsentChoice(true))
            }
            .width('100%')
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 24, bottom: 24 })
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius({ topLeft: 26, topRight: 26 })
          .shadow({ radius: 16, color: '#26000000', offsetY: -2 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .justifyContent(FlexAlign.End)
      }
    }
    .width('100%')
    .height('100%')
  }
}
