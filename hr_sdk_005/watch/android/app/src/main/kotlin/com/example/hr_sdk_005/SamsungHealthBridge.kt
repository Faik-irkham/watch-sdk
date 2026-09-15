package com.example.hr_sdk_005

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/** Sensor yang bisa diminta dari sisi Dart. */
enum class HealthSensor(val key: String) {
    HEART_RATE("heartRate"),
    SPO2("spo2"),
    ACCELEROMETER("accelerometer"),
    PPG("ppg");

    companion object {
        fun fromKey(key: String?): HealthSensor =
            entries.firstOrNull { it.key == key } ?: HEART_RATE
    }
}

/**
 * Menjembatani Samsung Health Sensor SDK ke Flutter.
 *
 * - MethodChannel [METHOD_CHANNEL] untuk izin, daftar tracker yang didukung,
 *   dan menjaga layar tetap menyala selama pengukuran.
 * - EventChannel [HEART_RATE_CHANNEL] untuk detak jantung.
 * - EventChannel [SPO2_CHANNEL] untuk saturasi oksigen.
 * - EventChannel [ACCELEROMETER_CHANNEL] untuk akselerometer tiga sumbu.
 * - EventChannel [PPG_CHANNEL] untuk PPG mentah.
 */
class SamsungHealthBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {

    private val connection = SamsungHealthConnection(activity)
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val heartRateChannel = EventChannel(messenger, HEART_RATE_CHANNEL)
    private val spo2Channel = EventChannel(messenger, SPO2_CHANNEL)
    private val accelerometerChannel = EventChannel(messenger, ACCELEROMETER_CHANNEL)
    private val ppgChannel = EventChannel(messenger, PPG_CHANNEL)

    private val heartRateHandler = HeartRateStreamHandler(connection) {
        hasPermission(HealthSensor.HEART_RATE)
    }
    private val spo2Handler = Spo2StreamHandler(connection) {
        hasPermission(HealthSensor.SPO2)
    }
    private val accelerometerHandler = AccelerometerStreamHandler(connection) {
        hasPermission(HealthSensor.ACCELEROMETER)
    }
    private val ppgHandler = PpgStreamHandler(connection) {
        hasPermission(HealthSensor.PPG)
    }

    private var pendingPermissionResult: MethodChannel.Result? = null

    fun attach() {
        heartRateChannel.setStreamHandler(heartRateHandler)
        spo2Channel.setStreamHandler(spo2Handler)
        accelerometerChannel.setStreamHandler(accelerometerHandler)
        ppgChannel.setStreamHandler(ppgHandler)
        methodChannel.setMethodCallHandler { call, result ->
            val sensor = HealthSensor.fromKey(call.argument<String>("sensor"))
            when (call.method) {
                "hasPermission" -> result.success(hasPermission(sensor))
                "requestPermission" -> requestPermission(sensor, result)
                "supportedTrackers" -> result.success(connection.supportedTrackerNames())
                "keepScreenOn" -> {
                    setKeepScreenOn(call.argument<Boolean>("on") == true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun detach() {
        heartRateChannel.setStreamHandler(null)
        spo2Channel.setStreamHandler(null)
        accelerometerChannel.setStreamHandler(null)
        ppgChannel.setStreamHandler(null)
        methodChannel.setMethodCallHandler(null)
        connection.disconnect()
    }

    /**
     * Selama pengukuran layar tidak mati sendiri. Tanpa izin khusus; bila
     * aplikasi masuk latar belakang, sistem tetap boleh mematikan layar.
     */
    private fun setKeepScreenOn(on: Boolean) {
        val flag = WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
        if (on) activity.window.addFlags(flag) else activity.window.clearFlags(flag)
    }

    /**
     * Android 16 (API 36) memindahkan izin sensor tubuh ke Health Connect, dan
     * tiap sensor punya izinnya sendiri. Di bawah itu satu BODY_SENSORS
     * mencakup semuanya.
     */
    private fun permissionFor(sensor: HealthSensor): String = when {
        // Tabel izin resmi Samsung: ACCELEROMETER_CONTINUOUS menuntut
        // ACTIVITY_RECOGNITION di semua versi Android. Izin sensor tubuh tidak
        // cukup; layanan Samsung menolaknya dengan PERMISSION_ERROR.
        sensor == HealthSensor.ACCELEROMETER -> Manifest.permission.ACTIVITY_RECOGNITION
        Build.VERSION.SDK_INT < 36 -> Manifest.permission.BODY_SENSORS
        sensor == HealthSensor.SPO2 -> PERMISSION_READ_OXYGEN_SATURATION
        // Detak jantung dan PPG: dengan target API 34, tabel resmi Samsung
        // menuntut BODY_SENSORS untuk keduanya, dan di Wear OS 6 izin itu
        // teramati ikut diberikan bersama READ_HEART_RATE.
        else -> PERMISSION_READ_HEART_RATE
    }

    private fun hasPermission(sensor: HealthSensor): Boolean =
        ContextCompat.checkSelfPermission(activity, permissionFor(sensor)) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestPermission(sensor: HealthSensor, result: MethodChannel.Result) {
        if (hasPermission(sensor)) {
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
            arrayOf(permissionFor(sensor)),
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
        const val ACCELEROMETER_CHANNEL = "samsung_health/accelerometer"
        const val PPG_CHANNEL = "samsung_health/ppg"
        const val PERMISSION_REQUEST_CODE = 4711
        const val PERMISSION_READ_HEART_RATE = "android.permission.health.READ_HEART_RATE"
        const val PERMISSION_READ_OXYGEN_SATURATION =
            "android.permission.health.READ_OXYGEN_SATURATION"
    }
}
