import 'package:flutter/material.dart';
import 'package:hr_sdk_004/measurement_shared.dart';
import 'package:hr_sdk_004/measurement_store.dart';

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
    this.accent = Colors.white,
  });

  final String title;
  final Future<History<HistoryEntry>> Function() load;

  /// Kata benda untuk jumlah total, misalnya "data" atau "sampel".
  final String totalNoun;

  /// Warna sensor asal riwayat, untuk judul.
  final Color accent;

  static Future<void> open(
    BuildContext context, {
    required String title,
    required Future<History<HistoryEntry>> Function() load,
    String totalNoun = 'data',
    Color accent = Colors.white,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HistoryPage(
          title: title,
          load: load,
          totalNoun: totalNoun,
          accent: accent,
        ),
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
                accent: widget.accent,
                text: 'Gagal membaca riwayat: ${snapshot.error}',
              );
            }
            final history = snapshot.data;
            if (history == null) {
              return _Centered(
                title: widget.title,
                accent: widget.accent,
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: widget.accent,
                  ),
                ),
              );
            }
            if (history.items.isEmpty) {
              return _Centered(
                title: widget.title,
                accent: widget.accent,
                text: 'Belum ada data tersimpan',
              );
            }
            return _HistoryList(
              title: widget.title,
              accent: widget.accent,
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
    required this.accent,
    required this.history,
    required this.totalNoun,
  });

  final String title;
  final Color accent;
  final History<HistoryEntry> history;
  final String totalNoun;

  @override
  Widget build(BuildContext context) {
    final shown = history.items.length;
    final summary = shown < history.total
        ? '${history.total} $totalNoun · $shown terbaru'
        : '${history.total} $totalNoun';

    return ListView.builder(
      // Atas lebih dalam agar judul dua baris menjauhi lengkung; bawah cukup
      // lega agar kartu terakhir bisa digulir sampai ke tengah layar.
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 56),
      itemCount: shown + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _Header(title: title, summary: summary, accent: accent),
          );
        }
        return _EntryCard(history.items[index - 1]);
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.summary,
    required this.accent,
  });

  final String title;
  final String summary;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    // Rata tengah: judul yang terbungkus dua baris tetap menjauhi lengkung layar.
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: accent,
          ),
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

/// Satu kartu per baris, rata tengah: di layar bulat, teks di tengah kartu
/// paling lama terhindar dari lengkung saat digulir ke atas dan bawah.
class _EntryCard extends StatelessWidget {
  const _EntryCard(this.entry);

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final detail = entry.detail;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Text(
            formatHistoryTime(entry.at),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white54,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 1),
          Text(
            entry.value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          if (detail != null)
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: Colors.white54),
            ),
        ],
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({
    required this.title,
    required this.accent,
    this.text,
    this.child,
  });

  final String title;
  final Color accent;
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
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
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
