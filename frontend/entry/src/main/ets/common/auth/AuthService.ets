import { common } from '@kit.AbilityKit';
import { authentication } from '@kit.AccountKit';
import { buffer, util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import auth from '@hw-agconnect/auth';
import { CloudStorageService } from './CloudStorageService';
import { RdbHelper } from '../data/RdbHelper';

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
      hilog.info(DOMAIN, TAG, `restoreSession: no local profile, will use Huawei default`);
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
    hilog.info(DOMAIN, TAG, `saveLocalProfile: displayName="${profile.displayName}", avatarPath="${profile.avatarPath}"`);
    await RdbHelper.getInstance().saveUserProfile(
      profile.displayName,
      profile.avatarPath,
      profile.bio
    );
    cachedEffectiveProfile = {
      displayName: profile.displayName,
      avatarUrl: profile.avatarPath.replace(/^file:\/\//, ''),
      bio: profile.bio
    };
    hilog.info(DOMAIN, TAG, `saveLocalProfile: done, cached="${cachedEffectiveProfile.displayName}"`);
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
      const profileCredential = profileResponse.data;
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
}
