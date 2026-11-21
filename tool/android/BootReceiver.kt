package ro.noraz.nauto

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Restarts the monitor after a reboot or an app update, if it was on. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        if (MonitorService.prefs(ctx).getBoolean("enabled", false)) {
            MonitorService.start(ctx)
        }
    }
}
