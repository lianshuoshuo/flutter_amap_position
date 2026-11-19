import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_amap_location/flutter_amap_location.dart';

void main() => runApp(const LocationExample());

const _apiKey = String.fromEnvironment('AMAP_API_KEY');
const _permissions = MethodChannel(
  'dev.hscw.flutter_amap_position/example_permissions',
);

class LocationExample extends StatelessWidget {
  const LocationExample({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '高德定位示例',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff006b63)),
    ),
    home: const _LocationPage(),
  );
}

class _LocationPage extends StatefulWidget {
  const _LocationPage();

  @override
  State<_LocationPage> createState() => _LocationPageState();
}

class _LocationPageState extends State<_LocationPage> {
  bool _initialized = false;
  bool _working = false;
  StreamSubscription<AMapLocationFix>? _updates;
  AMapLocationFix? _fix;
  int _count = 0;
  String _status = '请先阅读隐私政策并选择是否同意';

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _working = true);
    try {
      await action();
    } on AMapLocationException catch (error) {
      _showError(error);
    } on PlatformException {
      if (mounted) setState(() => _status = '申请系统权限失败');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    if (error is! AMapLocationException) {
      setState(() => _status = '定位失败');
      return;
    }
    final message = switch (error.code) {
      AMapLocationErrorCode.notInitialized => '请先初始化',
      AMapLocationErrorCode.privacyNotAgreed => '未同意高德隐私政策',
      AMapLocationErrorCode.permissionDenied => '定位权限不足',
      AMapLocationErrorCode.locationServicesDisabled => '系统定位已关闭',
      AMapLocationErrorCode.timeout => '定位超时',
      AMapLocationErrorCode.sdkFailure => '高德定位失败',
      AMapLocationErrorCode.busy => '已有定位正在运行',
      AMapLocationErrorCode.notInForeground => '应用离开前台，定位已结束',
      AMapLocationErrorCode.cancelled => '定位已取消',
      AMapLocationErrorCode.invalidArgument =>
        _apiKey.isEmpty ? '还没有配置 AMAP_API_KEY' : '定位参数无效',
      AMapLocationErrorCode.unsupportedPlatform => '此平台不支持高德定位',
    };
    setState(() {
      final nativeCode = error.nativeCode;
      _status = nativeCode == null ? message : '$message（原生码 $nativeCode）';
    });
  }

  Future<void> _initialize(bool agreed) => _run(() async {
    setState(() {
      _initialized = false;
      if (!agreed) _fix = null;
    });
    await AMapLocation.initialize(apiKey: _apiKey, privacyAgreed: agreed);
    if (!mounted) return;
    setState(() {
      _initialized = true;
      _status = '定位已初始化，请申请系统定位权限';
    });
  });

  Future<void> _requestPermission() => _run(() async {
    final granted = await _permissions.invokeMethod<bool>('request');
    if (!mounted) return;
    setState(() => _status = granted == true ? '定位权限已授予' : '定位权限不足');
  });

  Future<void> _locateOnce() => _run(() async {
    setState(() => _status = '正在单次定位…');
    _showFix(await AMapLocation.getCurrentPosition());
  });

  void _start() {
    final subscription = AMapLocation.watchPosition().listen(
      _showFix,
      onError: _showError,
      onDone: () {
        if (mounted) setState(() => _updates = null);
      },
    );
    setState(() {
      _updates = subscription;
      _status = '正在持续定位…';
    });
  }

  Future<void> _stop() => _run(() async {
    await AMapLocation.stop();
    if (mounted) setState(() => _status = '持续定位已停止');
  });

  void _showFix(AMapLocationFix fix) {
    if (!mounted) return;
    setState(() {
      _fix = fix;
      _count++;
      _status = '已收到位置';
    });
  }

  @override
  void dispose() {
    unawaited(_updates?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canStart = _initialized && !_working && _updates == null;
    final fix = _fix;
    return Scaffold(
      appBar: AppBar(title: const Text('高德定位示例')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('同意后，示例会使用高德定位 SDK 获取手机位置。位置只显示在当前页面。'),
          const SizedBox(height: 6),
          const SelectableText('https://lbs.amap.com/pages/privacy/'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: !_working && _updates == null
                    ? () => _initialize(true)
                    : null,
                child: const Text('同意并初始化'),
              ),
              OutlinedButton(
                onPressed: !_working ? () => _initialize(false) : null,
                child: const Text('不同意'),
              ),
            ],
          ),
          const Divider(height: 30),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: canStart ? _requestPermission : null,
                child: const Text('申请定位权限'),
              ),
              FilledButton.tonal(
                onPressed: canStart ? _locateOnce : null,
                child: const Text('单次定位'),
              ),
              FilledButton.tonal(
                onPressed: canStart ? _start : null,
                child: const Text('开始持续定位'),
              ),
              OutlinedButton(
                onPressed: _updates != null && !_working ? _stop : null,
                child: const Text('停止定位'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(_status, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('已收到位置数：$_count'),
          if (fix != null) ...[
            Text('纬度：${fix.latitude.toStringAsFixed(6)}'),
            Text('经度：${fix.longitude.toStringAsFixed(6)}'),
            Text('水平精度：${fix.horizontalAccuracy.toStringAsFixed(1)} 米'),
            Text('定位时间：${fix.timestamp.toLocal()}'),
            Text('坐标系：${fix.coordinateSystem.name}'),
          ],
        ],
      ),
    );
  }
}
