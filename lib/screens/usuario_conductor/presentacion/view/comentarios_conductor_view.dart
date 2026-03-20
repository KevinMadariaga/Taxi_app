import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

class ComentariosConductorView extends StatelessWidget {
  const ComentariosConductorView({super.key});

  @override
  Widget build(BuildContext context) {
    final conductorId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: AppColores.background,
      appBar: AppBar(
        title: const Text('Comentarios de clientes'),
        backgroundColor: AppColores.primary,
      ),
      body: conductorId.isEmpty
          ? const Center(
              child: Text(
                'No se pudo identificar el conductor.',
                style: TextStyle(color: AppColores.textSecondary),
              ),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('solicitudes')
                  .where('conductor.id', isEqualTo: conductorId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: const TextStyle(color: AppColores.textSecondary),
                    ),
                  );
                }

                final items =
                    (snapshot.data?.docs ?? [])
                        .map(_buildCommentItem)
                        .whereType<_DriverCommentItem>()
                        .toList()
                      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

                if (items.isEmpty) {
                  return const Center(
                    child: Text(
                      'Aun no hay comentarios de clientes.',
                      style: TextStyle(
                        color: AppColores.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 16,
                  ),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Container(
                      decoration: BoxDecoration(
                        color: AppColores.cardBackground,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColores.borderSubtle),
                        boxShadow: const [
                          BoxShadow(
                            color: AppColores.borderSubtle,
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColores.primary,
                                ),
                                child: const Icon(
                                  Icons.rate_review_rounded,
                                  color: AppColores.textPrimary,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Comentario del cliente',
                                  style: TextStyle(
                                    color: AppColores.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (item.createdAt.millisecondsSinceEpoch > 0)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.schedule_rounded,
                                      size: 14,
                                      color: AppColores.textSecondary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _formatDate(item.createdAt),
                                      style: const TextStyle(
                                        color: AppColores.textSecondary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.format_quote_rounded,
                                color: AppColores.primary,
                                size: 22,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  item.comment,
                                  style: const TextStyle(
                                    color: AppColores.textPrimary,
                                    fontSize: 17,
                                    height: 1.45,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  _DriverCommentItem? _buildCommentItem(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final comment = _extractComment(data);
    if (comment.isEmpty) return null;

    return _DriverCommentItem(
      comment: comment,
      createdAt: _extractCommentDate(data),
    );
  }

  String _extractComment(Map<String, dynamic> data) {
    final direct = data['comentarioCalificacion'];
    if (direct != null) {
      final text = direct.toString().trim();
      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }

    final ratingRaw =
        data['calificacion'] ?? data['calificacion_cliente'] ?? data['rating'];
    if (ratingRaw is Map) {
      final nested = ratingRaw['comentarioCalificacion'];
      if (nested != null) {
        final text = nested.toString().trim();
        if (text.isNotEmpty && text.toLowerCase() != 'null') {
          return text;
        }
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
      return DateTime.fromMillisecondsSinceEpoch(
        rawDate,
        isUtc: true,
      ).toLocal();
    }
    if (rawDate is String) {
      final parsed = DateTime.tryParse(rawDate);
      if (parsed != null) return parsed.toLocal();
    }

    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month';
  }
}

class _DriverCommentItem {
  final String comment;
  final DateTime createdAt;

  const _DriverCommentItem({required this.comment, required this.createdAt});
}
