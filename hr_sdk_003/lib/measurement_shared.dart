import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hr_sdk_003/measurement_store.dart';

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

/// Tata letak yang dipakai halaman detak jantung dan SpO2.
class MeasurementLayout extends StatelessWidget {
  const MeasurementLayout({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.unit,
    required this.message,
    required this.buttonLabel,
    required this.onPressed,
    this.footnote,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String unit;
  final String message;
  final String buttonLabel;
  final VoidCallback onPressed;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: iconColor, size: 22),
                const SizedBox(width: 8),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w600,
                    height: 1,
                  ),
                ),
              ],
            ),
            Text(unit, style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.white60),
            ),
            if (footnote != null) Footnote(footnote!),
            const SizedBox(height: 10),
            FilledButton(onPressed: onPressed, child: Text(buttonLabel)),
          ],
        ),
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
