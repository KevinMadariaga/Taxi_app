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

/// Registro de cliente terminado: misma regla que decide si entra al home
/// (`ClientUserEntity.perfilCompleto`): la bandera Y la foto. Los que no lo
/// terminaron no se listan en el panel admin.
bool registroCompleto(Map<String, dynamic> data) {
  final foto = '${data['foto'] ?? data['fotoUrl'] ?? ''}'.trim();
  return data['isProfileComplete'] == true && foto.isNotEmpty;
}

/// Fecha de alta del usuario: cuándo completó el registro
/// (`perfilCompletadoAt`) y, en cuentas anteriores a ese campo, `createdAt`
/// o `fechaRegistro`. `null` si no tiene ninguna.
DateTime? fechaRegistro(Map<String, dynamic> data) {
  final v =
      data['perfilCompletadoAt'] ?? data['createdAt'] ?? data['fechaRegistro'];
  return v is Timestamp ? v.toDate() : null;
}

/// Cuánto tiempo se marca a un usuario como "Nuevo" en el panel.
const Duration ventanaUsuarioNuevo = Duration(days: 7);

/// Registrado dentro de [ventanaUsuarioNuevo]. Sin fecha de alta: no.
bool esUsuarioNuevo(Map<String, dynamic> data, {DateTime? ahora}) {
  final alta = fechaRegistro(data);
  if (alta == null) return false;
  return (ahora ?? DateTime.now()).difference(alta) <= ventanaUsuarioNuevo;
}

enum EstadoConductor { pendiente, activo, inactivo }

/// Para ordenar la pestaña Conductores: primero los que esperan activación,
/// después los activos y al final el resto (membresía vencida o revocada).
EstadoConductor estadoConductor(Map<String, dynamic> data) {
  if (membresiaActiva(data)) return EstadoConductor.activo;
  if (data['solicitudConductor'] == true) return EstadoConductor.pendiente;
  return EstadoConductor.inactivo;
}

/// Cuándo pidió la activación el conductor: `solicitudConductorAt`, o
/// `updatedAt` en solicitudes anteriores a ese campo.
DateTime? fechaSolicitudConductor(Map<String, dynamic> data) {
  final v = data['solicitudConductorAt'] ?? data['updatedAt'];
  return v is Timestamp ? v.toDate() : null;
}

/// Ordena de más reciente a más antiguo por [fecha]; sin fecha, al final.
int masRecientePrimero(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return b.compareTo(a);
}
