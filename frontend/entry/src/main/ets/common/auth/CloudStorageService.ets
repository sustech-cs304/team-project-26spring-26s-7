import { common } from '@kit.AbilityKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { cloudCommon, cloudStorage } from '@kit.CloudFoundationKit'
import { request, BusinessError } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import auth from '@hw-agconnect/auth'
import { PhotoPickerUtil } from '../utils/PhotoPickerUtil'

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
    const normalizedPath = CloudStorageService.normalizeCloudPath(path)
    return `users/${currentUid}/${normalizedPath}`
  }

  static buildNodePhotoPath(travelId: string, nodeId: string, localPath: string): string {
    const fileName = CloudStorageService.getFileName(localPath)
    return `travels/${travelId}/nodes/${nodeId}/${fileName}`
  }

  static buildTravelPhotoRoot(travelId: string): string {
    return `travels/${travelId}/`
  }

  static buildNodePhotoDir(travelId: string, nodeId: string): string {
    return `travels/${travelId}/nodes/${nodeId}/`
  }

  static async deleteDirectoryRecursively(cloudPath: string): Promise<void> {
    const ready = await CloudStorageService.ensureReady()
    if (!ready) {
      throw new Error(CloudStorageService.getLastError() || '云存储未初始化')
    }

    try {
      const directories = await CloudStorageService.listDirectories(cloudPath)
      for (let i = 0; i < directories.length; i++) {
        await CloudStorageService.deleteDirectoryRecursively(`${cloudPath}${directories[i]}`)
      }

      const files = await CloudStorageService.listFiles(cloudPath)
      for (let i = 0; i < files.length; i++) {
        await CloudStorageService.deleteFile(`${cloudPath}${files[i]}`)
      }
      hilog.info(DOMAIN, TAG, `Delete directory completed: ${CloudStorageService.getUserScopedPath(cloudPath)}`)
    } catch (err) {
      const error = err as BusinessError
      hilog.warn(DOMAIN, TAG, `Skip deleting directory ${cloudPath}: ${error.message}`)
    }
  }

  static async listDirectories(cloudPath: string): Promise<string[]> {
    const ready = await CloudStorageService.ensureReady()
    if (!ready) {
      throw new Error(CloudStorageService.getLastError() || '云存储未初始化')
    }

    const fullCloudPath = CloudStorageService.getUserScopedPath(cloudPath)
    const result = await CloudStorageService.getBucket().list(fullCloudPath)
    const directories: string[] = []
    for (let i = 0; i < result.directories.length; i++) {
      directories.push(CloudStorageService.toRelativeListEntry(fullCloudPath, result.directories[i]))
    }
    return directories
  }

  static async listFiles(cloudPath: string): Promise<string[]> {
    const ready = await CloudStorageService.ensureReady()
    if (!ready) {
      throw new Error(CloudStorageService.getLastError() || '云存储未初始化')
    }

    const fullCloudPath = CloudStorageService.getUserScopedPath(cloudPath)
    const result = await CloudStorageService.getBucket().list(fullCloudPath)
    const files: string[] = []
    for (let i = 0; i < result.files.length; i++) {
      files.push(CloudStorageService.toRelativeListEntry(fullCloudPath, result.files[i]))
    }
    return files
  }

  static async downloadFile(cloudPath: string, localRelativePath: string): Promise<void> {
    const ready = await CloudStorageService.ensureReady()
    if (!ready) {
      throw new Error(CloudStorageService.getLastError() || '云存储未初始化')
    }
    if (appContext === null) {
      throw new Error('应用上下文未初始化')
    }

    const fullCloudPath = CloudStorageService.getUserScopedPath(cloudPath)
    await CloudStorageService.ensureLocalParentDir(appContext, localRelativePath)

    await new Promise<void>((resolve, reject) => {
      CloudStorageService.getBucket().downloadFile(appContext, {
        cloudPath: fullCloudPath,
        localPath: localRelativePath,
        overwrite: true,
        mode: request.agent.Mode.BACKGROUND
      }).then((task: request.agent.Task) => {
        task.on('completed', () => {
          hilog.info(DOMAIN, TAG, `Download completed: ${fullCloudPath}`)
          resolve()
        })
        task.on('failed', (progress: Object) => {
          reject(new Error(`下载失败: ${JSON.stringify(progress)}`))
        })
        task.start((err: BusinessError) => {
          if (err) {
            reject(new Error(`启动下载失败: ${err.message}`))
            return
          }
          hilog.info(DOMAIN, TAG, `Download task started: ${fullCloudPath}`)
        })
      }).catch((err: BusinessError) => {
        reject(new Error(`下载异常: ${err.message}`))
      })
    })
  }

  static async downloadNodePhotoToSandbox(cloudPath: string): Promise<string> {
    if (appContext === null) {
      throw new Error('应用上下文未初始化')
    }
    const normalizedCloudPath = CloudStorageService.normalizeCloudPath(cloudPath)
    const fileName = normalizedCloudPath.substring(normalizedCloudPath.lastIndexOf('/') + 1)
    const cacheRelativePath = `downloaded/${fileName}`
    await CloudStorageService.downloadFile(normalizedCloudPath, cacheRelativePath)

    const cacheFullPath = CloudStorageService.normalizeCachePath(cacheRelativePath)
    const sandboxDir = PhotoPickerUtil.getSandboxPhotoDir(appContext)
    const targetPath = `${sandboxDir}/${fileName}`
    try {
      fs.mkdirSync(sandboxDir, true)
    } catch (_) {}

    const sourceFile = fs.openSync(cacheFullPath, fs.OpenMode.READ_ONLY)
    const targetFile = fs.openSync(targetPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC)
    fs.copyFileSync(sourceFile.fd, targetFile.fd)
    fs.closeSync(sourceFile)
    fs.closeSync(targetFile)
    hilog.info(DOMAIN, TAG, `Copied downloaded photo to sandbox: ${targetPath}`)
    return `file://${targetPath}`
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

  static normalizeCachePath(localRelativePath: string): string {
    if (appContext === null) {
      return localRelativePath
    }
    return `${appContext.cacheDir}/${localRelativePath}`
  }

  private static toRelativeListEntry(baseCloudPath: string, entry: string): string {
    let normalizedEntry = CloudStorageService.normalizeCloudPath(entry)
    const normalizedBase = CloudStorageService.normalizeCloudPath(baseCloudPath)
    if (normalizedEntry.startsWith(normalizedBase)) {
      normalizedEntry = normalizedEntry.substring(normalizedBase.length)
    }
    return normalizedEntry.startsWith('/') ? normalizedEntry.substring(1) : normalizedEntry
  }

  private static normalizeCloudPath(path: string): string {
    let normalizedPath = path.startsWith('/') ? path.substring(1) : path
    const userPrefix = `users/${currentUid}/`
    if (normalizedPath.startsWith(userPrefix)) {
      normalizedPath = normalizedPath.substring(userPrefix.length)
    }
    return normalizedPath
  }

  private static normalizeLocalPath(localPath: string): string {
    return localPath.startsWith('file://') ? localPath.substring(7) : localPath
  }

  private static ensureLocalParentDir(context: common.UIAbilityContext, localRelativePath: string): void {
    const lastSlashIndex = localRelativePath.lastIndexOf('/')
    if (lastSlashIndex < 0) {
      return
    }

    const parentRelativePath = localRelativePath.substring(0, lastSlashIndex)
    if (parentRelativePath.length === 0) {
      return
    }

    const parentFullPath = `${context.cacheDir}/${parentRelativePath}`
    try {
      fs.mkdirSync(parentFullPath, true)
    } catch (_) {}
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
