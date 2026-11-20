# NeoStatus 1.0.0 — 首个源码发布版

NeoStatus 是面向 **iPhone 15 Pro / iOS 17.0 / Relaxin + RootHide + ElleKit** 的 iOS 26 风格控制中心视觉预览插件。1.0.0 是首个可交付源码版本，交付范围是可配置的 SpringBoard 内 UIKit 预览面板与诊断工具，**不是 Apple 原生控制中心替换版**。

## 已包含

- SpringBoard 注入，仅匹配 `com.apple.springboard`。
- 设置入口：**设置 → NeoStatus**（PreferenceLoader + PreferenceBundle）。
- 总开关、预览手势、玻璃材质、圆角、彩色图标、媒体卡片和诊断日志设置。
- 默认关闭三击预览入口；启用后在主屏幕三击可打开 NeoStatus 预览。
- 两页控制中心视觉预览，支持本地控件排序、移除和添加。
- 亮度滑块（`UIScreen`）、音量（`MPVolumeView`）、媒体播放/暂停（`MPMusicPlayerController`）和手电筒（`AVCaptureDevice`）使用公开框架/API。
- Wi-Fi、蓝牙、蜂窝数据、飞行模式、个人热点、VPN、方向锁定、专注模式、录屏、屏幕镜像等控件明确标记为预览占位，不伪造系统状态，也不声称可以切换系统开关。
- 诊断快照：采集系统版本、设备型号、相关运行时类和方法类型编码、注入环境路径存在性；不收集序列号、Apple ID、Wi-Fi 名称、已安装 App 列表或个人内容。
- 诊断快照目录权限 `0700`、报告文件权限 `0600`，最多保留 10 份快照。
- RootHide Theos 工程，面向 iPhone 15 Pro 的 arm64e 切片，最低部署目标 iOS 17.0。

## 尚未包含（不要误认为已实现）

- 原生控制中心上滑手势/Overlay 接管。
- CCAster 的完整原生分页、编辑、拖动、缩放引擎移植。
- CC26 的完整系统视觉 Hook 移植。
- PowerModule 的原生 `CCUIContentModule` 模块及 CCSupport 注册。
- 全局系统状态栏替换。
- Wi-Fi、蓝牙等系统私有开关桥接。

这些部分需要在目标 iOS 17.0 设备上确认类、方法签名、调用时机及恢复路径。上游仓库可见不等于其源码可任意复制；本包未 vendoring CCAster/CC26/PowerModule 的源码。详见 `docs/UPSTREAM-PORT-MAP.md`。

## 依赖与目标

- iPhone 15 Pro / arm64e
- iOS 17.0
- Relaxin + RootHide
- ElleKit
- PreferenceLoader
- RootHide 版本 Theos 与可用 iOS SDK

## 编译

在已配置 RootHide Theos 的 macOS 环境中，于项目根目录执行：

```sh
./tools/build.sh
```

或：

```sh
make clean package
```

当前交付环境没有 Theos / iOS SDK，故此源码包**未声称已完成 Theos 编译，也不附带 DEB**。编译成功后请检查 DEB 内容，确认包含 `NeoStatus.plist`、`NeoStatusPrefs.plist` 和 `NeoStatusPrefs.bundle`。

## 首次安装与验证

1. 确认设备已安装 ElleKit 与 PreferenceLoader，并准备好可用的安全模式/移除插件恢复路径。
2. 编译并安装 DEB，重启 SpringBoard。
3. 检查 **设置 → NeoStatus** 是否出现。
4. 确认总开关开启、三击预览默认关闭。
5. 手动开启三击预览，返回主屏幕三击打开预览；再次关闭开关，确认手势移除。
6. 调整玻璃、圆角、图标和媒体卡片设置，重新打开预览确认视觉变化。
7. 请求诊断快照，检查诊断目录中的四份文本文件。

完整步骤见 `docs/BUILD-AND-TEST.md` 和 `docs/DEVICE-TEST.md`。

## 诊断目录

首选目录：

```text
/var/mobile/Library/Logs/NeoStatus/
```

若该路径不可写，插件会尝试基于 `NSHomeDirectory()` 的日志目录及 `/tmp/NeoStatus-Logs/`。设置面板可复制诊断目录并请求生成快照。

## 安全恢复

若 SpringBoard 不稳定，使用 Relaxin 的安全模式/禁用注入方式或包管理器移除 `com.neostatus.tweak`。SpringBoard 无法启动时，设置面板里的总开关不能作为恢复手段。

## 许可

本仓库 NeoStatus 原创代码采用 MIT License，见 `LICENSE`。上游项目说明与许可边界见 `THIRD_PARTY_NOTICES.md`。
