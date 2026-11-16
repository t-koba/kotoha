package org.kotoha.app;

import android.accessibilityservice.AccessibilityServiceInfo;
import android.app.UiAutomation;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.graphics.Rect;
import android.os.Build;
import android.os.Bundle;
import android.os.SystemClock;
import android.test.ActivityInstrumentationTestCase2;
import android.test.InstrumentationTestRunner;
import android.view.InputDevice;
import android.view.KeyCharacterMap;
import android.view.KeyEvent;
import android.view.View;
import android.view.WindowInsets;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityWindowInfo;
import java.util.ArrayDeque;
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
    private static final int MAX_DIAGNOSTIC_EVENTS = 24;
    private UiAutomation automation;
    private ClipboardManager clipboard;
    private String appPackageName;
    private final Object diagnosticLock = new Object();
    private final ArrayDeque<String> diagnosticEvents = new ArrayDeque<>();
    private String lastWindowContentChange = "none";
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
        appPackageName = getInstrumentation().getTargetContext().getPackageName();
        // Enables native semantics exposure without installing/enabling TalkBack.
        automation = getInstrumentation().getUiAutomation();
        assertNotNull(automation);
        AccessibilityServiceInfo service = automation.getServiceInfo();
        service.flags |= AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
                | AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS;
        service.eventTypes |= AccessibilityEvent.TYPE_VIEW_SCROLLED
                | AccessibilityEvent.TYPE_VIEW_TEXT_SELECTION_CHANGED
                | AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED
                | AccessibilityEvent.TYPE_VIEW_FOCUSED
                | AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUSED
                | AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
                | AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED;
        automation.setServiceInfo(service);
        automation.setOnAccessibilityEventListener(this::recordAccessibilityEvent);
        clipboard = getActivity().getSystemService(ClipboardManager.class);
        assertNotNull(clipboard);
    }

    @Override
    protected void tearDown() throws Exception {
        try {
            if (automation != null) automation.setOnAccessibilityEventListener(null);
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
                "Copy translation 1", "Import text or Markdown", "Review model package terms");
    }

    public void testInstrumentationDeleteKeyComparison() {
        click("interface language menu", n -> named(n, "Interface language")
                || named(n, "表示言語"));
        click("English", n -> named(n, "English"));
        getInstrumentation().waitForIdleSync();

        String id = "target-language-0";
        String label = "Target language";
        revealField(id);
        click(label, n -> field(n, id));
        assertField(id, label, "");
        setClipboardText("p");
        controlKey(KeyEvent.KEYCODE_V);
        assertField(id, label, "p");
        AssertionFailedError controlFailure = null;
        try {
            getInstrumentation().sendKeyDownUpSync(KeyEvent.KEYCODE_DEL);
            assertField(id, label, "");
        } catch (AssertionFailedError failure) {
            // Retain the explicit expectation, but still exercise the other API once.
            controlFailure = failure;
        }
        String controlState = "Instrumentation.sendKeyDownUpSync(KEYCODE_DEL)"
                + "; expectedCodePoints=" + codePoints("") + "; observed=" + fieldState(id)
                + "; assertionPassed=" + (controlFailure == null);
        try {
            // Replace any remaining marker rather than appending after a failed delete.
            // No re-tap: both APIs must act on the same focused target editor.
            controlKey(KeyEvent.KEYCODE_A);
            setClipboardText("p");
            controlKey(KeyEvent.KEYCODE_V);
            assertField(id, label, "p");
        } catch (AssertionFailedError failure) {
            failure.addSuppressed(new AssertionFailedError(controlState));
            if (controlFailure != null) failure.addSuppressed(controlFailure);
            throw failure;
        }
        AssertionFailedError injectionFailure = null;
        try {
            injectKeyDownUpAndAssertAccepted(KeyEvent.KEYCODE_DEL);
            assertField(id, label, "");
        } catch (AssertionFailedError failure) {
            injectionFailure = failure;
        }
        if (controlFailure != null || injectionFailure != null) {
            AssertionFailedError comparison = new AssertionFailedError(
                    "Synthetic target-language-0 delete comparison: " + controlState
                            + "; UiAutomation.injectInputEvent(KEYCODE_DEL down/up)"
                            + "; expectedCodePoints=" + codePoints("")
                            + "; observed=" + fieldState(id)
                            + "; assertionPassed=" + (injectionFailure == null));
            if (controlFailure != null) comparison.addSuppressed(controlFailure);
            if (injectionFailure != null) comparison.addSuppressed(injectionFailure);
            throw comparison;
        }
    }

    public void testJapaneseLanguageFields() {
        checkLocale("日本語", "原文の言語", "原文", "訳先の言語",
                "1件目の訳文をコピー", "テキスト・Markdownを読み込む",
                "モデルパッケージの利用条件を確認");
    }

    private void checkLocale(String locale, String source, String sourceText,
            String target, String copy, String importSource, String reviewModelTerms) {
        click("interface language menu", n -> named(n, "Interface language")
                || named(n, "表示言語"));
        click(locale, n -> named(n, locale));
        // Native assertions poll for localized semantics beyond main-thread idle.
        getInstrumentation().waitForIdleSync();
        checkField("source-language", source, "source-text", sourceText,
                importSource, reviewModelTerms);
        checkField("target-language-0", target, null, copy);
    }

    private void checkField(String id, String label, String nextId, String nextLabel,
            String... interveningControls) {
        String sourceStateBeforeTargetNavigation = "target-language-0".equals(id)
                ? fieldState("source-language") : null;
        revealField(id);
        click(label, n -> field(n, id));
        try {
            assertField(id, label, "");
        } catch (AssertionFailedError failure) {
            if (sourceStateBeforeTargetNavigation != null) {
                failure.addSuppressed(new AssertionFailedError(
                        "Source-language state before target navigation="
                                + sourceStateBeforeTargetNavigation));
            }
            throw failure;
        }
        // Verify that input reaches the tapped field by pasting a synthetic marker.
        // sendStringSync("p") failed to commit under the Japanese UI locale on the
        // hosted emulator even though the native field remained focused.
        setClipboardText("p");
        controlKey(KeyEvent.KEYCODE_V);
        assertField(id, label, "p");
        String currentValue = "p";
        for (String value : new String[] {"العربية", "Latin"}) {
            // Delete one scalar per exact update: Ctrl+A and rapid key bursts were unreliable.
            while (!currentValue.isEmpty()) {
                currentValue = currentValue.substring(0,
                        currentValue.offsetByCodePoints(currentValue.length(), -1));
                String before = inputFocusState();
                clearDiagnosticEvents();
                try {
                    injectKeyDownUpAndAssertAccepted(KeyEvent.KEYCODE_DEL);
                    assertField(id, label, currentValue);
                } catch (AssertionFailedError failure) {
                    failure.addSuppressed(new AssertionFailedError(
                            "Backspace native focus before=" + before + "; after=" + inputFocusState()
                                    + "; events=" + diagnosticEventState()));
                    throw failure;
                }
            }
            // Update the clipboard only after deleting the current value, keeping
            // clipboard changes outside the focused editor's deletion sequence.
            // Paste exercises this editor, not ACTION_SET_TEXT's optimistic
            // semantics prediction, without a Unicode key-map dependency.
            setClipboardText(value);
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
            for (String interveningControl : interveningControls) {
                awaitFocused(interveningControl);
                pressKey(KeyEvent.KEYCODE_TAB, 0);
            }
            controlKey(KeyEvent.KEYCODE_A);
            injectKeyDownUpAndAssertAccepted(KeyEvent.KEYCODE_DEL);
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

    // UiAutomation reports injection success, not delivery or handling by the app or IME.
    // Pair that result with exact field-value and focus assertions; do not infer a Flutter
    // or input-connection cause from injection success alone.
    private void injectKeyDownUpAndAssertAccepted(int keyCode) {
        // ACTION_UP must reuse the original ACTION_DOWN time to form one key press.
        long downTime = SystemClock.uptimeMillis();
        injectKeyEventAndAssertAccepted(downTime, downTime, KeyEvent.ACTION_DOWN, keyCode);
        injectKeyEventAndAssertAccepted(downTime, SystemClock.uptimeMillis(),
                KeyEvent.ACTION_UP, keyCode);
    }

    private void injectKeyEventAndAssertAccepted(long downTime, long eventTime,
            int action, int keyCode) {
        KeyEvent event = new KeyEvent(downTime, eventTime, action, keyCode, 0, 0,
                KeyCharacterMap.VIRTUAL_KEYBOARD, 0, KeyEvent.FLAG_FROM_SYSTEM,
                InputDevice.SOURCE_KEYBOARD);
        assertTrue("Android rejected native key injection: action=" + action
                + ", keyCode=" + keyCode,
                automation.injectInputEvent(event, true));
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
        clearDiagnosticEvents();
        int forwardAttempts = 0;
        int forwardAccepted = 0;
        int backwardAttempts = 0;
        int backwardAccepted = 0;
        int direction = AccessibilityNodeInfo.ACTION_SCROLL_FORWARD;
        boolean scrollExhausted = false;
        long deadline = SystemClock.uptimeMillis() + timeoutMillis;
        do {
            AccessibilityNodeInfo node = findInApplication(
                    n -> field(n, id) && n.isVisibleToUser());
            if (node != null) {
                node.recycle();
                return;
            }
            AccessibilityNodeInfo scroll = scrollExhausted ? null : findInApplication(
                    n -> n.isScrollable() && !n.isEditable());
            if (scroll != null) {
                try {
                    int attempts;
                    boolean accepted = scroll.performAction(direction);
                    if (direction == AccessibilityNodeInfo.ACTION_SCROLL_FORWARD) {
                        attempts = ++forwardAttempts;
                        if (accepted) forwardAccepted++;
                    } else {
                        attempts = ++backwardAttempts;
                        if (accepted) backwardAccepted++;
                    }
                    // Counts in the failure summary carry repeated failures; retain the first
                    // result and successful actions so the bounded event ring keeps useful state.
                    if (accepted || attempts == 1) {
                        recordDiagnosticMarker("scroll-direction="
                                + (direction == AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
                                        ? "forward" : "backward")
                                + ",attempt=" + attempts + ",accepted=" + accepted);
                    }
                    if (!accepted) {
                        if (direction == AccessibilityNodeInfo.ACTION_SCROLL_FORWARD) {
                            // The current position can already be at the forward edge. Search
                            // back through the same scrollable before declaring the field absent.
                            direction = AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD;
                            recordDiagnosticMarker("scroll-direction=backward");
                        } else {
                            // Keep the original deadline for delayed semantics updates, but
                            // do not keep issuing an action the container has rejected.
                            scrollExhausted = true;
                            recordDiagnosticMarker("scroll-container=exhausted");
                        }
                    }
                } finally {
                    scroll.recycle();
                }
            } else if (!scrollExhausted) {
                recordDiagnosticMarker("scroll-container=missing");
            }
            SystemClock.sleep(pollMillis);
        } while (SystemClock.uptimeMillis() < deadline);
        fail("Native field unavailable after scrolling: " + id
                + "; forwardAccepted/attempted=" + forwardAccepted + "/" + forwardAttempts
                + "; backwardAccepted/attempted=" + backwardAccepted + "/" + backwardAttempts
                + "; target=" + fieldAvailability(id)
                + "; scrollables=" + scrollableState()
                + "; events=" + diagnosticEventState());
    }

    private void clearDiagnosticEvents() {
        synchronized (diagnosticLock) {
            diagnosticEvents.clear();
            lastWindowContentChange = "none";
        }
    }

    private void recordDiagnosticMarker(String marker) {
        appendDiagnosticEvent(SystemClock.uptimeMillis() + ":" + marker);
    }

    // Keep the bounded event trail structural; never record text-bearing event fields.
    private void recordAccessibilityEvent(AccessibilityEvent event) {
        if (event == null
                || !appPackageName.contentEquals(string(event.getPackageName()))) return;
        int type = event.getEventType();
        String className = string(event.getClassName());
        if (className.length() > 128) className = className.substring(0, 128);
        String summary;
        if (type == AccessibilityEvent.TYPE_VIEW_SCROLLED) {
            summary = "scrolled{" + className + ",xy=" + event.getScrollX() + "/"
                    + event.getMaxScrollX() + "," + event.getScrollY() + "/"
                    + event.getMaxScrollY() + ",items=" + event.getFromIndex() + ".."
                    + event.getToIndex() + "/" + event.getItemCount() + "}";
        } else if (type == AccessibilityEvent.TYPE_VIEW_TEXT_SELECTION_CHANGED) {
            summary = "selection{" + className + ",range=" + event.getFromIndex() + ".."
                    + event.getToIndex() + ",items=" + event.getItemCount() + "}";
        } else if (type == AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED) {
            summary = "text-changed{" + className + ",from=" + event.getFromIndex()
                    + ",added=" + event.getAddedCount() + ",removed="
                    + event.getRemovedCount() + "}";
        } else if (type == AccessibilityEvent.TYPE_VIEW_FOCUSED
                || type == AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUSED) {
            summary = "focused{" + className + ",type=" + Integer.toHexString(type) + "}";
        } else if (type == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) {
            synchronized (diagnosticLock) {
                lastWindowContentChange = SystemClock.uptimeMillis() + ":" + className;
            }
            return;
        } else if (type == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            summary = "window-state-change{" + className + "}";
        } else {
            return;
        }
        appendDiagnosticEvent(SystemClock.uptimeMillis() + ":" + summary);
    }

    private void appendDiagnosticEvent(String event) {
        synchronized (diagnosticLock) {
            if (diagnosticEvents.size() == MAX_DIAGNOSTIC_EVENTS) diagnosticEvents.removeFirst();
            diagnosticEvents.addLast(event);
        }
    }

    private String diagnosticEventState() {
        synchronized (diagnosticLock) {
            return "lastContentChange=" + lastWindowContentChange
                    + ",events=" + diagnosticEvents;
        }
    }

    // Failure-only structure diagnostics distinguish an absent/hidden target from
    // an incorrectly selected scroll container without emitting labels or text.
    private String fieldAvailability(String id) {
        AccessibilityNodeInfo node = findInApplication(
                n -> id.equals(string(n.getViewIdResourceName())));
        if (node == null) return "identifier-not-in-tree";
        try {
            Rect bounds = new Rect();
            node.getBoundsInScreen(bounds);
            return "present{class=" + string(node.getClassName())
                    + ",editable=" + node.isEditable()
                    + ",enabled=" + node.isEnabled()
                    + ",visible=" + node.isVisibleToUser()
                    + ",bounds=" + bounds.toShortString() + "}";
        } finally {
            node.recycle();
        }
    }

    private String scrollableState() {
        StringBuilder state = new StringBuilder("[");
        int[] count = {0};
        List<AccessibilityWindowInfo> windows = automation.getWindows();
        try {
            for (AccessibilityWindowInfo window : windows) {
                if (window.getType() != AccessibilityWindowInfo.TYPE_APPLICATION) continue;
                appendScrollableState(window.getRoot(), appPackageName, state, count);
            }
        } finally {
            for (AccessibilityWindowInfo window : windows) window.recycle();
        }
        return state.append("] count=").append(count[0]).toString();
    }

    private static void appendScrollableState(AccessibilityNodeInfo node, String packageName,
            StringBuilder state, int[] count) {
        if (node == null) return;
        try {
            if (packageName.contentEquals(string(node.getPackageName())) && node.isScrollable()) {
                if (count[0] < 8) {
                    if (count[0] > 0) state.append(", ");
                    Rect bounds = new Rect();
                    node.getBoundsInScreen(bounds);
                    String actions = node.getActionList().stream()
                            .map(action -> Integer.toHexString(action.getId()))
                            .collect(Collectors.joining(","));
                    state.append("{class=").append(string(node.getClassName()))
                            .append(",id=").append(string(node.getViewIdResourceName()))
                            .append(",visible=").append(node.isVisibleToUser())
                            .append(",bounds=").append(bounds.toShortString())
                            .append(",children=").append(node.getChildCount())
                            .append(",actions=").append(actions);
                    if (Build.VERSION.SDK_INT >= 19) {
                        AccessibilityNodeInfo.RangeInfo range = node.getRangeInfo();
                        if (range != null) {
                            state.append(",range=").append(range.getCurrent()).append("/")
                                    .append(range.getMin()).append("..").append(range.getMax());
                        }
                    }
                    state.append("}");
                }
                count[0]++;
            }
            for (int i = 0; i < node.getChildCount(); i++) {
                appendScrollableState(node.getChild(i), packageName, state, count);
            }
        } finally {
            node.recycle();
        }
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
                    WindowInsets insets = activity.getWindow().getDecorView().getRootWindowInsets();
                    String imeVisible = Build.VERSION.SDK_INT >= 30 && insets != null
                            ? Boolean.toString(insets.isVisible(WindowInsets.Type.ime()))
                            : "unavailable";
                    state[0] = "{windowFocus=" + activity.hasWindowFocus()
                            + ", currentFocusExists=" + (focus != null)
                            + ", currentFocusClass="
                            + (focus == null ? "none" : focus.getClass().getName())
                            + ", currentFocusHasFocus=" + (focus != null && focus.hasFocus())
                            + ", currentFocusShown=" + (focus != null && focus.isShown())
                            + ", imeVisible=" + imeVisible + "}";
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
        List<AccessibilityWindowInfo> windows = automation.getWindows();
        try {
            for (AccessibilityWindowInfo window : windows) {
                if (window.getType() != AccessibilityWindowInfo.TYPE_APPLICATION) continue;
                AccessibilityNodeInfo node = find(window.getRoot(), n ->
                        appPackageName.contentEquals(string(n.getPackageName()))
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
