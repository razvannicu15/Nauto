package ro.noraz.nauto

import android.content.Context
import org.json.JSONObject
import java.io.File

/** Append-only JSON-lines journal kept in the app's private files folder. */
object EventLog {
    private const val MAX_BYTES = 4_000_000L

    fun file(ctx: Context) = File(ctx.filesDir, "events.jsonl")

    @Synchronized
    fun add(ctx: Context, type: String, data: Map<String, Any?> = emptyMap()) {
        try {
            val o = JSONObject()
            o.put("ts", System.currentTimeMillis())
            o.put("t", type)
            for ((k, v) in data) if (v != null) o.put(k, v)
            val f = file(ctx)
            if (f.length() > MAX_BYTES) {
                val old = File(ctx.filesDir, "events.1.jsonl")
                old.delete()
                f.renameTo(old)
            }
            file(ctx).appendText(o.toString() + "\n")
        } catch (_: Throwable) {
        }
    }

    @Synchronized
    fun clear(ctx: Context) {
        file(ctx).delete()
        File(ctx.filesDir, "events.1.jsonl").delete()
        File(ctx.filesDir, "sys.log").delete()
        File(ctx.filesDir, "sys.1.log").delete()
    }
}
