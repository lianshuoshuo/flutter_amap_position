package dev.hscw.flutter_amap_position

import android.Manifest
import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import com.amap.api.location.AMapLocation
import com.amap.api.location.AMapLocationClient
import com.amap.api.location.AMapLocationClientOption
import com.amap.api.location.AMapLocationListener
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class FlutterAmapPositionPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {
    private lateinit var app: Application
    private lateinit var channel: MethodChannel
    private val handler = Handler(Looper.getMainLooper())
    private var activity: Activity? = null
    private var foreground = false
    private var initialized = false
    private var privacyDeclined = false
    private var clientId: String? = null
    private var active: Request? = null

    private class Request(val id: String?, val singleResult: MethodChannel.Result?) {
        var sdkClient: AMapLocationClient? = null
        var listener: AMapLocationListener? = null
        var timeout: Runnable? = null
    }

    private val lifecycle = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityStarted(activity: Activity) {
            if (this@FlutterAmapPositionPlugin.activity === activity) foreground = true
        }

        override fun onActivityStopped(activity: Activity) {
            if (this@FlutterAmapPositionPlugin.activity === activity) leaveForeground()
        }

        override fun onActivityCreated(activity: Activity, state: Bundle?) = Unit
        override fun onActivityResumed(activity: Activity) = Unit
        override fun onActivityPaused(activity: Activity) = Unit
        override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) = Unit
        override fun onActivityDestroyed(activity: Activity) = Unit
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        app = binding.applicationContext as Application
        channel = MethodChannel(binding.binaryMessenger, "dev.hscw.flutter_amap_position/location")
        channel.setMethodCallHandler(this)
        app.registerActivityLifecycleCallbacks(lifecycle)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        active?.let { fail(it, "cancelled") }
        app.unregisterActivityLifecycleCallbacks(lifecycle)
        channel.setMethodCallHandler(null)
        activity = null
        foreground = false
        initialized = false
        privacyDeclined = false
        clientId = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        foreground = true
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activity = null
        leaveForeground()
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> initialize(call, result)
            "getCurrentPosition" -> {
                val timeout = call.argument<Number>("timeoutMs")?.toLong()
                if (timeout == null || timeout !in 1..Int.MAX_VALUE.toLong()) {
                    result.error("invalid_argument", null, null)
                } else {
                    start(Request(null, result), timeout, result)
                }
            }
            "startUpdates" -> {
                val id = call.argument<String>("id")
                if (id.isNullOrEmpty()) result.error("invalid_argument", null, null)
                else start(Request(id, null), null, result)
            }
            "stopUpdates" -> {
                val request = active
                if (request?.id != null && request.id == call.argument<String>("id")) {
                    release(request)
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun initialize(call: MethodCall, result: MethodChannel.Result) {
        if (call.argument<Boolean>("privacyAgreed") != true) {
            initialized = false
            privacyDeclined = true
            active?.let { fail(it, "privacy_not_agreed") }
            result.error("privacy_not_agreed", null, null)
            return
        }
        val key = call.argument<String>("apiKey")?.trim()
        val caller = call.argument<String>("clientId")
        if (key.isNullOrEmpty() || caller.isNullOrEmpty()) {
            result.error("invalid_argument", null, null)
            return
        }
        if (clientId != caller) active?.let { fail(it, "cancelled") }
        if (active != null) {
            result.error("busy", null, null)
            return
        }
        initialized = false
        privacyDeclined = false
        try {
            AMapLocationClient.updatePrivacyShow(app, true, true)
            AMapLocationClient.updatePrivacyAgree(app, true)
            AMapLocationClient.setApiKey(key)
            clientId = caller
            initialized = true
            result.success(null)
        } catch (_: Exception) {
            result.error("sdk_failure", null, null)
        }
    }

    private fun start(request: Request, timeoutMs: Long?, result: MethodChannel.Result) {
        val error = when {
            privacyDeclined -> "privacy_not_agreed"
            !initialized -> "not_initialized"
            active != null -> "busy"
            !foreground -> "not_in_foreground"
            else -> systemError()
        }
        if (error != null) {
            result.error(error, null, null)
            return
        }
        active = request
        try {
            val client = AMapLocationClient(app)
            request.sdkClient = client
            val listener = AMapLocationListener { location ->
                // Serialize SDK callbacks with start/stop and Activity lifecycle events.
                handler.post { onLocation(request, location) }
            }
            request.listener = listener
            client.setLocationListener(listener)
            client.setLocationOption(AMapLocationClientOption().apply {
                setOnceLocation(timeoutMs != null)
                setNeedAddress(false)
                setInterval(2000)
                setLocationCacheEnable(false)
                setOffset(true)
            })
            if (timeoutMs != null) {
                val timeout = Runnable { fail(request, "timeout") }
                request.timeout = timeout
                handler.postDelayed(timeout, timeoutMs)
            }
            client.startLocation()
            if (request.id != null) result.success(null)
        } catch (_: SecurityException) {
            release(request)
            result.error("permission_denied", null, null)
        } catch (_: Exception) {
            release(request)
            result.error("sdk_failure", null, null)
        }
    }

    private fun systemError(): String? {
        val manager = app.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val enabled = if (Build.VERSION.SDK_INT >= 28) manager.isLocationEnabled else {
            manager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        }
        return when {
            !enabled -> "location_services_disabled"
            app.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) !=
                PackageManager.PERMISSION_GRANTED &&
                app.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) !=
                PackageManager.PERMISSION_GRANTED -> "permission_denied"
            else -> null
        }
    }

    private fun onLocation(request: Request, location: AMapLocation?) {
        if (active !== request) return
        val code = location?.errorCode
        val error = systemError() ?: when {
            code == AMapLocation.ERROR_CODE_FAILURE_LOCATION_PERMISSION -> "permission_denied"
            code != 0 -> "sdk_failure"
            else -> null
        }
        if (error != null || location == null) {
            fail(request, error ?: "sdk_failure", code?.takeIf { it != 0 })
            return
        }
        if (!location.hasAccuracy()) {
            fail(request, "sdk_failure")
            return
        }

        val fix = mapOf(
            "latitude" to location.latitude,
            "longitude" to location.longitude,
            "horizontalAccuracy" to location.accuracy.toDouble(),
            "timestamp" to location.time,
            "coordinateSystem" to location.coordType,
        )
        val single = request.singleResult
        if (single != null) {
            release(request)
            single.success(fix)
        } else {
            channel.invokeMethod("position", mapOf("id" to request.id, "fix" to fix))
        }
    }

    private fun leaveForeground() {
        foreground = false
        active?.let { fail(it, "not_in_foreground") }
    }

    private fun fail(request: Request, code: String, nativeCode: Int? = null) {
        if (active !== request) return
        release(request)
        val details = nativeCode?.let { mapOf("nativeCode" to it, "nativeDomain" to "AMapLocation") }
        val single = request.singleResult
        if (single != null) {
            single.error(code, null, details)
        } else {
            channel.invokeMethod(
                "positionError",
                mapOf("id" to request.id, "code" to code, "details" to details),
            )
        }
    }

    private fun release(request: Request) {
        // Invalidate before stop/destroy because the SDK may still invoke a listener.
        active = null
        request.timeout?.let(handler::removeCallbacks)
        request.sdkClient?.let { client ->
            request.listener?.let { runCatching { client.unRegisterLocationListener(it) } }
            runCatching { client.stopLocation() }
            runCatching { client.onDestroy() }
        }
        request.sdkClient = null
        request.listener = null
    }
}
