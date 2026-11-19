/// Coordinate reference system reported for an individual location fix.
enum AMapCoordinateSystem { gcj02, wgs84, unknown }

/// One native location fix. [timestamp] is in UTC.
final class AMapLocationFix {
  const AMapLocationFix({
    required this.latitude,
    required this.longitude,
    required this.horizontalAccuracy,
    required this.timestamp,
    required this.coordinateSystem,
  });

  final double latitude;
  final double longitude;

  /// Horizontal accuracy in metres, as reported by the SDK.
  final double horizontalAccuracy;
  final DateTime timestamp;
  final AMapCoordinateSystem coordinateSystem;

  factory AMapLocationFix.fromPlatform(Object? value) {
    if (value is! Map) {
      throw const AMapLocationException(AMapLocationErrorCode.sdkFailure);
    }
    final latitude = value['latitude'];
    final longitude = value['longitude'];
    final accuracy = value['horizontalAccuracy'];
    final timestamp = value['timestamp'];
    if (latitude is! num ||
        !latitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude is! num ||
        !longitude.isFinite ||
        longitude < -180 ||
        longitude > 180 ||
        accuracy is! num ||
        !accuracy.isFinite ||
        accuracy < 0 ||
        timestamp is! num ||
        !timestamp.isFinite ||
        timestamp <= 0 ||
        timestamp > 8640000000000000) {
      throw const AMapLocationException(AMapLocationErrorCode.sdkFailure);
    }
    return AMapLocationFix(
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      horizontalAccuracy: accuracy.toDouble(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        timestamp.toInt(),
        isUtc: true,
      ),
      coordinateSystem: switch (value['coordinateSystem']) {
        'GCJ02' => AMapCoordinateSystem.gcj02,
        'WGS84' => AMapCoordinateSystem.wgs84,
        _ => AMapCoordinateSystem.unknown,
      },
    );
  }
}

/// Errors shared by Android, iOS and HarmonyOS NEXT.
enum AMapLocationErrorCode {
  notInitialized,
  privacyNotAgreed,
  permissionDenied,
  locationServicesDisabled,
  timeout,
  sdkFailure,
  busy,
  notInForeground,
  cancelled,
  invalidArgument,
  unsupportedPlatform,
}

final class AMapLocationException implements Exception {
  const AMapLocationException(this.code, {this.nativeCode, this.nativeDomain});

  final AMapLocationErrorCode code;

  /// The native error code when one was supplied.
  final int? nativeCode;

  /// The native error domain when one was supplied, such as an iOS NSError domain.
  final String? nativeDomain;

  factory AMapLocationException.fromPlatform(Object? code, Object? details) {
    final nativeCode = details is Map ? details['nativeCode'] : null;
    final nativeDomain = details is Map ? details['nativeDomain'] : null;
    return AMapLocationException(
      switch (code) {
        'not_initialized' => AMapLocationErrorCode.notInitialized,
        'privacy_not_agreed' => AMapLocationErrorCode.privacyNotAgreed,
        'permission_denied' => AMapLocationErrorCode.permissionDenied,
        'location_services_disabled' =>
          AMapLocationErrorCode.locationServicesDisabled,
        'timeout' => AMapLocationErrorCode.timeout,
        'busy' => AMapLocationErrorCode.busy,
        'not_in_foreground' => AMapLocationErrorCode.notInForeground,
        'cancelled' => AMapLocationErrorCode.cancelled,
        'invalid_argument' => AMapLocationErrorCode.invalidArgument,
        'unsupported_platform' => AMapLocationErrorCode.unsupportedPlatform,
        _ => AMapLocationErrorCode.sdkFailure,
      },
      nativeCode: nativeCode is num ? nativeCode.toInt() : null,
      nativeDomain: nativeDomain is String ? nativeDomain : null,
    );
  }

  @override
  String toString() {
    final native = nativeCode == null
        ? ''
        : ' (${nativeDomain ?? 'SDK'} ${nativeCode!})';
    return 'AMapLocationException: ${code.name}$native';
  }
}
