export enum ReplayBgmId {
  MORNING = 'morning_chill_birds',
  CITY_WALK = 'city_lights_lofi',
  NIGHT_JAZZ = 'jazz_night',
  TROPICAL_TRAVEL = 'tropical_chill_travel',
  CINEMATIC_CALM = 'cinematic_ambient'
}

export interface ReplayMusicOption {
  id: ReplayBgmId
  title: string
  subtitle: string
  filename: string
  author: string
}

export class ReplayMusicCatalog {
  static readonly DEFAULT_ID: ReplayBgmId = ReplayBgmId.CITY_WALK

  static list(): ReplayMusicOption[] {
    return [
      {
        id: ReplayBgmId.MORNING,
        title: '晨间鸟鸣',
        subtitle: '轻环境氛围，适合自然和清晨路线',
        filename: 'welc0mei0-180126-ambient-morning-chill-with-birds-21348.mp3',
        author: 'welc0mei0'
      },
      {
        id: ReplayBgmId.CITY_WALK,
        title: '城市微光',
        subtitle: '轻 LoFi 节奏，适合城市漫步回放',
        filename: 'lofidreams-city-lights-chill-lofi-365944.mp3',
        author: 'lofidreams'
      },
      {
        id: ReplayBgmId.NIGHT_JAZZ,
        title: '夜色爵士',
        subtitle: '低刺激爵士氛围，适合夜景路线',
        filename: 'vibedepot-jazz-night-419811.mp3',
        author: 'vibedepot'
      },
      {
        id: ReplayBgmId.TROPICAL_TRAVEL,
        title: '热带旅拍',
        subtitle: '轻快旅行 vlog 氛围，适合活力路线',
        filename: 'jaystacksbeats-travel-vlog-_-tropical-chill-002-451749.mp3',
        author: 'jaystacksbeats'
      },
      {
        id: ReplayBgmId.CINEMATIC_CALM,
        title: '静谧电影感',
        subtitle: '舒缓铺底，适合安静沉浸式回放',
        filename: 'sigmaeffect-cinematic-ambient-atmosphere-463222.mp3',
        author: 'sigmaeffect'
      }
    ]
  }

  static getById(id: ReplayBgmId): ReplayMusicOption {
    return ReplayMusicCatalog.list().find((item: ReplayMusicOption) => item.id === id) ??
      ReplayMusicCatalog.list()[0]
  }
}
