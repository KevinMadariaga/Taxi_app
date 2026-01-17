import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/helper/session_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/inicio_cliente_model.dart';
import 'package:taxi_app/services/firebase_service.dart';

class InicioClienteViewModel extends ChangeNotifier {
  String search = '';
  String _clientName = 'Cliente';
  String get clientName => _clientName;

  String? _clientId;
  String? get clientId => _clientId;

  bool _isLoadingLocation = false;
  bool get isLoadingLocation => _isLoadingLocation;

  LatLng? _currentLocation;
  LatLng? get currentLocation => _currentLocation;

  bool _disposed = false;
  StreamSubscription<User?>? _authSub;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseService _firebaseService = FirebaseService();

  /// Inicializar listeners y cargar sesión previa
  Future<void> init() async {
    // Escuchar cambios de auth
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        _clientId = user.uid;
        // Preferir nombre guardado en cache; si no existe, usar displayName/email derivado
        String name = 'Cliente';
        try {
          final cached = await SessionHelper.getCachedName();
          if (cached != null && cached.trim().isNotEmpty) {
            name = cached.trim();
          } else if (user.displayName != null && user.displayName!.trim().isNotEmpty) {
            name = user.displayName!.trim();
          } else if (user.email != null && user.email!.contains('@')) {
            final namePart = user.email!.split('@').first;
            name = namePart.isNotEmpty ? '${namePart[0].toUpperCase()}${namePart.substring(1)}' : 'Cliente';
          }
        } catch (e) {
          debugPrint('Error leyendo cached name: $e');
        }

        _clientName = name;
        await SessionHelper.saveSession('cliente', user.uid);
        if (!_disposed) notifyListeners();
      } else {
        // intentar cargar uid desde SessionHelper
        try {
          final savedUid = await SessionHelper.getUserUid();
          if (savedUid != null && savedUid.isNotEmpty) {
            _clientId = savedUid;
            try {
              final cached = await SessionHelper.getCachedName();
              if (cached != null && cached.trim().isNotEmpty) {
                _clientName = cached.trim();
              }
            } catch (e) {
              debugPrint('Error leyendo nombre desde session cache: $e');
            }
          }
        } catch (e) {
          debugPrint('Error accediendo SessionHelper: $e');
        }
        if (!_disposed) notifyListeners();
      }
    });
  }

  /// Actualiza la ubicación local y en Firestore si hay cliente
  Future<void> updateLocation(LatLng loc) async {
    _isLoadingLocation = true;
    _currentLocation = loc;
    if (!_disposed) notifyListeners();

    try {
      String? cid = _clientId ?? FirebaseAuth.instance.currentUser?.uid;
      if (cid == null || cid.isEmpty) cid = await SessionHelper.getUserUid();
      if (cid != null && cid.isNotEmpty) {
        await _firebaseService.guardarUbicacionCliente(
          clienteId: cid,
          position: loc,
        );
      }
    } catch (e) {
      debugPrint('Error guardando ubicacion: $e');
    } finally {
      _isLoadingLocation = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _authSub?.cancel();
    super.dispose();
  }

  final List<LocationShortcut> shortcuts = [
    LocationShortcut(
      title: 'Sizzling Fresh',
      subtitle: '3551 Truxel Rd, Sacramento',
      iconLetter: 'S',
    ),
    LocationShortcut(
      title: 'Trabajo',
      subtitle: 'Add shortcut',
      iconLetter: 'T',
    ),
  ];

  final List<LoyaltyProgram> programs = [
    LoyaltyProgram(
      name: 'United MileagePlus',
      description: 'Gana entre 1 y 4 millas por cada dólar en viajes calificados.',
    ),
    LoyaltyProgram(
      name: 'Hilton Honors',
      description: 'Recibe 3 puntos por cada dólar que gastes en viajes.',
    ),
    LoyaltyProgram(
      name: 'Recompensas de Atmos',
      description: 'Gana entre 2 y 3 puntos por 1 en viajes calificados.',
    ),
  ];

  void updateSearch(String value) {
    search = value;
    if (!_disposed) notifyListeners();
  }
}
