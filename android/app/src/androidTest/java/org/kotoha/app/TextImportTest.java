package org.kotoha.app;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.ContentResolver;
import android.content.Intent;
import android.net.Uri;
import android.test.ActivityInstrumentationTestCase2;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.StandardMethodCodec;
import java.util.Arrays;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

/** Synthetic provider/results on Emulator, not live system DocumentsUI coverage. */
@SuppressWarnings("deprecation")
public final class TextImportTest extends ActivityInstrumentationTestCase2<MainActivity> {
    public TextImportTest() { super(MainActivity.class); }
    private static Uri uri(String kind) {
        return Uri.parse("content://org.kotoha.app.test.documents/" + kind);
    }
    private static final class Reply implements MethodChannel.Result {
        final CountDownLatch done = new CountDownLatch(1);
        final AtomicInteger completions = new AtomicInteger();
        Object value;
        String error;
        public void success(Object value) { this.value = value; complete(); }
        public void error(String code, String message, Object details) { error = code; complete(); }
        public void notImplemented() { error = "notImplemented"; complete(); }
        void complete() { completions.incrementAndGet(); done.countDown(); }
    }
    private void await(Reply reply) throws Exception {
        // Reuse the configured native-test wait budget, not an import runtime deadline.
        android.os.Bundle args = ((android.test.InstrumentationTestRunner) getInstrumentation()).getArguments();
        long timeout = Long.parseLong(args.getString("axTimeoutMillis", "10000"));
        assertTrue("Native import completed", reply.done.await(timeout, TimeUnit.MILLISECONDS));
        assertEquals(1, reply.completions.get());
    }
    private void open(TextImportPlugin plugin, Reply reply) throws Throwable {
        runTestOnUiThread(() -> {
            // The channel's actual handler and StandardMethodCodec request, on its engine plugin.
            java.nio.ByteBuffer encoded = StandardMethodCodec.INSTANCE.encodeMethodCall(new MethodCall("open", null));
            encoded.flip();
            MethodCall call = StandardMethodCodec.INSTANCE.decodeMethodCall(encoded);
            plugin.onMethodCall(call, reply);
        });
    }
    private Instrumentation.ActivityMonitor monitor(int resultCode, Intent data) {
        Instrumentation.ActivityMonitor monitor = new Instrumentation.ActivityMonitor() {
            @Override public Instrumentation.ActivityResult onStartActivity(Intent intent) {
                if (!Intent.ACTION_OPEN_DOCUMENT.equals(intent.getAction())) return null;
                assertTrue(intent.hasCategory(Intent.CATEGORY_OPENABLE));
                assertFalse(intent.getBooleanExtra(Intent.EXTRA_ALLOW_MULTIPLE, true));
                assertEquals("*/*", intent.getType());
                assertEquals(0, intent.getFlags() & Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
                return new Instrumentation.ActivityResult(resultCode, data);
            }
        };
        getInstrumentation().addMonitor(monitor);
        return monitor;
    }
    private io.flutter.embedding.engine.FlutterEngine engine() {
        io.flutter.embedding.android.FlutterView view = getActivity().findViewById(
                io.flutter.embedding.android.FlutterActivity.FLUTTER_VIEW_ID);
        return view.getAttachedFlutterEngine();
    }
    private TextImportPlugin plugin() {
        TextImportPlugin plugin = (TextImportPlugin) engine().getPlugins().get(TextImportPlugin.class);
        assertNotNull("Registered on the real Flutter engine", plugin);
        return plugin;
    }

    public void testProviderReadAndClosureOnSuccessAndFailure() throws Exception {
        // Local provider transport retains the tracking stream subclass; remote binder
        // descriptors cannot expose close counts. No mock reader bypasses ContentResolver.
        ImportTestProvider provider = new ImportTestProvider();
        android.content.pm.ProviderInfo info = new android.content.pm.ProviderInfo();
        info.authority = "org.kotoha.app.test.documents";
        info.exported = true;
        provider.attachInfo(getInstrumentation().getTargetContext(), info);
        ContentResolver resolver = ContentResolver.wrap(provider);
        Map<String, Object> value = TextImportPlugin.readDocument(resolver, uri("ok"));
        assertEquals("sample.MaRkDoWn", value.get("name"));
        assertTrue(Arrays.equals(ImportTestProvider.BYTES, (byte[]) value.get("bytes")));
        for (String kind : new String[] {"missing", "unsupported", "stream-error", "open-error"}) {
            try { TextImportPlugin.readDocument(resolver, uri(kind)); fail(kind); }
            catch (Exception expected) { /* Each fails closed. */ }
        }
        assertEquals(5, provider.cursorsClosed.get());
        assertEquals(2, provider.streamsOpened.get());
        assertEquals(2, provider.streamsClosed.get());
    }

    public void testActivityResultsCancelThenProviderSelection() throws Throwable {
        TextImportPlugin plugin = plugin();
        Instrumentation.ActivityMonitor cancelled = monitor(Activity.RESULT_CANCELED, null);
        Reply cancel = new Reply();
        try { open(plugin, cancel); await(cancel); assertNull(cancel.value); assertNull(cancel.error); }
        finally { getInstrumentation().removeMonitor(cancelled); }
        for (String kind : new String[] {"ok", "missing", "unsupported", "open-error"}) {
            Intent selected = new Intent().setData(uri(kind)).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            Instrumentation.ActivityMonitor picked = monitor(Activity.RESULT_OK, selected);
            Reply reply = new Reply();
            try {
                open(plugin, reply); await(reply);
                if ("ok".equals(kind)) {
                    assertNull(reply.error);
                    Map<?, ?> document = (Map<?, ?>) reply.value;
                    assertEquals("sample.MaRkDoWn", document.get("name"));
                    assertTrue(Arrays.equals(ImportTestProvider.BYTES, (byte[]) document.get("bytes")));
                } else { assertEquals("read_failed", reply.error); }
            } finally { getInstrumentation().removeMonitor(picked); }
        }
    }

    public void testBusyDetachAndLateResultCannotCompleteAgain() throws Throwable {
        TextImportPlugin plugin = plugin();
        // Hold the synthetic activity result until after detach.
        Instrumentation.ActivityMonitor held = monitor(Activity.RESULT_CANCELED, null);
        Reply pending = new Reply();
        Reply busy = new Reply();
        try {
            runTestOnUiThread(() -> {
                plugin.onMethodCall(new MethodCall("open", null), pending);
                plugin.onMethodCall(new MethodCall("open", null), busy);
                engine().getPlugins().remove(TextImportPlugin.class);
            });
            await(pending); await(busy);
            assertEquals("detached", pending.error);
            assertEquals("busy", busy.error);
            getInstrumentation().waitForIdleSync();
            assertEquals(1, pending.completions.get());
            Reply detached = new Reply();
            open(plugin, detached); await(detached);
            assertEquals("detached", detached.error);
            runTestOnUiThread(() -> engine().getPlugins().add(new TextImportPlugin()));
            Reply fresh = new Reply();
            open(plugin(), fresh); await(fresh);
            assertNull(fresh.error);
            assertNull(fresh.value);
            assertEquals(1, pending.completions.get());
        } finally { getInstrumentation().removeMonitor(held); }
    }
}
