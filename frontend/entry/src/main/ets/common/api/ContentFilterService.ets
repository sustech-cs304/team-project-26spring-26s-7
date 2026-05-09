import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CONTENT_FILTER_BASE_URL } from './ApiEndpoints';

const DOMAIN = 0x0000;
const TAG = 'ContentFilterService';
const FILTER_BASE_URL = CONTENT_FILTER_BASE_URL;

export interface CheckResult {
  blocked: boolean;
  hit: string | null;
  hits_count: number;
}

export interface MaskResult {
  masked: string;
  hits: string[];
}

// 请求体类型
class CheckIn {
  text: string = '';
  constructor(text: string) {
    this.text = text;
  }
}

class BatchCheckIn {
  texts: string[] = [];
  constructor(texts: string[]) {
    this.texts = texts;
  }
}

class MaskIn {
  text: string = '';
  mask: string = '';
  constructor(text: string, mask: string) {
    this.text = text;
    this.mask = mask;
  }
}

class BatchCheckOut {
  results: CheckResult[] = [];
}

// 返回值类型
class CheckResultImpl implements CheckResult {
  blocked: boolean;
  hit: string | null;
  hits_count: number;

  constructor(blocked: boolean, hit: string | null, hits_count: number) {
    this.blocked = blocked;
    this.hit = hit;
    this.hits_count = hits_count;
  }
}

class MaskResultImpl implements MaskResult {
  masked: string;
  hits: string[];

  constructor(masked: string, hits: string[]) {
    this.masked = masked;
    this.hits = hits;
  }
}

export class ContentFilterService {
  /**
   * 网络状态检测（复用 EntryAbility 维护的全局状态）
   */
  static isOnline(): boolean {
    return (AppStorage.get('networkOnline') as boolean) ?? false;
  }

  /**
   * 单条文本内容安全审查
   * POST /check
   */
  static async check(text: string): Promise<CheckResult> {
    if (!text || text.trim().length === 0) {
      return new CheckResultImpl(false, null, 0);
    }

    const result = await ContentFilterService.requestCheck(
      FILTER_BASE_URL + '/check',
      new CheckIn(text.trim())
    );
    if (result === null) {
      // 网络不通或超时，不 fallback，直接抛错让上层阻止保存
      throw new Error('CONTENT_CHECK_NETWORK_ERROR');
    }
    return result;
  }

  /**
   * 批量文本内容安全审查（一次 HTTP 请求查多条）
   * POST /batch_check
   */
  static async batchCheck(texts: string[]): Promise<CheckResult[]> {
    if (!texts || texts.length === 0) {
      return [];
    }

    const nonEmpty = texts.map(t => t.trim()).filter(t => t.length > 0);
    if (nonEmpty.length === 0) {
      return [];
    }

    const result = await ContentFilterService.requestBatchCheck(new BatchCheckIn(nonEmpty));
    return result?.results ?? [];
  }

  /**
   * 内容脱敏（将敏感词替换为 maskChar）
   * POST /mask
   */
  static async mask(text: string, maskChar: string = '***'): Promise<MaskResult> {
    if (!text || text.trim().length === 0) {
      return new MaskResultImpl(text, []);
    }

    const result = await ContentFilterService.requestMask(
      FILTER_BASE_URL + '/mask',
      new MaskIn(text.trim(), maskChar)
    );
    return result ?? new MaskResultImpl(text, []);
  }

  private static async requestCheck(url: string, body: CheckIn): Promise<CheckResult | null> {
    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json' },
        extraData: JSON.stringify(body),
        readTimeout: 10000,
        connectTimeout: 10000,
        expectDataType: http.HttpDataType.OBJECT
      });

      if (response.responseCode === 200 || response.responseCode === 201) {
        return response.result as CheckResult;
      }
      hilog.error(DOMAIN, TAG, `ContentFilter /check failed: HTTP ${response.responseCode}`);
      return null;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `ContentFilter /check error: ${(err as BusinessError).message}`);
      return null;
    } finally {
      httpRequest.destroy();
    }
  }

  private static async requestMask(url: string, body: MaskIn): Promise<MaskResult | null> {
    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json' },
        extraData: JSON.stringify(body),
        readTimeout: 10000,
        connectTimeout: 10000,
        expectDataType: http.HttpDataType.OBJECT
      });

      if (response.responseCode === 200 || response.responseCode === 201) {
        return response.result as MaskResult;
      }
      hilog.error(DOMAIN, TAG, `ContentFilter /mask failed: HTTP ${response.responseCode}`);
      return null;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `ContentFilter /mask error: ${(err as BusinessError).message}`);
      return null;
    } finally {
      httpRequest.destroy();
    }
  }

  private static async requestBatchCheck(body: BatchCheckIn): Promise<BatchCheckOut | null> {
    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(FILTER_BASE_URL + '/batch_check', {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json' },
        extraData: JSON.stringify(body),
        readTimeout: 10000,
        connectTimeout: 10000,
        expectDataType: http.HttpDataType.OBJECT
      });

      if (response.responseCode === 200 || response.responseCode === 201) {
        return response.result as BatchCheckOut;
      }
      hilog.error(DOMAIN, TAG, `ContentFilter /batch_check failed: HTTP ${response.responseCode}`);
      return null;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `ContentFilter /batch_check error: ${(err as BusinessError).message}`);
      return null;
    } finally {
      httpRequest.destroy();
    }
  }
}