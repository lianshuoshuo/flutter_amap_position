import AMapFoundationKit
import AMapLocationKit
import CoreLocation
import Flutter
import UIKit

public final class FlutterAmapPositionPlugin: NSObject, FlutterPlugin, AMapLocationManagerDelegate {
    private final class Request {
        let id: String?
        var reply: FlutterResult?
        var manager: AMapLocationManager?
        var timer: DispatchWorkItem?

        init(id: String?, reply: @escaping FlutterResult) {
            self.id = id
            self.reply = reply
        }
    }

    private let channel: FlutterMethodChannel
    private var initialized = false
    private var privacyDeclined = false
    private var clientId: String?
    private var active: Request?

    private init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(didEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil
        )
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "dev.hscw.flutter_amap_position/location",
            binaryMessenger: registrar.messenger()
        )
        let plugin = FlutterAmapPositionPlugin(channel: channel)
        registrar.addMethodCallDelegate(plugin, channel: channel)
        registrar.publish(plugin)
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        if let request = active { fail(request, "cancelled") }
        NotificationCenter.default.removeObserver(self)
        channel.setMethodCallHandler(nil)
        initialized = false
        privacyDeclined = false
        clientId = nil
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        switch call.method {
        case "initialize":
            initialize(args, result: result)
        case "getCurrentPosition":
            guard let timeout = args?["timeoutMs"] as? Int, (1...Int(Int32.max)).contains(timeout) else {
                result(failure("invalid_argument"))
                return
            }
            start(Request(id: nil, reply: result), timeoutMs: timeout)
        case "startUpdates":
            guard let id = args?["id"] as? String, !id.isEmpty else {
                result(failure("invalid_argument"))
                return
            }
            start(Request(id: id, reply: result), timeoutMs: nil)
        case "stopUpdates":
            if let request = active, let id = request.id, id == args?["id"] as? String {
                release(request)
                // A stop can arrive while the permission preflight is still running.
                request.reply?(failure("cancelled"))
            }
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func initialize(_ args: [String: Any]?, result: FlutterResult) {
        guard args?["privacyAgreed"] as? Bool == true else {
            initialized = false
            privacyDeclined = true
            if let request = active { fail(request, "privacy_not_agreed") }
            result(failure("privacy_not_agreed"))
            return
        }
        guard let key = (args?["apiKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty, let caller = args?["clientId"] as? String, !caller.isEmpty else {
            result(failure("invalid_argument"))
            return
        }
        if clientId != caller, let request = active { fail(request, "cancelled") }
        guard active == nil else {
            result(failure("busy"))
            return
        }
        AMapLocationManager.updatePrivacyShow(.didShow, privacyInfo: .didContain)
        AMapLocationManager.updatePrivacyAgree(.didAgree)
        AMapServices.shared().apiKey = key
        clientId = caller
        privacyDeclined = false
        initialized = true
        result(nil)
    }

    private func start(_ request: Request, timeoutMs: Int?) {
        let error: String?
        if privacyDeclined { error = "privacy_not_agreed" }
        else if !initialized { error = "not_initialized" }
        else if active != nil { error = "busy" }
        else if UIApplication.shared.applicationState == .background { error = "not_in_foreground" }
        else { error = nil }

        if let error = error {
            request.reply?(failure(error))
            return
        }

        active = request
        if let timeoutMs = timeoutMs {
            let timer = DispatchWorkItem { [weak self, weak request] in
                guard let request = request else { return }
                self?.fail(request, "timeout")
            }
            request.timer = timer
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(timeoutMs), execute: timer)
        }

        checkSystem(request) { [weak self, weak request] error in
            guard let self = self, let request = request else { return }
            if let error = error {
                self.fail(request, error)
                return
            }
            self.startSdk(request, timeoutMs: timeoutMs)
        }
    }

    private func startSdk(_ request: Request, timeoutMs: Int?) {
        guard let manager = AMapLocationManager() as AMapLocationManager? else {
            fail(request, "sdk_failure")
            return
        }
        request.manager = manager
        manager.delegate = self
        manager.allowsBackgroundLocationUpdates = false
        manager.locatingWithReGeocode = false
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        if #available(iOS 14, *) {
            manager.locationAccuracyMode = .init(rawValue: 2)! // AMapLocationReduceAccuracy
        }

        if let timeoutMs = timeoutMs {
            // Let AMap return its best candidate before the bridge's hard deadline.
            manager.locationTimeout = max(2, (timeoutMs - 1) / 1000)
            let started = manager.requestLocation(withReGeocode: false) { [weak self, weak request] location, _, error in
                DispatchQueue.main.async {
                    guard let self = self, let request = request else { return }
                    if let error = error {
                        self.handleSdkError(request, error as NSError)
                    } else {
                        self.receive(request, location)
                    }
                }
            }
            if !started { fail(request, "sdk_failure") }
        } else {
            manager.startUpdatingLocation()
            let reply = request.reply
            request.reply = nil
            reply?(nil)
        }
    }

    private func checkSystem(_ request: Request, complete: @escaping (String?) -> Void) {
        // Core Location's service check can block. Only touch the session on the main queue.
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak request] in
            let enabled = CLLocationManager.locationServicesEnabled()
            DispatchQueue.main.async {
                guard let request = request, self?.active === request else { return }
                if !enabled {
                    complete("location_services_disabled")
                    return
                }
                let authorization = CLLocationManager.authorizationStatus()
                let allowed = authorization == .authorizedWhenInUse || authorization == .authorizedAlways
                complete(allowed ? nil : "permission_denied")
            }
        }
    }

    public func amapLocationManager(_ manager: AMapLocationManager!, didUpdate location: CLLocation!) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let request = self.active, request.manager === manager else { return }
            self.receive(request, location)
        }
    }

    public func amapLocationManager(_ manager: AMapLocationManager!, didFailWithError error: Error!) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let request = self.active, request.manager === manager,
                  let error = error else { return }
            self.handleSdkError(request, error as NSError)
        }
    }

    private func receive(_ request: Request, _ location: CLLocation?) {
        guard active === request else { return }
        guard let location = location, CLLocationCoordinate2DIsValid(location.coordinate),
              location.horizontalAccuracy >= 0 else {
            fail(request, "sdk_failure")
            return
        }
        let fix: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "horizontalAccuracy": location.horizontalAccuracy,
            "timestamp": Int64(location.timestamp.timeIntervalSince1970 * 1000),
            // CLLocation provides no AMap coordinate-system flag.
            "coordinateSystem": "UNKNOWN"
        ]
        if let id = request.id {
            channel.invokeMethod("position", arguments: ["id": id, "fix": fix])
        } else {
            release(request)
            request.reply?(fix)
        }
    }

    private func handleSdkError(_ request: Request, _ error: NSError) {
        guard active === request else { return }
        let amapError = error.domain == AMapLocationErrorDomain
        if amapError && error.code == AMapLocationErrorCode.timeOut.rawValue {
            fail(request, "timeout", native: error)
        } else if amapError && error.code == AMapLocationErrorCode.canceled.rawValue {
            fail(request, "cancelled", native: error)
        } else {
            checkSystem(request) { [weak self, weak request] reason in
                guard let request = request else { return }
                let requiresFullAccuracy = amapError && error.code == AMapLocationErrorCode.noFullAccuracyAuth.rawValue
                self?.fail(request, reason ?? (requiresFullAccuracy ? "permission_denied" : "sdk_failure"), native: error)
            }
        }
    }

    @objc private func didEnterBackground() {
        if let request = active { fail(request, "not_in_foreground") }
    }

    private func fail(_ request: Request, _ code: String, native: NSError? = nil) {
        guard active === request else { return }
        release(request)
        if let reply = request.reply {
            reply(failure(code, native: native))
        } else if let id = request.id {
            var args: [String: Any] = ["id": id, "code": code]
            args["details"] = details(native)
            channel.invokeMethod("positionError", arguments: args)
        }
    }

    private func details(_ native: NSError?) -> [String: Any]? {
        guard let native = native else { return nil }
        return ["nativeCode": native.code, "nativeDomain": native.domain]
    }

    private func failure(_ code: String, native: NSError? = nil) -> FlutterError {
        return FlutterError(code: code, message: nil, details: details(native))
    }

    private func release(_ request: Request) {
        active = nil
        request.timer?.cancel()
        request.timer = nil
        request.manager?.delegate = nil
        request.manager?.stopUpdatingLocation()
        request.manager = nil
    }
}
