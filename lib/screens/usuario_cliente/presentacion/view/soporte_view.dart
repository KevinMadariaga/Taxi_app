import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/soporte_chat_screen.dart';

class SoporteView extends StatelessWidget {
  const SoporteView({super.key, this.userType = 'cliente'});

  final String userType;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Soporte'),
        backgroundColor: AppColores.primary,
        foregroundColor: AppColores.textWhite,
        elevation: 0,
      ),
      backgroundColor: context.palette.background,
      body: ListView(
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.chat_bubble_outline),
            title: const Text('Chat en vivo'),
            subtitle: const Text(
              'Habla directamente con el equipo de soporte.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SoporteChatScreen(userType: userType),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Nuestro equipo atiende de lunes a viernes de 8:00 a.m. a 6:00 p.m.',
              style: TextStyle(
                color: context.palette.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
