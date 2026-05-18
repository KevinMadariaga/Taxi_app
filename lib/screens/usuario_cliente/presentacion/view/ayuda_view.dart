import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

class AyudaView extends StatefulWidget {
  const AyudaView({super.key});

  @override
  State<AyudaView> createState() => _AyudaViewState();
}

class _AyudaViewState extends State<AyudaView> {
  String _query = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  final List<Map<String, String>> _faqItems = const [
    {
      'q': '¿Cómo solicito un viaje?',
      'a':
          'Toca "¿A dónde vamos?", selecciona tu destino y confirma la solicitud para empezar a buscar conductor.',
    },
    {
      'q': 'Como cambio mi metodo de pago?',
      'a':
          'En la vista de confirmación del viaje puedes tocar el método de pago y escoger entre las opciones disponibles.',
    },
    {
      'q': 'Que hago si no aparece ningun conductor?',
      'a':
          'Revisa tu conexión, confirma que el GPS esté activo y vuelve a intentar. También puedes usar la sección de soporte.',
    },
    {
      'q': 'Como reporto un problema con un viaje?',
      'a':
          'Desde Historial selecciona el viaje y usa la opcion de soporte para enviarnos detalles del inconveniente.',
    },
  ];
  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

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
                          childrenPadding: const EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            16,
                          ),
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
