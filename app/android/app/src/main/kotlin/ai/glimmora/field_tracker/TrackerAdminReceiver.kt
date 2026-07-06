package ai.glimmora.field_tracker

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent

class TrackerAdminReceiver : DeviceAdminReceiver() {

    override fun onDisableRequested(context: Context, intent: Intent): CharSequence {
        return "Turning off protection will let the tracking app be removed. Your manager will be notified."
    }

    override fun onDisabled(context: Context, intent: Intent) {
        // Leave a flag the Flutter side reports as an "admin_removed" event on next launch.
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        prefs.edit().putBoolean("flutter.admin_removed_flag", true).apply()
    }
}
