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
 * API 端点常量定义
 *
 * 后端架构（2026-05-12 起）：4 个后端服务统一挂在 audit.itsmappin.top
 * 单一域名下，由华为云 ECS (139.159.143.195) 上的 nginx 做路径路由。
 * 全程 HTTPS，符合应用上架合规与 HarmonyOS 默认禁止明文 HTTP 的要求。
 *
 * 后端部署物 / 路由表：Backend_ItsMapPin/deploy/DEPLOY_HUAWEI_CLOUD.md
 */

/**
 * 统一 BASE —— ICP 主体备案已通过（粤ICP备2026065491号-1A），但华为云"接入备案"
 * 同步窗口期内 80/443 仍被 ADM 拦截；同时 itsmappin.top 仅做 APP 备案，
 * 是否能用 443 还在跟华为云客服确认。
 *
 * 因此暂时把 BASE 留在 8443 兜底（华为云不拦非标端口）。
 *
 *   当前（备案接入同步中）：'https://audit.itsmappin.top:8443'  ← 一直可用
 *   未来（443 通且政策允许后）：'https://audit.itsmappin.top'   ← 切回标准端口
 *
 * 服务端 nginx 同时在 443 + 8443 提供完整路由（mirror），两个端口任意使用。
 */
const AUDIT_BASE: string = 'https://audit.itsmappin.top:8443'

/**
 * 分享服务 base —— 与 nginx /api/* 路由对接
 * 配合后端实际端点 /api/v1/share/publish、/api/v1/share/{code}/status 等
 */
export const API_BASE_URL: string = AUDIT_BASE

/**
 * VisionLLM 服务 base —— 与 nginx /v1/* 路由对接
 *
 * 后端走 SiliconFlow Cloud relay（Qwen3.5-4B 文本 + Qwen3-VL-8B-Instruct 图片），
 * 入口保持 OpenAI 兼容协议，端点仍是 /v1/chat/completions、/v1/chat/completions/image。
 *
 * Bearer token 由 share_service /api/v1/auth/issue_ai_token 运行时下发，
 * 见 AiTokenManager.ets；不再硬编码到客户端。
 */
export const VISION_LLM_BASE_URL: string = AUDIT_BASE

/**
 * 个人资料文本审核 base
 *
 * 当前昵称/签名审核走 sensitive-check 的 /text_check，
 * 对外路径带 /censor 前缀，nginx rewrite 后转给后端。
 */
export const CONTENT_FILTER_BASE_URL: string = AUDIT_BASE + '/censor'

/**
 * 图片内容审核服务（百度智能云代理）base
 *
 * 路径带 /censor 前缀，nginx rewrite 去掉再转给后端。
 * 客户端拼出来的 URL 形如 https://audit.itsmappin.top:8443/censor/check
 */
export const IMAGE_CENSOR_BASE_URL: string = AUDIT_BASE + '/censor'

/** API 版本号 */
export const API_VERSION: string = 'v1'

/** AI Gateway 端点 */
export class AiEndpoints {
  /** 文案生成端点: POST /api/v1/ai/generate */
  static readonly GENERATE_COPY: string = `/api/${API_VERSION}/ai/generate`

  /** 内容审核端点: POST /api/v1/ai/moderate */
  static readonly MODERATE: string = `/api/${API_VERSION}/ai/moderate`
}

/** 分享服务端点（P08 API 规范 §3 + v0.8 revoke-by-trip） */
export class ShareEndpoints {
  /** 发布分享: POST /api/v1/share/publish (multipart/form-data) */
  static readonly PUBLISH: string = `/api/${API_VERSION}/share/publish`

  /** 状态查询: GET /api/v1/share/{shortCode}/status */
  static readonly STATUS_PREFIX: string = `/api/${API_VERSION}/share`

  /** Trip 改私密时关停其全部分享: POST /api/v1/share/revoke-by-trip */
  static readonly REVOKE_BY_TRIP: string = `/api/${API_VERSION}/share/revoke-by-trip`

  /** v1.1 分享海报（JPG，带 QR 跳转回 /s/{code}）: GET /share/{code}/poster.jpg?t=&s= */
  static readonly POSTER_PREFIX: string = `/share`

  /** 旧字段名（保留以避免破坏其他引用） */
  static readonly VERIFY: string = `/api/${API_VERSION}/share`
}

/** HTTP 请求超时配置 (毫秒) */
export class HttpTimeout {
  static readonly DEFAULT: number = 30000
  static readonly IMAGE_CENSOR: number = 60000
  static readonly AI_GENERATE: number = 60000  // AI 生成需要更长超时
  static readonly UPLOAD: number = 120000     // 文件上传超时
}
