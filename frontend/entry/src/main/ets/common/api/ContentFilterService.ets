import { http } from '@kit.NetworkKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { CONTENT_FILTER_BASE_URL } from './ApiEndpoints'
import { AiTokenManager } from './AiTokenManager'

const DOMAIN = 0x0000
const TAG = 'ContentFilterService'

export interface CheckResult {
  blocked: boolean
  hit: string | null
  hits_count: number
}

export interface MaskResult {
  masked: string
  hits: string[]
}

interface TextCheckIn {
  text: string
  user_id?: string
  user_ip?: string
}

interface TextHit {
  keyword?: string
  msg?: string
}

interface TextCheckOut {
  conclusion: string
  conclusionType: number
  log_id: number
  is_safe: boolean
  is_hit: boolean
  error_code?: number | null
  error_msg?: string | null
  data?: TextHit[]
}

class CheckResultImpl implements CheckResult {
  blocked: boolean
  hit: string | null
  hits_count: number

  constructor(blocked: boolean, hit: string | null, hits_count: number) {
    this.blocked = blocked
    this.hit = hit
    this.hits_count = hits_count
  }
}

class MaskResultImpl implements MaskResult {
  masked: string
  hits: string[]

  constructor(masked: string, hits: string[]) {
    this.masked = masked
    this.hits = hits
  }
}

export class ContentFilterService {
  static isOnline(): boolean {
    return (AppStorage.get('networkOnline') as boolean) ?? false
  }

  static async check(text: string): Promise<CheckResult> {
    const trimmed = text.trim()
    if (!trimmed) {
      return new CheckResultImpl(false, null, 0)
    }

    const result = await ContentFilterService.requestTextCheck({ text: trimmed })
    const hits = result.data ?? []
    const firstHit = hits.length > 0 ? (hits[0].keyword ?? hits[0].msg ?? result.conclusion) : null
    return new CheckResultImpl(!result.is_safe, firstHit, hits.length)
  }

  static async batchCheck(texts: string[]): Promise<CheckResult[]> {
    const results: CheckResult[] = []
    for (let i = 0; i < texts.length; i++) {
      if (texts[i].trim().length > 0) {
        results.push(await ContentFilterService.check(texts[i]))
      }
    }
    return results
  }

  static async mask(text: string, maskChar: string = '***'): Promise<MaskResult> {
    const result = await ContentFilterService.check(text)
    if (!result.blocked || !result.hit) {
      return new MaskResultImpl(text, [])
    }
    return new MaskResultImpl(text.replace(result.hit, maskChar), [result.hit])
  }

  private static async requestTextCheck(body: TextCheckIn, retry: boolean = true): Promise<TextCheckOut> {
    const token = await AiTokenManager.getCensorToken()
    const httpRequest = http.createHttp()

    try {
      const response = await httpRequest.request(`${CONTENT_FILTER_BASE_URL}/text_check`, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`
        },
        extraData: JSON.stringify(body),
        readTimeout: 30000,
        connectTimeout: 10000,
        expectDataType: http.HttpDataType.OBJECT
      })

      if (response.responseCode === 200 || response.responseCode === 201) {
        const result = response.result as TextCheckOut
        if (result.error_code !== undefined && result.error_code !== null) {
          hilog.error(DOMAIN, TAG, `text_check provider error: code=${result.error_code}, msg=${result.error_msg ?? ''}`)
          throw new Error('CONTENT_CHECK_NETWORK_ERROR')
        }
        return result
      }

      if (response.responseCode === 401 && retry) {
        AiTokenManager.invalidate()
        return ContentFilterService.requestTextCheck(body, false)
      }

      hilog.error(DOMAIN, TAG, `text_check failed: HTTP ${response.responseCode}, body=${JSON.stringify(response.result)}`)
      throw new Error('CONTENT_CHECK_NETWORK_ERROR')
    } catch (err) {
      const error = err as BusinessError
      if ((err as Error).message === 'AUDIT_AUTH_REQUIRED') {
        throw err as Error
      }
      if ((err as Error).message === 'CONTENT_CHECK_NETWORK_ERROR') {
        throw err as Error
      }
      hilog.error(DOMAIN, TAG, `text_check error: ${error.message ?? JSON.stringify(err)}`)
      throw new Error('CONTENT_CHECK_NETWORK_ERROR')
    } finally {
      httpRequest.destroy()
    }
  }
}
