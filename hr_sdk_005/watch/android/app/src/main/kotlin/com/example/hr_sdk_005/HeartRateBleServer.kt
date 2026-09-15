package com.example.hr_sdk_005

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import io.flutter.plugin.common.EventChannel
import java.util.ArrayDeque
import java.util.UUID
import java.util.zip.CRC32

/**
 * GATT server + BLE advertiser. Watch berperan sebagai **peripheral** yang
 * mengiklankan sebuah custom service berisi karakteristik "record" (notify).
 * Setiap pembacaan valid dikirim sebagai JSON `{bpm, accuracy, time}` lewat
 * notifikasi, sehingga aplikasi di smartphone bisa membangun ulang database
 * SQLite yang isinya identik dengan watch (lengkap dengan timestamp asli).
 *
 * Aplikasi phone tinggal scan service ini, connect, lalu subscribe ke
 * karakteristik record untuk menerima data.
 */
class HeartRateBleServer(private val context: Context) {

    companion object {
        private const val TAG = "HR-BLE"
        // Tag khusus metrik. Baris CSV bisa ditarik dengan:
        //   adb logcat -s HR-METRIC:I
        // Kolom: event,batch_id,records,bytes,frames,mtu,duration_ms,throughput_Bps
        private const val METRIC_TAG = "HR-METRIC"

        // Custom UUID (128-bit) untuk service & karakteristik record. Harus
        // sama dengan yang dipakai aplikasi phone saat scan/subscribe.
        val RECORD_SERVICE_UUID: UUID = UUID.fromString("0000a100-0000-1000-8000-00805f9b34fb")
        val RECORD_CHAR_UUID: UUID = UUID.fromString("0000a101-0000-1000-8000-00805f9b34fb")
        // Karakteristik ACK: ponsel menulis konfirmasi setelah menyimpan batch,
        // sehingga watch baru menandai data terkirim setelah benar-benar diterima.
        val ACK_CHAR_UUID: UUID = UUID.fromString("0000a102-0000-1000-8000-00805f9b34fb")
        // Client Characteristic Configuration Descriptor (untuk enable notify).
        val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

        // Opcode pada byte pertama tiap notifikasi, agar phone bisa merangkai
        // batch yang dipecah menjadi beberapa chunk. Semua bilangan multi-byte
        // memakai urutan big-endian.
        //   START = 0x01 | batch_id(4) | expected_frames(2) | payload_length(4)
        //   DATA  = 0x02 | seq(2) | potongan JSON
        //   END   = 0x03 | crc32(4)
        private const val OP_START: Byte = 0x01
        private const val OP_DATA: Byte = 0x02
        private const val OP_END: Byte = 0x03

        // Byte tambahan di depan payload tiap frame DATA: opcode + seq.
        private const val DATA_HEADER = 3
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val bluetoothManager =
        context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager

    private var gattServer: BluetoothGattServer? = null
    private var advertiser: BluetoothLeAdvertiser? = null
    private var recordChar: BluetoothGattCharacteristic? = null

    // Perangkat yang sudah meng-enable notify (boleh menerima notifikasi).
    private val subscribers = mutableSetOf<BluetoothDevice>()
    private var advertising = false

    // Pengiriman batch dengan flow-control: chunk berikutnya dikirim setelah
    // onNotificationSent dari chunk sebelumnya.
    private val sendQueue = ArrayDeque<ByteArray>()
    private var sending = false
    private var negotiatedMtu = 23 // default ATT MTU sebelum dinegosiasikan

    // Metrik per batch (untuk evaluasi).
    private var batchId = 0L           // pengenal batch berjalan (dikirim di START)
    private var batchRecords = 0       // jumlah record dalam batch berjalan
    private var batchPayloadBytes = 0  // ukuran payload JSON (tanpa header/opcode)
    private var batchFrames = 0        // total frame (START + DATA… + END)
    private var batchStartNs = 0L      // waktu mulai mengirim frame pertama

    private var statusSink: EventChannel.EventSink? = null
    private var ackSink: EventChannel.EventSink? = null

    val statusHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            statusSink = events
            // Kirim status terkini begitu Dart mulai mendengarkan.
            emit(if (isConnected()) "connected" else if (advertising) "advertising" else "idle")
        }

        override fun onCancel(arguments: Any?) {
            statusSink = null
        }
    }

    /// Aliran ACK ke Dart: isi tulisan ponsel diteruskan apa adanya sebagai
    /// String; parsing & validasi `batch_id` dilakukan di `ble_peripheral.dart`.
    val ackHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            ackSink = events
        }

        override fun onCancel(arguments: Any?) {
            ackSink = null
        }
    }

    fun isConnected(): Boolean = subscribers.isNotEmpty()

    private fun emit(state: String, message: String? = null) {
        mainHandler.post {
            statusSink?.success(mapOf("state" to state, "message" to message))
        }
    }

    @SuppressLint("MissingPermission")
    fun start() {
        val adapter = bluetoothManager.adapter
        if (adapter == null || !adapter.isEnabled) {
            emit("error", "Bluetooth tidak aktif")
            return
        }
        if (adapter.bluetoothLeAdvertiser == null) {
            emit("error", "Perangkat tidak mendukung BLE advertising")
            return
        }
        if (gattServer == null) {
            try {
                openGattServer()
            } catch (e: SecurityException) {
                emit("error", "Izin Bluetooth belum diberikan")
                Log.e(TAG, "openGattServer", e)
                return
            }
        }
        // 005: compileSdk 37 menandai getBluetoothLeAdvertiser() nullable; nilai
        // null sudah ditangani di atas, jadi baris ini hanya memenuhi Kotlin.
        startAdvertising(adapter.bluetoothLeAdvertiser ?: return)
    }

    @SuppressLint("MissingPermission")
    private fun openGattServer() {
        val server = bluetoothManager.openGattServer(context, gattServerCallback) ?: run {
            emit("error", "Gagal membuka GATT server")
            return
        }
        gattServer = server

        val service = BluetoothGattService(
            RECORD_SERVICE_UUID,
            BluetoothGattService.SERVICE_TYPE_PRIMARY,
        )
        val characteristic = BluetoothGattCharacteristic(
            RECORD_CHAR_UUID,
            BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            // Notify-only: tidak butuh izin read/write pada karakteristik itu sendiri.
            0,
        )
        val cccd = BluetoothGattDescriptor(
            CCCD_UUID,
            BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE,
        )
        characteristic.addDescriptor(cccd)
        service.addCharacteristic(characteristic)

        // Karakteristik ACK (write): ponsel menulis konfirmasi penerimaan batch.
        val ackCharacteristic = BluetoothGattCharacteristic(
            ACK_CHAR_UUID,
            BluetoothGattCharacteristic.PROPERTY_WRITE,
            BluetoothGattCharacteristic.PERMISSION_WRITE,
        )
        service.addCharacteristic(ackCharacteristic)

        server.addService(service)
        recordChar = characteristic
    }

    @SuppressLint("MissingPermission")
    private fun startAdvertising(adv: BluetoothLeAdvertiser) {
        if (advertising) return
        advertiser = adv

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .setTimeout(0) // tanpa batas waktu; berhenti manual lewat stop()
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .build()

        // Paket utama: service UUID agar mudah difilter oleh aplikasi ponsel.
        val data = AdvertiseData.Builder()
            .addServiceUuid(ParcelUuid(RECORD_SERVICE_UUID))
            .build()

        // Nama perangkat ditaruh di scan response agar tidak melebihi 31 byte.
        val scanResponse = AdvertiseData.Builder()
            .setIncludeDeviceName(true)
            .build()

        try {
            adv.startAdvertising(settings, data, scanResponse, advertiseCallback)
        } catch (e: SecurityException) {
            emit("error", "Izin BLUETOOTH_ADVERTISE belum diberikan")
            Log.e(TAG, "startAdvertising", e)
        }
    }

    @SuppressLint("MissingPermission")
    fun stop() {
        try {
            advertiser?.stopAdvertising(advertiseCallback)
        } catch (e: SecurityException) {
            Log.e(TAG, "stopAdvertising", e)
        }
        advertiser = null
        advertising = false

        try {
            gattServer?.close()
        } catch (e: SecurityException) {
            Log.e(TAG, "closeGattServer", e)
        }
        gattServer = null
        recordChar = null
        subscribers.clear()
        sendQueue.clear()
        sending = false
        emit("idle")
    }

    /**
     * Kirim satu **batch** (JSON array `[{bpm, accuracy, time}, ...]`) ke
     * perangkat yang sedang subscribe. Payload dipecah menjadi beberapa chunk
     * berukuran sesuai MTU, masing-masing diawali opcode (START/DATA/END) agar
     * phone bisa merangkainya kembali. Chunk dikirim satu per satu dengan
     * flow-control lewat [onNotificationSent].
     *
     * [id] adalah pengenal batch (uint32) yang dibawa frame START dan
     * dikembalikan ponsel di dalam ACK.
     *
     * Mengembalikan `true` bila ada perangkat terhubung dan batch diantrekan.
     * Menolak (`false`) bila masih ada batch yang sedang dikirim, agar antrean
     * tidak dikosongkan di tengah transfer.
     */
    fun sendBatch(json: String, count: Int = 0, id: Long = 0L): Boolean {
        if (subscribers.isEmpty() || recordChar == null) return false
        if (sending) {
            Log.w(TAG, "sendBatch ditolak: batch $batchId masih dikirim")
            return false
        }
        val bytes = json.toByteArray(Charsets.UTF_8)
        // Sisakan ruang untuk header ATT (3 byte), opcode, dan nomor urut.
        val chunkSize = (negotiatedMtu - 3 - DATA_HEADER).coerceAtLeast(16)
        val dataFrames = (bytes.size + chunkSize - 1) / chunkSize

        sendQueue.clear()
        sendQueue.add(
            byteArrayOf(
                OP_START,
                (id ushr 24).toByte(),
                (id ushr 16).toByte(),
                (id ushr 8).toByte(),
                id.toByte(),
                (dataFrames ushr 8).toByte(),
                dataFrames.toByte(),
                (bytes.size ushr 24).toByte(),
                (bytes.size ushr 16).toByte(),
                (bytes.size ushr 8).toByte(),
                bytes.size.toByte(),
            ),
        )
        var i = 0
        var seq = 0
        while (i < bytes.size) {
            val end = minOf(i + chunkSize, bytes.size)
            val frame = ByteArray(end - i + DATA_HEADER)
            frame[0] = OP_DATA
            frame[1] = (seq ushr 8).toByte()
            frame[2] = seq.toByte()
            System.arraycopy(bytes, i, frame, DATA_HEADER, end - i)
            sendQueue.add(frame)
            i = end
            seq++
        }
        // END membawa CRC32 payload agar penerima bisa memverifikasi
        // kelengkapan batch, bukan hanya mengandalkan JSON yang bisa di-parse.
        val crc = CRC32().apply { update(bytes) }.value
        sendQueue.add(
            byteArrayOf(
                OP_END,
                (crc ushr 24).toByte(),
                (crc ushr 16).toByte(),
                (crc ushr 8).toByte(),
                crc.toByte(),
            ),
        )

        // Catat metrik batch; durasi diukur saat frame pertama benar-benar dikirim.
        batchId = id
        batchRecords = count
        batchPayloadBytes = bytes.size
        batchFrames = sendQueue.size
        batchStartNs = 0L

        Log.d(
            TAG,
            "sendBatch #$id: ${bytes.size} byte dalam ${sendQueue.size} frame (mtu=$negotiatedMtu)",
        )
        if (!sending) sendNextFrame()
        return true
    }

    /** Kirim satu frame dari antrean ke semua subscriber. */
    @SuppressLint("MissingPermission")
    private fun sendNextFrame() {
        val characteristic = recordChar
        val server = gattServer
        val frame = sendQueue.poll()
        if (frame == null || characteristic == null || server == null) {
            // Antrean habis → batch selesai terkirim. Catat metrik bila sebelumnya
            // memang ada pengiriman berjalan (batchStartNs sudah diset).
            if (sending && batchStartNs > 0L) {
                val durationMs = (System.nanoTime() - batchStartNs) / 1_000_000.0
                val throughput = if (durationMs > 0) {
                    (batchPayloadBytes * 1000.0 / durationMs).toLong()
                } else 0L
                Log.i(
                    METRIC_TAG,
                    "tx_batch,$batchId,$batchRecords,$batchPayloadBytes,$batchFrames," +
                        "$negotiatedMtu,${"%.1f".format(durationMs)},$throughput",
                )
                batchStartNs = 0L
            }
            sending = false
            return
        }
        // Tandai awal pengiriman pada frame pertama batch.
        if (batchStartNs == 0L) batchStartNs = System.nanoTime()
        sending = true
        characteristic.value = frame
        for (device in subscribers.toList()) {
            try {
                server.notifyCharacteristicChanged(device, characteristic, false)
            } catch (e: SecurityException) {
                Log.e(TAG, "notifyCharacteristicChanged", e)
            }
        }
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            advertising = true
            Log.d(TAG, "advertising dimulai")
            emit(if (isConnected()) "connected" else "advertising", "menunggu koneksi")
        }

        override fun onStartFailure(errorCode: Int) {
            advertising = false
            Log.e(TAG, "advertising gagal: $errorCode")
            emit("error", "Advertising gagal (kode $errorCode)")
        }
    }

    private val gattServerCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice?, status: Int, newState: Int) {
            device ?: return
            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    // Sengaja belum "connected": tautan sudah terbentuk, tetapi
                    // batch baru boleh dikirim setelah ponsel menulis CCCD dan
                    // masuk daftar subscriber. Status diumumkan di
                    // onDescriptorWriteRequest agar sepadan dengan isConnected(),
                    // dan agar backfill saat rekoneksi tidak terpicu terlalu dini
                    // lalu terbuang karena belum ada penerima.
                    Log.d(TAG, "tautan terbentuk: ${device.address}")
                }
                BluetoothProfile.STATE_DISCONNECTED -> {
                    Log.d(TAG, "perangkat terputus: ${device.address}")
                    subscribers.remove(device)
                    // Hentikan pengiriman batch yang sedang berjalan.
                    sendQueue.clear()
                    sending = false
                    negotiatedMtu = 23
                    emit(if (advertising) "advertising" else "idle", "perangkat terputus")
                }
            }
        }

        override fun onMtuChanged(device: BluetoothDevice?, mtu: Int) {
            // Simpan MTU hasil negosiasi central agar chunk batch dibuat optimal.
            negotiatedMtu = mtu
            Log.d(TAG, "MTU dinegosiasikan: $mtu")
        }

        override fun onNotificationSent(device: BluetoothDevice?, status: Int) {
            // Flow-control: kirim chunk berikutnya setelah yang sebelumnya tuntas.
            sendNextFrame()
        }

        @SuppressLint("MissingPermission")
        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice?,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic?,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?,
        ) {
            if (characteristic?.uuid == ACK_CHAR_UUID) {
                // Payload ACK = JSON {batch_id, expected, stored, status}.
                val payload = value?.toString(Charsets.UTF_8)?.trim().orEmpty()
                Log.d(TAG, "ACK diterima: $payload")
                mainHandler.post { ackSink?.success(payload) }
            }
            // 005: compileSdk 37 mewajibkan device non-null untuk sendResponse.
            if (responseNeeded && device != null) {
                try {
                    gattServer?.sendResponse(
                        device,
                        requestId,
                        android.bluetooth.BluetoothGatt.GATT_SUCCESS,
                        offset,
                        value,
                    )
                } catch (e: SecurityException) {
                    Log.e(TAG, "sendResponse(ack)", e)
                }
            }
        }

        @SuppressLint("MissingPermission")
        override fun onDescriptorWriteRequest(
            device: BluetoothDevice?,
            requestId: Int,
            descriptor: BluetoothGattDescriptor?,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?,
        ) {
            if (device != null && descriptor?.uuid == CCCD_UUID && value != null) {
                // value == ENABLE_NOTIFICATION_VALUE (0x01, 0x00) → subscribe.
                val enable = value.isNotEmpty() && value[0].toInt() != 0
                if (enable) {
                    subscribers.add(device)
                    emit("connected", device.address)
                } else {
                    subscribers.remove(device)
                }
                Log.d(TAG, "CCCD write enable=$enable dari ${device.address}")
            }
            // 005: compileSdk 37 mewajibkan device non-null untuk sendResponse.
            if (responseNeeded && device != null) {
                try {
                    gattServer?.sendResponse(
                        device,
                        requestId,
                        android.bluetooth.BluetoothGatt.GATT_SUCCESS,
                        offset,
                        value,
                    )
                } catch (e: SecurityException) {
                    Log.e(TAG, "sendResponse", e)
                }
            }
        }
    }
}
