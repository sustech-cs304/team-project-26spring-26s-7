# Linux CI 迁移尝试事后总结

## 摘要

为把当前 Windows 上的 GitHub Actions + Jenkins CI/CD 流水线迁移到 Linux 服务器，团队进行了一次完整可行性验证。在完成阶段 A（服务器基础设施准备）后，验证发现 HarmonyOS 闭源工具链没有 Linux 版本，迁移在编译阶段被无法绕过的工程约束阻断。**结论：维持现状（Windows CI），等待 HarmonyOS 官方 Linux 工具链发布后再启动迁移。**

本次迁移尝试虽未达成最终目标，但沉淀了一份明确的工具链可行性边界，避免后续团队成员重复踩坑。

---

## 一、迁移目标

将 [linux-ci-migration-guide-zh.md](./linux-ci-migration-guide-zh.md) 中描述的方案 B 落地：

1. GitHub Actions runner 迁到 Linux
2. Jenkins 迁到同一台 Linux 服务器
3. `Jenkinsfile` / `build.ps1` / `watch-jenkins-build.ps1` 改写为 Linux 兼容版本
4. HarmonyOS 项目（ArkTS）在 Linux 上完成 `ohpm install` + `assembleHap`

---

## 二、实际验证通过的部分

以下工具链组合在 Linux（Ubuntu，`/home/26s-7/ci-server`）上**已实测可用**：

| 工具 | 版本 | 状态 |
|---|---|---|
| Java | OpenJDK 21 | ✅ |
| Jenkins | 系统包，端口 8080，用户 `jenkins:jenkins` | ✅ |
| GitHub self-hosted runner | 已注册标签 `self-hosted, linux, travelpin`，名称 `hcss-ecs-cfeem` | ✅ |
| Node.js | 系统 `/usr/bin/node` v22.22.2 | ✅ |
| ohpm | 1.2.0，registry 设为 `https://ohpm.openharmony.cn/ohpm/` | ✅ |
| hvigor | 6.22.3（从 Windows DevEco Studio 拷贝过来的 `hvigor/bin/hvigorw.js`） | ✅ 能在 Node v22 上跑起来 |
| `ohpm install` 全链路 | 项目 3 个依赖（`@ohos/hypium`、`@ohos/hamock`、`@hw-agconnect/auth`）均能从 ohpm registry 成功拉取 | ✅ |
| Jenkins 服务用户对 `/home/26s-7/ci-server` 树的读写权限 | 经过 `chmod o+rX` + `chown` 配置后通过 | ✅ |

---

## 三、致命阻碍

### 阻碍 1：HarmonyOS 闭源工具链无官方 Linux 版本

DevEco Studio 截至 2026 年仅提供 **Windows 和 macOS** 版本，没有官方 Linux 桌面版。HarmonyOS 的核心编译工具（`restool`、`ark`、`abc`、`idl`、`hdc`、`hnpcli` 等）都是平台相关的本地二进制，只随 DevEco Studio 发布。

将 Windows DevEco Studio 中的 `sdk` 目录原样拷到 Linux 服务器后，`file` 命令验证：

```
restool.exe: PE32+ executable (console) x86-64, for MS Windows
```

`sdk/default/openharmony/toolchains/` 和 `sdk/default/openharmony/native/llvm/bin/` 下数十个二进制全部是 Windows PE 可执行文件，Linux 上无法直接调用。

### 阻碍 2：华为 commandline-tools-linux 不能下载到目标 SDK

服务器上下载的 `commandline-tools-linux-2.0.0.2.zip` 自带的 `sdkmgr` 工具，`list` 出来的全部组件只有 **OpenHarmony API 8/9** 时代的内容：

```
OpenHarmony/ets        | 9 | 3.2.12.5 | Release | Not Installed
OpenHarmony/ets        | 8 | 3.1.13.6 | Release | Not Installed
```

项目要求 `compatibleSdkVersion: 5.0.5(17)`（HarmonyOS NEXT API 17），目标 SDK 在 sdkmgr 公开源中**不存在**。

### 阻碍 3：OpenHarmony 公开 Linux SDK 不能直接替代闭源 HarmonyOS

理论上可以从 OpenHarmony 公开镜像（`repo.huaweicloud.com/openharmony/os/`）下载 Linux 工具链，替换 `sdk/default/openharmony/toolchains/` 中的 Windows 二进制。但项目的实际依赖结构存在以下问题：

1. 项目用了 `@hms.ai.*`、`@hw-agconnect/auth`、Map Kit、Push Kit 等 HMS 闭源 API
2. SDK 中存在 `sdk/default/hms/toolchains/` 这一**闭源 HMS 工具链子目录**，OpenHarmony 公开仓库**没有任何对应替代品**
3. OpenHarmony 公开版本进度滞后于 HarmonyOS 闭源版本（HarmonyOS 6.0.2 / API 22 对应的 OpenHarmony 版本可能尚未发布）
4. 即使工具链能跑通编译，输出的 `.abc` 字节码版本可能与 HarmonyOS 运行时不兼容

混搭存在 5+ 个不确定风险点，无法在合理时间内验证可行性。

---

## 四、否决方案备忘

| 方案 | 否决理由 |
|---|---|
| 直接拷贝 Windows DevEco SDK 到 Linux | 工具链是 Windows 二进制，Linux 无法执行 |
| 用 Wine 模拟运行 Windows 工具链 | hvigor 调用工具链频次高、参数复杂，Wine 不稳定 |
| 从华为官网下载 DevEco Studio Linux 版 | 经核实，华为官方未发布 Linux 版 DevEco Studio |
| 用 `commandline-tools-linux-2.0.0.2` + sdkmgr 安装目标 SDK | sdkmgr 公开源最高只到 OpenHarmony API 9，下载不到 API 17/22 |
| OpenHarmony 公开 Linux toolchains + 闭源 HarmonyOS 头文件混搭 | HMS 闭源工具链无开源替代；版本不匹配风险高；预估 1-2 天调试投入，失败概率显著 |

---

## 五、重启迁移的前置条件

只有以下任一条件满足时，才值得重新启动 Linux 迁移：

1. **华为发布官方 DevEco Studio Linux 版本**（最理想）
2. **华为以独立 zip 形式发布 Linux 版 HarmonyOS 工具链**（命令行版，包含 `restool` 等 Linux 二进制 + HMS 闭源工具）
3. **项目移除全部 HMS 依赖**，仅使用 OpenHarmony 公开 API，此时可用 OpenHarmony Linux SDK 跑全链路

在上述条件未满足前，CI 应继续运行在 Windows 服务器上。

---

## 六、本次工作的具体清单

### 在仓库中保留的产物

- 本文档：[linux-ci-migration-postmortem-zh.md](./linux-ci-migration-postmortem-zh.md)
- 之前编写的迁移指南：[linux-ci-migration-guide-zh.md](./linux-ci-migration-guide-zh.md)、[linux-jenkins-github-actions-migration-guide.md](./linux-jenkins-github-actions-migration-guide.md)、[linux-ci-handoff-for-claude-code.md](./linux-ci-handoff-for-claude-code.md) — 指导文档仍有参考价值，待前置条件满足时可直接复用

### 已撤回的仓库改动

下列文件在迁移尝试中曾被新增/修改，**已全部撤回，回到 commit `68de39a` 的状态**：

| 文件 | 操作 |
|---|---|
| `Jenkinsfile.linux` | 新增后已删除 |
| `frontend/build.sh` | 新增后已删除 |
| `scripts/watch-jenkins-build.sh` | 新增后已删除 |
| `.github/workflows/jenkinsfile-check.yml` | 修改后已 `git restore` 回 Windows 版 |

### 在新 Linux 服务器（`hcss-ecs-cfee`）上的部署

新服务器上已经完成以下安装/配置。若决定不再保留这台服务器，可整体回收；若保留作为测试沙箱，下列状态可继续维护：

- Java 21 / Jenkins / GitHub runner / Node.js v22 / ohpm 1.2.0
- 路径 `/home/26s-7/ci-server/`
- 来自队友 Windows DevEco 的 `deveco-sdk.zip` + `deveco-hvigor.zip` 及解压结果

### CI 当前状态

- GitHub Actions workflow `.github/workflows/jenkinsfile-check.yml` 仍指向 Windows self-hosted runner
- Jenkins job `travelpin-ci` 仍跑在 Windows 上
- 整体 CI 与本次迁移尝试前状态完全一致

---

## 七、对未来工作的建议

1. **跟踪 HarmonyOS Linux 工具链动态**：每 3-6 个月查一次华为开发者站，确认是否发布了 Linux 工具链
2. **不要修改 `build-profile.json5` 中的 SDK 版本以适配开源工具链**：会影响真机部署兼容性，不是合理代价
3. **如需 Linux 端能力**，可考虑 hybrid 方案：Linux 跑 GitHub Actions runner，通过 HTTP 远程触发 Windows Jenkins。这种半 Linux 化在 HarmonyOS 生态当前阶段是较常见的工程权衡。本次未实施，但可在未来评估
