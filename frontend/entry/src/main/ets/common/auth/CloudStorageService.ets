import { cloudCommon, cloudStorage } from '@kit.CloudFoundationKit'
import { request, BusinessError } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import auth from '@hw-agconnect/auth'

const DOMAIN = 0x0000
const TAG = 'CloudStorageService'

let storageBucket: cloudStorage.StorageBucket | null = null
let cloudInitialized: boolean = false
let currentUid: string = ''
let lastError: string = ''

export class CloudStorageService {
  static async ensureReady(): Promise<boolean> {
    try {
      const user = await auth.getCurrentUser()
      if (!user) {
        lastError = '当前未登录'
        CloudStorageService.reset()
        return false
      }

      const uid = user.getUid()
      if (cloudInitialized && storageBucket !== null && currentUid === uid) {
        lastError = ''
        return true
      }

      cloudCommon.init({
        region: cloudCommon.CloudRegion.CHINA,
        authProvider: auth.getAuthProvider(),
        storageOptions: {
          mode: request.agent.Mode.BACKGROUND,
          network: request.agent.Network.ANY
        }
      })
      storageBucket = cloudStorage.bucket()
      cloudInitialized = true
      currentUid = uid
      lastError = ''
      hilog.info(DOMAIN, TAG, `Cloud storage initialized for uid: ${uid}`)
      return true
    } catch (err) {
      const error = err as BusinessError
      storageBucket = null
      cloudInitialized = false
      currentUid = ''
      lastError = error.message
      hilog.error(DOMAIN, TAG, `Failed to initialize cloud storage: ${error.message}`)
      return false
    }
  }

  static reset(): void {
    storageBucket = null
    cloudInitialized = false
    currentUid = ''
  }

  static isReady(): boolean {
    return cloudInitialized && storageBucket !== null
  }

  static getUid(): string {
    return currentUid
  }

  static getLastError(): string {
    return lastError
  }

  static getStatusText(): string {
    if (CloudStorageService.isReady()) {
      return '云存储已连接'
    }
    if (lastError.length > 0) {
      return '云存储暂不可用'
    }
    return '云存储未连接'
  }

  static getBucket(): cloudStorage.StorageBucket {
    if (storageBucket === null) {
      throw new Error('云存储未初始化')
    }
    return storageBucket
  }

  static getUserScopedPath(path: string): string {
    const normalizedPath = path.startsWith('/') ? path.substring(1) : path
    return `users/${currentUid}/${normalizedPath}`
  }
}
