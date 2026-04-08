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

import { HttpClient, HttpResponse } from './HttpClient';
import { AiEndpoints, HttpTimeout } from './ApiEndpoints';
import { logger } from '../utils/Logger';
import { AiCopyRequest, AiCopyResponse, AiCopyResponseData, VisualKitResult } from '../ai/PhotoMetadata';

const TAG = 'AiGatewayClient';

/**
 * AI Gateway 客户端
 * 负责与自建服务器 AI Gateway 交互
 *
 * TODO: 后端开发同事需要：
 * 1. 实现服务器端 /api/v1/ai/generate 接口
 * 2. 定义请求/响应的具体字段
 * 3. 配置认证方式（Bearer Token / Session）
 * 4. 实现内容审核接口 /api/v1/ai/moderate
 */
export class AiGatewayClient {
  private httpClient: HttpClient;

  constructor() {
    this.httpClient = new HttpClient();
  }

  /**
   * 生成文案
   * @param request AI 文案生成请求（包含旅程元数据 + 用户配置）
   * @returns 生成的文案响应
   *
   * TODO: 后端开发同事需要实现以下接口规范：
   * POST /api/v1/ai/generate
   * Request: AiCopyRequest (见 common/ai/PhotoMetadata.ets)
   * Response: AiCopyResponse (见 common/ai/PhotoMetadata.ets)
   */
  async generateCopy(request: AiCopyRequest): Promise<HttpResponse<AiCopyResponse>> {
    logger.info(TAG, 'Generating AI copy...');
    logger.debug(TAG, `Request: ${JSON.stringify(request)}`);

    // TODO: 当前为占位实现，返回模拟数据
    // 实际实现应为：
    // return this.httpClient.post<AiCopyResponse>(
    //   AiEndpoints.GENERATE_COPY,
    //   request,
    //   HttpTimeout.AI_GENERATE
    // );

    // 模拟响应（供前端开发测试）
    const mockData: AiCopyResponseData = {
      generated_text: `[模拟 AI 文案]\n\n基于您提供的旅程信息，为您生成了${request.style}风格的文案（约${request.word_limit}字）。\n\n地点：${request.journey_metadata.poiList.join('、')}\n标签：${request.journey_metadata.tags.join('、')}\n\n这是后端 AI 服务返回的真实文案内容占位。`,
      alternatives: [
        '方案一：简洁版文案...',
        '方案二：详细版文案...'
      ]
    };
    const mockResponse: AiCopyResponse = {
      code: 0,
      data: mockData
    };

    // 模拟网络延迟
    await new Promise<void>((resolve: () => void) => {
      setTimeout(() => resolve(), 1500);
    });

    logger.info(TAG, 'AI copy generated (mock)');
    return {
      statusCode: 200,
      data: mockResponse
    };
  }

  /**
   * 内容审核
   * @param text 待审核的文本内容
   * @returns 审核结果
   *
   * TODO: 后端开发同事需要实现内容审核接口
   */
  async moderateContent(text: string): Promise<HttpResponse<ModerateResponse>> {
    logger.info(TAG, 'Moderating content...');

    // TODO: 实际实现
    // return this.httpClient.post<ModerateResponse>(
    //   AiEndpoints.MODERATE,
    //   { text }
    // );

    // 模拟响应
    const mockData: ModerateResponseData = {
      is_safe: true,
      categories: []
    };
    const mockResponse: ModerateResponse = {
      code: 0,
      data: mockData
    };

    return {
      statusCode: 200,
      data: mockResponse
    };
  }
}

/**
 * 内容审核响应数据结构
 */
interface ModerateResponseData {
  is_safe: boolean;
  categories: string[];
}

/**
 * 内容审核响应结构
 * TODO: 后端开发同事定义具体字段
 */
interface ModerateResponse {
  code: number;
  data: ModerateResponseData;
}