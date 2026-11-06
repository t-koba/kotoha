package org.kotoha.app;

import android.accessibilityservice.AccessibilityServiceInfo;
import android.app.UiAutomation;
import android.os.Bundle;
import android.os.SystemClock;
import android.test.ActivityInstrumentationTestCase2;
import android.test.InstrumentationTestRunner;
import android.view.KeyEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityWindowInfo;
import java.util.List;
import java.util.function.Predicate;

/**
 * Native accessibility bridge and synthesized keyboard input on the pinned emulator only.
 * No TalkBack speech/gestures, physical keyboard/device, or OS thumbnail claims.
 * Widget tests own bidi direction/caret policy and the complete Flutter traversal order.
 */
@SuppressWarnings("deprecation") // SDK instrumentation only; no third-party dependencies.
public final class MainActivityAccessibilityTest
        extends ActivityInstrumentationTestCase2<MainActivity> {
    private UiAutomation automation;
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
        getActivity();
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
        act("interface language menu", n -> named(n, "Interface language")
                || named(n, "表示言語"), AccessibilityNodeInfo.ACTION_CLICK, null);
        act(locale, n -> named(n, locale), AccessibilityNodeInfo.ACTION_CLICK, null);
        // The selection rebuilds localized Flutter semantics asynchronously; wait
        // for that UI work before querying the native field tree.
        getInstrumentation().waitForIdleSync();
        checkField("source-language", source, "source-text", sourceText, importSource);
        checkField("target-language-0", target, null, copy, null);
    }

    private void checkField(String id, String label, String nextId, String nextLabel,
            String interveningControl) {
        revealField(id);
        act(label, n -> field(n, id), AccessibilityNodeInfo.ACTION_CLICK, null);
        Bundle clear = new Bundle();
        clear.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, "");
        act(label, n -> field(n, id), AccessibilityNodeInfo.ACTION_SET_TEXT, clear);
        getInstrumentation().waitForIdleSync();
        // Verify initial native input focus by sending real keyboard input rather than
        // relying on isFocused(), which is not consistently exposed for Flutter editors.
        getInstrumentation().sendStringSync("p");
        assertField(id, label, "p");
        for (String value : new String[] {"العربية", "Latin"}) {
            Bundle text = new Bundle();
            text.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, value);
            act(label, n -> field(n, id), AccessibilityNodeInfo.ACTION_SET_TEXT, text);
            assertField(id, label, value);
            // No re-tap: input must still reach this field after its direction rebuild.
            getInstrumentation().sendStringSync("x");
            assertField(id, label, value + "x");
        }
        // Verify the native forward traversal target. The import action is now
        // between the source-language and source-text controls; widget tests own
        // the complete forward/reverse sequence.
        tabForward();
        if (nextId != null) {
            if (interveningControl != null) {
                awaitFocused(interveningControl);
                tabForward();
            }
            Bundle clearNext = new Bundle();
            clearNext.putCharSequence(
                    AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, "");
            act(nextLabel, n -> field(n, nextId), AccessibilityNodeInfo.ACTION_SET_TEXT, clearNext);
            getInstrumentation().waitForIdleSync();
            getInstrumentation().sendStringSync("z");
            assertField(nextId, nextLabel, "z");
        } else {
            awaitFocused(nextLabel);
        }
    }

    private void tabForward() {
        long now = SystemClock.uptimeMillis();
        getInstrumentation().sendKeySync(
                new KeyEvent(now, now, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_TAB, 0, 0));
        getInstrumentation().sendKeySync(
                new KeyEvent(now, now, KeyEvent.ACTION_UP, KeyEvent.KEYCODE_TAB, 0, 0));
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
        AccessibilityNodeInfo node = await(label + " value=" + value,
                n -> field(n, id) && value.contentEquals(string(n.getText())));
        try {
            // Flutter may expose the localized name in the hint or description, optionally
            // combined with the field's example hint.
            assertTrue("localized native field label: " + label,
                    nameMatches(string(node.getHintText()), label)
                            || nameMatches(string(node.getContentDescription()), label));
            assertEquals("android.widget.EditText", string(node.getClassName()));
            assertTrue(node.isEnabled());
            assertTrue(node.isEditable());
            assertTrue(node.isFocusable());
        } finally {
            node.recycle();
        }
    }

    private void revealField(String id) {
        // A phone viewport cannot show the entire editor. Scroll until the field is
        // visible in the native tree, bounded by the configured wait.
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
                    scroll.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD);
                } finally {
                    scroll.recycle();
                }
            }
            SystemClock.sleep(pollMillis);
        } while (SystemClock.uptimeMillis() < deadline);
        fail("Native field unavailable after scrolling: " + id);
    }

    private void act(String description, Predicate<AccessibilityNodeInfo> predicate,
            int action, Bundle args) {
        AccessibilityNodeInfo node = await(description, predicate);
        try {
            assertTrue(description + " action " + action, node.performAction(action, args));
        } finally {
            node.recycle();
        }
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
        return name.equals(label) || name.startsWith(label + ", ");
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
