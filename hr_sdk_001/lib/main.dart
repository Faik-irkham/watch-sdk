import 'package:flutter/material.dart';
import 'package:hr_sdk_001/heart_rate_page.dart';

void main() {
  runApp(const HeartRateApp());
}

class HeartRateApp extends StatelessWidget {
  const HeartRateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Heart Rate',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        // Layar jam berbentuk bulat dan hitam pekat menghemat daya OLED.
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.redAccent,
          brightness: Brightness.dark,
        ),
      ),
      home: const HeartRatePage(),
    );
  }
}
