import { common } from '@kit.AbilityKit';
import { authentication } from '@kit.AccountKit';
import { buffer, util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import auth from '@hw-agconnect/auth';
import { CloudStorageService } from './CloudStorageService';

const DOMAIN = 0x0000;
const TAG = 'AuthService';

export interface AuthUser {
  uid: string;
  displayName: string;
  unionId?: string;
}

export interface AuthStatus {
  user: AuthUser | null;
  isLoggedIn: boolean;
  cloudReady: boolean;
  cloudStatusText: string;
}

let initialized: boolean = false;
let currentUser: AuthUser | null = null;

export class AuthService {
  static init(context: common.UIAbilityContext): void {
    if (initialized) {
      return;
    }

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
        displayName: user.getDisplayName() ?? 'TravelPin 用户'
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
    return await CloudStorageService.ensureReady();
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
    currentUser = {
      uid: agcUser.getUid(),
      displayName: agcUser.getDisplayName() ?? 'TravelPin 用户',
      unionId: credential.unionID
    };

    const cloudReady = await CloudStorageService.ensureReady();
    if (!cloudReady) {
      throw new Error(CloudStorageService.getLastError() || '云存储初始化失败，请重试');
    }
    return currentUser;
  }

  static async signOut(): Promise<void> {
    try {
      await auth.signOut();
    } finally {
      currentUser = null;
      CloudStorageService.reset();
    }
  }
}
