package org.kotoha.app;

import android.app.Activity;
import android.content.ContentProvider;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Intent;
import android.content.pm.ProviderInfo;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.Bundle;
import android.provider.DocumentsContract;
import android.test.ActivityInstrumentationTestCase2;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.StandardMethodCodec;
import java.lang.reflect.Proxy;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Synthetic SAF selection and path checks for the terms-review increment.
 * It does not exercise live DocumentsUI/provider behavior or read model weights.
 */
@SuppressWarnings("deprecation")
public final class ModelPackageTest extends ActivityInstrumentationTestCase2<MainActivity> {
    private static final String AUTHORITY = "org.kotoha.app.test.modeldocuments";

    public ModelPackageTest() {
        super(MainActivity.class);
    }

    private static final class Reply implements MethodChannel.Result {
        final CountDownLatch done = new CountDownLatch(1);
        final AtomicInteger completions = new AtomicInteger();
        Object value;
        String error;

        @Override
        public void success(Object value) {
            this.value = value;
            complete();
        }

        @Override
        public void error(String code, String message, Object details) {
            error = code;
            complete();
        }

        @Override
        public void notImplemented() {
            error = "notImplemented";
            complete();
        }

        private void complete() {
            completions.incrementAndGet();
            done.countDown();
        }
    }

    private static final class CapturingActivity extends Activity {
        Intent intent;
        int requestCode = -1;

        @Override
        public void startActivityForResult(Intent intent, int requestCode) {
            this.intent = intent;
            this.requestCode = requestCode;
        }
    }

    /** Minimal synthetic DocumentsProvider response for nested path traversal. */
    private static final class PackageProvider extends ContentProvider {
        @Override
        public boolean onCreate() {
            return true;
        }

        @Override
        public Cursor query(
                Uri uri,
                String[] projection,
                String selection,
                String[] selectionArgs,
                String sortOrder) {
            String parent = DocumentsContract.getDocumentId(uri);
            MatrixCursor cursor = new MatrixCursor(projection);
            if ("root".equals(parent)) {
                add(cursor, projection, "root/license", "license",
                        DocumentsContract.Document.MIME_TYPE_DIR);
                add(cursor, projection, "root/weights.bin", "weights.bin",
                        "application/octet-stream");
            } else if ("root/license".equals(parent)) {
                add(cursor, projection, "root/license/terms.txt", "terms.txt", "text/plain");
            }
            return cursor;
        }

        private static void add(
                MatrixCursor cursor,
                String[] projection,
                String id,
                String name,
                String mimeType) {
            Object[] values = new Object[projection.length];
            for (int i = 0; i < projection.length; i++) {
                if (DocumentsContract.Document.COLUMN_DOCUMENT_ID.equals(projection[i])) {
                    values[i] = id;
                } else if (DocumentsContract.Document.COLUMN_DISPLAY_NAME.equals(projection[i])) {
                    values[i] = name;
                } else if (DocumentsContract.Document.COLUMN_MIME_TYPE.equals(projection[i])) {
                    values[i] = mimeType;
                }
            }
            cursor.addRow(values);
        }

        @Override
        public String getType(Uri uri) {
            return null;
        }

        @Override
        public Uri insert(Uri uri, ContentValues values) {
            return null;
        }

        @Override
        public int delete(Uri uri, String selection, String[] selectionArgs) {
            return 0;
        }

        @Override
        public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) {
            return 0;
        }
    }

    private static ActivityPluginBinding binding(Activity activity) {
        return (ActivityPluginBinding) Proxy.newProxyInstance(
                ActivityPluginBinding.class.getClassLoader(),
                new Class<?>[] {ActivityPluginBinding.class},
                (proxy, method, args) -> "getActivity".equals(method.getName()) ? activity : null);
    }

    private void await(Reply reply) throws Exception {
        Bundle args = ((android.test.InstrumentationTestRunner) getInstrumentation()).getArguments();
        long timeout = Long.parseLong(args.getString("axTimeoutMillis", "10000"));
        assertTrue("Native model-package step completed",
                reply.done.await(timeout, TimeUnit.MILLISECONDS));
        assertEquals(1, reply.completions.get());
    }

    private void call(
            ModelPackagePlugin plugin,
            String method,
            Map<String, Object> args,
            Reply reply) throws Throwable {
        runTestOnUiThread(() -> {
            java.nio.ByteBuffer encoded = StandardMethodCodec.INSTANCE.encodeMethodCall(
                    new MethodCall(method, args));
            encoded.flip();
            plugin.onMethodCall(StandardMethodCodec.INSTANCE.decodeMethodCall(encoded), reply);
        });
    }

    public void testSafePathAcceptsOnlyRelativeSegments() {
        assertTrue(ModelPackagePlugin.isSafePath("model_manifest.json"));
        assertTrue(ModelPackagePlugin.isSafePath("license/terms.txt"));
        for (String bad : new String[] {
                "", "/abs.txt", "../terms.txt", "a/../b", "a/./b", "a//b",
                "a\\b", "C:terms.txt", "a:b", ".", "..", "a/.", "a/..",
                "NUL.txt", "dir/name. ", "bad" + (char) 1 + "name", "a?.txt"}) {
            assertFalse("Rejected: " + bad, ModelPackagePlugin.isSafePath(bad));
        }
    }

    public void testResolveRejectsUnsafePathBeforeQuery() {
        try {
            ModelPackagePlugin.resolveDocument(
                    getInstrumentation().getTargetContext().getContentResolver(),
                    Uri.parse("content://org.kotoha.app.test.documents/tree/root"),
                    "../terms.txt");
            fail("unsafe path");
        } catch (IllegalArgumentException expected) {
            // Expected: no provider query is needed for an invalid path.
        }
    }

    public void testResolveWalksNestedDirectoryAndReturnsTermsFile() {
        PackageProvider provider = new PackageProvider();
        ProviderInfo info = new ProviderInfo();
        info.authority = AUTHORITY;
        provider.attachInfo(getInstrumentation().getTargetContext(), info);
        ContentResolver resolver = ContentResolver.wrap(provider);
        Uri tree = DocumentsContract.buildTreeDocumentUri(AUTHORITY, "root");

        Uri file = ModelPackagePlugin.resolveDocument(resolver, tree, "license/terms.txt");

        assertEquals("root/license/terms.txt", DocumentsContract.getDocumentId(file));
    }

    public void testResolveFailsClosedOnUnresolvableTree() {
        try {
            ModelPackagePlugin.resolveDocument(
                    getInstrumentation().getTargetContext().getContentResolver(),
                    Uri.parse("content://org.kotoha.app.test.documents/tree/missing"),
                    "license/terms.txt");
            fail("missing tree");
        } catch (Exception expected) {
            // Provider failure and incomplete metadata must fail closed.
        }
    }

    public void testSelectDirectoryRequestsTemporaryReadOnlyGrant() throws Throwable {
        ModelPackagePlugin plugin = new ModelPackagePlugin();
        CapturingActivity activity = new CapturingActivity();
        runTestOnUiThread(() -> plugin.onAttachedToActivity(binding(activity)));
        Reply reply = new Reply();
        call(plugin, "selectDirectory", null, reply);

        assertNotNull(activity.intent);
        assertEquals(Intent.ACTION_OPEN_DOCUMENT_TREE, activity.intent.getAction());
        assertTrue((activity.intent.getFlags() & Intent.FLAG_GRANT_READ_URI_PERMISSION) != 0);
        assertEquals(0, activity.intent.getFlags() & Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
        assertEquals(0, activity.intent.getFlags() & Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
        assertTrue(activity.requestCode >= 0);

        int code = activity.requestCode;
        runTestOnUiThread(() -> plugin.onActivityResult(code, Activity.RESULT_CANCELED, null));
        await(reply);
        assertEquals(Boolean.FALSE, reply.value);
        runTestOnUiThread(plugin::onDetachedFromActivity);
    }

    public void testSelectionAcceptsReadOnlyTreeAndRejectsWriteGrant() throws Throwable {
        for (boolean grantWrite : new boolean[] {false, true}) {
            ModelPackagePlugin plugin = new ModelPackagePlugin();
            CapturingActivity activity = new CapturingActivity();
            runTestOnUiThread(() -> plugin.onAttachedToActivity(binding(activity)));
            Reply reply = new Reply();
            call(plugin, "selectDirectory", null, reply);

            Intent data = new Intent().setData(DocumentsContract.buildTreeDocumentUri(AUTHORITY, "root"));
            data.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            if (grantWrite) data.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
            int code = activity.requestCode;
            runTestOnUiThread(() -> plugin.onActivityResult(code, Activity.RESULT_OK, data));
            await(reply);
            assertEquals(Boolean.valueOf(!grantWrite), reply.value);
            runTestOnUiThread(plugin::onDetachedFromActivity);
        }
    }

    public void testReadWithoutSelectionFailsClosed() throws Throwable {
        ModelPackagePlugin plugin = new ModelPackagePlugin();
        CapturingActivity activity = new CapturingActivity();
        runTestOnUiThread(() -> plugin.onAttachedToActivity(binding(activity)));
        Reply reply = new Reply();
        Map<String, Object> args = new HashMap<>();
        args.put("path", "license/terms.txt");
        args.put("maxBytes", 1024 * 1024);
        call(plugin, "readFile", args, reply);
        await(reply);
        assertEquals("invalid", reply.error);
        runTestOnUiThread(plugin::onDetachedFromActivity);
    }
}
