package org.kotoha.app;

import android.app.UiAutomation;
import android.os.Bundle;
import android.os.SystemClock;
import android.test.ActivityInstrumentationTestCase2;
import android.test.InstrumentationTestRunner;
import android.view.KeyEvent;
import android.view.accessibility.AccessibilityNodeInfo;
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
        getActivity();
    }

    public void testEnglishLanguageFields() {
        checkLocale("English", "Source language", "Source text", "Target language",
                "Copy translation 1");
    }

    public void testJapaneseLanguageFields() {
        checkLocale("日本語", "原文の言語", "原文", "訳先の言語", "1件目の訳文をコピー");
    }

    private void checkLocale(String locale, String source, String sourceText,
            String target, String copy) {
        act("interface language menu", n -> named(n, "Interface language")
                || named(n, "表示言語"), AccessibilityNodeInfo.ACTION_CLICK, null);
        act(locale, n -> named(n, locale), AccessibilityNodeInfo.ACTION_CLICK, null);
        checkField(source, sourceText, true);
        checkField(target, copy, false);
    }

    private void checkField(String label, String nextLabel, boolean nextIsField) {
        revealField(label);
        act(label, n -> field(n, label), AccessibilityNodeInfo.ACTION_CLICK, null);
        awaitFocused(label, true);
        for (String value : new String[] {"العربية", "Latin"}) {
            Bundle text = new Bundle();
            text.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, value);
            act(label, n -> field(n, label), AccessibilityNodeInfo.ACTION_SET_TEXT, text);
            assertField(label, value);
            // No re-tap: input must still reach this field after its direction rebuild.
            getInstrumentation().sendStringSync("x");
            assertField(label, value + "x");
            tab(false);
            awaitFocused(nextLabel, nextIsField);
            tab(true);
            assertField(label, value + "x");
        }
    }

    private void assertField(String label, String value) {
        AccessibilityNodeInfo node = await(label + " value=" + value + " with input focus",
                n -> field(n, label) && value.contentEquals(string(n.getText()))
                        && n.isFocused());
        try {
            // Flutter may expose the localized name in the hint or description, optionally
            // combined with the field's example hint.
            assertTrue("localized native field label: " + label, field(node, label));
            assertEquals("android.widget.EditText", string(node.getClassName()));
            assertTrue(node.isEnabled());
            assertTrue(node.isEditable());
            assertTrue(node.isFocusable());
            assertTrue(node.getActionList().contains(
                    AccessibilityNodeInfo.AccessibilityAction.ACTION_SET_TEXT));
        } finally {
            node.recycle();
        }
    }

    private void awaitFocused(String label, boolean isField) {
        AccessibilityNodeInfo node = await(label + " input focus",
                n -> (isField ? field(n, label) : named(n, label)) && n.isFocused());
        node.recycle();
    }

    private void tab(boolean reverse) {
        long now = SystemClock.uptimeMillis();
        int meta = reverse ? KeyEvent.META_SHIFT_ON | KeyEvent.META_SHIFT_LEFT_ON : 0;
        getInstrumentation().sendKeySync(
                new KeyEvent(now, now, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_TAB, 0, meta));
        getInstrumentation().sendKeySync(
                new KeyEvent(now, now, KeyEvent.ACTION_UP, KeyEvent.KEYCODE_TAB, 0, meta));
    }

    private void revealField(String label) {
        // A phone viewport cannot show the entire editor. Scroll until the field is
        // visible in the native tree, bounded by the configured wait.
        long deadline = SystemClock.uptimeMillis() + timeoutMillis;
        do {
            AccessibilityNodeInfo node = find(automation.getRootInActiveWindow(),
                    n -> field(n, label) && n.isVisibleToUser());
            if (node != null) {
                node.recycle();
                return;
            }
            AccessibilityNodeInfo scroll = find(automation.getRootInActiveWindow(),
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
        fail("Native field unavailable after scrolling: " + label);
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
            AccessibilityNodeInfo node = find(automation.getRootInActiveWindow(), predicate);
            if (node != null) return node;
            SystemClock.sleep(pollMillis);
        } while (SystemClock.uptimeMillis() < deadline);
        fail("Native accessibility state unavailable: " + description);
        return null;
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

    private static boolean field(AccessibilityNodeInfo node, String label) {
        return node.isEditable() && (nameMatches(string(node.getHintText()), label)
                || nameMatches(string(node.getContentDescription()), label)
                || nameMatches(string(node.getText()), label));
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
