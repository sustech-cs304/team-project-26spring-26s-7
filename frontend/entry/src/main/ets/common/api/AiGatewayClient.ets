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
import { VisionLLMClient, VisionLLMRequest } from './VisionLLMClient';
import { logger } from '../utils/Logger';
import { AiCopyRequest, AiCopyResponse, AiCopyResponseData, VisualKitResult } from '../ai/PhotoMetadata';

const TAG = 'AiGatewayClient';

/** 风格名称映射（英文→中文描述，用于构建 prompt） */
const STYLE_PROMPTS: Record<string, string> = {
  'poetic': '诗意盎然、优美浪漫',
  'factual': '客观纪实、真实记录',
  'casual': '轻松随意、生活化',
  'minimal': '极简主义、言简意赅'
};

/** 长度等级→prompt 描述映射 */
const LENGTH_PROMPTS: Record<string, string> = {
  'short': '1-2句话，不超过30字，精炼概括',
  'medium': '3-5句话，约50-80字，适当展开描写',
  'long': '6-10句话，约120-200字，详细描绘场景细节和感受'
};

/**
 * 基于图片的 AI 文案生成请求
 */
export interface ImageCopyRequest {
  /** 图片沙箱路径 */
  imagePath: string;
  /** 文案风格 */
  style: string;
  /** 长度等级：short / medium / long */
  lengthLevel: string;
  /** 用户补充提示词 */
  userPrompt?: string;
  /** 地点名称（可选，从 MemoryNode 获取） */
  poiName?: string;
}

/**
 * AI Gateway 客户端
 * 负责与 VisionLLM（Qwen-VL）交互，生成旅行文案
 */
export class AiGatewayClient {
  private httpClient: HttpClient;
  private visionClient: VisionLLMClient;

  constructor() {
    this.httpClient = new HttpClient();
    this.visionClient = new VisionLLMClient();
  }

  /**
   * 基于图片生成旅行文案（核心方法）
   * 流程：将图片 + 构建好的 prompt 发送给 Qwen-VL，由模型分析图片内容并生成文案
   */
  async generateCopyFromImage(request: ImageCopyRequest): Promise<HttpResponse<AiCopyResponse>> {
    logger.info(TAG, `Generating copy from image: ${request.imagePath}`);

    try {
      const styleDesc = STYLE_PROMPTS[request.style] || request.style;
      const lengthDesc = LENGTH_PROMPTS[request.lengthLevel] || LENGTH_PROMPTS['medium'];
      const poiHint = request.poiName ? `拍摄地点是「${request.poiName}」。` : '';
      const userHint = request.userPrompt ? `用户补充说明：${request.userPrompt}。` : '';

      const question =
        `请你作为一名旅行博主，仔细观察这张照片，` +
        `${poiHint}${userHint}` +
        `用${styleDesc}的风格，写一段旅行文案。` +
        `长度要求：${lengthDesc}。` +
        `要求：生动描述照片中的场景和氛围，富有感染力，严格遵守长度要求。`;

      const visionRequest: VisionLLMRequest = {
        imagePath: request.imagePath,
        question: question,
        modelName: 'Qwen-VL-Chat-Int4',
        temperature: 0.9,
        topP: 0.85
      };

      const visionResponse = await this.visionClient.askImage(visionRequest);

      if (visionResponse.statusCode === 200 && visionResponse.data) {
        const responseData: AiCopyResponseData = {
          generated_text: visionResponse.data.content,
          alternatives: []
        };
        const aiResponse: AiCopyResponse = {
          code: 0,
          data: responseData
        };

        logger.info(TAG, 'Image copy generated successfully');
        return {
          statusCode: 200,
          data: aiResponse
        };
      } else {
        const errorMsg = visionResponse.error || `VisionLLM 返回状态码: ${visionResponse.statusCode}`;
        logger.error(TAG, errorMsg);
        return {
          statusCode: visionResponse.statusCode,
          data: undefined,
          error: errorMsg
        };
      }
    } catch (err) {
      const errorMsg = `generateCopyFromImage failed: ${JSON.stringify(err)}`;
      logger.error(TAG, errorMsg);
      return {
        statusCode: 0,
        data: undefined,
        error: errorMsg
      };
    }
  }

  /**
   * 基于文本元数据生成文案（无图片时的备选方案）
   * 将旅程元数据组装成 prompt，直接调用 VisionLLM 的文本能力
   */
  async generateCopy(request: AiCopyRequest): Promise<HttpResponse<AiCopyResponse>> {
    logger.info(TAG, 'Generating AI copy from metadata...');
    logger.debug(TAG, `Request: ${JSON.stringify(request)}`);

    // TODO: 当后端 /api/v1/ai/generate 接口就绪后，切换为：
    // return this.httpClient.post<AiCopyResponse>(
    //   AiEndpoints.GENERATE_COPY,
    //   request,
    //   HttpTimeout.AI_GENERATE
    // );

    // 当前使用模拟数据（无图片场景暂不调用 VisionLLM）
    const styleDesc = STYLE_PROMPTS[request.style] || request.style;
    const mockData: AiCopyResponseData = {
      generated_text: `[模拟 AI 文案]\n\n基于您提供的旅程信息，为您生成了${styleDesc}风格的文案（约${request.word_limit}字）。\n\n地点：${request.journey_metadata.poiList.join('、')}\n标签：${request.journey_metadata.tags.join('、')}\n\n后端文本 AI 接口就绪后将返回真实文案。`,
      alternatives: []
    };
    const mockResponse: AiCopyResponse = {
      code: 0,
      data: mockData
    };

    await new Promise<void>((resolve: () => void) => {
      setTimeout(() => resolve(), 1000);
    });

    logger.info(TAG, 'AI copy generated (metadata mock)');
    return {
      statusCode: 200,
      data: mockResponse
    };
  }

  /**
   * 内容审核
   */
  async moderateContent(text: string): Promise<HttpResponse<ModerateResponse>> {
    logger.info(TAG, 'Moderating content...');

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
 */
interface ModerateResponse {
  code: number;
  data: ModerateResponseData;
}