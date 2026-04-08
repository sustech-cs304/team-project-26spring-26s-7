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
import { logger } from '../utils/Logger';
import { API_BASE_URL, HttpTimeout } from './ApiEndpoints';

const TAG = 'HttpClient';

/**
 * HTTP 响应结构
 */
export interface HttpResponse<T> {
  /** HTTP 状态码 */
  statusCode: number;
  /** 响应数据 */
  data: T | undefined;
  /** 错误信息 */
  error?: string;
}

/**
 * HTTP 客户端基础封装
 * 提供统一的请求发送和错误处理
 */
export class HttpClient {
  private baseUrl: string;

  constructor(baseUrl: string = API_BASE_URL) {
    this.baseUrl = baseUrl;
  }

  /**
   * 发送 GET 请求
   * @param endpoint API 端点路径
   * @param params 查询参数
   * @param timeout 超时时间 (毫秒)
   */
  async get<T>(
    endpoint: string,
    params?: Record<string, string | number>,
    timeout: number = HttpTimeout.DEFAULT
  ): Promise<HttpResponse<T>> {
    return this.request<T>('GET', endpoint, undefined, params, timeout);
  }

  /**
   * 发送 POST 请求
   * @param endpoint API 端点路径
   * @param body 请求体
   * @param timeout 超时时间 (毫秒)
   */
  async post<T>(
    endpoint: string,
    body: Object | undefined,
    timeout: number = HttpTimeout.DEFAULT
  ): Promise<HttpResponse<T>> {
    return this.request<T>('POST', endpoint, body, undefined, timeout);
  }

  /**
   * 发送 HTTP 请求
   * TODO: 后端开发同事可能需要添加认证 Token、签名等
   */
  private async request<T>(
    method: http.RequestMethod,
    endpoint: string,
    body: Object | undefined,
    params?: Record<string, string | number>,
    timeout: number = HttpTimeout.DEFAULT
  ): Promise<HttpResponse<T>> {
    const httpRequest = http.createHttp();

    try {
      // 构建完整 URL
      let url = `${this.baseUrl}${endpoint}`;
      if (params && Object.keys(params).length > 0) {
        // ArkTS 不支持解构赋值，使用传统方式构建查询字符串
        const keys = Object.keys(params);
        const queryParts: string[] = [];
        for (let i = 0; i < keys.length; i++) {
          const key = keys[i];
          const value = params[key];
          queryParts.push(`${key}=${encodeURIComponent(String(value))}`);
        }
        const queryString = queryParts.join('&');
        url = `${url}?${queryString}`;
      }

      logger.info(TAG, `Sending ${method} request to: ${url}`);

      // 请求配置
      const options: http.HttpRequestOptions = {
        method: method,
        header: {
          'Content-Type': 'application/json'
          // TODO: 添加认证 Token
          // 'Authorization': `Bearer ${token}`
        },
        readTimeout: timeout,
        connectTimeout: timeout,
        expectDataType: http.HttpDataType.OBJECT
      };

      // 添加请求体
      if (body) {
        options.extraData = JSON.stringify(body);
        logger.debug(TAG, `Request body: ${JSON.stringify(body)}`);
      }

      const response = await httpRequest.request(url, options);

      logger.info(TAG, `Response status: ${response.responseCode}`);

      // 处理响应
      if (response.responseCode === 200 || response.responseCode === 201) {
        const result = response.result as T;
        return {
          statusCode: response.responseCode,
          data: result
        };
      } else {
        const errorMsg = `HTTP ${response.responseCode}: ${response.result}`;
        logger.error(TAG, errorMsg);
        return {
          statusCode: response.responseCode,
          data: undefined,
          error: errorMsg
        };
      }
    } catch (err) {
      const errorMsg = `Request failed: ${JSON.stringify(err)}`;
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
}