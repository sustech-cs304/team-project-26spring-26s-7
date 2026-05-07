export enum ReplayBgmId {
  DEFAULT = 'default_southeast_traveling'
}

export interface ReplayMusicOption {
  id: ReplayBgmId
  title: string
  subtitle: string
  filename: string
  author: string
}

export class ReplayMusicCatalog {
  static readonly DEFAULT_ID: ReplayBgmId = ReplayBgmId.DEFAULT

  static list(): ReplayMusicOption[] {
    return [
      {
        id: ReplayBgmId.DEFAULT,
        title: '东南漫游',
        subtitle: '当前内置回放背景音乐',
        filename: 'South-East-Traveling.mp3',
        author: '内置曲目'
      }
    ]
  }

  static getById(id: ReplayBgmId): ReplayMusicOption {
    return ReplayMusicCatalog.list().find((item: ReplayMusicOption) => item.id === id) ??
      ReplayMusicCatalog.list()[0]
  }
}
