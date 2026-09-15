package com.example.hr_sdk_005

import android.content.Intent
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Seperti proyek heart_rate_phone_receiver: BLE ditangani di Dart lewat
 * flutter_blue_plus, dan Activity ini hanya menyediakan kanal untuk menyalakan
 * dan mematikan [MonitoringService].
 */
class MainActivity : FlutterActivity() {
    companion object {
        // Harus sama dengan nama channel di sisi Dart (BleReceiver).
        private const val SERVICE_CHANNEL = "hr_receiver/service"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SERVICE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startService" -> {
                        ContextCompat.startForegroundService(
                            this,
                            Intent(this, MonitoringService::class.java),
                        )
                        result.success(null)
                    }
                    "stopService" -> {
                        stopService(Intent(this, MonitoringService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
