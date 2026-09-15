package com.example.hr_sdk_005

import com.samsung.android.service.health.tracking.data.DataPoint
import com.samsung.android.service.health.tracking.data.HealthTrackerType
import com.samsung.android.service.health.tracking.data.ValueKey

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
