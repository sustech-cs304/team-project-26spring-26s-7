# AGC 上架被驳回："只在隐私政策中的权限：[READ_IMAGEVIDEO]" 修改指引

## 根因诊断

| 数据点 | 说明 |
|---|---|
| AGC 报错 | "检测到当前软件包 user_grant 类型的权限与隐私政策中声明的权限不一致…只在隐私政策中的权限：[READ_IMAGEVIDEO]" |
| 含义 | AGC 扫描了你贴在 `https://agreement-drcn.hispace.dbankcloud.cn/...` 上的隐私政策文本，从中文 "图片和视频（读取用户公共目录的图片或视频文件）" 这段反推出 `ohos.permission.READ_IMAGEVIDEO`，然后跟我们 [module.json5:58-91](../../../frontend/entry/src/main/module.json5#L58-L91) 里的 `requestPermissions` 数组比对——发现 module.json5 根本没声明 `READ_IMAGEVIDEO`，于是判定不一致 |
| 实际行为 | 我们用的是 [PhotoPickerUtil.ets:49-53](../../../frontend/entry/src/main/ets/common/utils/PhotoPickerUtil.ets#L49-L53) 调 `photoAccessHelper.PhotoViewPicker` —— HarmonyOS 系统级图库选择器，**系统介入选图后只返回用户点中的那几张 URI 给应用，不需要 `READ_IMAGEVIDEO` 这种"通览相册"权限** |
| 真正要补的 | 不是给 module.json5 加权限（这反而会增加多余的运行时弹窗，跟实际行为不符），而是**把 AGC 隐私政策文本里 "图片和视频权限" 那段改掉**，跟实际行为对齐 |

## 操作步骤

### 1. 登录 AGC 控制台，找到隐私政策编辑入口

AppGallery Connect → 应用信息 → **隐私政策声明** （URL 末尾的 `agreementId=1960262032443858112` 那条）→ 编辑

### 2. 找到 "**2. 设备权限调用**" 这一节

原文（要改的部分）：

```
2. 设备权限调用
位置（获取设备位置信息）
用于地图页面的定位

图片和视频（读取用户公共目录的图片或视频文件）
用于上传节点旅行图片
```

### 3. 改成下面这版

把 "图片和视频" 整段删掉，改成说明走系统图库选择器：

```
2. 设备权限调用
位置（获取设备位置信息）
用于地图页面的定位

照片
我们通过 HarmonyOS 系统提供的"图库选择器"（PhotoViewPicker）让您主动
选择需要上传的照片，不申请 READ_IMAGEVIDEO（"图片和视频"）等读取整个
相册的权限——应用只能拿到您每次手动点选的照片，无法访问您的相册全集。
```

> **关键**：标题里**不要再出现 "图片和视频" 四个字一起**，否则 AGC 扫描器还是会反推成 `READ_IMAGEVIDEO`。
> 改用 "照片" 这个不与 HMOS 权限名同形的中文词。

### 4. 顺带也改一下 "**1.2**" 那段

原文：

```
1.2 ... 为了实现应用功能，在获取您的同意后我们需要收集您的 GPS 位置、 图片或视频 。
```

改成：

```
1.2 ... 为了实现应用功能，在获取您的同意后我们需要收集您的 GPS 位置；
照片由您通过系统图库选择器手动逐张选择后上传，本应用不申请通览整个相册的权限。
```

同样原因：把 "图片或视频" 这种与 HMOS 权限官方中文名 "图片和视频" 几乎重合的措辞换掉。

### 5. 保存 → 重新提交审核

改完点保存，AGC 那条 URL 的内容会立刻更新。然后回到应用上架界面，重新点 "提交审核" 即可。AGC 这次扫描隐私文本就不会再提取出 `READ_IMAGEVIDEO`，跟 module.json5 一致，校验通过。

## 为什么不去给 module.json5 加 READ_IMAGEVIDEO

**反向能不能解决？** 给 module.json5 加上 `READ_IMAGEVIDEO`，让 module 跟隐私文本字面一致，理论上能过这关校验。

**为什么不这样做**：
1. PhotoPicker 设计就是为了**避免**应用拿到这个权限——华为/谷歌都在推动这种"用户授权选图，应用不要相册访问权"的范式
2. 申请了 `READ_IMAGEVIDEO` 会触发**多余的运行时弹窗**让用户授权"是否允许访问全部图片"——但应用代码里根本不用这个权限去做 `MediaLibrary.query()` 之类的全相册查询，是死代码
3. AGC 隐私合规审核近年开始反向严查 "申请了但代码里没用到的权限"，加这个权限可能在隐私合规专项审核里被打回
4. **跟实际行为一致** 才是隐私政策的正确方向，文本去匹配代码而不是代码去凑文本

## 应用内的同款修改（已经做了）

我顺手把应用内 `资源/rawfile/privacy_policy.html` 的 "2.2 关于照片与 EXIF 元数据" 一节也加了一句明确说明走 PhotoViewPicker、不申请 READ_IMAGEVIDEO 的话术，跟 AGC 在线文本对齐。改动在 [privacy_policy.html](../../../frontend/entry/src/main/resources/rawfile/privacy_policy.html)。
