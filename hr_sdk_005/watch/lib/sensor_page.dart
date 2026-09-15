import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hr_sdk_005_watch/measurement_shared.dart';
import 'package:hr_sdk_005_watch/phone_sync.dart';
import 'package:hr_sdk_005_watch/widgets/accelerometer_view.dart';
import 'package:hr_sdk_005_watch/widgets/heart_rate_view.dart';
import 'package:hr_sdk_005_watch/widgets/interval_view.dart';
import 'package:hr_sdk_005_watch/widgets/ppg_view.dart';
import 'package:hr_sdk_005_watch/widgets/spo2_view.dart';
import 'package:hr_sdk_005_watch/widgets/sync_view.dart';

class SensorPages extends StatefulWidget {
  const SensorPages({super.key});

  @override
  State<SensorPages> createState() => _SensorPagesState();
}

class _SensorPagesState extends State<SensorPages> {
  static const List<Widget> _pages = [
    HeartRateView(),
    Spo2View(),
    AccelerometerView(),
    PpgView(),
    IntervalView(),
    SyncView(),
  ];

  /// Warna titik aktif mengikuti sensor halaman yang sedang tampil.
  static const List<Color> _accents = [
    SensorColors.heartRate,
    SensorColors.spo2,
    SensorColors.accelerometer,
    SensorColors.ppg,
    SensorColors.interval,
    SensorColors.phone,
  ];

  /// Porsi lebar layar yang harus ditarik ke kanan di halaman pertama sebelum
  /// dianggap sebagai niat menutup aplikasi.
  static const double _exitPullFraction = 0.25;

  final PageController _controller = PageController();
  int _page = 0;
  double _exitPull = 0;

  @override
  void initState() {
    super.initState();
    // Selama aplikasi terbuka, data yang belum diterima HP dikirim berkala.
    PhoneSync.instance.start();
  }

  @override
  void dispose() {
    PhoneSync.instance.stop();
    _controller.dispose();
    super.dispose();
  }

  void _goToPreviousPage() {
    _controller.previousPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// Swipe-to-dismiss bawaan Wear OS dimatikan di tema Android karena merebut
  /// geser kanan dari PageView. Di sini perilakunya ditiru: tarikan ke kanan
  /// yang melewati tepi halaman pertama menutup aplikasi.
  bool _handleScroll(ScrollNotification notification) {
    if (notification is OverscrollNotification &&
        notification.dragDetails != null &&
        notification.overscroll < 0) {
      _exitPull -= notification.overscroll;
      if (_exitPull >
          notification.metrics.viewportDimension * _exitPullFraction) {
        _exitPull = 0;
        SystemNavigator.pop();
      }
    } else if (notification is ScrollStartNotification ||
        notification is ScrollEndNotification) {
      _exitPull = 0;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Tombol kembali mundur satu halaman; baru di halaman pertama aplikasi
      // ditutup.
      canPop: _page == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goToPreviousPage();
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: _handleScroll,
                child: PageView(
                  controller: _controller,
                  onPageChanged: (page) => setState(() => _page = page),
                  children: _pages,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(_pages.length, (index) {
                    final active = index == _page;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: active ? 14 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2.5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: active ? _accents[index] : Colors.white24,
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
