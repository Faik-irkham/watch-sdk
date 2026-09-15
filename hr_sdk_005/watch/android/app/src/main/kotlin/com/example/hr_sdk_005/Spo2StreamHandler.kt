package com.example.hr_sdk_005

import com.samsung.android.service.health.tracking.data.DataPoint
import com.samsung.android.service.health.tracking.data.HealthTrackerType
import com.samsung.android.service.health.tracking.data.ValueKey

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
