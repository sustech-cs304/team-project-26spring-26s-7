import { router, promptAction } from '@kit.ArkUI'
import { MapComponent, mapCommon, map, site } from '@kit.MapKit'
import { AsyncCallback } from '@kit.BasicServicesKit'
import { image } from '@kit.ImageKit'
import { fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import {
  AppColors,
  AppDimens,
  RouterUrls,
  getDataService,
  getDefaultMapCenter,
  getStoredPreferredMapCenter,
  hasStoredPreferredMapCenter,
  logger,
  requestCurrentLocation,
  resolveMapCenterFromNodes,
  savePreferredMapCenter,
  TravelSpecialValues
} from '../../../common'
import { MapNodeInfo, RouterParam } from '../../../common'
import type { MemoryNode } from '../../../common'

interface LoadedNodeData {
  id: string
  title: string
  poiName: string
  latitude: number
  longitude: number
  createdAt: number
  tags: string[]
  coverPhoto: string
  photoCount: number
}

interface HomeSearchResult {
  id: string
  title: string
  subtitle: string
  latitude: number
  longitude: number
  type: 'node' | 'site'
  coverPhoto?: string
}

interface SiteLike {
  name?: string
  formatAddress?: string
  location?: mapCommon.LatLng
}

interface SearchByTextResultLike {
  sites?: SiteLike[]
}

interface ReverseGeocodePoiLike {
  name?: string
}

interface ReverseGeocodeResultLike {
  addressDescription?: string
  pois?: ReverseGeocodePoiLike[]
}

const DEFAULT_MAP_CENTER: mapCommon.LatLng = getDefaultMapCenter()

const MARKER_SIZE = 360
const SINGLE_INNER_R = 107
const SINGLE_OUTER_R = 116
const CLUSTER_INNER_R = 116
const CLUSTER_OUTER_R = 125
const TIP_HEIGHT = 50

interface RgbColor {
  r: number
  g: number
  b: number
}

const MARKER_WHITE: RgbColor = { r: 0xFF, g: 0xFF, b: 0xFF }
const MARKER_BLUE_DARK: RgbColor = { r: 0x1D, g: 0x63, b: 0xB3 }
const MARKER_BLUE: RgbColor = { r: 0x4A, g: 0x90, b: 0xD9 }
const MARKER_BLUE_LIGHT: RgbColor = { r: 0x87, g: 0xC2, b: 0xFF }
const MARKER_BLUE_SOFT: RgbColor = { r: 0xDB, g: 0xEE, b: 0xFF }
const MARKER_BLUE_SURFACE: RgbColor = { r: 0xF3, g: 0xF9, b: 0xFF }

interface PhotoData {
  buffer: ArrayBuffer
  width: number
  height: number
}

interface CountBadgeMetrics {
  width: number
  height: number
  fontSize: number
  borderWidth: number
}

/**
 * 聚合图层参数 + 自定义图标绘制
 * BGRA_8888 buffer + 照片像素合成
 * 单节点 → 封面照片圆形裁剪 / 蓝色占位圆 + 白色描边
 * 聚合组 → 彩色圆形 + 白色描边
 */
class NodeClusterOverlayParams implements mapCommon.ClusterOverlayParams {
  clusterItems: mapCommon.ClusterItem[] = []
  distance: number = 50

  private nodeLookup: Map<string, LoadedNodeData[]> = new Map()
  private photoCache: Map<string, PhotoData> = new Map()
  private badgeCache: Map<string, PhotoData> = new Map()

  constructor(
    clusterItems: mapCommon.ClusterItem[],
    distance: number,
    nodeLookup: Map<string, LoadedNodeData[]>,
    photoCache: Map<string, PhotoData>
  ) {
    this.clusterItems = clusterItems
    this.distance = distance
    this.nodeLookup = nodeLookup
    this.photoCache = photoCache
  }

  async getCustomIcon(clusterItems: mapCommon.ClusterItem[]): Promise<image.PixelMap> {
    const size = MARKER_SIZE
    const buffer = new ArrayBuffer(size * size * 4)
    const view = new Uint8Array(buffer)

    if (clusterItems.length === 1) {
      // 水滴形：圆心贴顶，尖角在画布垂直中心 → 对准地图坐标
      await this.fillSingleIcon(view, size, clusterItems[0])
    } else {
      await this.fillClusterIcon(view, size, clusterItems)
    }

    return await image.createPixelMap(buffer, {
      size: { width: size, height: size },
      pixelFormat: image.PixelMapFormat.BGRA_8888
    })
  }

  // BGRA_8888 layout: view[idx]=B, [idx+1]=G, [idx+2]=R, [idx+3]=A
  // 参数语义为 R,G,B,A — 内部按 BGRA 顺序写入 buffer
  private setPixel(view: Uint8Array, idx: number, r: number, g: number, b: number, a: number): void {
    view[idx] = b
    view[idx + 1] = g
    view[idx + 2] = r
    view[idx + 3] = a
  }

  private fillCircle(view: Uint8Array, canvasW: number, canvasH: number, cx: number, cy: number,
    radius: number, color: RgbColor, alpha: number = 0xFF): void {
    const minY = Math.max(0, Math.floor(cy - radius))
    const maxY = Math.min(canvasH - 1, Math.ceil(cy + radius))
    const radiusSq = radius * radius

    for (let y = minY; y <= maxY; y++) {
      const dy = y - cy
      const maxDx = Math.sqrt(Math.max(0, radiusSq - dy * dy))
      const minX = Math.max(0, Math.floor(cx - maxDx))
      const maxX = Math.min(canvasW - 1, Math.ceil(cx + maxDx))
      for (let x = minX; x <= maxX; x++) {
        const idx = (y * canvasW + x) * 4
        this.setPixel(view, idx, color.r, color.g, color.b, alpha)
      }
    }
  }

  private fillRoundedRect(view: Uint8Array, canvasW: number, canvasH: number, left: number, top: number,
    width: number, height: number, radius: number, color: RgbColor, alpha: number = 0xFF): void {
    const safeLeft = Math.max(0, Math.floor(left))
    const safeTop = Math.max(0, Math.floor(top))
    const safeRight = Math.min(canvasW - 1, Math.ceil(left + width - 1))
    const safeBottom = Math.min(canvasH - 1, Math.ceil(top + height - 1))
    const safeRadius = Math.max(0, Math.min(radius, width / 2, height / 2))

    for (let y = safeTop; y <= safeBottom; y++) {
      for (let x = safeLeft; x <= safeRight; x++) {
        const nearestX = Math.max(left + safeRadius, Math.min(x, left + width - safeRadius - 1))
        const nearestY = Math.max(top + safeRadius, Math.min(y, top + height - safeRadius - 1))
        const dx = x - nearestX
        const dy = y - nearestY
        if (dx * dx + dy * dy <= safeRadius * safeRadius) {
          const idx = (y * canvasW + x) * 4
          this.setPixel(view, idx, color.r, color.g, color.b, alpha)
        }
      }
    }
  }

  private fillPhotoCircle(view: Uint8Array, canvasW: number, canvasH: number, cx: number, cy: number,
    radius: number, photoData: PhotoData): void {
    const photoView = new Uint8Array(photoData.buffer)
    const photoCx = photoData.width / 2
    const photoCy = photoData.height / 2
    const minY = Math.max(0, Math.floor(cy - radius))
    const maxY = Math.min(canvasH - 1, Math.ceil(cy + radius))
    const radiusSq = radius * radius

    for (let y = minY; y <= maxY; y++) {
      const dy = y - cy
      const maxDx = Math.sqrt(Math.max(0, radiusSq - dy * dy))
      const minX = Math.max(0, Math.floor(cx - maxDx))
      const maxX = Math.min(canvasW - 1, Math.ceil(cx + maxDx))
      for (let x = minX; x <= maxX; x++) {
        const dx = x - cx
        const photoX = Math.round(photoCx + dx)
        const photoY = Math.round(photoCy + dy)
        if (photoX >= 0 && photoX < photoData.width && photoY >= 0 && photoY < photoData.height) {
          const markerIdx = (y * canvasW + x) * 4
          const photoIdx = (photoY * photoData.width + photoX) * 4
          view[markerIdx] = photoView[photoIdx]
          view[markerIdx + 1] = photoView[photoIdx + 1]
          view[markerIdx + 2] = photoView[photoIdx + 2]
          view[markerIdx + 3] = 0xFF
        }
      }
    }
  }

  private fillPlaceholderCircle(view: Uint8Array, canvasW: number, canvasH: number, cx: number, cy: number,
    radius: number): void {
    this.fillCircle(view, canvasW, canvasH, cx, cy, radius, MARKER_BLUE_SURFACE)
    this.fillCircle(view, canvasW, canvasH, cx, cy, radius * 0.68, MARKER_BLUE_LIGHT)
    this.fillCircle(view, canvasW, canvasH, cx, cy, radius * 0.28, MARKER_WHITE)
    this.fillCircle(view, canvasW, canvasH, cx, cy, radius * 0.12, MARKER_BLUE_DARK)
    this.fillCircle(view, canvasW, canvasH, cx - radius * 0.36, cy - radius * 0.34, radius * 0.2, MARKER_WHITE)
  }

  private fillPhotoBubble(view: Uint8Array, canvasW: number, canvasH: number, cx: number, cy: number,
    radius: number, photoData?: PhotoData): void {
    this.fillCircle(view, canvasW, canvasH, cx, cy, radius, MARKER_WHITE)
    if (photoData) {
      this.fillPhotoCircle(view, canvasW, canvasH, cx, cy, Math.max(1, radius - 6), photoData)
    } else {
      this.fillPlaceholderCircle(view, canvasW, canvasH, cx, cy, Math.max(1, radius - 7))
    }
  }

  private isInsideRoundedRect(x: number, y: number, left: number, top: number,
    width: number, height: number, radius: number): boolean {
    const safeRadius = Math.max(0, Math.min(radius, width / 2, height / 2))
    const nearestX = Math.max(left + safeRadius, Math.min(x, left + width - safeRadius - 1))
    const nearestY = Math.max(top + safeRadius, Math.min(y, top + height - safeRadius - 1))
    const dx = x - nearestX
    const dy = y - nearestY
    return dx * dx + dy * dy <= safeRadius * safeRadius
  }

  private fillPhotoRoundedRect(view: Uint8Array, canvasW: number, canvasH: number, left: number, top: number,
    width: number, height: number, radius: number, photoData: PhotoData): void {
    const photoView = new Uint8Array(photoData.buffer)
    const safeLeft = Math.max(0, Math.floor(left))
    const safeTop = Math.max(0, Math.floor(top))
    const safeRight = Math.min(canvasW - 1, Math.ceil(left + width - 1))
    const safeBottom = Math.min(canvasH - 1, Math.ceil(top + height - 1))
    const scale = Math.max(width / photoData.width, height / photoData.height)
    const scaledWidth = photoData.width * scale
    const scaledHeight = photoData.height * scale
    const offsetX = (scaledWidth - width) / 2
    const offsetY = (scaledHeight - height) / 2

    for (let y = safeTop; y <= safeBottom; y++) {
      for (let x = safeLeft; x <= safeRight; x++) {
        if (this.isInsideRoundedRect(x, y, left, top, width, height, radius)) {
          const normalizedX = x - left
          const normalizedY = y - top
          const photoX = Math.min(photoData.width - 1, Math.max(0, Math.floor((normalizedX + offsetX) / scale)))
          const photoY = Math.min(photoData.height - 1, Math.max(0, Math.floor((normalizedY + offsetY) / scale)))
          const markerIdx = (y * canvasW + x) * 4
          const photoIdx = (photoY * photoData.width + photoX) * 4
          view[markerIdx] = photoView[photoIdx]
          view[markerIdx + 1] = photoView[photoIdx + 1]
          view[markerIdx + 2] = photoView[photoIdx + 2]
          view[markerIdx + 3] = 0xFF
        }
      }
    }
  }

  private drawBitmapPattern(view: Uint8Array, canvasW: number, canvasH: number, left: number, top: number,
    pattern: string[], scale: number, color: RgbColor): void {
    const originX = Math.round(left)
    const originY = Math.round(top)
    for (let row = 0; row < pattern.length; row++) {
      for (let column = 0; column < pattern[row].length; column++) {
        if (pattern[row][column] === '1') {
          this.fillRoundedRect(view, canvasW, canvasH, originX + column * scale, originY + row * scale,
            scale, scale, Math.max(1, scale / 3), color)
        }
      }
    }
  }

  private fillCameraPlaceholder(view: Uint8Array, canvasW: number, canvasH: number, left: number, top: number,
    width: number, height: number, radius: number): void {
    const surfaceColor: RgbColor = { r: 0xF4, g: 0xF6, b: 0xF8 }
    const accentColor: RgbColor = { r: 0x66, g: 0x72, b: 0x7F }
    const lensRingColor: RgbColor = { r: 0xD5, g: 0xDB, b: 0xE2 }

    this.fillRoundedRect(view, canvasW, canvasH, left, top, width, height, radius, surfaceColor)

    const bodyWidth = width * 0.52
    const bodyHeight = height * 0.34
    const bodyLeft = left + (width - bodyWidth) / 2
    const bodyTop = top + (height - bodyHeight) / 2 + height * 0.03
    const bodyRadius = Math.max(8, bodyHeight * 0.18)
    this.fillRoundedRect(view, canvasW, canvasH, bodyLeft, bodyTop, bodyWidth, bodyHeight, bodyRadius, accentColor)

    const bumpWidth = bodyWidth * 0.24
    const bumpHeight = bodyHeight * 0.18
    const bumpLeft = bodyLeft + bodyWidth * 0.12
    const bumpTop = bodyTop - bumpHeight * 0.7
    this.fillRoundedRect(view, canvasW, canvasH, bumpLeft, bumpTop, bumpWidth, bumpHeight,
      Math.max(4, bumpHeight / 2), accentColor)

    const lensOuterRadius = Math.max(10, Math.min(bodyWidth, bodyHeight) * 0.24)
    const lensCx = bodyLeft + bodyWidth / 2
    const lensCy = bodyTop + bodyHeight / 2
    this.fillCircle(view, canvasW, canvasH, lensCx, lensCy, lensOuterRadius, lensRingColor)
    this.fillCircle(view, canvasW, canvasH, lensCx, lensCy, lensOuterRadius * 0.58, accentColor)

    const flashRadius = Math.max(3, bodyHeight * 0.08)
    this.fillCircle(view, canvasW, canvasH, bodyLeft + bodyWidth * 0.78, bodyTop + bodyHeight * 0.28,
      flashRadius, surfaceColor)
  }

  private blendPhotoData(view: Uint8Array, canvasW: number, canvasH: number, left: number, top: number,
    photoData: PhotoData): void {
    const photoView = new Uint8Array(photoData.buffer)
    const startX = Math.max(0, Math.floor(left))
    const startY = Math.max(0, Math.floor(top))
    const endX = Math.min(canvasW, Math.ceil(left + photoData.width))
    const endY = Math.min(canvasH, Math.ceil(top + photoData.height))

    for (let y = startY; y < endY; y++) {
      for (let x = startX; x < endX; x++) {
        const srcX = x - startX
        const srcY = y - startY
        const srcIdx = (srcY * photoData.width + srcX) * 4
        const alpha = photoView[srcIdx + 3]
        if (alpha <= 0) {
          continue
        }

        const alphaRatio = alpha / 255
        const invAlpha = 1 - alphaRatio
        const destIdx = (y * canvasW + x) * 4
        view[destIdx] = Math.round(photoView[srcIdx] * alphaRatio + view[destIdx] * invAlpha)
        view[destIdx + 1] = Math.round(photoView[srcIdx + 1] * alphaRatio + view[destIdx + 1] * invAlpha)
        view[destIdx + 2] = Math.round(photoView[srcIdx + 2] * alphaRatio + view[destIdx + 2] * invAlpha)
        view[destIdx + 3] = Math.min(255, Math.round(alpha + view[destIdx + 3] * invAlpha))
      }
    }
  }

  private async createCountLabelPhotoData(label: string): Promise<PhotoData | undefined> {
    const cached = this.badgeCache.get(label)
    if (cached) {
      return cached
    }

    try {
      const metrics = this.getCountBadgeMetrics(label)
      const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${metrics.width}" height="${metrics.height}" viewBox="0 0 ${metrics.width} ${metrics.height}">
  <defs>
    <filter id="shadow" x="-30%" y="-30%" width="160%" height="160%">
      <feDropShadow dx="0" dy="4" stdDeviation="4" flood-color="#104b89" flood-opacity="0.22" />
    </filter>
  </defs>
  <rect x="0" y="0" width="${metrics.width}" height="${metrics.height}" rx="${metrics.height / 2}" ry="${metrics.height / 2}"
    fill="#FFFFFF" filter="url(#shadow)" />
  <rect x="${metrics.borderWidth}" y="${metrics.borderWidth}" width="${metrics.width - metrics.borderWidth * 2}"
    height="${metrics.height - metrics.borderWidth * 2}" rx="${(metrics.height - metrics.borderWidth * 2) / 2}"
    ry="${(metrics.height - metrics.borderWidth * 2) / 2}" fill="#1D63B3" />
  <text x="50%" y="66%" font-family="sans-serif" font-size="${metrics.fontSize}" font-weight="900"
    fill="#FFFFFF" text-anchor="middle" dominant-baseline="middle">${label}</text>
  <text x="49.2%" y="66%" font-family="sans-serif" font-size="${metrics.fontSize}" font-weight="900"
    fill="#FFFFFF" text-anchor="middle" dominant-baseline="middle">${label}</text>
  <text x="50.8%" y="66%" font-family="sans-serif" font-size="${metrics.fontSize}" font-weight="900"
    fill="#FFFFFF" text-anchor="middle" dominant-baseline="middle">${label}</text>
</svg>`
      const encoder = new util.TextEncoder()
      const source = image.createImageSource(encoder.encodeInto(svg).buffer)
      const pixelMap = await source.createPixelMap({ desiredSize: { width: metrics.width, height: metrics.height } })
      const pixelBuffer = new ArrayBuffer(pixelMap.getPixelBytesNumber())
      await pixelMap.readPixelsToBuffer(pixelBuffer)
      pixelMap.release()
      if (!this.hasVisiblePixels(pixelBuffer)) {
        return undefined
      }
      const labelData: PhotoData = { buffer: pixelBuffer, width: metrics.width, height: metrics.height }
      this.badgeCache.set(label, labelData)
      return labelData
    } catch (_) {
      logger.warn('MapHomeView', `create count label failed: ${label}`)
      return undefined
    }
  }

  private hasVisiblePixels(buffer: ArrayBuffer): boolean {
    const view = new Uint8Array(buffer)
    for (let index = 3; index < view.length; index += 4) {
      if (view[index] > 0) {
        return true
      }
    }
    return false
  }

  private getCountBadgeMetrics(label: string): CountBadgeMetrics {
    const borderWidth = 7
    const height = label.length >= 4 ? 78 : 74
    const fontSize = label.length >= 4 ? 24 : label.length >= 3 ? 28 : 34
    const estimatedTextWidth = Math.max(Math.round(fontSize * 0.72), Math.round(label.length * fontSize * 0.62))
    const horizontalPadding = label.length >= 4 ? 20 : label.length >= 3 ? 18 : 16
    const width = Math.max(height, estimatedTextWidth + horizontalPadding * 2 + borderWidth * 2)
    const metrics: CountBadgeMetrics = {
      width: width,
      height: height,
      fontSize: fontSize,
      borderWidth: borderWidth
    }
    return metrics
  }

  private async drawCountOverlay(view: Uint8Array, canvasSize: number, cardLeft: number, cardTop: number,
    cardSize: number, label: string): Promise<void> {
    if (label.length <= 0) {
      return
    }

    const labelData = await this.createCountLabelPhotoData(label)
    if (!labelData) {
      this.drawFallbackCountOverlay(view, canvasSize, cardLeft, cardTop, cardSize, label)
      return
    }

    const cornerX = cardLeft + cardSize
    const cornerY = cardTop
    const labelLeft = cornerX - labelData.width / 2
    const labelTop = Math.max(0, cornerY - labelData.height / 2)
    this.blendPhotoData(view, canvasSize, canvasSize, labelLeft, labelTop, labelData)
  }

  private drawFallbackCountOverlay(view: Uint8Array, canvasSize: number, cardLeft: number, cardTop: number,
    cardSize: number, label: string): void {
    const metrics = this.getCountBadgeMetrics(label)
    let scale = label.length >= 4 ? 4 : label.length >= 3 ? 5 : 6
    const spacing = Math.max(1, Math.floor(scale / 2))
    while (scale > 3 && this.measureBitmapText(label, scale, spacing) > metrics.width - metrics.borderWidth * 2 - 22) {
      scale -= 1
    }

    const textWidth = this.measureBitmapText(label, scale, spacing)
    const cornerX = cardLeft + cardSize
    const cornerY = cardTop
    const badgeLeft = cornerX - metrics.width / 2
    const badgeTop = Math.max(0, cornerY - metrics.height / 2)
    const textLeft = badgeLeft + (metrics.width - textWidth) / 2
    const textTop = badgeTop + (metrics.height - 7 * scale) / 2 + Math.max(2, Math.round(scale * 0.75))

    this.fillRoundedRect(view, canvasSize, canvasSize, badgeLeft, badgeTop, metrics.width, metrics.height,
      metrics.height / 2, MARKER_WHITE)
    this.fillRoundedRect(view, canvasSize, canvasSize, badgeLeft + metrics.borderWidth, badgeTop + metrics.borderWidth,
      metrics.width - metrics.borderWidth * 2, metrics.height - metrics.borderWidth * 2,
      (metrics.height - metrics.borderWidth * 2) / 2, MARKER_BLUE_DARK)
    this.drawBitmapText(view, canvasSize, canvasSize, textLeft, textTop, label, scale, spacing, MARKER_WHITE)
    this.drawBitmapText(view, canvasSize, canvasSize, textLeft + 1, textTop, label, scale, spacing, MARKER_WHITE)
  }

  private async drawMarkerCard(view: Uint8Array, canvasSize: number, photoData: PhotoData | undefined,
    countLabel: string): Promise<void> {
    const cardSize = 240
    const borderWidth = 6
    const radius = 35
    const cardLeft = Math.round((canvasSize - cardSize) / 2)
    const cardTop = Math.round((canvasSize - cardSize) / 2)
    const innerLeft = cardLeft + borderWidth
    const innerTop = cardTop + borderWidth
    const innerSize = cardSize - borderWidth * 2

    this.fillRoundedRect(view, canvasSize, canvasSize, cardLeft + 4, cardTop + 8, cardSize, cardSize, radius,
      { r: 0x00, g: 0x00, b: 0x00 }, 0x24)
    this.fillRoundedRect(view, canvasSize, canvasSize, cardLeft, cardTop, cardSize, cardSize, radius, MARKER_WHITE)

    if (photoData) {
      this.fillPhotoRoundedRect(view, canvasSize, canvasSize, innerLeft, innerTop, innerSize, innerSize, radius - 4, photoData)
    } else {
      this.fillCameraPlaceholder(view, canvasSize, canvasSize, innerLeft, innerTop, innerSize, innerSize, radius - 4)
    }

    await this.drawCountOverlay(view, canvasSize, cardLeft, cardTop, cardSize, countLabel)
  }

  private async fillSingleIcon(view: Uint8Array, canvasSize: number, item: mapCommon.ClusterItem): Promise<void> {
    const key = this.posKey(item.position.latitude, item.position.longitude)
    const nodes = this.nodeLookup.get(key)
    const targetNode = nodes && nodes.length > 0 ? nodes[0] : undefined
    const photoData = targetNode && targetNode.coverPhoto.length > 0 ? this.photoCache.get(targetNode.coverPhoto) : undefined

    await this.drawMarkerCard(view, canvasSize, photoData, '')
    return

    // 白色描边 + 尖角（只遍历内容区域 0 ~ tipY）

    if (photoData) {
      // 中心裁剪映射（cover 模式）：短边铺满圆直径，长边居中裁剪
    } else {
      // 无封面照片：蓝色填充
    }
  }

  private async fillClusterIcon(view: Uint8Array, canvasSize: number,
    clusterItems: mapCommon.ClusterItem[]): Promise<void> {
    const clusterNodes = this.resolveClusterNodes(clusterItems)
    const photoData = this.resolvePrimaryPhoto(clusterNodes)
    const count = clusterNodes.length
    await this.drawMarkerCard(view, canvasSize, photoData, count > 99 ? '99+' : `${count}`)
    return
    const size = canvasSize
    const cx = canvasSize / 2
    const cy = canvasSize / 2
    const photoEntries = this.resolveClusterPhotos(clusterNodes)

    this.fillCircle(view, size, size, cx, cy, CLUSTER_OUTER_R, MARKER_WHITE)
    this.fillCircle(view, size, size, cx, cy, CLUSTER_INNER_R, MARKER_BLUE_SOFT)
    this.fillCircle(view, size, size, cx, cy, CLUSTER_INNER_R - 12, MARKER_BLUE_SURFACE)

    if (photoEntries.length >= 3) {
      this.fillPhotoBubble(view, size, size, cx, cy - 26, 48, photoEntries[0])
      this.fillPhotoBubble(view, size, size, cx - 44, cy + 40, 42, photoEntries[1])
      this.fillPhotoBubble(view, size, size, cx + 44, cy + 40, 42, photoEntries[2])
    } else if (photoEntries.length === 2) {
      this.fillPhotoBubble(view, size, size, cx - 44, cy, 54, photoEntries[0])
      this.fillPhotoBubble(view, size, size, cx + 44, cy, 54, photoEntries[1])
    } else if (photoEntries.length === 1) {
      this.fillPhotoBubble(view, size, size, cx, cy, 74, photoEntries[0])
    } else {
      this.fillPhotoBubble(view, size, size, cx, cy - 26, 44)
      this.fillPhotoBubble(view, size, size, cx - 42, cy + 34, 38)
      this.fillPhotoBubble(view, size, size, cx + 42, cy + 34, 38)
    }

    this.drawClusterCountBadge(view, size, count)
    return
    // 目标色值按 R,G,B 定义，传给 setPixel(r,g,b,a) 内部自动转 BGRA
    let r: number = 0x4A; let g: number = 0x90; let b: number = 0xD9 // #4A90D9 蓝
    if (count >= 10) {
      r = 0xF4; g = 0x43; b = 0x36 // #F44336 红
    } else if (count >= 5) {
      r = 0xFF; g = 0x98; b = 0x00 // #FF9800 橙
    }

    for (let y = 0; y < size; y++) {
      for (let x = 0; x < size; x++) {
        const dist = Math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy))
        const idx = (y * size + x) * 4
        if (dist <= CLUSTER_INNER_R) {
          this.setPixel(view, idx, r, g, b, 0xFF)
        } else if (dist <= CLUSTER_OUTER_R) {
          this.setPixel(view, idx, 0xFF, 0xFF, 0xFF, 0xFF)
        }
      }
    }
  }

  private resolveClusterNodes(clusterItems: mapCommon.ClusterItem[]): LoadedNodeData[] {
    const nodesById: Map<string, LoadedNodeData> = new Map()
    const visitedKeys: Set<string> = new Set()
    for (const item of clusterItems) {
      const key = this.posKey(item.position.latitude, item.position.longitude)
      if (visitedKeys.has(key)) {
        continue
      }
      visitedKeys.add(key)
      const bucket = this.nodeLookup.get(key)
      if (bucket) {
        for (const node of bucket) {
          nodesById.set(node.id, node)
        }
      }
    }
    return Array.from(nodesById.values()).sort((a: LoadedNodeData, b: LoadedNodeData) => b.createdAt - a.createdAt)
  }

  private resolvePrimaryPhoto(nodes: LoadedNodeData[]): PhotoData | undefined {
    for (const node of nodes) {
      if (node.coverPhoto.length <= 0) {
        continue
      }
      const photoData = this.photoCache.get(node.coverPhoto)
      if (photoData) {
        return photoData
      }
    }
    return undefined
  }

  private resolveClusterPhotos(nodes: LoadedNodeData[]): PhotoData[] {
    const photos: PhotoData[] = []
    for (const node of nodes) {
      if (node.coverPhoto.length <= 0) {
        continue
      }
      const photoData = this.photoCache.get(node.coverPhoto)
      if (photoData) {
        photos.push(photoData)
      }
      if (photos.length >= 3) {
        break
      }
    }
    return photos
  }

  private drawClusterCountBadge(view: Uint8Array, canvasSize: number, count: number): void {
    const label = count > 99 ? '99+' : `${count}`
    const scale = label.length >= 3 ? 5 : 6
    const spacing = scale
    const textWidth = this.measureBitmapText(label, scale, spacing)
    const badgeHeight = 58
    const badgeWidth = Math.max(66, textWidth + 28)
    const left = canvasSize - badgeWidth - 26
    const top = 28

    this.fillRoundedRect(view, canvasSize, canvasSize, left, top, badgeWidth, badgeHeight, badgeHeight / 2, MARKER_WHITE)
    this.fillRoundedRect(view, canvasSize, canvasSize, left + 5, top + 5, badgeWidth - 10, badgeHeight - 10,
      (badgeHeight - 10) / 2, MARKER_BLUE_DARK)
    this.drawBitmapText(view, canvasSize, canvasSize, left + (badgeWidth - textWidth) / 2,
      top + (badgeHeight - 7 * scale) / 2, label, scale, spacing, MARKER_WHITE)
  }

  private measureBitmapText(label: string, scale: number, spacing: number): number {
    let width = 0
    for (let index = 0; index < label.length; index++) {
      width += this.getGlyphPattern(label[index])[0].length * scale
      if (index < label.length - 1) {
        width += spacing
      }
    }
    return width
  }

  private drawBitmapText(view: Uint8Array, canvasW: number, canvasH: number, left: number, top: number,
    label: string, scale: number, spacing: number, color: RgbColor): void {
    let cursorX = Math.round(left)
    const originY = Math.round(top)

    for (let index = 0; index < label.length; index++) {
      const glyph = this.getGlyphPattern(label[index])
      for (let row = 0; row < glyph.length; row++) {
        for (let column = 0; column < glyph[row].length; column++) {
          if (glyph[row][column] === '1') {
            this.fillRoundedRect(view, canvasW, canvasH, cursorX + column * scale, originY + row * scale,
              scale, scale, Math.max(1, scale / 3), color)
          }
        }
      }
      cursorX += glyph[0].length * scale + spacing
    }
  }

  private getCameraGlyphPattern(): string[] {
    return [
      '000000111111000000',
      '000011111111110000',
      '000111111111111000',
      '001111000000011100',
      '011100111111100110',
      '011001111111110011',
      '111011110000111011',
      '111011100000011011',
      '111011100000011011',
      '111011110000111011',
      '011001111111110011',
      '011100111111100110',
      '001111000000011100',
      '000111111111111000',
      '000011111111110000',
      '000000111111000000'
    ]
  }

  private getGlyphPattern(char: string): string[] {
    switch (char) {
      case '0':
        return ['11111', '10001', '10001', '10001', '10001', '10001', '11111']
      case '1':
        return ['00100', '01100', '00100', '00100', '00100', '00100', '01110']
      case '2':
        return ['11111', '00001', '00001', '11111', '10000', '10000', '11111']
      case '3':
        return ['11111', '00001', '00001', '01111', '00001', '00001', '11111']
      case '4':
        return ['10001', '10001', '10001', '11111', '00001', '00001', '00001']
      case '5':
        return ['11111', '10000', '10000', '11111', '00001', '00001', '11111']
      case '6':
        return ['11111', '10000', '10000', '11111', '10001', '10001', '11111']
      case '7':
        return ['11111', '00001', '00010', '00100', '01000', '01000', '01000']
      case '8':
        return ['11111', '10001', '10001', '11111', '10001', '10001', '11111']
      case '9':
        return ['11111', '10001', '10001', '11111', '00001', '00001', '11111']
      case '+':
        return ['00000', '00100', '00100', '11111', '00100', '00100', '00000']
      default:
        return ['00000', '00000', '00000', '00000', '00000', '00000', '00000']
    }
  }

  private posKey(lat: number, lng: number): string {
    return `${lat.toFixed(6)},${lng.toFixed(6)}`
  }
}

/**
 * 地图主页 Tab 内容视图
 * 使用 HarmonyOS Map Kit 展示真实地图 + 记忆节点 Marker
 */
@Component
export struct MapHomeView {
  @StorageLink('appThemeVersion') themeVersion: number = 0
  @State showFilter: boolean = false
  @State selectedFilterTime: string = '全部'
  @State selectedFilterTag: string = '全部'
  @State isLoadingNodes: boolean = false
  @State mapNodes: MapNodeInfo[] = []
  @State searchKeyword: string = ''
  @State searchResults: HomeSearchResult[] = []
  @State isSearching: boolean = false
  @State hasSelectedSearchResult: boolean = false
  @State selectedSearchType: string = ''
  @State selectedSearchTitle: string = ''
  @State selectedSearchSubtitle: string = ''
  @State selectedSearchLatitude: number = 0
  @State selectedSearchLongitude: number = 0
  @State isLocating: boolean = false
  @Watch('onTravelDataVersionChange')
  @StorageLink('travelDataVersion') travelDataVersion: number = 0
  @Watch('onTabRefresh')
  @StorageLink('tabRefreshToken') tabRefreshToken: number = 0
  @StorageLink('activeTabIndex') activeTabIndex: number = 0

  // 地图配置：默认中心为深圳
  private mapOptions: mapCommon.MapOptions = {
    position: {
      target: this.getInitialMapCenter(),
      zoom: 12
    }
  }

  private mapController?: map.MapComponentController
  private markerNodeIds: string[] = []
  private mapMarkers: map.Marker[] = []
  private selectedSearchMarker?: map.Marker
  private loadedNodes: LoadedNodeData[] = []
  private dataService = getDataService()
  private searchToken: number = 0

  // 聚合图层
  private clusterOverlay?: map.ClusterOverlay
  private nodeLookup: Map<string, LoadedNodeData[]> = new Map()
  private syncMarkersRunId: number = 0
  private photoCache: Map<string, PhotoData> = new Map()

  // 节点预览卡片状态
  @State previewVisible: boolean = false
  @State previewNodeId: string = ''
  @State previewTitle: string = ''
  @State previewPoi: string = ''
  @State previewPhoto: string = ''
  @State previewPhotoCount: number = 0
  @State previewTags: string[] = []

  // 聚合预览列表状态
  @State clusterPreviewVisible: boolean = false
  @State clusterPreviewNodes: LoadedNodeData[] = []

  private mapCallback: AsyncCallback<map.MapComponentController> = async (err, controller) => {
    if (!err && controller) {
      this.mapController = controller
      await this.syncMarkers()
      this.setupMapLongClickListener()
      this.applyPreferredCenter()
    }
  }

  private getInitialMapCenter(): mapCommon.LatLng {
    const preferred = getStoredPreferredMapCenter()
    return {
      latitude: preferred.latitude,
      longitude: preferred.longitude
    }
  }

  private applyPreferredCenter(): void {
    if (!this.mapController) {
      return
    }
    const preferred = getStoredPreferredMapCenter()
    const cameraUpdate = map.newCameraPosition({
      target: { latitude: preferred.latitude, longitude: preferred.longitude },
      zoom: 12
    })
    this.mapController.animateCamera(cameraUpdate, 300)
  }

  aboutToAppear(): void {
    this.loadNodes()
  }

  private onTravelDataVersionChange(): void {
    this.loadNodes()
  }

  private onTabRefresh(): void {
    if (this.activeTabIndex === 0) {
      this.loadNodes()
    }
  }

  private async loadNodes(): Promise<void> {
    this.isLoadingNodes = true
    try {
      const travels = await this.dataService.getAllTravels()
      const nodes: LoadedNodeData[] = []
      for (const travel of travels) {
        const tripNodes = await this.dataService.getNodesByTravelId(travel.id)
        for (const node of tripNodes) {
          nodes.push(this.mapNode(node))
        }
      }
      // 加载不属于任何旅行的节点
      const uncategorizedNodes = await this.dataService.getNodesByTravelId(TravelSpecialValues.UNCATEGORIZED_TRAVEL_ID)
      for (const node of uncategorizedNodes) {
        nodes.push(this.mapNode(node))
      }

      this.loadedNodes = nodes
      if (!hasStoredPreferredMapCenter()) {
        const nodeCenter = resolveMapCenterFromNodes(nodes)
        if (nodeCenter) {
          savePreferredMapCenter(nodeCenter.latitude, nodeCenter.longitude, '已有记忆', 'history')
          this.applyPreferredCenter()
        }
      }
      this.applyFilters()
      await this.syncMarkers()
    } catch (err) {
      promptAction.showToast({ message: '加载地图节点失败' })
    } finally {
      this.isLoadingNodes = false
    }
  }

  private mapNode(node: MemoryNode): LoadedNodeData {
    return {
      id: node.id,
      title: node.title,
      poiName: node.poiName,
      latitude: node.latitude,
      longitude: node.longitude,
      createdAt: node.createdAt,
      tags: node.tags,
      coverPhoto: node.photos.length > 0 ? node.photos[0] : '',
      photoCount: node.photos.length
    }
  }

  private findLoadedNodeById(nodeId: string): LoadedNodeData | undefined {
    return this.loadedNodes.find((node: LoadedNodeData) => node.id === nodeId)
  }

  private positionKey(lat: number, lng: number): string {
    return `${lat.toFixed(6)},${lng.toFixed(6)}`
  }

  private async preloadPhotos(nodes: LoadedNodeData[]): Promise<void> {
    this.releasePhotoCache()
    const diameter = 2 * SINGLE_INNER_R
    for (const node of nodes) {
      if (node.coverPhoto.length > 0 && !this.photoCache.has(node.coverPhoto)) {
        try {
          const file = fileIo.openSync(node.coverPhoto, fileIo.OpenMode.READ_ONLY)
          const stat = fileIo.statSync(node.coverPhoto)
          const buf = new ArrayBuffer(stat.size)
          fileIo.readSync(file.fd, buf)
          fileIo.closeSync(file)
          const src = image.createImageSource(buf)
          const info = await src.getImageInfo()
          const shortSide = Math.min(info.size.width, info.size.height)
          const scale = diameter / shortSide
          const targetW = Math.round(info.size.width * scale)
          const targetH = Math.round(info.size.height * scale)
          const pm = await src.createPixelMap({ desiredSize: { width: targetW, height: targetH } })
          const pixelBuf = new ArrayBuffer(pm.getPixelBytesNumber())
          await pm.readPixelsToBuffer(pixelBuf)
          pm.release()
          this.photoCache.set(node.coverPhoto, { buffer: pixelBuf, width: targetW, height: targetH })
        } catch (e) {
          logger.warn('MapHomeView', `preload photo failed: ${node.coverPhoto}`)
        }
      }
    }
  }

  private releasePhotoCache(): void {
    this.photoCache.clear()
  }

  private getSearchCenter(): mapCommon.LatLng {
    if (this.hasSelectedSearchResult) {
      return {
        latitude: this.selectedSearchLatitude,
        longitude: this.selectedSearchLongitude
      }
    }
    const preferred = getStoredPreferredMapCenter()
    if (hasStoredPreferredMapCenter()) {
      return {
        latitude: preferred.latitude,
        longitude: preferred.longitude
      }
    }
    const nodeCenter = resolveMapCenterFromNodes(this.loadedNodes)
    if (nodeCenter) {
      return nodeCenter
    }
    return DEFAULT_MAP_CENTER
  }

  private normalizeText(value: string): string {
    return value.trim().toLowerCase()
  }

  private formatLocationLabel(name: string, address: string): string {
    const trimmedName = name.trim()
    const trimmedAddress = address.trim()
    if (trimmedName.length === 0) {
      return trimmedAddress
    }
    if (trimmedAddress.length === 0) {
      return trimmedName
    }
    return `${trimmedName} · ${trimmedAddress}`
  }

  private getReverseGeocodeLabel(result: ReverseGeocodeResultLike, latitude: number, longitude: number): string {
    const firstPoi = result.pois && result.pois.length > 0 ? result.pois[0] : undefined
    if (firstPoi?.name) {
      return this.formatLocationLabel(firstPoi.name, result.addressDescription ?? '')
    }
    if (result.addressDescription && result.addressDescription.trim().length > 0) {
      return result.addressDescription
    }
    return `${latitude.toFixed(4)}, ${longitude.toFixed(4)}`
  }

  private async reverseGeocodeLocation(latitude: number, longitude: number): Promise<string> {
    try {
      const result = await site.reverseGeocode(this.getUIContext().getHostContext(), {
        location: { latitude, longitude },
        language: 'zh-CN',
        radius: 200
      }) as ReverseGeocodeResultLike
      return this.getReverseGeocodeLabel(result, latitude, longitude)
    } catch (error) {
      logger.warn('MapHomeView', `reverseGeocode failed: ${JSON.stringify(error)}`)
      return `${latitude.toFixed(4)}, ${longitude.toFixed(4)}`
    }
  }

  private formatSearchSubtitle(primary: string, secondary: string): string {
    const first = primary.trim()
    const second = secondary.trim()
    if (first.length === 0) {
      return second
    }
    if (second.length === 0) {
      return first
    }
    return `${first} · ${second}`
  }

  private matchesKeyword(node: LoadedNodeData, keyword: string): boolean {
    const haystack = `${node.title} ${node.poiName} ${node.tags.join(' ')}`.toLowerCase()
    return haystack.includes(keyword)
  }

  private buildNodeSearchResults(keyword: string): HomeSearchResult[] {
    const results: HomeSearchResult[] = []
    for (const node of this.loadedNodes) {
      if (!this.matchesKeyword(node, keyword)) {
        continue
      }
      results.push({
        id: node.id,
        title: node.title,
        subtitle: node.poiName,
        latitude: node.latitude,
        longitude: node.longitude,
        type: 'node',
        coverPhoto: node.coverPhoto
      })
      if (results.length >= 8) {
        break
      }
    }
    return results
  }

  private buildSiteSearchResult(item: SiteLike, index: number): HomeSearchResult | null {
    if (!item.location) {
      return null
    }
    const title = item.name ?? '未知地点'
    const subtitle = item.formatAddress ?? item.name ?? ''
    return {
      id: `site-${index}-${item.location.latitude}-${item.location.longitude}`,
      title,
      subtitle,
      latitude: item.location.latitude,
      longitude: item.location.longitude,
      type: 'site'
    }
  }

  private shouldShowSearchFailureToast(error: Object): boolean {
    const serialized = JSON.stringify(error)
    return !serialized.includes('1002603001')
  }

  private clearSelectedSearchState(): void {
    this.hasSelectedSearchResult = false
    this.selectedSearchType = ''
    this.selectedSearchTitle = ''
    this.selectedSearchSubtitle = ''
    this.selectedSearchLatitude = 0
    this.selectedSearchLongitude = 0
    this.previewVisible = false
    this.previewNodeId = ''
    this.previewTitle = ''
    this.previewPoi = ''
    this.previewPhoto = ''
    this.previewPhotoCount = 0
    this.previewTags = []
    this.clusterPreviewVisible = false
    this.clusterPreviewNodes = []
    if (this.selectedSearchMarker) {
      try {
        this.selectedSearchMarker.remove()
      } catch (_) {}
      this.selectedSearchMarker = undefined
    }
  }

  private async updateSelectedSearchMarker(latitude: number, longitude: number, title: string, subtitle: string): Promise<void> {
    if (!this.mapController) {
      return
    }
    if (this.selectedSearchMarker) {
      try {
        this.selectedSearchMarker.remove()
      } catch (_) {}
      this.selectedSearchMarker = undefined
    }
    const marker = await this.mapController.addMarker({
      position: { latitude, longitude },
      icon: $r('app.media.search_destination_marker'),
      rotation: 0,
      visible: true,
      zIndex: 3,
      alpha: 1,
      anchorU: 0.5,
      anchorV: 1,
      clickable: true,
      draggable: false,
      flat: false
    })
    marker.setTitle(title)
    marker.setSnippet(subtitle)
    this.selectedSearchMarker = marker
  }

  private async handleSearchInputChange(value: string): Promise<void> {
    this.searchKeyword = value
    this.clearSelectedSearchState()
    const keyword = this.normalizeText(value)
    this.searchToken += 1
    this.isSearching = false
    if (keyword.length === 0) {
      this.searchResults = []
      return
    }

    const localResults = this.buildNodeSearchResults(keyword)
    this.searchResults = localResults
    await this.searchSites(value.trim(), localResults)
  }

  private async searchSites(keyword: string, localResults: HomeSearchResult[]): Promise<void> {
    const currentToken = ++this.searchToken
    this.isSearching = true
    try {
      const result = await site.searchByText(this.getUIContext().getHostContext(), {
        query: keyword,
        location: this.getSearchCenter(),
        radius: 10000,
        language: 'zh-CN'
      }) as SearchByTextResultLike
      if (currentToken !== this.searchToken) {
        return
      }
      const merged = [...localResults]
      const sites = result.sites ?? []
      for (let index = 0; index < sites.length; index++) {
        const mapped = this.buildSiteSearchResult(sites[index], index)
        if (!mapped) {
          continue
        }
        const duplicated = merged.some((item: HomeSearchResult) =>
          Math.abs(item.latitude - mapped.latitude) < 0.0001 &&
          Math.abs(item.longitude - mapped.longitude) < 0.0001
        )
        if (!duplicated) {
          merged.push(mapped)
        }
        if (merged.length >= 8) {
          break
        }
      }
      this.searchResults = merged
    } catch (error) {
      if (currentToken !== this.searchToken) {
        return
      }
      logger.warn('MapHomeView', `searchByText failed: ${JSON.stringify(error)}`)
      this.searchResults = localResults
      if (this.shouldShowSearchFailureToast(error as Object)) {
        promptAction.showToast({ message: '地点搜索失败，请稍后重试' })
      }
    } finally {
      if (currentToken === this.searchToken) {
        this.isSearching = false
      }
    }
  }

  private navigateToCreateNodeFromSearch(): void {
    if (!this.hasSelectedSearchResult) {
      return
    }
    const latitude = this.selectedSearchLatitude
    const longitude = this.selectedSearchLongitude
    const poiName = this.selectedSearchSubtitle.length > 0
      ? this.selectedSearchSubtitle
      : this.selectedSearchTitle
    this.clearSelectedSearchState()
    this.searchKeyword = ''
    this.searchResults = []
    router.pushUrl({
      url: RouterUrls.NODE_EDIT,
      params: {
        latitude,
        longitude,
        poiName
      } as RouterParam
    })
  }

  private async selectSearchResult(item: HomeSearchResult): Promise<void> {
    this.searchKeyword = item.title
    this.searchResults = []
    this.searchToken += 1
    this.isSearching = false
    this.previewVisible = false
    this.hasSelectedSearchResult = true
    this.selectedSearchType = item.type
    this.selectedSearchTitle = item.title
    this.selectedSearchSubtitle = item.subtitle
    this.selectedSearchLatitude = item.latitude
    this.selectedSearchLongitude = item.longitude

    if (!this.mapController) {
      return
    }

    if (item.type === 'site') {
      await this.updateSelectedSearchMarker(item.latitude, item.longitude, item.title,
        item.subtitle.length > 0 ? item.subtitle : item.title)
    } else if (this.selectedSearchMarker) {
      try {
        this.selectedSearchMarker.remove()
      } catch (_) {}
      this.selectedSearchMarker = undefined
    }

    const cameraUpdate = map.newCameraPosition({
      target: { latitude: item.latitude, longitude: item.longitude },
      zoom: 15
    })
    this.mapController.animateCamera(cameraUpdate, 400)

    if (item.type === 'node') {
      this.previewNodeId = item.id
      this.previewTitle = item.title
      this.previewPoi = item.subtitle
      this.previewPhoto = item.coverPhoto ?? ''
      this.previewVisible = true
    }
  }

  private getTimeThreshold(): number {
    const now = Date.now()
    if (this.selectedFilterTime === '近 7 天') {
      return now - 7 * 24 * 60 * 60 * 1000
    }
    if (this.selectedFilterTime === '近 30 天') {
      return now - 30 * 24 * 60 * 60 * 1000
    }
    if (this.selectedFilterTime === '近一年') {
      return now - 365 * 24 * 60 * 60 * 1000
    }
    return 0
  }

  private applyFilters(): void {
    const threshold = this.getTimeThreshold()
    const filteredNodes = this.loadedNodes.filter((node: LoadedNodeData) => {
      const matchesTime = threshold === 0 || node.createdAt >= threshold
      const matchesTag = this.selectedFilterTag === '全部' || node.tags.includes(this.selectedFilterTag)
      return matchesTime && matchesTag
    })

    this.mapNodes = filteredNodes.map((node: LoadedNodeData) =>
      new MapNodeInfo(node.id, node.title, node.poiName, node.latitude, node.longitude)
    )
  }

  /** 在地图上同步记忆节点 Marker（使用 ClusterOverlay 聚合）
   *
   * 【全量同步模式】每次都移除所有旧图层后重新创建
   * 优点：简单可靠，不易产生状态不一致
   * 缺点：节点数较多时性能开销略高
   *
   * 【增量同步优化点】未来可优化为：
   * 1. 比较新旧 nodeIds 差异，仅移除消失的节点、添加新增的节点
   * 2. ClusterOverlay 支持 addItem() 单个添加，但移除需整体 remove() 后重建
   * 3. 增量模式需维护 nodeIds 与 ClusterOverlay 的映射关系
   */
  private async syncMarkers(): Promise<void> {
    if (!this.mapController) {
      return
    }
    const runId = ++this.syncMarkersRunId

    // === 清理阶段：移除所有旧图层 ===

    // 移除旧的聚合图层
    if (this.clusterOverlay) {
      try {
        await this.clusterOverlay.remove()
      } catch (_) {}
      this.clusterOverlay = undefined
    }

    // 清理旧的传统 Marker（兼容保留）
    for (const marker of this.mapMarkers) {
      try {
        marker.remove()
      } catch (_) {}
    }
    this.mapMarkers = []
    this.markerNodeIds = []

    // 清理搜索目标 Marker
    if (this.selectedSearchMarker) {
      try {
        this.selectedSearchMarker.remove()
      } catch (_) {}
      this.selectedSearchMarker = undefined
    }

    // 重置查找映射
    this.nodeLookup.clear()

    // === 构建阶段：创建新图层 ===
    await this.preloadPhotos(this.loadedNodes)
    if (runId !== this.syncMarkersRunId) {
      return
    }

    // 构建 ClusterItem 数组 + 填充 nodeLookup
    const positionCounts: Map<string, number> = new Map()
    const loadedNodeById: Map<string, LoadedNodeData> = new Map()
    for (const node of this.mapNodes) {
      const loadedNode = this.findLoadedNodeById(node.id)
      if (loadedNode) {
        loadedNodeById.set(node.id, loadedNode)
        const key = this.positionKey(node.latitude, node.longitude)
        const existing = this.nodeLookup.get(key)
        if (existing) {
          existing.push(loadedNode)
        } else {
          this.nodeLookup.set(key, [loadedNode])
        }
        positionCounts.set(key, (positionCounts.get(key) ?? 0) + 1)
      }
    }

    const sortedNodes = this.mapNodes.slice().sort((a: MapNodeInfo, b: MapNodeInfo) => {
      const aCount = positionCounts.get(this.positionKey(a.latitude, a.longitude)) ?? 1
      const bCount = positionCounts.get(this.positionKey(b.latitude, b.longitude)) ?? 1
      if (aCount !== bCount) {
        return aCount - bCount
      }
      const aCreatedAt = loadedNodeById.get(a.id)?.createdAt ?? 0
      const bCreatedAt = loadedNodeById.get(b.id)?.createdAt ?? 0
      return aCreatedAt - bCreatedAt
    })

    const clusterItems: mapCommon.ClusterItem[] = []
    for (const node of sortedNodes) {
      clusterItems.push({
        position: { latitude: node.latitude, longitude: node.longitude }
      })
    }

    // 创建聚合图层
    if (clusterItems.length > 0) {
      const params = new NodeClusterOverlayParams(clusterItems, 50, this.nodeLookup, this.photoCache)
      const overlay = await this.mapController.addClusterOverlay(params)
      if (runId !== this.syncMarkersRunId) {
        try {
          await overlay.remove()
        } catch (_) {}
        return
      }
      this.clusterOverlay = overlay
      this.setupClusterEventListeners()
    }

    // === 重建独立标记（搜索目的地，不受聚合影响） ===
    if (this.hasSelectedSearchResult && this.selectedSearchType === 'site') {
      await this.updateSelectedSearchMarker(
        this.selectedSearchLatitude,
        this.selectedSearchLongitude,
        this.selectedSearchTitle,
        this.selectedSearchSubtitle.length > 0 ? this.selectedSearchSubtitle : this.selectedSearchTitle
      )
    }
  }

  /** 监听聚合图层点击事件 */
  private setupClusterEventListeners(): void {
    if (!this.clusterOverlay) {
      return
    }

    // 单个标记点击 → 显示预览卡片
    this.clusterOverlay.on('markerClusterClick', (info: map.MarkerClusterInfo) => {
      const items = info.clusterItems
      if (items.length === 1) {
        const key = this.positionKey(items[0].position.latitude, items[0].position.longitude)
        const nodes = this.nodeLookup.get(key)
        if (nodes && nodes.length > 0) {
          const node = nodes[0]
          this.previewNodeId = node.id
          this.previewTitle = node.title
          this.previewPoi = node.poiName
          this.previewPhoto = node.coverPhoto
          this.previewPhotoCount = node.photoCount
          this.previewTags = node.tags.slice(0, 3)
          this.previewVisible = true
          this.clusterPreviewVisible = false
        }
      }
    })

    // 聚合组点击 → 显示列表 + 相机放大
    this.clusterOverlay.on('click', (items: mapCommon.ClusterItem[]) => {
      if (items.length > 1) {
        // 计算中心点
        let sumLat = 0, sumLng = 0
        for (const item of items) {
          sumLat += item.position.latitude
          sumLng += item.position.longitude
        }
        const centerLat = sumLat / items.length
        const centerLng = sumLng / items.length

        // 收集该聚合内的所有节点
        const clusterNodes = this.resolveClusterPreviewNodes(items)

        // 显示聚合预览列表
        this.previewVisible = false
        this.clusterPreviewNodes = clusterNodes
        this.clusterPreviewVisible = true

        // 相机放大 2 级
        if (this.mapController) {
          const currentCamera = this.mapController.getCameraPosition()
          const newZoom = Math.min((currentCamera.zoom ?? 12) + 2, 20)
          const cameraUpdate = map.newCameraPosition({
            target: { latitude: centerLat, longitude: centerLng },
            zoom: newZoom
          })
          this.mapController.animateCamera(cameraUpdate, 400)
        }
      }
    })
  }

  /** 监听地图长按，快捷创建节点并自动填入坐标 */
  private resolveClusterPreviewNodes(items: mapCommon.ClusterItem[]): LoadedNodeData[] {
    const nodesById: Map<string, LoadedNodeData> = new Map()
    const visitedKeys: Set<string> = new Set()

    for (const item of items) {
      const key = this.positionKey(item.position.latitude, item.position.longitude)
      if (visitedKeys.has(key)) {
        continue
      }
      visitedKeys.add(key)
      const nodes = this.nodeLookup.get(key)
      if (!nodes) {
        continue
      }
      for (const node of nodes) {
        nodesById.set(node.id, node)
      }
    }

    return Array.from(nodesById.values()).sort((a: LoadedNodeData, b: LoadedNodeData) => b.createdAt - a.createdAt)
  }

  private setupMapLongClickListener(): void {
    if (!this.mapController) {
      return
    }
    const navigateToNodeEdit = async (position: mapCommon.LatLng): Promise<void> => {
      const poiName = await this.reverseGeocodeLocation(position.latitude, position.longitude)
      router.pushUrl({
        url: RouterUrls.NODE_EDIT,
        params: {
          latitude: position.latitude,
          longitude: position.longitude,
          poiName
        } as RouterParam
      })
    }
    this.mapController.on('mapLongClick', navigateToNodeEdit)
  }

  private async recenterToCurrentLocation(): Promise<void> {
    if (!this.mapController || this.isLocating) {
      return
    }
    const hostContext = this.getUIContext().getHostContext()
    if (!hostContext) {
      promptAction.showToast({ message: '当前无法获取页面上下文' })
      return
    }
    this.isLocating = true
    try {
      const current = await requestCurrentLocation(hostContext)
      if (!current) {
        promptAction.showToast({ message: '定位失败，已保留当前地图位置' })
        return
      }
      savePreferredMapCenter(current.latitude, current.longitude, '当前位置', 'device')
      const cameraUpdate = map.newCameraPosition({
        target: { latitude: current.latitude, longitude: current.longitude },
        zoom: 14
      })
      this.mapController.animateCamera(cameraUpdate, 500)
    } finally {
      this.isLocating = false
    }
  }

  private updateFilters(timeLabel?: string, tagLabel?: string): void {
    if (timeLabel) {
      this.selectedFilterTime = timeLabel
    }
    if (tagLabel) {
      this.selectedFilterTag = tagLabel
    }
    this.applyFilters()
    this.syncMarkers()
  }

  build() {
    Stack() {
      // 真实地图组件
      MapComponent({ mapOptions: this.mapOptions, mapCallback: this.mapCallback })
        .width('100%')
        .height('100%')

      if (this.isLoadingNodes) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
          Text('正在加载地图节点...')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_HINT)
            .margin({ top: 12 })
        }
        .padding(16)
        .backgroundColor(AppColors.CARD_BG)
        .borderRadius(AppDimens.RADIUS_MD)
        .position({ x: '25%', y: '45%' })
      }

      // 搜索栏 (顶部浮动)
      Column() {
        Row() {
          TextInput({ placeholder: '搜索地点、标签...', text: this.searchKeyword })
            .layoutWeight(1)
            .height(40)
            .fontColor(AppColors.INPUT_TEXT)
            .placeholderColor(AppColors.INPUT_PLACEHOLDER)
            .caretColor(AppColors.INPUT_CARET)
            .backgroundColor(AppColors.INPUT_BG)
            .borderRadius(20)
            .padding({ left: 14, right: 14 })
            .onChange((value: string) => this.handleSearchInputChange(value))

          if (this.searchKeyword.length > 0) {
            Text('清空')
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.PRIMARY)
              .margin({ left: 10 })
              .onClick(() => this.handleSearchInputChange(''))
          }

          if (this.hasSelectedSearchResult) {
            Text('用该地址新建记忆')
              .fontSize(AppDimens.FONT_MD)
              .fontColor(AppColors.TEXT_ON_PRIMARY)
              .backgroundColor(AppColors.PRIMARY)
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .borderRadius(20)
              .margin({ left: 8 })
              .shadow({ radius: 4, color: '#1890FF33', offsetY: 2 })
              .onClick(() => this.navigateToCreateNodeFromSearch())
          }

          Text('筛选')
            .fontSize(AppDimens.FONT_MD)
            .fontColor(this.showFilter ? AppColors.TEXT_ON_PRIMARY : AppColors.PRIMARY)
            .backgroundColor(this.showFilter ? AppColors.PRIMARY : AppColors.CARD_BG)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .borderRadius(20)
            .margin({ left: 8 })
            .shadow({ radius: 4, color: '#0000001A', offsetY: 2 })
            .onClick(() => { this.showFilter = !this.showFilter })
        }
        .width('100%')

        if (this.isSearching) {
          Text('搜索中...')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_SECONDARY)
            .backgroundColor(AppColors.CARD_BG)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(AppDimens.RADIUS_SM)
            .margin({ top: 8 })
            .alignSelf(ItemAlign.Start)
        }

        if (!this.isSearching && !this.hasSelectedSearchResult && this.searchKeyword.trim().length > 0 && this.searchResults.length === 0) {
          Text('未找到相关地点或记忆')
            .fontSize(AppDimens.FONT_SM)
            .fontColor(AppColors.TEXT_SECONDARY)
            .backgroundColor(AppColors.CARD_BG)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(AppDimens.RADIUS_SM)
            .margin({ top: 8 })
            .alignSelf(ItemAlign.Start)
        }

        if (this.searchResults.length > 0) {
          Column() {
            ForEach(this.searchResults, (item: HomeSearchResult) => {
              Column() {
                Text(item.title)
                  .fontSize(AppDimens.FONT_MD)
                  .fontColor(AppColors.TEXT_PRIMARY)
                  .width('100%')
                Text(item.subtitle)
                  .fontSize(AppDimens.FONT_SM)
                  .fontColor(AppColors.TEXT_SECONDARY)
                  .width('100%')
                  .margin({ top: 4 })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .onClick(() => this.selectSearchResult(item))
            })
          }
          .width('100%')
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius(AppDimens.RADIUS_SM)
          .margin({ top: 8 })
          .shadow({ radius: 6, color: '#0000001A', offsetY: 2 })
        }
      }
      .width('100%')
      .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD, top: 8 })
      .position({ x: 0, y: 0 })

      // 筛选面板
      if (this.showFilter) {
        Column() {
          Text('时间范围')
            .fontSize(AppDimens.FONT_SM)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_PRIMARY)
          Row({ space: 8 }) {
            ForEach(['全部', '近 7 天', '近 30 天', '近一年'], (label: string) => {
              Text(label)
                .fontSize(AppDimens.FONT_SM)
                .fontColor(this.selectedFilterTime === label ? AppColors.TEXT_ON_PRIMARY : AppColors.TEXT_SECONDARY)
                .backgroundColor(this.selectedFilterTime === label ? AppColors.PRIMARY : AppColors.BACKGROUND)
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .borderRadius(14)
                .onClick(() => { this.updateFilters(label, undefined) })
            })
          }
          .margin({ top: 8 })

          Text('标签')
            .fontSize(AppDimens.FONT_SM)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.TEXT_PRIMARY)
            .margin({ top: 12 })
          Row({ space: 8 }) {
            ForEach(['全部', '旅行', '美食', '风景', '打卡'], (label: string) => {
              Text(label)
                .fontSize(AppDimens.FONT_SM)
                .fontColor(this.selectedFilterTag === label ? AppColors.TEXT_ON_PRIMARY : AppColors.TEXT_SECONDARY)
                .backgroundColor(this.selectedFilterTag === label ? AppColors.PRIMARY : AppColors.BACKGROUND)
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .borderRadius(14)
                .onClick(() => { this.updateFilters(undefined, label) })
            })
          }
          .margin({ top: 8 })
        }
        .width('100%')
        .padding(AppDimens.PADDING_MD)
        .backgroundColor(AppColors.CARD_BG)
        .borderRadius({ bottomLeft: AppDimens.RADIUS_MD, bottomRight: AppDimens.RADIUS_MD })
        .shadow({ radius: 4, color: '#0000001A', offsetY: 4 })
        .position({ x: 0, y: 56 })
        .alignItems(HorizontalAlign.Start)
      }

      // 右下角操作按钮（回到当前位置）
      Column({ space: 12 }) {
        Button() {
          Stack() {
            Text(this.isLocating ? '…' : '⌖')
              .fontSize(32)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColors.PRIMARY)
          }
          .width('100%')
          .height('100%')
          .alignContent(Alignment.Center)
        }
        .width(48)
        .height(48)
        .backgroundColor(AppColors.CARD_BG)
        .borderRadius(24)
        .padding(0)
        .enabled(!this.isLocating)
        .shadow({ radius: 4, color: '#0000001A', offsetY: 2 })
        .onClick(() => this.recenterToCurrentLocation())

        Button('+')
          .width(52)
          .height(52)
          .fontSize(24)
          .fontColor(AppColors.TEXT_ON_PRIMARY)
          .backgroundColor(AppColors.PRIMARY)
          .borderRadius(26)
          .shadow({ radius: 6, color: '#1890FF66', offsetY: 3 })
          .onClick(() => {
            router.pushUrl({ url: RouterUrls.NODE_EDIT })
          })
      }
      .position({ x: '80%', y: '60%' })

      // 底部节点预览卡片（增强版：80x80 封面 + 照片数量徽章 + 标签行）
      if (this.previewVisible) {
        Column() {
          Column()
            .width('100%')
            .layoutWeight(1)
            .onClick(() => { this.previewVisible = false })

          Row() {
            Stack() {
              if (this.previewPhoto.length > 0) {
                Image(this.previewPhoto)
                  .width('100%')
                  .height('100%')
                  .objectFit(ImageFit.Cover)
              } else {
                Column() {
                  Text('📷')
                    .fontSize(28)
                }
                .width('100%')
                .height('100%')
                .justifyContent(FlexAlign.Center)
                .backgroundColor('#5C646E')
              }
              // 照片数量徽章
              if (this.previewPhotoCount > 1) {
                Text(`${this.previewPhotoCount}张`)
                  .fontSize(10)
                  .fontColor('#FFFFFF')
                  .backgroundColor('#000000AA')
                  .padding({ left: 4, right: 4, top: 2, bottom: 2 })
                  .borderRadius(4)
                  .position({ x: 56, y: 64 })
              }
            }
            .width(80)
            .height(80)
            .backgroundColor(AppColors.BACKGROUND)
            .borderRadius(AppDimens.RADIUS_SM)
            .clip(true)

            Column() {
              Text(this.previewTitle)
                .fontSize(AppDimens.FONT_LG)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppColors.TEXT_PRIMARY)
                .width('100%')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text('📍 ' + this.previewPoi)
                .fontSize(AppDimens.FONT_SM)
                .fontColor(AppColors.TEXT_SECONDARY)
                .margin({ top: 4 })
                .width('100%')
                .maxLines(2)
              // 标签行
              if (this.previewTags.length > 0) {
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(this.previewTags.slice(0, 3), (tag: string) => {
                    Text(tag)
                      .fontSize(10)
                      .fontColor(AppColors.PRIMARY)
                      .backgroundColor('#4A90D920')
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .borderRadius(8)
                      .margin({ right: 4 })
                  })
                }
                .margin({ top: 6 })
              }
              Text('点击查看详情 >')
                .fontSize(AppDimens.FONT_SM)
                .fontColor(AppColors.PRIMARY)
                .margin({ top: 6 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 12 })
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius({ topLeft: AppDimens.RADIUS_LG, topRight: AppDimens.RADIUS_LG })
          .shadow({ radius: 8, color: '#0000001A', offsetY: -2 })
          .onClick(() => {
            this.previewVisible = false
            router.pushUrl({
              url: RouterUrls.NODE_DETAIL,
              params: { nodeId: this.previewNodeId } as RouterParam
            })
          })
        }
        .width('100%')
        .height('100%')
      }

      // 聚合展开列表（点击聚合标记后显示）
      if (this.clusterPreviewVisible) {
        Column() {
          Column()
            .width('100%')
            .layoutWeight(1)
            .onClick(() => { this.clusterPreviewVisible = false })

          Column() {
            Text(`此处有 ${this.clusterPreviewNodes.length} 个记忆节点`)
              .fontSize(AppDimens.FONT_SM)
              .fontColor(AppColors.TEXT_HINT)
              .margin({ bottom: 8 })

            Scroll() {
              Row({ space: 12 }) {
                ForEach(this.clusterPreviewNodes, (node: LoadedNodeData) => {
                  Column() {
                    Stack() {
                      if (node.coverPhoto.length > 0) {
                        Image(node.coverPhoto)
                          .width(60)
                          .height(60)
                          .objectFit(ImageFit.Cover)
                          .borderRadius(AppDimens.RADIUS_SM)
                      } else {
                        Column() {
                          Text('📷')
                            .fontSize(20)
                        }
                        .width(60)
                        .height(60)
                        .backgroundColor('#5C646E')
                        .borderRadius(AppDimens.RADIUS_SM)
                        .justifyContent(FlexAlign.Center)
                      }
                    }
                    .width(60)
                    .height(60)
                    Text(node.title)
                      .fontSize(12)
                      .fontColor(AppColors.TEXT_PRIMARY)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width(60)
                      .textAlign(TextAlign.Center)
                      .margin({ top: 4 })
                  }
                  .onClick(() => {
                    this.clusterPreviewVisible = false
                    router.pushUrl({
                      url: RouterUrls.NODE_DETAIL,
                      params: { nodeId: node.id } as RouterParam
                    })
                  })
                })
              }
              .padding({ left: AppDimens.PADDING_MD, right: AppDimens.PADDING_MD })
            }
            .scrollable(ScrollDirection.Horizontal)
            .width('100%')
            .height(100)
          }
          .width('100%')
          .padding(AppDimens.PADDING_MD)
          .backgroundColor(AppColors.CARD_BG)
          .borderRadius({ topLeft: AppDimens.RADIUS_LG, topRight: AppDimens.RADIUS_LG })
          .shadow({ radius: 8, color: '#0000001A', offsetY: -2 })
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
  }
}
