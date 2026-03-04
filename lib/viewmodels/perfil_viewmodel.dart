import 'package:flutter/material.dart';

class PerfilViewModel extends ChangeNotifier {
  String? _correo;
  String? _telefono;

  PerfilViewModel({String? correo, String? telefono}) {
    _correo = correo;
    _telefono = telefono;
  }

  String get correoCensurado => _censurarCorreo(_correo ?? 'Sin correo');
  String get telefonoCensurado => _censurarTelefono(_telefono ?? 'Sin número');

  set correo(String? value) {
    _correo = value;
    notifyListeners();
  }

  set telefono(String? value) {
    _telefono = value;
    notifyListeners();
  }

  String _censurarCorreo(String correo) {
    if (correo == 'Sin correo' || !correo.contains('@')) return correo;
    final partes = correo.split('@');
    final nombre = partes[0];
    final dominio = partes[1];
    final censurado = nombre.length > 2
        ? nombre.substring(0, 2) + '***' + nombre.substring(nombre.length - 1)
        : nombre.substring(0, 1) + '***';
    return '$censurado@$dominio';
  }

  String _censurarTelefono(String telefono) {
    if (telefono == 'Sin número' || telefono.length < 4) return telefono;
    return telefono.substring(0, 2) + '****' + telefono.substring(telefono.length - 2);
  }
}
