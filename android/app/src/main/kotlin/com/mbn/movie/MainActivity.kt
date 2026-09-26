package com.mbn.movie

import android.Manifest
import android.content.ContentValues
import android.content.res.Configuration
import android.content.pm.PackageManager
import android.app.PictureInPictureParams
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.graphics.Rect
import android.util.Rational
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }
    private var deviceBridge: DeviceBridge? = null
    @Deprecated("Delegates the install permission settings result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        deviceBridge?.onActivityResult(requestCode)
    }
    private val downloadsChannel = "com.mbn.movie/downloads"
    private val pipChannelName = "com.mbn.movie/pip"
    private val storageRequestCode = 4107
    private var pendingSave: PendingSave? = null
    private var pipChannel: MethodChannel? = null
    private var pipEnabled = false
    private var pipAspectRatio = 16.0 / 9.0
    private var pipTitle = "MBNMovie"
    private var pipSubtitle = ""

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val deviceChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.mbn.movie/device",
        )
        val bridge = DeviceBridge(this, deviceChannel)
        deviceBridge = bridge
        deviceChannel.setMethodCallHandler(bridge::handle)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, downloadsChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "saveImage") saveImage(call, result)
                else result.notImplemented()
            }
        pipChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            pipChannelName,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> result.success(supportsPictureInPicture())
                    "isInPipMode" -> result.success(
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
                            isInPictureInPictureMode,
                    )
                    "configure" -> {
                        updatePipOptions(call)
                        updatePictureInPictureParams()
                        result.success(null)
                    }
                    "enter" -> {
                        updatePipOptions(call)
                        result.success(enterPip())
                    }
                    "deactivate" -> {
                        pipEnabled = false
                        updatePictureInPictureParams()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun supportsPictureInPicture(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun updatePipOptions(call: MethodCall) {
        pipEnabled = call.argument<Boolean>("autoEnter") ?: pipEnabled
        pipAspectRatio = (call.argument<Number>("aspectRatio")?.toDouble()
            ?: pipAspectRatio).coerceIn(0.42, 2.38)
        pipTitle = call.argument<String>("title") ?: pipTitle
        pipSubtitle = call.argument<String>("subtitle") ?: pipSubtitle
    }

    private fun createPictureInPictureParams(): PictureInPictureParams {
        val denominator = 10_000
        val numerator = (pipAspectRatio * denominator).toInt().coerceAtLeast(1)
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(numerator, denominator))
        val sourceRectHint = Rect()
        if (window.decorView.getGlobalVisibleRect(sourceRectHint) && !sourceRectHint.isEmpty) {
            builder.setSourceRectHint(sourceRectHint)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder
                .setAutoEnterEnabled(pipEnabled)
                .setSeamlessResizeEnabled(true)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            builder.setTitle(pipTitle).setSubtitle(pipSubtitle)
        }
        return builder.build()
    }

    private fun updatePictureInPictureParams() {
        if (!supportsPictureInPicture()) return
        setPictureInPictureParams(createPictureInPictureParams())
    }

    private fun enterPip(): Boolean {
        if (!supportsPictureInPicture() || isInPictureInPictureMode) return false
        pipChannel?.invokeMethod("onPipTransitionStarted", null)
        val entered = enterPictureInPictureMode(createPictureInPictureParams())
        if (!entered) pipChannel?.invokeMethod("onPipModeChanged", false)
        return entered
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Android 12+ uses auto-enter for a smoother gesture animation.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S && pipEnabled) enterPip()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("onPipModeChanged", isInPictureInPictureMode)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        pipChannel?.setMethodCallHandler(null)
        pipChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun saveImage(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("bytes")
        val fileName = call.argument<String>("fileName")
        val mimeType = call.argument<String>("mimeType") ?: "image/jpeg"
        if (bytes == null || fileName.isNullOrBlank()) {
            result.error("invalid", "Image data or file name is missing.", null)
            return
        }

        if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.P &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            pendingSave = PendingSave(bytes, fileName, mimeType, result)
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                storageRequestCode,
            )
            return
        }
        writeImage(bytes, fileName, mimeType, result)
    }

    private fun writeImage(
        bytes: ByteArray,
        fileName: String,
        mimeType: String,
        result: MethodChannel.Result,
    ) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                    put(
                        MediaStore.MediaColumns.RELATIVE_PATH,
                        Environment.DIRECTORY_DOWNLOADS + "/MBNMovie",
                    )
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val uri = contentResolver.insert(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    values,
                ) ?: error("Android could not create the download file.")
                contentResolver.openOutputStream(uri, "w")!!.use { it.write(bytes) }
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
                result.success(uri.toString())
            } else {
                val directory = File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                    "MBNMovie",
                ).apply { mkdirs() }
                val output = uniqueFile(directory, fileName)
                output.writeBytes(bytes)
                result.success(output.absolutePath)
            }
        } catch (error: Throwable) {
            result.error("save_failed", error.message, null)
        }
    }

    private fun uniqueFile(directory: File, fileName: String): File {
        val requested = File(directory, fileName)
        if (!requested.exists()) return requested
        val dot = fileName.lastIndexOf('.')
        val base = if (dot > 0) fileName.substring(0, dot) else fileName
        val extension = if (dot > 0) fileName.substring(dot) else ""
        var index = 2
        while (true) {
            val candidate = File(directory, "$base ($index)$extension")
            if (!candidate.exists()) return candidate
            index++
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != storageRequestCode) return
        val save = pendingSave ?: return
        pendingSave = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            writeImage(save.bytes, save.fileName, save.mimeType, save.result)
        } else {
            save.result.error("permission_denied", "Storage permission was denied.", null)
        }
    }

    private data class PendingSave(
        val bytes: ByteArray,
        val fileName: String,
        val mimeType: String,
        val result: MethodChannel.Result,
    )
}
