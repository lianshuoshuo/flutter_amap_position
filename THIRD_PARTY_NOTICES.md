# 第三方依赖

本仓库的桥接代码使用 MIT 许可证。以下依赖由各自的供应方提供，SDK 二进制由 Maven Central、CocoaPods 配置指向的官方 ZIP 和 OHPM 下载。

| 平台 | 固定依赖 | 许可与来源 |
| --- | --- | --- |
| Android 独立使用 | `com.amap.api:location:11.2.100` | 高德 SDK，许可见 Maven POM。[Maven Central](https://repo.maven.apache.org/maven2/com/amap/api/location/11.2.100/) |
| Android 与地图共用 | `com.amap.api:3dmap-location-search:11.2.100_loc11.2.100_sea9.8.1` | 高德 SDK。合包中的定位与独立包版本相同。[Maven Central](https://repo.maven.apache.org/maven2/com/amap/api/3dmap-location-search/11.2.100_loc11.2.100_sea9.8.1/) |
| iOS | `AMapLocation 2.12.2`、`AMapFoundation 1.9.1` | 高德 SDK。CocoaPods spec 许可为版权所有，分别由宿主引用官方 ZIP 和 CocoaPods trunk。[高德下载](https://lbs.amap.com/api/ios-location-sdk/download/) |
| HarmonyOS NEXT | `@amap/amap_lbs_location 11.2.1`、`@amap/amap_lbs_common 11.2.1` | 高德 SDK。OHPM 中这两个制品的许可字段为 Apache-2.0。[location](https://ohpm.openharmony.cn/ohpm/@amap/amap_lbs_location) · [common](https://ohpm.openharmony.cn/ohpm/@amap/amap_lbs_common) |
| Dart | Flutter SDK | BSD-3-Clause。[Flutter 许可证](https://github.com/flutter/flutter/blob/master/LICENSE) |

iOS 的 [AMapLocation podspec](ios/sdk/AMapLocation.podspec.json) 基于官方 CocoaPods 描述文件补充了 ZIP 的 SHA-256 和 `AMapLocation.bundle` 的打包声明。两个 Flutter 包共装时只链接一份 `AMapFoundation 1.9.1`。需要针对 Apple Silicon 模拟器构建时，应先确认此基础库的模拟器架构。当前验证产物为真机架构。

Android 的开发指南给出定位 SDK 的通用系统兼容性说明。11.2.100 的 Maven 制品为 JAR，POM 未声明专用的 Android API 下限。插件与示例以 Flutter 支持范围和项目 Manifest 设置的 API 24 为最低版本。 [高德兼容性](https://lbs.amap.com/api/android-location-sdk/locationsummary/#t5)

iOS 定位 Pod 声明的最低系统为 iOS 9，本插件最低为 iOS 13。HarmonyOS NEXT 11.2.1 HAR 声明兼容 API 12，本插件及示例以 OHOS Flutter 示例模板的 API 18 为应用下限。构建和真机验证范围见 [验证记录](doc/VERIFICATION.md)。

定位数据可能由设备系统及高德 SDK 处理。应用方应把高德定位 SDK 纳入隐私政策，并按使用场景取得用户同意。 [高德隐私政策](https://lbs.amap.com/pages/privacy/) · [SDK 合规使用说明](https://lbs.amap.com/compliance-center/check-and-reference/sdkhgsy)
