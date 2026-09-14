import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hr_sdk_004/measurement_store.dart';
import 'package:hr_sdk_004/samsung_health_service.dart';

/// Warna penanda tiap sensor: judul, tombol, cincin pengukuran, dan titik
/// penanda halaman.
abstract final class SensorColors {
  static const heartRate = Color(0xFFFF6B6B);
  static const spo2 = Color(0xFF4FC3F7);
  static const accelerometer = Color(0xFFFFD54F);
  static const ppg = Color(0xFF69F0AE);
}

/// Merah muda lembut untuk pesan galat; tetap terbaca di latar hitam.
const errorTextColor = Color(0xFFFFB4AB);

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
  const WatchSafeContent({
    super.key,
    required this.child,
    this.width = designWidth,
  });

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

/// Tata letak bersama halaman pengukuran: judul sensor di atas, bacaan dan
/// pesan di tengah, tombol di bawah, dan cincin di tepi layar selama mengukur.
/// Selama mengukur, layar juga dijaga tetap menyala.
///
/// Judul dan tombol berada di posisi dan ukuran tetap di semua halaman. Hanya
/// bagian tengah yang diperkecil bila tidak muat, dan ruang pesannya
/// dicadangkan tetap, jadi ukuran bacaan tidak melompat saat pesan berganti.
class MeasurementLayout extends StatelessWidget {
  const MeasurementLayout({
    super.key,
    required this.title,
    required this.icon,
    required this.accent,
    required this.reading,
    required this.message,
    required this.measuring,
    required this.onStart,
    required this.onStop,
    this.messageIsError = false,
    this.footnote,
    this.onHistory,
    this.countdown,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final Widget reading;
  final String message;
  final bool messageIsError;
  final bool measuring;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final String? footnote;
  final VoidCallback? onHistory;

  /// Bila diisi, cincin tepi menghitung mundur selama durasi ini. Tanpa itu,
  /// cincin menyala penuh selama pengukuran berjalan.
  final Duration? countdown;

  @override
  Widget build(BuildContext context) {
    final limit = countdown;
    return KeepScreenOn(
      active: measuring,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 26),
            child: Column(
              children: [
                // Puncak layar paling sempit: judul dibatasi selebar ini dan
                // mengecil sendiri bila ukuran huruf jam diperbesar.
                SizedBox(
                  width: 104,
                  height: 16,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SensorTitle(icon: icon, title: title, color: accent),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: WatchSafeContent.designWidth,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            reading,
                            const SizedBox(height: 6),
                            _StatusText(
                              message: message,
                              isError: messageIsError,
                              footnote: footnote,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                MeasurementActions(
                  measuring: measuring,
                  accent: accent,
                  onPressed: measuring ? onStop : onStart,
                  onHistory: onHistory,
                ),
              ],
            ),
          ),
          if (measuring)
            Positioned.fill(
              child: IgnorePointer(
                child: limit == null
                    ? MeasuringRing(color: accent)
                    : CountdownRing(duration: limit, color: accent),
              ),
            ),
        ],
      ),
    );
  }
}

/// Menjaga layar jam tetap menyala selama [active], supaya layar tidak mati
/// di tengah pengukuran dan aplikasi tetap di latar depan, seperti yang
/// diminta pedoman Samsung Health Sensor SDK.
class KeepScreenOn extends StatefulWidget {
  const KeepScreenOn({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<KeepScreenOn> createState() => _KeepScreenOnState();
}

class _KeepScreenOnState extends State<KeepScreenOn> {
  /// Saat bergeser antarhalaman, dua halaman bisa hidup bersamaan. Flag
  /// jendela baru dilepas saat tidak ada satu pun yang masih memintanya.
  static int _holders = 0;

  bool _holding = false;

  @override
  void initState() {
    super.initState();
    _hold(widget.active);
  }

  @override
  void didUpdateWidget(KeepScreenOn oldWidget) {
    super.didUpdateWidget(oldWidget);
    _hold(widget.active);
  }

  @override
  void dispose() {
    _hold(false);
    super.dispose();
  }

  void _hold(bool hold) {
    if (hold == _holding) return;
    _holding = hold;
    _holders += hold ? 1 : -1;
    // Hanya peralihan dari tidak ada ke ada peminta, dan sebaliknya, yang
    // menyentuh platform.
    if (_holders == (hold ? 1 : 0)) {
      SamsungHealthService().keepScreenOn(hold).catchError((Object error) {
        debugPrint('Gagal mengatur layar tetap menyala: $error');
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Ikon dan nama sensor dalam warna sensornya.
class SensorTitle extends StatelessWidget {
  const SensorTitle({
    super.key,
    required this.icon,
    required this.title,
    required this.color,
  });

  final IconData icon;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 4),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Satu angka besar beserta satuannya, untuk detak jantung dan SpO2.
class ValueReading extends StatelessWidget {
  const ValueReading({super.key, required this.value, required this.unit});

  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 46,
              fontWeight: FontWeight.w600,
              height: 1,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(unit, style: const TextStyle(fontSize: 12, color: Colors.white54)),
      ],
    );
  }
}

/// Pesan status dan keterangan penyimpanan di bawahnya.
class _StatusText extends StatelessWidget {
  const _StatusText({
    required this.message,
    required this.isError,
    this.footnote,
  });

  final String message;
  final bool isError;
  final String? footnote;

  static const double _messageSize = 11;
  static const double _footnoteSize = 10;
  static const double _lineHeight = 1.2;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    // Dua baris pesan dan satu baris keterangan selalu dicadangkan, supaya
    // bacaan di atasnya tidak berubah ukuran saat pesan memanjang atau
    // keterangan "tersimpan" muncul.
    final reserved =
        (scaler.scale(_messageSize) * 2 + scaler.scale(_footnoteSize)) *
        _lineHeight;
    final note = footnote;
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: reserved,
        minWidth: double.infinity,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: _messageSize,
              height: _lineHeight,
              color: isError ? errorTextColor : Colors.white60,
            ),
          ),
          if (note != null)
            Text(
              note,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: _footnoteSize,
                height: _lineHeight,
                color: Colors.white38,
              ),
            ),
        ],
      ),
    );
  }
}

/// Tombol utama pengukuran, diikuti tombol riwayat bila tersedia.
///
/// Mulai berwarna penuh; Berhenti berwarna lembut, jadi keadaan pengukuran
/// terbaca dari tombolnya saja.
class MeasurementActions extends StatelessWidget {
  const MeasurementActions({
    super.key,
    required this.measuring,
    required this.accent,
    required this.onPressed,
    this.onHistory,
  });

  final bool measuring;
  final Color accent;
  final VoidCallback onPressed;
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) {
    final history = onHistory;
    // Ukuran tetap: tombol hanya mengecil bila label memanjang karena ukuran
    // huruf jam diperbesar, tidak ikut isi di atasnya.
    return SizedBox(
      width: 136,
      height: 48,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: measuring
                    ? accent.withValues(alpha: 0.18)
                    : accent,
                foregroundColor: measuring ? accent : Colors.black,
                minimumSize: const Size(88, 40),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                // Gaya tema ditebalkan, bukan diganti: TextStyle baru akan
                // membuang keluarga fon tema.
                textStyle: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              child: Text(measuring ? 'Berhenti' : 'Mulai'),
            ),
            if (history != null) ...[
              const SizedBox(width: 6),
              IconButton.filledTonal(
                onPressed: history,
                tooltip: 'Riwayat',
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white12,
                  foregroundColor: Colors.white70,
                ),
                icon: const Icon(Icons.history, size: 20),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Cincin tipis mengikuti tepi layar bulat selama pengukuran berjalan.
/// [progress] 0–1 menggambar busur dari arah jam 12; tanpa itu cincin penuh.
class MeasuringRing extends StatelessWidget {
  const MeasuringRing({super.key, required this.color, this.progress});

  final Color color;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _RingPainter(color: color, progress: progress),
    );
  }
}

/// Cincin yang menyusut dari penuh ke kosong selama [duration].
class CountdownRing extends StatefulWidget {
  const CountdownRing({super.key, required this.duration, required this.color});

  final Duration duration;
  final Color color;

  @override
  State<CountdownRing> createState() => _CountdownRingState();
}

class _CountdownRingState extends State<CountdownRing> {
  /// Timer, bukan animasi: animasi meminta frame terus-menerus sampai selesai,
  /// sehingga pumpAndSettle di test ikut menunggu seluruh durasi. Empat
  /// langkah per detik sudah halus untuk cincin 30 detik.
  static const Duration _step = Duration(milliseconds: 250);

  Timer? _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_step, (timer) {
      setState(() => _elapsed += _step);
      if (_elapsed >= widget.duration) timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining =
        1 - _elapsed.inMilliseconds / widget.duration.inMilliseconds;
    return MeasuringRing(color: widget.color, progress: remaining.clamp(0, 1));
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.color, this.progress});

  final Color color;
  final double? progress;

  static const double _stroke = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final circle = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.shortestSide / 2 - _stroke / 2 - 1,
    );
    Paint stroke(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;

    final value = progress;
    if (value == null) {
      canvas.drawArc(circle, 0, 2 * math.pi, false, stroke(color));
      return;
    }
    canvas.drawArc(
      circle,
      0,
      2 * math.pi,
      false,
      stroke(color.withValues(alpha: 0.15)),
    );
    if (value > 0) {
      canvas.drawArc(
        circle,
        -math.pi / 2,
        2 * math.pi * value,
        false,
        stroke(color),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.progress != progress;
}
