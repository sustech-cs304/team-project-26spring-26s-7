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
export const API_BASE_URL: string = 'https://halloween-folder-unique-destination.trycloudflare.com'

/**
 * VisionLLM 服务地址
 * 演示阶段优先用公网 cloudflared 隧道（同校园网外也能跑）；
 * 域名是 quick tunnel，后端重启会换，每次演示前向后端 cc 再确认一次。
 * LAN 直连地址：http://172.18.35.215:8000（同校园网时延最低，可作备选）
 * 上架前：换成正式 HTTPS 域名 + CA 证书
 */
export const VISION_LLM_BASE_URL: string = 'https://auction-mild-shut-instrumental.trycloudflare.com'

/**
 * VisionLLM Bearer token
 * 演示用静态 token，上架前会替换为通过 AGC 登录态签发的动态 token，header 名不变
 * /health 端点不需要 token，其他端点缺/错 token 返回 401
 */
export const VISION_LLM_AUTH_TOKEN: string = 'DEV_05436de19d4ad0029b4d722b9288167b'

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

  /** 旧字段名（保留以避免破坏其他引用） */
  static readonly VERIFY: string = `/api/${API_VERSION}/share`
}

/** HTTP 请求超时配置 (毫秒) */
export class HttpTimeout {
  static readonly DEFAULT: number = 30000
  static readonly AI_GENERATE: number = 60000  // AI 生成需要更长超时
  static readonly UPLOAD: number = 120000     // 文件上传超时
}