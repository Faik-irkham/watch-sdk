package com.example.hr_sdk_005

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Activity Flutter yang mendaftarkan kanal ke native:
 * - [SamsungHealthBridge] untuk sensor Samsung Health Sensor SDK,
 * - [HeartRateBleServer] untuk BLE peripheral (GATT + advertising), sama
 *   dengan proyek basic_sensor_heart_rate_interval_sqflite_ble.
 */
class MainActivity : FlutterActivity() {
    companion object {
        // Harus sama dengan nama channel di sisi Dart (lib/ble_peripheral.dart).
        private const val BLE_METHOD_CHANNEL = "heart_rate/ble"
        private const val BLE_STATUS_CHANNEL = "heart_rate/ble/status"
        private const val BLE_ACK_CHANNEL = "heart_rate/ble/ack"
    }

    private var bridge: SamsungHealthBridge? = null
    private var bleServer: HeartRateBleServer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        bridge = SamsungHealthBridge(this, messenger).also { it.attach() }

        // BLE peripheral: watch mengirim data ke smartphone.
        val server = HeartRateBleServer(applicationContext)
        bleServer = server
        EventChannel(messenger, BLE_STATUS_CHANNEL).setStreamHandler(server.statusHandler)
        EventChannel(messenger, BLE_ACK_CHANNEL).setStreamHandler(server.ackHandler)
        MethodChannel(messenger, BLE_METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startAdvertising" -> {
                    server.start()
                    result.success(null)
                }
                "stopAdvertising" -> {
                    server.stop()
                    result.success(null)
                }
                "sendBatch" -> {
                    val json = call.argument<String>("json")
                    val count = call.argument<Int>("count") ?: 0
                    // batchId dikirim sebagai Number agar aman untuk uint32.
                    val batchId = call.argument<Number>("batchId")?.toLong() ?: 0L
                    val accepted = json != null && server.sendBatch(json, count, batchId)
                    result.success(accepted)
                }
                "isConnected" -> result.success(server.isConnected())
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (bridge?.onRequestPermissionsResult(requestCode, grantResults) == true) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        bridge?.detach()
        bridge = null
        bleServer?.stop()
        bleServer = null
        super.onDestroy()
    }
}
