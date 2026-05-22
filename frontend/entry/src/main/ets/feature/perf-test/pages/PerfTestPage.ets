import { router, promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import {
  AppColors,
  AppDimens,
  getDataService,
  CreateNodeInput,
  MemoryNodeRepository,
  AiGatewayClient,
  ImagesCopyRequest,
  TravelSpecialValues,
  logger
} from '../../../common'
import type { IDataService } from '../../../common'

const TAG = 'PerfTest'

@Entry
@Component
struct PerfTestPage {
  // ═══ 节点压力测试 ═══
  @State nodeCount: string = '100'
  @State attachPhoto: boolean = false
  @State photoUri: string = ''
  @State nodeTestRunning: boolean = false
  @State nodeTestResult: string = ''
  @State nodeTestDetail: string = ''

  // ═══ AI并发压力测试 ═══
  @State aiPhotoUri: string = ''
  @State aiConcurrency: string = '5'
  @State aiTestRunning: boolean = false
  @State aiTestResult: string = ''
  @State aiTestDetail: string = ''

  // ═══ 删除 ═══
  @State deleteRunning: boolean = false
  @State deleteResult: string = ''

  private dataService: IDataService = getDataService()
  private nodeRepo: MemoryNodeRepository = new MemoryNodeRepository()
  private aiClient: AiGatewayClient = new AiGatewayClient()

  private formatTime(ms: number): string {
    if (ms < 1000) return `${ms}ms`
    return `${(ms / 1000).toFixed(2)}s`
  }

  // ═══════════════════════════════════════════════
  // 选择照片
  // ═══════════════════════════════════════════════

  private async pickPhoto(): Promise<string> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (!ctx) {
      promptAction.showToast({ message: '无法获取上下文' })
      return ''
    }
    try {
      const options = new photoAccessHelper.PhotoSelectOptions()
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
      options.maxSelectNumber = 1
      const picker = new photoAccessHelper.PhotoViewPicker()
      const result = await picker.select(options)
      if (result.photoUris.length > 0) {
        promptAction.showToast({ message: '已选择照片' })
        return result.photoUris[0]
      }
      return ''
    } catch (e) {
      promptAction.showToast({ message: '选择照片失败' })
      return ''
    }
  }

  private async pickNodePhoto(): Promise<void> {
    const uri = await this.pickPhoto()
    if (uri) this.photoUri = uri
  }

  private async pickAiPhoto(): Promise<void> {
    const uri = await this.pickPhoto()
    if (uri) this.aiPhotoUri = uri
  }

  // ═══════════════════════════════════════════════
  // 节点压力测试（走真实 RdbDataService.createNode 链路）
  // ═══════════════════════════════════════════════

  private async runNodeStressTest(): Promise<void> {
    const count = parseInt(this.nodeCount)
    if (isNaN(count) || count < 1 || count > 500) {
      promptAction.showToast({ message: '节点数需在 1-500 之间' })
      return
    }
    const photos: string[] = this.attachPhoto && this.photoUri ? [this.photoUri] : []

    this.nodeTestRunning = true
    this.nodeTestResult = ''
    this.nodeTestDetail = ''

    const times: number[] = []
    const totalStart = Date.now()

    try {
      for (let i = 0; i < count; i++) {
        this.nodeTestResult = `创建中... ${i + 1}/${count}`

        const input: CreateNodeInput = {
          travelId: TravelSpecialValues.UNCATEGORIZED_TRAVEL_ID,
          title: `perf_node_${i}`,
          content: '性能测试节点',
          latitude: 22.55 + (i % 20) * 0.001,
          longitude: 113.96 + Math.floor(i / 20) * 0.001,
          poiName: '测试地点',
          photos: photos,
          mood: '开心',
          tags: ['测试'],
          visitedAt: Date.now()
        }

        const start = Date.now()
        await this.dataService.createNode(input)
        times.push(Date.now() - start)
      }

      const totalElapsed = Date.now() - totalStart
      const avg = times.reduce((a, b) => a + b, 0) / count
      const min = Math.min(...times)
      const max = Math.max(...times)

      const BATCH = 10
      const groupAvgs: string[] = []
      const batchCount = Math.ceil(count / BATCH)
      for (let g = 0; g < batchCount; g++) {
        const slice = times.slice(g * BATCH, (g + 1) * BATCH)
        const avgBatch = slice.reduce((a, b) => a + b, 0) / slice.length
        groupAvgs.push(this.formatTime(avgBatch))
      }

      const first10Avg = times.slice(0, 10).reduce((a, b) => a + b, 0) / 10
      const last10Avg = times.slice(-10).reduce((a, b) => a + b, 0) / 10
      const deg = first10Avg > 0 ? ((last10Avg - first10Avg) / first10Avg * 100) : 0

      this.nodeTestResult =
        `总耗时: ${this.formatTime(totalElapsed)}  |  平均: ${this.formatTime(avg)}  |  最快: ${this.formatTime(min)}  |  最慢: ${this.formatTime(max)}`

      let detail = `前10个平均: ${this.formatTime(first10Avg)}  →  后10个平均: ${this.formatTime(last10Avg)}`
      if (deg > 20) detail += `  ⚠ 性能下降 ${deg.toFixed(0)}%`
      else if (deg > 5) detail += `  波动 ${deg.toFixed(0)}%`
      else detail += `  变化 ${deg.toFixed(0)}%（稳定）`

      detail += `\n每10个平均耗时: ${groupAvgs.join(' → ')}`
      if (max > avg * 3) {
        detail += `\n⚠ 异常尖峰：最慢 ${this.formatTime(max)}（${(max / avg).toFixed(1)} 倍平均）`
      }

      this.nodeTestDetail = detail

      const report = `${this.nodeTestResult}\n${detail}`
      logger.info(TAG, `[节点压测 x${count}] ${report.replace(/\n/g, ' | ')}`)
      AlertDialog.show({
        title: `创建${count}个节点完成`,
        message: report,
        confirm: { value: '确定', action: () => {} }
      })
    } catch (e) {
      this.nodeTestResult = `错误: ${JSON.stringify(e)}`
    } finally {
      this.nodeTestRunning = false
    }
  }

  // ═══════════════════════════════════════════════
  // AI 并发压力测试（走真实 AiGatewayClient.generateCopyFromImages 链路）
  // ═══════════════════════════════════════════════

  private async runAiStressTest(): Promise<void> {
    const concurrency = parseInt(this.aiConcurrency)
    if (isNaN(concurrency) || concurrency < 1 || concurrency > 20) {
      promptAction.showToast({ message: '并发数需在 1-20 之间' })
      return
    }
    if (!this.aiPhotoUri) {
      promptAction.showToast({ message: '请先选择一张照片（AI文案需要照片提取EXIF信息）' })
      return
    }

    this.aiTestRunning = true
    this.aiTestResult = ''
    this.aiTestDetail = ''

    try {
      // 共享同一个 request 对象（与真实用户 AiCopyPage 的请求一致）
      const sharedRequest: ImagesCopyRequest = {
        imagePaths: [this.aiPhotoUri],
        style: '诗意盎然',
        lengthLevel: 'short',
        poiName: '深圳湾公园',
        mood: '开心',
        tags: ['旅行', '风景'],
        userPrompt: '',
        enableCloudTagging: false
      }

      // 先预热一次（让 EXIF 缓存命中，后续请求跳过提取）
      this.aiTestResult = '预热中（提取EXIF/OCR元数据）...'
      await this.aiClient.generateCopyFromImages(sharedRequest)

      // 并发发送
      this.aiTestResult = `正在并发发送 ${concurrency} 个请求...`

      interface TaskResult {
        index: number
        time: number
        success: boolean
        error: string
      }

      const tasks: TaskResult[] = []
      for (let i = 0; i < concurrency; i++) {
        tasks.push({ index: i, time: 0, success: false, error: '' })
      }

      const wallStart = Date.now()
      const promises = tasks.map(async (task) => {
        const t0 = Date.now()
        try {
          const resp = await this.aiClient.generateCopyFromImages(sharedRequest)
          task.time = Date.now() - t0
          task.success = resp.statusCode === 200 && resp.data !== undefined
          if (!task.success) task.error = resp.error ?? 'unknown'
        } catch (e) {
          task.time = Date.now() - t0
          task.success = false
          task.error = JSON.stringify(e)
        }
      })

      await Promise.all(promises)
      const wallTime = Date.now() - wallStart

      const successCount = tasks.filter(t => t.success).length
      const failCount = concurrency - successCount
      const responseTimes = tasks.map(t => t.time)
      const avgTime = responseTimes.reduce((a, b) => a + b, 0) / concurrency
      const minTime = Math.min(...responseTimes)
      const maxTime = Math.max(...responseTimes)

      this.aiTestResult =
        `总耗时: ${this.formatTime(wallTime)}  |  成功: ${successCount}  |  失败: ${failCount}`

      let detail = `平均响应: ${this.formatTime(avgTime)}  |  最快: ${this.formatTime(minTime)}  |  最慢: ${this.formatTime(maxTime)}\n`
      detail += `各请求耗时: ${tasks.map(t => `${t.success ? '✓' : '✗'}${this.formatTime(t.time)}`).join('  ')}`
      if (failCount > 0) {
        const firstFail = tasks.find(t => !t.success)
        if (firstFail) detail += `\n首个失败原因: ${firstFail.error}`
      }

      this.aiTestDetail = detail

      logger.info(TAG, `[AI并发x${concurrency}] ${this.aiTestResult} | ${detail.replace(/\n/g, ' | ')}`)
      AlertDialog.show({
        title: `AI并发${concurrency}路测试完成`,
        message: `${this.aiTestResult}\n\n${detail}`,
        confirm: { value: '确定', action: () => {} }
      })
    } catch (e) {
      this.aiTestResult = `错误: ${JSON.stringify(e)}`
    } finally {
      this.aiTestRunning = false
    }
  }

  // ═══════════════════════════════════════════════
  // 一键删除测试节点
  // ═══════════════════════════════════════════════

  private async deleteAllTestNodes(): Promise<void> {
    this.deleteRunning = true
    this.deleteResult = ''

    try {
      const allNodes = await this.nodeRepo.getAllNodesIncludingDeleted()
      const testNodes = allNodes.filter(n => n.title && n.title.startsWith('perf_'))

      if (testNodes.length === 0) {
        this.deleteResult = '没有找到测试节点'
        promptAction.showToast({ message: '没有找到测试节点' })
        return
      }

      this.deleteResult = `正在删除 ${testNodes.length} 个测试节点...`
      let deleted = 0

      for (const node of testNodes) {
        await this.nodeRepo.softDeleteNode(node.id)
        await this.nodeRepo.deleteNode(node.id)
        deleted++
        this.deleteResult = `删除中... ${deleted}/${testNodes.length}`
      }

      this.deleteResult = `已删除 ${deleted} 个测试节点`
      logger.info(TAG, `[清理] ${this.deleteResult}`)
      promptAction.showToast({ message: this.deleteResult })
    } catch (e) {
      this.deleteResult = `删除失败: ${JSON.stringify(e)}`
    } finally {
      this.deleteRunning = false
    }
  }

  // ═══════════════════════════════════════════════
  // UI
  // ═══════════════════════════════════════════════

  @Builder
  sectionHeader(title: string) {
    Text(title)
      .fontSize(AppDimens.FONT_SM)
      .fontColor(AppColors.TEXT_HINT)
      .padding({ left: AppDimens.PADDING_MD, top: 16, bottom: 4 })
      .width('100%')
  }

  build() {
    Column() {
      Row() {
        Text('<')
          .fontSize(24)
          .fontColor(AppColors.TEXT_PRIMARY)
          .onClick(() => router.back())
        Text('压力测试')
          .fontSize(AppDimens.FONT_LG)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColors.TEXT_PRIMARY)
          .margin({ left: 12 })
      }
      .width('100%')
      .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 12, bottom: 12 })

      Scroll() {
        Column() {
          // ═══ 节点压力测试 ═══
          this.sectionHeader('节点压力测试（走 RdbDataService.createNode 完整链路）')
          Column() {
            Row() {
              Text('节点数量（1-500）')
                .fontSize(AppDimens.FONT_MD)
                .fontColor(AppColors.TEXT_PRIMARY)
              TextInput({ text: this.nodeCount })
                .width(70)
                .height(36)
                .fontSize(AppDimens.FONT_MD)
                .backgroundColor(AppColors.INPUT_BG)
                .borderRadius(8)
                .type(InputType.Number)
                .onChange((value: string) => { this.nodeCount = value })
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
            .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 12 })

            Divider().color(AppColors.DIVIDER)

            Row() {
              Text('每个节点附加照片')
                .fontSize(AppDimens.FONT_MD)
                .fontColor(AppColors.TEXT_PRIMARY)
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.attachPhoto })
                .onChange((value: boolean) => { this.attachPhoto = value })
            }
            .width('100%')
            .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 10, bottom: 10 })

            if (this.attachPhoto) {
              Row() {
                Button(this.photoUri ? '重新选择' : '选择照片')
                  .fontSize(AppDimens.FONT_SM)
                  .height(32)
                  .backgroundColor(AppColors.PRIMARY)
                  .onClick(() => { void this.pickNodePhoto() })
                if (this.photoUri) {
                  Text('已选 1 张')
                    .fontSize(AppDimens.FONT_XS)
                    .fontColor(AppColors.TEXT_HINT)
                    .margin({ left: 8 })
                }
                Blank()
                Text('节点保存 → 构建 photoManifest → 写入同步队列 → 在线时上传照片')
                  .fontSize(10)
                  .fontColor(AppColors.TEXT_HINT)
                  .maxLines(2)
              }
              .width('100%')
              .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, bottom: 10 })
            }

            if (this.nodeTestResult.length > 0) {
              Divider().color(AppColors.DIVIDER)
              Column() {
                Text(this.nodeTestResult)
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(AppColors.TEXT_SECONDARY)
                  .maxLines(5)
                if (this.nodeTestDetail.length > 0) {
                  Text(this.nodeTestDetail)
                    .fontSize(AppDimens.FONT_XS)
                    .fontColor(AppColors.TEXT_HINT)
                    .margin({ top: 4 })
                    .maxLines(12)
                }
              }
              .width('100%')
              .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 8 })
              .alignItems(HorizontalAlign.Start)
            }

            Divider().color(AppColors.DIVIDER)

            Button(this.nodeTestRunning ? `创建中...` : '开始测试')
              .fontSize(AppDimens.FONT_MD)
              .height(44)
              .width('100%')
              .backgroundColor(this.nodeTestRunning ? AppColors.TEXT_HINT : AppColors.PRIMARY)
              .fontColor(AppColors.TEXT_ON_PRIMARY)
              .margin({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, bottom: 12 })
              .enabled(!this.nodeTestRunning && !this.aiTestRunning && !this.deleteRunning)
              .onClick(() => { void this.runNodeStressTest() })
          }
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_MD)

          // ═══ AI并发压力测试 ═══
          this.sectionHeader('AI 并发压力测试（走 AiGatewayClient.generateCopyFromImages 完整链路）')
          Column() {
            Row() {
              Text('并发请求数（1-20）')
                .fontSize(AppDimens.FONT_MD)
                .fontColor(AppColors.TEXT_PRIMARY)
              TextInput({ text: this.aiConcurrency })
                .width(70)
                .height(36)
                .fontSize(AppDimens.FONT_MD)
                .backgroundColor(AppColors.INPUT_BG)
                .borderRadius(8)
                .type(InputType.Number)
                .onChange((value: string) => { this.aiConcurrency = value })
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
            .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 12 })

            Divider().color(AppColors.DIVIDER)

            Row() {
              Button(this.aiPhotoUri ? '重新选择照片' : '选择测试照片')
                .fontSize(AppDimens.FONT_SM)
                .height(32)
                .backgroundColor(AppColors.PRIMARY)
                .onClick(() => { void this.pickAiPhoto() })
              if (this.aiPhotoUri) {
                Text('已选 1 张')
                  .fontSize(AppDimens.FONT_XS)
                  .fontColor(AppColors.TEXT_HINT)
                  .margin({ left: 8 })
              }
              Blank()
              Text('照片 → EXIF/OCR提取 → 构建prompt → askText（cloud off）')
                .fontSize(10)
                .fontColor(AppColors.TEXT_HINT)
                .maxLines(2)
            }
            .width('100%')
            .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 10, bottom: 10 })

            if (this.aiTestResult.length > 0) {
              Divider().color(AppColors.DIVIDER)
              Column() {
                Text(this.aiTestResult)
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(AppColors.TEXT_SECONDARY)
                if (this.aiTestDetail.length > 0) {
                  Text(this.aiTestDetail)
                    .fontSize(AppDimens.FONT_XS)
                    .fontColor(AppColors.TEXT_HINT)
                    .margin({ top: 4 })
                    .maxLines(12)
                }
              }
              .width('100%')
              .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 8 })
              .alignItems(HorizontalAlign.Start)
            }

            Divider().color(AppColors.DIVIDER)

            Button(this.aiTestRunning ? `请求中...` : '开始测试')
              .fontSize(AppDimens.FONT_MD)
              .height(44)
              .width('100%')
              .backgroundColor(this.aiTestRunning ? AppColors.TEXT_HINT : AppColors.PRIMARY)
              .fontColor(AppColors.TEXT_ON_PRIMARY)
              .margin({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, bottom: 12 })
              .enabled(!this.nodeTestRunning && !this.aiTestRunning && !this.deleteRunning)
              .onClick(() => { void this.runAiStressTest() })
          }
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_MD)

          // ═══ 清理 ═══
          this.sectionHeader('清理测试数据')
          Column() {
            if (this.deleteResult.length > 0) {
              Text(this.deleteResult)
                .fontSize(AppDimens.FONT_SM)
                .fontColor(AppColors.TEXT_SECONDARY)
                .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 8 })
                .width('100%')
            }

            Button(this.deleteRunning ? '删除中...' : '一键删除所有测试节点（perf_ 开头）')
              .fontSize(AppDimens.FONT_MD)
              .height(44)
              .width('100%')
              .backgroundColor(this.deleteRunning ? AppColors.TEXT_HINT : AppColors.DANGER)
              .fontColor(AppColors.TEXT_ON_PRIMARY)
              .margin({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 12, bottom: 12 })
              .enabled(!this.nodeTestRunning && !this.aiTestRunning && !this.deleteRunning)
              .onClick(() => { void this.deleteAllTestNodes() })
          }
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_MD)

          Column().width('100%').height(48)
        }
        .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD })
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.BACKGROUND)
  }
}
