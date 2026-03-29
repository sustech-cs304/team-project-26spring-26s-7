import { router } from '@kit.ArkUI'
import { AppColors, AppDimens, RouterUrls } from '../../../common'
import { RouterParam } from '../../../common'

/**
 * P04 节点详情页
 * 路由参数：{ nodeId: string }
 */
@Entry
@Component
struct NodeDetailPage {
  @State title: string = '深圳湾的日落'
  @State poiName: string = '深圳湾公园'
  @State date: string = '2026.03.15'
  @State mood: string = '🤩'
  @State tags: string[] = ['旅行', '风景']
  @State content: string = '傍晚六点的深圳湾，海风带着咸味扑面而来。夕阳把整片天空染成橘红色，远处的桥在晚霞中若隐若现...'
  @State photos: string[] = []
  @State tripName: string = '深圳三日游'
  @State tripId: string = '1'
  @State nodeId: string = ''

  aboutToAppear(): void {
    const params = router.getParams() as RouterParam
    if (params?.nodeId) {
      this.nodeId = params.nodeId
      // TODO: 从本地 RDB 加载节点数据
    }
  }

  private handleDelete(): void {
    AlertDialog.show({
      title: '删除记忆',
      message: `确定要删除「${this.title}」吗？此操作不可撤销。`,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '删除',
        fontColor: AppColors.DANGER,
        action: () => {
          // TODO: 从 RDB 删除节点，级联清理照片文件，排入同步队列
          router.back()
        }
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
        Blank()
        Text('编辑')
          .fontSize(AppDimens.FONT_MD)
          .fontColor(AppColors.PRIMARY)
          .padding(AppDimens.PADDING_MD)
          .onClick(() => {
            router.pushUrl({
              url: RouterUrls.NODE_EDIT,
              params: { nodeId: this.nodeId } as RouterParam
            })
          })
        Text('删除')
          .fontSize(AppDimens.FONT_MD)
          .fontColor(AppColors.DANGER)
          .padding(AppDimens.PADDING_MD)
          .onClick(() => this.handleDelete())
      }
      .width('100%')
      .height(56)
      .backgroundColor(AppColors.CARD_BG)

      // 内容区
      Scroll() {
        Column() {
          // 照片轮播区 (占位)
          Stack() {
            Column() {
              Text('📷')
                .fontSize(48)
                .fontColor(AppColors.TEXT_HINT)
              Text('暂无照片')
                .fontSize(AppDimens.FONT_SM)
                .fontColor(AppColors.TEXT_HINT)
            }
            .justifyContent(FlexAlign.Center)
          }
          .width('100%')
          .height(240)
          .backgroundColor(AppColors.DIVIDER)
          // TODO: 替换为 Swiper 组件展示照片轮播

          // 基本信息
          Column() {
            Text(this.title)
              .fontSize(AppDimens.FONT_XL)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.TEXT_PRIMARY)

            Row() {
              Text(`📍 ${this.poiName}`)
                .fontSize(AppDimens.FONT_MD)
                .fontColor(AppColors.TEXT_SECONDARY)
              Text(`· ${this.date}`)
                .fontSize(AppDimens.FONT_MD)
                .fontColor(AppColors.TEXT_HINT)
                .margin({ left: 8 })
            }
            .margin({ top: 8 })

            Row({ space: 8 }) {
              Text(this.mood)
                .fontSize(18)
              ForEach(this.tags, (tag: string) => {
                Text(`#${tag}`)
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(AppColors.PRIMARY)
                  .backgroundColor(AppColors.PRIMARY + '15')
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .borderRadius(12)
              })
            }
            .margin({ top: 12 })
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .alignItems(HorizontalAlign.Start)

          Divider()
            .color(AppColors.DIVIDER)
            .margin({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD })

          // 正文
          Text(this.content)
            .fontSize(AppDimens.FONT_MD)
            .fontColor(AppColors.TEXT_PRIMARY)
            .lineHeight(24)
            .padding(AppDimens.PADDING_MD)
            .width('100%')

          // 所属旅行
          if (this.tripName.length > 0) {
            Row() {
              Text('所属旅行')
                .fontSize(AppDimens.FONT_MD)
                .fontColor(AppColors.TEXT_SECONDARY)
              Blank()
              Text(this.tripName)
                .fontSize(AppDimens.FONT_MD)
                .fontColor(AppColors.PRIMARY)
              Text(' >')
                .fontColor(AppColors.TEXT_HINT)
            }
            .width('100%')
            .padding(AppDimens.PADDING_MD)
            .margin({ top: 12 })
            .backgroundColor(AppColors.CARD_BG)
            .borderRadius(AppDimens.RADIUS_SM)
            .onClick(() => {
              router.pushUrl({
                url: RouterUrls.TRIP_DETAIL,
                params: { tripId: this.tripId } as RouterParam
              })
            })
          }
        }
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.BACKGROUND)
  }
}
