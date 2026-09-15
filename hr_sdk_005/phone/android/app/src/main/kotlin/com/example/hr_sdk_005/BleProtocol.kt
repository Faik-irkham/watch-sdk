package com.example.hr_sdk_005

import java.nio.ByteBuffer
import java.util.UUID

/**
 * Protokol BLE HR 005 antara jam (peripheral, GATT server) dan HP (central,
 * GATT client). Berkas ini sama persis di aplikasi jam dan aplikasi HP.
 *
 * Service HR005:
 * - DATA    (notify)        jam → HP: satu kiriman JSON, dipotong menjadi frame.
 * - CONTROL (write)         HP → jam: `START`, `ACK <nomor>`, `RETRY <nomor>`.
 * - STATUS  (read + notify) jam → HP: `{"v":1,"pending":N}`.
 *
 * DATA dan STATUS memakai CCCD standar (0x2902). HP menulis 0x0001 ke CCCD
 * untuk menyalakan notifikasi.
 *
 * Satu frame: nomor kiriman (2 byte), nomor potongan (2 byte), jumlah
 * potongan (2 byte), lalu isi potongan. Semua bilangan big-endian tanpa tanda.
 */
object BleProtocol {
    val SERVICE: UUID = UUID.fromString("07229ca5-66dd-4d2d-8780-e43d760716ce")
    val DATA: UUID = UUID.fromString("32730064-e102-4e66-bbf7-d64dc980f9b8")
    val CONTROL: UUID = UUID.fromString("afa422dd-7122-429c-af84-85e35b22d96a")
    val STATUS: UUID = UUID.fromString("6d641fda-5730-46c1-8b23-bce729194cec")

    /** Client Characteristic Configuration Descriptor: UUID standar Bluetooth SIG. */
    val CCCD: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    const val VERSION = 1

    const val START = "START"
    const val ACK = "ACK"
    const val RETRY = "RETRY"

    /** MTU yang diminta HP setelah tersambung. */
    const val REQUESTED_MTU = 517

    /** MTU bawaan BLE bila HP tidak meminta yang lebih besar. */
    const val DEFAULT_MTU = 23

    /** Header ATT pada notifikasi: opcode 1 byte dan handle 2 byte. */
    private const val ATT_HEADER = 3

    /** Batas panjang nilai atribut GATT. */
    private const val MAX_ATTRIBUTE = 512

    const val FRAME_HEADER = 6

    /** Memotong satu kiriman menjadi frame yang masing-masing muat dalam satu notifikasi. */
    fun frames(seq: Int, payload: ByteArray, mtu: Int): List<ByteArray> {
        val frameSize = minOf(mtu - ATT_HEADER, MAX_ATTRIBUTE)
        val chunk = (frameSize - FRAME_HEADER).coerceAtLeast(1)
        val count = maxOf(1, (payload.size + chunk - 1) / chunk)
        require(count <= 0xFFFF) { "Kiriman terlalu besar untuk MTU $mtu" }
        return List(count) { index ->
            val start = index * chunk
            val length = minOf(payload.size, start + chunk) - start
            ByteBuffer.allocate(FRAME_HEADER + length)
                .putShort(seq.toShort())
                .putShort(index.toShort())
                .putShort(count.toShort())
                .put(payload, start, length)
                .array()
        }
    }

    class Frame(val seq: Int, val index: Int, val count: Int, val body: ByteArray)

    /** Membaca header satu frame; null bila frame rusak. */
    fun parseFrame(bytes: ByteArray): Frame? {
        if (bytes.size < FRAME_HEADER) return null
        val buffer = ByteBuffer.wrap(bytes)
        val seq = buffer.short.toInt() and 0xFFFF
        val index = buffer.short.toInt() and 0xFFFF
        val count = buffer.short.toInt() and 0xFFFF
        if (count == 0 || index >= count) return null
        return Frame(seq, index, count, bytes.copyOfRange(FRAME_HEADER, bytes.size))
    }
}
