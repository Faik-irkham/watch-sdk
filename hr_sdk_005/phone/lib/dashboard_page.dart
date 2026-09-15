import 'package:flutter/material.dart';
import 'package:hr_sdk_005_phone/edge_store.dart';
import 'package:hr_sdk_005_phone/watch_receiver.dart';

/// Layar utama HP (edge): sambungan BLE ke jam, nilai terbaru tiap sensor, dan
/// kiriman yang baru diterima. Diperbarui setiap ada kiriman masuk.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.store, required this.receiver});

  final EdgeStore store;
  final WatchReceiver receiver;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  EdgeSnapshot _snapshot = const EdgeSnapshot();
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.receiver.recent.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.receiver.recent.removeListener(_reload);
    super.dispose();
  }

  /// Memuat ulang data, dan menyambung ulang BLE bila sedang tidak berjalan.
  Future<void> _refresh() async {
    final phase = widget.receiver.link.value.phase;
    if (phase == LinkPhase.idle || phase == LinkPhase.error) {
      await widget.receiver.connect();
    }
    await _reload();
  }

  Future<void> _reload() async {
    try {
      final snapshot = await widget.store.snapshot();
      if (mounted) {
        setState(() {
          _snapshot = snapshot;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Gagal membaca data: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('HR 005 · Edge'),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ValueListenableBuilder<WatchLinkState>(
              valueListenable: widget.receiver.link,
              builder: (context, state, _) => _WatchCard(
                state: state,
                lastReceivedAt: _snapshot.lastReceivedAt,
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            for (final table in EdgeStore.columns.keys)
              _SensorCard(
                table: table,
                count: _snapshot.counts[table] ?? 0,
                latest: _snapshot.latest[table],
              ),
            const SizedBox(height: 16),
            Text('Kiriman terbaru', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            ValueListenableBuilder<List<ReceivedBatch>>(
              valueListenable: widget.receiver.recent,
              builder: (context, batches, _) => batches.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Belum ada kiriman sejak aplikasi dibuka'),
                    )
                  : Column(
                      children: [
                        for (final batch in batches) _BatchTile(batch),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WatchCard extends StatelessWidget {
  const _WatchCard({required this.state, required this.lastReceivedAt});

  final WatchLinkState state;
  final DateTime? lastReceivedAt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final received = lastReceivedAt;
    final name = state.name ?? 'jam';
    final message = state.message;
    final pending = state.pending;
    final (title, icon, color) = switch (state.phase) {
      LinkPhase.idle => (
        'Jam belum tersambung',
        Icons.bluetooth,
        scheme.surfaceContainerHighest,
      ),
      LinkPhase.scanning => (
        'Mencari jam…',
        Icons.bluetooth_searching,
        scheme.surfaceContainerHighest,
      ),
      LinkPhase.connecting => (
        'Menyambung ke $name…',
        Icons.bluetooth_searching,
        scheme.surfaceContainerHighest,
      ),
      LinkPhase.connected => (
        name,
        Icons.bluetooth_connected,
        scheme.primaryContainer,
      ),
      LinkPhase.disconnected => (
        'Jam terputus, mencari lagi…',
        Icons.bluetooth_searching,
        scheme.surfaceContainerHighest,
      ),
      LinkPhase.error => (
        'Galat BLE',
        Icons.bluetooth_disabled,
        scheme.errorContainer,
      ),
    };
    final lines = [
      if (state.phase == LinkPhase.error && message != null) message,
      if (state.phase == LinkPhase.connected)
        pending == null
            ? 'Tersambung lewat BLE'
            : 'Tersambung lewat BLE · antrean di jam: $pending',
      received == null
          ? 'Belum ada data diterima'
          : 'Terakhir menerima ${formatDateTime(received)}',
    ];
    return Card(
      color: color,
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(lines.join('\n')),
        isThreeLine: lines.length > 1,
      ),
    );
  }
}

class _SensorCard extends StatelessWidget {
  const _SensorCard({
    required this.table,
    required this.count,
    required this.latest,
  });

  final String table;
  final int count;
  final Map<String, Object?>? latest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = sensorStyle(table);
    final row = latest;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tableLabel(table), style: theme.textTheme.labelLarge),
                  const SizedBox(height: 2),
                  Text(
                    row == null ? '--' : describeLatest(table, row),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    row == null
                        ? 'Belum ada data'
                        : '$count ${countNoun(table)} · terakhir '
                              '${formatDateTime(DateTime.fromMillisecondsSinceEpoch(row['measured_at']! as int))}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BatchTile extends StatelessWidget {
  const _BatchTile(this.batch);

  final ReceivedBatch batch;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.download_done),
      title: Text('${tableLabel(batch.table)} · ${batch.rows} baris'),
      subtitle: Text('${batch.inserted} baru · ${formatClock(batch.at)}'),
    );
  }
}

String tableLabel(String table) => switch (table) {
  'heart_rate' => 'Detak jantung',
  'spo2' => 'SpO₂',
  'accelerometer' => 'Akselerometer',
  _ => table,
};

/// Kata benda untuk jumlah baris tiap tabel.
String countNoun(String table) => switch (table) {
  'heart_rate' => 'data',
  'spo2' => 'hasil',
  _ => 'sampel',
};

(IconData, Color) sensorStyle(String table) => switch (table) {
  'heart_rate' => (Icons.favorite, const Color(0xFFE53935)),
  'spo2' => (Icons.water_drop, const Color(0xFF039BE5)),
  _ => (Icons.open_with, const Color(0xFFF9A825)),
};

/// Nilai terbaru satu tabel dalam bentuk siap tampil.
String describeLatest(String table, Map<String, Object?> row) =>
    switch (table) {
      'heart_rate' => '${row['bpm']} bpm',
      'spo2' => '${row['spo2_percent']}%',
      _ => 'x ${row['x']} · y ${row['y']} · z ${row['z']}',
    };

String formatClock(DateTime at) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
}

String formatDateTime(DateTime at) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${formatClock(at)} · ${two(at.day)}/${two(at.month)}';
}
