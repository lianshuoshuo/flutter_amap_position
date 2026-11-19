import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_amap_location/flutter_amap_location.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('dev.hscw.flutter_amap_position/location');
const _fix = <String, Object>{
  'latitude': 30.0,
  'longitude': 110.0,
  'horizontalAccuracy': 12.5,
  'timestamp': 1700000000000,
  'coordinateSystem': 'GCJ02',
};

TypeMatcher<AMapLocationException> hasCode(AMapLocationErrorCode code) =>
    isA<AMapLocationException>().having((error) => error.code, 'code', code);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<void> event(String method, Map<String, Object> args) async {
    await messenger.handlePlatformMessage(
      _channel.name,
      _channel.codec.encodeMethodCall(MethodCall(method, args)),
      null,
    );
  }

  tearDown(() async {
    await AMapLocation.stop();
    messenger.setMockMethodCallHandler(_channel, null);
  });

  test('initialize carries the host decision and passes on refusal', () async {
    messenger.setMockMethodCallHandler(_channel, (call) async {
      expect(call.method, 'initialize');
      expect(call.arguments['apiKey'], 'example-key');
      expect(call.arguments['clientId'], isA<String>());
      if (call.arguments['privacyAgreed'] == false) {
        throw PlatformException(code: 'privacy_not_agreed');
      }
      expect(call.arguments['privacyAgreed'], true);
      return null;
    });

    await expectLater(
      AMapLocation.initialize(apiKey: 'example-key', privacyAgreed: false),
      throwsA(hasCode(AMapLocationErrorCode.privacyNotAgreed)),
    );
    await AMapLocation.initialize(apiKey: 'example-key', privacyAgreed: true);
  });

  test('one-shot returns a typed fix and forwards the deadline', () async {
    messenger.setMockMethodCallHandler(_channel, (call) async {
      expect(call.method, 'getCurrentPosition');
      expect(call.arguments['timeoutMs'], 2400);
      return _fix;
    });

    final location = await AMapLocation.getCurrentPosition(
      timeout: const Duration(milliseconds: 2400),
    );
    expect(location.latitude, 30);
    expect(location.longitude, 110);
    expect(location.horizontalAccuracy, 12.5);
    expect(location.timestamp, DateTime.utc(2023, 11, 14, 22, 13, 20));
    expect(location.coordinateSystem, AMapCoordinateSystem.gcj02);
  });

  test(
    'one-shot preserves WGS84 and leaves unlabelled fixes unknown',
    () async {
      var coordinateSystem = 'WGS84';
      messenger.setMockMethodCallHandler(_channel, (_) async {
        return {..._fix, 'coordinateSystem': coordinateSystem};
      });
      expect(
        (await AMapLocation.getCurrentPosition()).coordinateSystem,
        AMapCoordinateSystem.wgs84,
      );

      coordinateSystem = 'undocumented';
      expect(
        (await AMapLocation.getCurrentPosition()).coordinateSystem,
        AMapCoordinateSystem.unknown,
      );
    },
  );

  test(
    'invalid fixes and unsupported platforms are explicit failures',
    () async {
      await expectLater(
        AMapLocation.getCurrentPosition(),
        throwsA(hasCode(AMapLocationErrorCode.unsupportedPlatform)),
      );
      messenger.setMockMethodCallHandler(
        _channel,
        (_) async => {..._fix, 'horizontalAccuracy': -1},
      );
      await expectLater(
        AMapLocation.getCurrentPosition(),
        throwsA(hasCode(AMapLocationErrorCode.sdkFailure)),
      );
      await expectLater(
        AMapLocation.getCurrentPosition(timeout: Duration.zero),
        throwsA(hasCode(AMapLocationErrorCode.invalidArgument)),
      );
    },
  );

  for (final testCase in {
    'not_initialized': AMapLocationErrorCode.notInitialized,
    'privacy_not_agreed': AMapLocationErrorCode.privacyNotAgreed,
    'permission_denied': AMapLocationErrorCode.permissionDenied,
    'location_services_disabled':
        AMapLocationErrorCode.locationServicesDisabled,
    'timeout': AMapLocationErrorCode.timeout,
    'sdk_failure': AMapLocationErrorCode.sdkFailure,
    'busy': AMapLocationErrorCode.busy,
    'not_in_foreground': AMapLocationErrorCode.notInForeground,
  }.entries) {
    test(
      'one-shot translates ${testCase.key} and preserves native details',
      () async {
        messenger.setMockMethodCallHandler(_channel, (_) async {
          throw PlatformException(
            code: testCase.key,
            details: {'nativeCode': 12, 'nativeDomain': 'AMapLocation'},
          );
        });
        await expectLater(
          AMapLocation.getCurrentPosition(),
          throwsA(
            hasCode(testCase.value)
                .having((error) => error.nativeCode, 'nativeCode', 12)
                .having(
                  (error) => error.nativeDomain,
                  'nativeDomain',
                  'AMapLocation',
                ),
          ),
        );
      },
    );
  }

  test('a rejected subscription emits a typed error and closes', () async {
    messenger.setMockMethodCallHandler(_channel, (call) async {
      expect(call.method, 'startUpdates');
      throw PlatformException(code: 'busy');
    });
    await expectLater(
      AMapLocation.watchPosition(),
      emitsInOrder([
        emitsError(hasCode(AMapLocationErrorCode.busy)),
        emitsDone,
      ]),
    );
  });

  test(
    'duplicate watch and one-shot leave the first subscription intact',
    () async {
      final started = Completer<String>();
      final received = Completer<AMapLocationFix>();
      messenger.setMockMethodCallHandler(_channel, (call) async {
        switch (call.method) {
          case 'startUpdates':
            started.complete(call.arguments['id'] as String);
          case 'getCurrentPosition':
            throw PlatformException(code: 'busy');
          case 'stopUpdates':
            expect(call.arguments['id'], await started.future);
          default:
            fail('Unexpected call ${call.method}');
        }
        return null;
      });
      final first = AMapLocation.watchPosition().listen(received.complete);
      final id = await started.future;
      await expectLater(
        AMapLocation.watchPosition(),
        emitsInOrder([
          emitsError(hasCode(AMapLocationErrorCode.busy)),
          emitsDone,
        ]),
      );
      await expectLater(
        AMapLocation.getCurrentPosition(),
        throwsA(hasCode(AMapLocationErrorCode.busy)),
      );
      await event('position', {'id': id, 'fix': _fix});
      expect((await received.future).latitude, 30);
      await first.cancel();
    },
  );

  test(
    'stop drops buffered and late callbacks, and waits for native cleanup',
    () async {
      final stopped = Completer<void>();
      final ids = <String>[];
      messenger.setMockMethodCallHandler(_channel, (call) async {
        if (call.method == 'startUpdates') {
          ids.add(call.arguments['id'] as String);
        }
        if (call.method == 'stopUpdates') {
          expect(call.arguments['id'], ids.last);
          await stopped.future;
        }
        return null;
      });

      final positions = <AMapLocationFix>[];
      final watch = AMapLocation.watchPosition();
      expect(ids, isEmpty);
      final first = watch.listen(positions.add)..pause();
      final done = first.asFuture<void>();
      await event('position', {'id': ids.single, 'fix': _fix});
      var stopHasReturned = false;
      final stop = AMapLocation.stop();
      final anotherStop = AMapLocation.stop().then(
        (_) => stopHasReturned = true,
      );
      await event('position', {'id': ids.single, 'fix': _fix});
      expect(stopHasReturned, false);
      expect(positions, isEmpty);

      stopped.complete();
      await stop;
      await anotherStop;
      first.resume();
      await done;
      expect(positions, isEmpty);

      final secondFix = Completer<AMapLocationFix>();
      final second = AMapLocation.watchPosition().listen(secondFix.complete);
      expect(ids, hasLength(2));
      await event('position', {'id': ids.first, 'fix': _fix});
      expect(secondFix.isCompleted, false);
      await event('position', {'id': ids.last, 'fix': _fix});
      expect((await secondFix.future).horizontalAccuracy, 12.5);
      await second.cancel();
    },
  );

  test(
    'cancellation releases a watch even while start is awaiting its reply',
    () async {
      final started = Completer<void>();
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        if (call.method == 'startUpdates') await started.future;
        return null;
      });

      final watch = AMapLocation.watchPosition().listen(
        (_) => fail('Late fix'),
      );
      await watch.cancel();
      expect(calls.map((call) => call.method), ['startUpdates', 'stopUpdates']);
      expect(calls.last.arguments, calls.first.arguments);
      started.complete();
    },
  );

  test(
    'native terminal error ends the stream with its own session ID',
    () async {
      final started = Completer<String>();
      messenger.setMockMethodCallHandler(_channel, (call) async {
        expect(call.method, 'startUpdates');
        started.complete(call.arguments['id'] as String);
        return null;
      });

      final terminal = expectLater(
        AMapLocation.watchPosition(),
        emitsInOrder([
          emitsError(
            hasCode(
              AMapLocationErrorCode.sdkFailure,
            ).having((error) => error.nativeCode, 'nativeCode', 7),
          ),
          emitsDone,
        ]),
      );
      final id = await started.future;
      await event('positionError', {
        'id': 'older',
        'code': 'permission_denied',
      });
      await event('positionError', {
        'id': id,
        'code': 'sdk_failure',
        'details': {'nativeCode': 7},
      });
      await terminal;
    },
  );
}
