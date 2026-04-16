# 折叠屏音乐播放器案例

## 简介

本示例介绍使用 ArkUI 中的容器组件 FolderStack 在折叠屏设备中实现音乐播放器场景，展示当前播放歌曲信息，支持播控中心控制播放和后台播放能力。

## 源码仓库

**官方仓库**: https://gitee.com/harmonyos-cases/cases

**案例路径**: `CommonAppDevelopment/feature/foldablescreencases/`

## 快速获取

```bash
# 克隆官方案例仓库
git clone https://gitee.com/harmonyos-cases/cases.git

# 进入本案例目录
cd cases/CommonAppDevelopment/feature/foldablescreencases/
```

## 核心功能

1. **折叠屏适配**: 使用 FolderStack 组件自动避让折叠屏折痕区
2. **音乐播放**: AVPlayer 实现音乐播放、暂停、进度控制
3. **后台播放**: 支持退到后台由播控中心控制
4. **歌词展示**: 支持歌词随歌曲进度滚动

## 核心技术点

| 技术 | 用途 |
|------|------|
| `FolderStack` | 折叠屏容器组件，自动避让折痕区 |
| `AVPlayer` | 媒体播放控制 |
| `AVSession` | 后台播控中心集成 |
| `display` | 屏幕状态监听 |

## 关键文件参考

- `MusicPlayerPage.ets` - 主页面
- `MusicPlayerInfoComp.ets` - 歌曲信息组件
- `MusicPlayerCtrlComp.ets` - 播放控制组件
- `AVPlayerModel.ets` - 播放器模型

## 使用说明

1. 播放器预加载了歌曲列表，即开即用
2. 支持播放模式切换、播放、暂停、重新播放、上一首、下一首
3. 支持歌词展示、随歌曲滚动
4. 支持歌曲进度拖拽
5. 在折叠屏上支持横屏半展开态下的组件自适应动态布局

## 官方文档

- [FolderStack 组件](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/arkui-ts-container-folderstack-V5)
- [AVPlayer API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/arkts-apis-media-avplayer-V5)
