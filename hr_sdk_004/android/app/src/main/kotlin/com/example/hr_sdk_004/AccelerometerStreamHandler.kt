package com.example.hr_sdk_004

import com.samsung.android.service.health.tracking.data.DataPoint
import com.samsung.android.service.health.tracking.data.HealthTrackerType
import com.samsung.android.service.health.tracking.data.ValueKey

/**
 * Akselerometer tiga sumbu, bilangan bulat mentah dari sensor. Referensi API
 * Samsung (ValueKey.AccelerometerSet) menyebut gravitasi tidak termasuk, tetapi
 * pengukuran di Galaxy Watch4 (Wear OS 6, SDK 1.4.1) menunjukkan sebaliknya:
 * jam diam dengan layar menghadap atas terbaca z ≈ +4096 (≈ 1 g). Konversi
 * resmi ke m/s²: nilai × 9,81 / (16383,75 / 4).
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
