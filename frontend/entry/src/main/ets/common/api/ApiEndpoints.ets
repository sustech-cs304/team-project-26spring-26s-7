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