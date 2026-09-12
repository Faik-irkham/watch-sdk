import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hr_sdk_004/measurement_store.dart';

/// Menulis ke SQLite tanpa menahan aliran data
mixin PersistsMeasurements<T extends StatefulWidget> on State<T> {
  final MeasurementStore store = MeasurementStore.instance;

  int _saved = 0;
  bool _saveFailed = false;

  String? get savedLabel {
    if (_saveFailed) return 'Gagal menyimpan ke SQLite';
    return _saved == 0 ? null : '$_saved tersimpan';
  }

  void resetSaved() {
    _saved = 0;
    _saveFailed = false;
  }

  void persist(Future<int> write) {
    write.then(
      (count) {
        if (count > 0 && mounted) setState(() => _saved += count);
      },
      onError: (Object error) {
        debugPrint('Gagal menyimpan ke SQLite: $error');
        if (mounted) setState(() => _saveFailed = true);
      },
    );
  }
}

String describeStreamError(Object error) => error is PlatformException
    ? (error.message ?? error.code)
    : error.toString();

/// Area aman untuk layar bulat Galaxy Watch4 (198×198 dp).
///
/// Isi disusun pada lebar tetap supaya teks membungkus di tempat yang sama,
/// lalu diperkecil seperlunya bila lebih tinggi dari ruang yang tersedia,
/// misalnya saat ukuran huruf jam diperbesar atau pesan galat panjang. Tidak
/// ada yang overflow, dan tombol tidak pernah terdorong keluar layar.
class WatchSafeContent extends StatelessWidget {
  const WatchSafeContent({super.key, required this.child, this.width = designWidth});

  /// Lebar susunan isi. Pada ketinggian tengah layar bulat, lebar ini masih
  /// berada di dalam lingkaran.
  static const double designWidth = 150;

  final Widget child;

  /// Lebih sempit dari [designWidth] untuk isi yang elemen lebarnya bisa
  /// terdorong ke atas, tempat lingkaran layar menyempit.
  final double width;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Bawah paling lega: baris tombol adalah elemen terlebar dan duduk di
      // bawah, tempat lingkaran layar paling sempit; titik penanda halaman juga
      // ada di sana.
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(width: width, child: child),
        ),
      ),
    );
  }
}

/// Tata letak bersama ketiga halaman pengukuran: bacaan sensor, pesan status,
/// keterangan penyimpanan, lalu tombol.
class MeasurementLayout extends StatelessWidget {
  const MeasurementLayout({
    super.key,
    required this.reading,
    required this.message,
    required this.buttonLabel,
    required this.onPressed,
    this.footnote,
    this.onHistory,
  });

  final Widget reading;
  final String message;
  final String buttonLabel;
  final VoidCallback onPressed;
  final String? footnote;
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) {
    return WatchSafeContent(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          reading,
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Colors.white60),
          ),
          if (footnote != null) Footnote(footnote!),
          const SizedBox(height: 8),
          MeasurementActions(
            buttonLabel: buttonLabel,
            onPressed: onPressed,
            onHistory: onHistory,
          ),
        ],
      ),
    );
  }
}

/// Satu angka besar beserta ikon dan satuannya, untuk detak jantung dan SpO2.
class ValueReading extends StatelessWidget {
  const ValueReading({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.unit,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Mengecil sendiri bila angka dan ikon lebih lebar dari area isi.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 6),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w600,
                  height: 1,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        Text(unit, style: const TextStyle(color: Colors.white54)),
      ],
    );
  }
}

/// Tombol utama pengukuran, diikuti tombol riwayat bila tersedia.
class MeasurementActions extends StatelessWidget {
  const MeasurementActions({
    super.key,
    required this.buttonLabel,
    required this.onPressed,
    this.onHistory,
  });

  final String buttonLabel;
  final VoidCallback onPressed;
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) {
    final history = onHistory;
    // Mengecil sendiri bila label memanjang karena ukuran huruf diperbesar.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18),
            ),
            child: Text(buttonLabel),
          ),
          if (history != null) ...[
            const SizedBox(width: 6),
            IconButton.filledTonal(
              onPressed: history,
              tooltip: 'Riwayat',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.history, size: 20),
            ),
          ],
        ],
      ),
    );
  }
}

class Footnote extends StatelessWidget {
  const Footnote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, color: Colors.white38),
      ),
    );
  }
}
