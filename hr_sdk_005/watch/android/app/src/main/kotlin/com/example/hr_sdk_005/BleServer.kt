package com.example.hr_sdk_005

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Jam sebagai peripheral BLE: GATT server dengan service HR005 (lihat
 * [BleProtocol]) dan iklan BLE agar HP (central) bisa menemukannya.
 *
 * Satu kiriman JSON dari Dart dipotong menjadi frame dan dikirim sebagai
 * notifikasi DATA, satu per satu setelah onNotificationSent. Notifikasi BLE
 * tidak dikonfirmasi penerimanya, jadi kiriman baru dianggap berhasil setelah
 * HP menulis `ACK <nomor>` ke CONTROL, yaitu setelah datanya tersimpan di HP.
 *
 * Izin dan status Bluetooth diperiksa sendiri sebelum dipakai, sehingga
 * peringatan MissingPermission diredam untuk seluruh kelas.
 */
@SuppressLint("MissingPermission")
class BleServer(private val activity: Activity, messenger: BinaryMessenger) {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val manager: BluetoothManager? = activity.getSystemService(BluetoothManager::class.java)

    private var server: BluetoothGattServer? = null
    private var dataCharacteristic: BluetoothGattCharacteristic? = null
    private var statusCharacteristic: BluetoothGattCharacteristic? = null
    private var advertising = false
    private var pendingStart: MethodChannel.Result? = null

    /** HP yang menyalakan notifikasi DATA. Jam hanya melayani satu HP. */
    private var phone: BluetoothDevice? = null
    private var statusSubscribed = false
    private val mtus = mutableMapOf<String, Int>()

    /** Android hanya mengizinkan satu notifikasi menunggu onNotificationSent. */
    private var notifying = false
    private var notifyingFrame = false

    private var seq = 0
    private var sending: Sending? = null
    private var pendingCount = 0
    private var statusDirty = false

    private class Sending(
        val device: BluetoothDevice,
        val seq: Int,
        val frames: ArrayDeque<ByteArray>,
        val result: MethodChannel.Result,
    )

    private val ackTimeout = Runnable {
        finishSending(error = "NO_ACK" to "HP tidak membalas kiriman")
    }

    fun attach() {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> start(result)
                "stop" -> {
                    stop()
                    result.success(null)
                }
                "connectedPhone" -> result.success(
                    phone?.let { mapOf("id" to it.address, "name" to nameOf(it)) },
                )
                "sendBatch" -> {
                    val json = call.arguments as? String
                    if (json == null) {
                        result.error("BAD_ARGUMENT", "Kiriman harus berupa teks JSON", null)
                    } else {
                        sendBatch(json, result)
                    }
                }
                "setPending" -> {
                    pendingCount = (call.arguments as? Number)?.toInt() ?: 0
                    notifyStatus()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun detach() {
        stop()
        channel.setMethodCallHandler(null)
    }

    // ------------------------------------------------------ izin dan mulai

    private fun start(result: MethodChannel.Result) {
        val missing = missingPermissions()
        if (missing.isEmpty()) {
            open(result)
            return
        }
        if (pendingStart != null) {
            result.error("PERMISSION_PENDING", "Permintaan izin Bluetooth belum selesai", null)
            return
        }
        pendingStart = result
        activity.requestPermissions(missing.toTypedArray(), PERMISSION_REQUEST_CODE)
    }

    /** Dipanggil dari MainActivity.onRequestPermissionsResult. */
    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        val result = pendingStart ?: return true
        pendingStart = null
        if (grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
            open(result)
        } else {
            result.error("PERMISSION_DENIED", "Izin Bluetooth ditolak", null)
        }
        return true
    }

    /** Di bawah Android 12, BLUETOOTH dan BLUETOOTH_ADMIN diberikan saat pemasangan. */
    private fun missingPermissions(): List<String> =
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            emptyList()
        } else {
            listOf(Manifest.permission.BLUETOOTH_ADVERTISE, Manifest.permission.BLUETOOTH_CONNECT)
                .filter { activity.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        }

    private fun open(result: MethodChannel.Result) {
        val bluetooth = manager
        val adapter = bluetooth?.adapter
        if (bluetooth == null || adapter == null) {
            result.error("NO_BLUETOOTH", "Jam ini tidak punya Bluetooth", null)
            return
        }
        if (!adapter.isEnabled) {
            result.error("BLUETOOTH_OFF", "Bluetooth jam mati", null)
            return
        }
        val advertiser = adapter.bluetoothLeAdvertiser
        if (!adapter.isMultipleAdvertisementSupported || advertiser == null) {
            result.error("NO_ADVERTISER", "Jam ini tidak mendukung BLE advertising (peripheral)", null)
            return
        }
        if (server == null) {
            server = bluetooth.openGattServer(activity, serverCallback)?.also {
                it.addService(buildService())
            }
        }
        if (server == null) {
            result.error("GATT_FAILED", "Gagal membuka GATT server", null)
            return
        }
        if (!advertising) {
            advertiser.startAdvertising(advertiseSettings, advertiseData, advertiseCallback)
            advertising = true
        }
        result.success(null)
    }

    private fun stop() {
        if (advertising) {
            runCatching { manager?.adapter?.bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback) }
            advertising = false
        }
        finishSending(error = "STOPPED" to "Pengiriman dihentikan")
        server?.close()
        server = null
        phone = null
        statusSubscribed = false
        notifying = false
        notifyingFrame = false
        mtus.clear()
    }

    private fun buildService(): BluetoothGattService {
        fun cccd() = BluetoothGattDescriptor(
            BleProtocol.CCCD,
            BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE,
        )
        val data = BluetoothGattCharacteristic(
            BleProtocol.DATA,
            BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            0,
        ).apply { addDescriptor(cccd()) }
        val control = BluetoothGattCharacteristic(
            BleProtocol.CONTROL,
            BluetoothGattCharacteristic.PROPERTY_WRITE,
            BluetoothGattCharacteristic.PERMISSION_WRITE,
        )
        val status = BluetoothGattCharacteristic(
            BleProtocol.STATUS,
            BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_READ,
        ).apply { addDescriptor(cccd()) }
        dataCharacteristic = data
        statusCharacteristic = status
        return BluetoothGattService(BleProtocol.SERVICE, BluetoothGattService.SERVICE_TYPE_PRIMARY)
            .apply {
                addCharacteristic(data)
                addCharacteristic(control)
                addCharacteristic(status)
            }
    }

    private val advertiseSettings = AdvertiseSettings.Builder()
        .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_BALANCED)
        .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
        .setConnectable(true)
        .build()

    // UUID 128-bit (18 byte) dan flags (3 byte) muat dalam 31 byte iklan. Nama
    // jam sengaja tidak disertakan agar iklan tidak melebihi batas itu.
    private val advertiseData = AdvertiseData.Builder()
        .setIncludeDeviceName(false)
        .addServiceUuid(ParcelUuid(BleProtocol.SERVICE))
        .build()

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartFailure(errorCode: Int) {
            mainHandler.post {
                advertising = false
                reportError("Iklan BLE gagal dimulai (kode $errorCode)")
            }
        }
    }

    // ------------------------------------------------------------ kiriman

    private fun sendBatch(json: String, result: MethodChannel.Result) {
        val device = phone ?: return result.error("NO_PHONE", "HP belum tersambung lewat BLE", null)
        if (sending != null) return result.error("BUSY", "Kiriman sebelumnya belum selesai", null)
        seq = (seq + 1) and 0xFFFF
        val mtu = mtus[device.address] ?: BleProtocol.DEFAULT_MTU
        val frames = BleProtocol.frames(seq, json.toByteArray(Charsets.UTF_8), mtu)
        sending = Sending(device, seq, ArrayDeque(frames), result)
        mainHandler.postDelayed(ackTimeout, ACK_TIMEOUT_MS)
        sendNextFrame()
    }

    /** Mengirim frame berikutnya; bila semua sudah terkirim, tinggal menunggu ACK. */
    private fun sendNextFrame() {
        if (notifying) return
        val current = sending ?: return
        val characteristic = dataCharacteristic
            ?: return finishSending(error = "NO_SERVER" to "GATT server berhenti")
        val frame = current.frames.removeFirstOrNull() ?: return
        if (!notify(current.device, characteristic, frame, isFrame = true)) {
            finishSending(error = "NOTIFY_FAILED" to "Notifikasi gagal dikirim")
        }
    }

    private fun finishSending(stored: Boolean = false, error: Pair<String, String>? = null) {
        val current = sending ?: return
        sending = null
        mainHandler.removeCallbacks(ackTimeout)
        if (error != null) {
            current.result.error(error.first, error.second, null)
        } else {
            current.result.success(stored)
        }
        if (statusDirty && !notifying) notifyStatus()
    }

    private fun onCommand(command: String) {
        val parts = command.split(' ')
        when (parts.first()) {
            BleProtocol.START -> channel.invokeMethod("phoneReady", null)
            BleProtocol.ACK, BleProtocol.RETRY -> {
                val current = sending ?: return
                if (parts.getOrNull(1)?.toIntOrNull() != current.seq) return
                finishSending(stored = parts.first() == BleProtocol.ACK)
            }
            else -> Log.w(TAG, "Perintah tidak dikenal: $command")
        }
    }

    // ------------------------------------------------------------- status

    private fun statusBytes() =
        """{"v":${BleProtocol.VERSION},"pending":$pendingCount}""".toByteArray(Charsets.UTF_8)

    private fun notifyStatus() {
        val device = phone ?: return
        val characteristic = statusCharacteristic ?: return
        if (!statusSubscribed) return
        if (notifying || sending != null) {
            statusDirty = true
            return
        }
        statusDirty = false
        notify(device, characteristic, statusBytes(), isFrame = false)
    }

    @Suppress("DEPRECATION")
    private fun notify(
        device: BluetoothDevice,
        characteristic: BluetoothGattCharacteristic,
        value: ByteArray,
        isFrame: Boolean,
    ): Boolean {
        val gattServer = server ?: return false
        val sent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            gattServer.notifyCharacteristicChanged(device, characteristic, false, value) ==
                BluetoothStatusCodes.SUCCESS
        } else {
            characteristic.value = value
            gattServer.notifyCharacteristicChanged(device, characteristic, false)
        }
        if (sent) {
            notifying = true
            notifyingFrame = isFrame
        }
        return sent
    }

    // ---------------------------------------------------- callback server

    private val serverCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            if (newState != BluetoothProfile.STATE_DISCONNECTED) return
            mainHandler.post {
                mtus.remove(device.address)
                if (phone?.address == device.address) {
                    phone = null
                    statusSubscribed = false
                    notifying = false
                    notifyingFrame = false
                }
                if (sending?.device?.address == device.address) {
                    finishSending(error = "DISCONNECTED" to "HP terputus saat menerima kiriman")
                }
            }
        }

        override fun onMtuChanged(device: BluetoothDevice, mtu: Int) {
            mainHandler.post { mtus[device.address] = mtu }
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray,
        ) {
            val enabled = value.contentEquals(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
            val characteristic = descriptor.characteristic.uuid
            mainHandler.post {
                when (characteristic) {
                    BleProtocol.DATA -> phone = when {
                        enabled -> device
                        phone?.address == device.address -> null
                        else -> phone
                    }
                    BleProtocol.STATUS -> statusSubscribed = enabled
                }
            }
            if (responseNeeded) {
                server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, null)
            }
        }

        override fun onDescriptorReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            descriptor: BluetoothGattDescriptor,
        ) {
            val on = when (descriptor.characteristic.uuid) {
                BleProtocol.DATA -> phone?.address == device.address
                BleProtocol.STATUS -> statusSubscribed
                else -> false
            }
            val value = if (on) {
                BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
            } else {
                BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE
            }
            server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, value)
        }

        override fun onCharacteristicReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            characteristic: BluetoothGattCharacteristic,
        ) {
            if (characteristic.uuid != BleProtocol.STATUS) {
                server?.sendResponse(device, requestId, BluetoothGatt.GATT_READ_NOT_PERMITTED, offset, null)
                return
            }
            val value = statusBytes()
            val start = minOf(offset, value.size)
            server?.sendResponse(
                device,
                requestId,
                BluetoothGatt.GATT_SUCCESS,
                offset,
                value.copyOfRange(start, value.size),
            )
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray,
        ) {
            val isControl = characteristic.uuid == BleProtocol.CONTROL
            if (responseNeeded) {
                val status = if (isControl) {
                    BluetoothGatt.GATT_SUCCESS
                } else {
                    BluetoothGatt.GATT_WRITE_NOT_PERMITTED
                }
                server?.sendResponse(device, requestId, status, offset, null)
            }
            if (!isControl) return
            val command = String(value, Charsets.UTF_8).trim()
            mainHandler.post { onCommand(command) }
        }

        override fun onNotificationSent(device: BluetoothDevice, status: Int) {
            mainHandler.post {
                val wasFrame = notifyingFrame
                notifying = false
                notifyingFrame = false
                if (wasFrame && status != BluetoothGatt.GATT_SUCCESS) {
                    finishSending(error = "NOTIFY_FAILED" to "Notifikasi gagal terkirim (status $status)")
                } else if (sending != null) {
                    sendNextFrame()
                } else if (statusDirty) {
                    notifyStatus()
                }
            }
        }
    }

    // ------------------------------------------------------------- helper

    private fun nameOf(device: BluetoothDevice): String =
        runCatching { device.name }.getOrNull() ?: device.address

    private fun reportError(message: String) {
        Log.w(TAG, message)
        channel.invokeMethod("linkError", message)
    }

    private companion object {
        const val TAG = "BleServer"
        const val CHANNEL = "edge/phone"
        const val PERMISSION_REQUEST_CODE = 4712

        /** Batas menunggu ACK setelah kiriman mulai dikirim. */
        const val ACK_TIMEOUT_MS = 15_000L
    }
}
