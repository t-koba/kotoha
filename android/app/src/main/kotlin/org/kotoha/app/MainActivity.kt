package org.kotoha.app

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
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
