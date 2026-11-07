package org.kotoha.app;

import android.accessibilityservice.AccessibilityServiceInfo;
import android.app.UiAutomation;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.os.Bundle;
import android.os.SystemClock;
import android.test.ActivityInstrumentationTestCase2;
import android.test.InstrumentationTestRunner;
import android.view.KeyEvent;
import android.view.View;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityWindowInfo;
import java.util.List;
import java.util.function.Predicate;
import java.util.stream.Collectors;
import junit.framework.AssertionFailedError;

/**
 * Native accessibility bridge and synthesized keyboard input on the pinned emulator only.
 * No TalkBack speech/gestures, physical keyboard/device, or OS thumbnail claims.
 * Widget tests own bidi direction/caret policy and the complete Flutter traversal order.
 */
@SuppressWarnings("deprecation") // SDK instrumentation only; no third-party dependencies.
public final class MainActivityAccessibilityTest
        extends ActivityInstrumentationTestCase2<MainActivity> {
    private UiAutomation automation;
    private ClipboardManager clipboard;
    private long timeoutMillis;
    private long pollMillis;

    public MainActivityAccessibilityTest() {
        super(MainActivity.class);
    }

    @Override
    protected void setUp() throws Exception {
        super.setUp();
        Bundle args = ((InstrumentationTestRunner) getInstrumentation()).getArguments();
        // Test policy defaults; CI passes both settings explicitly.
        timeoutMillis = Long.parseLong(args.getString("axTimeoutMillis", "10000"));
        pollMillis = Long.parseLong(args.getString("axPollMillis", "100"));
        assertTrue(timeoutMillis > 0 && pollMillis > 0);
        // Enables native semantics exposure without installing/enabling TalkBack.
        automation = getInstrumentation().getUiAutomation();
        assertNotNull(automation);
        AccessibilityServiceInfo service = automation.getServiceInfo();
        service.flags |= AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
                | AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS;
        automation.setServiceInfo(service);
        clipboard = getActivity().getSystemService(ClipboardManager.class);
        assertNotNull(clipboard);
    }

    @Override
    protected void tearDown() throws Exception {
        try {
            // Only synthetic test input is placed on the clipboard.
            if (clipboard != null) {
                getInstrumentation().runOnMainSync(() -> clipboard.clearPrimaryClip());
            }
        } finally {
            super.tearDown();
        }
    }

    public void testEnglishLanguageFields() {
        checkLocale("English", "Source language", "Source text", "Target language",
                "Copy translation 1", "Import text or Markdown");
    }

    public void testJapaneseLanguageFields() {
        checkLocale("日本語", "原文の言語", "原文", "訳先の言語",
                "1件目の訳文をコピー", "テキスト・Markdownを読み込む");
    }

    private void checkLocale(String locale, String source, String sourceText,
            String target, String copy, String importSource) {
        click("interface language menu", n -> named(n, "Interface language")
                || named(n, "表示言語"));
        click(locale, n -> named(n, locale));
        // Native assertions poll for localized semantics beyond main-thread idle.
        getInstrumentation().waitForIdleSync();
        checkField("source-language", source, "source-text", sourceText, importSource);
        checkField("target-language-0", target, null, copy, null);
    }

    private void checkField(String id, String label, String nextId, String nextLabel,
            String interveningControl) {
        revealField(id);
        click(label, n -> field(n, id));
        assertField(id, label, "");
        // Verify that input reaches the tapped field by pasting a synthetic marker.
        // sendStringSync("p") failed to commit under the Japanese UI locale on the
        // hosted emulator even though the native field remained focused.
        setClipboardText("p");
        controlKey(KeyEvent.KEYCODE_V);
        assertField(id, label, "p");
        String currentValue = "p";
        for (String value : new String[] {"العربية", "Latin"}) {
            // Keyboard paste exercises the focused editor, not ACTION_SET_TEXT's
            // optimistic semantics prediction, without a Unicode key-map dependency.
            setClipboardText(value);
            // Delete one scalar per exact update: Ctrl+A and rapid key bursts were unreliable.
            while (!currentValue.isEmpty()) {
                currentValue = currentValue.substring(0,
                        currentValue.offsetByCodePoints(currentValue.length(), -1));
                String before = inputFocusState();
                getInstrumentation().sendKeyDownUpSync(KeyEvent.KEYCODE_DEL);
                try {
                    assertField(id, label, currentValue);
                } catch (AssertionFailedError failure) {
                    failure.addSuppressed(new AssertionFailedError(
                            "Backspace native focus before=" + before + "; after=" + inputFocusState()));
                    throw failure;
                }
            }
            controlKey(KeyEvent.KEYCODE_V);
            assertField(id, label, value);
            // No re-tap: input must still reach this field after its direction rebuild.
            setClipboardText("x");
            controlKey(KeyEvent.KEYCODE_V);
            currentValue = value + "x";
            assertField(id, label, currentValue);
            // Wait for Android main-thread idle, not asynchronous Dart/IME completion.
            getInstrumentation().waitForIdleSync();
        }
        // Verify the native forward traversal target. The import action is now
        // between the source-language and source-text controls; widget tests own
        // the complete forward/reverse sequence.
        pressKey(KeyEvent.KEYCODE_TAB, 0);
        if (nextId != null) {
            if (interveningControl != null) {
                awaitFocused(interveningControl);
                pressKey(KeyEvent.KEYCODE_TAB, 0);
            }
            controlKey(KeyEvent.KEYCODE_A);
            getInstrumentation().sendKeyDownUpSync(KeyEvent.KEYCODE_DEL);
            getInstrumentation().sendStringSync("z");
            assertField(nextId, nextLabel, "z");
        } else {
            awaitFocused(nextLabel);
        }
    }

    private void setClipboardText(String value) {
        getInstrumentation().runOnMainSync(() ->
                clipboard.setPrimaryClip(ClipData.newPlainText("RTL test", value)));
    }

    private void controlKey(int keyCode) {
        long now = SystemClock.uptimeMillis();
        int meta = KeyEvent.META_CTRL_ON | KeyEvent.META_CTRL_LEFT_ON;
        getInstrumentation().sendKeySync(
                new KeyEvent(now, now, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_CTRL_LEFT, 0, meta));
        try {
            pressKey(keyCode, meta);
        } finally {
            getInstrumentation().sendKeySync(new KeyEvent(now, SystemClock.uptimeMillis(),
                    KeyEvent.ACTION_UP, KeyEvent.KEYCODE_CTRL_LEFT, 0, 0));
        }
    }

    private void pressKey(int keyCode, int meta) {
        long now = SystemClock.uptimeMillis();
        getInstrumentation().sendKeySync(
                new KeyEvent(now, now, KeyEvent.ACTION_DOWN, keyCode, 0, meta));
        getInstrumentation().sendKeySync(
                new KeyEvent(now, now, KeyEvent.ACTION_UP, keyCode, 0, meta));
    }

    private void awaitFocused(String label) {
        AccessibilityNodeInfo node = await(label + " traversal focus",
                n -> named(n, label) && n.isFocused());
        node.recycle();
    }

    private void assertField(String id, String label, String value) {
        // Value updates are polled independently from focus flags. The initial typed
        // marker proves input reaches the field; later typing without retapping proves
        // it remains routed here when direction changes rebuild the semantics tree.
        AccessibilityNodeInfo node = awaitFieldValue(id, label, value);
        try {
            // Flutter may expose the localized name in the hint or description, optionally
            // combined with the field's example hint.
            String hint = string(node.getHintText());
            String description = string(node.getContentDescription());
            assertTrue("localized native field label: " + label
                            + "; hintCodePoints=" + codePoints(hint)
                            + "; descriptionCodePoints=" + codePoints(description)
                            + "; valueCodePoints=" + codePoints(string(node.getText()))
                            + "; focused=" + node.isFocused()
                            + "; accessibilityFocused=" + node.isAccessibilityFocused(),
                    nameMatches(hint, label) || nameMatches(description, label));
            assertEquals("android.widget.EditText", string(node.getClassName()));
            assertTrue(node.isEnabled());
            assertTrue(node.isEditable());
            assertTrue(node.isFocusable());
        } finally {
            node.recycle();
        }
    }

    private void revealField(String id) {
        // Flutter's Android bridge omits hidden children, so an absent field cannot
        // be addressed with ACTION_SHOW_ON_SCREEN.
        int scrollAttempts = 0;
        int scrollAccepted = 0;
        long deadline = SystemClock.uptimeMillis() + timeoutMillis;
        do {
            AccessibilityNodeInfo node = findInApplication(
                    n -> field(n, id) && n.isVisibleToUser());
            if (node != null) {
                node.recycle();
                return;
            }
            AccessibilityNodeInfo scroll = findInApplication(
                    n -> n.isScrollable() && !n.isEditable());
            if (scroll != null) {
                try {
                    scrollAttempts++;
                    if (scroll.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)) {
                        scrollAccepted++;
                    }
                } finally {
                    scroll.recycle();
                }
            }
            SystemClock.sleep(pollMillis);
        } while (SystemClock.uptimeMillis() < deadline);
        fail("Native field unavailable after scrolling: " + id
                + "; forwardAccepted/attempted=" + scrollAccepted + "/" + scrollAttempts);
    }

    // Window/view focus only: IMM status getters can trigger checkFocus/startInput.
    // Observation errors report unavailable, not false.
    private String inputFocusState() {
        String[] state = {"unavailable"};
        try {
            getInstrumentation().runOnMainSync(() -> {
                try {
                    MainActivity activity = getActivity();
                    View focus = activity.getCurrentFocus();
                    state[0] = "{windowFocus=" + activity.hasWindowFocus()
                            + ", currentFocusExists=" + (focus != null)
                            + ", currentFocusHasFocus=" + (focus != null && focus.hasFocus()) + "}";
                } catch (RuntimeException | AssertionError ignored) { /* Keep unavailable. */ }
            });
        } catch (RuntimeException | AssertionError ignored) { /* Keep unavailable. */ }
        return state[0];
    }

    private void click(String description, Predicate<AccessibilityNodeInfo> predicate) {
        AccessibilityNodeInfo node = await(description, predicate);
        try {
            assertTrue(description + " click", node.performAction(AccessibilityNodeInfo.ACTION_CLICK));
        } finally {
            node.recycle();
        }
    }

    private AccessibilityNodeInfo awaitFieldValue(String id, String label, String value) {
        long deadline = SystemClock.uptimeMillis() + timeoutMillis;
        do {
            AccessibilityNodeInfo node = findInApplication(n ->
                    field(n, id) && value.contentEquals(string(n.getText())));
            if (node != null) return node;
            SystemClock.sleep(pollMillis);
        } while (SystemClock.uptimeMillis() < deadline);
        fail("Native accessibility value unavailable: " + label
                + "; expectedCodePoints=" + codePoints(value) + "; current=" + fieldState(id));
        return null;
    }

    // This test enters only synthetic text. Emit a bounded code-point prefix, not
    // raw text or a tree dump, so invisible bidi controls can be diagnosed without
    // changing the exact-value assertion.
    private String fieldState(String id) {
        AccessibilityNodeInfo node = findInApplication(n -> field(n, id));
        if (node == null) return "field missing";
        try {
            return "textCodePoints=" + codePoints(string(node.getText()))
                    + ", selection=" + node.getTextSelectionStart()
                    + ".." + node.getTextSelectionEnd()
                    + ", focused=" + node.isFocused()
                    + ", visible=" + node.isVisibleToUser();
        } finally {
            node.recycle();
        }
    }

    private static String codePoints(String value) {
        return value.codePoints().limit(32)
                .mapToObj(codePoint -> "U+" + Integer.toHexString(codePoint))
                .collect(Collectors.joining(" ", "[", "]"))
                + " (scalars=" + value.codePointCount(0, value.length()) + ")";
    }

    private AccessibilityNodeInfo await(String description,
            Predicate<AccessibilityNodeInfo> predicate) {
        long deadline = SystemClock.uptimeMillis() + timeoutMillis;
        do {
            AccessibilityNodeInfo node = findInApplication(predicate);
            if (node != null) return node;
            SystemClock.sleep(pollMillis);
        } while (SystemClock.uptimeMillis() < deadline);
        fail("Native accessibility state unavailable: " + description);
        return null;
    }

    // The active window can be the IME after tapping an editor. Search only our
    // application's windows, including popup menus, without substituting AX focus
    // for the input focus asserted above.
    private AccessibilityNodeInfo findInApplication(Predicate<AccessibilityNodeInfo> predicate) {
        String packageName = getInstrumentation().getTargetContext().getPackageName();
        List<AccessibilityWindowInfo> windows = automation.getWindows();
        try {
            for (AccessibilityWindowInfo window : windows) {
                if (window.getType() != AccessibilityWindowInfo.TYPE_APPLICATION) continue;
                AccessibilityNodeInfo node = find(window.getRoot(), n ->
                        packageName.contentEquals(string(n.getPackageName()))
                                && predicate.test(n));
                if (node != null) return node;
            }
            return null;
        } finally {
            for (AccessibilityWindowInfo window : windows) window.recycle();
        }
    }

    // Each poll reads a fresh OS tree; never assert against a stale pre-rebuild node.
    private static AccessibilityNodeInfo find(AccessibilityNodeInfo node,
            Predicate<AccessibilityNodeInfo> predicate) {
        if (node == null) return null;
        try {
            if (predicate.test(node)) return AccessibilityNodeInfo.obtain(node);
            for (int i = 0; i < node.getChildCount(); i++) {
                AccessibilityNodeInfo found = find(node.getChild(i), predicate);
                if (found != null) return found;
            }
            return null;
        } finally {
            node.recycle();
        }
    }

    private static boolean field(AccessibilityNodeInfo node, String id) {
        return node.isEditable() && id.equals(node.getViewIdResourceName());
    }

    private static boolean nameMatches(String name, String label) {
        return name.equals(label) || name.startsWith(label + ", ")
                || name.startsWith(label + "\n");
    }

    private static boolean named(AccessibilityNodeInfo node, String label) {
        return label.equals(string(node.getContentDescription()))
                || label.equals(string(node.getText()))
                || label.equals(string(node.getTooltipText()));
    }

    private static String string(CharSequence value) {
        return value == null ? "" : value.toString();
    }
}
