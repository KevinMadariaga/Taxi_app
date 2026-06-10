import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

class AyudaConductorView extends StatefulWidget {
  const AyudaConductorView({super.key});

  @override
  State<AyudaConductorView> createState() => _AyudaConductorViewState();
}

class _AyudaConductorViewState extends State<AyudaConductorView> {
  String _query = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  final List<Map<String, String>> _faqItems = const [
    {
      'q': '¿Cómo activo mi cuenta de conductor?',
      'a':
          'Tu cuenta debe ser aprobada por el administrador de tu gremio. Una vez aprobada, podrás recibir solicitudes de viaje.',
    },
    {
      'q': '¿Cómo acepto una solicitud de viaje?',
      'a':
          'Cuando recibas una solicitud aparecerá una alerta en pantalla. Toca "Aceptar" para confirmar el viaje.',
    },
    {
      'q': '¿Qué hago si no recibo solicitudes?',
      'a':
          'Verifica que tu estado esté en "Disponible", que el GPS esté activo y que tengas conexión a internet.',
    },
    {
      'q': '¿Cómo actualizo mis datos del vehículo?',
      'a':
          'Ve a tu perfil y selecciona "Editar vehículo". Podrás actualizar la placa, foto del vehículo y otros datos.',
    },
    {
      'q': '¿Cómo contacto al administrador?',
      'a':
          'Puedes usar la sección Soporte para escribirle directamente al equipo de soporte o contactar a tu administrador de gremio.',
    },
    {
      'q': '¿Cómo veo mi historial de viajes?',
      'a':
          'En el menú "Más opciones" selecciona Historial para ver todos tus viajes completados con detalle de tarifa y ruta.',
    },
  ];

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _faqItems.where((item) {
      if (_query.trim().isEmpty) return true;
      final q = item['q']!.toLowerCase();
      final a = item['a']!.toLowerCase();
      final query = _query.toLowerCase().trim();
      return q.contains(query) || a.contains(query);
    }).toList();

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Ayuda'),
        backgroundColor: AppColores.surface,
        foregroundColor: AppColores.textPrimary,
        elevation: 0,
      ),
      backgroundColor: AppColores.background,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onTapOutside: (_) => _searchFocusNode.unfocus(),
              onChanged: (value) {
                if (!mounted) return;
                setState(() => _query = value);
              },
              decoration: const InputDecoration(
                hintText: 'Buscar en ayuda',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text(
                      'No hay resultados para tu búsqueda.',
                      style: TextStyle(color: AppColores.textSecondary),
                    ),
                  )
                : ListView.builder(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return ExpansionTile(
                        leading: const Icon(Icons.help_outline),
                        title: Text(item['q'] ?? ''),
                        childrenPadding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              item['a'] ?? '',
                              style: const TextStyle(
                                color: AppColores.textSecondary,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
