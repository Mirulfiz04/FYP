package com.example.meds_flutter_no_python

import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.HttpURLConnection
import java.net.URL

class MainActivity : FlutterActivity() {
    private val channelName = "meds/wifi_sensor"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "fetchOverWifi" -> {
                        val url = call.argument<String>("url")
                        val timeoutMs = call.argument<Int>("timeoutMs") ?: 4000
                        if (url == null) {
                            result.error("ARG", "url is required", null)
                        } else {
                            fetchOverWifi(url, timeoutMs, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Fetches [url] over the Wi-Fi transport specifically, so a request to the
     * ESP32 hotspot (e.g. http://192.168.4.1/data) still reaches it even when
     * mobile data is the default (internet) network. Only this one connection is
     * pinned to Wi-Fi — the rest of the app keeps using the default route, so
     * Supabase/cloud traffic still goes out over cellular.
     */
    private fun fetchOverWifi(url: String, timeoutMs: Int, result: MethodChannel.Result) {
        Thread {
            try {
                val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
                val wifi: Network? = cm.allNetworks.firstOrNull { network ->
                    cm.getNetworkCapabilities(network)
                        ?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
                }
                if (wifi == null) {
                    runOnUiThread {
                        result.error("NO_WIFI", "Not connected to a Wi-Fi network", null)
                    }
                    return@Thread
                }

                val conn = wifi.openConnection(URL(url)) as HttpURLConnection
                conn.connectTimeout = timeoutMs
                conn.readTimeout = timeoutMs
                conn.requestMethod = "GET"
                try {
                    val code = conn.responseCode
                    if (code != 200) {
                        runOnUiThread { result.error("HTTP", "HTTP $code", null) }
                        return@Thread
                    }
                    val body = conn.inputStream.bufferedReader().use { it.readText() }
                    runOnUiThread { result.success(body) }
                } finally {
                    conn.disconnect()
                }
            } catch (e: Exception) {
                runOnUiThread { result.error("FETCH", e.message ?: e.toString(), null) }
            }
        }.start()
    }
}
