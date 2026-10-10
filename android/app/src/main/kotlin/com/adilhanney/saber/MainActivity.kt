package com.adilhanney.saber

import android.content.Intent
import android.content.Intent.FLAG_ACTIVITY_NEW_TASK
import android.net.Uri
import android.os.Bundle
import android.util.Log
import androidx.core.view.WindowCompat
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream

class MainActivity: FlutterActivity() {
    private val SAF_CHANNEL = "com.adilhanney.saber/saf_storage"

    override fun onCreate(savedInstanceState: Bundle?) {
        if (intent.getIntExtra("org.chromium.chrome.extra.TASK_ID", -1) == this.taskId) {
            this.finish()
            intent.addFlags(FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        }
        super.onCreate(savedInstanceState)

        WindowCompat.setDecorFitsSystemWindows(window, false)

        val windowInsetsController = WindowCompat.getInsetsController(window, window.decorView)
        windowInsetsController.isAppearanceLightNavigationBars = true
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SAF_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "takePersistablePermission" -> {
                    val uriStr = call.argument<String>("uri")
                    if (uriStr.isNullOrBlank()) {
                        result.error("INVALID_URI", "URI cannot be empty", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val uri = Uri.parse(uriStr)
                        val takeFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                        contentResolver.takePersistableUriPermission(uri, takeFlags)
                        result.success(true)
                    } catch (e: Exception) {
                        Log.w("SafStorage", "Failed to take persistable permission: ${e.message}")
                        result.success(false)
                    }
                }
                "isUriAccessible" -> {
                    val uriStr = call.argument<String>("uri")
                    if (uriStr.isNullOrBlank()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    try {
                        val uri = Uri.parse(uriStr)
                        val doc = DocumentFile.fromTreeUri(applicationContext, uri)
                        result.success(doc != null && doc.canWrite())
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "writeFile" -> {
                    val treeUriStr = call.argument<String>("treeUri")
                    val relativePath = call.argument<String>("relativePath")
                    val bytes = call.argument<ByteArray>("bytes")
                    val mimeType = call.argument<String>("mimeType") ?: "application/pdf"

                    if (treeUriStr.isNullOrBlank() || relativePath.isNullOrBlank() || bytes == null) {
                        result.error("INVALID_ARGS", "Missing required parameters", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val treeUri = Uri.parse(treeUriStr)
                        // Proactively ensure persistable permission is granted
                        try {
                            val takeFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                            contentResolver.takePersistableUriPermission(treeUri, takeFlags)
                        } catch (ignored: Exception) {}

                        var currentDir = DocumentFile.fromTreeUri(applicationContext, treeUri)
                        if (currentDir == null || !currentDir.canWrite()) {
                            result.error("NO_PERM", "Cannot write to folder: $treeUriStr", null)
                            return@setMethodCallHandler
                        }

                        val segments = relativePath.split("/").filter { it.isNotEmpty() }
                        val dirSegments = segments.dropLast(1)
                        val fileName = segments.last()

                        for (dirName in dirSegments) {
                            var subDir = currentDir!!.findFile(dirName)
                            if (subDir == null || !subDir.isDirectory) {
                                subDir = currentDir!!.createDirectory(dirName)
                            }
                            if (subDir == null) {
                                result.error("MKDIR_FAILED", "Failed to create directory $dirName", null)
                                return@setMethodCallHandler
                            }
                            currentDir = subDir
                        }

                        var targetFile = currentDir!!.findFile(fileName)
                        if (targetFile == null && fileName.endsWith(".pdf", ignoreCase = true)) {
                            targetFile = currentDir!!.findFile(fileName.substringBeforeLast("."))
                        }
                        if (targetFile == null) {
                            targetFile = currentDir!!.createFile(mimeType, fileName)
                        }

                        if (targetFile == null) {
                            result.error("CREATE_FAILED", "Failed to create document $fileName", null)
                            return@setMethodCallHandler
                        }

                        var os: OutputStream? = null
                        try {
                            os = contentResolver.openOutputStream(targetFile.uri, "wt")
                        } catch (e: Exception) {
                            os = contentResolver.openOutputStream(targetFile.uri, "w")
                        }

                        if (os == null) {
                            result.error("STREAM_FAILED", "Cannot open stream for ${targetFile.uri}", null)
                            return@setMethodCallHandler
                        }

                        os.use { stream ->
                            stream.write(bytes)
                            stream.flush()
                        }

                        result.success(mapOf(
                            "uri" to targetFile.uri.toString(),
                            "name" to targetFile.name
                        ))
                    } catch (e: Exception) {
                        Log.e("SafStorage", "Error writing file via SAF", e)
                        result.error("IO_ERROR", e.message, null)
                    }
                }
                "renameFile" -> {
                    val treeUriStr = call.argument<String>("treeUri")
                    val oldRelativePath = call.argument<String>("oldRelativePath")
                    val newRelativePath = call.argument<String>("newRelativePath")

                    if (treeUriStr.isNullOrBlank() || oldRelativePath.isNullOrBlank() || newRelativePath.isNullOrBlank()) {
                        result.error("INVALID_ARGS", "Missing required parameters", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val treeUri = Uri.parse(treeUriStr)
                        val currentDir = findParentDirectory(treeUri, oldRelativePath)
                        val oldName = oldRelativePath.split("/").filter { it.isNotEmpty() }.last()
                        val newName = newRelativePath.split("/").filter { it.isNotEmpty() }.last()

                        var oldDoc = currentDir?.findFile(oldName)
                        if (oldDoc == null && oldName.endsWith(".pdf", ignoreCase = true)) {
                            oldDoc = currentDir?.findFile(oldName.substringBeforeLast("."))
                        }
                        if (oldDoc != null) {
                            val success = oldDoc.renameTo(newName)
                            result.success(success)
                        } else {
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        Log.e("SafStorage", "Error renaming file via SAF", e)
                        result.error("IO_ERROR", e.message, null)
                    }
                }
                "deleteFile" -> {
                    val treeUriStr = call.argument<String>("treeUri")
                    val relativePath = call.argument<String>("relativePath")

                    if (treeUriStr.isNullOrBlank() || relativePath.isNullOrBlank()) {
                        result.error("INVALID_ARGS", "Missing required parameters", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val treeUri = Uri.parse(treeUriStr)
                        val currentDir = findParentDirectory(treeUri, relativePath)
                        val fileName = relativePath.split("/").filter { it.isNotEmpty() }.last()

                        var targetDoc = currentDir?.findFile(fileName)
                        if (targetDoc == null && fileName.endsWith(".pdf", ignoreCase = true)) {
                            targetDoc = currentDir?.findFile(fileName.substringBeforeLast("."))
                        }
                        if (targetDoc != null) {
                            result.success(targetDoc.delete())
                        } else {
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        Log.e("SafStorage", "Error deleting file via SAF", e)
                        result.error("IO_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun findParentDirectory(treeUri: Uri, relativePath: String): DocumentFile? {
        var current = DocumentFile.fromTreeUri(applicationContext, treeUri) ?: return null
        val segments = relativePath.split("/").filter { it.isNotEmpty() }
        val dirSegments = segments.dropLast(1)
        for (dir in dirSegments) {
            current = current.findFile(dir) ?: return null
            if (!current.isDirectory) return null
        }
        return current
    }
}
