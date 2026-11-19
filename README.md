# flutter_amap_position

通过高德原生定位 SDK 获取手机位置。Android、iOS 和 HarmonyOS NEXT 共用 Dart API。应用自行申请系统权限。定位插件可以单独运行。需要显示地图、标记和轨迹时，可同时安装地图插件。 [flutter_amap_map](https://pub.dev/packages/flutter_amap_map)

首版包含前台单次定位、持续定位和停止。地图蓝点、后台定位、地理围栏及轨迹存储属于首版范围之外。

## 安装

在宿主的 `pubspec.yaml` 中添加下面的依赖，再运行 `flutter pub get`。

```yaml
dependencies:
  flutter_amap_position: ^0.0.1
```

也可以运行 `flutter pub add flutter_amap_position`。本地开发时，在 `flutter_amap_position` 项下可改用 `path: ../flutter_amap_position`，路径以实际检出目录为准。

从 GitHub 标签 `v0.0.1` 迁移时，把原来的 `flutter_amap_location` Git 依赖换成上面的 pub.dev 依赖，并更新 Dart 导入及下方的 iOS Podfile 路径。

本仓库的 [example](example/README.md) 已配置本地依赖。用标准 Flutter 运行 Android、iOS，用支持 HarmonyOS NEXT 的 Flutter SDK 运行鸿蒙。同一份示例 Dart 代码可以在三端启动。

| 平台 | 插件最低系统 | 本轮构建 SDK |
| --- | --- | --- |
| Android | Android 7.0（API 24） | compileSdk 36，JDK 17 |
| iOS | iOS 13 | 示例用 iOS 15，CocoaPods，Xcode 27.2 |
| HarmonyOS NEXT | HarmonyOS 5.1.0（API 18） | Harmony SDK API 22，OHOS Flutter 3.41.9 |

## 配置 Key 和权限

在高德控制台为实际安装的 App 申请各端 Key。Android 绑定 applicationId 与签名 SHA-1，iOS 绑定 Bundle ID，HarmonyOS NEXT 绑定签名后的 AppID。两包共装时给同一平台的两个插件传相同的 Key。

**Android** 在宿主应用的 `AndroidManifest.xml` 中声明以下前台权限。宿主在定位前申请运行时权限，Android 12 起应同时请求这两项，由用户选择精确或大致位置。定位插件的 Manifest 提供网络权限和 SDK 所需的 `APSService`。

```xml
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

**iOS** 在宿主 `Info.plist` 设置 `NSLocationWhenInUseUsageDescription`，由宿主调用 `requestWhenInUseAuthorization()`。在 CocoaPods 的 `Runner` target 中，保留 Flutter 的安装逻辑，并添加定位 SDK 的来源声明。随后执行 `flutter pub get` 和 `pod install`。

```ruby
use_frameworks! :linkage => :static
flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
pod 'AMapLocation', :podspec => '.symlinks/plugins/flutter_amap_position/ios/sdk/AMapLocation.podspec.json'
```

**HarmonyOS NEXT** 在宿主 entry 的 `module.json5` 中声明 `ohos.permission.APPROXIMATELY_LOCATION` 和 `ohos.permission.LOCATION`，分别填写权限用途 `reason` 和 `usedScene.when: "inuse"`，由宿主请求授权。在工程的 `build-profile.json5` 产品配置里启用 `buildOption.strictMode.useNormalizedOHMUrl`。可直接参考 [示例权限配置](example/ohos/entry/src/main/module.json5) 和 [构建配置](example/ohos/build-profile.json5)。

## 初始化

宿主向用户展示含高德定位 SDK 内容的隐私政策，把用户的实际选择传给插件。拒绝时返回 `privacyNotAgreed`。接到同意后，插件按顺序更新高德隐私展示状态、同意状态，再设置 Key。初始化完成表示配置已交给 SDK，实际定位仍取决于权限、手机设置和 SDK 响应。

```dart
import 'package:flutter_amap_position/flutter_amap_position.dart';

await AMapLocation.initialize(
  apiKey: platformKey,
  privacyAgreed: userConsent,
);
```

## 单次定位

```dart
final fix = await AMapLocation.getCurrentPosition(
  timeout: const Duration(seconds: 12),
);

final latitude = fix.latitude;
final longitude = fix.longitude;
final accuracyInMeters = fix.horizontalAccuracy;
final timestamp = fix.timestamp; // UTC DateTime
final coordinateSystem = fix.coordinateSystem;
```

默认超时 15 秒。单次请求结束后会释放原生定位资源。

## 持续定位与停止

```dart
final subscription = AMapLocation.watchPosition().listen(
  updatePosition,
  onError: (Object error) => showLocationError(error),
);

// 按下停止按钮。
await AMapLocation.stop();

// 也可由页面自己的订阅触发清理。
await subscription.cancel();
```

开始监听时才启用原生定位，回调频率取决于系统和 SDK。同一时间只运行一个单次请求或一个持续会话。重复启动或并发请求会收到 `busy`，当前会话继续运行。停止和取消订阅都会释放会话，迟到的回调会被丢弃。后台、原生出错或撤回同意会结束会话，回到前台后由宿主重新启动。

### 错误

捕获 `AMapLocationException` 后根据 `code` 给用户提示。SDK 有提供原生错误码时，可读 `nativeCode` 和 `nativeDomain`。

| `code` | 含义 |
| --- | --- |
| `notInitialized` / `privacyNotAgreed` | 还未初始化 / 用户未同意隐私政策 |
| `permissionDenied` / `locationServicesDisabled` | 应用没有所需的定位权限 / 手机的系统定位开关关闭 |
| `timeout` / `sdkFailure` | 请求超时 / 原生 SDK 报错或给出无效位置 |
| `busy` / `notInForeground` | 已有定位请求 / 应用离开前台 |
| `cancelled` | 原生会话因引擎断开或重建被取消 |
| `invalidArgument` / `unsupportedPlatform` | Key 或参数不符合要求 / 当前运行平台没有对应的原生实现 |

## 与地图一起使用

先看每条位置的 `coordinateSystem`。只有 `gcj02` 可以直接用于地图插件的坐标参数。Android 读取 SDK 的 `getCoordType()`，HarmonyOS NEXT 读取返回值中的 `coordType`，缺失时返回 `unknown`。高德说明中国大陆及港澳台通常返回 GCJ-02，海外返回 WGS84。iOS 的回调对象没有逐次坐标系字段，插件保留原始坐标并标记为 `unknown`。 [高德坐标说明](https://lbs.amap.com/faq/advisory/others/39840/) · [Android 定位结果 API](https://a.amap.com/lbs/static/unzip/Android_Location_Doc/com/amap/api/location/AMapLocation.html) · [iOS 回调 API](https://a.amap.com/lbs/static/unzip/iOS_Location_Doc/interface_a_map_location_manager.html)

[两包共装与标记示例](doc/COEXISTENCE.md) · [第三方依赖与原生 SDK](THIRD_PARTY_NOTICES.md) · [验证记录](doc/VERIFICATION.md)
