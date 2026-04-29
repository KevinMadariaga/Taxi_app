import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodel/comentarios_conductor_viewmodel.dart';

class ComentariosConductorView extends StatelessWidget {
  const ComentariosConductorView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = ComentariosConductorViewModel();

    return Scaffold(
      backgroundColor: AppColores.background,
      appBar: AppBar(
        title: const Text('Comentarios de clientes'),
        backgroundColor: AppColores.primary,
      ),
      body: vm.conductorId.isEmpty
          ? const Center(
              child: Text(
                'No se pudo identificar el conductor.',
                style: TextStyle(color: AppColores.textSecondary),
              ),
            )
          : StreamBuilder<List<DriverCommentItem>>(
              stream: vm.streamComentarios(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style:
                          const TextStyle(color: AppColores.textSecondary),
                    ),
                  );
                }

                final items = snapshot.data ?? [];

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
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
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
                                      vm.formatDate(item.createdAt),
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
}
