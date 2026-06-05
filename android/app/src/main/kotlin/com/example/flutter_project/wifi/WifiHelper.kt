package com.example.flutter_project.wifi

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.wifi.ScanResult
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.text.format.Formatter

class WifiHelper(private val context: Context) {

    private val wifiManager: WifiManager =
        context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager

    private var scanReceiver: BroadcastReceiver? = null
    private var scanCallback: ((List<Map<String, Any>>) -> Unit)? = null
    private val handler = Handler(Looper.getMainLooper())

    fun isWifiEnabled(): Boolean = wifiManager.isWifiEnabled

    @Suppress("DEPRECATION")
    fun setWifiEnabled(enabled: Boolean): Boolean {
        return wifiManager.setWifiEnabled(enabled)
    }

    fun startScan(callback: (List<Map<String, Any>>) -> Unit) {
        scanCallback = callback
        unregisterScanReceiver()

        scanReceiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                val success = intent?.getBooleanExtra(
                    WifiManager.EXTRA_RESULTS_UPDATED, false
                ) ?: false
                handleScanResults(success)
            }
        }

        val filter = IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION)
        context.registerReceiver(scanReceiver, filter)

        @Suppress("DEPRECATION")
        val started = wifiManager.startScan()
        if (!started) {
            // If startScan returns false, still try to get cached results
            handler.postDelayed({ handleScanResults(false) }, 500)
        }
    }

    private fun handleScanResults(success: Boolean) {
        val results = wifiManager.scanResults ?: emptyList()
        val currentSsid = getCurrentSsid()
        val networks = buildNetworkList(results, currentSsid)
        unregisterScanReceiver()
        scanCallback?.invoke(networks)
        scanCallback = null
    }

    private fun buildNetworkList(
        results: List<ScanResult>,
        currentSsid: String?
    ): List<Map<String, Any>> {
        val seen = mutableSetOf<String>()
        val networks = mutableListOf<Map<String, Any>>()

        // Sort by signal strength descending
        val sorted = results.sortedByDescending { it.level }

        for (result in sorted) {
            val ssid = result.SSID ?: ""
            if (ssid.isBlank() || ssid in seen) continue
            seen.add(ssid)

            val security = getSecurityType(result)
            val isConnected = currentSsid != null && ssid == currentSsid

            networks.add(
                mapOf(
                    "ssid" to ssid,
                    "level" to result.level,
                    "security" to security,
                    "isConnected" to isConnected
                )
            )
        }
        return networks
    }

    private fun getSecurityType(result: ScanResult): String {
        val caps = result.capabilities ?: ""
        return when {
            caps.contains("WPA2") -> "WPA2"
            caps.contains("WPA") -> "WPA"
            caps.contains("WEP") -> "WEP"
            else -> "OPEN"
        }
    }

    @Suppress("DEPRECATION")
    fun connectToNetwork(ssid: String, password: String): Boolean {
        if (!wifiManager.isWifiEnabled) {
            wifiManager.setWifiEnabled(true)
            Thread.sleep(1500)
        }

        // Remove any existing configuration for this SSID
        val existingConfigs = try {
            wifiManager.configuredNetworks
        } catch (_: SecurityException) {
            null
        }
        existingConfigs?.forEach { config ->
            if (config.SSID == "\"$ssid\"") {
                wifiManager.removeNetwork(config.networkId)
            }
        }

        val config = WifiConfiguration().apply {
            SSID = "\"$ssid\""
            if (password.isEmpty()) {
                // Open network
                allowedKeyManagement.set(WifiConfiguration.KeyMgmt.NONE)
            } else {
                // WPA/WPA2
                preSharedKey = "\"$password\""
                allowedKeyManagement.set(WifiConfiguration.KeyMgmt.WPA_PSK)
                allowedProtocols.set(WifiConfiguration.Protocol.RSN)
                allowedProtocols.set(WifiConfiguration.Protocol.WPA)
                allowedPairwiseCiphers.set(WifiConfiguration.PairwiseCipher.CCMP)
                allowedPairwiseCiphers.set(WifiConfiguration.PairwiseCipher.TKIP)
                allowedGroupCiphers.set(WifiConfiguration.GroupCipher.CCMP)
                allowedGroupCiphers.set(WifiConfiguration.GroupCipher.TKIP)
                allowedGroupCiphers.set(WifiConfiguration.GroupCipher.WEP40)
                allowedGroupCiphers.set(WifiConfiguration.GroupCipher.WEP104)
            }
        }

        val networkId = wifiManager.addNetwork(config)
        if (networkId == -1) return false

        wifiManager.disconnect()
        val enabled = wifiManager.enableNetwork(networkId, true)
        wifiManager.reconnect()

        // Wait briefly to check if connection is successful
        Thread.sleep(3000)

        val connectedSsid = getCurrentSsid()
        return enabled && connectedSsid == ssid
    }

    @Suppress("DEPRECATION")
    fun disconnectFromNetwork(): Boolean {
        return wifiManager.disconnect()
    }

    @Suppress("DEPRECATION")
    fun getCurrentWifiInfo(): Map<String, Any> {
        val info: WifiInfo? = wifiManager.connectionInfo
        val ssid = info?.ssid?.removePrefix("\"")?.removeSuffix("\"") ?: ""
        val ipAddress = info?.ipAddress ?: 0
        val ip = Formatter.formatIpAddress(ipAddress)
        val isConnected = info != null &&
                info.networkId != -1 &&
                ssid != "<unknown ssid>" &&
                ssid.isNotBlank()

        return mapOf(
            "ssid" to if (isConnected) ssid else "",
            "ip" to if (isConnected) ip else "",
            "isConnected" to isConnected
        )
    }

    @Suppress("DEPRECATION")
    private fun getCurrentSsid(): String? {
        val info = wifiManager.connectionInfo ?: return null
        val ssid = info.ssid?.removePrefix("\"")?.removeSuffix("\"")
        if (ssid == "<unknown ssid>" || ssid.isNullOrBlank() || info.networkId == -1) {
            return null
        }
        return ssid
    }

    private fun unregisterScanReceiver() {
        scanReceiver?.let {
            try {
                context.unregisterReceiver(it)
            } catch (_: IllegalArgumentException) {
                // Already unregistered
            }
        }
        scanReceiver = null
    }

    fun cleanup() {
        unregisterScanReceiver()
        scanCallback = null
    }
}
