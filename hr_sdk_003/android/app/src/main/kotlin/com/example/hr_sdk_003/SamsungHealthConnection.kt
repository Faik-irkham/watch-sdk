package com.example.hr_sdk_003

import android.app.Activity
import android.util.Log
import com.samsung.android.service.health.tracking.ConnectionListener
import com.samsung.android.service.health.tracking.HealthTrackerException
import com.samsung.android.service.health.tracking.HealthTrackingService

/**
 * Satu koneksi ke HealthTrackingService yang dipakai bersama semua tracker.
 *
 * Service dibuka saat peminat pertama mendaftar dan ditutup saat peminat
 * terakhir pergi, jadi mengukur detak jantung dan SpO2 bersamaan tidak
 * membuka dua koneksi.
 */
class SamsungHealthConnection(private val activity: Activity) {

    interface Listener {
        fun onServiceConnected(service: HealthTrackingService)
        fun onServiceFailed(code: String, message: String)
        fun onServiceEnded()
    }

    private val listeners = mutableSetOf<Listener>()
    private var service: HealthTrackingService? = null
    private var connected = false

    fun acquire(listener: Listener) {
        listeners.add(listener)

        val existing = service
        if (existing != null) {
            // Koneksi sudah ada; kalau masih dalam proses, listener menunggu callback.
            if (connected) listener.onServiceConnected(existing)
            return
        }

        val created = HealthTrackingService(connectionListener, activity)
        service = created
        try {
            created.connectService()
        } catch (e: Throwable) {
            service = null
            notifyFailed("CONNECT_FAILED", e.message ?: "Gagal menghubungi Samsung Health Service")
        }
    }

    fun release(listener: Listener) {
        listeners.remove(listener)
        if (listeners.isNotEmpty()) return
        disconnect()
    }

    fun disconnect() {
        listeners.clear()
        try {
            service?.disconnectService()
        } catch (e: Throwable) {
            Log.w(TAG, "disconnectService gagal", e)
        }
        service = null
        connected = false
    }

    /** Nama tracker yang didukung jam ini; kosong selama belum tersambung. */
    fun supportedTrackerNames(): List<String> {
        val current = service?.takeIf { connected } ?: return emptyList()
        return try {
            current.trackingCapability.supportHealthTrackerTypes.map { it.name }
        } catch (e: Throwable) {
            Log.w(TAG, "getTrackingCapability gagal", e)
            emptyList()
        }
    }

    private fun notifyFailed(code: String, message: String) {
        listeners.toList().forEach { it.onServiceFailed(code, message) }
    }

    private val connectionListener = object : ConnectionListener {
        override fun onConnectionSuccess() {
            connected = true
            val current = service ?: return
            listeners.toList().forEach { it.onServiceConnected(current) }
        }

        override fun onConnectionEnded() {
            connected = false
            listeners.toList().forEach { it.onServiceEnded() }
        }

        override fun onConnectionFailed(e: HealthTrackerException) {
            connected = false
            // hasResolution() true artinya user bisa dipandu memasang atau
            // memperbarui Samsung Health Service lewat resolve().
            if (e.hasResolution()) e.resolve(activity)
            notifyFailed(
                "CONNECTION_FAILED",
                "Koneksi gagal (errorCode=${e.errorCode}): ${e.message}",
            )
        }
    }

    private companion object {
        const val TAG = "SamsungHealthConn"
    }
}
