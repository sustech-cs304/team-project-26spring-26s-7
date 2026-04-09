import { common } from '@kit.AbilityKit'
import { fileIo as fs } from '@kit.CoreFileKit'
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
let appContext: common.UIAbilityContext | null = null

export class CloudStorageService {
  static setContext(context: common.UIAbilityContext): void {
    appContext = context
  }

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

      try {
        await auth.signOut()
        hilog.info(DOMAIN, TAG, 'Signed out previous AGC session before cloud init')
      } catch (_) {
        hilog.info(DOMAIN, TAG, 'No previous AGC session to sign out before cloud init')
      }

      const signInResult = await auth.signIn({
        credentialInfo: { kind: 'hwid' },
        autoCreateUser: true
      })
      const signedInUid = signInResult.getUser().getUid()
      hilog.info(DOMAIN, TAG, `AGC hwid signIn success, uid: ${signedInUid}`)
      await CloudStorageService.logAuthProviderToken('ensureReady')

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
      currentUid = signedInUid
      lastError = ''
      hilog.info(DOMAIN, TAG, `Cloud storage initialized for uid: ${signedInUid}`)
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

  static buildNodePhotoPath(travelId: string, nodeId: string, localPath: string): string {
    const fileName = CloudStorageService.getFileName(localPath)
    return `travels/${travelId}/nodes/${nodeId}/${fileName}`
  }

  static async uploadNodePhoto(travelId: string, nodeId: string, localPath: string): Promise<void> {
    const cloudPath = CloudStorageService.buildNodePhotoPath(travelId, nodeId, localPath)
    await CloudStorageService.uploadFile(localPath, cloudPath)
  }

  static async deleteNodePhoto(travelId: string, nodeId: string, localPath: string): Promise<void> {
    const cloudPath = CloudStorageService.buildNodePhotoPath(travelId, nodeId, localPath)
    await CloudStorageService.deleteFile(cloudPath)
  }

  static async uploadFile(localPath: string, cloudPath: string): Promise<void> {
    const ready = await CloudStorageService.ensureReady()
    if (!ready) {
      throw new Error(CloudStorageService.getLastError() || '云存储未初始化')
    }
    if (appContext === null) {
      throw new Error('应用上下文未初始化')
    }

    const cacheRelativePath = CloudStorageService.prepareUploadSource(appContext, localPath)
    const fullCloudPath = CloudStorageService.getUserScopedPath(cloudPath)
    await CloudStorageService.logAuthProviderToken('upload')

    await new Promise<void>((resolve, reject) => {
      CloudStorageService.getBucket().uploadFile(appContext, {
        localPath: cacheRelativePath,
        cloudPath: fullCloudPath,
        mode: request.agent.Mode.BACKGROUND
      }).then((task: request.agent.Task) => {
        task.on('completed', () => {
          hilog.info(DOMAIN, TAG, `Upload completed: ${fullCloudPath}`)
          resolve()
        })
        task.on('failed', (progress: Object) => {
          reject(new Error(`上传失败: ${JSON.stringify(progress)}`))
        })
        task.start((err: BusinessError) => {
          if (err) {
            reject(new Error(`启动上传失败: ${err.message}`))
            return
          }
          hilog.info(DOMAIN, TAG, `Upload task started: ${fullCloudPath}`)
        })
      }).catch((err: BusinessError) => {
        reject(new Error(`上传异常: ${err.message}`))
      })
    })
  }

  static async deleteFile(cloudPath: string): Promise<void> {
    const ready = await CloudStorageService.ensureReady()
    if (!ready) {
      throw new Error(CloudStorageService.getLastError() || '云存储未初始化')
    }

    const fullCloudPath = CloudStorageService.getUserScopedPath(cloudPath)
    await CloudStorageService.getBucket().deleteFile(fullCloudPath)
    hilog.info(DOMAIN, TAG, `Delete completed: ${fullCloudPath}`)
  }

  private static async logAuthProviderToken(stage: string): Promise<void> {
    try {
      const token = await auth.getAuthProvider().getAccessToken(false)
      hilog.info(DOMAIN, TAG, `Auth token ready at ${stage}, uid=${currentUid}, length=${token.length}`)
    } catch (err) {
      const error = err as BusinessError
      hilog.error(DOMAIN, TAG, `Failed to get auth token at ${stage}: ${error.code}, ${error.message}`)
    }
  }

  private static normalizeLocalPath(localPath: string): string {
    return localPath.startsWith('file://') ? localPath.substring(7) : localPath
  }

  private static prepareUploadSource(context: common.UIAbilityContext, localPath: string): string {
    const normalizedLocalPath = CloudStorageService.normalizeLocalPath(localPath)
    const fileName = `${Date.now()}_${CloudStorageService.getFileName(normalizedLocalPath)}`
    const cacheTargetPath = `${context.cacheDir}/${fileName}`

    if (normalizedLocalPath !== cacheTargetPath) {
      const sourceFile = fs.openSync(normalizedLocalPath, fs.OpenMode.READ_ONLY)
      const targetFile = fs.openSync(cacheTargetPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC)
      fs.copyFileSync(sourceFile.fd, targetFile.fd)
      fs.closeSync(sourceFile)
      fs.closeSync(targetFile)
    }

    hilog.info(DOMAIN, TAG, `Prepared upload source in cacheDir: ${cacheTargetPath}`)
    return fileName
  }

  private static getFileName(localPath: string): string {
    const normalizedLocalPath = CloudStorageService.normalizeLocalPath(localPath)
    const pathParts = normalizedLocalPath.split('/')
    return pathParts[pathParts.length - 1]
  }
}
