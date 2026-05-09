/*
 * Copyright (c) 2024 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { http } from '@kit.NetworkKit'
import { BusinessError } from '@kit.BasicServicesKit'
import {
  API_BASE_URL,
  HttpTimeout,
  MultipartFormData,
  ShareEndpoints,
} from '../../../common/api'
import { logger } from '../../../common/utils/Logger'
import {
  ReplaceLink,
  ReplayPrefsForShare,
  RevokeByTripOk,
  SharePublishOk,
  SharePublishRequest,
  SharePublishResponse,
  ShareStatusOk,
  ShareStatusResponse,
} from '../types/ShareTypes'

const TAG = 'ShareService'

/**
 * 单张待上传照片描述 — name 在 multipart 里固定为 photo_{flatIdx}，
 * 调用方按节点顺序整理好 photoPaths 后传进来即可。
 */
export interface SharePhoto {
  /** 沙箱绝对路径（不带 file:// 前缀） */
  filePath: string
  /** 文件名（用于 multipart Content-Disposition.filename） */
  filename: string
  /** MIME 类型；JPEG/PNG/HEIC 等 */
  contentType: string
  cleanupPath?: string
}

/**
 * 分享服务客户端 — 封装 P08 API 规范的 publish / status 两个端点。
 *
 * 用法：
 * ```ts
 * const svc = new ShareService();
 * const result = await svc.publish(tripData, photos, 168);
 * if (result.ok) {
 *   console.log(result.data.url);
 * } else {
 *   console.error(result.errorMessage);
 * }
 * ```
 */
export class ShareService {
  private baseUrl: string
  private timeout: number

  constructor(baseUrl: string = API_BASE_URL, timeout: number = HttpTimeout.UPLOAD) {
    this.baseUrl = baseUrl
    this.timeout = timeout
  }

  /**
   * 发布分享 — 调用 POST /api/v1/share/publish
   *
   * @param trip            trip 元数据 + 节点数组（含每节点 photoCount）
   * @param photos          按 nodeOrder 升序、每节点内按 photoIdx 顺序整理好的扁平照片列表
   *                        总数必须等于 sum(nodes[].photoCount)，否则后端返回 40001
   * @param expiryHours     过期小时数；默认 168 (7 天)，范围 1–720
   * @param expiryMinutes   可选，过期分钟数；当传入且 > 0 时**优先级高于** expiryHours
   *                        （供 SharePage 的"5 分钟测试"选项使用，最低 1 分钟）
   * @param replace         可选，要随本次发布**自动撤销**的旧链接三件套
   *                        (shortCode + expirySec + sig)。后端会校验 sig 后
   *                        在新发布**成功之后**才删除旧的；新失败旧保留。
   * @param replayPrefs     可选（v1.0），把当前用户的回放偏好顺路上传，让生成
   *                        的 /sreplay 页面与发布者本机的回放设置视觉一致。
   *                        缺哪个字段后端就用哪个的 default；不传整个对象 →
   *                        DB 存 NULL，viewer 走全局默认（极简白 + city_lights_lofi 等）。
   */
  async publish(
    trip: SharePublishRequest,
    photos: SharePhoto[],
    expiryHours: number = 168,
    expiryMinutes?: number,
    replace?: ReplaceLink,
    replayPrefs?: ReplayPrefsForShare
  ): Promise<ShareCallResult<SharePublishOk>> {
    // 客户端先做一遍 photoCount 校验，避免无谓的上传
    let expectedTotal = 0
    for (let i = 0; i < trip.nodes.length; i++) {
      expectedTotal += trip.nodes[i].photoCount
    }
    if (expectedTotal !== photos.length) {
      const msg =
        `photoCount sum (${expectedTotal}) != photos.length (${photos.length})`
      logger.error(TAG, msg)
      return errResult(40001, 'INVALID_PHOTO_COUNT', msg)
    }

    const form = new MultipartFormData()
    // §4.2 — tripData 作为文本字段（JSON 字符串）
    form.addField('tripData', JSON.stringify(trip))
    // §4.1 — 过期时长。expiryMinutes 优先于 expiryHours（与后端约定一致）
    if (expiryMinutes !== undefined && expiryMinutes > 0) {
      form.addField('expiryMinutes', expiryMinutes.toString())
    } else {
      form.addField('expiryHours', expiryHours.toString())
    }
    // v0.6 — 替换上一条链接（"切档自动撤销旧链接"）
    if (replace !== undefined && replace.shortCode) {
      form.addField('replaceShortCode', replace.shortCode)
      form.addField('replaceExpiry',    replace.expirySec.toString())
      form.addField('replaceSig',       replace.sig)
    }
    // v1.0 — 回放偏好（6 个字段全部可选；后端按字段 fallback）
    if (replayPrefs !== undefined) {
      if (replayPrefs.styleKitId !== undefined) {
        form.addField('replayStyleKitId', replayPrefs.styleKitId)
      }
      if (replayPrefs.bgmId !== undefined) {
        form.addField('replayBgmId', replayPrefs.bgmId)
      }
      if (replayPrefs.filterId !== undefined) {
        form.addField('replayFilterId', replayPrefs.filterId)
      }
      if (replayPrefs.transitionType !== undefined) {
        form.addField('replayTransitionType', replayPrefs.transitionType)
      }
      if (replayPrefs.enableBlurOverlay !== undefined) {
        form.addField('replayEnableBlurOverlay',
          replayPrefs.enableBlurOverlay ? 'true' : 'false')
      }
      if (replayPrefs.enableRouteAnimation !== undefined) {
        form.addField('replayEnableRouteAnimation',
          replayPrefs.enableRouteAnimation ? 'true' : 'false')
      }
    }
    // §4.1 + §4.3 — photo_N 作为文件字段，按 N 从 0 起连续
    for (let i = 0; i < photos.length; i++) {
      const p = photos[i]
      form.addFile(`photo_${i}`, p.filename, p.filePath, p.contentType)
    }

    const url = `${this.baseUrl}${ShareEndpoints.PUBLISH}`
    logger.info(TAG, `POST ${url} (${photos.length} photos, ${trip.nodes.length} nodes)`)

    const httpReq = http.createHttp()
    try {
      const body = await form.build()
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': form.getContentType() },
        readTimeout: this.timeout,
        connectTimeout: this.timeout,
        expectDataType: http.HttpDataType.OBJECT,
        extraData: body,
      }
      const resp = await httpReq.request(url, options)
      logger.info(TAG, `Response status: ${resp.responseCode}`)

      const parsed = parseEnvelope<SharePublishOk>(resp.result)
      if (resp.responseCode === 201 && parsed.code === 0 && parsed.data) {
        return okResult(parsed.data)
      }
      // 错误：尽量带回后端的 message + detail，便于 UI 展示
      const errMsg = parsed.message || `HTTP ${resp.responseCode}`
      const errDetail = parsed.detail || JSON.stringify(resp.result)
      logger.error(TAG, `publish failed: ${errMsg} — ${errDetail}`)
      return errResult(parsed.code || resp.responseCode, errMsg, errDetail)
    } catch (e) {
      const be = e as BusinessError
      const msg = `Network error: ${be?.message ?? JSON.stringify(e)}`
      logger.error(TAG, msg)
      return errResult(0, 'NETWORK_ERROR', msg)
    } finally {
      httpReq.destroy()
    }
  }

  /**
   * 查询分享状态 — 调用 GET /api/v1/share/{shortCode}/status (§6)
   */
  async status(shortCode: string): Promise<ShareCallResult<ShareStatusOk>> {
    const url = `${this.baseUrl}${ShareEndpoints.STATUS_PREFIX}/${shortCode}/status`
    logger.info(TAG, `GET ${url}`)

    const httpReq = http.createHttp()
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        readTimeout: HttpTimeout.DEFAULT,
        connectTimeout: HttpTimeout.DEFAULT,
        expectDataType: http.HttpDataType.OBJECT,
      }
      const resp = await httpReq.request(url, options)
      const parsed = parseEnvelope<ShareStatusOk>(resp.result)
      if (parsed.code === 0 && parsed.data) {
        return okResult(parsed.data)
      }
      return errResult(parsed.code, parsed.message ?? 'NOT_FOUND_OR_EXPIRED')
    } catch (e) {
      const be = e as BusinessError
      return errResult(0, 'NETWORK_ERROR', be?.message ?? JSON.stringify(e))
    } finally {
      httpReq.destroy()
    }
  }

  /**
   * 关停某 trip 的全部分享 — 当用户把 trip 从公开切换到私密时调用。
   * 调用 POST /api/v1/share/revoke-by-trip (v0.8)。
   *
   * 失败处理：网络错误等不该阻塞 trip 保存本身（隐私设置已经在 RDB 写好），
   * 调用方应该 fire-and-forget 这个调用，最多 log 一行警告。
   *
   * @param tripId  本地 RDB 里 Trip.id（与 publish 时上传的 tripData.tripId 一致）
   * @returns       后端实际撤销的链接条数（0 = 这个 trip 没分享或已都失活）
   */
  async revokeByTrip(tripId: string): Promise<ShareCallResult<RevokeByTripOk>> {
    const url = `${this.baseUrl}${ShareEndpoints.REVOKE_BY_TRIP}`
    logger.info(TAG, `POST ${url} tripId=${tripId}`)

    const httpReq = http.createHttp()
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json' },
        readTimeout: HttpTimeout.DEFAULT,
        connectTimeout: HttpTimeout.DEFAULT,
        expectDataType: http.HttpDataType.OBJECT,
        extraData: JSON.stringify({ tripId }),
      }
      const resp = await httpReq.request(url, options)
      const parsed = parseEnvelope<RevokeByTripOk>(resp.result)
      if (resp.responseCode === 200 && parsed.code === 0 && parsed.data) {
        logger.info(TAG, `revoked ${parsed.data.revokedCount} shares for trip=${tripId}`)
        return okResult(parsed.data)
      }
      const errMsg = parsed.message || `HTTP ${resp.responseCode}`
      logger.warn(TAG, `revokeByTrip failed: ${errMsg}`)
      return errResult(parsed.code || resp.responseCode, errMsg, parsed.detail)
    } catch (e) {
      const be = e as BusinessError
      const msg = `Network error: ${be?.message ?? JSON.stringify(e)}`
      logger.warn(TAG, msg)
      return errResult(0, 'NETWORK_ERROR', msg)
    } finally {
      httpReq.destroy()
    }
  }
}

// ========== 内部工具：响应包络解析 + Result 类型 ==========

/**
 * 调用结果 — discriminated union 风格的 Result。
 * 用 ok 字段判别，TypeScript 能在 ok=true 分支里收窄到有 data。
 */
export interface ShareCallResult<T> {
  ok: boolean
  data?: T
  errorCode?: number
  errorMessage?: string
  errorDetail?: string
}

function okResult<T>(data: T): ShareCallResult<T> {
  return { ok: true, data }
}

function errResult<T>(code: number, message: string, detail?: string): ShareCallResult<T> {
  return { ok: false, errorCode: code, errorMessage: message, errorDetail: detail }
}

interface Envelope<T> {
  code: number
  message?: string
  data?: T
  detail?: string
}

/**
 * 后端响应一律是 {code, message, data?, detail?} 信封。
 * 这里把 unknown 转成强类型；解析失败时返回 50000 INTERNAL_ERROR。
 */
function parseEnvelope<T>(raw: Object | string | ArrayBuffer | undefined): Envelope<T> {
  if (raw === undefined || raw === null) {
    return { code: 50000, message: 'EMPTY_RESPONSE' }
  }
  let obj: Object
  if (typeof raw === 'string') {
    try {
      obj = JSON.parse(raw) as Object
    } catch (e) {
      return { code: 50000, message: 'INVALID_JSON_RESPONSE' }
    }
  } else {
    obj = raw as Object
  }
  // ArkTS 不支持 `as` 收窄到任意接口，手动取字段
  const r = obj as Record<string, Object>
  return {
    code: typeof r['code'] === 'number' ? r['code'] as number : 50000,
    message: typeof r['message'] === 'string' ? r['message'] as string : undefined,
    data: r['data'] as T | undefined,
    detail: typeof r['detail'] === 'string' ? r['detail'] as string : undefined,
  }
}
