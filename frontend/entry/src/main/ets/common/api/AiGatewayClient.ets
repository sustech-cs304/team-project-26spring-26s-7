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

import { common } from '@kit.AbilityKit';
import { HttpClient, HttpResponse } from './HttpClient';
import { AiEndpoints, HttpTimeout } from './ApiEndpoints';
import { VisionLLMClient, TextLLMRequest, VisionLLMRequest } from './VisionLLMClient';
import { logger } from '../utils/Logger';
import { ImageSanitizer } from '../utils/ImageSanitizer';
import { AiCopyRequest, AiCopyResponse, AiCopyResponseData, VisualKitResult } from '../ai/PhotoMetadata';
import { LocalImageTagger } from '../ai/LocalImageTagger';
import { PhotoMetadata } from '../ai/PhotoMetadata';

const TAG = 'AiGatewayClient';
/**
 * 控制云端打标签时最多送多少张照片
 * 后端 GPU 入口当前是 asyncio.Semaphore(1) 严格串行，N>1 也会排队 → 只放大端到端时延
 * 等后端上 batching / 多卡再放开
 */
const MAX_CLOUD_TAGGING_IMAGES = 1;
/** 给 Qwen-VL 的打标签 prompt */
const TAGGING_QUESTION =
  '请用 5-10 个简短中文短语描述这张图片中的主要物体、场景和氛围，每个短语不超过 8 个汉字，' +
  '使用中文顿号「、」分隔，只输出短语列表本身，不要任何前缀、解释或编号。' +
  '示例：橘猫、布艺沙发、客厅、午后阳光、慵懒。';

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
 * 基于多张图片的 AI 文案生成请求
 * 端侧批量提取每张照片的 EXIF / 像素信息，再聚合成一段纯文本 prompt
 * 走 LLM 的 text-only 接口，照片不出设备。
 */
export interface ImagesCopyRequest {
  /** 图片沙箱路径数组 */
  imagePaths: string[];
  /** 文案风格 */
  style: string;
  /** 长度等级：short / medium / long */
  lengthLevel: string;
  /** 用户补充提示词 */
  userPrompt?: string;
  /** 地点名称（POI） */
  poiName?: string;
  /** 节点已记录的 GPS（与 EXIF 互为兜底） */
  latitude?: number;
  longitude?: number;
  /** 用户心情 */
  mood?: string;
  /** 用户标签 */
  tags?: string[];
  /**
   * 是否调用云端 Qwen-VL 抽取画面内容标签。
   * 仅当用户在 ProfileView 显式开启、且本次 JIT 同意通过时才传 true。
   */
  enableCloudTagging?: boolean;
  /**
   * 上下文：开启 cloudTagging 时必须传入，用于把照片在上传前 sanitize 出 EXIF。
   */
  context?: common.UIAbilityContext;
}

/**
 * AI Gateway 客户端
 * 负责与 VisionLLM（Qwen-VL）交互，生成旅行文案
 */
export class AiGatewayClient {
  private httpClient: HttpClient;
  private visionClient: VisionLLMClient;
  private localTagger: LocalImageTagger;
  /** 最近一次构建出的批量 prompt，给 UI 调试用 */
  private lastBatchPrompt: string = '';
  /**
   * PhotoMetadata 缓存：以沙箱路径为 key，避免同一张照片在
   * "UI 预览"和"实际生成"两条路径里被重复抽 EXIF / OCR / 分割。
   * 用 LRU 风格的简单大小限制，避免长会话堆积。
   */
  private metadataCache: Map<string, PhotoMetadata> = new Map();
  private static readonly METADATA_CACHE_MAX = 32;

  constructor() {
    this.httpClient = new HttpClient();
    this.visionClient = new VisionLLMClient();
    this.localTagger = new LocalImageTagger();
  }

  /** 取上一次实际发送给 LLM 的 prompt（调用 generateCopyFromImages 或 previewPromptForImages 后填充） */
  getLastBatchPrompt(): string {
    return this.lastBatchPrompt;
  }

  /**
   * 拿到一张图的 PhotoMetadata，命中缓存就不重抽
   * 注意：返回的是缓存对象本身，调用方往 objectTags 写入会被后续命中看到（这正是云端打标的预期）
   */
  private async getOrExtractMetadata(photoPath: string): Promise<PhotoMetadata> {
    const cached = this.metadataCache.get(photoPath);
    if (cached) {
      return cached;
    }
    const md = await this.localTagger.extractMetadata(photoPath);
    if (this.metadataCache.size >= AiGatewayClient.METADATA_CACHE_MAX) {
      // 简单驱逐：删掉最早插入的一条（Map 保留插入顺序）
      const firstKey: string | undefined = this.metadataCache.keys().next().value;
      if (firstKey) {
        this.metadataCache.delete(firstKey);
      }
    }
    this.metadataCache.set(photoPath, md);
    return md;
  }

  /** 用户删图或换图时由调用方主动失效缓存，避免缓存永远不释放 */
  invalidateMetadata(photoPath: string): void {
    this.metadataCache.delete(photoPath);
  }

  /** 一次性清掉所有缓存（页面销毁时可调用） */
  clearMetadataCache(): void {
    this.metadataCache.clear();
  }

  /**
   * 基于图片生成旅行文案（核心方法）
   * 流程：端侧分析图片提取标签 → 纯文本 prompt 发给 LLM → 生成文案
   * 照片不会离开设备
   */
  async generateCopyFromImage(request: ImageCopyRequest): Promise<HttpResponse<AiCopyResponse>> {
    logger.info(TAG, `Generating copy from image: ${request.imagePath}`);

    try {
      // 第一步：端侧图片分析（照片不出设备）
      const metadata = await this.localTagger.extractMetadata(request.imagePath);
      logger.info(TAG, `On-device analysis done: scene=[${metadata.sceneTags.join(',')}], object=[${metadata.objectTags.join(',')}]`);

      // 第二步：构建纯文本 prompt
      const question = this.buildPrompt(request, metadata);
      logger.debug(TAG, `Built prompt: ${question}`);

      // 第三步：纯文本调用 LLM（不发送图片）
      const textRequest: TextLLMRequest = {
        prompt: question,
        modelName: 'Qwen-VL-Chat-Int4',
        temperature: 0.9,
        topP: 0.85
      };

      const llmResponse = await this.visionClient.askText(textRequest);

      if (llmResponse.statusCode === 200 && llmResponse.data) {
        const responseData: AiCopyResponseData = {
          generated_text: llmResponse.data.content,
          alternatives: []
        };
        const aiResponse: AiCopyResponse = {
          code: 0,
          data: responseData
        };

        logger.info(TAG, 'Copy generated successfully (text-only, no image uploaded)');
        return {
          statusCode: 200,
          data: aiResponse
        };
      } else {
        const errorMsg = llmResponse.error || `LLM 返回状态码: ${llmResponse.statusCode}`;
        logger.error(TAG, errorMsg);
        return {
          statusCode: llmResponse.statusCode,
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
   * 根据端侧分析结果和用户输入构建纯文本 prompt
   */
  private buildPrompt(request: ImageCopyRequest, metadata: PhotoMetadata): string {
    const styleDesc = STYLE_PROMPTS[request.style] || request.style;
    const lengthDesc = LENGTH_PROMPTS[request.lengthLevel] || LENGTH_PROMPTS['medium'];
    const poiHint = request.poiName ? `拍摄地点是「${request.poiName}」。` : '';
    const userHint = request.userPrompt ? `用户补充说明：${request.userPrompt}。` : '';
    const metaDesc = describeSinglePhoto(metadata);

    return `请你作为一名旅行博主，` +
      `${metaDesc}` +
      `${poiHint}${userHint}` +
      `用${styleDesc}的风格，写一段旅行文案。` +
      `长度要求：${lengthDesc}。` +
      `要求：生动描绘旅行场景和氛围，富有感染力，严格遵守长度要求。`;
  }

  /**
   * 多图入口：批量提取 EXIF -> 聚合 -> 单次 LLM 调用
   * 照片仍然不出设备
   */
  async generateCopyFromImages(request: ImagesCopyRequest): Promise<HttpResponse<AiCopyResponse>> {
    logger.info(TAG, `Generating copy from ${request.imagePaths.length} images`);

    if (request.imagePaths.length === 0) {
      return {
        statusCode: 0,
        data: undefined,
        error: 'imagePaths is empty'
      };
    }

    try {
      // Step 1: 端侧批量抽 EXIF（命中缓存就跳过重抽）
      const metadataList: PhotoMetadata[] = [];
      for (const path of request.imagePaths) {
        const md = await this.getOrExtractMetadata(path);
        metadataList.push(md);
      }

      // Step 2 (可选): 云端打标签 —— 把前 N 张照片送 Qwen-VL 抽内容标签
      // 仅在用户已知情同意 + ProfileView 开关已打开时才走这条
      if (request.enableCloudTagging === true && request.context) {
        await this.augmentMetadataWithCloudTags(request.context, metadataList);
      }

      // Step 3: 聚合 -> 文本描述
      const aggregateDesc = describePhotoBatch(metadataList);

      // Step 4: 拼 prompt
      const prompt = buildBatchPrompt(request, aggregateDesc);
      this.lastBatchPrompt = prompt;
      logger.info(TAG, `Built batch prompt (${prompt.length} chars):\n${prompt}`);

      // Step 5: 纯文本 LLM
      const textRequest: TextLLMRequest = {
        prompt: prompt,
        modelName: 'Qwen-VL-Chat-Int4',
        temperature: 0.9,
        topP: 0.85
      };
      const llmResponse = await this.visionClient.askText(textRequest);

      if (llmResponse.statusCode === 200 && llmResponse.data) {
        const responseData: AiCopyResponseData = {
          generated_text: llmResponse.data.content,
          alternatives: []
        };
        return {
          statusCode: 200,
          data: { code: 0, data: responseData }
        };
      }

      const errorMsg = llmResponse.error || `LLM 返回状态码: ${llmResponse.statusCode}`;
      logger.error(TAG, errorMsg);
      return {
        statusCode: llmResponse.statusCode,
        data: undefined,
        error: errorMsg
      };
    } catch (err) {
      const errorMsg = `generateCopyFromImages failed: ${JSON.stringify(err)}`;
      logger.error(TAG, errorMsg);
      return {
        statusCode: 0,
        data: undefined,
        error: errorMsg
      };
    }
  }

  /**
   * 仅做端侧 EXIF 提取并返回聚合后的"可读文本描述"
   * 给 UI 预览用，不调 LLM
   */
  /**
   * 云端打标签：对前 MAX_CLOUD_TAGGING_IMAGES 张图调 Qwen-VL askImage，
   * 把返回的中文短语列表写回 PhotoMetadata.objectTags。
   *
   * 关键约束：
   *   - 上传前先 sanitize 副本（剥 EXIF），原图不动；
   *   - 失败/超时单张静默回退到空标签，不阻断生成；
   *   - 推理后立即删除 sanitize 副本。
   */
  private async augmentMetadataWithCloudTags(
    context: common.UIAbilityContext,
    metadataList: PhotoMetadata[]
  ): Promise<void> {
    const targets = metadataList.slice(0, MAX_CLOUD_TAGGING_IMAGES);
    logger.info(TAG, `Cloud tagging: requesting ${targets.length}/${metadataList.length} images`);

    const tasks: Promise<void>[] = [];
    for (const md of targets) {
      tasks.push(this.tagOnePhoto(context, md));
    }
    await Promise.all(tasks);
  }

  private async tagOnePhoto(
    context: common.UIAbilityContext,
    md: PhotoMetadata
  ): Promise<void> {
    let sanitizedPath = '';
    try {
      sanitizedPath = await ImageSanitizer.sanitizeForUpload(context, md.photoPath);
      if (sanitizedPath.length === 0) {
        logger.warn(TAG, `Sanitize failed, skip cloud tag for: ${md.photoPath}`);
        return;
      }
      // 后端会把 temperature<0.7 静默上调到 0.7（Int4 量化模型的 softmax NaN 防护）
      // 所以直接传 0.7 + top_p 0.5 让候选更聚焦，避免标签发散
      const visionRequest: VisionLLMRequest = {
        imagePath: sanitizedPath,
        question: TAGGING_QUESTION,
        modelName: 'Qwen-VL-Chat-Int4',
        temperature: 0.7,
        topP: 0.5
      };
      const resp = await this.visionClient.askImage(visionRequest);
      if (resp.statusCode === 200 && resp.data && resp.data.content) {
        const tags = parseTagList(resp.data.content);
        if (tags.length > 0) {
          md.objectTags = mergeUnique(md.objectTags, tags);
          logger.info(TAG, `Cloud tags for ${md.photoPath}: ${tags.join(',')}`);
        }
      } else if (resp.statusCode === 401) {
        logger.error(TAG, `Cloud tag 401: token 缺失或失效，停止本次打标`);
      } else if (resp.statusCode === 429) {
        logger.warn(TAG, `Cloud tag 429: 触发限流（30 次/分钟），降级到纯 EXIF`);
      } else {
        logger.warn(TAG, `Cloud tag call failed: status=${resp.statusCode}, err=${resp.error}`);
      }
    } catch (err) {
      logger.error(TAG, `tagOnePhoto error: ${JSON.stringify(err)}`);
    } finally {
      if (sanitizedPath.length > 0) {
        ImageSanitizer.deleteSanitized(sanitizedPath);
      }
    }
  }

  async describeImages(imagePaths: string[]): Promise<string> {
    if (imagePaths.length === 0) {
      return '';
    }
    const metadataList: PhotoMetadata[] = [];
    for (const path of imagePaths) {
      const md = await this.getOrExtractMetadata(path);
      metadataList.push(md);
    }
    return describePhotoBatch(metadataList);
  }

  /**
   * 预览 prompt：完整跑一遍提取 + 聚合 + 拼 prompt，但不发给 LLM
   * 用于 UI 上"生成前预览"功能
   */
  async previewPromptForImages(request: ImagesCopyRequest): Promise<string> {
    if (request.imagePaths.length === 0) {
      return '';
    }
    const metadataList: PhotoMetadata[] = [];
    for (const path of request.imagePaths) {
      const md = await this.getOrExtractMetadata(path);
      metadataList.push(md);
    }
    if (request.enableCloudTagging === true && request.context) {
      await this.augmentMetadataWithCloudTags(request.context, metadataList);
    }
    const aggregateDesc = describePhotoBatch(metadataList);
    const prompt = buildBatchPrompt(request, aggregateDesc);
    this.lastBatchPrompt = prompt;
    return prompt;
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

/** 把单张照片的元数据描述成一段中文（精简，只保留对文案生成有用的信号） */
function describeSinglePhoto(md: PhotoMetadata): string {
  const parts: string[] = [];
  if (md.objectTags.length > 0) {
    parts.push(`画面内容：${md.objectTags.join('、')}`);
  }
  if (md.ocrText && md.ocrText.length > 0) {
    parts.push(`画面中文字：「${md.ocrText}」`);
  }
  if (md.timeTags.length > 0) {
    parts.push(`拍摄时段：${md.timeTags.join('、')}`);
  }
  if (md.dateTimeOriginal) {
    parts.push(`拍摄时间：${md.dateTimeOriginal}`);
  }
  if (md.gpsLatitude !== undefined && md.gpsLongitude !== undefined) {
    parts.push(`GPS：${md.gpsLatitude.toFixed(4)}, ${md.gpsLongitude.toFixed(4)}`);
  }
  return parts.length > 0 ? parts.join('。') + '。' : '';
}

/** 多张照片的元数据聚合成一段中文（去重 + 范围归并） */
function describePhotoBatch(list: PhotoMetadata[]): string {
  if (list.length === 0) {
    return '';
  }

  const objectSet: Set<string> = new Set();
  const ocrSet: Set<string> = new Set();
  const timeSet: Set<string> = new Set();
  let earliest: string | undefined;
  let latest: string | undefined;
  let latSum = 0;
  let lonSum = 0;
  let gpsCount = 0;
  let withDateTime = 0;

  for (const md of list) {
    md.objectTags.forEach((t: string) => objectSet.add(t));
    md.timeTags.forEach((t: string) => timeSet.add(t));
    if (md.ocrText && md.ocrText.length > 0) {
      ocrSet.add(md.ocrText);
    }
    if (md.dateTimeOriginal) {
      withDateTime += 1;
      if (!earliest || md.dateTimeOriginal < earliest) {
        earliest = md.dateTimeOriginal;
      }
      if (!latest || md.dateTimeOriginal > latest) {
        latest = md.dateTimeOriginal;
      }
    }
    if (md.gpsLatitude !== undefined && md.gpsLongitude !== undefined) {
      latSum += md.gpsLatitude;
      lonSum += md.gpsLongitude;
      gpsCount += 1;
    }
  }

  const parts: string[] = [];
  parts.push(`共 ${list.length} 张照片`);

  if (objectSet.size > 0) {
    parts.push(`画面内容：${Array.from(objectSet).join('、')}`);
  }
  if (ocrSet.size > 0) {
    let combined = Array.from(ocrSet).join(' / ');
    if (combined.length > 200) {
      combined = combined.substring(0, 200) + '…';
    }
    parts.push(`画面中文字：「${combined}」`);
  }
  if (timeSet.size > 0) {
    parts.push(`时段：${Array.from(timeSet).join('、')}`);
  }
  if (withDateTime > 0 && earliest && latest) {
    if (earliest === latest) {
      parts.push(`拍摄时间：${earliest}`);
    } else {
      parts.push(`拍摄时间区间：${earliest} ~ ${latest}`);
    }
  }
  if (gpsCount > 0) {
    const avgLat = latSum / gpsCount;
    const avgLon = lonSum / gpsCount;
    parts.push(`GPS 中心点：${avgLat.toFixed(4)}, ${avgLon.toFixed(4)}`);
  }

  return parts.join('；') + '。';
}

/** 多图 prompt 模板 */
function buildBatchPrompt(request: ImagesCopyRequest, exifDesc: string): string {
  const styleDesc = STYLE_PROMPTS[request.style] || request.style;
  const lengthDesc = LENGTH_PROMPTS[request.lengthLevel] || LENGTH_PROMPTS['medium'];
  const poiHint = request.poiName ? `拍摄地点是「${request.poiName}」。` : '';
  const moodHint = request.mood && request.mood.length > 0 ? `当前心情：${request.mood}。` : '';
  const tagsHint = request.tags && request.tags.length > 0 ? `标签：${request.tags.join('、')}。` : '';
  const userHint = request.userPrompt && request.userPrompt.length > 0
    ? `用户补充说明：${request.userPrompt}。`
    : '';

  // 节点上的 GPS 兜底（EXIF 缺失时仍能给出位置）
  const fallbackGps =
    request.latitude !== undefined &&
    request.longitude !== undefined &&
    request.latitude !== 0 &&
    request.longitude !== 0
      ? `节点定位：${request.latitude.toFixed(4)}, ${request.longitude.toFixed(4)}。`
      : '';

  return `请你作为一名旅行博主，根据以下元数据写一段旅行文案。` +
    `${exifDesc}` +
    `${poiHint}${fallbackGps}${moodHint}${tagsHint}${userHint}` +
    `风格：${styleDesc}。长度：${lengthDesc}。` +
    `要求：生动描绘场景和氛围，不要复述 GPS 数字，` +
    `如果"画面中文字"是地名/招牌/菜名，可自然融入。`;
}

/**
 * 把 Qwen-VL 返回的"短语1、短语2、短语3"形式的字符串解析成数组
 * 兼容中英文逗号 / 顿号 / 换行 / 回车混用
 *
 * 后端"敏感词命中只把命中片段替换成 ***"的策略意味着可能出现整段为 *
 * 的短语，需要显式丢弃；单 token 命中（标签里夹杂 *）保持原样上行
 */
function parseTagList(raw: string): string[] {
  if (!raw || raw.length === 0) {
    return [];
  }
  // 去掉常见前缀（"标签：" / "短语：" / 数字编号 等）
  const cleaned = raw
    .replace(/^[\s\S]*?[：:]/, (m: string) => (m.length > 30 ? m : ''))  // 仅短前缀去除
    .replace(/[\d]+[\.、)]\s*/g, '');
  const pieces = cleaned.split(/[、，,；;\n\r\/]+/);
  const out: string[] = [];
  for (const p of pieces) {
    const trimmed = p.trim().replace(/^[「『"']+/, '').replace(/[」』"']+$/, '');
    if (trimmed.length === 0 || trimmed.length > 16) {
      continue;
    }
    // 整段全是 * 是后端打码的产物，直接丢
    if (/^\*+$/.test(trimmed)) {
      continue;
    }
    out.push(trimmed);
  }
  // 最多 10 个，避免污染 prompt
  return out.slice(0, 10);
}

function mergeUnique(existing: string[], incoming: string[]): string[] {
  const set: Set<string> = new Set(existing);
  for (const t of incoming) {
    set.add(t);
  }
  return Array.from(set);
}