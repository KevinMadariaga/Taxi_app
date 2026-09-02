/// Lógica pura de clasificación y búsqueda del panel admin — separada de
/// `admin_home_screen.dart` para poder testearla sin Firestore ni widgets.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

enum AdminUserBucket { conductor, cliente }

/// Una membresía está activa solo si el campo dice 'activa' **y** la fecha
/// de vencimiento no pasó. Compartida entre `admin_home_screen.dart` (lista
/// de conductores) y `admin_hub_screen.dart` (pestaña de activaciones
/// pendientes de la campana) — antes vivía duplicada como función privada
/// en el primero.
bool membresiaActiva(Map<String, dynamic> data) {
  final activa = (data['membresia'] ?? '').toString().toLowerCase() == 'activa';
  if (!activa) return false;
  final vence = data['membresiaVence'];
  if (vence is Timestamp && vence.toDate().isBefore(DateTime.now())) {
    return false;
  }
  return true;
}

/// Clasifica un doc de `usuarios` en la pestaña que le corresponde.
///
/// Calcada de la cascada real de rol que usa `initial_screen_resolver.dart`
/// (que es la que de verdad decide a dónde entra cada usuario en la app):
/// conductor si `rol=='conductor'` **o** `tipoUsuario=='conductor'` **o**
/// `solicitudConductor==true`. Todo lo demás cae en `cliente` — nunca hay un
/// tercer balde donde un usuario pueda desaparecer del panel (antes, un
/// `rol` distinto de `cliente`/`conductor`/vacío, como `'admin'`, no entraba
/// en ninguna pestaña).
AdminUserBucket clasificarUsuario(Map<String, dynamic> data) {
  final rol = (data['rol'] ?? '').toString().toLowerCase();
  final tipoUsuario = (data['tipoUsuario'] ?? '').toString().toLowerCase();
  final pidioConductor = data['solicitudConductor'] == true;
  if (rol == 'conductor' || tipoUsuario == 'conductor' || pidioConductor) {
    return AdminUserBucket.conductor;
  }
  return AdminUserBucket.cliente;
}

String _normalizar(String texto) {
  const conAcento = 'áéíóúÁÉÍÓÚñÑ';
  const sinAcento = 'aeiouAEIOUnN';
  var out = texto.toLowerCase().trim();
  for (var i = 0; i < conAcento.length; i++) {
    out = out.replaceAll(conAcento[i], sinAcento[i].toLowerCase());
  }
  return out;
}

String _soloDigitos(String texto) => texto.replaceAll(RegExp(r'[^0-9]'), '');

String _soloAlfanumerico(String texto) =>
    texto.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// Busca por nombre/apellido (en cualquier orden, sin distinguir acentos),
/// teléfono (ignora `+57`, espacios y guiones) y placa (ignora espacios y
/// guion, sin distinguir mayúsculas).
bool coincideBusqueda(Map<String, dynamic> data, String query) {
  final q = query.trim();
  if (q.isEmpty) return true;

  final nombreCompleto = _normalizar(
    '${data['nombre'] ?? ''} ${data['apellido'] ?? ''}',
  );
  final qNormalizado = _normalizar(q);
  if (nombreCompleto.contains(qNormalizado)) return true;

  final qDigitos = _soloDigitos(q);
  if (qDigitos.isNotEmpty) {
    final telefono = _soloDigitos((data['telefono'] ?? '').toString());
    if (telefono.isNotEmpty && telefono.contains(qDigitos)) return true;
  }

  final qAlfanumerico = _soloAlfanumerico(q);
  if (qAlfanumerico.isNotEmpty) {
    final placa = _soloAlfanumerico((data['placa'] ?? '').toString());
    if (placa.isNotEmpty && placa.contains(qAlfanumerico)) return true;
  }

  return false;
}
