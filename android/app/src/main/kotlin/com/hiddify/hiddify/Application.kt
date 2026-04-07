package com.hiddify.hiddify

import android.app.Application
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.wifi.WifiManager
import android.os.PowerManager
import android.util.Log
import androidx.core.content.getSystemService
import com.hiddify.hiddify.bg.AppChangeReceiver
import go.Seq
import com.hiddify.hiddify.Application as BoxApplication

class Application : Application() {

    override fun attachBaseContext(base: Context?) {
        super.attachBaseContext(base)
        application = this
    }

    override fun onCreate() {
        super.onCreate()

        Seq.setContext(this)
        clearCoreDataOnUpgrade()

        registerReceiver(AppChangeReceiver(), IntentFilter().apply {
            addAction(Intent.ACTION_PACKAGE_ADDED)
            addDataScheme("package")
        })
    }

    /**
     * When upgrading from v2.3 (FFI) to v4.x (gRPC), old core data is
     * incompatible and causes 0B traffic. Clear core caches on version change.
     * Preserves: databases (app_flutter/), shared_prefs, user profiles.
     */
    private fun clearCoreDataOnUpgrade() {
        try {
            val prefs = getSharedPreferences("core_version", Context.MODE_PRIVATE)
            val savedVersion = prefs.getString("version_code", null)
            val currentVersion = packageManager.getPackageInfo(packageName, 0).versionCode.toString()

            if (savedVersion != null && savedVersion != currentVersion) {
                Log.i("Application", "Version changed $savedVersion -> $currentVersion, clearing core caches")

                // Clear cache dir (temp files for core)
                cacheDir.deleteRecursively()
                cacheDir.mkdirs()

                // Clear core files in filesDir, but keep app data dirs
                val keepDirs = setOf("shared_prefs", "databases", "app_flutter", "code_cache", "no_backup")
                filesDir.listFiles()?.forEach { file ->
                    if (file.name !in keepDirs) {
                        Log.d("Application", "Deleting ${file.name}")
                        file.deleteRecursively()
                    }
                }
                // Also check parent (dataDir) for app_flutter
                dataDir.listFiles()?.forEach { file ->
                    if (file.name !in keepDirs && file.name != "files" && file.name != "lib") {
                        // Don't touch lib (native .so), files (handled above)
                    }
                }

                // Clear external files dir (working dir for core configs/logs)
                getExternalFilesDir(null)?.let { extDir ->
                    extDir.listFiles()?.forEach { it.deleteRecursively() }
                    extDir.mkdirs()
                }

                Log.i("Application", "Core caches cleared")
            }

            prefs.edit().putString("version_code", currentVersion).apply()
        } catch (e: Throwable) {
            Log.w("Application", "Failed to clear core data on upgrade: ${e.message}")
        }
    }

    companion object {
        lateinit var application: BoxApplication
        val notification by lazy { application.getSystemService<NotificationManager>()!! }
        val connectivity by lazy { application.getSystemService<ConnectivityManager>()!! }
        val packageManager by lazy { application.packageManager }
        val powerManager by lazy { application.getSystemService<PowerManager>()!! }
        val notificationManager by lazy { application.getSystemService<NotificationManager>()!! }

        val wifiManager by lazy { application.getSystemService<WifiManager>()!! }

    }

}