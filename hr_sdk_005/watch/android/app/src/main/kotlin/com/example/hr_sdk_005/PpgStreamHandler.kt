package com.example.hr_sdk_005

import android.util.Log
import com.samsung.android.service.health.tracking.HealthTracker
import com.samsung.android.service.health.tracking.HealthTrackingService
import com.samsung.android.service.health.tracking.data.DataPoint
import com.samsung.android.service.health.tracking.data.HealthTrackerType
import com.samsung.android.service.health.tracking.data.PpgType
import com.samsung.android.service.health.tracking.data.ValueKey

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
