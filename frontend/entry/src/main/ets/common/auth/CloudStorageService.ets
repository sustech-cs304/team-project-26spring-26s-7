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
      // 先检查是否有现成的 AGC auth 会话（signInWithHuaweiID 已建立）
      // 如果有，直接复用，不再做 signOut/signIn（避免重新安装后 signIn 失败导致会话被破坏）
      const user = await auth.getCurrentUser()
      hilog.info(DOMAIN, TAG, `ensureReady: getCurrentUser=${user ? 'ok(uid=' + user.getUid() + ')' : 'null'}`)

      if (!user) {
        lastError = '当前未登录或会话失效'
        CloudStorageService.reset()
        hilog.error(DOMAIN, TAG, `ensureReady: no AGC user, skipping cloud storage init`)
        return false
      }

      const uid = user.getUid()

      // 缓存命中：直接复用
      if (cloudInitialized && storageBucket !== null && currentUid === uid) {
        hilog.info(DOMAIN, TAG, `ensureReady: cache hit, uid=${uid}`)
        lastError = ''
        return true
      }

      // 初始化 cloudCommon（依赖 signInWithHuaweiID 已建立的 AGC 会话）
      hilog.info(DOMAIN, TAG, `ensureReady: initializing cloud storage for uid=${uid}`)
      await CloudStorageService.logAuthProviderToken('init-before')
      cloudCommon.init({
        region: cloudCommon.CloudRegion.CHINA,
        authProvider: auth.getAuthProvider(),
        storageOptions: {
          mode: request.agent.Mode.BACKGROUND,
          network: request.agent.Network.ANY
        }
      })
      await CloudStorageService.logAuthProviderToken('init-after')
      storageBucket = cloudStorage.bucket()
      cloudInitialized = true
      currentUid = uid
      lastError = ''
      hilog.info(DOMAIN, TAG, `ensureReady: success, uid=${uid}`)
      return true
    } catch (err) {
      const error = err as BusinessError
      storageBucket = null
      cloudInitialized = false
      currentUid = ''
      lastError = error.message
      hilog.error(DOMAIN, TAG, `ensureReady: FAILED: ${error.code}, ${error.message}`)
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

  /**
   * 把一个本地文件路径在指定的 home 目录下落位。
   * homeDir 形如 `travels/<T>/nodes/<N>/`（注意末尾要有斜杠，由调用方保证）。
   */
  static buildNodePhotoPathInHomeDir(homeDir: string, localPath: string): string {
    return `${homeDir}${CloudStorageService.getFileName(localPath)}`
  }

  /**
   * 从 photoManifest（JSON 字符串）反推节点的 "home 目录"——即第一条云路径的 dirname，
   * 该目录就是这个节点首次上传时的 travel/node 落位。后续无论节点跨过多少次 travel，
   * 它的图片都继续落在这里，path 由 home 决定而非 currentTravelId。
   *
   * manifest 为空（节点从未上传过任何图）时退回到 currentTravelId/nodeId 拼出来的目录，
   * 表示"还没有 home，现在选一个"——之后第一次上传完成、manifest 写入，home 就此锁定。
   */
  static getNodeHomeDir(photoManifestJson: string, fallbackTravelId: string, nodeId: string): string {
    if (photoManifestJson && photoManifestJson.length > 2) {
      try {
        const parsed = JSON.parse(photoManifestJson) as Object
        if (Array.isArray(parsed) && parsed.length > 0) {
          const first = parsed[0] as string
          if (typeof first === 'string') {
            const slashIdx = first.lastIndexOf('/')
            if (slashIdx > 0) {
              return first.substring(0, slashIdx + 1)
            }
          }
        }
      } catch (_) {}
    }
    return CloudStorageService.buildNodePhotoDir(fallbackTravelId, nodeId)
  }

  static buildTravelPhotoRoot(travelId: string): string {
    return `travels/${travelId}/`
  }

  static buildNodePhotoDir(travelId: string, nodeId: string): string {
    return `travels/${travelId}/nodes/${nodeId}/`
  }

  /**
   * 暴露给上层：把一个本地路径或云路径里的最后一段（文件名）取出来。
   * RdbDataService / SyncManager 在按 home-dir 拼路径时需要。
   */
  static getFileNameFromPath(path: string): string {
    return CloudStorageService.getFileName(path)
  }

  // ========== Profile Avatar ==========

  static buildProfileAvatarPath(): string {
    // uid 只在 getUserScopedPath 那层加（users/{uid}/），这里不要重复
    return `profiles/avatar.jpg`
  }

  static async uploadProfileAvatar(uid: string, localPath: string): Promise<void> {
    // getUserScopedPath 会加上 users/{uid}/，最终路径：users/{uid}/profiles/avatar.jpg
    const cloudPath = CloudStorageService.buildProfileAvatarPath()
    await CloudStorageService.uploadFile(localPath, cloudPath)
    hilog.info(DOMAIN, TAG, `uploadProfileAvatar: uid=${uid}, cloudPath=${cloudPath}`)
  }

  static async downloadProfileAvatar(uid: string): Promise<string> {
    const cloudPath = CloudStorageService.buildProfileAvatarPath()
    const localPath = `downloaded/profile_avatar_${uid}.jpg`
    // 走 getUserScopedPath 包装，与 uploadProfileAvatar 保持一致
    await CloudStorageService.downloadFile(cloudPath, localPath)
    hilog.info(DOMAIN, TAG, `downloadProfileAvatar: uid=${uid}`)
    return CloudStorageService.normalizeCachePath(localPath)
  }

  // 直接上传到云端（不经过 getUserScopedPath），用于 profiles 等已包含 user scope 的路径
  static async uploadFileWithoutUserScope(localPath: string, cloudPath: string): Promise<void> {
    hilog.info(DOMAIN, TAG, `uploadFileWithoutUserScope: START localPath="${localPath}", cloudPath="${cloudPath}"`)
    hilog.info(DOMAIN, TAG, `uploadFileWithoutUserScope: appContext is ${appContext === null ? 'NULL' : 'SET'}`)

    const ready = await CloudStorageService.ensureReady()
    if (!ready) {
      const err = CloudStorageService.getLastError() || '云存储未初始化'
      hilog.error(DOMAIN, TAG, `uploadFileWithoutUserScope: ensureReady failed, error="${err}"`)
      throw new Error(err)
    }
    if (appContext === null) {
      hilog.error(DOMAIN, TAG, `uploadFileWithoutUserScope: appContext is NULL, cannot proceed`)
      throw new Error('应用上下文未初始化')
    }

    let cacheRelativePath = ''
    try {
      cacheRelativePath = CloudStorageService.prepareUploadSource(appContext, localPath)
      hilog.info(DOMAIN, TAG, `uploadFileWithoutUserScope: prepareUploadSource returned="${cacheRelativePath}"`)
    } catch (err) {
      const error = err as Error
      hilog.error(DOMAIN, TAG, `uploadFileWithoutUserScope: prepareUploadSource FAILED: ${error.message}`)
      throw error
    }

    // cloudPath 直接使用，不加 users/{uid}/ 前缀
    const fullCloudPath = cloudPath.startsWith('/') ? cloudPath.substring(1) : cloudPath
    hilog.info(DOMAIN, TAG, `uploadFileWithoutUserScope: fullCloudPath="${fullCloudPath}"`)

    await CloudStorageService.logAuthProviderToken('upload')

    await new Promise<void>((resolve, reject) => {
      hilog.info(DOMAIN, TAG, `uploadFileWithoutUserScope: calling getBucket().uploadFile() with localPath="${cacheRelativePath}"`)
      CloudStorageService.getBucket().uploadFile(appContext, {
        localPath: cacheRelativePath,
        cloudPath: fullCloudPath,
        mode: request.agent.Mode.BACKGROUND
      }).then((task: request.agent.Task) => {
        hilog.info(DOMAIN, TAG, `uploadFileWithoutUserScope: uploadFile() Promise resolved, task=${task !== null ? 'OK' : 'NULL'}`)
        task.on('completed', () => {
          hilog.info(DOMAIN, TAG, `UploadWithoutUserScope completed: ${fullCloudPath}`)
          resolve()
        })
        task.on('failed', (progress: Object) => {
          hilog.error(DOMAIN, TAG, `UploadWithoutUserScope failed: ${JSON.stringify(progress)}`)
          reject(new Error(`上传失败: ${JSON.stringify(progress)}`))
        })
        task.start((err: BusinessError) => {
          if (err) {
            hilog.error(DOMAIN, TAG, `UploadWithoutUserScope start error: code=${err.code}, message=${err.message}`)
            reject(new Error(`启动上传失败: ${err.message}`))
            return
          }
          hilog.info(DOMAIN, TAG, `UploadWithoutUserScope started: ${fullCloudPath}`)
        })
      }).catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, `uploadFileWithoutUserScope: uploadFile Promise rejected: code=${err.code}, message=${err.message}`)
        reject(new Error(`上传异常: ${err.message}`))
      })
    })
  }

  // 直接从云端下载（不经过 getUserScopedPath），用于 profiles 等已包含 user scope 的路径
  static async downloadFileWithoutUserScope(cloudPath: string, localRelativePath: string): Promise<void> {
    const ready = await CloudStorageService.ensureReady()
    if (!ready) {
      throw new Error(CloudStorageService.getLastError() || '云存储未初始化')
    }
    if (appContext === null) {
      throw new Error('应用上下文未初始化')
    }

    // cloudPath 直接使用，不加 users/{uid}/ 前缀
    const fullCloudPath = cloudPath.startsWith('/') ? cloudPath.substring(1) : cloudPath
    await CloudStorageService.ensureLocalParentDir(appContext, localRelativePath)

    await new Promise<void>((resolve, reject) => {
      CloudStorageService.getBucket().downloadFile(appContext, {
        cloudPath: fullCloudPath,
        localPath: localRelativePath,
        overwrite: true,
        mode: request.agent.Mode.BACKGROUND
      }).then((task: request.agent.Task) => {
        task.on('completed', () => {
          hilog.info(DOMAIN, TAG, `DownloadWithoutUserScope completed: ${fullCloudPath}`)
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
          hilog.info(DOMAIN, TAG, `DownloadWithoutUserScope started: ${fullCloudPath}`)
        })
      }).catch((err: BusinessError) => {
        reject(new Error(`下载异常: ${err.message}`))
      })
    })
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

  static async copyNodePhoto(fromTravelId: string, toTravelId: string, nodeId: string, localPath: string): Promise<void> {
    if (fromTravelId === toTravelId) {
      return
    }
    if (appContext === null) {
      throw new Error('应用上下文未初始化')
    }
    const sourceCloudPath = CloudStorageService.buildNodePhotoPath(fromTravelId, nodeId, localPath)
    const targetCloudPath = CloudStorageService.buildNodePhotoPath(toTravelId, nodeId, localPath)
    const fileName = `${Date.now()}_${CloudStorageService.getFileName(localPath)}`
    const tempRelativePath = `migrate/${fileName}`
    await CloudStorageService.downloadFile(sourceCloudPath, tempRelativePath)
    const tempLocalPath = CloudStorageService.normalizeCachePath(tempRelativePath)
    try {
      await CloudStorageService.uploadFile(tempLocalPath, targetCloudPath)
    } finally {
      try {
        fs.unlinkSync(tempLocalPath)
      } catch (_) {}
    }
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
      hilog.info(DOMAIN, TAG, `prepareUploadSource: copying from "${normalizedLocalPath}" to "${cacheTargetPath}"`)
      const sourceFile = fs.openSync(normalizedLocalPath, fs.OpenMode.READ_ONLY)
      const targetFile = fs.openSync(cacheTargetPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC)
      fs.copyFileSync(sourceFile.fd, targetFile.fd)
      fs.closeSync(sourceFile)
      fs.closeSync(targetFile)
      hilog.info(DOMAIN, TAG, `prepareUploadSource: copy done, fileSize=${fs.statSync(cacheTargetPath).size}`)
    }

    hilog.info(DOMAIN, TAG, `Prepared upload source: fullPath="${cacheTargetPath}", relativePath="${fileName}"`)
    return fileName
  }

  private static getFileName(localPath: string): string {
    const normalizedLocalPath = CloudStorageService.normalizeLocalPath(localPath)
    const pathParts = normalizedLocalPath.split('/')
    return pathParts[pathParts.length - 1]
  }
}
