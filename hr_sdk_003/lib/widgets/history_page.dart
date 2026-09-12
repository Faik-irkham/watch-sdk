import 'package:flutter/material.dart';
import 'package:hr_sdk_003/measurement_shared.dart';
import 'package:hr_sdk_003/measurement_store.dart';

/// Satu baris di halaman riwayat, sudah dalam bentuk siap tampil.
class HistoryEntry {
  const HistoryEntry({required this.at, required this.value, this.detail});

  final DateTime at;
  final String value;
  final String? detail;
}

/// Daftar riwayat satu tabel SQLite, terbaru di atas.
///
/// Swipe-to-dismiss sistem dimatikan di tema Android, jadi halaman ini
/// menirunya sendiri: geser ke kanan menutup halaman, sama seperti tombol
/// kembali.
class HistoryPage extends StatefulWidget {
  const HistoryPage({
    super.key,
    required this.title,
    required this.load,
    this.totalNoun = 'data',
  });

  final String title;
  final Future<History<HistoryEntry>> Function() load;

  /// Kata benda untuk jumlah total, misalnya "data" atau "sampel".
  final String totalNoun;

  static Future<void> open(
    BuildContext context, {
    required String title,
    required Future<History<HistoryEntry>> Function() load,
    String totalNoun = 'data',
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HistoryPage(title: title, load: load, totalNoun: totalNoun),
      ),
    );
  }

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late final Future<History<HistoryEntry>> _history = widget.load();

  void _closeOnSwipeRight(DragEndDetails details) {
    if ((details.primaryVelocity ?? 0) > 250) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        // Seluruh layar menerima geser, termasuk area kosong di sekitar teks.
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: _closeOnSwipeRight,
        child: FutureBuilder<History<HistoryEntry>>(
          future: _history,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _Centered(
                title: widget.title,
                text: 'Gagal membaca riwayat: ${snapshot.error}',
              );
            }
            final history = snapshot.data;
            if (history == null) {
              return _Centered(
                title: widget.title,
                child: const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            if (history.items.isEmpty) {
              return _Centered(title: widget.title, text: 'Belum ada data tersimpan');
            }
            return _HistoryList(
              title: widget.title,
              history: history,
              totalNoun: widget.totalNoun,
            );
          },
        ),
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({
    required this.title,
    required this.history,
    required this.totalNoun,
  });

  final String title;
  final History<HistoryEntry> history;
  final String totalNoun;

  @override
  Widget build(BuildContext context) {
    final shown = history.items.length;
    final summary = shown < history.total
        ? '${history.total} $totalNoun · $shown terbaru'
        : '${history.total} $totalNoun';

    return ListView.separated(
      // Bantalan lebar di atas dan bawah agar baris pertama dan terakhir tidak
      // terpotong lengkung layar bulat.
      // Atas lebih dalam agar judul dua baris menjauhi lengkung; bawah cukup
      // lega agar baris terakhir bisa digulir sampai ke tengah layar.
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 56),
      itemCount: shown + 1,
      separatorBuilder: (_, index) => index == 0
          ? const SizedBox(height: 10)
          : const Divider(height: 1, color: Colors.white12),
      itemBuilder: (context, index) {
        if (index == 0) return _Header(title: title, summary: summary);
        return _EntryRow(history.items[index - 1]);
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.summary});

  final String title;
  final String summary;

  @override
  Widget build(BuildContext context) {
    // Rata tengah: judul yang terbungkus dua baris tetap menjauhi lengkung layar.
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          summary,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: Colors.white54),
        ),
      ],
    );
  }
}

/// Waktu di atas, nilai di bawah dengan lebar penuh: di layar sesempit ini
/// kolom waktu di samping nilai memaksa nilai terbelah atau menempel.
class _EntryRow extends StatelessWidget {
  const _EntryRow(this.entry);

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final detail = entry.detail;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatHistoryTime(entry.at),
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white54,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            entry.value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          if (detail != null)
            Text(detail, style: const TextStyle(fontSize: 10, color: Colors.white54)),
        ],
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.title, this.text, this.child});

  final String title;
  final String? text;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    // Judul dua baris duduk paling atas, tempat lingkaran paling sempit.
    return WatchSafeContent(
      width: 132,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          child ??
              Text(
                text ?? '',
                textAlign: TextAlign.center,
                // Pesan galat dari SQLite bisa sangat panjang. Tiga baris cukup
                // untuk mengenali masalahnya, dan menjaga kolom tetap pendek
                // agar judul di atasnya tidak terdorong ke tepi lingkaran.
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.white60),
              ),
        ],
      ),
    );
  }
}

/// Jam lebih dulu karena paling sering dibaca; tanggal membedakan sesi.
String formatHistoryTime(DateTime at) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(at.hour)}:${two(at.minute)}:${two(at.second)} · '
      '${two(at.day)}/${two(at.month)}/${at.year}';
}
