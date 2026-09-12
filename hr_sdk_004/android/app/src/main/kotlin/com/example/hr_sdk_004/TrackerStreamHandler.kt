package com.example.hr_sdk_004

import android.os.Handler
import android.os.Looper
import android.util.Log
import com.samsung.android.service.health.tracking.HealthTracker
import com.samsung.android.service.health.tracking.HealthTrackingService
import com.samsung.android.service.health.tracking.data.DataPoint
import com.samsung.android.service.health.tracking.data.HealthTrackerType
import com.samsung.android.service.health.tracking.data.PpgType
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
 * belasan detik - terukur 13,9 detik pada Galaxy Watch4 - lalu mengirim
 * hasil akhir dengan status [SPO2_STATUS_COMPLETED].
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

    // Tabel status resmi Samsung: pengukuran berakhir saat rampung (2) atau
    // waktu habis (-6). Dokumentasi tidak menyebut apakah -4 dan -5 ikut
    // mengakhiri, jadi keduanya diperlakukan sebagai peringatan; pengguna tetap
    // bisa menekan Berhenti.
    override fun isFinal(payload: Map<String, Any?>): Boolean =
        payload["spo2Status"] == SPO2_STATUS_COMPLETED ||
            payload["spo2Status"] == SPO2_STATUS_TIMEOUT

    private companion object {
        /** Nilai STATUS saat pengukuran SpO2 rampung. */
        const val SPO2_STATUS_COMPLETED = 2

        /** Nilai STATUS saat pengukuran SpO2 berhenti karena waktu habis. */
        const val SPO2_STATUS_TIMEOUT = -6
    }
}

/**
 * Akselerometer tiga sumbu. Nilainya bilangan bulat mentah dari sensor dan,
 * menurut dokumentasi resmi Samsung, tidak termasuk gravitasi. Konversi resmi
 * ke m/s²: nilai × 9,81 / (16383,75 / 4).
 *
 * Datanya berlaju tinggi dan tiba berkelompok, jadi satu kiriman diteruskan
 * sebagai satu muatan berisi deret sampel.
 */
class AccelerometerStreamHandler(
    connection: SamsungHealthConnection,
    hasPermission: () -> Boolean,
) : TrackerStreamHandler(connection, hasPermission) {

    override val label = "akselerometer"

    override fun pickType(supported: List<HealthTrackerType>): HealthTrackerType? = when {
        supported.contains(HealthTrackerType.ACCELEROMETER_CONTINUOUS) ->
            HealthTrackerType.ACCELEROMETER_CONTINUOUS
        supported.contains(HealthTrackerType.ACCELEROMETER) ->
            HealthTrackerType.ACCELEROMETER
        else -> null
    }

    override fun toPayload(point: DataPoint): Map<String, Any?> = mapOf(
        "x" to point.getValue(ValueKey.AccelerometerSet.ACCELEROMETER_X),
        "y" to point.getValue(ValueKey.AccelerometerSet.ACCELEROMETER_Y),
        "z" to point.getValue(ValueKey.AccelerometerSet.ACCELEROMETER_Z),
        "timestamp" to point.timestamp,
    )

    override fun toEvents(points: List<DataPoint>): List<Map<String, Any?>> =
        if (points.isEmpty()) emptyList()
        else listOf(mapOf("samples" to points.map { toPayload(it) }))

    override fun describe(payload: Map<String, Any?>): String {
        val samples = payload["samples"] as? List<*> ?: return payload.toString()
        return "n=${samples.size} terakhir=${samples.lastOrNull()}"
    }
}

/**
 * PPG mentah: nilai ADC LED hijau, ditambah inframerah dan merah bila jam
 * mendukungnya dalam mode menerus (25 Hz). Dokumentasi resmi tidak menyebut
 * kombinasi warna yang sah untuk PPG_CONTINUOUS, jadi ketiganya dicoba lebih
 * dulu dan, bila ditolak, turun ke hijau saja. Kombinasi yang dipakai muncul
 * di pesan status.
 *
 * Status tiap warna menurut ValueKey.PpgSet untuk PPG_CONTINUOUS: 0 normal,
 * -1 sensor yang lebih prioritas (misalnya BIA) sedang berjalan.
 */
class PpgStreamHandler(
    connection: SamsungHealthConnection,
    hasPermission: () -> Boolean,
) : TrackerStreamHandler(connection, hasPermission) {

    override val label = "PPG"

    private var colors: Set<PpgType> = emptySet()

    override fun pickType(supported: List<HealthTrackerType>): HealthTrackerType? =
        HealthTrackerType.PPG_CONTINUOUS.takeIf { it in supported }

    override fun createTracker(
        service: HealthTrackingService,
        type: HealthTrackerType,
    ): HealthTracker {
        val all = setOf(PpgType.GREEN, PpgType.IR, PpgType.RED)
        return try {
            service.getHealthTracker(type, all).also { colors = all }
        } catch (e: IllegalArgumentException) {
            Log.w(TAG, "[PPG] kombinasi $all ditolak, turun ke hijau saja", e)
            val green = setOf(PpgType.GREEN)
            service.getHealthTracker(type, green).also { colors = green }
        }
    }

    override fun activeDescription(type: HealthTrackerType): String =
        "$type (${colors.joinToString { it.name }})"

    override fun toPayload(point: DataPoint): Map<String, Any?> = mapOf(
        "green" to point.read(PpgType.GREEN, ValueKey.PpgSet.PPG_GREEN),
        "greenStatus" to point.read(PpgType.GREEN, ValueKey.PpgSet.GREEN_STATUS),
        "ir" to point.read(PpgType.IR, ValueKey.PpgSet.PPG_IR),
        "irStatus" to point.read(PpgType.IR, ValueKey.PpgSet.IR_STATUS),
        "red" to point.read(PpgType.RED, ValueKey.PpgSet.PPG_RED),
        "redStatus" to point.read(PpgType.RED, ValueKey.PpgSet.RED_STATUS),
        "timestamp" to point.timestamp,
    )

    /** Hanya warna yang diminta yang dibaca; kunci warna lain bisa tidak ada. */
    private fun <T> DataPoint.read(color: PpgType, key: ValueKey<T>): T? =
        if (color in colors) runCatching { getValue(key) }.getOrNull() else null

    override fun toEvents(points: List<DataPoint>): List<Map<String, Any?>> =
        if (points.isEmpty()) emptyList()
        else listOf(mapOf("samples" to points.map { toPayload(it) }))

    override fun describe(payload: Map<String, Any?>): String {
        val samples = payload["samples"] as? List<*> ?: return payload.toString()
        return "n=${samples.size} terakhir=${samples.lastOrNull()}"
    }

    private companion object {
        const val TAG = "TrackerStream"
    }
}
