package com.example.hr_sdk_005

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.UUID

/**
 * HP sebagai central BLE: mencari jam yang mengiklankan service HR005 (lihat
 * [BleProtocol]), tersambung, lalu menerima kiriman lewat notifikasi DATA.
 *
 * Urutan setelah tersambung, satu operasi GATT pada satu waktu:
 * minta MTU → cari service → CCCD DATA → CCCD STATUS → tulis START.
 * Frame DATA disusun ulang menjadi satu kiriman JSON dan diteruskan ke Dart.
 * Setelah Dart menjawab, HP menulis `ACK <nomor>` atau `RETRY <nomor>` ke
 * CONTROL. Bila sambungan putus, pencarian diulang otomatis.
 *
 * Izin dan status Bluetooth diperiksa sendiri sebelum dipakai, sehingga
 * peringatan MissingPermission diredam untuk seluruh kelas.
 */
@SuppressLint("MissingPermission")
class BleClient(private val activity: Activity, messenger: BinaryMessenger) {

    private val context = activity.applicationContext
    private val channel = MethodChannel(messenger, CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val manager: BluetoothManager? = context.getSystemService(BluetoothManager::class.java)

    /** Dart meminta HP tetap tersambung ke jam. */
    private var wanted = false
    private var scanning = false
    private var gatt: BluetoothGatt? = null
    private var control: BluetoothGattCharacteristic? = null
    private var watchName: String? = null
    private var ready = false
    private var pendingStart: MethodChannel.Result? = null

    /** Potongan kiriman yang sedang disusun. */
    private var batchSeq = -1
    private var parts: Array<ByteArray?> = emptyArray()

    fun attach() {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> start(result)
                "stop" -> {
                    stop()
                    state("idle")
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
            begin(result)
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
            begin(result)
        } else {
            result.error("PERMISSION_DENIED", "Izin Bluetooth ditolak", null)
        }
        return true
    }

    /** Android 12 ke atas: izin BLE. Di bawahnya, pencarian BLE menuntut izin lokasi. */
    private fun missingPermissions(): List<String> {
        val needed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            listOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            listOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        return needed.filter { context.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
    }

    private fun begin(result: MethodChannel.Result) {
        val adapter = manager?.adapter
        if (adapter == null) {
            result.error("NO_BLUETOOTH", "HP ini tidak punya Bluetooth", null)
            return
        }
        if (!adapter.isEnabled) {
            result.error("BLUETOOTH_OFF", "Bluetooth HP mati", null)
            return
        }
        wanted = true
        scan()
        result.success(null)
    }

    private fun stop() {
        wanted = false
        mainHandler.removeCallbacksAndMessages(null)
        stopScan()
        gatt?.disconnect()
        gatt?.close()
        gatt = null
        control = null
        ready = false
        resetAssembly()
    }

    // ----------------------------------------------------- cari dan sambung

    private fun scan() {
        if (!wanted || scanning || gatt != null) return
        val scanner = manager?.adapter?.bluetoothLeScanner
        if (scanner == null) {
            state("error", "Bluetooth HP mati")
            return
        }
        val filters = listOf(
            ScanFilter.Builder().setServiceUuid(ParcelUuid(BleProtocol.SERVICE)).build(),
        )
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
        scanner.startScan(filters, settings, scanCallback)
        scanning = true
        state("scanning")
    }

    private fun stopScan() {
        if (!scanning) return
        runCatching { manager?.adapter?.bluetoothLeScanner?.stopScan(scanCallback) }
        scanning = false
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            mainHandler.post { connect(result.device) }
        }

        override fun onScanFailed(errorCode: Int) {
            mainHandler.post {
                scanning = false
                state("error", "Pencarian BLE gagal (kode $errorCode)")
                retryLater()
            }
        }
    }

    private fun connect(device: BluetoothDevice) {
        if (gatt != null || !wanted) return
        stopScan()
        watchName = runCatching { device.name }.getOrNull() ?: device.address
        state("connecting")
        gatt = device.connectGatt(context, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
    }

    private fun disconnected() {
        gatt?.close()
        gatt = null
        control = null
        ready = false
        resetAssembly()
        state("disconnected")
        retryLater()
    }

    /** Jeda sebelum mencari lagi; Android membatasi pencarian yang terlalu sering. */
    private fun retryLater() {
        if (wanted) mainHandler.postDelayed({ scan() }, RETRY_DELAY_MS)
    }

    // -------------------------------------------------------- callback GATT

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            mainHandler.post {
                if (status == BluetoothGatt.GATT_SUCCESS && newState == BluetoothProfile.STATE_CONNECTED) {
                    if (!g.requestMtu(BleProtocol.REQUESTED_MTU)) g.discoverServices()
                } else if (g == gatt) {
                    disconnected()
                }
            }
        }

        override fun onMtuChanged(g: BluetoothGatt, mtu: Int, status: Int) {
            mainHandler.post { g.discoverServices() }
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            mainHandler.post {
                val service = g.getService(BleProtocol.SERVICE)
                val data = service?.getCharacteristic(BleProtocol.DATA)
                control = service?.getCharacteristic(BleProtocol.CONTROL)
                if (status != BluetoothGatt.GATT_SUCCESS || data == null || control == null) {
                    state("error", "Service HR005 tidak ditemukan di jam")
                    g.disconnect()
                    return@post
                }
                enableNotifications(g, data)
            }
        }

        override fun onDescriptorWrite(g: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
            mainHandler.post {
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    state("error", "Gagal menyalakan notifikasi (status $status)")
                    g.disconnect()
                    return@post
                }
                val statusCharacteristic = g.getService(BleProtocol.SERVICE)
                    ?.getCharacteristic(BleProtocol.STATUS)
                if (descriptor.characteristic.uuid == BleProtocol.DATA && statusCharacteristic != null) {
                    enableNotifications(g, statusCharacteristic)
                } else {
                    writeControl(BleProtocol.START)
                }
            }
        }

        override fun onCharacteristicWrite(
            g: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            mainHandler.post {
                // Tulisan pertama ke CONTROL adalah START: jam kini mulai mengirim.
                if (!ready && status == BluetoothGatt.GATT_SUCCESS) {
                    ready = true
                    state("connected")
                }
            }
        }

        override fun onCharacteristicChanged(
            g: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
        ) {
            val uuid = characteristic.uuid
            mainHandler.post { onNotification(uuid, value) }
        }

        // Android 12 ke bawah hanya memanggil versi lama ini.
        @Deprecated("Diganti versi dengan parameter value sejak API 33")
        @Suppress("DEPRECATION")
        override fun onCharacteristicChanged(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) return
            val value = characteristic.value?.copyOf() ?: return
            val uuid = characteristic.uuid
            mainHandler.post { onNotification(uuid, value) }
        }
    }

    @Suppress("DEPRECATION")
    private fun enableNotifications(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
        g.setCharacteristicNotification(characteristic, true)
        val cccd = characteristic.getDescriptor(BleProtocol.CCCD)
        if (cccd == null) {
            state("error", "CCCD tidak ditemukan di jam")
            return
        }
        val enable = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            g.writeDescriptor(cccd, enable)
        } else {
            cccd.value = enable
            g.writeDescriptor(cccd)
        }
    }

    @Suppress("DEPRECATION")
    private fun writeControl(text: String) {
        val g = gatt ?: return
        val characteristic = control ?: return
        val bytes = text.toByteArray(Charsets.UTF_8)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            g.writeCharacteristic(characteristic, bytes, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT)
        } else {
            characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            characteristic.value = bytes
            g.writeCharacteristic(characteristic)
        }
    }

    // --------------------------------------------------------- notifikasi

    private fun onNotification(uuid: UUID, value: ByteArray) {
        when (uuid) {
            BleProtocol.DATA -> onFrame(value)
            BleProtocol.STATUS -> channel.invokeMethod("onStatus", String(value, Charsets.UTF_8))
        }
    }

    private fun onFrame(bytes: ByteArray) {
        val frame = BleProtocol.parseFrame(bytes) ?: return
        if (frame.seq != batchSeq || parts.size != frame.count) {
            batchSeq = frame.seq
            parts = arrayOfNulls(frame.count)
        }
        parts[frame.index] = frame.body
        if (parts.any { it == null }) return

        val out = ByteArrayOutputStream()
        parts.forEach { out.write(it!!) }
        val json = String(out.toByteArray(), Charsets.UTF_8)
        val seq = batchSeq
        resetAssembly()
        channel.invokeMethod("onBatch", mapOf("json" to json), object : MethodChannel.Result {
            override fun success(result: Any?) = answer(seq, result == true)

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) =
                answer(seq, false)

            // Mesin Dart belum siap: jam akan mengirim ulang.
            override fun notImplemented() = answer(seq, false)
        })
    }

    private fun answer(seq: Int, stored: Boolean) =
        writeControl("${if (stored) BleProtocol.ACK else BleProtocol.RETRY} $seq")

    private fun resetAssembly() {
        batchSeq = -1
        parts = emptyArray()
    }

    private fun state(phase: String, message: String? = null) {
        channel.invokeMethod(
            "onState",
            mapOf("phase" to phase, "name" to watchName, "message" to message),
        )
    }

    private companion object {
        const val CHANNEL = "edge/watch"
        const val PERMISSION_REQUEST_CODE = 4713
        const val RETRY_DELAY_MS = 3_000L
    }
}
