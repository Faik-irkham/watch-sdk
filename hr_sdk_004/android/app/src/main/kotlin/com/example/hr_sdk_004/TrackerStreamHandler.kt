package com.example.hr_sdk_004

import android.os.Handler
import android.os.Looper
import android.util.Log
import com.samsung.android.service.health.tracking.HealthTracker
import com.samsung.android.service.health.tracking.HealthTrackingService
import com.samsung.android.service.health.tracking.data.DataPoint
import com.samsung.android.service.health.tracking.data.HealthTrackerType
import io.flutter.plugin.common.EventChannel

/**
 * Menyalurkan satu jenis tracker Samsung ke satu EventChannel.
 *
 * Sensor menyala saat Dart mulai listen dan mati saat langganan dibatalkan.
 *
 * Kelas ini hanya berisi alur bersama. Tiap sensor ada di filenya sendiri:
 * [HeartRateStreamHandler], [Spo2StreamHandler], [AccelerometerStreamHandler],
 * dan [PpgStreamHandler].
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

    /**
     * Mengubah satu kiriman titik data menjadi muatan untuk Dart. Bawaannya satu
     * muatan per titik; sensor berlaju tinggi menggabungkan satu kiriman menjadi
     * satu muatan agar saluran dan log tidak kebanjiran.
     */
    protected open fun toEvents(points: List<DataPoint>): List<Map<String, Any?>> =
        points.map { toPayload(it) }

    /** Ringkasan satu muatan untuk log. */
    protected open fun describe(payload: Map<String, Any?>): String = payload.toString()

    /**
     * Membuat tracker untuk [type]. PPG menimpanya karena warna LED harus
     * dipilih lewat overload Set<PpgType>.
     */
    protected open fun createTracker(
        service: HealthTrackingService,
        type: HealthTrackerType,
    ): HealthTracker = service.getHealthTracker(type)

    /** Keterangan tracker yang aktif untuk pesan status di layar. */
    protected open fun activeDescription(type: HealthTrackerType): String = "$type"

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
            tracker = createTracker(service, type).apply { setEventListener(trackerListener) }
            emitStatus("tracking", "Tracker aktif: ${activeDescription(type)}")
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
            for (payload in toEvents(dataPoints)) {
                // Nilai mentah dicatat supaya kode status yang belum terpetakan
                // bisa dicocokkan dengan apa yang benar-benar terjadi di jam.
                Log.i(TAG, "[$label] ${describe(payload)}")
                emit(payload + ("event" to "data"))
                if (isFinal(payload)) {
                    mainHandler.post {
                        releaseTracker()
                        emitStatus("completed", "Pengukuran $label berakhir")
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
