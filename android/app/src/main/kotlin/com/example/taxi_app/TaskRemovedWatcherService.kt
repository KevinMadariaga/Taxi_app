package com.taxiya.taxiapp

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import androidx.work.Data
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager

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

                WorkManager.getInstance(applicationContext).enqueue(request)
            }
        } catch (_: Exception) {
        } finally {
            stopSelf()
        }
    }
}
