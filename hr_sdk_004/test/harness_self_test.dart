import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'watch_harness.dart';

/// Kontrol negatif: pemeriksa yang tidak pernah gagal tidak membuktikan apa-apa.
void main() {
  Future<void> pumpWord(WidgetTester tester, double width) {
    return tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: width,
            child: const Text('Merah', style: TextStyle(fontSize: 16)),
          ),
        ),
      ),
    );
  }

  testWidgets('kata yang terbelah ke baris berikutnya tertangkap', (tester) async {
    await pumpWord(tester, 24);
    expect(() => expectNoBrokenWords(tester), throwsA(isA<TestFailure>()));
  });

  testWidgets('kata yang muat dalam satu baris tidak dianggap terbelah', (tester) async {
    await pumpWord(tester, 200);
    expectNoBrokenWords(tester);
  });
}
