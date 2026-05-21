import { router, promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { image } from '@kit.ImageKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppColors, AppDimens } from '../../../common'

const DOMAIN: number = 0x0000
const TAG: string = 'AvatarCropPage'
const OUTPUT_SIZE: number = 512
const OUTPUT_QUALITY: number = 90
const CROP_APPLIED_KEY: string = 'avatarCropApplied'
const CROP_PATH_KEY: string = 'avatarCropPath'

interface AvatarCropParams {
  sourcePath?: string
}

interface CropRegion {
  x: number
  y: number
  side: number
}

@Entry
@Component
export struct AvatarCropPage {
  @StorageLink('appThemeVersion') themeVersion: number = 0
  @State sourcePath: string = ''
  @State imageUri: string = ''
  @State imageWidth: number = 0
  @State imageHeight: number = 0
  @State viewportWidth: number = 0
  @State viewportHeight: number = 0
  @State cropSize: number = 260
  @State minScale: number = 1
  @State maxScale: number = 4
  @State zoomScale: number = 1
  @State offsetX: number = 0
  @State offsetY: number = 0
  @State isSaving: boolean = false

  private startOffsetX: number = 0
  private startOffsetY: number = 0
  private startZoomScale: number = 1
  private hasInitialTransform: boolean = false

  aboutToAppear(): void {
    const params = router.getParams() as AvatarCropParams
    this.sourcePath = params?.sourcePath ?? ''
    if (this.sourcePath.length === 0) {
      promptAction.showToast({ message: '头像文件无效' })
      router.back()
      return
    }

    this.imageUri = this.sourcePath.startsWith('file://') ? this.sourcePath : `file://${this.sourcePath}`
    void this.loadImageInfo()
  }

  private async loadImageInfo(): Promise<void> {
    let srcFile: fs.File | undefined
    let imageSource: image.ImageSource | undefined
    try {
      srcFile = fs.openSync(this.realPath(this.sourcePath), fs.OpenMode.READ_ONLY)
      imageSource = image.createImageSource(srcFile.fd)
      const info = await imageSource.getImageInfo()
      if (!info || !info.size || info.size.width <= 0 || info.size.height <= 0) {
        throw new Error('invalid image size')
      }
      this.imageWidth = info.size.width
      this.imageHeight = info.size.height
      this.setupInitialTransform()
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `loadImageInfo failed: ${JSON.stringify(err)}`)
      this.deleteFile(this.sourcePath)
      promptAction.showToast({ message: '头像读取失败，请重试' })
      router.back()
    } finally {
      try { imageSource?.release() } catch (_) {}
      try {
        if (srcFile) {
          fs.closeSync(srcFile)
        }
      } catch (_) {}
    }
  }

  private setupInitialTransform(): void {
    if (this.imageWidth <= 0 || this.imageHeight <= 0 || this.cropSize <= 0) {
      return
    }
    const minScale = Math.max(this.cropSize / this.imageWidth, this.cropSize / this.imageHeight)
    this.minScale = minScale
    this.maxScale = minScale * 4
    if (!this.hasInitialTransform) {
      this.zoomScale = minScale
      this.offsetX = 0
      this.offsetY = 0
      this.hasInitialTransform = true
    } else if (this.zoomScale < minScale) {
      this.zoomScale = minScale
    }
    this.clampOffset()
  }

  private updateCropArea(width: number, height: number): void {
    if (width <= 0 || height <= 0) {
      return
    }
    this.viewportWidth = width
    this.viewportHeight = height
    const side = Math.min(width, height) * 0.78
    this.cropSize = Math.max(180, Math.min(320, side))
    this.setupInitialTransform()
  }

  private clamp(value: number, min: number, max: number): number {
    return Math.max(min, Math.min(max, value))
  }

  private clampOffset(): void {
    const displayW = this.imageWidth * this.zoomScale
    const displayH = this.imageHeight * this.zoomScale
    const maxX = Math.max(0, (displayW - this.cropSize) / 2)
    const maxY = Math.max(0, (displayH - this.cropSize) / 2)
    this.offsetX = this.clamp(this.offsetX, -maxX, maxX)
    this.offsetY = this.clamp(this.offsetY, -maxY, maxY)
  }

  private updateZoomByPinch(event: GestureEvent): void {
    const previousScale = this.zoomScale
    const nextScale = this.clamp(this.startZoomScale * event.scale, this.minScale, this.maxScale)
    if (previousScale <= 0 || nextScale <= 0) {
      return
    }

    const ratio = nextScale / previousScale
    const centerX = event.pinchCenterX - this.viewportWidth / 2
    const centerY = event.pinchCenterY - this.viewportHeight / 2
    this.offsetX = centerX - (centerX - this.offsetX) * ratio
    this.offsetY = centerY - (centerY - this.offsetY) * ratio
    this.zoomScale = nextScale
    this.clampOffset()
  }

  private getDisplayWidth(): number {
    return Math.max(1, this.imageWidth * this.zoomScale)
  }

  private getDisplayHeight(): number {
    return Math.max(1, this.imageHeight * this.zoomScale)
  }

  private computeCropRegion(): CropRegion {
    const displayW = this.getDisplayWidth()
    const displayH = this.getDisplayHeight()
    const imageLeft = this.viewportWidth / 2 - displayW / 2 + this.offsetX
    const imageTop = this.viewportHeight / 2 - displayH / 2 + this.offsetY
    const cropLeft = this.viewportWidth / 2 - this.cropSize / 2
    const cropTop = this.viewportHeight / 2 - this.cropSize / 2

    let side = Math.floor(this.cropSize / this.zoomScale)
    side = Math.max(1, Math.min(side, this.imageWidth, this.imageHeight))

    let x = Math.round((cropLeft - imageLeft) / this.zoomScale)
    let y = Math.round((cropTop - imageTop) / this.zoomScale)
    x = this.clamp(x, 0, this.imageWidth - side)
    y = this.clamp(y, 0, this.imageHeight - side)

    return { x, y, side }
  }

  private async cropToFile(): Promise<string> {
    const context = getContext(this) as common.UIAbilityContext
    const dir = `${context.filesDir}/photos`
    try {
      fs.mkdirSync(dir, true)
    } catch (_) {}

    const targetPath = `${dir}/avatar_crop_${Date.now()}.jpg`
    let srcFile: fs.File | undefined
    let outFile: fs.File | undefined
    let imageSource: image.ImageSource | undefined
    let pixelMap: image.PixelMap | undefined
    let packer: image.ImagePacker | undefined

    try {
      const region = this.computeCropRegion()
      srcFile = fs.openSync(this.realPath(this.sourcePath), fs.OpenMode.READ_ONLY)
      imageSource = image.createImageSource(srcFile.fd)
      pixelMap = await imageSource.createPixelMap({
        desiredRegion: {
          x: region.x,
          y: region.y,
          size: { width: region.side, height: region.side }
        },
        desiredSize: { width: OUTPUT_SIZE, height: OUTPUT_SIZE },
        cropAndScaleStrategy: image.CropAndScaleStrategy.CROP_FIRST
      })

      packer = image.createImagePacker()
      const packed = await packer.packing(pixelMap, {
        format: 'image/jpeg',
        quality: OUTPUT_QUALITY
      })
      outFile = fs.openSync(targetPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      fs.writeSync(outFile.fd, packed)
      return targetPath
    } finally {
      try { await pixelMap?.release() } catch (_) {}
      try { await packer?.release() } catch (_) {}
      try { imageSource?.release() } catch (_) {}
      try {
        if (outFile) {
          fs.closeSync(outFile)
        }
      } catch (_) {}
      try {
        if (srcFile) {
          fs.closeSync(srcFile)
        }
      } catch (_) {}
    }
  }

  private async handleDone(): Promise<void> {
    if (this.isSaving || this.imageWidth <= 0 || this.imageHeight <= 0) {
      return
    }

    this.isSaving = true
    try {
      const croppedPath = await this.cropToFile()
      AppStorage.setOrCreate(CROP_APPLIED_KEY, true)
      AppStorage.setOrCreate(CROP_PATH_KEY, croppedPath)
      this.deleteFile(this.sourcePath)
      router.back()
    } catch (err) {
      const error = err as BusinessError
      hilog.warn(DOMAIN, TAG, `crop failed: ${error?.code ?? 'unknown'} - ${error?.message ?? error}`)
      promptAction.showToast({ message: '头像裁剪失败，请重试' })
    } finally {
      this.isSaving = false
    }
  }

  private handleCancel(): void {
    this.deleteFile(this.sourcePath)
    router.back()
  }

  private realPath(path: string): string {
    return path.startsWith('file://') ? path.substring(7) : path
  }

  private deleteFile(path: string): void {
    if (path.length === 0) {
      return
    }
    try {
      fs.unlinkSync(this.realPath(path))
    } catch (_) {}
  }

  build() {
    Column() {
      Row() {
        Text('取消')
          .fontSize(AppDimens.FONT_MD)
          .fontColor(AppColors.TEXT_PRIMARY)
          .padding(AppDimens.PADDING_MD)
          .enabled(!this.isSaving)
          .onClick(() => this.handleCancel())

        Text('裁剪头像')
          .fontSize(AppDimens.FONT_LG)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TEXT_PRIMARY)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Text(this.isSaving ? '处理中' : '完成')
          .fontSize(AppDimens.FONT_MD)
          .fontColor(this.isSaving ? AppColors.TEXT_HINT : AppColors.PRIMARY)
          .padding(AppDimens.PADDING_MD)
          .enabled(!this.isSaving)
          .onClick(() => void this.handleDone())
      }
      .width('100%')
      .height(56)
      .backgroundColor(AppColors.CARD_BG)

      Stack({ alignContent: Alignment.Center }) {
        if (this.imageUri.length > 0) {
          Image(this.imageUri)
            .width(this.getDisplayWidth())
            .height(this.getDisplayHeight())
            .objectFit(ImageFit.Fill)
            .translate({ x: this.offsetX, y: this.offsetY })
        }

        Circle()
          .width(this.cropSize)
          .height(this.cropSize)
          .fill('#00000000')
          .stroke('#FFFFFFFF')
          .strokeWidth(3)

        Circle()
          .width(this.cropSize + 8)
          .height(this.cropSize + 8)
          .fill('#00000000')
          .stroke('#66000000')
          .strokeWidth(4)
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor('#111111')
      .clip(true)
      .onAreaChange((_, value) => {
        this.updateCropArea(Number(value.width), Number(value.height))
      })
      .gesture(
        GestureGroup(
          GestureMode.Parallel,
          PanGesture()
            .onActionStart(() => {
              this.startOffsetX = this.offsetX
              this.startOffsetY = this.offsetY
            })
            .onActionUpdate((event: GestureEvent) => {
              this.offsetX = this.startOffsetX + event.offsetX
              this.offsetY = this.startOffsetY + event.offsetY
              this.clampOffset()
            }),
          PinchGesture({ fingers: 2 })
            .onActionStart(() => {
              this.startZoomScale = this.zoomScale
            })
            .onActionUpdate((event: GestureEvent) => {
              this.updateZoomByPinch(event)
            })
        )
      )

      Row() {
        Text('-')
          .fontSize(AppDimens.FONT_XL)
          .fontColor(AppColors.TEXT_SECONDARY)
          .width(32)
          .textAlign(TextAlign.Center)

        Slider({
          value: this.zoomScale,
          min: this.minScale,
          max: this.maxScale,
          step: Math.max(0.01, (this.maxScale - this.minScale) / 80)
        })
          .layoutWeight(1)
          .trackColor(AppColors.DIVIDER)
          .selectedColor(AppColors.PRIMARY)
          .blockColor(AppColors.PRIMARY)
          .onChange((value: number) => {
            this.zoomScale = value
            this.clampOffset()
          })

        Text('+')
          .fontSize(AppDimens.FONT_XL)
          .fontColor(AppColors.TEXT_SECONDARY)
          .width(32)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .height(72)
      .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD })
      .backgroundColor(AppColors.CARD_BG)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.BACKGROUND)
  }
}
