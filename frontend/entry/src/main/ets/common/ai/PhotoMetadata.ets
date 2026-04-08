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
 * 照片元数据类型定义
 * 视觉套件提取的图片信息结构
 */

/**
 * 单张照片的元数据
 * 由视觉套件提取，存储在 photo_metadata 表
 */
export interface PhotoMetadata {
  /** 照片沙箱路径 (主键) */
  photoPath: string;
  /** 场景标签 (如: nature, city, indoor, outdoor) */
  sceneTags: string[];
  /** 物体标签 (如: mountain, building, person, food) */
  objectTags: string[];
  /** 颜色标签 (如: warm, cool, colorful) */
  colorTags: string[];
  /** 时间标签 (如: morning, sunset, night) */
  timeTags: string[];
  /** 情感标签 (如: happy, peaceful, exciting) */
  emotionTags: string[];
  /** 提取时间戳 */
  extractedAt: number;
}

/**
 * 旅程元数据聚合结果
 * 用于发送给后端 AI Gateway
 */
export interface JourneyMetadata {
  /** POI 名称列表 (脱敏) */
  poiList: string[];
  /** 总距离 (公里) */
  totalDistanceKm: number;
  /** 时长 (小时) */
  durationHours: number;
  /** 聚合后的场景标签 */
  tags: string[];
  /** 照片数量 */
  photoCount: number;
}

/**
 * AI 文案生成请求
 * 发送给后端 /api/v1/ai/generate
 */
export interface AiCopyRequest {
  /** 旅程元数据 */
  journey_metadata: JourneyMetadata;
  /** 用户草稿/提示词 (可选) */
  user_draft?: string;
  /** 文案风格 (poetic, factual, casual, minimal, social) */
  style: string;
  /** 字数限制 */
  word_limit: number;
  /** 自定义提示词 (可选) */
  custom_prompt?: string;
}

/**
 * AI 文案生成响应数据
 * 后端返回 data 字段结构
 */
export interface AiCopyResponseData {
  /** 生成的文案 */
  generated_text: string;
  /** 备选方案 */
  alternatives?: string[];
}

/**
 * AI 文案生成响应
 * 后端返回结构
 */
export interface AiCopyResponse {
  /** 响应码 (0 表示成功) */
  code: number;
  /** 响应数据 */
  data: AiCopyResponseData;
}

/**
 * 视觉套件提取结果
 * TODO: 视觉套件队友需确认具体字段
 */
export interface VisualKitResult {
  /** 原始照片路径 */
  photoPath: string;
  /** 标签数组 */
  tags: string[];
  /** 提取是否成功 */
  success: boolean;
  /** 错误信息 (失败时) */
  error?: string;
}