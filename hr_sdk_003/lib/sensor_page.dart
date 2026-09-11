import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hr_sdk_003/widgets/accelerometer_view.dart';
import 'package:hr_sdk_003/widgets/heart_rate_view.dart';
import 'package:hr_sdk_003/widgets/spo2_view.dart';

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
  ];

  /// Porsi lebar layar yang harus ditarik ke kanan di halaman pertama sebelum
  /// dianggap sebagai niat menutup aplikasi.
  static const double _exitPullFraction = 0.25;

  final PageController _controller = PageController();
  int _page = 0;
  double _exitPull = 0;

  @override
  void dispose() {
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
      if (_exitPull > notification.metrics.viewportDimension * _exitPullFraction) {
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
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(_pages.length, (index) {
                    return Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: index == _page ? Colors.white70 : Colors.white24,
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
