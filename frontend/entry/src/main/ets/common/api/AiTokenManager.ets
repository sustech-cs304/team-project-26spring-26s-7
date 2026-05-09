/**
 * AI 子服务 token 管理器（运行时获取，非硬编码）。
 *
 * 设计：
 * - 登录用户调用 share_service 的 POST /api/v1/auth/issue_ai_token，
 *   一次性领取 vision/filter/censor 三套 token，按 expires_in 缓存。
 * - 缓存命中直接返回；过期或缺失则重新申领。
 * - 申领失败时降级到 fallback dev token，保证 debug 包不直接挂掉
 *   （release 上架前后端必须配齐 AI_*_TOKEN，不会走到 fallback）。
 *
 * 鉴权方式：
 * - 当前 share_service 开启 ALLOW_DEV_UID_HEADER=1，发 X-Dev-Uid 即可。
 * - 上架时后端关掉该开关，前端需要切换到 Bearer <agc_id_token>，参见 Tier 2.3。
 */
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

import { API_BASE_URL } from './ApiEndpoints';
import { AuthService } from '../auth/AuthService';

const DOMAIN = 0x0000;
const TAG = 'AiTokenManager';

/** Tier 2.2 完成前的兜底 token；上架前后端不允许走到这里 */
const FALLBACK_DEV_TOKEN = 'DEV_05436de19d4ad0029b4d722b9288167b';

interface IssueResp {
  vision_token?: string;
  filter_token?: string;
  censor_token?: string;
  issued_at?: number;
  expires_in?: number;
}

interface CachedTokens {
  vision: string;
  filter: string;
  censor: string;
  /** 本地时间戳（秒），到此点视为过期 */
  expiresAt: number;
}

let cached: CachedTokens | null = null;
let inflight: Promise<CachedTokens> | null = null;

/** 提前 60s 视为过期，避免边界请求被服务端拒绝 */
const EXPIRY_LEEWAY_SEC = 60;

async function fetchTokens(): Promise<CachedTokens> {
  const user = await AuthService.getCurrentUser();
  if (!user) {
    hilog.warn(DOMAIN, TAG, 'no current user, falling back to dev token');
    return makeFallback();
  }

  const url = `${API_BASE_URL}/api/v1/auth/issue_ai_token`;
  const httpReq = http.createHttp();
  try {
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        // 当前后端 ALLOW_DEV_UID_HEADER=1，用此头免登录 token
        'X-Dev-Uid': user.uid,
      },
      readTimeout: 10_000,
      connectTimeout: 10_000,
      expectDataType: http.HttpDataType.OBJECT,
      extraData: '',
    };
    const resp = await httpReq.request(url, options);
    if (resp.responseCode !== 200) {
      hilog.warn(DOMAIN, TAG, `issue_ai_token http ${resp.responseCode}, fallback`);
      return makeFallback();
    }
    const body = resp.result as IssueResp;
    if (!body || !body.vision_token || !body.filter_token || !body.censor_token) {
      hilog.warn(DOMAIN, TAG, 'issue_ai_token resp missing fields, fallback');
      return makeFallback();
    }
    const ttl = body.expires_in ?? 1800;
    const issued = body.issued_at ?? Math.floor(Date.now() / 1000);
    return {
      vision: body.vision_token,
      filter: body.filter_token,
      censor: body.censor_token,
      expiresAt: issued + ttl - EXPIRY_LEEWAY_SEC,
    };
  } catch (e) {
    const be = e as BusinessError;
    hilog.warn(DOMAIN, TAG, `issue_ai_token failed: ${be?.message ?? JSON.stringify(e)}, fallback`);
    return makeFallback();
  } finally {
    httpReq.destroy();
  }
}

function makeFallback(): CachedTokens {
  return {
    vision: FALLBACK_DEV_TOKEN,
    filter: FALLBACK_DEV_TOKEN,
    censor: FALLBACK_DEV_TOKEN,
    expiresAt: Math.floor(Date.now() / 1000) + 60, // 1 分钟后重试，避免雪崩
  };
}

async function getTokens(): Promise<CachedTokens> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.expiresAt > now) {
    return cached;
  }
  if (inflight) {
    return inflight;
  }
  // fetchTokens 内部已经 try/catch 所有异常并降级到 fallback，不会 throw；
  // 这里只用 try/finally 保证 inflight 被清理。
  const p: Promise<CachedTokens> = fetchTokens();
  inflight = p;
  try {
    const t: CachedTokens = await p;
    cached = t;
    return t;
  } finally {
    inflight = null;
  }
}

export class AiTokenManager {
  /** 拿 ai-service (Qwen-VL) 用的 Bearer token */
  static async getVisionToken(): Promise<string> {
    return (await getTokens()).vision;
  }

  /** 拿敏感词过滤服务用的 Bearer token */
  static async getFilterToken(): Promise<string> {
    return (await getTokens()).filter;
  }

  /** 拿百度图片审核代理用的 Bearer token */
  static async getCensorToken(): Promise<string> {
    return (await getTokens()).censor;
  }

  /** 强制清缓存（如收到 401，应用应清缓存重试一次） */
  static invalidate(): void {
    cached = null;
  }
}
