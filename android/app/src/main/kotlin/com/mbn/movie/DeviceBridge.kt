package com.mbn.movie

import android.Manifest
import android.app.PendingIntent
import android.content.Intent
import android.content.Context
import android.media.AudioManager
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import android.provider.DocumentsContract
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class DeviceBridge(
    private val activity: FlutterActivity,
    private val channel: MethodChannel,
) {
    companion object {
        internal const val installStatusAction = "com.mbn.movie.UPDATE_INSTALL_STATUS"
        private var statusChannel: MethodChannel? = null

        internal fun publishInstallStatus(status: String) {
            statusChannel?.invokeMethod("updateInstallStatus", status)
        }
    }
    private var installPermissionResult: MethodChannel.Result? = null
    private val installPermissionRequestCode = 4119

    init {
        statusChannel = channel
    }

    fun onActivityResult(requestCode: Int) {
        if (requestCode != installPermissionRequestCode) return
        val pending = installPermissionResult
        installPermissionResult = null
        pending?.success(Build.VERSION.SDK_INT < 26 || activity.packageManager.canRequestPackageInstalls())
    }

    @Suppress("DEPRECATION")
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "isTelevision" -> {
                    val manager = activity.getSystemService(Context.UI_MODE_SERVICE) as android.app.UiModeManager
                    result.success(manager.currentModeType == android.content.res.Configuration.UI_MODE_TYPE_TELEVISION ||
                        activity.packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK))
                }
                "requestInstallPermission" -> {
                    if (Build.VERSION.SDK_INT < 26 || activity.packageManager.canRequestPackageInstalls()) {
                        result.success(true)
                    } else if (installPermissionResult != null) {
                        result.success(false)
                    } else {
                        installPermissionResult = result
                        try {
                            activity.startActivityForResult(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:${activity.packageName}")), installPermissionRequestCode)
                        } catch (_: Exception) {
                            installPermissionResult = null
                            result.success(false)
                        }
                    }
                }
                "abi" -> result.success(when {
                    Build.SUPPORTED_ABIS.contains("arm64-v8a") -> "arm64-v8a"
                    Build.SUPPORTED_ABIS.contains("armeabi-v7a") -> "armeabi-v7a"
                    else -> "unsupported"
                })
                "mediaVolume" -> result.success(mediaVolume())
                "setMediaVolume" -> {
                    val audio = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val maximum = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
                    val value = (call.argument<Double>("value") ?: 1.0).coerceIn(0.0, 1.0)
                    val flags = if (call.argument<Boolean>("showUi") != false) AudioManager.FLAG_SHOW_UI else 0
                    audio.setStreamVolume(AudioManager.STREAM_MUSIC, (value * maximum).toInt(), flags)
                    result.success(mediaVolume())
                }
                "screenBrightness" -> {
                    val override = activity.window.attributes.screenBrightness
                    val value = if (override >= 0f) override.toDouble() else
                        Settings.System.getInt(activity.contentResolver, Settings.System.SCREEN_BRIGHTNESS, 128) / 255.0
                    result.success(value.coerceIn(0.0, 1.0))
                }
                "setScreenBrightness" -> {
                    val value = (call.argument<Double>("value") ?: -1.0).coerceIn(-1.0, 1.0)
                    val attributes = activity.window.attributes
                    attributes.screenBrightness = value.toFloat()
                    activity.window.attributes = attributes
                    result.success(null)
                }
                "wirelessDisplay" -> {
                    val intents = listOf(Intent(Settings.ACTION_CAST_SETTINGS), Intent(Settings.ACTION_DISPLAY_SETTINGS))
                    var opened = false
                    for (intent in intents) {
                        try { activity.startActivity(intent); opened = true; break }
                        catch (_: android.content.ActivityNotFoundException) { }
                    }
                    result.success(opened)
                }
                "storageGranted" -> result.success(storageGranted())
                "requestStorage" -> {
                    if (Build.VERSION.SDK_INT >= 30) {
                        activity.startActivity(Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                            Uri.parse("package:${activity.packageName}")))
                    } else {
                        ActivityCompat.requestPermissions(activity,
                            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 4110)
                    }
                    result.success(null)
                }
                "downloadsDirectory" -> result.success(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).absolutePath)
                "openDownloads" -> {
                    val folder = DocumentsContract.buildDocumentUri(
                        "com.android.externalstorage.documents", "primary:Download/MBNMovie")
                    val intents = listOf(
                        Intent(Intent.ACTION_VIEW).setDataAndType(folder, DocumentsContract.Document.MIME_TYPE_DIR)
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
                        Intent(android.app.DownloadManager.ACTION_VIEW_DOWNLOADS))
                    var opened = false
                    for (intent in intents) {
                        try { activity.startActivity(intent); opened = true; break }
                        catch (_: android.content.ActivityNotFoundException) { }
                    }
                    result.success(opened)
                }
                "installApk" -> result.success(installApk(call.argument<String>("path") ?: ""))
                "isAppInstalled" -> result.success(isAppInstalled(call.argument<String>("package") ?: ""))
                "openApp" -> result.success(openApp(call.argument<String>("package") ?: "", call.argument<String>("handoff")))
                "takeHandoff" -> {
                    val message = activity.intent?.getStringExtra("mbn_handoff")
                    activity.intent?.removeExtra("mbn_handoff")
                    result.success(message)
                }
                "playLocalVideo" -> {
                    val file = File(call.argument<String>("path") ?: "").canonicalFile
                    val root = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "MBNMovie").canonicalFile
                    require(file.isFile && file.path.startsWith(root.path + File.separator))
                    val target = when (call.argument<String>("player")) {
                        "vlc" -> "org.videolan.vlc"
                        "mxPlayer" -> "com.mxtech.videoplayer.ad"
                        "mxPlayerPro" -> "com.mxtech.videoplayer.pro"
                        else -> throw IllegalArgumentException("Unknown player")
                    }
                    val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", file)
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, "video/*")
                        setPackage(target)
                        clipData = android.content.ClipData.newRawUri("video", uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        putExtra("title", call.argument<String>("title"))
                    }
                    try { activity.startActivity(intent); result.success("launched") }
                    catch (_: android.content.ActivityNotFoundException) { result.success("missing") }
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) { result.error("DEVICE", e.javaClass.simpleName, null) }
    }

    private fun storageGranted(): Boolean = if (Build.VERSION.SDK_INT >= 30)
        Environment.isExternalStorageManager()
    else ContextCompat.checkSelfPermission(activity, Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED

    private fun isAppInstalled(pkg: String): Boolean {
        if (pkg.isEmpty()) return false
        return try {
            if (Build.VERSION.SDK_INT >= 33) {
                activity.packageManager.getPackageInfo(pkg, PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                activity.packageManager.getPackageInfo(pkg, 0)
            }
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun openApp(pkg: String, handoff: String? = null): Boolean {
        if (pkg.isEmpty()) return false
        val intent = activity.packageManager.getLaunchIntentForPackage(pkg) ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        if (handoff != null) intent.putExtra("mbn_handoff", handoff)
        return try {
            activity.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun mediaVolume(): Double {
        val audio = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val maximum = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        return audio.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / maximum
    }

    @Suppress("DEPRECATION")
    private fun installApk(path: String): String {
        if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) return "permission"
        val file = File(path).canonicalFile
        val updates = File(activity.filesDir, "updates").canonicalFile
        if (!file.path.startsWith(updates.path + File.separator) || !file.isFile || file.extension != "apk") return "invalid"
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        val pm = activity.packageManager
        val archive = pm.getPackageArchiveInfo(file.path, flags) ?: return "invalid"
        val current = pm.getPackageInfo(activity.packageName, flags)
        if (archive.packageName != activity.packageName) return "invalid"
        val newCode = if (Build.VERSION.SDK_INT >= 28) archive.longVersionCode else archive.versionCode.toLong()
        val oldCode = if (Build.VERSION.SDK_INT >= 28) current.longVersionCode else current.versionCode.toLong()
        if (newCode <= oldCode) return "invalid"
        val incoming = if (Build.VERSION.SDK_INT >= 28) archive.signingInfo?.apkContentsSigners else archive.signatures
        val installed = if (Build.VERSION.SDK_INT >= 28) current.signingInfo?.apkContentsSigners else current.signatures
        if (incoming.isNullOrEmpty() || installed.isNullOrEmpty() || incoming.toSet() != installed.toSet()) return "signature"
        var sessionId = -1
        try {
            val params = PackageInstaller.SessionParams(
                PackageInstaller.SessionParams.MODE_FULL_INSTALL,
            ).apply {
                setAppPackageName(activity.packageName)
                setSize(file.length())
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    setRequireUserAction(
                        PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED,
                    )
                }
            }
            val installer = pm.packageInstaller
            sessionId = installer.createSession(params)
            installer.openSession(sessionId).use { session ->
                file.inputStream().use { input ->
                    session.openWrite("base.apk", 0, file.length()).use { output ->
                        input.copyTo(output)
                        session.fsync(output)
                    }
                }
                val callback = Intent(activity, UpdateInstallReceiver::class.java).apply {
                    action = installStatusAction
                    putExtra("sessionId", sessionId)
                }
                val pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT or
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        PendingIntent.FLAG_MUTABLE
                    } else {
                        0
                    }
                val sender = PendingIntent.getBroadcast(
                    activity,
                    sessionId,
                    callback,
                    pendingFlags,
                )
                session.commit(sender.intentSender)
            }
            return "installing"
        } catch (_: Exception) {
            if (sessionId >= 0) {
                try { pm.packageInstaller.abandonSession(sessionId) } catch (_: Exception) { }
            }
            return "failed"
        }
    }
}
