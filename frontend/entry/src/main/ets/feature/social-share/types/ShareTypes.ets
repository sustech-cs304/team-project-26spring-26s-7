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

/**
 * 分享系统类型定义 — 与后端 API 契约严格对齐
 * 契约文档：references/documents/social-share/分享系统 API 规范.md
 *
 * 这里只定义"对外契约"层面的类型；
 * 内部 RDB 数据 (Trip / MemoryNode) 用 common/service/types.ets 里的版本。
 */

/** POST /api/v1/share/publish 请求体中的 tripData JSON（§4.2） */
export interface SharePublishRequest {
  tripId: string
  tripName: string
  totalDistance: number
  coverIndex: number
  createdAt: number
  nodes: SharePublishNode[]
}

/** SharePublishRequest.nodes 元素（§4.2） */
export interface SharePublishNode {
  id: string
  title: string
  content: string
  poiName: string
  /** 该节点的照片数量；上传的 photo_N 按 nodeOrder 升序逐节点填充 */
  photoCount: number
  mood: string
  tags: string[]
  visitedAt: number
  nodeOrder: number
  /** 经纬度（对齐版文档新增字段，规范 §4.2 没列但后端兼容接收） */
  latitude?: number
  longitude?: number
}

/** POST /api/v1/share/publish 成功响应 data 字段（§4.4 + v0.6 sig + v0.7.1 cover） */
export interface SharePublishOk {
  /** 完整分享链接，可直接复制 / 分享 / 生成二维码 */
  url: string
  /** 8 位短码 */
  shortCode: string
  /** 过期时间 — Unix timestamp，秒级 */
  expiresAt: number
  /** 64 字符 hex 签名（与 url 里 &s= 之后的部分一致），
   *  v0.6 起从后端直接返回，避免前端再解析 URL */
  sig: string
  /** 公网可访问的封面图 URL（指向 /cache/.../0_375w.webp）。
   *  v0.7.1 新增 — 供 systemShare 把它 fetch 成 ArrayBuffer 作为 thumbnail
   *  传给 QQ / 微博等不主动抓 OG meta 的接收方。0 张照片时为 null。 */
  coverPhotoUrl?: string
}

/** 切档时撤销旧链接所需的三件套（v0.6） */
export interface ReplaceLink {
  shortCode: string
  expirySec: number
  sig: string
}

/** POST /api/v1/share/publish 完整响应（§4.4 / §4.5） */
export interface SharePublishResponse {
  code: number
  message: string
  data?: SharePublishOk
  detail?: string
}

/** GET /api/v1/share/{shortCode}/status 响应（§6.2） */
export interface ShareStatusResponse {
  code: number
  data?: ShareStatusOk
  message?: string
}

export interface ShareStatusOk {
  shortCode: string
  expiresAt: number
  remainingSeconds: number
  publishedAt: number
}

/** 错误码（§4.5） */
export interface SharePhotoIssue {
  nodeId?: string
  rawPath?: string
  reason: string
  message: string
}

export interface SharePreflightResult {
  ok: boolean
  errorCode?: string
  message?: string
  detail?: string
  totalPhotoCount: number
  totalBytes: number
  issues?: SharePhotoIssue[]
}

export class SharePreflightErrorCode {
  static readonly CLOUD_ONLY_PHOTO: string = 'CLOUD_ONLY_PHOTO'
  static readonly LOCAL_PHOTO_MISSING: string = 'LOCAL_PHOTO_MISSING'
  static readonly PHOTO_SANITIZE_FAILED: string = 'PHOTO_SANITIZE_FAILED'
}

export class ShareErrorCode {
  static readonly OK: number = 0
  static readonly INVALID_PHOTO_COUNT: number = 40001
  static readonly EMPTY_NODES: number = 40002
  static readonly TOO_MANY_NODES: number = 40003
  static readonly PHOTO_TOO_LARGE: number = 40004
  static readonly BODY_TOO_LARGE: number = 40005
  static readonly INVALID_JSON: number = 40006
  static readonly INVALID_EXPIRY: number = 40007
  static readonly RATE_LIMITED: number = 42901
  static readonly NOT_FOUND_OR_EXPIRED: number = 40401
  static readonly INTERNAL_ERROR: number = 50000
}
