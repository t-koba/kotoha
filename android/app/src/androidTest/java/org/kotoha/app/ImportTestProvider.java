package org.kotoha.app;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.res.AssetFileDescriptor;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.util.concurrent.atomic.AtomicInteger;

/** Test APK only. Synthetic provider bytes live in a pipe, never a staged file. */
public final class ImportTestProvider extends ContentProvider {
    static final byte[] BYTES = new byte[] {65, 10, (byte) 0xe6, (byte) 0x97, (byte) 0xa5};
    // A complete multilingual UTF-8 fixture chunk divides all configured profile sizes.
    static final byte[] PROFILE_CHUNK = (new String(new char[1003]).replace('\0', 'a')
            + "日本語 مرحبا\n").getBytes(java.nio.charset.StandardCharsets.UTF_8);
    final AtomicInteger cursorsClosed = new AtomicInteger();
    final AtomicInteger streamsOpened = new AtomicInteger();
    final AtomicInteger streamsClosed = new AtomicInteger();

    @Override public boolean onCreate() { return true; }
    @Override public String getType(Uri uri) { return "text/plain"; }
    @Override public Cursor query(Uri uri, String[] projection, String selection,
            String[] args, String sortOrder) {
        MatrixCursor cursor = new MatrixCursor(new String[] {OpenableColumns.DISPLAY_NAME}) {
            @Override public void close() { super.close(); cursorsClosed.incrementAndGet(); }
        };
        String kind = uri.getLastPathSegment();
        cursor.addRow(new Object[] {"missing".equals(kind) ? null
                : "unsupported".equals(kind) ? "sample.pdf" : "sample.MaRkDoWn"});
        return cursor;
    }
    @Override public AssetFileDescriptor openAssetFile(Uri uri, String mode)
            throws FileNotFoundException {
        if ("open-error".equals(uri.getLastPathSegment())) throw new FileNotFoundException("fixture");
        try {
            ParcelFileDescriptor[] pipe = ParcelFileDescriptor.createPipe();
            streamsOpened.incrementAndGet();
            new Thread(() -> {
                try (ParcelFileDescriptor.AutoCloseOutputStream out =
                        new ParcelFileDescriptor.AutoCloseOutputStream(pipe[1])) {
                    String requested = uri.getQueryParameter("profileBytes");
                    if (requested == null) { out.write(BYTES); }
                    else {
                        int requestedBytes = Integer.parseInt(requested);
                        if (requestedBytes % PROFILE_CHUNK.length != 0) {
                            throw new IOException(
                                    "profileBytes must be divisible by the UTF-8 fixture chunk");
                        }
                        for (int n = 0; n < requestedBytes; n += PROFILE_CHUNK.length) {
                            out.write(PROFILE_CHUNK);
                        }
                    }
                } catch (IOException ignored) { /* Reader may reject or detach. */ }
            }).start();
            return new AssetFileDescriptor(pipe[0], 0, AssetFileDescriptor.UNKNOWN_LENGTH) {
                @Override public FileInputStream createInputStream() {
                    return new ParcelFileDescriptor.AutoCloseInputStream(pipe[0]) {
                        @Override public int read(byte[] bytes) throws IOException {
                            return read(bytes, 0, bytes.length);
                        }
                        @Override public int read(byte[] bytes, int offset, int length) throws IOException {
                            if ("stream-error".equals(uri.getLastPathSegment())) throw new IOException("fixture");
                            return super.read(bytes, offset, length);
                        }
                        @Override public void close() throws IOException {
                            try { super.close(); } finally { streamsClosed.incrementAndGet(); }
                        }
                    };
                }
            };
        } catch (IOException error) { throw new FileNotFoundException("fixture"); }
    }
    @Override public Uri insert(Uri uri, ContentValues values) { throw new UnsupportedOperationException(); }
    @Override public int delete(Uri uri, String selection, String[] args) { throw new UnsupportedOperationException(); }
    @Override public int update(Uri uri, ContentValues values, String selection, String[] args) { throw new UnsupportedOperationException(); }
}
