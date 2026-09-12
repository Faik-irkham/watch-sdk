// Sementara: pemeriksaan visual halaman PPG; hanya jalan bila CAPTURE_DIR diisi.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_sdk_004/main.dart';

import 'watch_harness.dart';

void main() {
  final dir = Platform.environment['CAPTURE_DIR'];

  testWidgets('lembar PPG', skip: dir == null, (tester) async {
    await tester.runAsync(loadWatchFonts);
    final shots = <(String, ui.Image)>[];
    final key = GlobalKey();

    Future<void> capture(String name) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
      final image = await tester.runAsync(() => boundary.toImage(pixelRatio: watchPixelRatio));
      shots.add((name, image!));
    }

    for (final scale in [1.0, 1.3]) {
      useWatchScreen(tester, textScale: scale);
      for (final s in pageScenarios.where((s) => s.page == SensorPage.ppg)) {
        await showScenario(
          tester,
          RepaintBoundary(key: key, child: KeyedSubtree(key: UniqueKey(), child: const SamsungHealthApp())),
          s,
        );
        await capture('${s.name} · $scale');
      }
      final (title, noun, history) = historyScenarios['riwayat PPG']!;
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: KeyedSubtree(key: UniqueKey(), child: historyApp(title, noun, history)),
      ));
      await tester.pumpAndSettle();
      await capture('riwayat PPG · $scale');
    }

    await tester.runAsync(() async {
      const cols = 5, tile = 396.0, caption = 30.0, gap = 14.0;
      final rows = (shots.length / cols).ceil();
      final width = gap + cols * (tile + gap);
      final height = gap + rows * (tile + caption + gap);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = const Color(0xFF30363A));
      for (var i = 0; i < shots.length; i++) {
        final (name, image) = shots[i];
        final origin = Offset(gap + (i % cols) * (tile + gap), gap + (i ~/ cols) * (tile + caption + gap));
        final square = origin & const Size(tile, tile);
        canvas.drawImage(image, origin, Paint());
        canvas.drawPath(
          Path()
            ..fillType = PathFillType.evenOdd
            ..addRect(square)
            ..addOval(square),
          Paint()..color = const Color(0x88FF2D2D),
        );
        final builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontFamily: 'Roboto', fontSize: 19))
          ..pushStyle(ui.TextStyle(color: const Color(0xFFFFFFFF)))
          ..addText(name);
        canvas.drawParagraph(
          builder.build()..layout(const ui.ParagraphConstraints(width: tile)),
          origin + const Offset(4, tile + 4),
        );
      }
      final sheet = await recorder.endRecording().toImage(width.toInt(), height.toInt());
      final png = await sheet.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/lembar_ppg.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  });
}
