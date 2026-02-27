
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/helper/session_helper.dart';
import 'package:taxi_app/services/firebase_service.dart';


class InicioClienteViewModel extends ChangeNotifier {
  // --- Estado principal ---
  String search = '';
  String _clientName = 'Cliente';
  String? _clientId;
  bool _isLoadingLocation = false;
  LatLng? _currentLocation;
  bool _disposed = false;

  // --- Getters públicos ---
  String get clientName => _clientName;
  String? get clientId => _clientId;
  bool get isLoadingLocation => _isLoadingLocation;
  LatLng? get currentLocation => _currentLocation;

  // --- Servicios y subscripciones ---
  final FirebaseService _firebaseService = FirebaseService();
  StreamSubscription<User?>? _authSub;
  StreamSubscription<String?>? _cachedNameSub;

  // --- Inicialización y ciclo de vida ---
  Future<void> init() async {
    _listenAuthChanges();
    _listenCachedName();
  }

  void _listenAuthChanges() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        _clientId = user.uid;
        _clientName = await _obtenerNombreCliente(user);
        await SessionHelper.saveSession('cliente', user.uid);
        if (!_disposed) notifyListeners();
      } else {
        await _cargarClienteDesdeCache();
        if (!_disposed) notifyListeners();
      }
    });
  }

  void _listenCachedName() {
    try {
      _cachedNameSub = SessionHelper.cachedNameStream.listen((n) {
        if (n != null && n.trim().isNotEmpty) {
          _clientName = n.trim();
          if (!_disposed) notifyListeners();
        }
      });
      // Aplicar valor actual si existe
      SessionHelper.getCachedName().then((n) {
        if (n != null && n.trim().isNotEmpty) {
          _clientName = n.trim();
          if (!_disposed) notifyListeners();
        }
      }).catchError((_) {});
    } catch (_) {}
  }

  Future<String> _obtenerNombreCliente(User user) async {
    String name = 'Cliente';
    try {
      // 1. Intentar leer el nombre desde la colección 'cliente' en Firestore
      final doc = await FirebaseFirestore.instance
          .collection('cliente')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final data = doc.data();
        final dynamic maybeName = data != null ? data['nombre'] : null;
        if (maybeName is String && maybeName.trim().isNotEmpty) {
          name = maybeName.trim();
        }
      }
      // 2. Si no hay nombre en Firestore, usar cache/displayName/email
      if (name == 'Cliente') {
        final cached = await SessionHelper.getCachedName();
        if (cached != null && cached.trim().isNotEmpty) {
          name = cached.trim();
        } else if (user.displayName != null && user.displayName!.trim().isNotEmpty) {
          name = user.displayName!.trim();
        } else if (user.email != null && user.email!.contains('@')) {
          final namePart = user.email!.split('@').first;
          name = namePart.isNotEmpty ? '${namePart[0].toUpperCase()}${namePart.substring(1)}' : 'Cliente';
        }
      }
    } catch (e) {
      debugPrint('Error leyendo nombre de cliente: $e');
    }
    return name;
  }

  Future<void> _cargarClienteDesdeCache() async {
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
    try {
      _cachedNameSub?.cancel();
    } catch (_) {}
    super.dispose();
  }



  // --- Métodos utilitarios ---
  void updateSearch(String value) {
    search = value;
    if (!_disposed) notifyListeners();
  }
}
