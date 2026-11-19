import CoreLocation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, CLLocationManagerDelegate {
    private lazy var permissionManager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = self
        return manager
    }()
    private var pending: FlutterResult?

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
        let channel = FlutterMethodChannel(
            name: "dev.hscw.flutter_amap_position/example_permissions",
            binaryMessenger: engineBridge.applicationRegistrar.messenger()
        )
        channel.setMethodCallHandler { [weak self] call, result in
            guard call.method == "request", let self = self else {
                result(FlutterMethodNotImplemented)
                return
            }
            if self.pending != nil {
                result(FlutterError(code: "busy", message: nil, details: nil))
            } else if self.permissionManager.authorizationStatus == .notDetermined {
                self.pending = result
                self.permissionManager.requestWhenInUseAuthorization()
            } else {
                result(self.allowed(self.permissionManager.authorizationStatus))
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined, let reply = pending else { return }
        pending = nil
        reply(allowed(manager.authorizationStatus))
    }

    private func allowed(_ status: CLAuthorizationStatus) -> Bool {
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }
}
