import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class DriverCommentItem {
  final String comment;
  final DateTime createdAt;

  /// Estrellas que dejó el cliente con el comentario (0 si no hay).
  final double estrellas;

  /// Solo el primer nombre: suficiente para reconocer el viaje sin exponer
  /// el nombre completo del pasajero.
  final String nombreCliente;

  const DriverCommentItem({
    required this.comment,
    required this.createdAt,
    this.estrellas = 0,
    this.nombreCliente = '',
  });
}

/// Promedio de estrellas y cantidad de comentarios, para el encabezado.
({double promedio, int total}) resumenComentarios(
  List<DriverCommentItem> items,
) {
  final conEstrellas = items.where((i) => i.estrellas > 0).toList();
  final promedio = conEstrellas.isEmpty
      ? 0.0
      : conEstrellas.map((i) => i.estrellas).reduce((a, b) => a + b) /
            conEstrellas.length;
  return (promedio: promedio, total: items.length);
}

class ComentariosConductorViewModel extends ChangeNotifier {
  String get conductorId => FirebaseAuth.instance.currentUser?.uid ?? '';

  Stream<List<DriverCommentItem>> streamComentarios() {
    final uid = conductorId;
    if (uid.isEmpty) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('solicitudes')
        .where('conductor.id', isEqualTo: uid)
        .snapshots()
        .map((snap) {
          final items = snap.docs
              .map(_buildItem)
              .whereType<DriverCommentItem>()
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return items;
        });
  }

  DriverCommentItem? _buildItem(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final comment = _extractComment(data);
    if (comment.isEmpty) return null;
    return DriverCommentItem(
      comment: comment,
      createdAt: _extractCommentDate(data),
      estrellas: _extractEstrellas(data),
      nombreCliente: _primerNombreCliente(data),
    );
  }

  String _extractComment(Map<String, dynamic> data) {
    final direct = data['comentarioCalificacion'];
    if (direct != null) {
      final text = direct.toString().trim();
      if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
    }

    final ratingRaw =
        data['calificacion'] ?? data['calificacion_cliente'] ?? data['rating'];
    if (ratingRaw is Map) {
      final nested = ratingRaw['comentarioCalificacion'];
      if (nested != null) {
        final text = nested.toString().trim();
        if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
      }
    }
    return '';
  }

  DateTime _extractCommentDate(Map<String, dynamic> data) {
    final ratingRaw =
        data['calificacion'] ??
        data['calificacion_cliente'] ??
        data['calificacion cliente'] ??
        data['rating'];

    dynamic rawDate;
    if (ratingRaw is Map) {
      rawDate =
          ratingRaw['fecha'] ??
          ratingRaw['fechaCalificacion'] ??
          ratingRaw['createdAt'] ??
          ratingRaw['timestamp'];
    }

    rawDate ??=
        data['fechaCalificacion'] ??
        data['completedAt'] ??
        data['fecha de terminacion'] ??
        data['updatedAt'] ??
        data['timestamp'];

    if (rawDate is Timestamp) return rawDate.toDate().toLocal();
    if (rawDate is DateTime) return rawDate.toLocal();
    if (rawDate is int) {
      return DateTime.fromMillisecondsSinceEpoch(rawDate, isUtc: true).toLocal();
    }
    if (rawDate is String) {
      final parsed = DateTime.tryParse(rawDate);
      if (parsed != null) return parsed.toLocal();
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  double _extractEstrellas(Map<String, dynamic> data) {
    final raw = data['calificacion'] ?? data['rating'];
    final valor = raw is num
        ? raw.toDouble()
        : raw is Map
        ? double.tryParse('${raw['valor'] ?? raw['estrellas'] ?? ''}') ?? 0
        : double.tryParse('${raw ?? ''}') ?? 0;
    return valor.clamp(0, 5).toDouble();
  }

  String _primerNombreCliente(Map<String, dynamic> data) {
    final cliente = data['cliente'];
    if (cliente is! Map) return '';
    final nombre = (cliente['nombre'] ?? cliente['name'] ?? '').toString();
    final partes = nombre.trim().split(RegExp(r'\s+'));
    return partes.isEmpty ? '' : partes.first;
  }

  String formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }
}
