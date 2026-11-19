# 地图与定位一起使用

在宿主安装本插件和 `flutter_amap_map: 0.0.1`，按各自的接入说明配置权限。在用户同意隐私政策后，用同一平台 Key 分别初始化定位和地图。

- Android 的 Flutter Gradle 加载器识别到 `:flutter_amap_map` 后，定位插件直接使用它已包含的高德合包。共装的宿主只需要一份合包。独立定位时使用同版本的定位 JAR。
- iOS 保留两个 SDK 的 `:podspec` 行，并核对 Podfile.lock 只有一份 `AMapFoundation 1.9.1`。
- HarmonyOS NEXT 的两个包共用 `common/location 11.2.1`。地图仍使用 `map3d 11.1.104`。只在 HarmonyOS 专属 Dart 入口调用地图插件的 `registerAMapHarmonyView()`，并按地图插件说明配置 ArkUI 宿主的纹理视图。定位沿用通用 Dart API。

在宿主已完成系统权限授权、且 `markerPngBytes` 是有效 PNG 时，可用真实定位结果建立标记：

```dart
import 'package:flutter_amap_location/flutter_amap_location.dart';
import 'package:flutter_amap_map/flutter_amap_map.dart';

// userConsent 是当前用户在宿主选择的结果。
await AMapLocation.initialize(apiKey: platformKey, privacyAgreed: userConsent);
await AMapSdk.initialize(apiKey: platformKey, privacyAgreed: userConsent);

final fix = await AMapLocation.getCurrentPosition();
if (fix.coordinateSystem == AMapCoordinateSystem.gcj02) {
  final map = AMapView(
    latitude: fix.latitude,
    longitude: fix.longitude,
    zoom: 17,
    markers: [
      AMapMarker(
        id: 'phone-location',
        latitude: fix.latitude,
        longitude: fix.longitude,
        pngBytes: markerPngBytes,
      ),
    ],
  );
  // 把 map 挂到页面上。
}
```

当坐标系为 `wgs84` 或 `unknown` 时，标记需要先取得已确认的 GCJ-02 坐标。本示例只转交 SDK 已确认的点。
