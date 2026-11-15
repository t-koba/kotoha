package org.kotoha.app;

import android.app.UiAutomation;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.test.ActivityInstrumentationTestCase2;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewGroupOverlay;
import android.view.WindowManager;

/**
 * Emulator callback/flag and in-memory screenshot coverage using synthetic content.
 * This does not test app-switcher thumbnails or physical-device behavior.
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

    public void testSecureFlagSuppressesScreenshotUntilResume() throws Throwable {
        MainActivity activity = getActivity();
        UiAutomation automation = getInstrumentation().getUiAutomation();
        assertNotNull("Screenshot automation must be available", automation);

        View decor = activity.getWindow().getDecorView();
        ViewGroupOverlay overlay = ((ViewGroup) decor).getOverlay();
        ColorDrawable marker = new ColorDrawable(Color.MAGENTA);
        int size = Math.round(48 * activity.getResources().getDisplayMetrics().density);
        int[] center = {-1, -1};
        boolean[] paused = {false};
        boolean[] markerAdded = {false};
        try {
            runTestOnUiThread(() -> {
                assertFalse("Foreground capture starts enabled", isSecure(activity));
                assertTrue("Activity decor must be laid out",
                        decor.getWidth() > 0 && decor.getHeight() > 0);
                int left = (decor.getWidth() - size) / 2;
                int top = (decor.getHeight() - size) / 2;
                int[] decorLocation = new int[2];
                decor.getLocationOnScreen(decorLocation);
                marker.setBounds(left, top, left + size, top + size);
                // Draw in the window's topmost view overlay, above Flutter's rendering surface.
                overlay.add(marker);
                markerAdded[0] = true;
                decor.invalidate();
                center[0] = decorLocation[0] + left + size / 2;
                center[1] = decorLocation[1] + top + size / 2;
            });
            getInstrumentation().waitForIdleSync();
            assertMarkerScreenshot(automation, center, true);

            runTestOnUiThread(() -> {
                paused[0] = true;
                getInstrumentation().callActivityOnPause(activity);
                assertTrue("Pause must secure the window", isSecure(activity));
            });
            getInstrumentation().waitForIdleSync();
            // Direct callback invocation leaves the app on screen; this is not recents UI.
            assertMarkerScreenshot(automation, center, false);

            runTestOnUiThread(() -> {
                getInstrumentation().callActivityOnResume(activity);
                paused[0] = false;
                assertFalse("Resume must restore foreground capture", isSecure(activity));
            });
            getInstrumentation().waitForIdleSync();
            assertMarkerScreenshot(automation, center, true);
        } finally {
            runTestOnUiThread(() -> {
                try {
                    if (paused[0]) getInstrumentation().callActivityOnResume(activity);
                } finally {
                    if (markerAdded[0]) {
                        overlay.remove(marker);
                        decor.invalidate();
                    }
                }
            });
        }
    }

    private void assertMarkerScreenshot(UiAutomation automation, int[] center,
            boolean expectVisible) {
        Bitmap screenshot = automation.takeScreenshot();
        assertNotNull("Screenshot capture must succeed", screenshot);
        try {
            assertTrue("Marker center must be inside the screenshot",
                    center[0] >= 0 && center[1] >= 0
                            && center[0] < screenshot.getWidth()
                            && center[1] < screenshot.getHeight());
            int pixel = screenshot.getPixel(center[0], center[1]);
            if (expectVisible) {
                assertEquals("Unsecured screenshot must show the synthetic marker",
                        Color.MAGENTA, pixel);
            } else {
                assertFalse("Secure screenshot must suppress the synthetic marker",
                        Color.MAGENTA == pixel);
            }
        } finally {
            // Keep captured pixels in memory only; never persist or log the image.
            screenshot.recycle();
        }
    }

    private static boolean isSecure(MainActivity activity) {
        return (activity.getWindow().getAttributes().flags
                & WindowManager.LayoutParams.FLAG_SECURE) != 0;
    }
}
