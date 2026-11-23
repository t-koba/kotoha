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
import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.lang.reflect.Proxy;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;
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


    /** Synthetic provider that serves fixed bytes for explicit integrity checks. */
    private static final class IntegrityPackageProvider extends ContentProvider {
        final Map<String, byte[]> contents = new HashMap<>();
        final AtomicInteger opens = new AtomicInteger();
        final AtomicReference<ParcelFileDescriptor> lastDescriptor =
                new AtomicReference<>();
        volatile CountDownLatch openEntered;
        volatile CountDownLatch releaseOpen;

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
            MatrixCursor cursor = new MatrixCursor(projection);
            if ("root".equals(DocumentsContract.getDocumentId(uri))) {
                for (String name : contents.keySet()) {
                    addRow(cursor, projection, "root/" + name, name,
                            "application/octet-stream");
                }
            }
            return cursor;
        }

        private static void addRow(
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
        public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
            opens.incrementAndGet();
            CountDownLatch entered = openEntered;
            if (entered != null) {
                entered.countDown();
                CountDownLatch release = releaseOpen;
                if (release != null) {
                    try {
                        // Bounded block so a cancellation test cannot hang the runner.
                        release.await(10, TimeUnit.SECONDS);
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                    }
                }
            }
            String id = DocumentsContract.getDocumentId(uri);
            String name = id.startsWith("root/") ? id.substring("root/".length()) : "";
            byte[] data = contents.get(name);
            if (data == null) throw new FileNotFoundException("synthetic file missing");
            try {
                File file = File.createTempFile("kotoha-integrity", ".bin",
                        getContext().getCacheDir());
                file.deleteOnExit();
                FileOutputStream out = new FileOutputStream(file);
                try {
                    out.write(data);
                } finally {
                    out.close();
                }
                ParcelFileDescriptor descriptor =
                        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY);
                lastDescriptor.set(descriptor);
                return descriptor;
            } catch (Exception e) {
                throw new FileNotFoundException("synthetic fixture: " + e);
            }
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

    private static byte[] knownBytes(int length) {
        byte[] data = new byte[length];
        for (int i = 0; i < length; i++) {
            data[i] = (byte) ((i * 31 + 7) & 0xff);
        }
        return data;
    }

    private static String digest(byte[] data) throws Exception {
        byte[] hash = MessageDigest.getInstance("SHA-256").digest(data);
        StringBuilder out = new StringBuilder();
        for (byte value : hash) {
            out.append(String.format("%02x", value & 0xff));
        }
        return out.toString();
    }

    private static Map<String, Object> declaration(String path, long size, String sha256) {
        Map<String, Object> entry = new HashMap<>();
        entry.put("path", path);
        entry.put("sizeBytes", size);
        entry.put("sha256", sha256);
        return entry;
    }

    private static Map<String, Object> declaration(String path, byte[] data) throws Exception {
        return declaration(path, data.length, digest(data));
    }

    private static Map<String, Object> verifyArgs(List<Map<String, Object>> files) {
        Map<String, Object> args = new HashMap<>();
        args.put("files", files);
        return args;
    }

    private IntegrityPackageProvider installIntegrityProvider() {
        IntegrityPackageProvider provider = new IntegrityPackageProvider();
        ProviderInfo info = new ProviderInfo();
        info.authority = AUTHORITY;
        provider.attachInfo(getInstrumentation().getTargetContext(), info);
        return provider;
    }

    private ModelPackagePlugin selectedPlugin(
            CapturingActivity activity,
            ContentResolver resolver) throws Throwable {
        activity.testResolver = resolver;
        ModelPackagePlugin plugin = new ModelPackagePlugin();
        runTestOnUiThread(() -> plugin.onAttachedToActivity(binding(activity)));
        Reply select = new Reply();
        call(plugin, "selectDirectory", null, select);
        Uri tree = DocumentsContract.buildTreeDocumentUri(AUTHORITY, "root");
        Intent data = new Intent().setData(tree)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        final int code = activity.requestCode;
        runTestOnUiThread(() -> plugin.onActivityResult(code, Activity.RESULT_OK, data));
        await(select);
        assertEquals(Boolean.TRUE, select.value);
        return plugin;
    }

    /** Success requires exact declared length and digest on every declared file. */
    public void testVerifyFilesSucceedsOnlyForExactSizeAndDigest() throws Throwable {
        IntegrityPackageProvider provider = installIntegrityProvider();
        byte[] weights = knownBytes(9000); // crosses the fixed streaming buffer
        byte[] config = knownBytes(5);
        provider.contents.put("weights/model.gguf", weights);
        provider.contents.put("config.json", config);
        ContentResolver resolver = ContentResolver.wrap(provider);
        CapturingActivity activity = new CapturingActivity();
        ModelPackagePlugin plugin = selectedPlugin(activity, resolver);
        try {
            List<Map<String, Object>> files = new ArrayList<>();
            files.add(declaration("weights/model.gguf", weights));
            files.add(declaration("config.json", config));
            Reply reply = new Reply();
            call(plugin, "verifyFiles", verifyArgs(files), reply);
            await(reply);
            assertNull(reply.error);
            assertEquals(Boolean.TRUE, reply.value);
            assertTrue("reply is status only, never file bytes",
                    reply.value instanceof Boolean);
            assertEquals(2, provider.opens.get());

            List<Map<String, Object>> wrong = new ArrayList<>(files);
            wrong.set(1, declaration("config.json", config.length, "0".repeat(64)));
            Reply mismatch = new Reply();
            call(plugin, "verifyFiles", verifyArgs(wrong), mismatch);
            await(mismatch);
            assertNull(mismatch.error);
            assertEquals(Boolean.FALSE, mismatch.value);
        } finally {
            runTestOnUiThread(plugin::onDetachedFromActivity);
        }
    }

    /** Oversized and truncated streams are rejected even with a matching prefix. */
    public void testVerifyFilesRejectsSizeMismatchAndExtraBytes() throws Throwable {
        IntegrityPackageProvider provider = installIntegrityProvider();
        byte[] exact = knownBytes(8192);
        byte[] extra = knownBytes(8193); // exact declared length plus one byte
        provider.contents.put("weights/model.gguf", exact);
        provider.contents.put("weights/extra.gguf", extra);
        ContentResolver resolver = ContentResolver.wrap(provider);
        CapturingActivity activity = new CapturingActivity();
        ModelPackagePlugin plugin = selectedPlugin(activity, resolver);
        try {
            List<Map<String, Object>> tooShort = new ArrayList<>();
            tooShort.add(declaration("weights/model.gguf", 8191, digest(exact)));
            Reply shortReply = new Reply();
            call(plugin, "verifyFiles", verifyArgs(tooShort), shortReply);
            await(shortReply);
            assertFalse(Boolean.TRUE.equals(shortReply.value));

            List<Map<String, Object>> tooLong = new ArrayList<>();
            tooLong.add(declaration("weights/model.gguf", 8193, digest(exact)));
            Reply longReply = new Reply();
            call(plugin, "verifyFiles", verifyArgs(tooLong), longReply);
            await(longReply);
            assertFalse(Boolean.TRUE.equals(longReply.value));

            List<Map<String, Object>> extraByte = new ArrayList<>();
            extraByte.add(declaration("weights/extra.gguf", 8192, digest(extra)));
            Reply extraReply = new Reply();
            call(plugin, "verifyFiles", verifyArgs(extraByte), extraReply);
            await(extraReply);
            assertFalse("extra byte past declared length is detected",
                    Boolean.TRUE.equals(extraReply.value));
        } finally {
            runTestOnUiThread(plugin::onDetachedFromActivity);
        }
    }

    /** No selection, invalid declarations, and detach all fail closed. */
    public void testVerifyFilesFailsClosedWithoutSelectionOnInvalidInputAndAfterDetach()
            throws Throwable {
        IntegrityPackageProvider provider = installIntegrityProvider();
        provider.contents.put("weights/model.gguf", knownBytes(16));
        ContentResolver resolver = ContentResolver.wrap(provider);
        CapturingActivity activity = new CapturingActivity();
        ModelPackagePlugin plugin = new ModelPackagePlugin();
        runTestOnUiThread(() -> plugin.onAttachedToActivity(binding(activity)));
        List<Map<String, Object>> files = new ArrayList<>();
        files.add(declaration("weights/model.gguf", 16, digest(knownBytes(16))));
        Reply noSelection = new Reply();
        call(plugin, "verifyFiles", verifyArgs(files), noSelection);
        await(noSelection);
        assertEquals("cancelled", noSelection.error);

        runTestOnUiThread(() -> plugin.onDetachedFromActivity());
        ModelPackagePlugin selected = selectedPlugin(activity, resolver);
        try {
            for (Map<String, Object> bad : new Map[] {
                    declaration("../weights/model.gguf", 16, digest(knownBytes(16))),
                    declaration("weights/model.gguf", 0, digest(knownBytes(16))),
                    declaration("weights/model.gguf", 16, "A".repeat(64)),
                    declaration("weights/model.gguf", 16, "abc"),
                    declaration("weights/model.gguf",
                            ModelPackagePlugin.MAX_VERIFY_FILE_BYTES + 1,
                            digest(knownBytes(16))),
            }) {
                List<Map<String, Object>> invalid = new ArrayList<>();
                invalid.add(bad);
                Reply reply = new Reply();
                call(selected, "verifyFiles", verifyArgs(invalid), reply);
                await(reply);
                assertEquals("invalid declaration fails closed", "invalid", reply.error);
            }
            Reply empty = new Reply();
            call(selected, "verifyFiles", verifyArgs(new ArrayList<>()), empty);
            await(empty);
            assertEquals("invalid", empty.error);
        } finally {
            runTestOnUiThread(selected::onDetachedFromActivity);
        }
        Reply afterDetach = new Reply();
        call(selected, "verifyFiles", verifyArgs(files), afterDetach);
        await(afterDetach);
        assertEquals("detached", afterDetach.error);
    }

    /** Release/detach stop an in-flight stream, close it, and keep the slot busy. */
    public void testVerifyFilesReleaseAndDetachCancelInFlightStream() throws Throwable {
        for (boolean detach : new boolean[] {false, true}) {
            IntegrityPackageProvider provider = installIntegrityProvider();
            provider.contents.put("weights/model.gguf", knownBytes(9000));
            provider.openEntered = new CountDownLatch(1);
            provider.releaseOpen = new CountDownLatch(1);
            ContentResolver resolver = ContentResolver.wrap(provider);
            CapturingActivity activity = new CapturingActivity();
            ModelPackagePlugin plugin = selectedPlugin(activity, resolver);
            Reply verify = new Reply();
            List<Map<String, Object>> files = new ArrayList<>();
            files.add(declaration("weights/model.gguf", knownBytes(9000)));
            try {
                call(plugin, "verifyFiles", verifyArgs(files), verify);
                assertTrue("provider open started",
                        provider.openEntered.await(10, TimeUnit.SECONDS));
                if (detach) {
                    runTestOnUiThread(plugin::onDetachedFromActivity);
                } else {
                    Reply release = new Reply();
                    call(plugin, "release", null, release);
                    await(release);
                    assertNull(release.error);
                }
                Bundle args = ((android.test.InstrumentationTestRunner) getInstrumentation())
                        .getArguments();
                long limit = Math.min(1000L,
                        Long.parseLong(args.getString("axTimeoutMillis", "10000")));
                assertTrue("cancellation replies promptly while provider is held",
                        verify.done.await(limit, TimeUnit.MILLISECONDS));
                assertEquals(detach ? "detached" : "released", verify.error);
                assertEquals(1, verify.completions.get());

                Reply busy = new Reply();
                call(plugin, "selectDirectory", null, busy);
                await(busy);
                assertEquals("busy", busy.error);

                // The fixture publishes its descriptor only after the blocked
                // open returns; release it and confirm the late stream is closed.
                provider.releaseOpen.countDown();
                ParcelFileDescriptor descriptor = null;
                long deadline = SystemClock.uptimeMillis() + 5000;
                while (descriptor == null && SystemClock.uptimeMillis() < deadline) {
                    descriptor = provider.lastDescriptor.get();
                    if (descriptor == null) Thread.sleep(20);
                }
                assertNotNull("fixture descriptor was opened", descriptor);
                while (descriptor.getFd() >= 0 && SystemClock.uptimeMillis() < deadline) {
                    Thread.sleep(20);
                }
                assertEquals("late cancelled stream is closed", -1, descriptor.getFd());
            } finally {
                provider.releaseOpen.countDown();
                runTestOnUiThread(plugin::onDetachedFromActivity);
            }
        }
    }
}
