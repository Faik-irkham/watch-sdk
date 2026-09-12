import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hr_sdk_004/main.dart';

void main() {
  testWidgets('starts on the heart rate page with a placeholder', (tester) async {
    await tester.pumpWidget(const SamsungHealthApp());

    expect(find.text('bpm'), findsOneWidget);
    expect(find.text('--'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Mulai'), findsOneWidget);
  });

  testWidgets('setiap halaman sensor punya tombol riwayat', (tester) async {
    await tester.pumpWidget(const SamsungHealthApp());

    for (var page = 0; page < 4; page++) {
      expect(find.byTooltip('Riwayat'), findsOneWidget, reason: 'halaman ke-$page');
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('swiping reveals the SpO2 page', (tester) async {
    await tester.pumpWidget(const SamsungHealthApp());

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text('SpO₂'), findsOneWidget);
    expect(find.text('bpm'), findsNothing);
  });

  testWidgets('third page shows the accelerometer axes', (tester) async {
    await tester.pumpWidget(const SamsungHealthApp());

    for (var i = 0; i < 2; i++) {
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
    }

    expect(find.text('X'), findsOneWidget);
    expect(find.text('Y'), findsOneWidget);
    expect(find.text('Z'), findsOneWidget);
    expect(find.text('Nilai mentah sensor, belum m/s²'), findsOneWidget);
  });

  testWidgets('fourth page shows the PPG channels', (tester) async {
    await tester.pumpWidget(const SamsungHealthApp());

    for (var i = 0; i < 3; i++) {
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
    }

    expect(find.text('Hijau'), findsOneWidget);
    expect(find.text('IR'), findsOneWidget);
    expect(find.text('Merah'), findsOneWidget);
    expect(find.text('Nilai ADC mentah LED'), findsOneWidget);
  });

  group('navigasi tanpa swipe-to-dismiss sistem', () {
    late List<String> platformCalls;

    setUp(() => platformCalls = []);

    Future<void> watchPlatform(WidgetTester tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          platformCalls.add(call.method);
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
    }

    Future<void> swipeLeft(WidgetTester tester) async {
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
    }

    testWidgets('geser kanan dari akselerometer kembali ke SpO2, tidak keluar',
        (tester) async {
      await watchPlatform(tester);
      await tester.pumpWidget(const SamsungHealthApp());
      await swipeLeft(tester);
      await swipeLeft(tester);
      expect(find.text('X'), findsOneWidget);

      await tester.fling(find.byType(PageView), const Offset(400, 0), 1000);
      await tester.pumpAndSettle();

      expect(find.text('SpO₂'), findsOneWidget);
      expect(platformCalls, isNot(contains('SystemNavigator.pop')));
    });

    testWidgets('tombol kembali di akselerometer mundur ke SpO2, tidak keluar',
        (tester) async {
      await watchPlatform(tester);
      await tester.pumpWidget(const SamsungHealthApp());
      await swipeLeft(tester);
      await swipeLeft(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('SpO₂'), findsOneWidget);
      expect(platformCalls, isNot(contains('SystemNavigator.pop')));
    });

    testWidgets('tombol kembali di halaman pertama menutup aplikasi', (tester) async {
      await watchPlatform(tester);
      await tester.pumpWidget(const SamsungHealthApp());

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(platformCalls, contains('SystemNavigator.pop'));
    });

    testWidgets('geser kanan di halaman pertama menutup aplikasi', (tester) async {
      await watchPlatform(tester);
      await tester.pumpWidget(const SamsungHealthApp());

      await tester.drag(find.byType(PageView), const Offset(400, 0));
      await tester.pumpAndSettle();

      expect(platformCalls, contains('SystemNavigator.pop'));
    });

    testWidgets('geseran kecil di halaman pertama tidak menutup aplikasi',
        (tester) async {
      await watchPlatform(tester);
      await tester.pumpWidget(const SamsungHealthApp());

      await tester.drag(find.byType(PageView), const Offset(80, 0));
      await tester.pumpAndSettle();

      expect(platformCalls, isNot(contains('SystemNavigator.pop')));
      expect(find.text('bpm'), findsOneWidget);
    });
  });
}
