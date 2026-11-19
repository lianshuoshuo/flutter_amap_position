# 本地验证记录

验证日期 2026-11-19。当时定位包名为 `flutter_amap_position 0.0.1`，共装宿主依赖 pub.dev 已公开的 `flutter_amap_map 0.0.1`。该宿主由示例临时复制，联动逻辑见 [共装说明](COEXISTENCE.md)。

## Dart

标准 Flutter 3.44.6 静态分析无问题。17 项插件测试和 1 项示例组件测试通过。测试覆盖错误和原生码转换、未识别的坐标系、重复订阅、单次与持续并发时的错误、取消、停止后丢弃已排队和迟到的事件。测试的坐标来自模拟 method channel。OHOS Flutter 3.41.9 下也单独分析了共装宿主的 Harmony 入口和共用 Dart 页面，未发现问题。

## 原生构建

| 平台 | 独立示例 | 共装宿主 | 依赖检查 |
| --- | --- | --- | --- |
| Android | Debug APK 通过 | Debug APK 通过 | `checkDebugDuplicateClasses` 通过。独立版解析到 `location 11.2.100`，共装版解析到包含同版定位 SDK 的 `3dmap-location-search`。 |
| iOS | arm64 iPhoneOS 构建通过 | arm64 iPhoneOS 构建通过 | CocoaPods 只解析一份 `AMapFoundation 1.9.1`。共装包同时包含地图与定位资源，链接通过。 |
| HarmonyOS NEXT | Hvigor 构建未签名 HAP 通过 | Hvigor 构建未签名 HAP 通过 | entry 的 OHPM 锁文件只有一个 `common 11.2.1` 和一个 `location 11.2.1`；共装 HAP 只有一份定位原生库。 |

Android 和 iOS 使用标准 Flutter 3.44.6。HarmonyOS NEXT 使用 OHOS Flutter 3.41.9、Harmony SDK API 22，以 API 18 为应用兼容下限。Harmony 工程在缺少签名时仍会生成 unsigned HAP，Flutter CLI 随后提示配置签名。本轮以 Hvigor 的成功退出和 HAP 内容确认编译与打包。

## 真机结果

- **Android，CET-AL00 / Android 12。** 真机使用已有测试应用标识和与其匹配的 Key。已覆盖隐私拒绝、首次系统定位权限弹窗中的拒绝与允许、系统定位关闭。定位独立版和共装版均收到真实单次定位及持续定位事件。停止后观察 10 秒，回调计数没有增长。共装宿主将 SDK 标记为 GCJ-02 的真机结果交给地图，地图已加载并回传了该标记的点击。测试后恢复原地图测试 APK，并核对 SHA-256。
- **iOS，iPhone 15 Pro / iOS 27.2。** USB 上的 Release 共装测试宿主通过隐私拒绝、系统权限拒绝、首次授权和真实单次定位，持续会话收到真实位置，延长观察 35 秒后确认有后续位置更新。停止后观察 8 秒，回调计数没有增长。临时 Bundle ID 使用本地测试 Key，绑定 Key 的地图联动尚未验证。定位回调缺少逐次坐标系字段，标记示例跳过该点。
- **HarmonyOS NEXT。** `hdc` 未发现设备。首次授权、权限拒绝、单次定位、连续更新、停止和实时标记仍待真机验证。

验收只记录回调是否成功、坐标系标签、事件次数和地图标记点击是否收到。
