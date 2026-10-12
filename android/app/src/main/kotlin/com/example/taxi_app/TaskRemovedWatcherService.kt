package com.taxiya.taxiapp

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import androidx.work.Data
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.await
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Servicio liviano (no foreground, sin UI) cuyo único propósito es recibir
 * `onTaskRemoved`: el callback que Android sí dispara de forma confiable
 * cuando el usuario quita la app del selector de apps recientes (swipe-kill)
 * — a diferencia de cualquier callback de Activity o del lado Dart, que no
 * llegan a correr si el proceso muere antes.
 *
 * MainActivity lo arranca en `onCreate`. Al detectar el cierre total,
 * encola un job de WorkManager (persiste en su propia base de datos y
 * corre aunque el proceso ya no exista) para cancelar en el servidor la
 * solicitud 'buscando' que el cliente dejó activa, evitando que un
 * conductor la acepte mientras la app está cerrada.
 *
 * Después termina el proceso. Sin esto quedaba vivo un proceso "zombi":
 * el servicio en primer plano del GPS (`GeolocatorLocationService`, que abre
 * el inicio del conductor) no se detiene mientras siga conectado el motor
 * de Flutter de los push en segundo plano, y al reabrir la app arrancaba
 * dentro de ese proceso y se quedaba para siempre en el logo nativo. Ese GPS
 * ya no le servía a nadie (mandaba posiciones a un motor desconectado), y
 * los push siguen llegando: Android levanta el proceso cuando llega uno.
 */
class TaskRemovedWatcherService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        try {
            val prefs = applicationContext.getSharedPreferences(
                "FlutterSharedPreferences",
                Context.MODE_PRIVATE,
            )
            val solicitudId = prefs.getString("flutter.active_solicitud_id", null)
            val clienteId = prefs.getString("flutter.user_uid", null)

            if (!solicitudId.isNullOrBlank() && !clienteId.isNullOrBlank()) {
                val data = Data.Builder()
                    .putString(CancelSolicitudWorker.KEY_SOLICITUD_ID, solicitudId)
                    .putString(CancelSolicitudWorker.KEY_CLIENTE_ID, clienteId)
                    .build()

                val request = OneTimeWorkRequestBuilder<CancelSolicitudWorker>()
                    .setInputData(data)
                    .build()

                // Esperar a que quede guardado antes de terminar el proceso
                // (encolar escribe en la base de WorkManager en otro hilo).
                val operacion = WorkManager.getInstance(applicationContext)
                    .enqueue(request)
                runBlocking { withTimeoutOrNull(3000) { operacion.await() } }
            }
        } catch (_: Exception) {
        } finally {
            stopSelf()
            android.os.Process.killProcess(android.os.Process.myPid())
        }
    }
}
