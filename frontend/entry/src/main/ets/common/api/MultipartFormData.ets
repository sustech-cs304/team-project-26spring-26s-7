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

import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { logger } from '../utils/Logger';

const TAG = 'MultipartFormData';

/**
 * Multipart/form-data 表单字段
 */
export interface FormField {
  name: string;
  value: string;
}

/**
 * Multipart/form-data 文件字段
 */
export interface FileField {
  name: string;
  filename: string;
  filePath: string;
  contentType?: string;
}

/**
 * Multipart/form-data 构建器
 * 支持文本字段和文件字段
 */
export class MultipartFormData {
  private boundary: string;
  private fields: FormField[];
  private files: FileField[];

  constructor() {
    // 生成随机边界字符串
    this.boundary = `----WebKitFormBoundary${Date.now().toString(16)}`;
    this.fields = [];
    this.files = [];
  }

  /**
   * 添加文本字段
   */
  addField(name: string, value: string): void {
    this.fields.push({ name, value });
  }

  /**
   * 添加文件字段
   */
  addFile(name: string, filename: string, filePath: string, contentType: string = 'application/octet-stream'): void {
    this.files.push({ name, filename, filePath, contentType });
  }

  /**
   * 获取 Content-Type 头部值（包含边界）
   */
  getContentType(): string {
    return `multipart/form-data; boundary=${this.boundary}`;
  }

  /**
   * 构建完整的 multipart 请求体
   * @returns ArrayBuffer 格式的请求体
   */
  async build(): Promise<ArrayBuffer> {
    try {
      // 收集所有部分
      const parts: ArrayBuffer[] = [];

      // 添加文本字段
      for (const field of this.fields) {
        const part = this.buildFieldPart(field.name, field.value);
        parts.push(part);
      }

      // 添加文件字段
      for (const file of this.files) {
        const contentType = file.contentType || 'application/octet-stream';
        const part = await this.buildFilePart(file.name, file.filename, file.filePath, contentType);
        parts.push(part);
      }

      // 添加结束边界
      const footer = this.stringToArrayBuffer(`--${this.boundary}--\r\n`);
      parts.push(footer);

      // 合并所有部分
      return this.concatArrayBuffers(parts);
    } catch (err) {
      const errorMsg = `build multipart failed: ${err}`;
      logger.error(TAG, errorMsg);
      throw new Error(errorMsg);
    }
  }

  /**
   * 构建文本字段部分
   */
  private buildFieldPart(name: string, value: string): ArrayBuffer {
    const content = `--${this.boundary}\r\n` +
      `Content-Disposition: form-data; name="${name}"\r\n\r\n` +
      `${value}\r\n`;
    return this.stringToArrayBuffer(content);
  }

  /**
   * 构建文件字段部分
   */
  private async buildFilePart(name: string, filename: string, filePath: string, contentType: string): Promise<ArrayBuffer> {
    try {
      // 读取文件内容
      const fileContent = await this.readFileAsArrayBuffer(filePath);

      // 构建头部
      const header = `--${this.boundary}\r\n` +
        `Content-Disposition: form-data; name="${name}"; filename="${filename}"\r\n` +
        `Content-Type: ${contentType}\r\n\r\n`;

      const headerBuffer = this.stringToArrayBuffer(header);

      // 构建尾部换行
      const footer = this.stringToArrayBuffer('\r\n');

      // 合并头部、文件内容和尾部
      return this.concatArrayBuffers([headerBuffer, fileContent, footer]);
    } catch (err) {
      const errorMsg = `buildFilePart failed: ${err}`;
      logger.error(TAG, errorMsg);
      throw new Error(errorMsg);
    }
  }

  /**
   * 将字符串转换为 ArrayBuffer
   */
  private stringToArrayBuffer(str: string): ArrayBuffer {
    const encoder = new util.TextEncoder();
    const result = encoder.encodeInto(str);
    return result.buffer;
  }

  /**
   * 读取文件为 ArrayBuffer
   */
  private async readFileAsArrayBuffer(filePath: string): Promise<ArrayBuffer> {
    try {
      // 移除 file:// 前缀（如果有）
      const realPath = filePath.startsWith('file://') ? filePath.substring(7) : filePath;

      logger.info(TAG, `Reading file: ${realPath}`);

      // 打开文件
      const file = fs.openSync(realPath, fs.OpenMode.READ_ONLY);

      // 获取文件大小
      const stats = fs.statSync(realPath);
      const fileSize = stats.size;

      // 创建 ArrayBuffer
      const buffer = new ArrayBuffer(fileSize);
      const view = new Uint8Array(buffer);

      // 读取文件内容
      let offset = 0;
      const chunkSize = 4096;

      while (offset < fileSize) {
        const remaining = fileSize - offset;
        const readSize = Math.min(chunkSize, remaining);
        const chunk = new ArrayBuffer(readSize);
        const chunkView = new Uint8Array(chunk);

        const bytesRead = fs.readSync(file.fd, chunk);
        if (bytesRead > 0) {
          view.set(chunkView, offset);
          offset += bytesRead;
        } else {
          break;
        }
      }

      // 关闭文件
      fs.closeSync(file);

      logger.info(TAG, `Successfully read file: ${realPath} (${fileSize} bytes)`);
      return buffer;
    } catch (err) {
      const errorMsg = `readFileAsArrayBuffer failed: ${err}`;
      logger.error(TAG, errorMsg);
      throw new Error(errorMsg);
    }
  }

  /**
   * 合并多个 ArrayBuffer
   */
  private concatArrayBuffers(buffers: ArrayBuffer[]): ArrayBuffer {
    // 计算总长度
    let totalLength = 0;
    for (const buffer of buffers) {
      totalLength += buffer.byteLength;
    }

    // 创建新 ArrayBuffer
    const result = new ArrayBuffer(totalLength);
    const resultView = new Uint8Array(result);

    // 复制数据
    let offset = 0;
    for (const buffer of buffers) {
      const view = new Uint8Array(buffer);
      resultView.set(view, offset);
      offset += buffer.byteLength;
    }

    return result;
  }
}