//
//  RideWidgetExtension_REFERENCIA.swift
//
//  ESTE ARCHIVO NO SE COMPILA TAL CUAL — vive fuera de cualquier target de
//  Xcode a propósito (Claude Code no puede crear targets nuevos en un
//  .xcodeproj de forma segura por edición de texto). Es el contenido que hay
//  que pegar DENTRO del target "RideWidgetExtension" una vez creado.
//
//  Pasos en Xcode (ver plan de esta feature):
//  1. Abrir ios/Runner.xcworkspace (no el .xcodeproj).
//  2. File → New → Target → Widget Extension, nombre "RideWidgetExtension",
//     activar "Include Live Activity". Xcode genera un archivo de ejemplo
//     (algo como RideWidgetExtensionLiveActivity.swift) — BORRAR su
//     contenido y pegar el de acá.
//  3. En Signing & Capabilities de AMBOS targets (Runner y
//     RideWidgetExtension): agregar "App Groups" con el grupo
//     group.com.taxiya.app.liveactivity (mismo Team en los dos), y
//     confirmar "Live Activities" tildado en Info de los dos targets.
//  4. cd ios && pod install, compilar en iPhone real con iOS 16.1+.
//
//  Las claves del diccionario que llegan en `contentState` (ver
//  lib/core/services/live_activity_service.dart:
//  LiveActivityService.iniciarOActualizar) son:
//    titulo, etaText, distanceText, direccion, horaLlegadaText, progreso (0..1)
//

import ActivityKit
import WidgetKit
import SwiftUI

/// Atributos fijos de la actividad (no cambian durante el viaje) + el
/// estado dinámico que se actualiza en cada llamada a
/// `createOrUpdateActivity`/`updateActivity` desde Dart. El plugin
/// `live_activities` mapea el `Map<String, dynamic>` de Dart a este
/// `ContentState` por nombre de clave — deben coincidir exactamente.
struct RideActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var titulo: String
        var etaText: String
        var distanceText: String
        var direccion: String
        var horaLlegadaText: String
        var progreso: Double // 0.0 – 1.0
    }
}

struct RideWidgetExtensionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            // Pantalla de bloqueo / notificación expandida.
            RideLiveActivityView(state: context.state)
                .padding(16)
                .activityBackgroundTint(Color(red: 0.02, green: 0.02, blue: 0.02))
                .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            // Dynamic Island (iPhone 14 Pro+). Estados: compacto, mínimo,
            // expandido — se completan los tres con el mismo dato.
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "car.fill")
                        .foregroundStyle(Color(red: 1.0, green: 0.69, blue: 0.125)) // AppColores.primary
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.etaText)
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    RideLiveActivityView(state: context.state)
                }
            } compactLeading: {
                Image(systemName: "car.fill")
                    .foregroundStyle(Color(red: 1.0, green: 0.69, blue: 0.125))
            } compactTrailing: {
                Text(context.state.etaText)
                    .font(.caption2)
            } minimal: {
                Image(systemName: "car.fill")
                    .foregroundStyle(Color(red: 1.0, green: 0.69, blue: 0.125))
            }
        }
    }
}

/// Layout compartido entre pantalla de bloqueo y Dynamic Island expandido —
/// calca la referencia de Google Maps: título con ícono de auto + ETA
/// (distancia), línea de llegada + dirección, barra de progreso.
private struct RideLiveActivityView: View {
    let state: RideActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "car.fill")
                    .foregroundStyle(Color(red: 1.0, green: 0.69, blue: 0.125)) // AppColores.primary
                Text("\(state.titulo)")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text("\(state.etaText) (\(state.distanceText))")
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            if !state.direccion.isEmpty {
                Text("Llegada: \(state.horaLlegadaText) · \(state.direccion)")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            } else {
                Text("Llegada: \(state.horaLlegadaText)")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
            }

            ProgressView(value: state.progreso)
                .tint(Color(red: 1.0, green: 0.69, blue: 0.125)) // AppColores.primary
        }
    }
}
