import 'dart:async';

import 'package:flutter/services.dart';

import 'src/location_result.dart';

export 'src/location_result.dart'
    show
        AMapCoordinateSystem,
        AMapLocationErrorCode,
        AMapLocationException,
        AMapLocationFix;

/// Foreground location via the platform AMap Location SDK.
///
/// Call from the app's Flutter UI isolate. The host presents the privacy
/// policy and obtains the operating system's location permission.
abstract final class AMapLocation {
  static const _channel = MethodChannel(
    'dev.hscw.flutter_amap_position/location',
  );
  static final _clientId = DateTime.now().microsecondsSinceEpoch.toString();
  static int _nextWatchId = 0;
  static _WatchSession? _watch;
  static Future<void>? _stopping;

  /// Configures this platform's key after the user's actual privacy decision.
  ///
  /// Passing false reports [AMapLocationErrorCode.privacyNotAgreed] and
  /// prevents further location requests until the user consents.
  static Future<void> initialize({
    required String apiKey,
    required bool privacyAgreed,
  }) => _invoke<void>('initialize', {
    'apiKey': apiKey,
    'privacyAgreed': privacyAgreed,
    'clientId': _clientId,
  });

  /// Requests one fix. The native request is released on completion or timeout.
  ///
  /// Only one one-shot request or foreground stream can run at a time.
  static Future<AMapLocationFix> getCurrentPosition({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final milliseconds = timeout.inMilliseconds;
    if (milliseconds < 1 || milliseconds > 0x7fffffff) {
      throw const AMapLocationException(AMapLocationErrorCode.invalidArgument);
    }
    final value = await _invoke<Object>('getCurrentPosition', {
      'timeoutMs': milliseconds,
    });
    return AMapLocationFix.fromPlatform(value);
  }

  /// Starts a foreground session when listened to.
  ///
  /// Each call produces a single-subscription stream. An active request is
  /// left running if another call fails with [AMapLocationErrorCode.busy].
  /// A native error ends this stream. Cancelling the subscription releases
  /// its native session.
  static Stream<AMapLocationFix> watchPosition() {
    final watch = _WatchSession('$_clientId/${_nextWatchId++}');
    watch.events
      ..onListen = () {
        if (_watch != null) {
          watch.events.addError(
            const AMapLocationException(AMapLocationErrorCode.busy),
          );
          unawaited(watch.events.close());
          return;
        }
        _channel.setMethodCallHandler(_onNativeEvent);
        _watch = watch;
        unawaited(_start(watch));
      }
      ..onCancel = () => _stop(watch);
    return watch.events.stream.where((_) => !watch.stopped);
  }

  /// Stops the active stream and waits for native cleanup.
  ///
  /// A pending one-shot request is allowed to finish independently.
  static Future<void> stop() {
    final watch = _watch;
    return watch == null ? _stopping ?? Future<void>.value() : _stop(watch);
  }

  static Future<void> _start(_WatchSession watch) async {
    try {
      await _invoke<void>('startUpdates', {'id': watch.id});
    } on AMapLocationException catch (error) {
      _fail(watch, error);
    }
  }

  static Future<void> _stop(_WatchSession watch) {
    if (!identical(watch, _watch)) return Future<void>.value();

    // Invalidate locally before the native stop, including buffered stream events.
    _watch = null;
    watch.stopped = true;
    unawaited(watch.events.close());
    final pending = _invoke<void>('stopUpdates', {'id': watch.id});
    _stopping = pending;
    return pending.whenComplete(() {
      if (identical(_stopping, pending)) _stopping = null;
    });
  }

  static Future<void> _onNativeEvent(MethodCall call) async {
    final watch = _watch;
    final args = call.arguments;
    if (watch == null || args is! Map || args['id'] != watch.id) return;

    switch (call.method) {
      case 'position':
        try {
          watch.events.add(AMapLocationFix.fromPlatform(args['fix']));
        } on AMapLocationException catch (error) {
          // An invalid native fix terminates the same session that sent it.
          watch.events.addError(error);
          try {
            await _stop(watch);
          } on AMapLocationException {
            // The stream already delivered the error.
          }
        }
      case 'positionError':
        _fail(
          watch,
          AMapLocationException.fromPlatform(args['code'], args['details']),
        );
    }
  }

  static void _fail(_WatchSession watch, AMapLocationException error) {
    if (!identical(watch, _watch)) return;
    _watch = null;
    watch.events.addError(error);
    unawaited(watch.events.close());
  }

  static Future<T?> _invoke<T>(String method, Map<String, Object> args) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      throw const AMapLocationException(
        AMapLocationErrorCode.unsupportedPlatform,
      );
    } on PlatformException catch (error) {
      throw AMapLocationException.fromPlatform(error.code, error.details);
    }
  }
}

final class _WatchSession {
  _WatchSession(this.id);

  final String id;
  final events = StreamController<AMapLocationFix>();
  bool stopped = false;
}
