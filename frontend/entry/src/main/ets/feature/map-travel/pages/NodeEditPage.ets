import { router, promptAction } from '@kit.ArkUI'
import { AppColors, AppDimens, RouterUrls } from '../../../common'
import { RouterParam } from '../../../common'

/**
 * P03 节点创建/编辑页
 * 路由参数：{ nodeId?: string, latitude?: number, longitude?: number }
 */
@Entry
@Component
struct NodeEditPage {
  @State title: string = ''
  @State content: string = ''
  @State poiName: string = '获取位置中...'
  @State mood: string = ''
  @State tags: string[] = []
  @State photos: string[] = []
  @State isEditMode: boolean = false

  aboutToAppear(): void {
    const params = router.getParams() as RouterParam
    if (params?.nodeId && params.nodeId.length > 0) {
      this.isEditMode = true
      // TODO: 从本地 RDB 加载节点数据回填
    }
    if (params?.latitude && params?.longitude) {
      this.poiName = params.latitude + ', ' + params.longitude
      // TODO: 逆地理编码获取 POI 名称
    }
  }

  private handleSave(): void {
    // TODO: 校验必填字段，写入本地 RDB，排入同步队列
    router.back()
  }

  private handlePickPhoto(): void {
    // TODO: 调用系统 Photo Picker，选择后本地剥离 EXIF
  }

  private handleNavigateToAI(): void {
    router.pushUrl({
      url: RouterUrls.AI_COPY,
      params: {
        defaultPrompt: this.content,
        defaultTitle: this.title
      }
    })
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
        Text(this.isEditMode ? '编辑记忆' : '新建记忆')
          .fontSize(AppDimens.FONT_LG)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
        Text('保存')
          .fontSize(AppDimens.FONT_LG)
          .fontColor(AppColors.PRIMARY)
          .padding(AppDimens.PADDING_MD)
          .onClick(() => this.handleSave())
      }
      .width('100%')
      .height(56)
      .backgroundColor(AppColors.CARD_BG)

      // 表单内容 (可滚动)
      Scroll() {
        Column() {
          // 位置信息
          Row() {
            Text('📍')
              .fontSize(18)
            Text(this.poiName)
              .fontSize(AppDimens.FONT_MD)
              .fontColor(AppColors.TEXT_SECONDARY)
              .margin({ left: 8 })
              .layoutWeight(1)
            Text('重新选点 >')
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.PRIMARY)
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_SM)

          // 照片选择区
          Column() {
            Text('照片')
              .fontSize(AppDimens.FONT_MD)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)
            Row() {
              // 已选照片占位 (TODO: 动态渲染 this.photos)
              Column() {
                Text('+')
                  .fontSize(28)
                  .fontColor(AppColors.TEXT_HINT)
                Text('添加照片')
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(AppColors.TEXT_HINT)
              }
              .width(80)
              .height(80)
              .backgroundColor(AppColors.BACKGROUND)
              .borderRadius(AppDimens.RADIUS_SM)
              .justifyContent(FlexAlign.Center)
              .onClick(() => this.handlePickPhoto())
            }
            .margin({ top: 8 })
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .margin({ top: 12 })
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_SM)
          .alignItems(HorizontalAlign.Start)

          // 标题
          Column() {
            Text('标题')
              .fontSize(AppDimens.FONT_MD)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)
            TextInput({ placeholder: '给这段记忆起个名字', text: this.title })
              .onChange((value: string) => { this.title = value })
              .margin({ top: 8 })
              .backgroundColor(AppColors.BACKGROUND)
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .margin({ top: 12 })
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_SM)
          .alignItems(HorizontalAlign.Start)

          // 内容
          Column() {
            Text('内容')
              .fontSize(AppDimens.FONT_MD)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)
            TextArea({ placeholder: '写下这一刻的感受...', text: this.content })
              .onChange((value: string) => { this.content = value })
              .height(120)
              .margin({ top: 8 })
              .backgroundColor(AppColors.BACKGROUND)
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .margin({ top: 12 })
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_SM)
          .alignItems(HorizontalAlign.Start)

          // AI 助手按钮 (放在内容下方，更显眼)
          Row() {
            Text('🤖 AI 助手')
              .fontSize(AppDimens.FONT_MD)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.PRIMARY)
            Text('  帮你润色内容')
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_SECONDARY)
            Blank()
            Text('→')
              .fontSize(AppDimens.FONT_LG)
              .fontColor(AppColors.PRIMARY)
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .backgroundColor(AppColors.PRIMARY + '10')
          .borderRadius(AppDimens.RADIUS_SM)
          .margin({ bottom: 12, top: 8 })
          .onClick(() => this.handleNavigateToAI())

          // 心情选择
          Column() {
            Text('心情')
              .fontSize(AppDimens.FONT_MD)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)
            Row({ space: 16 }) {
              ForEach(['😊', '😢', '🤩', '😌', '🥰', '😤'], (emoji: string) => {
                Text(emoji)
                  .fontSize(28)
                  .padding(8)
                  .borderRadius(AppDimens.RADIUS_SM)
                  .backgroundColor(this.mood === emoji ? AppColors.PRIMARY + '20' : 'transparent')
                  .onClick(() => { this.mood = emoji })
              })
            }
            .margin({ top: 8 })
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .margin({ top: 12 })
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_SM)
          .alignItems(HorizontalAlign.Start)

          // 标签
          Column() {
            Text('标签')
              .fontSize(AppDimens.FONT_MD)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.TEXT_PRIMARY)
            Row({ space: 8 }) {
              ForEach(['旅行', '美食', '风景', '打卡', '日常'], (tag: string) => {
                Text(`#${tag}`)
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(this.tags.includes(tag) ? AppColors.CARD_BG : AppColors.PRIMARY)
                  .backgroundColor(this.tags.includes(tag) ? AppColors.PRIMARY : AppColors.PRIMARY + '15')
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .borderRadius(20)
                  .onClick(() => {
                    if (this.tags.includes(tag)) {
                      this.tags = this.tags.filter(t => t !== tag)
                    } else {
                      this.tags = [...this.tags, tag]
                    }
                  })
              })
            }
            .margin({ top: 8 })
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .margin({ top: 12, bottom: 24 })
          .backgroundColor(AppColors.CARD_BG)
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
