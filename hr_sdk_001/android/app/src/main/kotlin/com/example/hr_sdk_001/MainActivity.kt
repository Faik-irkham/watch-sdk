package com.example.hr_sdk_001

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var heartRateBridge: HeartRateBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        heartRateBridge = HeartRateBridge(this, flutterEngine.dartExecutor.binaryMessenger)
            .also { it.attach() }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (heartRateBridge?.onRequestPermissionsResult(requestCode, grantResults) == true) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        heartRateBridge?.detach()
        heartRateBridge = null
        super.onDestroy()
    }
}
