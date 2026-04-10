import { cloudDatabase } from '@kit.CloudFoundationKit'

export class CloudMemoryNode extends cloudDatabase.DatabaseObject {
  public naturalbase_ClassName(): string {
    return 'MemoryNode'
  }

  public cloudId: string | undefined
  public ownerUid: string | undefined
  public travelCloudId: string | undefined
  public title: string | undefined
  public content: string | undefined
  public latitude: number | undefined
  public longitude: number | undefined
  public poiName: string | undefined
  public mood: string | undefined
  public tagsJson: string | undefined
  public nodeOrder: number | undefined
  public photoManifest: string | undefined
  public createdAt: number | undefined
  public updatedAt: number | undefined
  public deletedAt: number | undefined
  public version: number | undefined
}
