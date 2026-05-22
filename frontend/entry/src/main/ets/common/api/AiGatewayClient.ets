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
import { VisionLLMClient, TextLLMRequest, VisionLLMRequest, VisionLLMResponse } from './VisionLLMClient';
import { logger } from '../utils/Logger';
import { ImageSanitizer } from '../utils/ImageSanitizer';
import { AiCopyRequest, AiCopyResponse, AiCopyResponseData, VisualKitResult } from '../ai/PhotoMetadata';
import { LocalImageTagger } from '../ai/LocalImageTagger';
import { PhotoMetadata } from '../ai/PhotoMetadata';

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
 * 长度等级 → 目标字数（与 LENGTH_PROMPTS 文案保持一致）
 * 实际 max_tokens 由公式 charLimitToMaxTokens 派生，不要手写硬编码值
 */
const LENGTH_TARGET_CHARS: Record<string, number> = {
  'short': 30,    // "1-2 句话不超过 30 字"
  'medium': 80,   // "约 50-80 字"，取上限
  'long': 200     // "约 120-200 字"，取上限
};

/**
 * 中文目标字数 → max_tokens
 * 公式来自后端实测：1.3 token/字 + 16 给标点和 stop token
 * 实测耗时档位：
 *   30 字  →  55 tok →  8-13s
 *   80 字  → 120 tok → 18-23s
 *   200 字 → 276 tok → 30-35s（接近模型自然 stop 上限）
 */
function charLimitToMaxTokens(targetChars: number): number {
  return Math.ceil(targetChars * 1.3) + 16;
}

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
  /** 进行中的提取任务：同一张图被并行触发多次时，第二次起复用已有 Promise */
  private inflightExtractions: Map<string, Promise<PhotoMetadata>> = new Map();
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
   * 拿到一张图的 PhotoMetadata；命中缓存或 in-flight 直接复用，不重抽。
   * 注意：返回的是缓存对象本身，调用方往 objectTags 写入会被后续命中看到（这正是云端打标的预期）。
   * 并发安全：批量调用 Promise.all([this.getOrExtract..., ...]) 触发同一 path 时只跑一次。
   */
  private async getOrExtractMetadata(photoPath: string): Promise<PhotoMetadata> {
    const cached = this.metadataCache.get(photoPath);
    if (cached) {
      return cached;
    }
    const inflight = this.inflightExtractions.get(photoPath);
    if (inflight) {
      return inflight;
    }
    const promise: Promise<PhotoMetadata> = this.localTagger.extractMetadata(photoPath)
      .then((md: PhotoMetadata) => {
        this.inflightExtractions.delete(photoPath);
        if (this.metadataCache.size >= AiGatewayClient.METADATA_CACHE_MAX) {
          const firstKey: string | undefined = this.metadataCache.keys().next().value;
          if (firstKey) {
            this.metadataCache.delete(firstKey);
          }
        }
        this.metadataCache.set(photoPath, md);
        return md;
      })
      .catch((err: Object): never => {
        this.inflightExtractions.delete(photoPath);
        // ArkTS arkts-limited-throw 要求 throw 必须是 Error 实例
        if (err instanceof Error) {
          throw err;
        }
        throw new Error(`extractMetadata failed: ${JSON.stringify(err)}`);
      });
    this.inflightExtractions.set(photoPath, promise);
    return promise;
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
        topP: 0.85,
        maxTokens: charLimitToMaxTokens(LENGTH_TARGET_CHARS[request.lengthLevel] || LENGTH_TARGET_CHARS['medium'])
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
   * 单图入口的纯文本 prompt（legacy 路径）
   * 与 buildBatchPrompt 同款风格：直接给写作任务，不角色扮演，不塞坐标
   */
  private buildPrompt(request: ImageCopyRequest, metadata: PhotoMetadata): string {
    const styleDesc = STYLE_PROMPTS[request.style] || request.style;
    const lengthDesc = LENGTH_PROMPTS[request.lengthLevel] || LENGTH_PROMPTS['medium'];
    const poiHint = request.poiName ? `地点：${request.poiName}。` : '';
    const userHint = request.userPrompt ? `用户补充：${request.userPrompt}。` : '';
    const metaDesc = describeSinglePhoto(metadata);

    return `根据以下元数据，用${styleDesc}的风格写一段中文旅行短文。` +
      `${metaDesc}` +
      `${poiHint}${userHint}` +
      `长度：${lengthDesc}。` +
      `要求：生动描绘场景和氛围。`;
  }

  /**
   * 多图入口：批量提取 EXIF -> 聚合 -> 单次 LLM 调用
   *
   * 两条路径：
   *  - cloud off：纯文本 prompt → askText
   *  - cloud on：把首张照片（剥 EXIF 副本）+ 完整写作 prompt 一次性发给 askImage，
   *              让模型边看图边写文案。
   *              不再走"先打标再 askText 写文案"的两段流程，省一次推理往返。
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
      // Step 1: 端侧批量抽 EXIF + OCR（并行，命中缓存就跳过重抽）
      const metadataList: PhotoMetadata[] = await Promise.all(
        request.imagePaths.map((path: string) => this.getOrExtractMetadata(path))
      );

      // Step 2: 聚合元数据描述
      const aggregateDesc = describePhotoBatch(metadataList);

      // Step 3: 拼 prompt
      const prompt = buildBatchPrompt(request, aggregateDesc);
      this.lastBatchPrompt = prompt;
      logger.info(TAG, `Built batch prompt (${prompt.length} chars):\n${prompt}`);

      const maxTokens = charLimitToMaxTokens(
        LENGTH_TARGET_CHARS[request.lengthLevel] || LENGTH_TARGET_CHARS['medium']
      );

      // Step 4: 单次推理 —— 走 askImage（cloud on）或 askText（cloud off）
      const cloudOn = request.enableCloudTagging === true && request.context !== undefined;
      const llmResponse = cloudOn
        ? await this.callImageWithPrompt(
            request.context as common.UIAbilityContext,
            request.imagePaths[0],
            prompt,
            maxTokens
          )
        : await this.visionClient.askText({
            prompt: prompt,
            modelName: 'Qwen-VL-Chat-Int4',
            temperature: 0.9,
            topP: 0.85,
            maxTokens: maxTokens
          });

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
   * 把首张照片 sanitize 后连同完整写作 prompt 一次发给 askImage。
   * 失败时回退到 askText（仅文本），避免阻断生成。
   */
  private async callImageWithPrompt(
    context: common.UIAbilityContext,
    imagePath: string,
    prompt: string,
    maxTokens: number
  ): Promise<HttpResponse<VisionLLMResponse>> {
    let sanitizedPath = '';
    try {
      sanitizedPath = await ImageSanitizer.sanitizeForUpload(context, imagePath);
      if (sanitizedPath.length === 0) {
        logger.warn(TAG, 'Sanitize failed, falling back to text-only generation');
        return await this.visionClient.askText({
          prompt: prompt,
          modelName: 'Qwen-VL-Chat-Int4',
          temperature: 0.9,
          topP: 0.85,
          maxTokens: maxTokens
        });
      }
      const visionRequest: VisionLLMRequest = {
        imagePath: sanitizedPath,
        question: prompt,
        modelName: 'Qwen-VL-Chat-Int4',
        temperature: 0.9,
        topP: 0.85,
        maxTokens: maxTokens
      };
      return await this.visionClient.askImage(visionRequest);
    } finally {
      if (sanitizedPath.length > 0) {
        ImageSanitizer.deleteSanitized(sanitizedPath);
      }
    }
  }

  /**
   * 仅做端侧 EXIF 提取并返回聚合后的"可读文本描述"
   * 给 UI 预览用，不调 LLM
   */
  async describeImages(imagePaths: string[]): Promise<string> {
    if (imagePaths.length === 0) {
      return '';
    }
    const metadataList: PhotoMetadata[] = await Promise.all(
      imagePaths.map((path: string) => this.getOrExtractMetadata(path))
    );
    return describePhotoBatch(metadataList);
  }

  /**
   * 预览 prompt：完整跑一遍提取 + 聚合 + 拼 prompt，但不发给 LLM
   * 用于 UI 上"生成前预览"功能
   *
   * 注意：cloud on 时，真正的生成会把首张照片连同这段 prompt 一起发给 askImage，
   * 模型会同时看到图片本身。预览 UI 只能展示 prompt 文本部分，需要在调用方
   * 给出"将连同首张照片一起发送"的提示。
   */
  async previewPromptForImages(request: ImagesCopyRequest): Promise<string> {
    if (request.imagePaths.length === 0) {
      return '';
    }
    const metadataList: PhotoMetadata[] = await Promise.all(
      request.imagePaths.map((path: string) => this.getOrExtractMetadata(path))
    );
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
}

/**
 * 把 EXIF 时间字符串 "YYYY:MM:DD HH:MM:SS" 简化成 "YYYY-MM-DD"
 * 只保留日期，丢弃秒级精度和原始的奇怪冒号分隔
 */
function formatExifDate(raw: string): string | undefined {
  const datePart = raw.split(' ')[0];
  const parts = datePart.split(':');
  if (parts.length !== 3) {
    return undefined;
  }
  const yyyy = parts[0];
  const mm = parts[1];
  const dd = parts[2];
  if (!yyyy || !mm || !dd) {
    return undefined;
  }
  return `${yyyy}-${mm}-${dd}`;
}

/**
 * 把单张照片的元数据描述成一段中文
 * 不再输出 GPS 数字（对模型无意义）和拍摄设备/曝光等技术参数
 */
function describeSinglePhoto(md: PhotoMetadata): string {
  // 没有"画面内容"或"画面中文字"时，仅时段/日期对 LLM 无信息价值，直接返空。
  if (md.objectTags.length === 0 && (!md.ocrText || md.ocrText.length === 0)) {
    return '';
  }
  const parts: string[] = [];
  if (md.objectTags.length > 0) {
    parts.push(`画面内容：${md.objectTags.join('、')}`);
  }
  if (md.ocrText && md.ocrText.length > 0) {
    parts.push(`画面中文字：「${md.ocrText}」`);
  }
  if (md.timeTags.length > 0) {
    parts.push(`时段：${md.timeTags.join('、')}`);
  }
  if (md.dateTimeOriginal) {
    const date = formatExifDate(md.dateTimeOriginal);
    if (date) {
      parts.push(`日期：${date}`);
    }
  }
  return parts.length > 0 ? parts.join('。') + '。' : '';
}

/**
 * 多张照片的元数据聚合成一段中文（去重 + 范围归并）
 * 同样不再写 GPS 数字
 */
function describePhotoBatch(list: PhotoMetadata[]): string {
  if (list.length === 0) {
    return '';
  }

  const objectSet: Set<string> = new Set();
  const ocrSet: Set<string> = new Set();
  const timeSet: Set<string> = new Set();
  let earliest: string | undefined;
  let latest: string | undefined;
  let withDateTime = 0;

  for (const md of list) {
    md.objectTags.forEach((t: string) => objectSet.add(t));
    md.timeTags.forEach((t: string) => timeSet.add(t));
    if (md.ocrText && md.ocrText.length > 0) {
      ocrSet.add(md.ocrText);
    }
    if (md.dateTimeOriginal) {
      const formatted = formatExifDate(md.dateTimeOriginal);
      if (formatted) {
        withDateTime += 1;
        if (!earliest || formatted < earliest) {
          earliest = formatted;
        }
        if (!latest || formatted > latest) {
          latest = formatted;
        }
      }
    }
  }

  // 没有"画面内容"或"画面中文字"时，只剩张数+时段+日期对 LLM 没什么信息价值，
  // 反而占 prompt 长度，直接返空让 buildBatchPrompt 跳过整个【照片元数据】section。
  if (objectSet.size === 0 && ocrSet.size === 0) {
    return '';
  }

  const parts: string[] = [];
  if (list.length > 1) {
    parts.push(`共 ${list.length} 张照片`);
  }
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
      parts.push(`日期：${earliest}`);
    } else {
      parts.push(`日期区间：${earliest} ~ ${latest}`);
    }
  }

  return parts.length > 0 ? parts.join('；') + '。' : '';
}

/**
 * 多图 prompt 模板（v2，2026-05-15 重构）
 *
 * 设计原则：
 * - **结构化分段**：用【任务】/【场景信息】/【照片元数据】/【输出要求】把上下文和指令分块，
 *   LLM 比读一大段连续文本更可靠地遵守约束（实测 Qwen3 系列改善明显）。
 * - **空字段不渲染**：没填的字段（如 mood）直接省略对应行，prompt 不混入空 "心情:"。
 * - **明确输出格式**：显式说"直接给正文，不要标题/前言/总结/Markdown"，避免模型加 # 或 *。
 * - **cloud-on 必加 grounding 句**：Qwen-VL prompt-sensitive，没有"基于照片实际画面"约束，
 *   模型容易把图片当 optional context 略过，瞎编画面里没有的细节。
 * - **不做角色扮演**：不用"你是旅行博主"，直接给任务；不塞 GPS 数字（模型会机械复述）。
 *
 * 详细规则与各字段含义参见根目录 PROMPT_RULES.md。
 */
function buildBatchPrompt(request: ImagesCopyRequest, exifDesc: string): string {
  const styleDesc = STYLE_PROMPTS[request.style] || request.style;
  const lengthDesc = LENGTH_PROMPTS[request.lengthLevel] || LENGTH_PROMPTS['medium'];
  const cloudOn = request.enableCloudTagging === true && request.context !== undefined;

  // 【场景信息】子项：空字段一律不出现，避免 prompt 里挂"地点："这种空 placeholder
  const sceneLines: string[] = [];
  if (request.poiName && request.poiName.length > 0) {
    sceneLines.push(`- 地点：${request.poiName}`);
  }
  if (request.mood && request.mood.length > 0) {
    sceneLines.push(`- 心情：${request.mood}`);
  }
  if (request.tags && request.tags.length > 0) {
    sceneLines.push(`- 标签：${request.tags.join('、')}`);
  }
  if (request.userPrompt && request.userPrompt.length > 0) {
    sceneLines.push(`- 用户补充：${request.userPrompt}`);
  }

  // 【输出要求】子项：固定 + 条件式
  const reqLines: string[] = [
    `- 长度：${lengthDesc}`,
    `- 直接给正文，不要标题、前言、总结，不要 Markdown 格式`,
    `- 生动描绘场景与氛围`,
    `- 照片里出现的地名、招牌、菜名可自然融入文中`,
  ];
  if (cloudOn) {
    reqLines.unshift('- 基于照片中实际看到的画面来写，不要编造画面里没有的内容');
  }

  const parts: string[] = [];
  parts.push(`【任务】用「${styleDesc}」的风格写一段中文旅行短文。`);
  if (sceneLines.length > 0) {
    parts.push(`\n\n【场景信息】\n${sceneLines.join('\n')}`);
  }
  if (exifDesc && exifDesc.length > 0) {
    parts.push(`\n\n【照片元数据】\n${exifDesc}`);
  }
  parts.push(`\n\n【输出要求】\n${reqLines.join('\n')}`);

  return parts.join('');
}

