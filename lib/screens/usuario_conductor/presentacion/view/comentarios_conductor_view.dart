import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodels/comentarios_conductor_viewmodel.dart';

class ComentariosConductorView extends StatelessWidget {
  const ComentariosConductorView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = ComentariosConductorViewModel();

    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(
        title: const Text('Comentarios de clientes'),
        backgroundColor: AppColores.primary,
      ),
      body: vm.conductorId.isEmpty
          ? Center(
              child: Text(
                'No se pudo identificar el conductor.',
                style: TextStyle(color: context.palette.textSecondary),
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
                      style: TextStyle(color: context.palette.textSecondary),
                    ),
                  );
                }

                final items = snapshot.data ?? [];

                if (items.isEmpty) {
                  return Center(
                    child: Text(
                      'Aun no hay comentarios de clientes.',
                      style: TextStyle(
                        color: context.palette.textSecondary,
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
                        color: context.palette.cardBackground,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: context.palette.borderSubtle),
                        boxShadow: [
                          BoxShadow(
                            color: context.palette.borderSubtle,
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
                                child: Icon(
                                  Icons.rate_review_rounded,
                                  color: context.palette.textPrimary,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Comentario del cliente',
                                  style: TextStyle(
                                    color: context.palette.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (item.createdAt.millisecondsSinceEpoch > 0)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.schedule_rounded,
                                      size: 14,
                                      color: context.palette.textSecondary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      vm.formatDate(item.createdAt),
                                      style: TextStyle(
                                        color: context.palette.textSecondary,
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
                                  style: TextStyle(
                                    color: context.palette.textPrimary,
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
