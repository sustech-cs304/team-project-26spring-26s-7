import { AppDimens } from '../../../common'

/**
 * 地图资质标注小条 —— 显式审图号 + 合作单位。
 *
 * 法规依据：《华为审核指南》第 12 章（互联网地图服务）要求在地图显著位置
 * 明示审图号；涉及与测绘单位合作的，同时标注合作单位。
 *
 * 本应用使用华为 Map Kit 渲染地图，由华为公司持有相关测绘资质并取得审图号，
 * 我们作为下游集成方在地图覆盖层把审图号 + 华为合作信息显示出来。
 *
 * 数值由 MAP_ATTRIBUTION_TEXT 常量统一管理；若华为之后更换审图号需要更新，
 * 只改一个文件。
 *
 * 用法：放在地图页 Stack 内部，组件自己 position 到右下角；
 *   Stack() {
 *     MapComponent(...)
 *     // 其他叠加层 ...
 *     MapAttribution()
 *   }
 */
const MAP_ATTRIBUTION_TEXT: string = '审图号 GS京(2024)2429号 · 华为终端有限公司'

@Component
export struct MapAttribution {
  /** 跟右下角的距离，默认 12vp；底部如果有控件挡住可以传入更大的 bottomOffset */
  @Prop bottomOffset: number = 12
  @Prop rightOffset: number = 12

  build() {
    Text(MAP_ATTRIBUTION_TEXT)
      .fontSize(AppDimens.FONT_XS)
      .fontColor('#FFFFFF')
      .backgroundColor('#80000000')
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .borderRadius(4)
      // 跟项目里其他右下角控件 (定位 / 缩放) 一致的 position+translate 模式，
      // 不抢占其他像素、不接触摸事件外的区域。
      .position({ x: '100%', y: '100%' })
      .translate({ x: -this.rightOffset, y: -this.bottomOffset })
      .markAnchor({ x: '100%', y: '100%' })
      .zIndex(50)
  }
}
