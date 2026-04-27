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

/** API 基础地址 - TODO: 替换为实际服务器地址 */
export const API_BASE_URL: string = 'https://api.example.com'

/**
 * VisionLLM 服务地址
 * 演示阶段：LAN 直连最稳，时延最低（同校园网时）
 * 备选：cloudflared quick tunnel（域名临时，进程重启就变，演示当天再确认）
 *   - https://arrested-martin-thanksgiving-jpeg.trycloudflare.com
 * 上架前：换成正式 HTTPS 域名 + CA 证书
 */
export const VISION_LLM_BASE_URL: string = 'http://172.18.35.215:8000'

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

/** 分享服务端点 */
export class ShareEndpoints {
  /** 分享链接验证: GET /api/v1/share/{travel_id} */
  static readonly VERIFY: string = `/api/${API_VERSION}/share`
}

/** HTTP 请求超时配置 (毫秒) */
export class HttpTimeout {
  static readonly DEFAULT: number = 30000
  static readonly AI_GENERATE: number = 60000  // AI 生成需要更长超时
  static readonly UPLOAD: number = 120000     // 文件上传超时
}