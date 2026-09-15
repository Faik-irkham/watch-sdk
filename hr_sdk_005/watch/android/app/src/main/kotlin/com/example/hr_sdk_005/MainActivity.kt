package com.example.hr_sdk_005

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var bridge: SamsungHealthBridge? = null
    private var bleServer: BleServer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bridge = SamsungHealthBridge(this, flutterEngine.dartExecutor.binaryMessenger)
            .also { it.attach() }
        bleServer = BleServer(this, flutterEngine.dartExecutor.binaryMessenger)
            .also { it.attach() }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (bridge?.onRequestPermissionsResult(requestCode, grantResults) == true) return
        if (bleServer?.onRequestPermissionsResult(requestCode, grantResults) == true) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        bridge?.detach()
        bridge = null
        bleServer?.detach()
        bleServer = null
        super.onDestroy()
    }
}
