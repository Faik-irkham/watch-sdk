import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_sdk_004/measurement_store.dart';
import 'package:hr_sdk_004/widgets/accelerometer_view.dart';
import 'package:hr_sdk_004/widgets/history_page.dart';
import 'package:hr_sdk_004/widgets/ppg_view.dart';

/// Galaxy Watch4 SM-R860: 396×396 piksel fisik. Rasio 2,0 disimpulkan dari
/// screenshot perangkat (tombol setinggi 40 dp tampil 80 piksel), jadi layar
/// logisnya 198×198 dp.
const watchPhysicalSize = Size(396, 396);
const watchPixelRatio = 2.0;

/// Skala huruf bawaan dan dua tingkat lebih besar, untuk pengguna yang
/// memperbesar ukuran huruf di jam.
const watchTextScales = [1.0, 1.15, 1.3];

/// Pesan terpanjang yang dapat dikirim lapisan Android ke layar
/// (TrackerStreamHandler, SDK_POLICY_ERROR).
const longestSensorError =
    'Paket aplikasi belum terdaftar di program partner Samsung Health Sensor SDK';

/// Memuat Roboto dan Material Icons dari cache SDK Flutter, supaya lebar teks
/// di test sama dengan di jam. Tanpa ini Flutter memakai fon uji yang setiap
/// hurufnya selebar 1 em, hampir dua kali lebar angka Roboto, sehingga
/// pemeriksaan lingkaran menghasilkan alarm palsu.
Future<void> loadWatchFonts() async {
  // flutter_tester ada di <sdk>/bin/cache/artifacts/engine/<platform>/, dan
  // fonnya di <sdk>/bin/cache/artifacts/material_fonts/.
  var dir = File(Platform.resolvedExecutable).parent;
  Directory? fonts;
  for (var i = 0; i < 6 && fonts == null; i++, dir = dir.parent) {
    final candidate = Directory('${dir.path}/material_fonts');
    if (candidate.existsSync()) fonts = candidate;
  }
  if (fonts == null) {
    throw StateError('material_fonts tidak ditemukan dari ${Platform.resolvedExecutable}');
  }
  Future<ByteData> read(String name) async =>
      ByteData.view(File('${fonts!.path}/$name').readAsBytesSync().buffer);

  final roboto = FontLoader('Roboto');
  for (final weight in ['Regular', 'Medium', 'Bold']) {
    roboto.addFont(read('Roboto-$weight.ttf'));
  }
  await roboto.load();
  await (FontLoader('MaterialIcons')..addFont(read('MaterialIcons-Regular.otf'))).load();
}

void useWatchScreen(WidgetTester tester, {double textScale = 1.0}) {
  tester.view.physicalSize = watchPhysicalSize;
  tester.view.devicePixelRatio = watchPixelRatio;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

enum SensorPage {
  heartRate(0, 'samsung_health/heart_rate'),
  spo2(1, 'samsung_health/spo2'),
  accelerometer(2, 'samsung_health/accelerometer'),
  ppg(3, 'samsung_health/ppg');

  const SensorPage(this.pageIndex, this.channel);

  final int pageIndex;
  final String channel;
}

/// Galat yang dikirim sensor palsu, seolah datang dari lapisan Android.
class SensorError {
  const SensorError(this.message);

  final String message;
}

/// Satu keadaan layar: halaman mana, dan kejadian apa yang dikirim sensor
/// setelah tombol Mulai ditekan. Tanpa kejadian berarti halaman dibiarkan diam.
class Scenario {
  const Scenario(this.name, this.page, [this.events = const []]);

  final String name;
  final SensorPage page;
  final List<Object> events;
}

Map<String, Object?> _heartRate() => {
      'event': 'data',
      'heartRate': 220,
      'heartRateStatus': 1,
      'ibi': [1186, 712],
      'ibiStatus': [0, 0],
      'timestamp': 0,
    };

Map<String, Object?> _spo2({required int status, int value = 100}) => {
      'event': 'data',
      'spo2': value,
      'spo2Status': status,
      'heartRate': 220,
      'accuracyFlag': 0,
      'timestamp': 0,
    };

/// Nilai mentah terlebar: rumus konversi resmi (16383,75 / 4) menyiratkan
/// rentang sekitar ±16384.
Map<String, Object?> _accelerometer() => {
      'event': 'data',
      'samples': [
        for (var i = 0; i < 25; i++)
          {'x': -16384, 'y': -16384, 'z': -16384, 'timestamp': i * 40},
      ],
    };

/// Rentang ADC PPG tidak didokumentasikan; delapan digit (batas 24 bit) dipakai
/// agar tata letak aman untuk nilai besar.
Map<String, Object?> _ppg({int status = 0}) => {
      'event': 'data',
      'samples': [
        for (var i = 0; i < 25; i++)
          {
            'green': 16777215 - i * 3000,
            'greenStatus': status,
            'ir': 16777215,
            'irStatus': status,
            'red': 16777215,
            'redStatus': status,
            'timestamp': i * 40,
          },
      ],
    };

/// Setiap halaman dalam keadaan diam, sedang mengukur dengan nilai terlebar,
/// dan keadaan terpadat: nilai, keterangan "Gagal menyimpan", lalu galat
/// terpanjang. Penyimpanan memang gagal di test karena sqflite tidak aktif,
/// sehingga keterangan itu ikut muncul.
final pageScenarios = [
  const Scenario('detak jantung · diam', SensorPage.heartRate),
  Scenario('detak jantung · mengukur', SensorPage.heartRate, [_heartRate()]),
  Scenario('detak jantung · galat', SensorPage.heartRate, [
    _heartRate(),
    const SensorError(longestSensorError),
  ]),
  const Scenario('SpO2 · diam', SensorPage.spo2),
  Scenario('SpO2 · terganggu', SensorPage.spo2, [_spo2(status: -5, value: 0)]),
  Scenario('SpO2 · galat', SensorPage.spo2, [
    _spo2(status: 2),
    const SensorError(longestSensorError),
  ]),
  const Scenario('akselerometer · diam', SensorPage.accelerometer),
  Scenario('akselerometer · mengukur', SensorPage.accelerometer, [_accelerometer()]),
  Scenario('akselerometer · galat', SensorPage.accelerometer, [
    _accelerometer(),
    const SensorError(longestSensorError),
  ]),
  const Scenario('PPG · diam', SensorPage.ppg),
  Scenario('PPG · mengukur', SensorPage.ppg, [_ppg()]),
  Scenario('PPG · prioritas', SensorPage.ppg, [_ppg(status: -1)]),
  Scenario('PPG · galat', SensorPage.ppg, [
    _ppg(),
    const SensorError(longestSensorError),
  ]),
];

List<HistoryEntry> _entries(String value, [String? detail]) => [
      for (var i = 0; i < 12; i++)
        HistoryEntry(
          at: DateTime(2026, 12, 31, 23, 59, 59 - i),
          value: value,
          detail: detail,
        ),
    ];

final historyScenarios = <String, (String, String, History<HistoryEntry>)>{
  'riwayat detak jantung': (
    'Riwayat detak jantung',
    'data',
    History(_entries('220 bpm'), 90000),
  ),
  'riwayat SpO2': ('Riwayat SpO₂', 'data', History(_entries('100%', '220 bpm'), 9000)),
  'riwayat akselerometer': (
    'Riwayat akselerometer',
    'sampel',
    History(
      // Format yang sama persis dengan halaman akselerometer.
      _entries(
        formatAccelerometerMeans(AccelerometerSecond(
          second: DateTime(2026),
          samples: 25,
          meanX: -16384,
          meanY: -16384,
          meanZ: -16384,
        )),
        'rata-rata 25 sampel, nilai mentah',
      ),
      2250000,
    ),
  ),
  'riwayat PPG': (
    'Riwayat PPG',
    'sampel',
    History(
      _entries(
        formatPpgMeans(PpgSecond(
          second: DateTime(2026),
          samples: 25,
          meanGreen: 16777215,
          meanIr: 16777215,
          meanRed: 16777215,
        )),
        'rata-rata 25 sampel, ADC mentah',
      ),
      2250000,
    ),
  ),
  'riwayat kosong': ('Riwayat akselerometer', 'sampel', const History([], 0)),
};

Widget historyApp(String title, String noun, History<HistoryEntry> history) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: Colors.black),
    home: HistoryPage(title: title, totalNoun: noun, load: () async => history),
  );
}

/// Halaman riwayat yang gagal membaca SQLite, dengan pesan galat sepanjang
/// yang dilaporkan sqflite saat pabrik basis datanya belum siap.
Widget historyErrorApp() {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: Colors.black),
    home: HistoryPage(
      title: 'Riwayat detak jantung',
      load: () async => throw StateError(
        'databaseFactory not initialized. databaseFactory is only initialized '
        'when using sqflite. When using sqflite_common_ffi you must call '
        'databaseFactory = databaseFactoryFfi before using global openDatabase API',
      ),
    ),
  );
}

const _methods = MethodChannel('samsung_health/method');

/// Menampilkan [app], menggeser ke halaman [scenario], lalu bila ada kejadian,
/// menekan Mulai dan mengalirkan kejadian itu dari sensor palsu.
Future<void> showScenario(WidgetTester tester, Widget app, Scenario scenario) async {
  final messenger = tester.binding.defaultBinaryMessenger;
  final channel = EventChannel(scenario.page.channel);
  messenger.setMockMethodCallHandler(_methods, (call) async {
    return switch (call.method) {
      'hasPermission' || 'requestPermission' => true,
      _ => null,
    };
  });
  messenger.setMockStreamHandler(
    channel,
    MockStreamHandler.inline(
      onListen: (_, sink) {
        for (final event in scenario.events) {
          if (event is SensorError) {
            sink.error(code: 'TEST', message: event.message);
          } else {
            sink.success(event);
          }
        }
      },
    ),
  );
  addTearDown(() {
    messenger.setMockMethodCallHandler(_methods, null);
    messenger.setMockStreamHandler(channel, null);
  });

  await tester.pumpWidget(app);
  if (scenario.page.pageIndex > 0) {
    // Lompat langsung: fling yang lebih jauh dari lebar layar 198 dp bisa
    // melewati dua halaman sekaligus dan diam-diam menguji halaman yang salah.
    tester
        .widget<PageView>(find.byType(PageView))
        .controller!
        .jumpToPage(scenario.page.pageIndex);
    await tester.pumpAndSettle();
  }
  if (scenario.events.isNotEmpty) {
    await tester.tap(find.widgetWithText(FilledButton, 'Mulai').hitTestable());
    await tester.pumpAndSettle();
  }
}

/// Memastikan setiap teks, ikon, dan tombol yang tampil berada di dalam
/// lingkaran layar, bukan sekadar di dalam kotak 198×198. Sudut kotak tiap
/// elemen diuji terhadap jari-jari layar dengan toleransi kecil, karena kotak
/// teks sedikit lebih besar dari hurufnya.
void expectInsideRoundScreen(WidgetTester tester, {Finder? only, double tolerance = 2}) {
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  final center = screen.center(Offset.zero);
  final radius = screen.shortestSide / 2 + tolerance;
  final offenders = <String>[];

  void check(Finder finder, String Function(Widget) describe) {
    for (final element in finder.evaluate()) {
      final box = element.renderObject;
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      // Transformasi penuh ke layar, termasuk pengecilan oleh FittedBox;
      // localToGlobal + ukuran lokal akan membesar-besarkan kotak yang diperkecil.
      final rect = MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
      if (!rect.overlaps(Offset.zero & screen)) continue;
      final worst = [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight]
          .map((corner) => (corner - center).distance)
          .reduce((a, b) => a > b ? a : b);
      if (worst > radius) {
        String n(double v) => v.toStringAsFixed(0);
        offenders.add('${describe(element.widget)} menjorok '
            '${(worst - radius + tolerance).toStringAsFixed(1)} dp keluar lingkaran '
            '[kotak x ${n(rect.left)}–${n(rect.right)}, y ${n(rect.top)}–${n(rect.bottom)}]');
      }
    }
  }

  if (only != null) {
    check(only, (w) => w is Text ? '"${w.data}"' : w.runtimeType.toString());
  } else {
    check(find.byType(Text), (w) => '"${(w as Text).data ?? w.textSpan?.toPlainText()}"');
    check(find.byType(Icon), (w) => 'ikon ${(w as Icon).icon?.codePoint}');
    check(find.byType(FilledButton), (_) => 'tombol utama');
    check(find.byType(IconButton), (_) => 'tombol riwayat');
  }
  expect(offenders, isEmpty, reason: 'terpotong lengkung layar bulat');
}

/// Teks satu kata — angka atau label — tidak boleh terbelah ke baris
/// berikutnya: "Mera / h" atau "167052 / 15" sama buruknya dengan overflow,
/// padahal tidak terdeteksi sebagai overflow maupun keluar lingkaran.
void expectNoBrokenWords(WidgetTester tester) {
  final broken = <String>[];
  for (final element in find.byType(Text).evaluate()) {
    final text = (element.widget as Text).data;
    if (text == null || text.trim().isEmpty || text.contains(RegExp(r'\s'))) continue;
    final paragraph = element.renderObject;
    if (paragraph is! RenderParagraph || !paragraph.hasSize) continue;
    // Satu kotak per baris: jumlah posisi atas yang berbeda = jumlah baris.
    final lines = paragraph
        .getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: text.length))
        .map((box) => box.top.round())
        .toSet();
    if (lines.length > 1) broken.add('"$text"');
  }
  expect(broken, isEmpty, reason: 'kata atau angka terbelah ke baris berikutnya');
}
