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
 * TODO: 后端开发同事需配置实际服务器地址
 */

/**
 * API 基础地址 — 自建分享服务（FastAPI + cloudflared 临时隧道）
 *
 * 隧道说明：trycloudflare 免费域名，进程不死域名稳定，重启进程会换域名。
 * 上线后替换为正式 https 域名（如 https://share.travelpin.app）。
 *
 * 后端实现路径：/data2/cse12310817/backend/share_service/
 * 后端契约文档：references/documents/social-share/分享系统 API 规范.md
 */
export const API_BASE_URL: string = 'https://surprise-seekers-toxic-applies.trycloudflare.com'

/**
 * VisionLLM 服务地址
 * 上架前：换成正式 HTTPS 域名 + CA 证书
 *
 * 2026-05-10 起后端切到 SiliconFlow Cloud（Qwen3.5-4B 文本 + Qwen3-VL-8B-Instruct 图片），
 * 入口仍是 OpenAI 兼容协议、同一组端点，客户端无需协议改动。
 * 隧道是 cloudflared quick tunnel；进程不死域名稳定，重启会换域名（同 share_service 同上注释）。
 */
export const VISION_LLM_BASE_URL: string = 'https://dryer-declined-resistance-liability.trycloudflare.com'

/**
 * VisionLLM Bearer token（已迁移到 AiTokenManager 运行时申领，见 Tier 2.2）
 * 上架包不再硬编码，通过 share_service /api/v1/auth/issue_ai_token 下发
 * /health 端点不需要 token，其他端点缺/错 token 返回 401
 */

/**
 * 敏感词过滤服务
 * TODO(release): 上架前替换为正式 HTTPS 域名（HarmonyOS 默认禁止明文 HTTP）
 */
export const CONTENT_FILTER_BASE_URL: string = 'http://172.18.35.215:9100'

/**
 * 图片内容审核服务（百度智能云代理）
 * TODO(release): 上架前替换为正式 HTTPS 域名
 */
export const IMAGE_CENSOR_BASE_URL: string = 'http://172.18.35.215:9200'

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
  static readonly AI_GENERATE: number = 60000  // AI 生成需要更长超时
  static readonly UPLOAD: number = 120000     // 文件上传超时
}