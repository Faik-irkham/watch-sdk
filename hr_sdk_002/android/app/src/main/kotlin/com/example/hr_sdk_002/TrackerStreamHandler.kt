package com.example.hr_sdk_002

import android.os.Handler
import android.os.Looper
import android.util.Log
import com.samsung.android.service.health.tracking.HealthTracker
import com.samsung.android.service.health.tracking.HealthTrackingService
import com.samsung.android.service.health.tracking.data.DataPoint
import com.samsung.android.service.health.tracking.data.HealthTrackerType
import com.samsung.android.service.health.tracking.data.ValueKey
import io.flutter.plugin.common.EventChannel

/**
 * Menyalurkan satu jenis tracker Samsung ke satu EventChannel.
 *
 * Sensor menyala saat Dart mulai listen dan mati saat langganan dibatalkan.
 */
abstract class TrackerStreamHandler(
    private val connection: SamsungHealthConnection,
    private val hasPermission: () -> Boolean,
) : EventChannel.StreamHandler, SamsungHealthConnection.Listener {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var tracker: HealthTracker? = null

    /** Nama untuk log dan pesan error. */
    protected abstract val label: String

    protected abstract fun pickType(supported: List<HealthTrackerType>): HealthTrackerType?

    protected abstract fun toPayload(point: DataPoint): Map<String, Any?>

    /**
     * Pengukuran sekali jalan (SpO2) selesai sendiri; tracker dilepas begitu
     * hasil akhir datang supaya sensor tidak terus menyala.
     */
    protected open fun isFinal(payload: Map<String, Any?>): Boolean = false

    // -------------------------------------------------------- stream Dart

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        if (!hasPermission()) {
            emitError("PERMISSION_DENIED", "Izin sensor untuk $label belum diberikan")
            return
        }
        connection.acquire(this)
    }

    override fun onCancel(arguments: Any?) {
        releaseTracker()
        connection.release(this)
        sink = null
    }

    // --------------------------------------------------- callback koneksi

    override fun onServiceConnected(service: HealthTrackingService) {
        if (tracker != null) return

        val supported = try {
            service.trackingCapability.supportHealthTrackerTypes
        } catch (e: Throwable) {
            Log.w(TAG, "getTrackingCapability gagal", e)
            emptyList<HealthTrackerType>()
        }

        val type = pickType(supported)
        if (type == null) {
            emitError("UNSUPPORTED", "Jam ini tidak mendukung pengukuran $label")
            return
        }

        try {
            tracker = service.getHealthTracker(type).apply { setEventListener(trackerListener) }
            emitStatus("tracking", "Tracker aktif: $type")
        } catch (e: Throwable) {
            emitError("TRACKER_FAILED", e.message ?: "Gagal membuat tracker $label")
        }
    }

    override fun onServiceFailed(code: String, message: String) = emitError(code, message)

    override fun onServiceEnded() =
        emitStatus("disconnected", "Koneksi ke Samsung Health Service berakhir")

    // ---------------------------------------------------- callback tracker

    private val trackerListener = object : HealthTracker.TrackerEventListener {
        override fun onDataReceived(dataPoints: List<DataPoint>) {
            for (point in dataPoints) {
                val payload = toPayload(point)
                emit(payload + ("event" to "data"))
                if (isFinal(payload)) {
                    mainHandler.post {
                        releaseTracker()
                        emitStatus("completed", "Pengukuran $label selesai")
                    }
                    return
                }
            }
        }

        override fun onFlushCompleted() = emitStatus("flushed", "Flush selesai")

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

    private fun releaseTracker() {
        try {
            tracker?.unsetEventListener()
        } catch (e: Throwable) {
            Log.w(TAG, "unsetEventListener gagal", e)
        }
        tracker = null
    }

    // ------------------------------------------------------------ helper

    private fun emit(payload: Map<String, Any?>) {
        mainHandler.post { sink?.success(payload) }
    }

    protected fun emitStatus(state: String, message: String) {
        emit(mapOf("event" to "status", "state" to state, "message" to message))
    }

    protected fun emitError(code: String, message: String) {
        Log.w(TAG, "[$label] $code: $message")
        mainHandler.post { sink?.error(code, message, null) }
    }

    private companion object {
        const val TAG = "TrackerStream"
    }
}

/**
 * Detak jantung. HEART_RATE_CONTINUOUS lebih hemat daya tapi tidak ada di
 * semua model, jadi HEART_RATE dipakai sebagai cadangan.
 */
class HeartRateStreamHandler(
    connection: SamsungHealthConnection,
    hasPermission: () -> Boolean,
) : TrackerStreamHandler(connection, hasPermission) {

    override val label = "detak jantung"

    override fun pickType(supported: List<HealthTrackerType>): HealthTrackerType? = when {
        supported.contains(HealthTrackerType.HEART_RATE_CONTINUOUS) ->
            HealthTrackerType.HEART_RATE_CONTINUOUS
        supported.contains(HealthTrackerType.HEART_RATE) ->
            HealthTrackerType.HEART_RATE
        else -> null
    }

    override fun toPayload(point: DataPoint): Map<String, Any?> = mapOf(
        "heartRate" to point.getValue(ValueKey.HeartRateSet.HEART_RATE),
        "heartRateStatus" to point.getValue(ValueKey.HeartRateSet.HEART_RATE_STATUS),
        "ibi" to point.getValue(ValueKey.HeartRateSet.IBI_LIST),
        "ibiStatus" to point.getValue(ValueKey.HeartRateSet.IBI_STATUS_LIST),
        "timestamp" to point.timestamp,
    )
}

/**
 * Saturasi oksigen. Pengukuran bersifat sekali jalan: sensor menghitung
 * sekitar 30 detik lalu mengirim hasil akhir dengan status
 * [SPO2_STATUS_COMPLETED].
 */
class Spo2StreamHandler(
    connection: SamsungHealthConnection,
    hasPermission: () -> Boolean,
) : TrackerStreamHandler(connection, hasPermission) {

    override val label = "SpO2"

    override fun pickType(supported: List<HealthTrackerType>): HealthTrackerType? = when {
        supported.contains(HealthTrackerType.SPO2_ON_DEMAND) ->
            HealthTrackerType.SPO2_ON_DEMAND
        supported.contains(HealthTrackerType.SPO2) ->
            HealthTrackerType.SPO2
        else -> null
    }

    override fun toPayload(point: DataPoint): Map<String, Any?> = mapOf(
        "spo2" to point.getValue(ValueKey.SpO2Set.SPO2),
        "spo2Status" to point.getValue(ValueKey.SpO2Set.STATUS),
        "heartRate" to point.getValue(ValueKey.SpO2Set.HEART_RATE),
        "accuracyFlag" to point.getValue(ValueKey.SpO2Set.ACCURACY_FLAG),
        "timestamp" to point.timestamp,
    )

    override fun isFinal(payload: Map<String, Any?>): Boolean =
        payload["spo2Status"] == SPO2_STATUS_COMPLETED

    private companion object {
        /** Nilai STATUS saat pengukuran SpO2 rampung. */
        const val SPO2_STATUS_COMPLETED = 2
    }
}
