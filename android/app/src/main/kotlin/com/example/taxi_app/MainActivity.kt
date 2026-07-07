package com.taxiya.taxiapp

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    /**
     * Arranca el watcher que detecta el cierre total de la app (swipe en
     * recientes) vía Service.onTaskRemoved — callback que solo existe en
     * Service, no en Activity. Ver TaskRemovedWatcherService.kt.
     */
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            startService(Intent(this, TaskRemovedWatcherService::class.java))
        } catch (_: Exception) {
        }
    }
}
