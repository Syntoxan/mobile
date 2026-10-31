// SYNTOXAN — Zero-plugin native storage bridge. PART 2 OF 3 (Android side).
//
// Target path: android/app/src/main/kotlin/org/lichess/mobileapp/SynFileBridge.kt
//
// Channel: "syntoxan/file_bridge"
//   pickPuzzleFile      -> opens the system document picker (ACTION_OPEN_DOCUMENT),
//                          stream-copies the chosen content:// URI into
//                          filesDir/syn_puzzles/<sanitized_name> on a background
//                          thread and returns {path, name, size}; null if cancelled.
//   deleteCopiedFile    -> deletes a previously copied file (plus SQLite side files).
//                          Only direct children of filesDir/syn_puzzles are deletable.
//
// No permissions are required: the Storage Access Framework grants a one-shot
// read grant for the picked document, and we copy it into app-private storage so
// sqflite and Dart isolates can open it with a plain file path.
//
// ---- MainActivity.kt registration (merge into your existing MainActivity) ----
//
//   package org.lichess.mobileapp
//
//   import android.content.Intent
//   import io.flutter.embedding.android.FlutterActivity
//   import io.flutter.embedding.engine.FlutterEngine
//
//   class MainActivity : FlutterActivity() {
//       private var synFileBridge: SynFileBridge? = null
//
//       override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
//           super.configureFlutterEngine(flutterEngine)
//           synFileBridge = SynFileBridge(this, flutterEngine)
//       }
//
//       override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
//           if (synFileBridge?.onActivityResult(requestCode, resultCode, data) == true) return
//           super.onActivityResult(requestCode, resultCode, data)
//       }
//
//       override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
//           synFileBridge?.dispose()
//           synFileBridge = null
//           super.cleanUpFlutterEngine(flutterEngine)
//       }
//   }
//
// If your MainActivity already overrides configureFlutterEngine / onActivityResult /
// cleanUpFlutterEngine, just add the three SynFileBridge lines to those overrides.

package org.lichess.mobileV2

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

class SynFileBridge(
    private val activity: Activity,
    flutterEngine: FlutterEngine,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "syntoxan/file_bridge"
        const val REQUEST_PICK_PUZZLE_FILE = 0x5359
        private const val SUBDIR = "syn_puzzles"
        private const val COPY_BUFFER_BYTES = 256 * 1024
        private const val MAX_NAME_LENGTH = 120
        private const val MAX_EXTENSION_LENGTH = 16
        private const val FREE_SPACE_MARGIN_BYTES = 8L * 1024L * 1024L
    }

    private class BridgeException(val code: String, message: String) : Exception(message)

    private val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

    // Single worker: copies and deletions are serialized, so a delete can never
    // race with a copy that is still writing the same file.
    private val io: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "syn-file-bridge").apply { isDaemon = true }
    }
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingPick: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(this)
    }

    // ------------------------------------------------------------------ channel

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickPuzzleFile" -> pickPuzzleFile(result)
            "deleteCopiedFile" -> {
                val path = (call.arguments as? String) ?: call.argument<String>("path")
                deleteCopiedFile(path, result)
            }
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        pendingPick?.success(null)
        pendingPick = null
        io.shutdown()
    }

    // --------------------------------------------------------------- pick + copy

    private fun pickPuzzleFile(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("BUSY", "A file picker is already open", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        pendingPick = result
        try {
            activity.startActivityForResult(intent, REQUEST_PICK_PUZZLE_FILE)
        } catch (e: ActivityNotFoundException) {
            pendingPick = null
            result.error("NO_PICKER", "No document picker is available on this device", null)
        }
    }

    /** Returns true when the result belonged to this bridge (so the caller must not forward it). */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_PICK_PUZZLE_FILE) return false
        val result = pendingPick ?: return true
        pendingPick = null

        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null) // user cancelled
            return true
        }
        try {
            io.execute {
                try {
                    val payload = copyUriToPrivateStorage(uri)
                    mainHandler.post { result.success(payload) }
                } catch (e: BridgeException) {
                    mainHandler.post { result.error(e.code, e.message, null) }
                } catch (e: Exception) {
                    mainHandler.post { result.error("COPY_FAILED", e.message ?: e.javaClass.simpleName, null) }
                }
            }
        } catch (e: RejectedExecutionException) {
            result.error("BRIDGE_CLOSED", "File bridge has been disposed", null)
        }
        return true
    }

    private fun copyUriToPrivateStorage(uri: Uri): Map<String, Any> {
        val resolver = activity.contentResolver

        var displayName: String? = null
        var declaredSize = -1L
        resolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (nameIndex >= 0 && !cursor.isNull(nameIndex)) displayName = cursor.getString(nameIndex)
                if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) declaredSize = cursor.getLong(sizeIndex)
            }
        }
        val shownName = displayName?.takeIf { it.isNotBlank() } ?: uri.lastPathSegment ?: "puzzles"

        val dir = File(activity.filesDir, SUBDIR)
        if (!dir.exists() && !dir.mkdirs()) {
            throw BridgeException("IO_ERROR", "Could not create ${dir.absolutePath}")
        }
        if (!dir.isDirectory) {
            throw BridgeException("IO_ERROR", "${dir.absolutePath} is not a directory")
        }
        if (declaredSize > 0 && dir.usableSpace < declaredSize + FREE_SPACE_MARGIN_BYTES) {
            throw BridgeException("NO_SPACE", "Not enough free storage to import this file")
        }

        val safeName = sanitizeName(shownName)
        var dest = File(dir, safeName)
        var counter = 1
        while (dest.exists()) {
            // Prefix (not suffix) so compound extensions such as .csv.gz survive.
            dest = File(dir, "${counter}_$safeName")
            counter++
        }
        val partial = File(dir, ".${dest.name}.part")

        val input = resolver.openInputStream(uri)
            ?: throw BridgeException("OPEN_FAILED", "Could not open the selected document")
        try {
            input.use { source ->
                FileOutputStream(partial).use { sink ->
                    source.copyTo(sink, COPY_BUFFER_BYTES)
                    sink.flush()
                    sink.fd.sync()
                }
            }
            if (!partial.renameTo(dest)) {
                throw IOException("Could not move ${partial.name} into place")
            }
        } catch (e: BridgeException) {
            partial.delete()
            throw e
        } catch (e: Exception) {
            partial.delete()
            dest.delete()
            throw BridgeException("COPY_FAILED", e.message ?: e.javaClass.simpleName)
        }

        return mapOf(
            "path" to dest.absolutePath,
            "name" to shownName,
            "size" to dest.length(),
        )
    }

    /**
     * Keeps [A-Za-z0-9._-], strips path separators and leading dots, collapses
     * ".." and caps the length while preserving a short trailing extension.
     */
    private fun sanitizeName(raw: String): String {
        val base = raw.substringAfterLast('/').substringAfterLast('\\')
        var name = base
            .replace(Regex("[^A-Za-z0-9._-]"), "_")
            .replace(Regex("\\.{2,}"), ".")
            .trimStart('.')
        if (name.length > MAX_NAME_LENGTH) {
            val dot = name.lastIndexOf('.')
            val extension = if (dot > 0 && name.length - dot <= MAX_EXTENSION_LENGTH) name.substring(dot) else ""
            val stem = if (dot > 0 && extension.isNotEmpty()) name.substring(0, dot) else name
            name = stem.take(MAX_NAME_LENGTH - extension.length) + extension
        }
        if (name.isBlank()) name = "puzzles_${System.currentTimeMillis()}"
        return name
    }

    // ------------------------------------------------------------------- delete

    private fun deleteCopiedFile(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) {
            result.error("BAD_ARGS", "path is required", null)
            return
        }
        try {
            io.execute {
                val outcome = try {
                    deleteWithinSandbox(path)
                } catch (e: Exception) {
                    false
                }
                mainHandler.post { result.success(outcome) }
            }
        } catch (e: RejectedExecutionException) {
            result.success(false)
        }
    }

    /**
     * true  -> the file is gone (deleted now, or it was already absent)
     * false -> refused (outside filesDir/syn_puzzles) or the delete failed
     */
    private fun deleteWithinSandbox(path: String): Boolean {
        val root = File(activity.filesDir, SUBDIR).canonicalFile
        val target = File(path).canonicalFile
        if (target.parentFile?.canonicalFile != root) return false
        if (!target.exists()) return true
        val deleted = target.delete()
        for (suffix in listOf("-journal", "-wal", "-shm")) {
            File(target.path + suffix).delete()
        }
        return deleted
    }
}
