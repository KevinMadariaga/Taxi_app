package com.taxiya.taxiapp

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/**
 * Cancela en el servidor la solicitud 'buscando' del cliente cuando la app
 * fue cerrada por completo (swipe en el selector de apps recientes).
 *
 * Se encola desde MainActivity.onTaskRemoved. WorkManager persiste el job
 * en su propia base de datos y lo ejecuta aunque el proceso Android muera
 * justo después de encolarlo — a diferencia de cualquier Timer/callback
 * Dart, que muere junto con el proceso sin llegar a escribir en Firestore.
 */
class CancelSolicitudWorker(context: Context, params: WorkerParameters) :
    CoroutineWorker(context, params) {

    companion object {
        private const val ENDPOINT =
            "https://us-central1-aplicacion-taxi-fd0a7.cloudfunctions.net/cancelarSolicitudPorCierreApp"
        const val KEY_SOLICITUD_ID = "solicitudId"
        const val KEY_CLIENTE_ID = "clienteId"
    }

    override suspend fun doWork(): Result {
        val solicitudId = inputData.getString(KEY_SOLICITUD_ID)
        val clienteId = inputData.getString(KEY_CLIENTE_ID)
        if (solicitudId.isNullOrBlank() || clienteId.isNullOrBlank()) {
            return Result.failure()
        }

        return try {
            val query =
                "solicitudId=${URLEncoder.encode(solicitudId, "UTF-8")}" +
                    "&clienteId=${URLEncoder.encode(clienteId, "UTF-8")}"
            val connection = URL("$ENDPOINT?$query").openConnection() as HttpURLConnection
            connection.requestMethod = "POST"
            connection.connectTimeout = 8000
            connection.readTimeout = 8000
            connection.doOutput = false
            val code = connection.responseCode
            connection.disconnect()
            if (code in 200..299) Result.success() else Result.retry()
        } catch (e: Exception) {
            Result.retry()
        }
    }
}
