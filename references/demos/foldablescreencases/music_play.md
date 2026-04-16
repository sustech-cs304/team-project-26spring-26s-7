# HarmonyOS 音乐播放系统构建指南

本文档基于 `foldablescreencases` 项目，详细说明如何构建一个完整的本地音乐播放系统。

## 一、项目概述

### 功能特性
- 播放内置 `.mp3` 音乐文件（位于 `resources/rawfile/` 目录）
- 支持播放/暂停/停止/Seek 操作
- 支持三种播放模式：单曲循环、列表循环、随机播放
- 支持后台播放（应用退到后台后继续播放）
- 接入系统播控中心（锁屏/通知栏控制）
- 歌词同步滚动显示
- 进度条拖拽控制

### 技术栈
- **UI 框架**: ArkUI (声明式 UI)
- **音频播放**: `@kit.MediaKit` (AVPlayer)
- **媒体会话**: `@kit.AVSessionKit` (AVSession)
- **后台任务**: `@ohos.app.ability.backgroundTaskManager`
- **架构模式**: MVVM

---

## 二、核心模块架构

```
foldablescreencases/
├── common/constants/
│   └── CommonConstants.ets       # 常量定义（歌曲列表、播放状态等）
├── model/
│   ├── AVPlayerModel.ets         # 音频播放器封装
│   ├── AVSessionModel.ets        # 媒体会话管理
│   ├── MusicModel.ets            # 歌曲数据模型
│   └── WindowModel.ets           # 窗口管理
├── viewmodel/
│   └── MusicPlayViewModel.ets    # 播放控制逻辑（MVVM 中的 VM）
├── components/
│   ├── MusicPlayerInfoComp.ets   # 歌曲信息展示组件
│   └── MusicPlayerCtrlComp.ets   # 播放控制按钮组件
├── pages/
│   └── MusicPlayerPage.ets       # 主播放页面
└── resources/rawfile/
    ├── music.mp3                 # 内置音乐文件
    └── lyrics.lrc                # 歌词文件
```

---

## 三、关键实现步骤

### 步骤 1: 配置项目依赖

在 `module.json5` 中申请后台播放权限：

```json5
{
  "module": {
    "name": "foldablescreencases",
    "type": "har",
    "deviceTypes": ["phone", "tablet"],
    "requestPermissions": [
      {
        "name": "ohos.permission.KEEP_BACKGROUND_RUNNING"
      }
    ]
  }
}
```

### 步骤 2: 准备音乐资源

将 `.mp3` 文件放入 `src/main/resources/rawfile/` 目录，并在常量文件中定义歌曲信息：

```typescript
// common/constants/CommonConstants.ets
static readonly MUSIC_INFO_ARR: Array<MusicInfo> = [
  {
    title: '歌曲名称',
    cover: 'cover.webp',
    singer: '歌手名',
    duration: 133000,  // 毫秒
    res: 'music.mp3',  // rawfile 中的文件名
    lrcRes: 'lyrics.lrc'
  } as MusicInfo
]
```

### 步骤 3: 创建 AVPlayer 播放器

```typescript
// model/AVPlayerModel.ets
import { media } from '@kit.MediaKit';
import common from '@ohos.app.ability.common';

export class AVPlayerModel {
  private avPlayer?: media.AVPlayer;

  // 初始化 AVPlayer
  async initAVPlayer(timeUpdateCb: Function, stateUpdateCb: Function, completeCb: Function): Promise<void> {
    // 创建 AVPlayer 实例
    let avPlayer: media.AVPlayer = await media.createAVPlayer();
    
    // 注册回调
    this.regAVPlayerCallback(avPlayer, timeUpdateCb, stateUpdateCb, completeCb);
    this.avPlayer = avPlayer;
  }

  // 注册回调函数
  private regAVPlayerCallback(avPlayer: media.AVPlayer, timeUpdateCb: Function, stateUpdateCb: Function, completeCb: Function): void {
    // 时间更新回调（用于进度条）
    avPlayer.on('timeUpdate', (newTime: number) => {
      timeUpdateCb(newTime);
    });
    
    // 状态变化回调
    avPlayer.on('stateChange', (state: media.AVPlayerState) => {
      stateUpdateCb(state);
      // 根据状态处理：idle, initialized, prepared, playing, paused, completed, stopped, released
    });
    
    // 单曲完成回调
    avPlayer.on('completed', () => {
      completeCb();
    });
  }

  // 加载本地 rawfile 资源
  async prepare(fileName: string, finishTask?: Function): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    // 获取 rawfile 资源的 fd、offset、length
    const fileDescriptor = await context.resourceManager.getRawFd(fileName);
    const avFileDescriptor: media.AVFileDescriptor = {
      fd: fileDescriptor.fd,
      offset: fileDescriptor.offset,
      length: fileDescriptor.length
    };
    this.avPlayer.fdSrc = avFileDescriptor;  // 触发 initialized 状态
    this.prepareFinishTask = finishTask;
  }

  // 播放控制
  play(): void { this.avPlayer?.play(); }
  pause(): void { this.avPlayer?.pause(); }
  stop(): void { this.avPlayer?.stop(); }
  seek(timeMs: number): void { this.avPlayer?.seek(timeMs); }
  
  // 释放资源
  releaseAVPlayer(): void {
    this.avPlayer?.release();
    this.avPlayer = undefined;
  }
}
```

### 步骤 4: 创建播放控制 ViewModel

```typescript
// viewmodel/MusicPlayViewModel.ets
import { avSession as AVSessionManager } from '@kit.AVSessionKit';
import { AVPlayerModel } from '../model/AVPlayerModel';
import { AVSessionModel } from '../model/AVSessionModel';
import { MusicModel } from '../model/MusicModel';

export class MusicPlayerViewModel {
  private avplayerModel: AVPlayerModel = new AVPlayerModel();
  private avsessionModel?: AVSessionModel;
  private musicModelArr: Array<MusicModel> = [];
  private curMusicModelIndex: number = 0;
  private curMusicModelRaw?: MusicModel;

  // 初始化
  async init(context: Context, musicInfoArr: Array<MusicInfo>): Promise<void> {
    // 1. 初始化歌曲列表
    musicInfoArr.forEach((info: MusicInfo) => {
      this.musicModelArr.push(new MusicModel(info));
    });
    this.curMusicModelRaw = this.musicModelArr[this.curMusicModelIndex];

    // 2. 初始化 AVSession（系统播控中心）
    this.avsessionModel = new AVSessionModel(context);
    await this.avsessionModel.createSession({
      onPlay: () => this.play(),
      onPause: () => this.pause(),
      onStop: () => this.stop(),
      onPlayNext: () => this.playNext(),
      onPlayPrevious: () => this.playPrevious(),
      onSeek: (timeMs: number) => this.seek(timeMs),
      onSetLoopMode: () => this.updateLoopMode()
    });

    // 3. 初始化 AVPlayer
    await this.avplayerModel.initAVPlayer(
      (newTime: number) => { /* 更新时间进度 */ },
      (state: string) => { /* 更新播放状态 */ },
      () => { this.playNext(); }  // 自动下一首
    );

    // 4. 加载资源
    this.prepare();
  }

  // 播放下一首（根据循环模式）
  async playNext() {
    switch (this.curLoopMode) {
      case AVSessionManager.LoopMode.LOOP_MODE_SINGLE:
        this.seek(0);  // 单曲循环：重新开始
        break;
      case AVSessionManager.LoopMode.LOOP_MODE_LIST:
        // 列表循环：索引 +1
        this.curMusicModelIndex = (this.curMusicModelIndex + 1) % this.musicModelArr.length;
        await this.switchMusic();
        break;
      case AVSessionManager.LoopMode.LOOP_MODE_SHUFFLE:
        // 随机播放
        const randomIndex = Math.floor(Math.random() * this.musicModelArr.length);
        this.curMusicModelIndex = randomIndex;
        await this.switchMusic();
        break;
    }
  }

  // 切换歌曲
  async switchMusic() {
    this.curMusicModelRaw = this.musicModelArr[this.curMusicModelIndex];
    await this.avplayerModel.resetAVPlayer();
    await this.avsessionModel?.setSessionInfo(this.curMusicModelRaw);
    await this.prepare(() => this.play());
  }

  // 释放资源
  release(): void {
    this.avplayerModel.releaseAVPlayer();
    this.avsessionModel?.destroySession();
  }
}
```

### 步骤 5: 创建 AVSession 接入系统播控中心

```typescript
// model/AVSessionModel.ets
import { avSession as AVSessionManager } from '@kit.AVSessionKit';
import backgroundTaskManager from '@ohos.app.ability.backgroundTaskManager';
import wantAgent from '@ohos.app.ability.wantAgent';

export class AVSessionModel {
  private session?: AVSessionManager.AVSession;
  private bindContext?: Context;

  // 创建 Session
  async createSession(context: Context, eventListener: AVSessionEventListener): Promise<void> {
    this.bindContext = context;
    // 创建 AVSession 实例
    this.session = await AVSessionManager.createAVSession(
      context,
      'com.example.musicplayer',  // session 标签
      'audio'  // session 类型
    );
    
    // 注册事件监听
    await this.registerSessionListener(eventListener);
    
    // 激活 Session
    await this.session.activate();
  }

  // 注册事件监听
  private async registerSessionListener(eventListener: AVSessionEventListener): Promise<void> {
    this.session?.on('play', () => eventListener.onPlay());
    this.session?.on('pause', () => eventListener.onPause());
    this.session?.on('stop', () => eventListener.onStop());
    this.session?.on('playNext', () => eventListener.onPlayNext());
    this.session?.on('playPrevious', () => eventListener.onPlayPrevious());
    this.session?.on('seek', (position) => eventListener.onSeek(position));
    this.session?.on('setLoopMode', (mode) => eventListener.onSetLoopMode());
  }

  // 设置媒体元信息（显示在锁屏/通知栏）
  async setSessionInfo(musicModel: MusicModel): Promise<void> {
    const metadata: AVSessionManager.AVMetadata = {
      assetId: '0',
      title: musicModel.title,
      mediaImage: musicModel.coverPixel,  // 封面图
      artist: musicModel.singer,
      duration: musicModel.totalTime,
      lyric: musicModel.lrcContent
    };
    await this.session?.setAVMetadata(metadata);
  }

  // 启动后台任务（后台播放）
  startContinuousTask(): void {
    const wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [{
        bundleName: 'com.example.musicplayer',
        abilityName: 'com.example.musicplayer.EntryAbility'
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };

    wantAgent.getWantAgent(wantAgentInfo).then((wantAgentObj) => {
      backgroundTaskManager.startBackgroundRunning(
        this.bindContext!,
        backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK,
        wantAgentObj
      );
    });
  }

  // 停止后台任务
  stopContinuousTask(): void {
    backgroundTaskManager.stopBackgroundRunning(
      this.bindContext!,
      backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK
    );
  }
}
```

### 步骤 6: 创建 UI 组件

```typescript
// pages/MusicPlayerPage.ets
@Entry
@Component
struct MusicPlayerPage {
  @State musicModel?: MusicModel;
  @State curPlayerState: string = 'idle';
  @State curProgress: number = 0;
  
  private viewModel: MusicPlayerViewModel = new MusicPlayerViewModel();

  async aboutToAppear() {
    // 初始化 ViewModel
    await this.viewModel.init(getContext(this), CommonConstants.MUSIC_INFO_ARR);
  }

  build() {
    Column() {
      // 歌曲信息组件（封面、歌名、歌手）
      MusicPlayerInfoComp({ musicModel: this.musicModel })
      
      // 进度条
      Slider({
        value: this.curProgress,
        min: 0,
        max: 100
      })
      .onChange((value: number) => {
        // 拖拽进度条
        const timeMs = value / 100 * this.musicModel!.totalTime;
        this.viewModel.seek(timeMs);
      })
      
      // 播放控制按钮
      MusicPlayerCtrlComp({
        onPlayPause: () => {
          if (this.curPlayerState === 'playing') {
            this.viewModel.pause();
          } else {
            this.viewModel.play();
          }
        },
        onPrevious: () => this.viewModel.playPrevious(),
        onNext: () => this.viewModel.playNext()
      })
    }
  }
}
```

---

## 四、播放状态机

AVPlayer 的状态流转：

```
idle → initialized → prepared → playing → completed → stopped → released
                              ↓
                          paused ←───┘
```

| 状态 | 触发条件 | 动作 |
|------|----------|------|
| `idle` | 调用 `reset()` 后 | 调用 `release()` 释放资源 |
| `initialized` | 设置 `fdSrc` 后 | 调用 `prepare()` |
| `prepared` | `prepare()` 完成 | 可调用 `play()` |
| `playing` | `play()` 成功 | 播放中 |
| `paused` | `pause()` 成功 | 暂停，可 `resume()` |
| `completed` | 播放结束 | 调用 `stop()` 或自动下一首 |
| `stopped` | `stop()` 成功 | 调用 `reset()` |
| `released` | `release()` 成功 | 资源已释放 |

---

## 五、播放模式详解

```typescript
// 循环模式（来自 AVSessionManager.LoopMode）
LOOP_MODE_SINGLE = 1   // 单曲循环：播放完成后 seek(0) 重新开始
LOOP_MODE_LIST = 2     // 列表循环：按顺序播放下一首
LOOP_MODE_SHUFFLE = 3  // 随机播放：随机选择下一首
```

---

## 六、后台播放要点

1. **权限申请**: 在 `module.json5` 中申请 `ohos.permission.KEEP_BACKGROUND_RUNNING`
2. **启动后台任务**: 使用 `backgroundTaskManager.startBackgroundRunning()`，指定 `AUDIO_PLAYBACK` 模式
3. **WantAgent**: 配置点击通知栏后拉起应用的 WantAgent
4. **生命周期**: 在应用前后台切换时启动/停止后台任务

---

## 七、常见问题

### Q1: 如何获取 rawfile 资源的播放地址？
使用 `context.resourceManager.getRawFd(fileName)` 获取 `{fd, offset, length}` 三元组，然后赋值给 `avPlayer.fdSrc`。

### Q2: 为什么需要 AVSession？
AVSession 用于接入系统播控中心，实现：
- 锁屏界面显示歌曲信息和控制按钮
- 通知栏媒体控制面板
- 蓝牙耳机控制（播放/暂停/切歌）

### Q3: 如何处理播放错误？
注册 `error` 事件监听，在错误时调用 `reset()` 重置播放器：
```typescript
avPlayer.on('error', (err) => {
  console.error(`AVPlayer error: ${err.code}, ${err.message}`);
  avPlayer.reset();
});
```

---

## 八、参考文档

- [AVPlayer 官方文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/using-avplayer-for-playback-0000001820880265)
- [AVSession 官方文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/avsession-access-scene-V5)
- [后台任务管理](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/background-task-management-V5)
