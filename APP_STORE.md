# Lyssen App Store 发布准备清单

本文档记录将 Lyssen 发布到 Mac App Store 前需要完成的准备工作。

## 当前状态

- GitHub 仓库：`https://github.com/WishingCat/Lyssen`
- 当前公开版本：`v1.0.0`
- 当前 Bundle ID：`com.wishingcat.lyssen.menubar`
- 当前分发方式：GitHub Release zip
- 当前构建方式：`swiftc` + ad-hoc 签名
- App Store 沙盒 entitlement：`源码/LyssenAppStore.entitlements`

当前版本适合直接分发和 GitHub Release，但还不是 Mac App Store 标准提交包。

## App Store 必做项

### 1. Apple Developer 账号

需要有效的 Apple Developer Program 会员账号，并在 App Store Connect 中拥有创建 App、上传构建、提交审核的权限。

### 2. 完整 Xcode

当前机器只有 Command Line Tools，无法使用 `xcodebuild archive`。提交 Mac App Store 前需要安装完整 Xcode，并在 Xcode 中登录 Apple ID。

### 3. Xcode 工程

需要把当前单文件 Swift 项目整理成 Xcode macOS App 工程，以便：

- 生成 App Store Archive
- 配置 Signing & Capabilities
- 配置 App Sandbox entitlement
- 上传构建到 App Store Connect 或 TestFlight

### 4. App Sandbox

Mac App Store 应用需要启用 App Sandbox。Lyssen 的核心能力是通过 CoreAudio 修改系统默认输入设备，因此需要专门验证：

- 沙盒环境下能否读取音频设备列表
- 沙盒环境下能否监听默认输入/输出变化
- 沙盒环境下能否调用 CoreAudio 切换默认输入设备

如果沙盒阻止核心能力，Mac App Store 版本可能需要调整功能，或继续采用 GitHub + notarized direct distribution 的分发路线。

#### 2026-06-21 本机沙盒测试结果

已使用 `com.apple.security.app-sandbox = true` 构建 `dist/Lyssen Sandbox.app`，并通过隐藏探针 `LYSSEN_SANDBOX_PROBE=1` 在沙盒 App 内执行 CoreAudio 测试。

通过项：

- 沙盒 App 可启动为菜单栏后台应用。
- 菜单栏 `L` 可见。
- 设置窗口可打开。
- 沙盒内可读取音频设备列表。
- 沙盒内可读取当前默认输入设备。
- 沙盒内可读取当前默认输出设备。
- 沙盒内调用 CoreAudio 设置当前输入为当前设备返回成功。
- 沙盒内调用 CoreAudio 设置当前输入为内置麦克风返回成功。

本机测试设备：

- 当前输入：MacBook Pro 麦克风
- 当前输出：MacBook Pro 扬声器
- 其他输入：TRTC Audio Device

未完成项：

- 早期测试时未连接可作为默认输入切换目标的蓝牙耳机麦克风，TRTC Audio Device 虽然对 `AudioObjectSetPropertyData` 返回成功，但系统没有实际把默认输入切到该虚拟设备，因此不能用它替代蓝牙麦克风完成最终验证。

#### 2026-06-21 蓝牙耳机端到端沙盒测试结果

已连接蓝牙耳机 `HUAWEI FreeClip 2` 后重新测试。

测试步骤：

1. 关闭普通 Lyssen 与沙盒 Lyssen。
2. 将系统默认输入手动切到 `HUAWEI FreeClip 2`。
3. 确认切换前当前输入为 `HUAWEI FreeClip 2`。
4. 启动带 App Sandbox 的 `Lyssen Sandbox.app`。
5. 读取沙盒探针报告并再次检查系统默认输入。

结果：

- 切换前输入：`HUAWEI FreeClip 2`
- 沙盒 Lyssen 启动后输入：`MacBook Pro 麦克风`
- 沙盒 Lyssen 启动后输出：`HUAWEI FreeClip 2`
- `setCurrentInput.ok=true`
- `setBuiltinInput.ok=true`

结论：

App Sandbox 没有阻止 Lyssen 的核心 CoreAudio 守护逻辑。当前测试环境下，沙盒版 Lyssen 可以在蓝牙耳机麦克风成为默认输入后，把默认输入切回 Mac 内置麦克风，同时保留蓝牙耳机作为输出设备。

### 5. App Store Connect 信息

建议填写：

- App 名称：Lyssen
- 副标题：Bluetooth audio quality guard
- 分类：Utilities
- 年龄分级：4+
- 价格：免费
- 隐私政策 URL：仓库中的 `PRIVACY.md`，或独立网站页面
- Support URL：GitHub Issues 或项目主页
- Marketing URL：GitHub 仓库或产品页

### 6. 隐私回答

Lyssen 当前设计：

- 不联网
- 不录音
- 不上传数据
- 不使用第三方 SDK
- 不追踪用户

App Privacy 可以按“未收集数据”方向填写，但提交前仍需再次核对代码。

### 7. 审核说明建议

提交审核时建议在 App Review Notes 中说明：

> Lyssen is a macOS menu bar utility that helps keep Bluetooth headphones in high-quality playback mode. It observes the system default audio input/output device through CoreAudio. When the system default input switches to a Bluetooth headset microphone, the app switches the default input back to the built-in Mac microphone. The app does not record audio, transmit audio, collect user data, or use network access.

同时建议说明测试方法：

1. Connect Bluetooth headphones with a microphone.
2. Open Lyssen from the menu bar.
3. Switch the system input to the Bluetooth microphone.
4. Lyssen switches input back to the built-in microphone.

## 发布流程

1. 安装并打开完整 Xcode。
2. 创建 Apple Developer App ID：`com.wishingcat.lyssen.menubar`。
3. 在 App Store Connect 创建 macOS App 记录。
4. 创建 Xcode 工程并配置 App Sandbox。
5. 本地测试沙盒版本核心功能。
6. 使用 Xcode Archive。
7. Validate App。
8. 上传构建到 App Store Connect。
9. 填写截图、描述、隐私、年龄分级、审核说明。
10. 先提交 TestFlight，确认安装和运行无问题。
11. 提交 App Review。

## 风险判断

最大风险不是界面，也不是打包，而是 App Sandbox 对系统音频默认输入切换能力的限制。

如果沙盒版本无法切换默认输入，比较现实的替代方案是：

- 继续 GitHub Release 分发
- 使用 Developer ID 正式签名
- 做 Apple notarization
- 提供 DMG 下载包

这条路线不是 Mac App Store，但对系统级菜单栏工具通常更宽松。
