/// CRC-32 (polinomial IEEE 802.3, sama dengan `java.util.zip.CRC32` yang
/// dipakai watch) untuk memverifikasi payload batch yang sudah dirangkai.
///
/// Ditulis manual agar tidak menambah dependensi hanya untuk satu fungsi.
int crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte & 0xFF;
    for (var i = 0; i < 8; i++) {
      // 0xEDB88320 adalah bentuk terbalik dari polinomial 0x04C11DB7.
      crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
