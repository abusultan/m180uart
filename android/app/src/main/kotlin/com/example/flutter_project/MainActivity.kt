package com.example.flutter_project

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.PorterDuff
import android.content.Intent
import android.provider.Settings
import android.os.Looper
import android.os.Handler
import android.os.Build
import android.os.Bundle
import android.net.NetworkCapabilities
import android.net.ConnectivityManager
import android.net.wifi.WifiManager
import android.net.Uri
import android.content.IntentFilter
import android.content.Context
import android.content.BroadcastReceiver
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import androidx.core.content.FileProvider
import com.caverock.androidsvg.SVG
import com.example.flutter_project.serial.SerialPortManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "svg_renderer"
    private val serialMethodChannel = "serial_port"
    private val serialEventChannel = "serial_port/events"
    private val settingsChannel = "app_settings"
    private val serialManager = SerialPortManager()
    private val serialExecutor = Executors.newSingleThreadExecutor()
    private var wifiReturnReceiver: BroadcastReceiver? = null
    private var wifiReturnTimeout: Runnable? = null
    private var wifiReturnPoller: Runnable? = null
    private val wifiHandler = Handler(Looper.getMainLooper())
    private var wifiReturnInitialConnected = false
    private var wifiReturnInitialSsid: String? = null
    private var launcherEnsurePosted = false

    private fun decodeSvg(bytes: ByteArray): String {
        if (bytes.size >= 2) {
            val b0 = bytes[0]
            val b1 = bytes[1]
            if (b0 == 0xFF.toByte() && b1 == 0xFE.toByte()) {
                return sanitizeSvg(String(bytes, Charsets.UTF_16LE))
            }
            if (b0 == 0xFE.toByte() && b1 == 0xFF.toByte()) {
                return sanitizeSvg(String(bytes, Charsets.UTF_16BE))
            }
        }
        val headLen = if (bytes.size > 200) 200 else bytes.size
        val head = String(bytes, 0, headLen, Charsets.ISO_8859_1)
        return if (head.contains("encoding=\"UTF-16\"") || head.contains("encoding='UTF-16'")) {
            sanitizeSvg(String(bytes, Charsets.UTF_16LE))
        } else {
            sanitizeSvg(String(bytes, Charsets.UTF_8))
        }
    }

    private fun sanitizeSvg(input: String): String {
        var text = input
        text = text.replace(Regex("<\\?xml[^>]*\\?>"), "")
        text = text.replace(Regex("<!DOCTYPE[^>]*>"), "")
        text = text.replace(Regex("<metadata[^>]*>.*?</metadata>", RegexOption.DOT_MATCHES_ALL), "")
        return text
    }

    private fun isNetworkConnected(): Boolean {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val network = cm.activeNetwork ?: return false
            val caps = cm.getNetworkCapabilities(network) ?: return false
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        } else {
            @Suppress("DEPRECATION")
            val info = cm.activeNetworkInfo
            info != null && info.isConnected
        }
    }

    private fun getWifiSsid(): String? {
        return try {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val info = wm.connectionInfo ?: return null
            val raw = info.ssid ?: return null
            if (raw == "<unknown ssid>") return null
            raw.trim('"')
        } catch (_: Exception) {
            null
        }
    }

    private fun cleanupWifiAutoReturn() {
        try {
            if (wifiReturnReceiver != null) {
                unregisterReceiver(wifiReturnReceiver)
            }
        } catch (_: Exception) {
        }
        wifiReturnReceiver = null
        if (wifiReturnTimeout != null) {
            wifiHandler.removeCallbacks(wifiReturnTimeout!!)
        }
        wifiReturnTimeout = null
        if (wifiReturnPoller != null) {
            wifiHandler.removeCallbacks(wifiReturnPoller!!)
        }
        wifiReturnPoller = null
    }

    private fun returnToApp() {
        val launch = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        startActivity(launch)
    }

    private fun buildHomeIntent(): Intent {
        return Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            addCategory(Intent.CATEGORY_DEFAULT)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
    }

    private fun isDefaultLauncherInternal(): Boolean {
        return try {
            val resolved = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.resolveActivity(
                    buildHomeIntent(),
                    PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_DEFAULT_ONLY.toLong())
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.resolveActivity(buildHomeIntent(), PackageManager.MATCH_DEFAULT_ONLY)
            } ?: return false

            val homePackage = resolved.activityInfo?.packageName ?: return false
            homePackage == packageName
        } catch (_: Exception) {
            false
        }
    }

    private fun queryHomePackages(): List<String> {
        return try {
            val infos = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.queryIntentActivities(
                    buildHomeIntent(),
                    PackageManager.ResolveInfoFlags.of(0)
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.queryIntentActivities(buildHomeIntent(), 0)
            }

            infos
                .mapNotNull { it.activityInfo?.packageName }
                .filter { it.isNotBlank() }
                .distinct()
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun promptHomeSelection() {
        try {
            startActivity(buildHomeIntent())
        } catch (_: Exception) {
        }
    }

    private fun tryForceDefaultLauncherWithRoot(): Boolean {
        val otherHomePackages = queryHomePackages()
            .filter { it != packageName && it != "android" }

        if (otherHomePackages.isEmpty()) {
            return false
        }

        runRootCommand("pm enable \"$packageName\" >/dev/null 2>&1 || true")

        var changed = false
        for (launcherPackage in otherHomePackages) {
            val disabled = runRootCommand(
                "pm disable \"$launcherPackage\" >/dev/null 2>&1 || pm disable-user \"$launcherPackage\" >/dev/null 2>&1"
            )
            if (disabled) {
                changed = true
            }
        }

        if (changed) {
            promptHomeSelection()
            return true
        }

        return false
    }

    private fun ensureLauncherDefaultOnStartup() {
        if (launcherEnsurePosted) return
        launcherEnsurePosted = true

        wifiHandler.postDelayed({
            if (isFinishing || isDestroyed) return@postDelayed
            if (isDefaultLauncherInternal()) return@postDelayed
            if (tryForceDefaultLauncherWithRoot()) return@postDelayed
            promptHomeSelection()
        }, 250L)
    }

    private fun canInstallPackagesNow(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    }

    private fun openUnknownSourcesSettingsInternal(): Boolean {
        return try {
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName")
                )
            } else {
                Intent(Settings.ACTION_SECURITY_SETTINGS)
            }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun installApkInternal(path: String): Boolean {
        val apkFile = File(path)
        if (!apkFile.exists()) {
            throw IllegalArgumentException("APK not found: $path")
        }

        val apkUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            FileProvider.getUriForFile(this, "$packageName.fileprovider", apkFile)
        } else {
            Uri.fromFile(apkFile)
        }

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(intent)
        return true
    }

    private fun getInstalledPackageInfoSafe(packageName: String): PackageInfo? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(
                    packageName,
                    PackageManager.PackageInfoFlags.of(0)
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, 0)
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun getArchivePackageInfoSafe(path: String): PackageInfo? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageArchiveInfo(
                    path,
                    PackageManager.PackageInfoFlags.of(0)
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageArchiveInfo(path, 0)
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun getVersionCode(info: PackageInfo): Long {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
    }

    private fun isApkNewerThanInstalledInternal(path: String): Boolean {
        val apkFile = File(path)
        if (!apkFile.exists()) {
            throw IllegalArgumentException("APK not found: $path")
        }

        val archiveInfo = getArchivePackageInfoSafe(path) ?: return false
        val archivePackageName = archiveInfo.packageName ?: return false
        if (archivePackageName != packageName) {
            return false
        }

        val installedInfo = getInstalledPackageInfoSafe(packageName) ?: return true
        val incomingVersionCode = getVersionCode(archiveInfo)
        val installedVersionCode = getVersionCode(installedInfo)
        return incomingVersionCode > installedVersionCode
    }

    private fun runRootCommand(command: String): Boolean {
        val candidates = arrayOf("/system/bin/su", "/system/xbin/su", "/su/bin/su", "su")
        for (su in candidates) {
            try {
                val process = Runtime.getRuntime().exec(su)
                process.outputStream.use { out ->
                    out.write(("sh -c '$command'\nexit\n").toByteArray())
                    out.flush()
                }
                val code = process.waitFor()
                if (code == 0) return true
            } catch (_: Exception) {
                // Try next su candidate.
            }
        }
        return false
    }

    private fun installApkSilentlyInternal(path: String): Boolean {
        val apkFile = File(path)
        if (!apkFile.exists()) {
            throw IllegalArgumentException("APK not found: $path")
        }

        val escapedPath = path.replace("\"", "\\\"")
        val pmFlags = mutableListOf("-r", "-d")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            pmFlags.add("-g")
        }

        val commands = mutableListOf(
            "pm install ${pmFlags.joinToString(" ")} \"$escapedPath\""
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            commands.add("cmd package install ${pmFlags.joinToString(" ")} \"$escapedPath\"")
        }

        for (command in commands) {
            if (runRootCommand(command)) {
                return true
            }
        }
        return false
    }

    private fun setupWifiAutoReturn(timeoutSeconds: Int) {
        cleanupWifiAutoReturn()
        wifiReturnInitialConnected = isNetworkConnected()
        wifiReturnInitialSsid = getWifiSsid()

        wifiReturnReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val connected = isNetworkConnected()
                val ssid = getWifiSsid()
                val wifiChanged = ssid != null && ssid != wifiReturnInitialSsid
                if (wifiReturnInitialConnected && !connected) {
                    wifiReturnInitialConnected = false
                    return
                }
                if ((!wifiReturnInitialConnected && connected) || wifiChanged) {
                    cleanupWifiAutoReturn()
                    returnToApp()
                }
            }
        }
        registerReceiver(wifiReturnReceiver, IntentFilter(ConnectivityManager.CONNECTIVITY_ACTION))

        wifiReturnPoller = object : Runnable {
            override fun run() {
                val connected = isNetworkConnected()
                val ssid = getWifiSsid()
                val wifiChanged = ssid != null && ssid != wifiReturnInitialSsid
                if ((!wifiReturnInitialConnected && connected) || wifiChanged) {
                    cleanupWifiAutoReturn()
                    returnToApp()
                    return
                }
                wifiHandler.postDelayed(this, 1500L)
            }
        }
        wifiHandler.postDelayed(wifiReturnPoller!!, 1500L)

        wifiReturnTimeout = Runnable {
            cleanupWifiAutoReturn()
            returnToApp()
        }
        wifiHandler.postDelayed(wifiReturnTimeout!!, (timeoutSeconds.coerceAtLeast(5) * 1000L))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ensureLauncherDefaultOnStartup()
    }


    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "renderSvg" -> {
                        try {
                            val svgText = call.argument<String>("svg") ?: ""
                            val width = call.argument<Int>("width") ?: 0
                            val height = call.argument<Int>("height") ?: 0
                            if (svgText.isEmpty() || width <= 0 || height <= 0) {
                                result.success(null)
                                return@setMethodCallHandler
                            }
                            val svg = SVG.getFromString(svgText)
                            svg.documentWidth = width.toFloat()
                            svg.documentHeight = height.toFloat()
                            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                            val canvas = Canvas(bitmap)
                            canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)
                            svg.renderToCanvas(canvas)
                            val stream = ByteArrayOutputStream()
                            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                            result.success(stream.toByteArray())
                        } catch (_: Exception) {
                            result.success(null)
                        }
                    }
                    "renderSvgBytes" -> {
                        try {
                            val bytes = call.argument<ByteArray>("bytes")
                            val width = call.argument<Int>("width") ?: 0
                            val height = call.argument<Int>("height") ?: 0
                            if (bytes == null || bytes.isEmpty() || width <= 0 || height <= 0) {
                                result.success(null)
                                return@setMethodCallHandler
                            }
                            val decoded = decodeSvg(bytes)
                            val svg = SVG.getFromString(decoded)
                            svg.documentWidth = width.toFloat()
                            svg.documentHeight = height.toFloat()
                            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                            val canvas = Canvas(bitmap)
                            canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)
                            svg.renderToCanvas(canvas)
                            val stream = ByteArrayOutputStream()
                            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                            result.success(stream.toByteArray())
                        } catch (_: Exception) {
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, serialEventChannel)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    serialManager.setEventSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    serialManager.setEventSink(null)
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, serialMethodChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "open" -> {
                        val path = call.argument<String>("path")
                        val baud = call.argument<Int>("baud") ?: 115200
                        serialExecutor.execute {
                            try {
                                val ok = serialManager.open(path, baud)
                                runOnUiThread { result.success(ok) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("open_failed", e.message, null)
                                }
                            }
                        }
                    }
                    "close" -> {
                        serialExecutor.execute {
                            serialManager.close()
                            runOnUiThread { result.success(true) }
                        }
                    }
                    "write" -> {
                        val data = call.argument<String>("data") ?: ""
                        serialExecutor.execute {
                            try {
                                serialManager.write(data.toByteArray(Charsets.ISO_8859_1))
                                runOnUiThread { result.success(true) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("write_failed", e.message, null)
                                }
                            }
                        }
                    }
                    "writeBytes" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        if (bytes == null) {
                            result.error("write_failed", "bytes is null", null)
                        } else {
                            serialExecutor.execute {
                                try {
                                    serialManager.write(bytes)
                                    runOnUiThread { result.success(true) }
                                } catch (e: Exception) {
                                    runOnUiThread {
                                        result.error("write_failed", e.message, null)
                                    }
                                }
                            }
                        }
                    }
                    "isOpen" -> {
                        serialExecutor.execute {
                            runOnUiThread { result.success(serialManager.isOpen()) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, settingsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openWifiSettings" -> {
                        try {
                            val autoReturn = call.argument<Boolean>("autoReturn") ?: true
                            val timeoutSeconds = call.argument<Int>("timeoutSeconds") ?: 30
                            if (autoReturn) {
                                setupWifiAutoReturn(timeoutSeconds)
                            } else {
                                cleanupWifiAutoReturn()
                            }
                            val intent = Intent(Settings.ACTION_WIFI_SETTINGS)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("wifi_settings_failed", e.message, null)
                        }
                    }
                    "canInstallPackages" -> {
                        result.success(canInstallPackagesNow())
                    }
                    "openInstallUnknownSourcesSettings" -> {
                        result.success(openUnknownSourcesSettingsInternal())
                    }
                    "installApk" -> {
                        val pathArg = call.argument<String>("path")
                        if (pathArg.isNullOrBlank()) {
                            result.error("install_apk_failed", "path is empty", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(installApkInternal(pathArg))
                        } catch (e: Exception) {
                            result.error("install_apk_failed", e.message, null)
                        }
                    }
                    "installApkSilently" -> {
                        val pathArg = call.argument<String>("path")
                        if (pathArg.isNullOrBlank()) {
                            result.error("install_apk_silent_failed", "path is empty", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(installApkSilentlyInternal(pathArg))
                        } catch (e: Exception) {
                            result.error("install_apk_silent_failed", e.message, null)
                        }
                    }
                    "isApkNewerThanInstalled" -> {
                        val pathArg = call.argument<String>("path")
                        if (pathArg.isNullOrBlank()) {
                            result.error("apk_version_check_failed", "path is empty", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(isApkNewerThanInstalledInternal(pathArg))
                        } catch (e: Exception) {
                            result.error("apk_version_check_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }


    }

    override fun onDestroy() {
        cleanupWifiAutoReturn()
        serialExecutor.shutdownNow()
        serialManager.close()
        super.onDestroy()
    }
}
