package org.kotoha.app

import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry.ActivityResultListener
import java.io.ByteArrayOutputStream
import java.io.InputStream

/**
 * Temporary SAF directory grant; only bounded manifest/terms metadata is exposed.
 * Picks share the activity-result pool with text import, and detached picks leave
 * late-result tombstones. This plugin never requests or takes persistable grants.
 */
class ModelPackagePlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    ActivityResultListener {
    private var channel: MethodChannel? = null
    private var binding: ActivityPluginBinding? = null
    private var pendingSelection: SelectRequest? = null
    private var pendingRead: ReadRequest? = null
    // Only a volatile reference to the current non-persistable SAF selection.
    private var root: Uri? = null
    private val main = Handler(Looper.getMainLooper())

    private class SelectRequest(val code: Int, var result: MethodChannel.Result?)

    private class ReadRequest(val result: MethodChannel.Result) {
        @Volatile var cancelled = false
        @Volatile var stream: InputStream? = null
        var replied = false
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        detachActivity()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        this.binding = binding
        binding.addActivityResultListener(this)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = detachActivity()

    override fun onDetachedFromActivity() = detachActivity()

    private fun detachActivity() {
        binding?.removeActivityResultListener(this)
        pendingSelection?.let {
            finishSelection(it, error = "detached", preserveLateResult = true)
        }
        cancelRead("detached")
        root = null
        binding = null
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ): Boolean {
        if (SharedActivityRequestCodes.pool.consumeAbandoned(requestCode)) return true
        val request = pendingSelection ?: return false
        if (request.code != requestCode) return false

        val uri = data?.data
        val flags = data?.flags ?: 0
        val valid = resultCode == Activity.RESULT_OK &&
            uri != null &&
            uri.scheme == "content" &&
            DocumentsContract.isTreeUri(uri) &&
            (flags and Intent.FLAG_GRANT_READ_URI_PERMISSION) != 0 &&
            (flags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION) == 0
        if (valid) {
            root = uri
            finishSelection(request, value = true)
        } else {
            root = null
            finishSelection(request, value = false)
        }
        return true
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "release" -> {
                cancelRead("released")
                root = null
                result.success(null)
            }
            "selectDirectory" -> selectDirectory(result)
            "readFile" -> readFile(call, result)
            else -> result.notImplemented()
        }
    }

    private fun selectDirectory(result: MethodChannel.Result) {
        if (pendingSelection != null || pendingRead != null) {
            result.error("busy", "A model-package operation is already active.", null)
            return
        }
        val activity = binding?.activity
        if (activity == null) {
            result.error("detached", "No active activity.", null)
            return
        }
        val code = SharedActivityRequestCodes.pool.acquire()
        if (code == null) {
            result.error("unavailable", "Activity request codes exhausted.", null)
            return
        }

        // Drop the old tree reference before asking for another temporary grant.
        root = null
        val request = SelectRequest(code, result)
        pendingSelection = request
        try {
            activity.startActivityForResult(
                Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
                code,
            )
        } catch (_: Exception) {
            finishSelection(request, error = "picker_failed")
        }
    }

    private fun readFile(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path") ?: ""
        val maxBytes = call.argument<Int>("maxBytes") ?: 0
        val selectedRoot = root
        val activity = binding?.activity
        if (selectedRoot == null || activity == null ||
            maxBytes !in 1..MAX_REQUEST_BYTES || !isSafePath(path)) {
            result.error("invalid", "Invalid model-package read.", null)
            return
        }
        val resolver = activity.contentResolver
        if (pendingRead != null || pendingSelection != null) {
            result.error("busy", "A model-package operation is already active.", null)
            return
        }

        val request = ReadRequest(result)
        pendingRead = request
        Thread({
            var bytes: ByteArray? = null
            var error: String? = null
            try {
                val file = resolveDocument(resolver, selectedRoot, path) { request.cancelled }
                if (request.cancelled) throw IllegalStateException("cancelled")
                val opened = resolver.openInputStream(file)
                request.stream = opened
                if (request.cancelled) {
                    try { opened?.close() } catch (_: Exception) { }
                    throw IllegalStateException("cancelled")
                }
                bytes = opened?.use { input ->
                    val output = ByteArrayOutputStream(minOf(maxBytes, BUFFER_BYTES))
                    val buffer = ByteArray(BUFFER_BYTES)
                    var total = 0
                    while (true) {
                        if (request.cancelled) throw IllegalStateException("cancelled")
                        val requestBytes = minOf(buffer.size, maxBytes - total + 1)
                        val count = input.read(buffer, 0, requestBytes)
                        if (count < 0) break
                        if (count == 0) {
                            val single = input.read()
                            if (single < 0) break
                            if (++total > maxBytes) throw IllegalArgumentException("size limit")
                            output.write(single)
                        } else {
                            total += count
                            if (total > maxBytes) throw IllegalArgumentException("size limit")
                            output.write(buffer, 0, count)
                        }
                    }
                    output.toByteArray()
                } ?: throw IllegalArgumentException("missing stream")
            } catch (_: Exception) {
                error = "read_failed"
            } finally {
                request.stream = null
                main.post { completeRead(request, bytes = bytes, error = error) }
            }
        }, "kotoha-model-metadata-read").start()
    }

    private fun completeRead(
        request: ReadRequest,
        bytes: ByteArray? = null,
        error: String? = null,
    ) {
        if (pendingRead !== request) return
        pendingRead = null
        request.stream = null
        if (request.cancelled || request.replied) return
        request.replied = true
        if (error == null) request.result.success(bytes)
        else request.result.error(error, "Could not safely read package metadata.", null)
    }

    private fun cancelRead(error: String) {
        val request = pendingRead ?: return
        request.cancelled = true
        try {
            request.stream?.close()
        } catch (_: Exception) {
            // The request is already cancelled; no further provider access is allowed.
        }
        request.stream = null
        if (!request.replied) {
            request.replied = true
            request.result.error(error, "Model-package read was cancelled.", null)
        }
    }

    private fun finishSelection(
        request: SelectRequest,
        value: Boolean? = null,
        error: String? = null,
        preserveLateResult: Boolean = false,
    ) {
        if (pendingSelection !== request) return
        pendingSelection = null
        if (preserveLateResult) SharedActivityRequestCodes.pool.abandon(request.code)
        else SharedActivityRequestCodes.pool.release(request.code)
        val reply = request.result
        request.result = null
        if (error == null) reply?.success(value)
        else reply?.error(error, "Could not select a model package.", null)
    }

    companion object {
        const val MAX_REQUEST_BYTES = 4 * 1024 * 1024
        private const val BUFFER_BYTES = 8192
        private const val CHANNEL = "org.kotoha/model_package"

        @JvmStatic
        fun isSafePath(path: String): Boolean {
            if (path.isEmpty() || path.startsWith('/') || path.contains('\\')) return false
            if (path.any { it.code < 0x20 || it in "<>:\"|?*" }) return false
            return path.split('/').all { part ->
                if (part.isEmpty() || part == "." || part == ".." ||
                    part.endsWith('.') || part.endsWith(' ')) return@all false
                val base = part.substringBefore('.').lowercase()
                base !in setOf("con", "prn", "aux", "nul") &&
                    !Regex("^(com|lpt)[1-9]$").matches(base)
            }
        }

        @JvmStatic
        @JvmOverloads
        fun resolveDocument(
            resolver: ContentResolver,
            tree: Uri,
            path: String,
            cancelled: () -> Boolean = { false },
        ): Uri {
            require(isSafePath(path)) { "unsafe path" }
            require(DocumentsContract.isTreeUri(tree)) { "not a tree URI" }
            var parent = DocumentsContract.buildDocumentUriUsingTree(
                tree,
                DocumentsContract.getTreeDocumentId(tree),
            )
            val parts = path.split('/')
            for ((index, part) in parts.withIndex()) {
                val children = DocumentsContract.buildChildDocumentsUriUsingTree(
                    tree,
                    DocumentsContract.getDocumentId(parent),
                )
                val found = mutableListOf<Pair<String, Boolean>>()
                check(!cancelled()) { "cancelled" }
                val cursorResult = resolver.query(
                    children,
                    arrayOf(
                        DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                        DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                        DocumentsContract.Document.COLUMN_MIME_TYPE,
                    ),
                    null,
                    null,
                    null,
                )
                cursorResult?.use { cursor ->
                    check(!cancelled()) { "cancelled" }
                    val idColumn = cursor.getColumnIndex(
                        DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    )
                    val nameColumn = cursor.getColumnIndex(
                        DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    )
                    val mimeColumn = cursor.getColumnIndex(
                        DocumentsContract.Document.COLUMN_MIME_TYPE,
                    )
                    require(idColumn >= 0 && nameColumn >= 0 && mimeColumn >= 0) {
                        "incomplete document metadata"
                    }
                    while (cursor.moveToNext()) {
                        if (!cursor.isNull(nameColumn) &&
                            cursor.getString(nameColumn) == part) {
                            found.add(
                                cursor.getString(idColumn) to
                                    (cursor.getString(mimeColumn) ==
                                        DocumentsContract.Document.MIME_TYPE_DIR),
                            )
                        }
                    }
                } ?: run {
                    check(!cancelled()) { "cancelled" }
                    throw IllegalArgumentException("missing child listing")
                }

                if (found.size != 1) throw IllegalArgumentException("ambiguous path")
                val isDirectory = found.single().second
                val isFinalPart = index == parts.lastIndex
                if (isDirectory == isFinalPart) {
                    throw IllegalArgumentException("unexpected directory/file node")
                }
                parent = DocumentsContract.buildDocumentUriUsingTree(tree, found.single().first)
            }
            return parent
        }
    }
}
