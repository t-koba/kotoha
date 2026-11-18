package org.kotoha.app

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Never let the system use this activity's screenshot as its Recents /
        // task-switcher representation. This suppresses the background snapshot
        // without blocking screenshots during active use; FLAG_SECURE below still
        // covers pause/resume on platforms without this API.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            setRecentsScreenshotEnabled(false)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!flutterEngine.plugins.has(TextImportPlugin::class.java)) {
            flutterEngine.plugins.add(TextImportPlugin())
        }
        if (!flutterEngine.plugins.has(ModelPackagePlugin::class.java)) {
            flutterEngine.plugins.add(ModelPackagePlugin())
        }
    }

    private var secureFlagCaptured = false
    private var secureFlagWasSet = false

    override fun onPause() {
        if (!secureFlagCaptured) {
            secureFlagWasSet =
                (window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0
            secureFlagCaptured = true
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        if (secureFlagCaptured && !secureFlagWasSet) {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        secureFlagCaptured = false
        secureFlagWasSet = false
    }
}
