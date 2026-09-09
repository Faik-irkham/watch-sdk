package com.example.hr_sdk_001

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.samsung.android.service.health.tracking.ConnectionListener
import com.samsung.android.service.health.tracking.HealthTracker
import com.samsung.android.service.health.tracking.HealthTrackerException
import com.samsung.android.service.health.tracking.HealthTrackingService
import com.samsung.android.service.health.tracking.data.DataPoint
import com.samsung.android.service.health.tracking.data.HealthTrackerType
import com.samsung.android.service.health.tracking.data.ValueKey
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Menjembatani Samsung Health Sensor SDK ke Flutter.
 *
 * - MethodChannel [METHOD_CHANNEL] untuk izin dan pengecekan dukungan sensor.
 * - EventChannel [EVENT_CHANNEL] untuk stream detak jantung. Koneksi ke
 *   HealthTrackingService dibuka saat Dart mulai listen dan ditutup saat cancel.
 */
class HeartRateBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : EventChannel.StreamHandler {

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())

    private var trackingService: HealthTrackingService? = null
    private var tracker: HealthTracker? = null
    private var eventSink: EventChannel.EventSink? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    fun attach() {
        eventChannel.setStreamHandler(this)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(hasBodySensorsPermission())
                "requestPermission" -> requestBodySensorsPermission(result)
                "supportedTrackers" -> result.success(supportedTrackerNames())
                else -> result.notImplemented()
            }
        }
    }

    fun detach() {
        stopTracking()
        eventChannel.setStreamHandler(null)
        methodChannel.setMethodCallHandler(null)
    }

    // ---------------------------------------------------------------- izin

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

    // ------------------------------------------------------------- stream

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        eventSink = sink
        if (!hasBodySensorsPermission()) {
            emitError("PERMISSION_DENIED", "Izin BODY_SENSORS belum diberikan")
            return
        }
        startTracking()
    }

    override fun onCancel(arguments: Any?) {
        stopTracking()
        eventSink = null
    }

    private fun startTracking() {
        if (trackingService != null) return
        val service = HealthTrackingService(connectionListener, activity)
        trackingService = service
        try {
            service.connectService()
        } catch (e: Throwable) {
            trackingService = null
            emitError("CONNECT_FAILED", e.message ?: "Gagal menghubungi Samsung Health Service")
        }
    }

    private fun stopTracking() {
        tracker?.unsetEventListener()
        tracker = null
        try {
            trackingService?.disconnectService()
        } catch (e: Throwable) {
            Log.w(TAG, "disconnectService gagal", e)
        }
        trackingService = null
    }

    private val connectionListener = object : ConnectionListener {
        override fun onConnectionSuccess() {
            val service = trackingService ?: return
            val type = pickHeartRateTrackerType(service)
            if (type == null) {
                emitError("UNSUPPORTED", "Perangkat ini tidak mendukung tracker detak jantung")
                return
            }
            try {
                tracker = service.getHealthTracker(type).apply {
                    setEventListener(trackerEventListener)
                }
                emitStatus("tracking", "Tracker aktif: $type")
            } catch (e: Throwable) {
                emitError("TRACKER_FAILED", e.message ?: "Gagal membuat HealthTracker")
            }
        }

        override fun onConnectionEnded() {
            emitStatus("disconnected", "Koneksi ke Samsung Health Service berakhir")
        }

        override fun onConnectionFailed(e: HealthTrackerException) {
            // hasResolution() true artinya user bisa dipandu memasang/memperbarui
            // Samsung Health Service lewat resolve().
            if (e.hasResolution()) {
                e.resolve(activity)
            }
            emitError(
                "CONNECTION_FAILED",
                "Koneksi gagal (errorCode=${e.errorCode}): ${e.message}",
            )
        }
    }

    /**
     * HEART_RATE_CONTINUOUS mengalirkan data terus-menerus dan lebih hemat daya,
     * tapi tidak ada di semua model; HEART_RATE dipakai sebagai cadangan.
     */
    private fun pickHeartRateTrackerType(service: HealthTrackingService): HealthTrackerType? {
        val supported = try {
            service.trackingCapability.supportHealthTrackerTypes
        } catch (e: Throwable) {
            Log.w(TAG, "getTrackingCapability gagal", e)
            emptyList<HealthTrackerType>()
        }
        return when {
            supported.contains(HealthTrackerType.HEART_RATE_CONTINUOUS) ->
                HealthTrackerType.HEART_RATE_CONTINUOUS
            supported.contains(HealthTrackerType.HEART_RATE) ->
                HealthTrackerType.HEART_RATE
            else -> null
        }
    }

    private fun supportedTrackerNames(): List<String> {
        val service = trackingService ?: return emptyList()
        return try {
            service.trackingCapability.supportHealthTrackerTypes.map { it.name }
        } catch (e: Throwable) {
            emptyList()
        }
    }

    private val trackerEventListener = object : HealthTracker.TrackerEventListener {
        override fun onDataReceived(dataPoints: List<DataPoint>) {
            for (point in dataPoints) {
                emit(
                    mapOf(
                        "event" to "data",
                        "heartRate" to point.getValue(ValueKey.HeartRateSet.HEART_RATE),
                        "heartRateStatus" to point.getValue(ValueKey.HeartRateSet.HEART_RATE_STATUS),
                        "ibi" to point.getValue(ValueKey.HeartRateSet.IBI_LIST),
                        "ibiStatus" to point.getValue(ValueKey.HeartRateSet.IBI_STATUS_LIST),
                        "timestamp" to point.timestamp,
                    ),
                )
            }
        }

        override fun onFlushCompleted() {
            emitStatus("flushed", "Flush selesai")
        }

        override fun onError(error: HealthTracker.TrackerError) {
            val message = when (error) {
                HealthTracker.TrackerError.PERMISSION_ERROR ->
                    "Izin sensor ditolak oleh Samsung Health Service"
                HealthTracker.TrackerError.SDK_POLICY_ERROR ->
                    "Paket aplikasi belum terdaftar di program partner Samsung Health Sensor SDK"
                else -> error.name
            }
            emitError(error.name, message)
        }
    }

    // ------------------------------------------------------------- helper

    private fun emit(payload: Map<String, Any?>) {
        mainHandler.post { eventSink?.success(payload) }
    }

    private fun emitStatus(state: String, message: String) {
        emit(mapOf("event" to "status", "state" to state, "message" to message))
    }

    private fun emitError(code: String, message: String) {
        Log.w(TAG, "$code: $message")
        mainHandler.post { eventSink?.error(code, message, null) }
    }

    companion object {
        private const val TAG = "HeartRateBridge"
        private const val METHOD_CHANNEL = "samsung_hr/method"
        private const val EVENT_CHANNEL = "samsung_hr/heart_rate"
        private const val PERMISSION_REQUEST_CODE = 4711
    }
}
