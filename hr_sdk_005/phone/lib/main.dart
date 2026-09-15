import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hr_sdk_005_phone/dashboard_page.dart';
import 'package:hr_sdk_005_phone/edge_store.dart';
import 'package:hr_sdk_005_phone/watch_receiver.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Penerima dipasang sebelum layar dibangun, supaya kiriman dari jam yang
  // datang saat aplikasi baru dibuka langsung tertangani.
  final receiver = WatchReceiver()..attach();
  // Mulai mencari jam lewat BLE; izin Bluetooth diminta di sini bila perlu.
  unawaited(receiver.connect());
  runApp(EdgeApp(store: EdgeStore.instance, receiver: receiver));
}

/// Aplikasi HP (edge): menampung data dari jam Galaxy Watch4.
class EdgeApp extends StatelessWidget {
  const EdgeApp({super.key, required this.store, required this.receiver});

  final EdgeStore store;
  final WatchReceiver receiver;

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
