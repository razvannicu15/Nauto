package ro.noraz.nauto

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.UiModeManager
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.SupplicantState
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.car.app.connection.CarConnection
import androidx.lifecycle.Observer
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.util.regex.Pattern

/**
 * Foreground service that records everything around an Android Auto wireless
 * connection: Bluetooth (adapter + profiles), Wi-Fi, Android Auto projection
 * state, power / doze / screen. Optional: system log stream when READ_LOGS
 * was granted over adb.
 */
class MonitorService : Service() {

    companion object {
        const val ACTION_MARK = "ro.noraz.nauto.MARK"
        const val ACTION_LOGS = "ro.noraz.nauto.LOGS"
        const val ACTION_STOP = "ro.noraz.nauto.STOP"
        const val GEARHEAD = "com.google.android.projection.gearhead"
        private const val CH = "monitor"
        private const val NID = 41
        @Volatile var running = false

        fun prefs(ctx: Context) = ctx.getSharedPreferences("nauto", Context.MODE_PRIVATE)

        fun start(ctx: Context, action: String? = null) {
            val i = Intent(ctx, MonitorService::class.java)
            if (action != null) i.action = action
            try {
                if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
            } catch (_: Throwable) {
            }
        }

        fun aaVersion(ctx: Context): String? = try {
            ctx.packageManager.getPackageInfo(GEARHEAD, 0).versionName
        } catch (_: Throwable) {
            null
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private lateinit var cm: ConnectivityManager
    private lateinit var wm: WifiManager
    private var car: CarConnection? = null
    private var lastAa = -1
    private val netSsid = HashMap<Network, String>()
    private val netInternet = HashMap<Network, Boolean>()
    private var dongleOnSince = 0L
    private var dongleOffAt = 0L
    private var dongleConnected = false
    private var lastSample = ""
    private var lastTtc: Long = -1
    private var logThread: Thread? = null
    private var logProc: Process? = null

    private fun prefix() = prefs(this).getString("prefix", "AAWireless") ?: "AAWireless"

    private fun log(type: String, data: Map<String, Any?> = emptyMap()) = EventLog.add(this, type, data)

    // ------------------------------------------------------------ lifecycle

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        cm = getSystemService(ConnectivityManager::class.java)
        wm = applicationContext.getSystemService(WifiManager::class.java)
        goForeground()
        running = true
        log("svc", mapOf("on" to true))
        logInfo()
        registerReceivers()
        registerNetworks()
        try {
            val c = CarConnection(this)
            c.type.observeForever(carObserver)
            car = c
        } catch (t: Throwable) {
            log("err", mapOf("where" to "car", "msg" to t.toString()))
        }
        main.postDelayed(sampler, 10_000)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_MARK -> {
                log("mark")
                updateNotification(if (ro()) "Notat ✓ — mulțumesc" else "Noted ✓ — thanks")
            }
            ACTION_LOGS -> startLogStream()
            ACTION_STOP -> {
                prefs(this).edit().putBoolean("enabled", false).apply()
                stopSelf()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        log("svc", mapOf("on" to false))
        try { unregisterReceiver(receiver) } catch (_: Throwable) {}
        try { cm.unregisterNetworkCallback(netCb) } catch (_: Throwable) {}
        try { car?.type?.removeObserver(carObserver) } catch (_: Throwable) {}
        main.removeCallbacksAndMessages(null)
        stopLogStream()
        super.onDestroy()
    }

    // --------------------------------------------------------- notification

    private fun goForeground() {
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CH) == null) {
            val ch = NotificationChannel(CH, "Nauto", NotificationManager.IMPORTANCE_LOW)
            ch.setShowBadge(false)
            nm.createNotificationChannel(ch)
        }
        val n = buildNotification(text())
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(NID, n)
        }
    }

    private fun ro() = (prefs(this).getString("lang", "ro") ?: "ro") == "ro"

    private fun text(): String {
        return if (lastTtc >= 0) {
            if (ro()) "Monitorizez · ultima conectare în ${lastTtc}s" else "Monitoring · last connection in ${lastTtc}s"
        } else {
            if (ro()) "Monitorizez conexiunea Android Auto" else "Monitoring the Android Auto connection"
        }
    }

    private fun buildNotification(body: String): Notification {
        val open = packageManager.getLaunchIntentForPackage(packageName)
        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val pOpen = PendingIntent.getActivity(this, 1, open ?: Intent(), piFlags)
        val mark = Intent(this, MonitorService::class.java).setAction(ACTION_MARK)
        val pMark = PendingIntent.getService(this, 2, mark, piFlags)
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CH) else Notification.Builder(this)
        val label = if (ro()) "Am avut o problemă" else "I had a problem"
        @Suppress("DEPRECATION")
        return b.setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setContentTitle("Nauto")
            .setContentText(body)
            .setOngoing(true)
            .setContentIntent(pOpen)
            .addAction(Notification.Action.Builder(android.graphics.drawable.Icon.createWithResource(this, android.R.drawable.ic_menu_edit), label, pMark).build())
            .build()
    }

    private fun updateNotification(body: String = text()) {
        try {
            getSystemService(NotificationManager::class.java).notify(NID, buildNotification(body))
        } catch (_: Throwable) {
        }
    }

    // ----------------------------------------------------------------- info

    private fun logInfo() {
        val pm = getSystemService(PowerManager::class.java)
        log(
            "info", mapOf(
                "aa_ver" to aaVersion(this),
                "aa_opt" to !pm.isIgnoringBatteryOptimizations(GEARHEAD),
                "self_opt" to !pm.isIgnoringBatteryOptimizations(packageName),
                "model" to Build.MODEL,
                "sdk" to Build.VERSION.SDK_INT,
                "logs" to (checkSelfPermission("android.permission.READ_LOGS") == PackageManager.PERMISSION_GRANTED),
            )
        )
    }

    private fun battery(): Int = try {
        getSystemService(BatteryManager::class.java).getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
    } catch (_: Throwable) {
        -1
    }

    // ------------------------------------------------------------ bluetooth

    @SuppressLint("MissingPermission")
    private fun devName(d: BluetoothDevice?): String? = try {
        d?.name
    } catch (_: Throwable) {
        null
    }

    private fun isDongle(d: BluetoothDevice?, name: String?): Boolean {
        if (d == null) return false
        val p = prefs(this)
        val known = p.getStringSet("dongles", emptySet()) ?: emptySet()
        if (name != null && name.startsWith(prefix(), ignoreCase = true)) {
            if (!known.contains(d.address)) p.edit().putStringSet("dongles", known + d.address).apply()
            return true
        }
        return known.contains(d.address)
    }

    private fun device(i: Intent): BluetoothDevice? = if (Build.VERSION.SDK_INT >= 33) {
        i.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
    } else {
        @Suppress("DEPRECATION") i.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
    }

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, i: Intent) {
            try {
                handle(i)
            } catch (t: Throwable) {
                log("err", mapOf("where" to (i.action ?: "?"), "msg" to t.toString()))
            }
        }
    }

    private fun handle(i: Intent) {
        when (val a = i.action) {
            BluetoothDevice.ACTION_ACL_CONNECTED, BluetoothDevice.ACTION_ACL_DISCONNECTED -> {
                val d = device(i)
                val n = devName(d)
                val dongle = isDongle(d, n)
                val on = a == BluetoothDevice.ACTION_ACL_CONNECTED
                log("bt", mapOf("dev" to n, "addr" to d?.address, "on" to on, "dongle" to dongle, "bat" to battery()))
                if (dongle) {
                    dongleConnected = on
                    val now = System.currentTimeMillis()
                    if (on) {
                        // A new attempt starts after 3 min of silence; retries count into the same attempt.
                        if (dongleOnSince == 0L || now - dongleOffAt > 180_000) dongleOnSince = now
                        logInfo()
                        sampleWifi(force = true)
                    } else {
                        dongleOffAt = now
                    }
                }
            }
            BluetoothDevice.ACTION_ACL_DISCONNECT_REQUESTED -> {
                val d = device(i); val n = devName(d)
                log("bt_req", mapOf("dev" to n, "dongle" to isDongle(d, n)))
            }
            BluetoothDevice.ACTION_BOND_STATE_CHANGED -> {
                val d = device(i); val n = devName(d)
                log("bt_bond", mapOf("dev" to n, "st" to i.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, -1), "dongle" to isDongle(d, n)))
            }
            "android.bluetooth.headset.profile.action.CONNECTION_STATE_CHANGED",
            "android.bluetooth.a2dp.profile.action.CONNECTION_STATE_CHANGED" -> {
                val d = device(i); val n = devName(d)
                val p = if ((a ?: "").contains("headset")) "hfp" else "a2dp"
                log("bt_prof", mapOf("p" to p, "dev" to n, "st" to i.getIntExtra("android.bluetooth.profile.extra.STATE", -1), "dongle" to isDongle(d, n)))
            }
            BluetoothAdapter.ACTION_STATE_CHANGED -> {
                val s = i.getIntExtra(BluetoothAdapter.EXTRA_STATE, -1)
                if (s == BluetoothAdapter.STATE_ON || s == BluetoothAdapter.STATE_OFF) log("bt_power", mapOf("on" to (s == BluetoothAdapter.STATE_ON)))
            }
            WifiManager.WIFI_STATE_CHANGED_ACTION -> {
                val s = i.getIntExtra(WifiManager.EXTRA_WIFI_STATE, -1)
                if (s == WifiManager.WIFI_STATE_ENABLED || s == WifiManager.WIFI_STATE_DISABLED) log("wifi_power", mapOf("on" to (s == WifiManager.WIFI_STATE_ENABLED)))
            }
            WifiManager.SUPPLICANT_STATE_CHANGED_ACTION -> {
                val st: SupplicantState? = if (Build.VERSION.SDK_INT >= 33) {
                    i.getParcelableExtra(WifiManager.EXTRA_NEW_STATE, SupplicantState::class.java)
                } else {
                    @Suppress("DEPRECATION") i.getParcelableExtra(WifiManager.EXTRA_NEW_STATE)
                }
                @Suppress("DEPRECATION")
                val err = i.getIntExtra(WifiManager.EXTRA_SUPPLICANT_ERROR, 0)
                // Only the interesting transitions, the rest is noise.
                val name = st?.name ?: return
                if (err != 0 || name in setOf("COMPLETED", "DISCONNECTED", "ASSOCIATING", "FOUR_WAY_HANDSHAKE", "INACTIVE")) {
                    if (dongleConnected || err != 0) log("supp", mapOf("st" to name, "err" to if (err != 0) err else null))
                }
            }
            Intent.ACTION_POWER_CONNECTED -> log("plug", mapOf("on" to true, "bat" to battery()))
            Intent.ACTION_POWER_DISCONNECTED -> log("plug", mapOf("on" to false, "bat" to battery()))
            Intent.ACTION_SCREEN_ON -> log("screen", mapOf("on" to true))
            Intent.ACTION_SCREEN_OFF -> log("screen", mapOf("on" to false))
            Intent.ACTION_AIRPLANE_MODE_CHANGED -> log("air", mapOf("on" to i.getBooleanExtra("state", false)))
            PowerManager.ACTION_POWER_SAVE_MODE_CHANGED ->
                log("saver", mapOf("on" to getSystemService(PowerManager::class.java).isPowerSaveMode))
            PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED ->
                log("idle", mapOf("on" to getSystemService(PowerManager::class.java).isDeviceIdleMode))
            UiModeManager.ACTION_ENTER_CAR_MODE -> log("carmode", mapOf("on" to true))
            UiModeManager.ACTION_EXIT_CAR_MODE -> log("carmode", mapOf("on" to false))
        }
    }

    private fun registerReceivers() {
        val f = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_ACL_CONNECTED)
            addAction(BluetoothDevice.ACTION_ACL_DISCONNECTED)
            addAction(BluetoothDevice.ACTION_ACL_DISCONNECT_REQUESTED)
            addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
            addAction("android.bluetooth.headset.profile.action.CONNECTION_STATE_CHANGED")
            addAction("android.bluetooth.a2dp.profile.action.CONNECTION_STATE_CHANGED")
            addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
            addAction(WifiManager.WIFI_STATE_CHANGED_ACTION)
            addAction(WifiManager.SUPPLICANT_STATE_CHANGED_ACTION)
            addAction(Intent.ACTION_POWER_CONNECTED)
            addAction(Intent.ACTION_POWER_DISCONNECTED)
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_AIRPLANE_MODE_CHANGED)
            addAction(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)
            addAction(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED)
            addAction(UiModeManager.ACTION_ENTER_CAR_MODE)
            addAction(UiModeManager.ACTION_EXIT_CAR_MODE)
        }
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(receiver, f, Context.RECEIVER_EXPORTED)
        else registerReceiver(receiver, f)
    }

    // ------------------------------------------------------- android auto

    private val carObserver = Observer<Int> { type ->
        if (type == null || type == lastAa) return@Observer
        val prev = lastAa
        lastAa = type
        val data = HashMap<String, Any?>()
        data["type"] = type
        data["bat"] = battery()
        if (type == CarConnection.CONNECTION_TYPE_PROJECTION && dongleOnSince > 0) {
            lastTtc = (System.currentTimeMillis() - dongleOnSince) / 1000
            data["ttc"] = lastTtc
            dongleOnSince = 0L
            updateNotification()
        }
        if (prev == CarConnection.CONNECTION_TYPE_PROJECTION && dongleConnected) {
            // Projection lost while the adapter is still there: the next attempt is a reconnect.
            dongleOnSince = System.currentTimeMillis()
        }
        log("aa", data)
        if (type == CarConnection.CONNECTION_TYPE_PROJECTION) sampleWifi(force = true)
    }

    // ----------------------------------------------------------------- wifi

    private val netCb = if (Build.VERSION.SDK_INT >= 31) {
        object : ConnectivityManager.NetworkCallback(ConnectivityManager.NetworkCallback.FLAG_INCLUDE_LOCATION_INFO) {
            override fun onCapabilitiesChanged(n: Network, c: NetworkCapabilities) = onCaps(n, c)
            override fun onLost(n: Network) = onNetLost(n)
        }
    } else {
        object : ConnectivityManager.NetworkCallback() {
            override fun onCapabilitiesChanged(n: Network, c: NetworkCapabilities) = onCaps(n, c)
            override fun onLost(n: Network) = onNetLost(n)
        }
    }

    private fun ssidOf(info: WifiInfo?): String? {
        val s = info?.ssid ?: return null
        return s.trim('"')
    }

    @Suppress("DEPRECATION")
    private fun onCaps(n: Network, c: NetworkCapabilities) {
        val info: WifiInfo? = if (Build.VERSION.SDK_INT >= 29) c.transportInfo as? WifiInfo else wm.connectionInfo
        val ssid = ssidOf(info) ?: "?"
        val internet = c.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        val first = !netSsid.containsKey(n)
        if (first || netInternet[n] != internet || (netSsid[n] == "?" && ssid != "?")) {
            netSsid[n] = ssid
            netInternet[n] = internet
            log(
                "wifi", mapOf(
                    "on" to true, "ssid" to ssid, "net" to internet,
                    "inet" to c.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET),
                    "rssi" to info?.rssi, "freq" to info?.frequency, "link" to info?.linkSpeed,
                    "id" to n.toString(),
                )
            )
        }
    }

    private fun onNetLost(n: Network) {
        val ssid = netSsid.remove(n) ?: return
        netInternet.remove(n)
        log("wifi", mapOf("on" to false, "ssid" to ssid, "id" to n.toString()))
    }

    private fun registerNetworks() {
        try {
            val req = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build()
            cm.registerNetworkCallback(req, netCb)
        } catch (t: Throwable) {
            log("err", mapOf("where" to "net", "msg" to t.toString()))
        }
    }

    @Suppress("DEPRECATION")
    private fun sampleWifi(force: Boolean = false) {
        try {
            val info = wm.connectionInfo ?: return
            val ssid = ssidOf(info) ?: "?"
            if (info.networkId == -1 && info.rssi <= -127) return
            val key = "$ssid|${info.frequency}|${info.rssi / 6}|${info.linkSpeed / 50}"
            if (!force && key == lastSample) return
            lastSample = key
            log("wifi_s", mapOf("ssid" to ssid, "rssi" to info.rssi, "freq" to info.frequency, "link" to info.linkSpeed))
        } catch (_: Throwable) {
        }
    }

    private val sampler = object : Runnable {
        override fun run() {
            if (dongleConnected || lastAa == CarConnection.CONNECTION_TYPE_PROJECTION) sampleWifi()
            main.postDelayed(this, 10_000)
        }
    }

    // ------------------------------------------------------- system logs

    private val keep: Pattern = Pattern.compile(
        "gearhead|[Pp]rojection|CAR\\.|GH\\.|AAWireless|aawireless|WifiNetworkSpecifier|WifiNetworkFactory|" +
            "wpa_supplicant|ClientModeImpl|SemWifi|WifiConnectivityManager|bt_btif|bt_stack|BluetoothAdapter|" +
            "AdapterService|HeadsetService|A2dpService|Rfcomm|RFCOMM|LocalOnly|local-only|UsbDeviceManager"
    )

    private val noise: Pattern = Pattern.compile(
        "NetworkFactory|StatusBar|VRI\\[|LocationManagerService|NotifRow|HoneySpace|NotificationPipeline|" +
            "SurfaceFlinger|PackageConfigPersister| View +:|SemWifiLinkQuality|SemWifiUsabilityStats|SemWifiBackOff|Binder +:"
    )

    private val ghKey: Pattern = Pattern.compile(
        "GH\\.ConnLoggerV2: .*?(WIRELESS_WIFI_SOCKET_CONNECTED|FRAMER_READ_IO_EXCEPTION_WITH_NO_DATA_RECEIVED|" +
            "WIRELESS_SETUP_FAILED_TO_START_NO_HFP_FROM_HU_PRESENCE|VERSION_NEGOTIATION_STARTED|PROJECTION_STARTED_WIFI|PROJECTION_STARTED_USB|" +
            "WIRELESS_CONNECTED_WIFI|WIRELESS_WIFI_NETWORK_CONNECTION_LOST)\\b"
    )

    private fun startLogStream() {
        if (checkSelfPermission("android.permission.READ_LOGS") != PackageManager.PERMISSION_GRANTED) return
        if (logThread?.isAlive == true) return
        val t = Thread {
            try {
                val p = Runtime.getRuntime().exec(arrayOf("logcat", "-v", "threadtime", "-T", "200"))
                logProc = p
                val r = BufferedReader(InputStreamReader(p.inputStream))
                var f = File(filesDir, "sys.log")
                var w = f.appendingWriter()
                var written = f.length()
                while (true) {
                    val line = r.readLine() ?: break
                    if (!keep.matcher(line).find() || noise.matcher(line).find()) continue
                    val gm = ghKey.matcher(line)
                    if (gm.find()) log("gh", mapOf("e" to gm.group(1)))
                    w.write(line); w.write("\n"); w.flush()
                    written += line.length + 1
                    if (written > 3_000_000) {
                        w.close()
                        val old = File(filesDir, "sys.1.log"); old.delete(); f.renameTo(old)
                        f = File(filesDir, "sys.log"); w = f.appendingWriter(); written = 0
                    }
                }
                w.close()
            } catch (e: Throwable) {
                log("err", mapOf("where" to "logcat", "msg" to e.toString()))
            }
        }
        t.isDaemon = true
        t.start()
        logThread = t
        log("logs", mapOf("on" to true))
    }

    private fun File.appendingWriter() = java.io.FileWriter(this, true).buffered()

    private fun stopLogStream() {
        try { logProc?.destroy() } catch (_: Throwable) {}
        logProc = null
        logThread = null
    }
}
