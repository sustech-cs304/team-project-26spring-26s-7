import { common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { preferences } from '@kit.ArkData'
import { http } from '@kit.NetworkKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import auth from '@hw-agconnect/auth'
import { IMAGE_CENSOR_BASE_URL } from '../api/ApiEndpoints'

const DOMAIN = 0x0000
const TAG = 'AppSessionManager'
const STORE_NAME = 'audit_app_session_v1'
const KEY_TOKEN = 'appSessionToken'
const KEY_UID = 'uid'
const KEY_EXPIRES_AT = 'expiresAt'
const EXPIRY_LEEWAY_SEC = 60

interface AgcLoginResp {
  app_session_token?: string
  issued_at?: number
  expires_in?: number
  uid?: string
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

export class AppSessionManager {
  private static context: common.UIAbilityContext | null = null
  private static loaded: boolean = false
  private static token: string = ''
  private static uid: string = ''
  private static expiresAt: number = 0
  private static loadingPromise: Promise<void> | null = null

  static init(context: common.UIAbilityContext): void {
    AppSessionManager.context = context
  }

  static async save(uid: string, token: string, issuedAt: number, expiresIn: number): Promise<void> {
    AppSessionManager.uid = uid
    AppSessionManager.token = token
    AppSessionManager.expiresAt = issuedAt + expiresIn - EXPIRY_LEEWAY_SEC
    AppSessionManager.loaded = true
    await AppSessionManager.persist()
  }

  static async getToken(expectedUid: string = ''): Promise<string | null> {
    await AppSessionManager.ensureLoaded()

    const now = Math.floor(Date.now() / 1000)
    if (!AppSessionManager.token || AppSessionManager.expiresAt <= now) {
      await AppSessionManager.clear()
      return null
    }

    if (expectedUid && AppSessionManager.uid && AppSessionManager.uid !== expectedUid) {
      await AppSessionManager.clear()
      return null
    }

    return AppSessionManager.token
  }

  static async refreshFromAgcAuth(expectedUid: string = ''): Promise<string | null> {
    let uid = ''
    let agcAccessToken = ''
    try {
      const user = await auth.getCurrentUser()
      if (!user) {
        hilog.warn(DOMAIN, TAG, 'refreshFromAgcAuth skipped: AGC user missing')
        return null
      }
      uid = user.getUid()
      if (expectedUid && uid !== expectedUid) {
        hilog.warn(DOMAIN, TAG, `refreshFromAgcAuth uid mismatch, expected=${expectedUid}, actual=${uid}`)
        await AppSessionManager.clear()
        return null
      }
      const tokenResult = await user.getToken(true)
      agcAccessToken = tokenResult.getString()
    } catch (err) {
      const error = err as BusinessError
      hilog.error(DOMAIN, TAG, `refreshFromAgcAuth get AGC token failed: ${error.message ?? JSON.stringify(err)}`)
      return null
    }

    if (!agcAccessToken) {
      hilog.error(DOMAIN, TAG, 'refreshFromAgcAuth missing AGC access token')
      return null
    }

    const httpRequest = http.createHttp()
    try {
      const response = await httpRequest.request(`${IMAGE_CENSOR_BASE_URL}/api/v1/auth/agc_login`, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json' },
        extraData: JSON.stringify({ access_token: agcAccessToken }),
        readTimeout: 15000,
        connectTimeout: 10000,
        expectDataType: http.HttpDataType.OBJECT
      })

      if (response.responseCode !== 200 && response.responseCode !== 201) {
        hilog.error(DOMAIN, TAG, `refreshFromAgcAuth failed: HTTP ${response.responseCode}, body=${stringifyHttpResult(response.result)}`)
        await AppSessionManager.clear()
        return null
      }

      const body = response.result as AgcLoginResp
      if (!body || !body.app_session_token || body.issued_at === undefined || body.expires_in === undefined) {
        hilog.error(DOMAIN, TAG, `refreshFromAgcAuth invalid response: ${JSON.stringify(response.result)}`)
        await AppSessionManager.clear()
        return null
      }

      await AppSessionManager.save(uid || body.uid || '', body.app_session_token, body.issued_at, body.expires_in)
      hilog.info(DOMAIN, TAG, `refreshFromAgcAuth success, expiresIn=${body.expires_in}`)
      return body.app_session_token
    } catch (err) {
      const error = err as BusinessError
      hilog.error(DOMAIN, TAG, `refreshFromAgcAuth error: ${error.message ?? JSON.stringify(err)}`)
      await AppSessionManager.clear()
      return null
    } finally {
      httpRequest.destroy()
    }
  }

  static async clear(): Promise<void> {
    AppSessionManager.token = ''
    AppSessionManager.uid = ''
    AppSessionManager.expiresAt = 0
    AppSessionManager.loaded = true

    const ctx = AppSessionManager.context
    if (!ctx) {
      return
    }

    try {
      const store = await preferences.getPreferences(ctx, { name: STORE_NAME })
      await store.delete(KEY_TOKEN)
      await store.delete(KEY_UID)
      await store.delete(KEY_EXPIRES_AT)
      await store.flush()
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `clear failed: ${JSON.stringify(err)}`)
    }
  }

  private static async ensureLoaded(): Promise<void> {
    if (AppSessionManager.loaded) {
      return
    }
    if (AppSessionManager.loadingPromise) {
      return AppSessionManager.loadingPromise
    }
    AppSessionManager.loadingPromise = AppSessionManager.load()
    return AppSessionManager.loadingPromise
  }

  private static async load(): Promise<void> {
    const ctx = AppSessionManager.context
    if (!ctx) {
      AppSessionManager.loaded = true
      AppSessionManager.loadingPromise = null
      return
    }

    try {
      const store = await preferences.getPreferences(ctx, { name: STORE_NAME })
      AppSessionManager.token = await store.get(KEY_TOKEN, '') as string
      AppSessionManager.uid = await store.get(KEY_UID, '') as string
      AppSessionManager.expiresAt = await store.get(KEY_EXPIRES_AT, 0) as number
      AppSessionManager.loaded = true
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `load failed: ${JSON.stringify(err)}`)
      AppSessionManager.loaded = true
    } finally {
      AppSessionManager.loadingPromise = null
    }
  }

  private static async persist(): Promise<void> {
    const ctx = AppSessionManager.context
    if (!ctx) {
      return
    }

    try {
      const store = await preferences.getPreferences(ctx, { name: STORE_NAME })
      await store.put(KEY_TOKEN, AppSessionManager.token)
      await store.put(KEY_UID, AppSessionManager.uid)
      await store.put(KEY_EXPIRES_AT, AppSessionManager.expiresAt)
      await store.flush()
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `persist failed: ${JSON.stringify(err)}`)
    }
  }
}
