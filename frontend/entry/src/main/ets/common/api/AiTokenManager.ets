import { http } from '@kit.NetworkKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { BusinessError } from '@kit.BasicServicesKit'
import auth from '@hw-agconnect/auth'

import { API_BASE_URL, IMAGE_CENSOR_BASE_URL, VISION_LLM_BASE_URL } from './ApiEndpoints'
import { AppSessionManager } from '../auth/AppSessionManager'

const DOMAIN = 0x0000
const TAG = 'AiTokenManager'
const EXPIRY_LEEWAY_SEC = 60

interface AuditIssueResp {
  filter_token?: string
  censor_token?: string
  issued_at?: number
  expires_in?: number
}

interface CachedAuditTokens {
  filter: string
  censor: string
  expiresAt: number
}

interface VisionIssueResp {
  vision_token?: string
  issued_at?: number
  expires_in?: number
}

interface CachedVisionToken {
  token: string
  expiresAt: number
}

interface ShareIssueResp {
  share_token?: string
  issued_at?: number
  expires_in?: number
}

interface CachedShareToken {
  token: string
  expiresAt: number
}

function stringifyHttpResult(result: Object | string | ArrayBuffer | undefined): string {
  if (result === undefined || result === null) {
    return ''
  }
  if (typeof result === 'string') {
    return result
  }
  try {
    return JSON.stringify(result)
  } catch (_) {
    return String(result)
  }
}

let auditCached: CachedAuditTokens | null = null
let auditInflight: Promise<CachedAuditTokens> | null = null
let visionCached: CachedVisionToken | null = null
let visionInflight: Promise<CachedVisionToken> | null = null
let shareCached: CachedShareToken | null = null
let shareInflight: Promise<CachedShareToken> | null = null

async function fetchAuditTokens(): Promise<CachedAuditTokens> {
  let appSessionToken = await AppSessionManager.getToken()
  if (!appSessionToken) {
    appSessionToken = await AppSessionManager.refreshFromAgcAuth()
  }
  if (!appSessionToken) {
    throw new Error('AUDIT_AUTH_REQUIRED')
  }
  const httpReq = http.createHttp()

  try {
    const response = await httpReq.request(`${IMAGE_CENSOR_BASE_URL}/api/v1/auth/issue_audit_token`, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${appSessionToken}`
      },
      readTimeout: 10000,
      connectTimeout: 10000,
      expectDataType: http.HttpDataType.OBJECT,
      extraData: JSON.stringify({})
    })

    if (response.responseCode !== 200 && response.responseCode !== 201) {
      hilog.error(DOMAIN, TAG, `issue_audit_token failed: HTTP ${response.responseCode}, body=${stringifyHttpResult(response.result)}`)
      throw new Error('AUDIT_TOKEN_REQUEST_FAILED')
    }

    const body = response.result as AuditIssueResp
    if (!body || !body.filter_token || !body.censor_token) {
      hilog.error(DOMAIN, TAG, `issue_audit_token invalid response: ${stringifyHttpResult(response.result)}`)
      throw new Error('AUDIT_TOKEN_INVALID_RESPONSE')
    }

    const ttl = body.expires_in ?? 1800
    const issued = body.issued_at ?? Math.floor(Date.now() / 1000)
    return {
      filter: body.filter_token,
      censor: body.censor_token,
      expiresAt: issued + ttl - EXPIRY_LEEWAY_SEC
    }
  } catch (err) {
    const be = err as BusinessError
    hilog.error(DOMAIN, TAG, `issue_audit_token error: ${be?.message ?? JSON.stringify(err)}`)
    throw err as Error
  } finally {
    httpReq.destroy()
  }
}

async function getAuditTokens(): Promise<CachedAuditTokens> {
  const now = Math.floor(Date.now() / 1000)
  if (auditCached && auditCached.expiresAt > now) {
    return auditCached
  }

  if (auditInflight) {
    return auditInflight
  }

  const promise = fetchAuditTokens()
  auditInflight = promise
  try {
    const tokens = await promise
    auditCached = tokens
    return tokens
  } finally {
    auditInflight = null
  }
}


async function fetchVisionToken(): Promise<CachedVisionToken> {
  // AGC 登录 → app_session_token → ai-relay /v1/auth/issue_vision_token → vision_token
  // 未登录或获取失败时抛出异常，不使用任何回退凭据
  let appSessionToken = await AppSessionManager.getToken()
  if (!appSessionToken) {
    appSessionToken = await AppSessionManager.refreshFromAgcAuth()
  }
  if (!appSessionToken) {
    hilog.error(DOMAIN, TAG, 'vision token: no app session')
    throw new Error('VISION_AUTH_REQUIRED')
  }

  const httpReq = http.createHttp()
  try {
    const response = await httpReq.request(`${VISION_LLM_BASE_URL}/v1/auth/issue_vision_token`, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${appSessionToken}`
      },
      readTimeout: 10000,
      connectTimeout: 10000,
      expectDataType: http.HttpDataType.OBJECT,
      extraData: JSON.stringify({})
    })

    if (response.responseCode !== 200 && response.responseCode !== 201) {
      hilog.error(DOMAIN, TAG, `issue_vision_token http ${response.responseCode}, body=${stringifyHttpResult(response.result)}`)
      throw new Error('VISION_TOKEN_REQUEST_FAILED')
    }

    const body = response.result as VisionIssueResp
    if (!body || !body.vision_token) {
      hilog.error(DOMAIN, TAG, `issue_vision_token missing vision_token: ${stringifyHttpResult(response.result)}`)
      throw new Error('VISION_TOKEN_INVALID_RESPONSE')
    }

    const ttl = body.expires_in ?? 1800
    const issued = body.issued_at ?? Math.floor(Date.now() / 1000)
    return {
      token: body.vision_token,
      expiresAt: issued + ttl - EXPIRY_LEEWAY_SEC
    }
  } catch (err) {
    const be = err as BusinessError
    hilog.error(DOMAIN, TAG, `issue_vision_token error: ${be?.message ?? JSON.stringify(err)}`)
    throw err as Error
  } finally {
    httpReq.destroy()
  }
}

async function fetchShareToken(): Promise<CachedShareToken> {
  // AGC 登录 → app_session_token → 调 share-service /api/v1/auth/issue_share_token
  // 未登录 → 抛错（调用方决定如何兜底；ShareService 当前会回落到不带 token，由后端 ALLOW_DEV_UID_HEADER 兜底）
  let appSessionToken = await AppSessionManager.getToken()
  if (!appSessionToken) {
    appSessionToken = await AppSessionManager.refreshFromAgcAuth()
  }
  if (!appSessionToken) {
    throw new Error('SHARE_AUTH_REQUIRED')
  }

  const httpReq = http.createHttp()
  try {
    const response = await httpReq.request(`${API_BASE_URL}/api/v1/auth/issue_share_token`, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${appSessionToken}`
      },
      readTimeout: 10000,
      connectTimeout: 10000,
      expectDataType: http.HttpDataType.OBJECT,
      extraData: JSON.stringify({})
    })

    if (response.responseCode !== 200 && response.responseCode !== 201) {
      hilog.error(DOMAIN, TAG, `issue_share_token http ${response.responseCode}, body=${stringifyHttpResult(response.result)}`)
      throw new Error('SHARE_TOKEN_REQUEST_FAILED')
    }

    const body = response.result as ShareIssueResp
    if (!body || !body.share_token) {
      hilog.error(DOMAIN, TAG, `issue_share_token invalid response: ${stringifyHttpResult(response.result)}`)
      throw new Error('SHARE_TOKEN_INVALID_RESPONSE')
    }

    const ttl = body.expires_in ?? 1800
    const issued = body.issued_at ?? Math.floor(Date.now() / 1000)
    return {
      token: body.share_token,
      expiresAt: issued + ttl - EXPIRY_LEEWAY_SEC
    }
  } catch (err) {
    const be = err as BusinessError
    hilog.error(DOMAIN, TAG, `issue_share_token error: ${be?.message ?? JSON.stringify(err)}`)
    throw err as Error
  } finally {
    httpReq.destroy()
  }
}

async function getVisionTokenCached(): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  if (visionCached && visionCached.expiresAt > now) {
    return visionCached.token
  }

  if (visionInflight) {
    return (await visionInflight).token
  }

  const promise = fetchVisionToken()
  visionInflight = promise
  try {
    const token = await promise
    visionCached = token
    return token.token
  } finally {
    visionInflight = null
  }
}

async function getShareTokenCached(): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  if (shareCached && shareCached.expiresAt > now) {
    return shareCached.token
  }

  if (shareInflight) {
    return (await shareInflight).token
  }

  const promise = fetchShareToken()
  shareInflight = promise
  try {
    const token = await promise
    shareCached = token
    return token.token
  } finally {
    shareInflight = null
  }
}

export class AiTokenManager {
  static async getVisionToken(): Promise<string> {
    return getVisionTokenCached()
  }

  static async getFilterToken(): Promise<string> {
    return (await getAuditTokens()).filter
  }

  static async getCensorToken(): Promise<string> {
    return (await getAuditTokens()).censor
  }

  /** 拿 share-service publish/revoke 用的 Bearer token */
  static async getShareToken(): Promise<string> {
    return getShareTokenCached()
  }

  /** 静默版本：失败返回 null 而不是抛，调用方可以选择回落到匿名调用 */
  static async tryGetShareToken(): Promise<string | null> {
    try {
      return await getShareTokenCached()
    } catch (_) {
      return null
    }
  }

  static invalidate(): void {
    auditCached = null
    visionCached = null
    shareCached = null
  }
}
