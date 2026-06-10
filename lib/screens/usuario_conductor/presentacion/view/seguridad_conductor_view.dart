import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/soporte_chat_screen.dart';

class SeguridadConductorView extends StatefulWidget {
  const SeguridadConductorView({super.key});

  @override
  State<SeguridadConductorView> createState() =>
      _SeguridadConductorViewState();
}

class _SeguridadConductorViewState extends State<SeguridadConductorView> {
  final List<String> _emergencyContacts = [];

  Future<void> _openSupportChat() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SoporteChatScreen(userType: 'conductor'),
      ),
    );
  }

  Future<void> _showEmergencyContactsModal() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> addContact() async {
              if (_emergencyContacts.length >= 5) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Ya agregaste el máximo de 5 contactos.'),
                  ),
                );
                return;
              }

              final ctrl = TextEditingController();
              final value = await showDialog<String>(
                context: context,
                builder: (dialogCtx) => AlertDialog(
                  scrollable: true,
                  title: const Text('Nuevo contacto de emergencia'),
                  content: TextField(
                    controller: ctrl,
                    decoration: const InputDecoration(
                      hintText: 'Nombre y teléfono',
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (v) =>
                        Navigator.of(dialogCtx).pop(v.trim()),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogCtx).pop(),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed: () =>
                          Navigator.of(dialogCtx).pop(ctrl.text.trim()),
                      child: const Text('Guardar'),
                    ),
                  ],
                ),
              );

              if (value == null || value.isEmpty) return;

              setState(() => _emergencyContacts.add(value));
              setModalState(() {});
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 14,
                  bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Contactos de emergencia',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Puedes agregar hasta 5 contactos de emergencia.',
                      style: TextStyle(color: AppColores.textSecondary),
                    ),
                    const SizedBox(height: 14),
                    if (_emergencyContacts.isEmpty)
                      const Text(
                        'No tienes contactos agregados todavía.',
                        style: TextStyle(color: AppColores.textSecondary),
                      )
                    else
                      ...List.generate(_emergencyContacts.length, (index) {
                        final item = _emergencyContacts[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.contact_phone_outlined),
                          title: Text(item),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () {
                              setState(
                                () => _emergencyContacts.removeAt(index),
                              );
                              setModalState(() {});
                            },
                          ),
                        );
                      }),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: addContact,
                            icon: const Icon(Icons.person_add_alt_1),
                            label: Text(
                              'Agregar contacto (${_emergencyContacts.length}/5)',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seguridad'),
        backgroundColor: AppColores.surface,
        foregroundColor: AppColores.textPrimary,
        elevation: 0,
      ),
      backgroundColor: AppColores.background,
      body: ListView(
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.support_agent),
            title: const Text('Soporte'),
            subtitle: const Text('Abre un chat con el equipo de seguridad.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openSupportChat,
          ),
          ListTile(
            leading: const Icon(Icons.contact_phone_outlined),
            title: const Text('Contacto de emergencia'),
            subtitle: Text(
              _emergencyContacts.isEmpty
                  ? 'Administra tus contactos de confianza.'
                  : '${_emergencyContacts.length} de 5 contactos agregados.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showEmergencyContactsModal,
          ),
        ],
      ),
    );
  }
}
