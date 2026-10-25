package com.example.sopu

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : AudioServiceActivity() {
    private val saveExecutor = Executors.newSingleThreadExecutor()
    private var pendingSave: Pair<MethodCall, MethodChannel.Result>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sopu/file_save")
            .setMethodCallHandler { call, result ->
                if (call.method != "save") {
                    result.notImplemented()
                } else if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
                    checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED
                ) {
                    if (pendingSave != null) {
                        result.error("BUSY", "正在等待存储权限授权", null)
                    } else {
                        pendingSave = call to result
                        requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 701)
                    }
                } else {
                    save(call, result)
                }
            }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 701) return
        val request = pendingSave ?: return
        pendingSave = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            save(request.first, request.second)
        } else {
            request.second.error("PERMISSION_DENIED", "保存到下载目录或相册需要存储权限，请在系统设置中允许后重试", null)
        }
    }

    private fun save(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("bytes")
        val name = call.argument<String>("name")
        val mime = call.argument<String>("mimeType") ?: "application/octet-stream"
        val gallery = call.argument<String>("destination") == "gallery"
        if (bytes == null || bytes.isEmpty() || name.isNullOrBlank() ||
            name == "." || name == ".." || name.any { it == '/' || it == '\\' || it.code < 32 } ||
            (gallery && !mime.startsWith("image/"))) {
            result.error("INVALID_FILE", "保存文件参数无效", null)
            return
        }
        saveExecutor.execute {
            try {
                val location = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val folder = if (gallery) Environment.DIRECTORY_PICTURES else Environment.DIRECTORY_DOWNLOADS
                    val collection = if (gallery) {
                        MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                    } else {
                        MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                    }
                    val values = ContentValues().apply {
                        put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                        put(MediaStore.MediaColumns.MIME_TYPE, mime)
                        put(MediaStore.MediaColumns.RELATIVE_PATH, "$folder/搜谱")
                        put(MediaStore.MediaColumns.IS_PENDING, 1)
                    }
                    val uri = contentResolver.insert(collection, values)
                        ?: throw IllegalStateException("系统未能创建文件")
                    try {
                        val stream = contentResolver.openOutputStream(uri)
                            ?: throw IllegalStateException("无法写入保存位置")
                        stream.use { it.write(bytes) }
                        val published = contentResolver.update(uri, ContentValues().apply {
                            put(MediaStore.MediaColumns.IS_PENDING, 0)
                        }, null, null)
                        check(published > 0) { "系统未能发布保存的文件" }
                    } catch (e: Exception) {
                        contentResolver.delete(uri, null, null)
                        throw e
                    }
                    "$folder/搜谱/$name"
                } else {
                    @Suppress("DEPRECATION")
                    val directory = File(Environment.getExternalStoragePublicDirectory(
                        if (gallery) Environment.DIRECTORY_PICTURES else Environment.DIRECTORY_DOWNLOADS
                    ), "搜谱")
                    check(directory.isDirectory || directory.mkdirs()) { "无法创建保存目录" }
                    val dot = name.lastIndexOf('.')
                    val stem = if (dot > 0) name.substring(0, dot) else name
                    val suffix = if (dot > 0) name.substring(dot) else ""
                    var file = File(directory, name)
                    var number = 1
                    while (!file.createNewFile()) {
                        file = File(directory, "$stem (${number++})$suffix")
                    }
                    file.outputStream().use { it.write(bytes) }
                    MediaScannerConnection.scanFile(applicationContext, arrayOf(file.absolutePath), arrayOf(mime), null)
                    file.absolutePath
                }
                runOnUiThread { result.success(location) }
            } catch (e: Exception) {
                runOnUiThread { result.error("SAVE_FAILED", e.message ?: "保存失败", null) }
            }
        }
    }

    override fun onDestroy() {
        pendingSave?.second?.error("CANCELLED", "保存已取消，请重试", null)
        pendingSave = null
        saveExecutor.shutdown()
        super.onDestroy()
    }
}
