import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/services/soporte_chat_service.dart';

import 'soporte_chat_detalle_admin_screen.dart';

class SoporteChatsAdminScreen extends StatelessWidget {
  const SoporteChatsAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = SoporteChatService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Soporte — Chats'),
        backgroundColor: AppColores.background,
        foregroundColor: AppColores.textPrimary,
        elevation: 0,
      ),
      backgroundColor: AppColores.background,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: service.watchTodosChats(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'No hay chats de soporte activos.',
                style: TextStyle(color: AppColores.textSecondary),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final userId = data['userId'] as String? ?? docs[index].id;
              final userName = data['userName'] as String? ?? 'Usuario';
              final userType = data['userType'] as String? ?? 'cliente';
              final ultimoMensaje = data['ultimoMensaje'] as String? ?? '';
              final hayNuevos =
                  data['hayMensajesNuevosAdmin'] as bool? ?? false;
              final ts = data['ultimoMensajeAt'] as Timestamp?;
              final hora = ts != null
                  ? '${ts.toDate().hour.toString().padLeft(2, '0')}:${ts.toDate().minute.toString().padLeft(2, '0')}'
                  : '';

              return ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                tileColor: AppColores.surface,
                leading: CircleAvatar(
                  backgroundColor:
                      hayNuevos ? AppColores.primary : AppColores.grey200,
                  child: Icon(
                    userType == 'conductor'
                        ? Icons.local_taxi
                        : Icons.person,
                    color: hayNuevos
                        ? AppColores.textPrimary
                        : AppColores.textSecondary,
                  ),
                ),
                title: Text(
                  userName,
                  style: TextStyle(
                    fontWeight:
                        hayNuevos ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  ultimoMensaje,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hayNuevos
                        ? AppColores.textPrimary
                        : AppColores.textSecondary,
                    fontWeight:
                        hayNuevos ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      hora,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColores.textSecondary,
                      ),
                    ),
                    if (hayNuevos)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: AppColores.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SoporteChatDetalleAdminScreen(
                        userId: userId,
                        userName: userName,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
