import { common } from '@kit.AbilityKit';
import { authentication } from '@kit.AccountKit';
import { buffer, util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import auth from '@hw-agconnect/auth';
import { CloudStorageService } from './CloudStorageService';
import { RdbHelper } from '../data/RdbHelper';
import { ContentFilterService } from '../api/ContentFilterService';
import { CloudSyncService } from '../sync/CloudSyncService';

const DOMAIN = 0x0000;
const TAG = 'AuthService';

export interface AuthUser {
  uid: string;
  displayName: string;
  avatarUrl?: string;
  unionId?: string;
}

export interface AuthStatus {
  user: AuthUser | null;
  isLoggedIn: boolean;
  cloudReady: boolean;
  cloudStatusText: string;
}

export interface LocalProfile {
  displayName: string;
  avatarPath: string;
  bio: string;
  userModified: boolean;
}

export interface EffectiveProfile {
  displayName: string;
  avatarUrl: string;
  bio: string;
}

export interface ProfilePayload {
  ownerUid: string;
  cloudId: string;
  nickname: string;
  bio: string;
  avatarCloudPath: string;
  version: number;
  updatedAt: number;
}

let initialized: boolean = false;
let currentUser: AuthUser | null = null;
let appContext: common.UIAbilityContext | null = null;
let cachedEffectiveProfile: EffectiveProfile | null = null;

export class AuthService {
  static init(context: common.UIAbilityContext): void {
    if (initialized) {
      return;
    }
    appContext = context;
    const file = context.resourceManager.getRawFileContentSync('agconnect-services.json');
    const json: string = buffer.from(file.buffer).toString();
    auth.init(context, json);
    CloudStorageService.setContext(context);
    initialized = true;
    hilog.info(DOMAIN, TAG, 'Auth initialized');
  }

  static async getCurrentUser(): Promise<AuthUser | null> {
    if (currentUser) {
      return currentUser;
    }
    try {
      const user = await auth.getCurrentUser();
      if (!user) {
        return null;
      }
      currentUser = {
        uid: user.getUid(),
        displayName: user.getDisplayName() ?? 'TravelPin 用户',
        avatarUrl: user.getPhotoUrl() ?? ''
      };
      return currentUser;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(DOMAIN, TAG, `Failed to get current user: ${error.message}`);
      return null;
    }
  }

  static async getAuthStatus(): Promise<AuthStatus> {
    const user = await AuthService.getCurrentUser();
    return {
      user,
      isLoggedIn: user !== null,
      cloudReady: CloudStorageService.isReady(),
      cloudStatusText: CloudStorageService.getStatusText()
    };
  }

  static async isLoggedIn(): Promise<boolean> {
    const user = await AuthService.getCurrentUser();
    return user !== null;
  }

  static async restoreSession(): Promise<boolean> {
    const user = await AuthService.getCurrentUser();
    if (!user) {
      CloudStorageService.reset();
      return false;
    }
    // 清空缓存，重新从 RDB 加载（避免被上次登录的华为数据污染）
    cachedEffectiveProfile = null;
    // 从 RDB 读取本地 profile
    const local = await RdbHelper.getInstance().loadUserProfile();
    if (local && local.displayName) {
      cachedEffectiveProfile = {
        displayName: local.displayName,
        avatarUrl: local.avatarPath.replace(/^file:\/\//, ''),
        bio: local.bio
      };
      hilog.info(DOMAIN, TAG, `restoreSession: loaded from RDB "${cachedEffectiveProfile.displayName}"`);
    } else {
      hilog.info(DOMAIN, TAG, `restoreSession: no local profile, pulling from cloud...`);
      // RDB 为空时，尝试从云端拉取 profile
      try {
        const cloudProfile = await CloudSyncService.fetchProfile(user.uid);
        if (cloudProfile) {
          hilog.info(DOMAIN, TAG, `restoreSession: found cloud profile nickname="${cloudProfile.nickname}"`);
          // 优先设置内存缓存（昵称/bio 立即可用，头像路径下载完成后更新）
          cachedEffectiveProfile = {
            displayName: cloudProfile.nickname ?? '',
            avatarUrl: cloudProfile.avatarCloudPath ?? '',
            bio: cloudProfile.bio ?? ''
          };
          // 写入 RDB 缓存
          await RdbHelper.getInstance().saveUserProfile(
            cloudProfile.nickname ?? '',
            cloudProfile.avatarCloudPath ?? '',
            cloudProfile.bio ?? ''
          );
          // 下载云端头像到沙箱（如有）
          if (cloudProfile.avatarCloudPath && cloudProfile.avatarCloudPath.length > 0) {
            try {
              const localPath = await CloudStorageService.downloadProfileAvatar(user.uid);
              // 用本地路径更新 RDB 和缓存
              await RdbHelper.getInstance().saveUserProfile(
                cloudProfile.nickname ?? '',
                localPath,
                cloudProfile.bio ?? ''
              );
              cachedEffectiveProfile.avatarUrl = localPath;
              cachedEffectiveProfile.displayName = cloudProfile.nickname ?? '';
              cachedEffectiveProfile.bio = cloudProfile.bio ?? '';
            } catch (downloadErr) {
              hilog.warn(DOMAIN, TAG, `downloadProfileAvatar failed: ${(downloadErr as Error).message}, using cloud path as fallback`);
              // avatarUrl 已在上面的 cachedEffectiveProfile 初始化时设置，无需额外处理
            }
          }
        } else {
          hilog.info(DOMAIN, TAG, `restoreSession: no cloud profile either`);
        }
      } catch (cloudErr) {
        hilog.warn(DOMAIN, TAG, `restoreSession: fetchProfile failed: ${(cloudErr as Error).message}`);
      }
    }
    return await CloudStorageService.ensureReady();
  }

  static async getEffectiveProfile(): Promise<EffectiveProfile | null> {
    // 已有缓存直接返回
    if (cachedEffectiveProfile !== null) {
      hilog.info(DOMAIN, TAG, `getEffectiveProfile: cache hit "${cachedEffectiveProfile.displayName}"`);
      return cachedEffectiveProfile;
    }
    // 从 RDB 读取本地 profile
    const local = await RdbHelper.getInstance().loadUserProfile();
    if (local && local.displayName) {
      cachedEffectiveProfile = {
        displayName: local.displayName,
        avatarUrl: local.avatarPath.replace(/^file:\/\//, ''),
        bio: local.bio
      };
      hilog.info(DOMAIN, TAG, `getEffectiveProfile: from RDB "${cachedEffectiveProfile.displayName}"`);
      return cachedEffectiveProfile;
    }
    // RDB 为空时，不缓存华为数据（避免覆盖用户已修改的 profile）
    // 调用方需要自己处理华为默认值的显示
    hilog.info(DOMAIN, TAG, 'getEffectiveProfile: RDB empty, returning null (no Huawei fallback cached)');
    return null;
  }

  /**
   * 获取用于显示的 profile（优先本地，否则华为默认值）
   * 与 getEffectiveProfile 的区别：会返回华为默认值用于显示，但不缓存
   */
  static async getDisplayProfile(): Promise<EffectiveProfile | null> {
    const cached = await AuthService.getEffectiveProfile();
    if (cached !== null) {
      return cached;
    }
    const user = await AuthService.getCurrentUser();
    if (!user) {
      return null;
    }
    return {
      displayName: user.displayName,
      avatarUrl: user.avatarUrl ?? '',
      bio: ''
    };
  }

  static async saveLocalProfile(profile: LocalProfile): Promise<void> {
    // 0. 网络检查 — 离线则拒绝
    const isOnline = (AppStorage.get('networkOnline') as boolean) ?? false
    if (!isOnline) {
      hilog.warn(DOMAIN, TAG, 'saveLocalProfile: offline, rejected')
      throw new Error('当前无网络连接，无法保存资料')
    }

    // 0b. 确保 currentUser 有值（页面加载时可能还没初始化）
    let uid = currentUser?.uid ?? ''
    if (!uid) {
      const user = await AuthService.getCurrentUser()
      uid = user?.uid ?? ''
      hilog.info(DOMAIN, TAG, `saveLocalProfile: resolved uid="${uid}"`)
      if (!uid) {
        throw new Error('用户未登录，无法保存资料')
      }
    }

    hilog.info(DOMAIN, TAG, `saveLocalProfile: uid="${uid}", displayName="${profile.displayName}", avatarPath="${profile.avatarPath}"`)

    // 1. 安全审查 — nickname（敏感词直接阻止）
    hilog.info(DOMAIN, TAG, `saveLocalProfile: calling check for nickname="${profile.displayName}"`)
    try {
      const nicknameResult = await ContentFilterService.check(profile.displayName)
      hilog.info(DOMAIN, TAG, `saveLocalProfile: nickname check done, blocked="${nicknameResult.blocked}", hit="${nicknameResult.hit}"`)
      if (nicknameResult.blocked) {
        hilog.warn(DOMAIN, TAG, `saveLocalProfile: nickname blocked, hit="${nicknameResult.hit}"`)
        throw new Error('昵称包含敏感内容，请修改后重试')
      }
    } catch (err) {
      const msg = (err as Error).message
      if (msg === 'CONTENT_CHECK_NETWORK_ERROR') {
        hilog.error(DOMAIN, TAG, `saveLocalProfile: nickname check network error`)
        throw new Error('内容检测服务不可用，请检查网络后重试')
      }
      throw err as Error
    }

    // 2. 安全审查 — bio（敏感词直接阻止，不脱敏）
    hilog.info(DOMAIN, TAG, `saveLocalProfile: calling check for bio="${profile.bio.trim()}"`)
    try {
      const bioResult = await ContentFilterService.check(profile.bio.trim())
      hilog.info(DOMAIN, TAG, `saveLocalProfile: bio check done, blocked="${bioResult.blocked}", hit="${bioResult.hit}"`)
      if (bioResult.blocked) {
        hilog.warn(DOMAIN, TAG, `saveLocalProfile: bio blocked, hit="${bioResult.hit}"`)
        throw new Error('个性签名包含敏感内容，请修改后重试')
      }
    } catch (err) {
      const msg = (err as Error).message
      if (msg === 'CONTENT_CHECK_NETWORK_ERROR') {
        hilog.error(DOMAIN, TAG, `saveLocalProfile: bio check network error`)
        throw new Error('内容检测服务不可用，请检查网络后重试')
      }
      throw err as Error
    }

    const finalBio = profile.bio.trim()

    hilog.info(DOMAIN, TAG, `saveLocalProfile: displayName="${profile.displayName}", avatarPath="${profile.avatarPath}"`)

    // 3. 写本地 RDB（头像路径用本地沙箱路径，avatarCloudPath 后续上传成功再更新）
    await RdbHelper.getInstance().saveUserProfile(
      profile.displayName,
      profile.avatarPath,
      finalBio
    )

    // 4. 头像 → CloudStorage（如有本地路径，非 http 链接）
    // 重要：头像必须上传成功才继续，否则 avatarCloudPath 为空，云端 profile 不完整
    let cloudAvatarPath = ''
    if (profile.avatarPath && !profile.avatarPath.startsWith('http') && uid.length > 0) {
      hilog.info(DOMAIN, TAG, `saveLocalProfile: uploading avatar, localPath="${profile.avatarPath}"`)
      try {
        await CloudStorageService.uploadProfileAvatar(uid, profile.avatarPath)
        cloudAvatarPath = CloudStorageService.buildProfileAvatarPath()
        hilog.info(DOMAIN, TAG, `uploadProfileAvatar success: cloudPath=${cloudAvatarPath}`)
      } catch (err) {
        hilog.error(DOMAIN, TAG, `uploadProfileAvatar FAILED: ${(err as Error).message}`)
        // 头像上传失败 → 报错上抛，让 ProfileEditPage 提示用户
        throw new Error('头像上传失败，请重试（可能是网络问题）')
      }
    } else {
      hilog.info(DOMAIN, TAG, `saveLocalProfile: skipping avatar upload, avatarPath="${profile.avatarPath}"`)
    }

    // 5. 昵称/bio/avatarCloudPath → CloudDB
    if (uid.length > 0) {
      const profileData: ProfilePayload = {
        ownerUid: uid,
        cloudId: `profile_${uid}`,
        nickname: profile.displayName,
        bio: finalBio,
        avatarCloudPath: cloudAvatarPath,
        version: 1,
        updatedAt: Date.now()
      }
      try {
        await CloudSyncService.upsertProfile(JSON.stringify(profileData))
        hilog.info(DOMAIN, TAG, `upsertProfile success`)
      } catch (err) {
        hilog.error(DOMAIN, TAG, `upsertProfile FAILED: ${(err as Error).message}`)
        throw new Error('个人资料保存失败，请重试')
      }
    }

    // 6. 更新内存缓存
    cachedEffectiveProfile = {
      displayName: profile.displayName,
      avatarUrl: profile.avatarPath.replace(/^file:\/\//, ''),
      bio: finalBio
    };
    hilog.info(DOMAIN, TAG, `saveLocalProfile: done, cached="${cachedEffectiveProfile.displayName}"`)
  }

  static async signInWithHuaweiID(hostContext: common.UIAbilityContext): Promise<AuthUser> {
    CloudStorageService.setContext(hostContext)
    const loginRequest = new authentication.HuaweiIDProvider().createLoginWithHuaweiIDRequest();
    loginRequest.forceLogin = true;
    loginRequest.state = util.generateRandomUUID();
    loginRequest.idTokenSignAlgorithm = authentication.IdTokenSignAlgorithm.PS256;

    const controller = new authentication.AuthenticationController(hostContext);
    const response = await controller.executeRequest(loginRequest) as authentication.LoginWithHuaweiIDResponse;

    if (response.state && response.state !== loginRequest.state) {
      throw new Error('登录态校验失败，请重试');
    }
    const credential = response.data;
    if (!credential) {
      throw new Error('未获取到华为账号凭证');
    }
    if (!credential.authorizationCode) {
      throw new Error('未获取到授权码，请重试');
    }

    const signInResult = await auth.signIn({
      credentialInfo: { kind: 'hwid' },
      autoCreateUser: true
    });

    const agcUser = signInResult.getUser();
    let displayName = agcUser.getDisplayName() ?? 'TravelPin 用户';
    let avatarUrl = agcUser.getPhotoUrl() ?? '';

    try {
      const profileRequest = new authentication.HuaweiIDProvider().createAuthorizationWithHuaweiIDRequest();
      profileRequest.scopes = ['profile'];
      profileRequest.forceAuthorization = true;
      profileRequest.state = util.generateRandomUUID();
      const profileResponse = await controller.executeRequest(profileRequest) as authentication.AuthorizationWithHuaweiIDResponse;
      if (profileResponse.state && profileResponse.state !== profileRequest.state) {
        throw new Error('资料授权校验失败');
      }
      const profileCredential = profileResponse.data as authentication.AuthorizationWithHuaweiIDCredential;
      if (profileCredential) {
        displayName = profileCredential.nickName ?? displayName;
        avatarUrl = profileCredential.avatarUri ?? avatarUrl;
      }
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, `Profile authorization skipped: ${error.message}`);
    }

    currentUser = {
      uid: agcUser.getUid(),
      displayName: displayName,
      avatarUrl: avatarUrl,
      unionId: credential.unionID
    };

    // 不再在登录时把华为数据写入 RDB！！！
    // 本地 profile 只在用户主动修改时保存，登录时不能覆盖
    hilog.info(DOMAIN, TAG, `signInWithHuaweiID: done, currentUser="${currentUser.displayName}", RDB preserved`);
    return currentUser;
  }

  static async signOut(): Promise<void> {
    try {
      await auth.signOut();
    } finally {
      currentUser = null;
      // 注意：不清除本地 profile 数据！这样重新登录时可以保留用户修改的昵称/头像
      cachedEffectiveProfile = null;
      CloudStorageService.reset();
    }
  }

  /**
   * 注销账号：永久删除该用户的全部数据。
   *
   * 流程：
   *  1. 拉取云端 travel + node 列表，逐条 hardDelete
   *  2. 删除云存储下 users/{uid}/travels 与 users/{uid}/profiles 目录
   *  3. 清空本地 RDB（travels / memory_nodes / sync_queue / app_sync_state / user_profile）
   *  4. 清空本地 sandbox 照片目录
   *  5. signOut 退出 AGC 账号
   *  6. 清除全部同意状态
   *
   * 任一步失败都会继续后续步骤（best-effort），保证用户数据尽可能被清理。
   */
  static async deleteAccount(): Promise<void> {
    const user = await AuthService.getCurrentUser();
    const uid = user?.uid ?? '';
    hilog.info(DOMAIN, TAG, `deleteAccount start, uid=${uid}`);

    // Step 1: 删除云端数据库记录（含 profile，否则重新登录会拉旧昵称/bio 回写本地）。
    // 三类删除分别独立 try，任一失败不影响其他删除。
    if (uid.length > 0) {
      try {
        const cloudTravels = await CloudSyncService.fetchTravels(uid);
        for (let i = 0; i < cloudTravels.length; i++) {
          const cloudId = cloudTravels[i].cloudId ?? '';
          if (cloudId.length > 0) {
            await CloudSyncService.hardDeleteTravelByCloudId(cloudId);
          }
        }
      } catch (err) {
        hilog.error(DOMAIN, TAG, `deleteAccount: travel cleanup failed: ${JSON.stringify(err)}`);
      }
      try {
        const cloudNodes = await CloudSyncService.fetchMemoryNodes(uid);
        for (let i = 0; i < cloudNodes.length; i++) {
          const cloudId = cloudNodes[i].cloudId ?? '';
          if (cloudId.length > 0) {
            await CloudSyncService.hardDeleteMemoryNodeByCloudId(cloudId);
          }
        }
      } catch (err) {
        hilog.error(DOMAIN, TAG, `deleteAccount: node cleanup failed: ${JSON.stringify(err)}`);
      }
      try {
        await CloudSyncService.hardDeleteProfileByOwnerUid(uid);
      } catch (err) {
        hilog.error(DOMAIN, TAG, `deleteAccount: profile cleanup failed: ${JSON.stringify(err)}`);
      }
    }

    // Step 2: 删除云存储下该用户的所有目录
    try {
      await CloudStorageService.deleteDirectoryRecursively('travels/');
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `deleteAccount: travel storage cleanup failed: ${JSON.stringify(err)}`);
    }
    try {
      await CloudStorageService.deleteDirectoryRecursively('profiles/');
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `deleteAccount: profile storage cleanup failed: ${JSON.stringify(err)}`);
    }

    // Step 3: 清空本地数据库
    try {
      await RdbHelper.getInstance().wipeAllUserData();
    } catch (err) {
      hilog.error(DOMAIN, TAG, `deleteAccount: rdb wipe failed: ${JSON.stringify(err)}`);
    }

    // Step 4: 退出账号
    try {
      await auth.signOut();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `deleteAccount: signOut failed: ${JSON.stringify(err)}`);
    }

    currentUser = null;
    cachedEffectiveProfile = null;
    CloudStorageService.reset();

    hilog.info(DOMAIN, TAG, 'deleteAccount done');
  }
}
