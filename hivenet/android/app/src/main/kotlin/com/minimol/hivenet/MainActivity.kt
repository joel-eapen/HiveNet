package com.minimol.hivenet

import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Battery level and charging state, so peers choosing where to store a
        // copy can avoid a phone that is about to switch off. Read-only; needs
        // no permission.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hivenet/device_status")
            .setMethodCallHandler { call, result ->
                if (call.method != "battery") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                // ACTION_BATTERY_CHANGED is a sticky broadcast: registering with
                // no receiver returns the latest value immediately.
                val intent: Intent? = applicationContext.registerReceiver(
                    null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)
                )
                if (intent == null) {
                    result.success(null)
                    return@setMethodCallHandler
                }
                val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
                val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
                val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
                val plugged = intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0)
                val percent: Int? = if (level >= 0 && scale > 0) (level * 100) / scale else null
                val charging = plugged != 0 ||
                    status == BatteryManager.BATTERY_STATUS_CHARGING ||
                    status == BatteryManager.BATTERY_STATUS_FULL
                result.success(mapOf("percent" to percent, "charging" to charging))
            }
    }
}
