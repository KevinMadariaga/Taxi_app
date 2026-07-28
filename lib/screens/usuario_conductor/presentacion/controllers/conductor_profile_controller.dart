import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:taxi_app/core/constants/solicitud_estado.dart';
import 'package:taxi_app/core/helpers/session_helper.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

/// Perfil del conductor (identidad + rating consolidado + historial de
/// viajes completados).
///
/// Extraído de InicioConductorViewmodel (comunidad de menor cohesión del
/// repo según graphify-out/GRAPH_REPORT.md). [hydrateFromConductorDoc] es el
/// método que unificó una duplicación real encontrada antes de este split
/// (ver commit previo): dos code paths independientes parseaban el mismo
/// documento `usuarios/{uid}` con reglas de fallback que habían divergido.
/// El vm host sigue siendo dueño del listener sobre ese documento (porque
/// ese mismo listener también gestiona el ciclo de vida de conexión/
/// solicitudes, que no es responsabilidad de este controller) y llama a
/// [hydrateFromConductorDoc] con cada snapshot.
class ConductorProfileController {
  ConductorProfileController({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
  }) : _firestore = firestore,
       _auth = auth;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String displayName = 'Conductor';
  String? photoUrl;

  String? nameFromDb;
  String? plate;
  String? vehiclePhotoUrl;
  String? tipoVehiculoConductor;

  String? get vehiclePlate => plate;
  String? get vehiclePhoto => vehiclePhotoUrl;

  double rating = 0.0;
  int totalRatings = 0;
  int totalCompletedTrips = 0;
  double totalServiceValue = 0.0;
  double _ratingFromConductorDoc = 0.0;
  int _totalRatingsFromConductorDoc = 0;

  StreamSubscription<String?>? _cachedNameSub;
  StreamSubscription<QuerySnapshot>? _ratingSub;

  /// Se dispara con cada cambio de estado — el vm host lo usa para su
  /// propio notifyListeners.
  VoidCallback? onChanged;

  void listenCachedName() {
    _cachedNameSub?.cancel();
    _cachedNameSub = SessionHelper.cachedNameStream.listen((name) {
      if (name != null && name.trim().isNotEmpty) {
        setDisplayName(name.trim());
      }
    });

    SessionHelper.getCachedName()
        .then((n) {
          if (n != null && n.trim().isNotEmpty) {
            setDisplayName(n.trim());
          }
        })
        .catchError((_) {});
  }

  /// Actualiza el nombre de display y notifica a los listeners de forma segura.
  void setDisplayName(String name) {
    displayName = name;
    onChanged?.call();
  }

  Future<void> loadProfile() async {
    // Cargar perfil (no solicitar ubicación aquí para evitar bloqueos duplicados)
    try {
      final user = _auth.currentUser;
      if (user != null) {
        photoUrl = user.photoURL;
        if (user.displayName != null && user.displayName!.trim().isNotEmpty) {
          displayName = user.displayName!.trim();
        } else if (user.email != null && user.email!.contains('@')) {
          final namePart = user.email!.split('@').first;
          if (namePart.isNotEmpty) {
            displayName =
                '${namePart[0].toUpperCase()}${namePart.substring(1)}';
          }
        }

        final uid = user.uid;
        try {
          final snap = await _firestore.collection('usuarios').doc(uid).get();
          if (snap.exists) {
            final data = snap.data();
            if (data != null) {
              hydrateFromConductorDoc(data);
            }
          }
        } catch (e, st) {
          ErrorReporter.report(e, st, reason: 'InicioConductorViewModel');
        }
      }
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'InicioConductorViewModel');
    }
    onChanged?.call();
  }

  /// Aplica los campos de perfil/rating leídos de `usuarios/{uid}`.
  ///
  /// Antes esta extracción vivía duplicada en `_loadProfile` (lectura única
  /// al iniciar) y en el listener de `_subscribeConductorStatus` — habían
  /// divergido en dos puntos reales: el orden de fallback de la foto
  /// (`fotoUrl` antes que `foto` en un lado, al revés en el otro — con
  /// ambos campos presentes en el doc, cada code path elegía uno distinto) y
  /// `plate` se sobreescribía sin guardia de vacío en un lado pero no en el
  /// otro (podía blanquear una placa válida con una lectura parcial). Se
  /// unificó al comportamiento del listener continuo (más defensivo: nunca
  /// pisa un valor ya cargado con uno vacío).
  void hydrateFromConductorDoc(Map<String, dynamic> data) {
    final docName = data['nombre']?.toString().trim();
    if (docName != null && docName.isNotEmpty) {
      displayName = docName;
      nameFromDb = docName;
    }

    final docPlate = data['placa']?.toString().trim();
    if (docPlate != null && docPlate.isNotEmpty) {
      plate = docPlate;
    }

    final docTipo = data['tipoVehiculo']?.toString().trim().toLowerCase();
    if (docTipo != null && docTipo.isNotEmpty) {
      tipoVehiculoConductor = docTipo;
    }

    final foto = data['foto'] ?? data['fotoUrl'] ?? data['photoUrl'];
    if (foto != null && foto.toString().trim().isNotEmpty) {
      photoUrl = foto.toString().trim();
    }

    final fotoVehiculo = data['fotoVehiculo'] ?? data['vehiclePhotoUrl'];
    if (fotoVehiculo != null && fotoVehiculo.toString().trim().isNotEmpty) {
      vehiclePhotoUrl = fotoVehiculo.toString().trim();
    }

    final docAverage = _toDoubleOrNull(
      data['calificacionPromedio'] ?? data['ratingPromedio'] ?? data['rating'],
    );
    final docCount = _toIntOrNull(
      data['totalCalificaciones'] ??
          data['ratingCount'] ??
          data['totalRatings'],
    );

    if (docAverage != null) {
      _ratingFromConductorDoc = docAverage.clamp(0.0, 5.0).toDouble();
    }
    if (docCount != null && docCount >= 0) {
      _totalRatingsFromConductorDoc = docCount;
    }
    if (_totalRatingsFromConductorDoc > 0) {
      totalRatings = _totalRatingsFromConductorDoc;
      rating = _ratingFromConductorDoc;
    }
  }

  void subscribeRatings() {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;
      _ratingSub?.cancel();
      _ratingSub = _firestore
          .collection('solicitudes')
          .where('conductor.id', isEqualTo: uid)
          .snapshots()
          .listen((snap) {
            double scoreTotal = 0.0;
            int completedCount = 0;
            int ratedCount = 0;
            double serviceTotal = 0.0;

            for (var doc in snap.docs) {
              try {
                final data = doc.data();
                final estado = SolicitudEstado.normalize(
                  (data['estado'] ?? data['status'] ?? '').toString(),
                );
                if (!_isCompletedStatus(estado)) continue;

                completedCount++;
                serviceTotal += _extractServiceValue(data);

                final score = _extractRatingScore(data);
                if (score != null) {
                  scoreTotal += score;
                  ratedCount++;
                }
              } catch (e, st) {
                ErrorReporter.report(e, st, reason: 'InicioConductorViewModel');
              }
            }

            // Promedio basado en calificaciones efectivamente realizadas por clientes.
            totalCompletedTrips = completedCount;
            totalServiceValue = serviceTotal;
            // Si existe rating consolidado en usuarios, priorizarlo en la vista.
            if (_totalRatingsFromConductorDoc > 0) {
              totalRatings = _totalRatingsFromConductorDoc;
              rating = _ratingFromConductorDoc;
            } else if (ratedCount > 0) {
              totalRatings = ratedCount;
              rating = scoreTotal / ratedCount;
            } else {
              totalRatings = _totalRatingsFromConductorDoc;
              rating = _totalRatingsFromConductorDoc > 0
                  ? _ratingFromConductorDoc
                  : 0.0;
            }
            onChanged?.call();
          });
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'InicioConductorViewModel');
    }
  }

  double? _toDoubleOrNull(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  int? _toIntOrNull(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  bool _isCompletedStatus(String status) {
    if (status.isEmpty) return false;
    return status == SolicitudEstado.completado;
  }

  double _extractServiceValue(Map<String, dynamic> data) {
    final tarifa = data['tarifa'];
    if (tarifa is Map<String, dynamic> && tarifa['total'] != null) {
      final total = tarifa['total'];
      if (total is num) return total.toDouble();
      return double.tryParse(total.toString()) ?? 0.0;
    }

    final valor = data['valor'];
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString() ?? '') ?? 0.0;
  }

  double? _extractRatingScore(Map<String, dynamic> data) {
    final raw = data['calificacion'] ?? data['calificacion_cliente'];
    if (raw is Map<String, dynamic>) {
      final score = raw['score'] ?? raw['puntaje'] ?? raw['valor'];
      if (score is num) return score.toDouble();
      return double.tryParse(score?.toString() ?? '');
    }
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '');
  }

  void dispose() {
    _cachedNameSub?.cancel();
    _ratingSub?.cancel();
  }
}
