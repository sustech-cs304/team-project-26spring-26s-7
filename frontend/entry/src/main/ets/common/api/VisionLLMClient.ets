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

import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { logger } from '../utils/Logger';
import { MultipartFormData, FormField, FileField } from './MultipartFormData';
import { HttpResponse } from './HttpClient';
import { VISION_LLM_BASE_URL, HttpTimeout } from './ApiEndpoints';

const TAG = 'VisionLLMClient';

/**
 * Qwen-VL API 响应中的 message 结构
 */
interface QwenMessage {
  content?: string;
}

/**
 * Qwen-VL API 响应中的 choice 结构
 */
interface QwenChoice {
  message?: QwenMessage;
}

/**
 * Qwen-VL API 响应体结构
 */
interface QwenApiResponse {
  choices?: Array<QwenChoice>;
  content?: string;
}

/**
 * 视觉 LLM 请求参数
 * 对应 backend_ai.py 的请求参数
 */
export interface VisionLLMRequest {
  /** 图片路径（沙箱路径，如 file://...） */
  imagePath: string;
  /** 问题文本 */
  question: string;
  /** 模型名称（默认：Qwen-VL-Chat-Int4） */
  modelName?: string;
  /** 温度（默认：1.0） */
  temperature?: number;
  /** top-p（默认：0.8） */
  topP?: number;
}

/**
 * 视觉 LLM 响应数据
 * 对应 Qwen-VL API 的响应格式
 */
export interface VisionLLMResponse {
  /** 生成的文本内容 */
  content: string;
  /** 原始响应（调试用） */
  raw?: Object;
}

/**
 * 视觉 LLM 客户端
 * 调用部署在服务器上的视觉 LLM（如 Qwen-VL）
 * 支持图片上传和问题提问
 */
export class VisionLLMClient {
  private baseUrl: string;
  private timeout: number;

  /**
   * 构造函数
   * @param baseUrl API 基础地址（默认取 VISION_LLM_BASE_URL 配置）
   * @param timeout 请求超时（毫秒，默认取 HttpTimeout.AI_GENERATE）
   */
  constructor(baseUrl: string = VISION_LLM_BASE_URL, timeout: number = HttpTimeout.AI_GENERATE) {
    this.baseUrl = baseUrl;
    this.timeout = timeout;
  }

  /**
   * 发送图片和问题到视觉 LLM
   * @param request 视觉 LLM 请求
   * @returns 生成的文本响应
   */
  async askImage(request: VisionLLMRequest): Promise<HttpResponse<VisionLLMResponse>> {
    logger.info(TAG, 'Sending image to vision LLM...');
    logger.debug(TAG, `Request: ${JSON.stringify(request)}`);

    const httpRequest = http.createHttp();

    try {
      // 构建 multipart/form-data
      const formData = new MultipartFormData();

      // 添加文件字段
      const filename = this.extractFilename(request.imagePath);
      formData.addFile('image', filename, request.imagePath, 'application/octet-stream');

      // 添加文本字段
      formData.addField('model_name', request.modelName || 'Qwen-VL-Chat-Int4');
      formData.addField('question', request.question);
      formData.addField('temperature', (request.temperature ?? 1.0).toString());
      formData.addField('top_p', (request.topP ?? 0.8).toString());

      // 构建请求体
      const requestBody = await formData.build();

      // 构建完整 URL
      const endpoint = '/v1/chat/completions/image';
      const url = `${this.baseUrl}${endpoint}`;

      logger.info(TAG, `Sending POST request to: ${url}`);

      // 请求配置
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': formData.getContentType()
        },
        readTimeout: this.timeout,
        connectTimeout: this.timeout,
        expectDataType: http.HttpDataType.OBJECT,
        extraData: requestBody
      };

      // 发送请求
      const response = await httpRequest.request(url, options);

      logger.info(TAG, `Response status: ${response.responseCode}`);

      // 处理响应
      if (response.responseCode === 200 || response.responseCode === 201) {
        const result = response.result as Object;
        logger.debug(TAG, `Response raw: ${JSON.stringify(result)}`);

        // 提取文本内容（Qwen-VL 响应格式）
        const content = this.extractContent(result);

        const visionResponse: VisionLLMResponse = {
          content,
          raw: result
        };

        return {
          statusCode: response.responseCode,
          data: visionResponse
        };
      } else {
        const errorMsg = `HTTP ${response.responseCode}: ${JSON.stringify(response.result)}`;
        logger.error(TAG, errorMsg);
        return {
          statusCode: response.responseCode,
          data: undefined,
          error: errorMsg
        };
      }
    } catch (err) {
      const error = err as BusinessError;
      const errorMsg = `Request failed: ${error.message}`;
      logger.error(TAG, errorMsg);
      return {
        statusCode: 0,
        data: undefined,
        error: errorMsg
      };
    } finally {
      httpRequest.destroy();
    }
  }

  /**
   * 从图片路径中提取文件名
   */
  private extractFilename(imagePath: string): string {
    // 移除 file:// 前缀
    const realPath = imagePath.startsWith('file://') ? imagePath.substring(7) : imagePath;
    // 获取文件名部分
    const lastSlash = realPath.lastIndexOf('/');
    return lastSlash >= 0 ? realPath.substring(lastSlash + 1) : realPath;
  }

  /**
   * 从 API 响应中提取文本内容
   * 支持 Qwen-VL 响应格式：choices[0].message.content
   */
  private extractContent(response: Object): string {
    try {
      // 类型断言
      const resp = response as QwenApiResponse;

      if (resp.choices && Array.isArray(resp.choices) && resp.choices.length > 0) {
        const choice = resp.choices[0];
        if (choice.message && choice.message.content) {
          return choice.message.content;
        }
      }

      // 备用提取方法
      if (resp.content) {
        return resp.content;
      }

      // 如果无法提取，返回整个响应字符串
      logger.warn(TAG, 'Could not extract content from response, returning raw string');
      return JSON.stringify(response, null, 2);
    } catch (err) {
      logger.error(TAG, `extractContent failed: ${err}`);
      return 'Failed to extract content from response';
    }
  }

  /**
   * 测试连接
   * @returns 连接是否成功
   */
  async testConnection(): Promise<boolean> {
    try {
      const httpRequest = http.createHttp();
      const url = `${this.baseUrl}/health`; // 假设有健康检查端点

      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        readTimeout: 10000,
        connectTimeout: 10000,
        expectDataType: http.HttpDataType.OBJECT
      };

      const response = await httpRequest.request(url, options);
      httpRequest.destroy();

      return response.responseCode === 200;
    } catch {
      return false;
    }
  }
}