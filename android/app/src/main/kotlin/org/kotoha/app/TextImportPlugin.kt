package org.kotoha.app

import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry.ActivityResultListener
import java.util.Locale

/** One-shot, read-in-place import. No paths, copies, persisted grants or recovery state. */
class TextImportPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler,
    ActivityResultListener {
    private var channel: MethodChannel? = null
    private var binding: ActivityPluginBinding? = null
    private class Request(val code: Int, var result: MethodChannel.Result?) {
        var reading = false
    }
    private var pending: Request? = null
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "org.kotoha/text_import").also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detachActivity()
        channel?.setMethodCallHandler(null)
        channel = null
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
        binding = null
        pending?.let { finish(it, error = "detached", preserveLateResult = !it.reading) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "open") { result.notImplemented(); return }
        if (pending != null) { result.error("busy", "Import already active.", null); return }
        val activity = binding?.activity
        if (activity == null) { result.error("detached", "No active activity.", null); return }
        // Uniqueness is needed only while a result can still arrive. Completed requests
        // release their code; detached requests remain reserved as late-result tombstones.
        val code = SharedActivityRequestCodes.pool.acquire()
        if (code == null) { result.error("unavailable", "Request codes exhausted.", null); return }
        val request = Request(code, result)
        pending = request
        try {
            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*" // Provider MIME mappings for Markdown vary; names are authoritative.
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, false)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }, code)
        } catch (_: Exception) {
            finish(request, error = "picker_failed")
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (SharedActivityRequestCodes.pool.consumeAbandoned(requestCode)) return true
        val request = pending ?: return false
        if (request.code != requestCode) return false
        if (request.reading) return true
        if (resultCode == Activity.RESULT_CANCELED) { finish(request); return true }
        val uri = data?.data
        val resolver = binding?.activity?.contentResolver
        if (resultCode != Activity.RESULT_OK || uri?.scheme != "content" || resolver == null ||
            data?.clipData?.let { it.itemCount != 1 || it.getItemAt(0).uri != uri } == true ||
            ((data?.flags ?: 0) and Intent.FLAG_GRANT_READ_URI_PERMISSION) == 0) {
            finish(request, error = "invalid_selection")
            return true
        }
        request.reading = true
        Thread {
            try {
                val document = readDocument(resolver, uri)
                main.post { finish(request, document) }
            } catch (_: Exception) {
                main.post { finish(request, error = "read_failed") }
            }
        }.start()
        return true
    }

    private fun finish(
        request: Request,
        document: Map<String, Any>? = null,
        error: String? = null,
        preserveLateResult: Boolean = false,
    ) {
        if (pending !== request) return
        pending = null
        if (preserveLateResult) SharedActivityRequestCodes.pool.abandon(request.code) else SharedActivityRequestCodes.pool.release(request.code)
        val result = request.result
        request.result = null
        if (error == null) result?.success(document)
        else result?.error(error, "Could not import this document.", null)
    }

    companion object {
        @JvmStatic
        fun readDocument(resolver: ContentResolver, uri: Uri): Map<String, Any> {
            val name = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (column < 0 || !cursor.moveToFirst() || cursor.isNull(column)) null
                    else cursor.getString(column)
                } ?: throw IllegalArgumentException("Missing display name")
            require(listOf(".txt", ".md", ".markdown").any {
                name.lowercase(Locale.ROOT).endsWith(it)
            }) { "Unsupported document" }
            val bytes = resolver.openInputStream(uri)?.use { it.readBytes() }
                ?: throw IllegalArgumentException("Missing stream")
            return mapOf("name" to name, "bytes" to bytes)
        }
    }
}
