package com.example.hr_sdk_002

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Menjembatani Samsung Health Sensor SDK ke Flutter.
 *
 * - MethodChannel [METHOD_CHANNEL] untuk izin dan daftar tracker yang didukung.
 * - EventChannel [HEART_RATE_CHANNEL] untuk detak jantung.
 * - EventChannel [SPO2_CHANNEL] untuk saturasi oksigen.
 */
class SamsungHealthBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {

    private val connection = SamsungHealthConnection(activity)
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val heartRateChannel = EventChannel(messenger, HEART_RATE_CHANNEL)
    private val spo2Channel = EventChannel(messenger, SPO2_CHANNEL)

    private val heartRateHandler = HeartRateStreamHandler(connection, ::hasBodySensorsPermission)
    private val spo2Handler = Spo2StreamHandler(connection, ::hasBodySensorsPermission)

    private var pendingPermissionResult: MethodChannel.Result? = null

    fun attach() {
        heartRateChannel.setStreamHandler(heartRateHandler)
        spo2Channel.setStreamHandler(spo2Handler)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(hasBodySensorsPermission())
                "requestPermission" -> requestBodySensorsPermission(result)
                "supportedTrackers" -> result.success(connection.supportedTrackerNames())
                else -> result.notImplemented()
            }
        }
    }

    fun detach() {
        heartRateChannel.setStreamHandler(null)
        spo2Channel.setStreamHandler(null)
        methodChannel.setMethodCallHandler(null)
        connection.disconnect()
    }

    private fun hasBodySensorsPermission(): Boolean =
        ContextCompat.checkSelfPermission(activity, Manifest.permission.BODY_SENSORS) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestBodySensorsPermission(result: MethodChannel.Result) {
        if (hasBodySensorsPermission()) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("PERMISSION_PENDING", "Permintaan izin sebelumnya belum selesai", null)
            return
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.BODY_SENSORS),
            PERMISSION_REQUEST_CODE,
        )
    }

    /** Dipanggil dari MainActivity.onRequestPermissionsResult. */
    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
        return true
    }

    private companion object {
        const val METHOD_CHANNEL = "samsung_health/method"
        const val HEART_RATE_CHANNEL = "samsung_health/heart_rate"
        const val SPO2_CHANNEL = "samsung_health/spo2"
        const val PERMISSION_REQUEST_CODE = 4711
    }
}
