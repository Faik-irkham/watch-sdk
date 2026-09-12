import 'package:flutter_test/flutter_test.dart';
import 'package:hr_sdk_004/measurement_store.dart';
import 'package:hr_sdk_004/samsung_health_service.dart';
import 'package:hr_sdk_004/widgets/ppg_view.dart';

PpgSample sample({int? green = 100, int? greenStatus = 0, int? ir, int? irStatus}) =>
    PpgSample(
      green: green,
      greenStatus: greenStatus,
      ir: ir,
      irStatus: irStatus,
      timestamp: DateTime(2026),
    );

void main() {
  test('sampel absah hanya bila semua warna yang terbaca berstatus normal', () {
    expect(sample().isValid, isTrue);
    expect(sample(ir: 200, irStatus: 0).isValid, isTrue);
    expect(sample(ir: 200, irStatus: -1).isValid, isFalse);
    expect(sample(greenStatus: -1).isValid, isFalse);
    // Tanpa satu warna pun yang terbaca, tidak ada yang layak disimpan.
    expect(sample(green: null, greenStatus: null).isValid, isFalse);
  });

  test('status -1 ditandai sebagai didahului sensor yang lebih prioritas', () {
    expect(sample(greenStatus: -1).isPreempted, isTrue);
    expect(sample().isPreempted, isFalse);
  });

  test('kiriman dari Android: warna yang tidak dilacak dibaca sebagai null', () {
    final batch = PpgBatch.fromMap({
      'samples': [
        for (var i = 0; i < 26; i++)
          {
            'green': 1000 + i,
            'greenStatus': 0,
            'ir': null,
            'irStatus': null,
            'red': null,
            'redStatus': null,
            'timestamp': i * 40,
          },
      ],
    });

    expect(batch.samples, hasLength(26));
    expect(batch.latest!.green, 1025);
    expect(batch.latest!.ir, isNull);
    expect(batch.validSamples, hasLength(26));
    expect(batch.rateHz, closeTo(25, 0.001));
  });

  test('format riwayat melewati warna yang tidak dilacak', () {
    final means = formatPpgMeans(PpgSecond(
      second: DateTime(2026),
      samples: 25,
      meanGreen: 123.4,
      meanRed: 456.6,
    ));

    expect(means, 'hijau 123 · merah 457');
  });
}
