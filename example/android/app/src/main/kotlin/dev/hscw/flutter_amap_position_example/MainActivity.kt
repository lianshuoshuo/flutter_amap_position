package dev.hscw.flutter_amap_position_example

import android.Manifest
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val locationPermissions = arrayOf(
        Manifest.permission.ACCESS_COARSE_LOCATION,
        Manifest.permission.ACCESS_FINE_LOCATION,
    )
    private var pending: MethodChannel.Result? = null
    private var permissionChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        permissionChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.hscw.flutter_amap_position/example_permissions",
        ).apply {
            setMethodCallHandler { call, result ->
                when {
                    call.method != "request" -> result.notImplemented()
                    hasPermission() -> result.success(true)
                    pending != null -> result.error("busy", null, null)
                    else -> {
                        pending = result
                        requestPermissions(locationPermissions, 41)
                    }
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        permissionChannel?.setMethodCallHandler(null)
        permissionChannel = null
        pending?.success(false)
        pending = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 41) return
        pending?.success(hasPermission())
        pending = null
    }

    private fun hasPermission() =
        locationPermissions.any { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
}
