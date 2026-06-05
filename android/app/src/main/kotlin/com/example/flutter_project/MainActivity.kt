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
import android.net.Network
import android.net.NetworkRequest
import android.net.ConnectivityManager
import android.net.wifi.WifiManager
import android.net.Uri
import android.content.IntentFilter
import android.content.Context
import android.content.BroadcastReceiver
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.ActivityInfo
import androidx.core.content.FileProvider
import com.caverock.androidsvg.SVG
import com.example.flutter_project.serial.SerialPortManager
import com.example.flutter_project.wifi.WifiHelper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors
import kotlin.system.exitProcess

class MainActivity : FlutterActivity() {
    private val channelName = "svg_renderer"
    private val serialMethodChannel = "serial_port"
    private val serialEventChannel = "serial_port/events"
    private val settingsChannel = "app_settings"
    private val wifiManagerChannel = "wifi_manager"
    private val serialManager = SerialPortManager()
    private val serialExecutor = Executors.newSingleThreadExecutor()
    private var wifiHelper: WifiHelper? = null
    private var wifiReturnReceiver: BroadcastReceiver? = null
    private var wifiReturnNetworkCallback: ConnectivityManager.NetworkCallback? = null
    private var wifiReturnTimeout: Runnable? = null
    private var wifiReturnPoller: Runnable? = null
    private var wifiReturnBringToFront: Runnable? = null
    private val wifiHandler = Handler(Looper.getMainLooper())
    private var wifiReturnActive = false
    private var wifiReturnInitialConnected = false
    private var wifiReturnInitialSsid: String? = null
    private var wifiReturnInitialNetworkId: String? = null
    private var wifiReturnSawDisconnect = false
    private var wifiReturnAttemptsRemaining = 0
    private var activityResumed = false
    private var launcherEnsurePosted = false

    data class RootCommandResult(
        val success: Boolean,
        val exitCode: Int,
        val output: String,
        val suPath: String?,
    )

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

    private fun getActiveNetworkId(): String? {
        return try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val network = cm.activeNetwork ?: return null
            network.toString()
        } catch (_: Exception) {
            null
        }
    }

    private fun cleanupWifiAutoReturn() {
        wifiReturnActive = false
        try {
            if (wifiReturnReceiver != null) {
                unregisterReceiver(wifiReturnReceiver)
            }
        } catch (_: Exception) {
        }
        wifiReturnReceiver = null
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            if (wifiReturnNetworkCallback != null) {
                cm.unregisterNetworkCallback(wifiReturnNetworkCallback!!)
            }
        } catch (_: Exception) {
        }
        wifiReturnNetworkCallback = null
        if (wifiReturnTimeout != null) {
            wifiHandler.removeCallbacks(wifiReturnTimeout!!)
        }
        wifiReturnTimeout = null
        if (wifiReturnPoller != null) {
            wifiHandler.removeCallbacks(wifiReturnPoller!!)
        }
        wifiReturnPoller = null
        if (wifiReturnBringToFront != null) {
            wifiHandler.removeCallbacks(wifiReturnBringToFront!!)
        }
        wifiReturnBringToFront = null
        wifiReturnInitialNetworkId = null
        wifiReturnSawDisconnect = false
        wifiReturnAttemptsRemaining = 0
    }

    private fun returnToApp() {
        val launch = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
            )
        } ?: Intent(this, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
            )
        }
        startActivity(launch)
    }

    private fun scheduleReturnToAppAttempts() {
        if (!wifiReturnActive) return
        if (wifiReturnBringToFront != null) {
            wifiHandler.removeCallbacks(wifiReturnBringToFront!!)
        }
        wifiReturnAttemptsRemaining = 6
        val runner = object : Runnable {
            override fun run() {
                if (!wifiReturnActive || activityResumed || wifiReturnAttemptsRemaining <= 0) {
                    wifiReturnBringToFront = null
                    return
                }
                wifiReturnAttemptsRemaining -= 1
                returnToApp()
                if (!activityResumed && wifiReturnAttemptsRemaining > 0) {
                    wifiHandler.postDelayed(this, if (wifiReturnAttemptsRemaining >= 3) 500L else 1200L)
                } else {
                    wifiReturnBringToFront = null
                }
            }
        }
        wifiReturnBringToFront = runner
        wifiHandler.post(runner)
    }

    private fun evaluateWifiAutoReturn(trigger: String) {
        if (!wifiReturnActive) return

        val connected = isNetworkConnected()
        val ssid = getWifiSsid()
        val networkId = getActiveNetworkId()

        if (!connected) {
            wifiReturnSawDisconnect = true
            return
        }

        val becameConnected = !wifiReturnInitialConnected && connected
        val ssidChanged =
            wifiReturnInitialSsid != null &&
                ssid != null &&
                ssid.isNotBlank() &&
                ssid != wifiReturnInitialSsid
        val networkChanged =
            wifiReturnInitialNetworkId != null &&
                networkId != null &&
                networkId != wifiReturnInitialNetworkId
        val reconnected = wifiReturnSawDisconnect && connected

        if (becameConnected || ssidChanged || networkChanged || reconnected) {
            scheduleReturnToAppAttempts()
        }
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

    private fun stageApkForPackageInstaller(path: String): File {
        val apkFile = File(path)
        if (!apkFile.exists()) {
            throw IllegalArgumentException("APK not found: $path")
        }

        val targetDir = File(externalCacheDir ?: cacheDir, "installer_apk").apply {
            mkdirs()
        }
        val stagedFile = File(targetDir, "update.apk")
        if (apkFile.absolutePath != stagedFile.absolutePath) {
            apkFile.inputStream().use { input ->
                stagedFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
        }
        stagedFile.setReadable(true, false)
        return stagedFile
    }

    private fun installApkInternal(path: String): Boolean {
        val stagedFile = stageApkForPackageInstaller(path)
        val apkUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            FileProvider.getUriForFile(this, "$packageName.fileprovider", stagedFile)
        } else {
            Uri.fromFile(stagedFile)
        }
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                data = apkUri
                putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
                putExtra(Intent.EXTRA_RETURN_RESULT, false)
            }
        } else {
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(apkUri, "application/vnd.android.package-archive")
            }
        }.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                clipData = android.content.ClipData.newRawUri("apk", apkUri)
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            packageManager.queryIntentActivities(intent, 0).forEach { resolveInfo ->
                grantUriPermission(
                    resolveInfo.activityInfo.packageName,
                    apkUri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
        }
        packageManager.resolveActivity(intent, 0)?.activityInfo?.packageName?.let {
            intent.setPackage(it)
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

    private fun getInstalledAppVersionInfoInternal(): Map<String, Any> {
        val installedInfo = getInstalledPackageInfoSafe(packageName)
        if (installedInfo == null) {
            return mapOf(
                "versionCode" to 0L,
                "versionName" to ""
            )
        }

        return mapOf(
            "versionCode" to getVersionCode(installedInfo),
            "versionName" to (installedInfo.versionName ?: "")
        )
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

    private fun runRootCommandDetailed(command: String): RootCommandResult {
        val candidates = arrayOf("/system/bin/su", "/system/xbin/su", "/su/bin/su", "su")
        var lastOutput = ""
        var lastExitCode = -1
        for (su in candidates) {
            try {
                val process = ProcessBuilder(su)
                    .redirectErrorStream(true)
                    .start()
                process.outputStream.use { out ->
                    out.write((command + "\nexit\n").toByteArray())
                    out.flush()
                }
                val output = process.inputStream.bufferedReader().use { it.readText() }.trim()
                val code = process.waitFor()
                if (code == 0) {
                    return RootCommandResult(
                        success = true,
                        exitCode = code,
                        output = output,
                        suPath = su,
                    )
                }
                lastExitCode = code
                if (output.isNotBlank()) {
                    lastOutput = output
                }
            } catch (_: Exception) {
                // Try next su candidate.
            }
        }
        return RootCommandResult(
            success = false,
            exitCode = lastExitCode,
            output = lastOutput,
            suPath = null,
        )
    }

    private fun runRootCommand(command: String): Boolean {
        return runRootCommandDetailed(command).success
    }

    private fun shellEscape(value: String): String {
        return value.replace("'", "'\"'\"'")
    }

    private fun getAppRootShellCapabilityInternal(): Map<String, Any?> {
        val candidates = arrayOf("/system/bin/su", "/system/xbin/su", "/su/bin/su")
        val reasons = mutableListOf<String>()

        for (su in candidates) {
            val suFile = File(su)
            if (!suFile.exists()) {
                continue
            }
            if (suFile.canExecute()) {
                return mapOf(
                    "available" to true,
                    "path" to su,
                    "reason" to "",
                )
            }
            reasons.add("$su exists but is not executable for the app process")
        }

        return mapOf(
            "available" to false,
            "path" to "",
            "reason" to (
                if (reasons.isNotEmpty()) {
                    reasons.joinToString("; ")
                } else {
                    "No executable su binary is available for the app process."
                }
            ),
        )
    }

    private fun stageApkForSilentInstall(path: String): String {
        val stagedPath = "/data/local/tmp/${packageName.replace('.', '_')}_update.apk"
        val escapedSource = shellEscape(path)
        val escapedDest = shellEscape(stagedPath)

        val staged = runRootCommand(
            "cp '$escapedSource' '$escapedDest' >/dev/null 2>&1 && chmod 0644 '$escapedDest'"
        )
        return if (staged) stagedPath else path
    }

    private fun summarizeInstallOutput(output: String): String {
        if (output.isBlank()) return ""
        val lines = output
            .lines()
            .map { it.trim() }
            .filter { it.isNotEmpty() }

        val interesting = lines.firstOrNull {
            it.contains("INSTALL_", ignoreCase = true) ||
                it.contains("Failure", ignoreCase = true) ||
                it.contains("Permission denied", ignoreCase = true) ||
                it.contains("not allowed", ignoreCase = true) ||
                it.contains("Unknown option", ignoreCase = true) ||
                it.contains("unknown option", ignoreCase = true) ||
                it.contains("Error", ignoreCase = true)
        }
        return (interesting ?: lines.lastOrNull().orEmpty())
            .replace(Regex("\\s+"), " ")
            .trim()
    }

    private fun startDetachedSelfUpdate(
        installSourcePath: String,
        pmFlags: List<String>,
    ): RootCommandResult {
        val logPath = "/data/local/tmp/${packageName.replace('.', '_')}_silent_update.log"
        val escapedLogPath = shellEscape(logPath)
        val escapedApkPath = shellEscape(installSourcePath)
        val escapedPackage = shellEscape(packageName)
        val escapedComponent = shellEscape("$packageName/.MainActivity")
        val pmArgs = pmFlags.joinToString(" ")
        val cmdInstallBlock = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            """
            elif cmd package install $pmArgs "${'$'}APK"; then
              rc=0
            """.trimIndent()
        } else {
            ""
        }

        val command =
            """
            LOG='$escapedLogPath'
            APK='$escapedApkPath'
            PKG='$escapedPackage'
            COMPONENT='$escapedComponent'
            sleep 2
            am force-stop "${'$'}PKG" >/dev/null 2>&1 || true
            pid=$(pidof "${'$'}PKG" 2>/dev/null | awk '{print $1}')
            [ -n "${'$'}pid" ] && kill -9 "${'$'}pid" >/dev/null 2>&1 || true

            if pm install $pmArgs "${'$'}APK" > "${'$'}LOG" 2>&1; then
              rc=0
            elif pm install $pmArgs --user 0 "${'$'}APK" >> "${'$'}LOG" 2>&1; then
              rc=0
            $cmdInstallBlock
            else
              session_id=$(cmd package install-create $pmArgs 2>>"${'$'}LOG" | sed -n 's/.*\[\(.*\)\].*/\1/p' | tail -n 1)
              if [ -n "${'$'}session_id" ]; then
                apk_size=$(wc -c < "${'$'}APK")
                if cmd package install-write -S "${'$'}apk_size" "${'$'}session_id" base.apk "${'$'}APK" >> "${'$'}LOG" 2>&1 &&
                  cmd package install-commit "${'$'}session_id" >> "${'$'}LOG" 2>&1; then
                  rc=0
                else
                  rc=1
                fi
              else
                rc=1
              fi
            fi

            echo "RC=${'$'}rc" >> "${'$'}LOG"
            if [ "${'$'}rc" -eq 0 ]; then
              rm -f "${'$'}APK" >/dev/null 2>&1 || true
              am start -n "${'$'}COMPONENT" >> "${'$'}LOG" 2>&1 ||
                monkey -p "${'$'}PKG" -c android.intent.category.LAUNCHER 1 >> "${'$'}LOG" 2>&1 ||
                true
            fi
            exit "${'$'}rc"
            """.trimIndent()

        val candidates = arrayOf("/system/bin/su", "/system/xbin/su", "/su/bin/su", "su")
        val skipped = mutableListOf<String>()
        for (su in candidates) {
            try {
                if (su != "su") {
                    val suFile = File(su)
                    if (!suFile.exists()) {
                        skipped.add("$su not found")
                        continue
                    }
                    if (!suFile.canExecute()) {
                        skipped.add("$su exists but is not executable for the app process")
                        continue
                    }
                }
                val process = ProcessBuilder(su)
                    .redirectErrorStream(true)
                    .start()
                process.outputStream.use { out ->
                    out.write((command + "\nexit\n").toByteArray())
                    out.flush()
                }
                return RootCommandResult(
                    success = true,
                    exitCode = 0,
                    output = "STARTED:$logPath",
                    suPath = su,
                )
            } catch (_: Exception) {
                // Try next su candidate.
            }
        }

        return RootCommandResult(
            success = false,
            exitCode = -1,
            output = if (skipped.isNotEmpty()) {
                "Could not start root shell for background self-update. ${skipped.joinToString("; ")}"
            } else {
                "Could not start root shell for background self-update."
            },
            suPath = null,
        )
    }

    private fun closeForBackgroundUpdateInternal(): Boolean {
        wifiHandler.postDelayed({
            try {
                moveTaskToBack(true)
            } catch (_: Exception) {
            }
            try {
                finishAffinity()
            } catch (_: Exception) {
            }
            try {
                finishAndRemoveTask()
            } catch (_: Exception) {
            }
            try {
                android.os.Process.killProcess(android.os.Process.myPid())
            } catch (_: Exception) {
            }
            try {
                exitProcess(0)
            } catch (_: Exception) {
            }
        }, 500L)
        return true
    }

    private fun installApkSilentlyDetailedInternal(path: String): Map<String, Any?> {
        val apkFile = File(path)
        if (!apkFile.exists()) {
            throw IllegalArgumentException("APK not found: $path")
        }

        val installSourcePath = stageApkForSilentInstall(path)
        val escapedPath = installSourcePath.replace("\"", "\\\"")
        val pmFlags = mutableListOf("-r", "-d")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            pmFlags.add("-g")
        }

        val attempts = mutableListOf<Map<String, Any?>>()
        val commands = mutableListOf(
            "pm install" to "pm install ${pmFlags.joinToString(" ")} \"$escapedPath\"",
            "pm install --user 0" to "pm install ${pmFlags.joinToString(" ")} --user 0 \"$escapedPath\""
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            commands.add(
                "cmd package install" to
                    "cmd package install ${pmFlags.joinToString(" ")} \"$escapedPath\""
            )
        }
        commands.add(
            "cmd package session install" to
            """
            session_id=$(
              cmd package install-create ${pmFlags.joinToString(" ")} 2>/dev/null |
              sed -n 's/.*\[\(.*\)\].*/\1/p' |
              tail -n 1
            )
            [ -n "${'$'}session_id" ] || exit 1
            apk_size=$(wc -c < "$escapedPath")
            cmd package install-write -S "${'$'}apk_size" "${'$'}session_id" base.apk "$escapedPath" >/dev/null 2>&1 &&
            cmd package install-commit "${'$'}session_id" >/dev/null 2>&1
            """.trimIndent()
        )

        for ((label, command) in commands) {
            val result = runRootCommandDetailed(command)
            val installOutput = summarizeInstallOutput(result.output)
            val installedVersionChanged =
                result.success && !isApkNewerThanInstalledInternal(path)
            val effectiveSuccess = result.success && installedVersionChanged
            val effectiveOutput =
                if (result.success && !installedVersionChanged) {
                    "Package manager reported success, but installed version did not change."
                } else {
                    installOutput
                }
            attempts.add(
                mapOf(
                    "label" to label,
                    "success" to effectiveSuccess,
                    "exitCode" to result.exitCode,
                    "output" to effectiveOutput,
                    "suPath" to result.suPath,
                )
            )
            if (effectiveSuccess) {
                if (installSourcePath != path) {
                    runRootCommand("rm -f \"${installSourcePath.replace("\"", "\\\"")}\" >/dev/null 2>&1 || true")
                }
                return mapOf(
                    "success" to true,
                    "deferred" to false,
                    "message" to "Installed silently via $label.",
                    "command" to label,
                    "exitCode" to result.exitCode,
                    "output" to effectiveOutput,
                    "sourcePath" to installSourcePath,
                    "attempts" to attempts,
                )
            }
        }

        val detachedResult = startDetachedSelfUpdate(installSourcePath, pmFlags)
        attempts.add(
            mapOf(
                "label" to "detached self-update",
                "success" to detachedResult.success,
                "exitCode" to detachedResult.exitCode,
                "output" to summarizeInstallOutput(detachedResult.output),
                "suPath" to detachedResult.suPath,
            )
        )
        if (detachedResult.success) {
            return mapOf(
                "success" to true,
                "deferred" to true,
                "message" to "Started background self-update via root installer.",
                "command" to "detached self-update",
                "exitCode" to detachedResult.exitCode,
                "output" to summarizeInstallOutput(detachedResult.output),
                "sourcePath" to installSourcePath,
                "attempts" to attempts,
            )
        }

        if (installSourcePath != path) {
            runRootCommand("rm -f \"${installSourcePath.replace("\"", "\\\"")}\" >/dev/null 2>&1 || true")
        }
        val lastAttempt = attempts.lastOrNull()
        val bestOutput = attempts
            .mapNotNull { it["output"]?.toString()?.trim() }
            .firstOrNull { it.isNotEmpty() }
            ?: "Silent install command failed with no package-manager output."
        return mapOf(
            "success" to false,
            "deferred" to false,
            "message" to bestOutput,
            "command" to (lastAttempt?.get("label")?.toString() ?: ""),
            "exitCode" to (lastAttempt?.get("exitCode") ?: -1),
            "output" to bestOutput,
            "sourcePath" to installSourcePath,
            "attempts" to attempts,
        )
    }

    private fun installApkSilentlyInternal(path: String): Boolean {
        val detailed = installApkSilentlyDetailedInternal(path)
        return detailed["success"] == true
    }

    private fun setupWifiAutoReturn(timeoutSeconds: Int) {
        cleanupWifiAutoReturn()
        wifiReturnActive = true
        wifiReturnInitialConnected = isNetworkConnected()
        wifiReturnInitialSsid = getWifiSsid()
        wifiReturnInitialNetworkId = getActiveNetworkId()
        wifiReturnSawDisconnect = false

        wifiReturnReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                evaluateWifiAutoReturn(intent.action ?: "broadcast")
            }
        }
        val filter = IntentFilter().apply {
            addAction(ConnectivityManager.CONNECTIVITY_ACTION)
            addAction(WifiManager.NETWORK_STATE_CHANGED_ACTION)
            addAction(WifiManager.WIFI_STATE_CHANGED_ACTION)
            addAction(WifiManager.SUPPLICANT_STATE_CHANGED_ACTION)
        }
        registerReceiver(wifiReturnReceiver, filter)

        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .build()
            wifiReturnNetworkCallback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    evaluateWifiAutoReturn("network_available")
                }

                override fun onCapabilitiesChanged(
                    network: Network,
                    networkCapabilities: NetworkCapabilities,
                ) {
                    evaluateWifiAutoReturn("network_capabilities")
                }

                override fun onLost(network: Network) {
                    wifiReturnSawDisconnect = true
                }
            }
            cm.registerNetworkCallback(request, wifiReturnNetworkCallback!!)
        } catch (_: Exception) {
        }

        wifiReturnPoller = object : Runnable {
            override fun run() {
                evaluateWifiAutoReturn("poll")
                if (wifiReturnActive) {
                    wifiHandler.postDelayed(this, 1000L)
                }
            }
        }
        wifiHandler.postDelayed(wifiReturnPoller!!, 1000L)

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

    override fun onResume() {
        super.onResume()
        activityResumed = true
        if (wifiReturnActive) {
            cleanupWifiAutoReturn()
        }
    }

    override fun onPause() {
        activityResumed = false
        super.onPause()
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
                            val supportsReliableWifiAutoReturn =
                                Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
                            val useAutoReturn =
                                autoReturn && supportsReliableWifiAutoReturn

                            if (useAutoReturn) {
                                setupWifiAutoReturn(timeoutSeconds)
                            } else {
                                cleanupWifiAutoReturn()
                            }
                            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                Intent(Settings.Panel.ACTION_INTERNET_CONNECTIVITY)
                            } else {
                                Intent(Settings.ACTION_WIFI_SETTINGS)
                            }
                            try {
                                startActivity(intent)
                            } catch (_: Exception) {
                                val fallbackIntent = Intent(Settings.ACTION_WIFI_SETTINGS)
                                try {
                                    startActivity(fallbackIntent)
                                } catch (_: Exception) {
                                    val secondFallback = Intent(Settings.ACTION_WIRELESS_SETTINGS)
                                    startActivity(secondFallback)
                                }
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("wifi_settings_failed", e.message, null)
                        }
                    }
                    "canInstallPackages" -> {
                        result.success(canInstallPackagesNow())
                    }
                    "getRootShellCapability" -> {
                        result.success(getAppRootShellCapabilityInternal())
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
                    "installApkSilentlyDetailed" -> {
                        val pathArg = call.argument<String>("path")
                        if (pathArg.isNullOrBlank()) {
                            result.error("install_apk_silent_failed", "path is empty", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(installApkSilentlyDetailedInternal(pathArg))
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
                    "getInstalledAppVersionInfo" -> {
                        try {
                            result.success(getInstalledAppVersionInfoInternal())
                        } catch (e: Exception) {
                            result.error("installed_version_failed", e.message, null)
                        }
                    }
                    "closeForBackgroundUpdate" -> {
                        try {
                            result.success(closeForBackgroundUpdateInternal())
                        } catch (e: Exception) {
                            result.error("close_for_update_failed", e.message, null)
                        }
                    }
                    "applyOrientationMode" -> {
                        try {
                            val forceLandscape = call.argument<Boolean>("forceLandscape") ?: false
                            requestedOrientation =
                                if (forceLandscape) {
                                    ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                                } else {
                                    ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                                }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("apply_orientation_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // WiFi Manager Channel - embedded WiFi management (API 21-26)
        wifiHelper = WifiHelper(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, wifiManagerChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scanWifi" -> {
                        wifiHelper?.startScan { networks ->
                            runOnUiThread { result.success(networks) }
                        }
                    }
                    "connectWifi" -> {
                        val ssid = call.argument<String>("ssid") ?: ""
                        val password = call.argument<String>("password") ?: ""
                        if (ssid.isEmpty()) {
                            result.error("connect_failed", "SSID is empty", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val success = wifiHelper?.connectToNetwork(ssid, password) ?: false
                                runOnUiThread { result.success(success) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("connect_failed", e.message, null)
                                }
                            }
                        }.start()
                    }
                    "disconnectWifi" -> {
                        try {
                            val success = wifiHelper?.disconnectFromNetwork() ?: false
                            result.success(success)
                        } catch (e: Exception) {
                            result.error("disconnect_failed", e.message, null)
                        }
                    }
                    "getCurrentWifi" -> {
                        try {
                            val info = wifiHelper?.getCurrentWifiInfo()
                                ?: mapOf("ssid" to "", "ip" to "", "isConnected" to false)
                            result.success(info)
                        } catch (e: Exception) {
                            result.error("get_wifi_failed", e.message, null)
                        }
                    }
                    "isWifiEnabled" -> {
                        try {
                            result.success(wifiHelper?.isWifiEnabled() ?: false)
                        } catch (e: Exception) {
                            result.error("wifi_enabled_check_failed", e.message, null)
                        }
                    }
                    "enableWifi" -> {
                        try {
                            val success = wifiHelper?.setWifiEnabled(true) ?: false
                            result.success(success)
                        } catch (e: Exception) {
                            result.error("enable_wifi_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

    }

    override fun onDestroy() {
        cleanupWifiAutoReturn()
        wifiHelper?.cleanup()
        wifiHelper = null
        serialExecutor.shutdownNow()
        serialManager.close()
        super.onDestroy()
    }
}
