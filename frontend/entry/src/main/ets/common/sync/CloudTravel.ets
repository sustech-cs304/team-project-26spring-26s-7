import { cloudDatabase } from '@kit.CloudFoundationKit'

export class CloudTravel extends cloudDatabase.DatabaseObject {
  public naturalbase_ClassName(): string {
    return 'Travel'
  }

  public cloudId: string | undefined
  public ownerUid: string | undefined
  public name: string | undefined
  public coverPhotoObjectKey: string | undefined
  public startDate: number | undefined
  public endDate: number | undefined
  public createdAt: number | undefined
  public updatedAt: number | undefined
  public deletedAt: number | undefined
  public version: number | undefined
  public isPublic: number | undefined
}
