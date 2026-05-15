import { http } from '@kit.NetworkKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { BusinessError } from '@kit.BasicServicesKit'
import auth from '@hw-agconnect/auth'

import { API_BASE_URL, IMAGE_CENSOR_BASE_URL } from './ApiEndpoints'
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

interface AiIssueResp {
  vision_token?: string
  issued_at?: number
  expires_in?: number
}

interface CachedVisionToken {
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

const FALLBACK_DEV_TOKEN = 'DEV_05436de19d4ad0029b4d722b9288167b'
let auditCached: CachedAuditTokens | null = null
let auditInflight: Promise<CachedAuditTokens> | null = null
let visionCached: CachedVisionToken | null = null
let visionInflight: Promise<CachedVisionToken> | null = null

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

function makeVisionFallback(): CachedVisionToken {
  return {
    token: FALLBACK_DEV_TOKEN,
    expiresAt: Math.floor(Date.now() / 1000) + 60
  }
}

async function fetchVisionToken(): Promise<CachedVisionToken> {
  let uid = ''
  try {
    const user = await auth.getCurrentUser()
    uid = user?.getUid() ?? ''
  } catch (err) {
    hilog.warn(DOMAIN, TAG, `get AGC user failed for vision token: ${JSON.stringify(err)}`)
  }

  if (!uid) {
    return makeVisionFallback()
  }

  const httpReq = http.createHttp()
  try {
    const response = await httpReq.request(`${API_BASE_URL}/api/v1/auth/issue_ai_token`, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'X-Dev-Uid': uid
      },
      readTimeout: 10000,
      connectTimeout: 10000,
      expectDataType: http.HttpDataType.OBJECT,
      extraData: ''
    })

    if (response.responseCode !== 200 && response.responseCode !== 201) {
      hilog.warn(DOMAIN, TAG, `issue_ai_token http ${response.responseCode}, fallback`)
      return makeVisionFallback()
    }

    const body = response.result as AiIssueResp
    if (!body || !body.vision_token) {
      hilog.warn(DOMAIN, TAG, 'issue_ai_token missing vision_token, fallback')
      return makeVisionFallback()
    }

    const ttl = body.expires_in ?? 1800
    const issued = body.issued_at ?? Math.floor(Date.now() / 1000)
    return {
      token: body.vision_token,
      expiresAt: issued + ttl - EXPIRY_LEEWAY_SEC
    }
  } catch (err) {
    const be = err as BusinessError
    hilog.warn(DOMAIN, TAG, `issue_ai_token error: ${be?.message ?? JSON.stringify(err)}, fallback`)
    return makeVisionFallback()
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

  static invalidate(): void {
    auditCached = null
    visionCached = null
  }
}
