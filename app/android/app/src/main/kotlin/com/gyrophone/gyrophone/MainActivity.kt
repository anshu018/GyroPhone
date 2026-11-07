package com.gyrophone.gyrophone

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var hidPlugin: HidPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        hidPlugin = HidPlugin(this, flutterEngine.dartExecutor.binaryMessenger)
            .apply { setActivity(this@MainActivity) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        hidPlugin?.dispose()
        hidPlugin = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        hidPlugin?.onRequestPermissionsResult(requestCode, grantResults)
    }
}
