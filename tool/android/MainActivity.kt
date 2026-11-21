package ro.noraz.nauto

import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Bridge between the Flutter UI and the background monitor. */
class MainActivity : FlutterActivity() {

    override fun onResume() {
        super.onResume()
        // Log access (READ_LOGS over adb) is only granted while the app is visible.
        if (MonitorService.running) MonitorService.start(this, MonitorService.ACTION_LOGS)
    }

    private fun granted(p: String) = checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED

    @SuppressLint("MissingPermission")
    private fun bonded(): List<String> = try {
        if (Build.VERSION.SDK_INT >= 31 && !granted("android.permission.BLUETOOTH_CONNECT")) emptyList()
        else getSystemService(BluetoothManager::class.java).adapter?.bondedDevices?.mapNotNull { it.name } ?: emptyList()
    } catch (_: Throwable) {
        emptyList()
    }

    private fun status(): Map<String, Any?> {
        val pm = getSystemService(PowerManager::class.java)
        val p = MonitorService.prefs(this)
        val lm = getSystemService(LocationManager::class.java)
        val wifiOn = try { applicationContext.getSystemService(WifiManager::class.java).isWifiEnabled } catch (_: Throwable) { false }
        val btOn = try { getSystemService(BluetoothManager::class.java).adapter?.isEnabled == true } catch (_: Throwable) { false }
        return mapOf(
            "running" to MonitorService.running,
            "enabled" to p.getBoolean("enabled", false),
            "files" to filesDir.absolutePath,
            "prefix" to (p.getString("prefix", "AAWireless") ?: "AAWireless"),
            "permBt" to (Build.VERSION.SDK_INT < 31 || granted("android.permission.BLUETOOTH_CONNECT")),
            "permLoc" to granted("android.permission.ACCESS_FINE_LOCATION"),
            "permBgLoc" to (Build.VERSION.SDK_INT < 29 || granted("android.permission.ACCESS_BACKGROUND_LOCATION")),
            "permNotif" to (Build.VERSION.SDK_INT < 33 || granted("android.permission.POST_NOTIFICATIONS")),
            "permLogs" to granted("android.permission.READ_LOGS"),
            "selfOpt" to !pm.isIgnoringBatteryOptimizations(packageName),
            "aaOpt" to !pm.isIgnoringBatteryOptimizations(MonitorService.GEARHEAD),
            "aaVer" to MonitorService.aaVersion(this),
            "locOn" to (Build.VERSION.SDK_INT < 28 || lm.isLocationEnabled),
            "wifiOn" to wifiOn,
            "btOn" to btOn,
            "bonded" to bonded(),
            "model" to "${Build.MANUFACTURER} ${Build.MODEL}",
            "android" to "${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})",
        )
    }

    private fun openDetails(pkg: String) {
        try {
            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$pkg")))
        } catch (_: Throwable) {
        }
    }

    /** Saves a text report to Downloads/Nauto so it can be sent from any app. */
    private fun saveReport(name: String, text: String): String? = try {
        if (Build.VERSION.SDK_INT >= 29) {
            val v = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, "text/plain")
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/Nauto")
            }
            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, v)!!
            contentResolver.openOutputStream(uri)!!.use { it.write(text.toByteArray()) }
            "Download/Nauto/$name"
        } else {
            @Suppress("DEPRECATION")
            val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "Nauto")
            dir.mkdirs()
            File(dir, name).writeText(text)
            "Download/Nauto/$name"
        }
    } catch (_: Throwable) {
        null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nauto/native").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "status" -> result.success(status())
                    "start" -> {
                        MonitorService.prefs(this).edit().putBoolean("enabled", true).apply()
                        MonitorService.start(this)
                        MonitorService.start(this, MonitorService.ACTION_LOGS)
                        result.success(true)
                    }
                    "stop" -> {
                        MonitorService.prefs(this).edit().putBoolean("enabled", false).apply()
                        stopService(Intent(this, MonitorService::class.java))
                        result.success(true)
                    }
                    "setPrefs" -> {
                        val e = MonitorService.prefs(this).edit()
                        call.argument<String>("prefix")?.let { e.putString("prefix", it) }
                        call.argument<String>("lang")?.let { e.putString("lang", it) }
                        e.apply()
                        result.success(true)
                    }
                    "requestPerms" -> {
                        val list = mutableListOf("android.permission.ACCESS_FINE_LOCATION")
                        if (Build.VERSION.SDK_INT >= 31) list += "android.permission.BLUETOOTH_CONNECT"
                        if (Build.VERSION.SDK_INT >= 33) list += "android.permission.POST_NOTIFICATIONS"
                        requestPermissions(list.toTypedArray(), 7)
                        result.success(true)
                    }
                    "requestBgLocation" -> {
                        if (Build.VERSION.SDK_INT >= 29) requestPermissions(arrayOf("android.permission.ACCESS_BACKGROUND_LOCATION"), 8)
                        result.success(true)
                    }
                    "ignoreBattery" -> {
                        try {
                            @SuppressLint("BatteryLife")
                            val i = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName"))
                            startActivity(i)
                        } catch (_: Throwable) {
                            openDetails(packageName)
                        }
                        result.success(true)
                    }
                    "openApp" -> { openDetails(packageName); result.success(true) }
                    "openAa" -> { openDetails(MonitorService.GEARHEAD); result.success(true) }
                    "openBt" -> { startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS)); result.success(true) }
                    "openWifi" -> { startActivity(Intent(Settings.ACTION_WIFI_SETTINGS)); result.success(true) }
                    "mark" -> { MonitorService.start(this, MonitorService.ACTION_MARK); result.success(true) }
                    "clear" -> { EventLog.clear(this); result.success(true) }
                    "save" -> result.success(saveReport(call.argument<String>("name") ?: "nauto.txt", call.argument<String>("text") ?: ""))
                    else -> result.notImplemented()
                }
            } catch (t: Throwable) {
                result.error("native", t.toString(), null)
            }
        }
    }
}
