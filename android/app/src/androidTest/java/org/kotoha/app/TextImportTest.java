package org.kotoha.app;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.ContentResolver;
import android.content.Intent;
import android.net.Uri;
import android.test.ActivityInstrumentationTestCase2;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.StandardMethodCodec;
import java.lang.reflect.Proxy;
import java.util.Arrays;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
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
    private static final class CapturingActivity extends Activity {
        int requestCode = -1;
        @Override public void startActivityForResult(Intent intent, int requestCode) {
            this.requestCode = requestCode;
        }
    }
    private static ActivityPluginBinding binding(Activity activity) {
        return (ActivityPluginBinding) Proxy.newProxyInstance(
                ActivityPluginBinding.class.getClassLoader(),
                new Class<?>[] {ActivityPluginBinding.class},
                (proxy, method, args) -> "getActivity".equals(method.getName()) ? activity : null);
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

    public void testOptInNativeReadMemoryProfile() throws Exception {
        android.os.Bundle args = ((android.test.InstrumentationTestRunner) getInstrumentation()).getArguments();
        String configured = args.getString("profileBytes", "");
        if (configured.isEmpty()) return; // Normal CI does not run a large profile.
        int requested = Integer.parseInt(configured);
        assertTrue(requested >= 1024);
        assertTrue("Profile fixture is bounded to 16 MiB", requested <= 16 * 1024 * 1024);
        Uri selected = uri("ok").buildUpon().appendQueryParameter("profileBytes", configured).build();
        String before = memoryStatus();
        long start = System.nanoTime();
        Map<String, Object> result = TextImportPlugin.readDocument(
                getInstrumentation().getContext().getContentResolver(), selected);
        byte[] bytes = (byte[]) result.get("bytes");
        assertTrue(bytes.length > 0 && bytes.length <= requested);
        android.util.Log.i("KotohaImportProfile", "native-read bytes=" + bytes.length
                + " nanos=" + (System.nanoTime() - start) + " sdk=" + android.os.Build.VERSION.SDK_INT
                + " before=" + before + " after=" + memoryStatus());
    }

    private static String memoryStatus() throws Exception {
        StringBuilder result = new StringBuilder();
        try (java.io.BufferedReader reader = new java.io.BufferedReader(new java.io.FileReader("/proc/self/status"))) {
            String line;
            while ((line = reader.readLine()) != null) {
                if (line.startsWith("VmRSS:") || line.startsWith("VmHWM:")) result.append(line).append(';');
            }
        }
        return result.toString();
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

    public void testRequestCodesRecycleAfterCompletedCycles() {
        ActivityRequestCodePool codes = new ActivityRequestCodePool(0xffff);
        int first = -1;
        for (int index = 0; index <= 0x10000; index++) {
            Integer code = codes.acquire();
            assertNotNull("Request code available at cycle " + index, code);
            if (index == 0) {
                first = code;
                assertEquals(0xffff, first);
            } else if (index == 0x10000) {
                assertEquals("Completed request codes are reusable after wrap", first, code.intValue());
            }
            codes.release(code);
        }
    }

    public void testAbandonedCodesRemainReservedUntilTheirLateResult() {
        ActivityRequestCodePool codes = new ActivityRequestCodePool(0xffff);
        Integer abandoned = codes.acquire();
        assertNotNull(abandoned);
        codes.abandon(abandoned);

        for (int index = 0; index < 0x10000; index++) {
            Integer code = codes.acquire();
            assertNotNull("Other completed requests remain available", code);
            assertTrue("Outstanding late result keeps its code reserved", code.intValue() != abandoned);
            codes.release(code);
        }
        assertTrue("Matching late result clears the tombstone", codes.consumeAbandoned(abandoned));

        boolean reused = false;
        for (int index = 0; index < 0x10000; index++) {
            Integer code = codes.acquire();
            assertNotNull(code);
            if (code.intValue() == abandoned) reused = true;
            codes.release(code);
        }
        assertTrue("Consumed tombstone returns its code to the pool", reused);
    }

    public void testBusyDetachAndLateResultCannotCompleteNewRequest() throws Throwable {
        TextImportPlugin detachedPlugin = new TextImportPlugin();
        CapturingActivity detachedActivity = new CapturingActivity();
        runTestOnUiThread(() -> detachedPlugin.onAttachedToActivity(binding(detachedActivity)));
        Reply detached = new Reply();
        Reply busy = new Reply();
        open(detachedPlugin, detached);
        open(detachedPlugin, busy);
        int retiredCode = detachedActivity.requestCode;
        assertTrue("Picker request code captured", retiredCode >= 0);

        runTestOnUiThread(detachedPlugin::onDetachedFromActivity);
        await(detached);
        await(busy);
        assertEquals("detached", detached.error);
        assertEquals("busy", busy.error);

        TextImportPlugin freshPlugin = new TextImportPlugin();
        CapturingActivity freshActivity = new CapturingActivity();
        runTestOnUiThread(() -> freshPlugin.onAttachedToActivity(binding(freshActivity)));
        Reply fresh = new Reply();
        open(freshPlugin, fresh);
        int freshCode = freshActivity.requestCode;
        assertTrue("New request gets a different code while the old result is outstanding",
                freshCode >= 0 && freshCode != retiredCode);

        AtomicBoolean lateHandled = new AtomicBoolean();
        runTestOnUiThread(() -> lateHandled.set(freshPlugin.onActivityResult(
                retiredCode, Activity.RESULT_CANCELED, null)));
        assertTrue("Late abandoned result is consumed", lateHandled.get());
        assertEquals("Late result does not finish the new request", 1L, fresh.done.getCount());

        AtomicBoolean currentHandled = new AtomicBoolean();
        runTestOnUiThread(() -> currentHandled.set(freshPlugin.onActivityResult(
                freshCode, Activity.RESULT_CANCELED, null)));
        assertTrue(currentHandled.get());
        await(fresh);
        assertNull(fresh.error);
        assertNull(fresh.value);
        runTestOnUiThread(freshPlugin::onDetachedFromActivity);
    }
}
