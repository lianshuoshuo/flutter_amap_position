import 'package:flutter/services.dart';
import 'package:flutter_amap_location_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('demo shows initialization, permission, fix and stop controls', (
    tester,
  ) async {
    const location = MethodChannel('dev.hscw.flutter_amap_position/location');
    const permission = MethodChannel(
      'dev.hscw.flutter_amap_position/example_permissions',
    );
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(permission, (_) async => true);
    messenger.setMockMethodCallHandler(location, (call) async {
      if (call.method == 'initialize' &&
          call.arguments['privacyAgreed'] == false) {
        throw PlatformException(code: 'privacy_not_agreed');
      }
      if (call.method == 'getCurrentPosition') {
        return <String, Object>{
          'latitude': 30.0,
          'longitude': 110.0,
          'horizontalAccuracy': 12.5,
          'timestamp': 1700000000000,
          'coordinateSystem': 'GCJ02',
        };
      }
      return null;
    });

    await tester.pumpWidget(const LocationExample());
    await tester.tap(find.text('不同意'));
    await tester.pumpAndSettle();
    expect(find.text('未同意高德隐私政策'), findsOneWidget);

    await tester.tap(find.text('同意并初始化'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('申请定位权限'));
    await tester.pumpAndSettle();
    expect(find.text('定位权限已授予'), findsOneWidget);

    await tester.tap(find.text('单次定位'));
    await tester.pumpAndSettle();
    expect(find.text('纬度：30.000000'), findsOneWidget);
    expect(find.text('经度：110.000000'), findsOneWidget);
    expect(find.text('水平精度：12.5 米'), findsOneWidget);
    expect(find.textContaining('定位时间：'), findsOneWidget);

    await tester.tap(find.text('开始持续定位'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('停止定位'));
    await tester.pumpAndSettle();
    expect(find.text('持续定位已停止'), findsOneWidget);
  });
}
