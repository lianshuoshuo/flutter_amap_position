# 运行高德定位示例

示例从本地插件目录安装依赖。屏幕显示经纬度、水平精度、定位时间、坐标系和回调次数。可以申请系统权限、单次定位、开始和停止持续定位。

1. 在本目录将 `config/keys.json.example` 复制为 `config/local.json`。
2. 填入当前平台的 Key。每次只填当前要运行的平台 Key。JSON 本地配置已被 Git 忽略。
3. 使用对应的 Flutter SDK 运行，在手机上阅读隐私政策并选择是否同意。接受后点击「申请定位权限」。

| 平台 | 示例应用标识 |
| --- | --- |
| Android | `dev.hscw.flutter_amap_position_example`，Key 还需匹配当前 APK 的签名 SHA-1 |
| iOS | `dev.hscw.flutterAmapPositionExample` |
| HarmonyOS NEXT | `dev.hscw.flutter_amap_position_example`，以签名后的 AppID 为准 |

Android 和 iOS 使用标准 Flutter。从本目录运行：

```bash
flutter pub get
flutter run -d <device-id> --dart-define-from-file=config/local.json
```

iOS 真机运行前，在 Xcode 为 Runner 设置自己的开发签名。Podfile 已配置定位 SDK 的下载来源。

HarmonyOS NEXT 请用 OHOS Flutter SDK，并先在 DevEco Studio 为示例配置签名：

```bash
"$OHOS_FLUTTER" pub get
"$OHOS_FLUTTER" run -d <device-id> --dart-define-from-file=config/local.json
```

切换 Flutter 工具链时建议为示例使用不同的工作副本，避免共用生成的依赖解析和原生构建目录。
