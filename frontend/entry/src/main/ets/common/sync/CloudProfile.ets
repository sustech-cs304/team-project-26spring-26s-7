import { cloudDatabase } from '@kit.CloudFoundationKit'

export class CloudProfile extends cloudDatabase.DatabaseObject {
  public naturalbase_ClassName(): string {
    return 'UserProfile'
  }

  public cloudId: string | undefined
  public ownerUid: string | undefined
  public nickname: string | undefined
  public bio: string | undefined
  public avatarCloudPath: string | undefined
  public version: number | undefined
  public updatedAt: number | undefined
}