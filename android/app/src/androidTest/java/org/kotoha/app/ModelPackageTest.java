package org.kotoha.app;

import android.app.Activity;
import android.content.ContentProvider;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Intent;
import android.content.pm.ProviderInfo;
import android.content.res.AssetFileDescriptor;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.Bundle;
import android.os.ParcelFileDescriptor;
import android.os.SystemClock;
import android.provider.DocumentsContract;
import android.test.ActivityInstrumentationTestCase2;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.StandardMethodCodec;
import java.io.FileNotFoundException;
import java.lang.reflect.Proxy;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Synthetic SAF selection, lifecycle, path, and cancellation checks for terms review.
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
        int revocationCalls;
        ContentResolver testResolver;

        @Override
        public ContentResolver getContentResolver() {
            if (testResolver != null) {
                return testResolver;
            }
            return super.getContentResolver();
        }

        @Override
        public void revokeUriPermission(Uri uri, int modeFlags) {
            revocationCalls++;
        }

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

    /** Synthetic provider whose first query blocks until released; never serves weights. */
    private static final class BlockingPackageProvider extends ContentProvider {
        final CountDownLatch entered = new CountDownLatch(1);
        final CountDownLatch releaseQuery = new CountDownLatch(1);
        final CountDownLatch queryReturned = new CountDownLatch(1);
        volatile MatrixCursor returnedCursor;
        final AtomicInteger queries = new AtomicInteger();
        final AtomicInteger opens = new AtomicInteger();

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
            int n = queries.incrementAndGet();
            if (n == 1) {
                entered.countDown();
                try {
                    // Bounded block: the test releases this after cancelling.
                    releaseQuery.await(10, TimeUnit.SECONDS);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
                String parent;
                try {
                    parent = DocumentsContract.getDocumentId(uri);
                } catch (Exception e) {
                    parent = "";
                }
                String[] cols = projection != null ? projection : new String[0];
                MatrixCursor cursor = new MatrixCursor(cols);
                if ("root".equals(parent)) {
                    addRow(cursor, projection, "root/license", "license",
                            DocumentsContract.Document.MIME_TYPE_DIR);
                }
                returnedCursor = cursor;
                queryReturned.countDown();
                return cursor;
            }
            String[] cols = projection != null ? projection : new String[0];
            return new MatrixCursor(cols);
        }

        private static void addRow(
                MatrixCursor cursor,
                String[] projection,
                String id,
                String name,
                String mimeType) {
            if (projection == null) {
                return;
            }
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
        public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
            opens.incrementAndGet();
            throw new FileNotFoundException("synthetic: no weights");
        }

        @Override
        public AssetFileDescriptor openAssetFile(Uri uri, String mode) throws FileNotFoundException {
            opens.incrementAndGet();
            throw new FileNotFoundException("synthetic: no weights");
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
            assertEquals("never revoke cross-package SAF grants", 0, activity.revocationCalls);
            if (!grantWrite) {
                Reply release = new Reply();
                call(plugin, "release", null, release);
                await(release);
                Reply afterRelease = new Reply();
                Map<String, Object> readArgs = new HashMap<>();
                readArgs.put("path", "license/terms.txt");
                readArgs.put("maxBytes", 1024 * 1024);
                call(plugin, "readFile", readArgs, afterRelease);
                await(afterRelease);
                assertEquals("invalid", afterRelease.error);
            }
            runTestOnUiThread(plugin::onDetachedFromActivity);
            assertEquals(0, activity.revocationCalls);
        }
    }

    public void testReselectionAndDetachDropTreeReferenceWithoutGlobalRevoke() throws Throwable {
        ModelPackagePlugin plugin = new ModelPackagePlugin();
        CapturingActivity activity = new CapturingActivity();
        runTestOnUiThread(() -> plugin.onAttachedToActivity(binding(activity)));
        Uri first = DocumentsContract.buildTreeDocumentUri(AUTHORITY, "first");
        Reply initial = new Reply();
        call(plugin, "selectDirectory", null, initial);
        final int initialCode = activity.requestCode;
        runTestOnUiThread(() -> plugin.onActivityResult(initialCode, Activity.RESULT_OK,
                new Intent().setData(first).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)));
        await(initial);

        Reply next = new Reply();
        call(plugin, "selectDirectory", null, next);
        assertEquals(0, activity.revocationCalls);
        Reply duringReselection = new Reply();
        Map<String, Object> readArgs = new HashMap<>();
        readArgs.put("path", "license/terms.txt");
        readArgs.put("maxBytes", 1024 * 1024);
        call(plugin, "readFile", readArgs, duringReselection);
        await(duringReselection);
        assertEquals("invalid", duringReselection.error);
        Uri second = DocumentsContract.buildTreeDocumentUri(AUTHORITY, "second");
        final int secondCode = activity.requestCode;
        runTestOnUiThread(() -> plugin.onActivityResult(secondCode, Activity.RESULT_OK,
                new Intent().setData(second).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)));
        await(next);
        runTestOnUiThread(plugin::onDetachedFromActivity);
        Reply afterDetach = new Reply();
        call(plugin, "readFile", readArgs, afterDetach);
        await(afterDetach);
        assertEquals("invalid", afterDetach.error);
        assertEquals("do not revoke matching grants owned by other packages",
                0, activity.revocationCalls);
    }

    public void testRejectedContentResultIsNotRetainedOrGloballyRevoked() throws Throwable {
        ModelPackagePlugin plugin = new ModelPackagePlugin();
        CapturingActivity activity = new CapturingActivity();
        runTestOnUiThread(() -> plugin.onAttachedToActivity(binding(activity)));
        Reply reply = new Reply();
        call(plugin, "selectDirectory", null, reply);
        Uri invalid = Uri.parse("content://" + AUTHORITY + "/not-a-tree");
        int code = activity.requestCode;
        Intent rejected = new Intent().setData(invalid).addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
        runTestOnUiThread(() -> plugin.onActivityResult(code, Activity.RESULT_OK, rejected));
        await(reply);
        assertEquals(Boolean.FALSE, reply.value);
        assertEquals("rejected URI is not retained or globally revoked",
                0, activity.revocationCalls);
        runTestOnUiThread(plugin::onDetachedFromActivity);
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

    public void testCancelledBlockedQueryRepliesImmediatelyAndFreesSlotOnce() throws Throwable {
        // Synthetic cancellation check: the first provider query blocks on a latch,
        // release cancels the read, and no later query or stream open may follow.
        // It does not exercise live DocumentsUI/provider behavior or read model weights.
        BlockingPackageProvider provider = new BlockingPackageProvider();
        ProviderInfo info = new ProviderInfo();
        info.authority = AUTHORITY;
        provider.attachInfo(getInstrumentation().getTargetContext(), info);
        ContentResolver resolver = ContentResolver.wrap(provider);

        ModelPackagePlugin plugin = new ModelPackagePlugin();
        CapturingActivity activity = new CapturingActivity();
        activity.testResolver = resolver;
        runTestOnUiThread(() -> plugin.onAttachedToActivity(binding(activity)));

        Reply select = new Reply();
        call(plugin, "selectDirectory", null, select);
        Uri tree = DocumentsContract.buildTreeDocumentUri(AUTHORITY, "root");
        Intent data =
                new Intent().setData(tree).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        final int selectCode = activity.requestCode;
        runTestOnUiThread(() -> plugin.onActivityResult(selectCode, Activity.RESULT_OK, data));
        await(select);
        assertEquals(Boolean.TRUE, select.value);

        Reply read = new Reply();
        Map<String, Object> args = new HashMap<>();
        args.put("path", "license/terms.txt");
        args.put("maxBytes", 1024 * 1024);
        call(plugin, "readFile", args, read);
        assertTrue("first provider query started",
                provider.entered.await(10, TimeUnit.SECONDS));

        Reply release = new Reply();
        call(plugin, "release", null, release);
        await(release);
        assertNull(release.error);
        Bundle runnerArgs = ((android.test.InstrumentationTestRunner) getInstrumentation())
                .getArguments();
        long promptLimitMillis = Math.min(1000L,
                Long.parseLong(runnerArgs.getString("axTimeoutMillis", "10000")));
        try {
            // Reply quickly while the provider is still held by the test latch.
            assertTrue("cancel reply is prompt while provider query is blocked",
                    read.done.await(promptLimitMillis, TimeUnit.MILLISECONDS));
            assertEquals("released", read.error);
            assertEquals(1, read.completions.get());
            assertEquals(1L, provider.queryReturned.getCount());

            // Slot remains busy until the blocked query returns.
            Reply busyProbe = new Reply();
            call(plugin, "selectDirectory", null, busyProbe);
            await(busyProbe);
            assertEquals("busy", busyProbe.error);
            assertEquals(0, provider.opens.get());
        } finally {
            provider.releaseQuery.countDown();
        }
        assertTrue("blocked provider query returned",
                provider.queryReturned.await(10, TimeUnit.SECONDS));

        // Observe slot release through the next public operation, not private state.
        long deadline = SystemClock.uptimeMillis() + 10000;
        Reply after;
        while (true) {
            if (SystemClock.uptimeMillis() > deadline) {
                fail("cancelled read slot was not freed");
            }
            after = new Reply();
            call(plugin, "selectDirectory", null, after);
            if (!after.done.await(100, TimeUnit.MILLISECONDS)) {
                break;
            }
            assertEquals("busy", after.error);
        }

        // No later query or stream open after cancellation, and one reply only.
        assertEquals(1, provider.queries.get());
        assertEquals(0, provider.opens.get());
        assertEquals(1, read.completions.get());
        assertNotNull(provider.returnedCursor);
        assertTrue("cursor is closed after cancelled resolution",
                provider.returnedCursor.isClosed());

        // Slot is freed: the next selection is accepted instead of reporting busy.
        assertNull(after.error);
        final int afterCode = activity.requestCode;
        runTestOnUiThread(() -> plugin.onActivityResult(afterCode, Activity.RESULT_CANCELED, null));
        await(after);
        assertEquals(Boolean.FALSE, after.value);
        runTestOnUiThread(plugin::onDetachedFromActivity);
    }
}
