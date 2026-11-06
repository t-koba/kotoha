package org.kotoha.app;

import android.test.ActivityInstrumentationTestCase2;
import android.view.WindowManager;

/**
 * Emulator callback/flag coverage, not proof of every launcher/OEM recents snapshot
 * or physical-device behavior. This does not inspect captured images or Flutter edits.
 */
@SuppressWarnings("deprecation") // Android SDK test APIs; no third-party test dependencies.
public final class MainActivityPrivacyTest extends ActivityInstrumentationTestCase2<MainActivity> {
    public MainActivityPrivacyTest() {
        super(MainActivity.class);
    }

    public void testSecureFlagTracksPauseResume() throws Throwable {
        MainActivity activity = getActivity();
        runTestOnUiThread(() -> {
            assertFalse("Foreground capture starts enabled", isSecure(activity));
            // Reuse the activity so each resume must also reset the captured flag state.
            for (boolean initiallySecure : new boolean[] {false, true, false}) {
                if (initiallySecure) {
                    activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
                } else {
                    activity.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_SECURE);
                }
                getInstrumentation().callActivityOnPause(activity);
                try {
                    assertTrue("Pause must secure the window", isSecure(activity));
                } finally {
                    getInstrumentation().callActivityOnResume(activity);
                }
                assertEquals("Resume must preserve the prior secure state",
                        initiallySecure, isSecure(activity));
            }
        });
    }

    private static boolean isSecure(MainActivity activity) {
        return (activity.getWindow().getAttributes().flags
                & WindowManager.LayoutParams.FLAG_SECURE) != 0;
    }
}
