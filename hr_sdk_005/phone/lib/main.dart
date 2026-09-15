import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hr_sdk_005_phone/ble_receiver.dart';
import 'package:hr_sdk_005_phone/dashboard_page.dart';
import 'package:hr_sdk_005_phone/edge_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final receiver = BleReceiver.instance;
  // Mulai mencari jam lewat BLE; izin Bluetooth diminta di sini bila perlu.
  unawaited(receiver.start());
  runApp(EdgeApp(store: EdgeStore.instance, receiver: receiver));
}

/// Aplikasi HP (edge): menampung data dari jam Galaxy Watch4.
class EdgeApp extends StatelessWidget {
  const EdgeApp({super.key, required this.store, required this.receiver});

  final EdgeStore store;
  final BleReceiver receiver;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HR 005 Edge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
      ),
      home: DashboardPage(store: store, receiver: receiver),
    );
  }
}
