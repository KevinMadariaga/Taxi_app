import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Un push que llegó al teléfono, tal como se muestra en la campana.
@immutable
class AvisoBandeja {
  const AvisoBandeja({
    required this.id,
    required this.titulo,
    required this.cuerpo,
    required this.tipo,
    required this.fecha,
    this.entidad = '',
    this.leido = false,
  });

  final String id;
  final String titulo;
  final String cuerpo;
  final String tipo;
  final DateTime fecha;

  /// A qué se refiere (p. ej. el id de la promoción), para abrirlo al tocar.
  final String entidad;
  final bool leido;

  AvisoBandeja leidoYa() => AvisoBandeja(
    id: id,
    titulo: titulo,
    cuerpo: cuerpo,
    tipo: tipo,
    fecha: fecha,
    entidad: entidad,
    leido: true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'titulo': titulo,
    'cuerpo': cuerpo,
    'tipo': tipo,
    'fecha': fecha.millisecondsSinceEpoch,
    'entidad': entidad,
    'leido': leido,
  };

  static AvisoBandeja? fromJson(Object? json) {
    if (json is! Map) return null;
    final fecha = json['fecha'];
    if (fecha is! int) return null;
    return AvisoBandeja(
      id: '${json['id'] ?? ''}',
      titulo: '${json['titulo'] ?? ''}',
      cuerpo: '${json['cuerpo'] ?? ''}',
      tipo: '${json['tipo'] ?? ''}',
      fecha: DateTime.fromMillisecondsSinceEpoch(fecha),
      entidad: '${json['entidad'] ?? ''}',
      leido: json['leido'] == true,
    );
  }
}

/// Bandeja de la campana: cada push que llega al teléfono (primer plano,
/// segundo plano o al tocarlo) queda acá, para comprobar que llegó aunque se
/// haya descartado de la barra del sistema.
///
/// Vive en SharedPreferences porque el handler de background de FCM corre en
/// otro isolate: [guardar] es estático y relee antes de escribir, y la
/// instancia del isolate principal relee al volver la app a primer plano.
class BandejaNotificaciones {
  BandejaNotificaciones._() {
    AppLifecycleListener(onResume: cargar);
  }

  static final BandejaNotificaciones instance = BandejaNotificaciones._();

  static const String _clave = 'bandeja_notificaciones';
  static const int _maximo = 50;

  /// Más reciente primero.
  final ValueNotifier<List<AvisoBandeja>> avisos = ValueNotifier(const []);

  int get noLeidos => avisos.value.where((a) => !a.leido).length;

  /// Tipos que no son avisos para el usuario.
  static const Set<String> _ignorados = {'retirar_notificacion'};

  /// Guarda un push desde cualquier isolate. Repetir el mismo [id] (p. ej. el
  /// mismo mensaje visto al llegar y al tocarlo) no lo duplica.
  static Future<void> guardar({
    required String id,
    required String titulo,
    required String cuerpo,
    required String tipo,
    String entidad = '',
    DateTime? fecha,
  }) async {
    if (_ignorados.contains(tipo)) return;
    if (titulo.trim().isEmpty && cuerpo.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final lista = _leer(prefs);
    if (lista.any((a) => a.id == id)) return;
    lista.insert(
      0,
      AvisoBandeja(
        id: id,
        titulo: titulo,
        cuerpo: cuerpo,
        tipo: tipo,
        entidad: entidad,
        fecha: fecha ?? DateTime.now(),
      ),
    );
    await _escribir(prefs, lista.take(_maximo).toList());
  }

  /// Relee lo que haya guardado cualquier isolate.
  Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    avisos.value = _leer(prefs);
  }

  Future<void> marcarTodasLeidas() async {
    if (noLeidos == 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final lista = _leer(prefs).map((a) => a.leidoYa()).toList();
    await _escribir(prefs, lista);
    avisos.value = lista;
  }

  Future<void> borrarTodo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_clave);
    avisos.value = const [];
  }

  static List<AvisoBandeja> _leer(SharedPreferences prefs) {
    try {
      final crudo = jsonDecode(prefs.getString(_clave) ?? '[]');
      if (crudo is! List) return [];
      return crudo
          .map(AvisoBandeja.fromJson)
          .whereType<AvisoBandeja>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _escribir(
    SharedPreferences prefs,
    List<AvisoBandeja> lista,
  ) => prefs.setString(
    _clave,
    jsonEncode(lista.map((a) => a.toJson()).toList()),
  );
}
