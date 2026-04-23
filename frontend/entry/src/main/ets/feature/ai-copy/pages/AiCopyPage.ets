import { router, promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import {
  AppColors,
  AppDimens,
  AiGatewayClient,
  ImageCopyRequest,
  AiCopyResponse,
  PhotoPickerUtil,
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

  // 图片选择状态
  @State imagePath: string = ''

  // 页面状态
  @State selectedStyle: string = 'poetic'
  @State selectedLength: string = 'medium'
  @State userPrompt: string = ''
  @State poiName: string = ''
  @State isGenerating: boolean = false
  @State generatedCopy: string = ''
  @State alternatives: string[] = []
  private isCancelled: boolean = false

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
    const params = router.getParams() as Record<string, Object>;
    if (params) {
      this.nodeId = (params['nodeId'] as string) || '';
      this.tripId = (params['tripId'] as string) || '';
      this.poiName = (params['poiName'] as string) || '';
      const defaultPhoto = (params['defaultPhoto'] as string) || '';
      if (defaultPhoto.length > 0) {
        this.imagePath = defaultPhoto;
      }
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
   * 选择图片
   */
  private async handleSelectImage(): Promise<void> {
    try {
      const uiContext = this.getUIContext();
      const context = uiContext.getHostContext() as common.UIAbilityContext;
      if (!context) {
        promptAction.showToast({ message: '无法获取应用上下文' });
        return;
      }

      const paths = await PhotoPickerUtil.pickAndSavePhotos(context, 1);
      if (paths.length > 0) {
        this.imagePath = paths[0];
        logger.info(TAG, `Selected image: ${this.imagePath}`);
        promptAction.showToast({ message: '图片选择成功' });
      }
    } catch (err) {
      logger.error(TAG, `选择图片失败: ${err}`);
      promptAction.showToast({ message: '选择图片失败' });
    }
  }

  /**
   * 生成文案 — 基于图片 + VisionLLM
   */
  private async handleGenerate(): Promise<void> {
    if (this.isGenerating) {
      return;
    }

    if (!this.imagePath) {
      promptAction.showToast({ message: '请先选择一张图片' });
      return;
    }

    const isOnline = (AppStorage.get('networkOnline') as boolean) ?? false;
    if (!isOnline) {
      promptAction.showToast({ message: '当前无网络连接，请检查网络后重试' });
      return;
    }

    this.isGenerating = true;
    this.isCancelled = false;
    this.generatedCopy = '';
    this.alternatives = [];

    try {
      const request: ImageCopyRequest = {
        imagePath: this.imagePath,
        style: this.selectedStyle,
        lengthLevel: this.selectedLength,
        userPrompt: this.userPrompt || undefined,
        poiName: this.poiName || undefined
      };

      const response = await this.aiClient.generateCopyFromImage(request);

      if (this.isCancelled) {
        logger.info(TAG, 'Generation cancelled by user');
        return;
      }

      if (response.statusCode === 200 && response.data) {
        const aiResponse: AiCopyResponse = response.data;
        if (aiResponse.code === 0 && aiResponse.data) {
          this.generatedCopy = aiResponse.data.generated_text;
          this.alternatives = aiResponse.data.alternatives || [];
          promptAction.showToast({ message: '文案已生成' });
        } else {
          promptAction.showToast({ message: '生成失败，请重试' });
        }
      } else {
        promptAction.showToast({ message: response.error || '网络错误，请重试' });
      }
    } catch (err) {
      if (this.isCancelled) {
        return;
      }
      const errorMsg = `生成失败: ${err}`;
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
          // 图片选择区域
          Column() {
            Text('选择照片')
              .fontSize(AppDimens.FONT_MD)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)
              .margin({ bottom: 12 })

            if (this.imagePath) {
              Image(this.imagePath)
                .width(160)
                .height(160)
                .objectFit(ImageFit.Cover)
                .borderRadius(AppDimens.RADIUS_SM)
                .margin({ bottom: 8 })

              Text('点击下方按钮更换照片')
                .fontSize(AppDimens.FONT_SM)
                .fontColor(AppColors.TEXT_HINT)
                .margin({ bottom: 8 })
            } else {
              Column() {
                Text('+')
                  .fontSize(40)
                  .fontColor(AppColors.TEXT_HINT)
                Text('点击选择照片')
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(AppColors.TEXT_HINT)
                  .margin({ top: 4 })
              }
              .width(160)
              .height(160)
              .justifyContent(FlexAlign.Center)
              .backgroundColor(AppColors.BACKGROUND)
              .borderRadius(AppDimens.RADIUS_SM)
              .border({ width: 1, color: AppColors.DIVIDER, style: BorderStyle.Dashed })
              .onClick(() => this.handleSelectImage())
              .margin({ bottom: 8 })
            }

            Button(this.imagePath ? '更换照片' : '选择照片')
              .fontSize(AppDimens.FONT_MD)
              .width('100%')
              .height(40)
              .backgroundColor(AppColors.PRIMARY)
              .fontColor(Color.White)
              .onClick(() => this.handleSelectImage())
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_SM)
          .margin({ bottom: 12 })
          .alignItems(HorizontalAlign.Center)

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
            Button('生成文案')
              .fontSize(AppDimens.FONT_LG)
              .width('100%')
              .height(50)
              .backgroundColor(this.imagePath ? AppColors.PRIMARY : AppColors.TEXT_HINT)
              .fontColor(Color.White)
              .enabled(this.imagePath.length > 0)
              .onClick(() => this.handleGenerate())
              .margin({ bottom: 12 })
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
  }
}
