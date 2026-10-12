package com.taxiya.taxiapp

import android.content.Context
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

    /**
     * Salir con "atrás" destruye la pantalla pero no el proceso: el GPS en
     * primer plano (`GeolocatorLocationService`) lo mantenía vivo y al
     * reabrir la app se quedaba en el logo (mismo problema que resuelve
     * `TaskRemovedWatcherService` para el cierre desde recientes). Si no hay
     * una solicitud activa, se termina el proceso para que la próxima
     * apertura arranque limpia. Con solicitud activa no se toca:
     * `onTaskRemoved` primero encola su cancelación y después lo termina.
     */
    override fun onDestroy() {
        val cerrandoDeVerdad = isFinishing && !isChangingConfigurations
        super.onDestroy()
        if (!cerrandoDeVerdad) return
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        if (prefs.getString("flutter.active_solicitud_id", null).isNullOrBlank()) {
            android.os.Process.killProcess(android.os.Process.myPid())
        }
    }
}
