import 'package:flutter/material.dart';
import 'package:hr_sdk_003/sensor_page.dart';

void main() {
  runApp(const SamsungHealthApp());
}

class SamsungHealthApp extends StatelessWidget {
  const SamsungHealthApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sensor Jam',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        // Layar jam bulat dan hitam pekat menghemat daya OLED.
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.redAccent,
          brightness: Brightness.dark,
        ),
      ),
      home: const SensorPages(),
    );
  }
}
