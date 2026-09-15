import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:hr_sdk_005_phone/utils/crc32.dart';

void main() {
  // Nilai acuan CRC-32 IEEE. Watch menghitung CRC dengan java.util.zip.CRC32,
  // jadi implementasi di sini wajib menghasilkan angka yang sama persis —
  // kalau tidak, setiap batch yang utuh akan ditolak sebagai crc_mismatch.
  test('cocok dengan vektor uji standar', () {
    expect(crc32(utf8.encode('123456789')), 0xCBF43926);
    expect(crc32(const []), 0);
    expect(crc32(utf8.encode('a')), 0xE8B7BE43);
  });

  test('berubah bila satu byte payload berubah', () {
    final asli = utf8.encode(
      '[{"bpm":78.0,"accuracy":3,"time":1750662000000}]',
    );
    final rusak = List<int>.from(asli)..[7] = 0x39;

    expect(crc32(rusak), isNot(crc32(asli)));
  });
}
