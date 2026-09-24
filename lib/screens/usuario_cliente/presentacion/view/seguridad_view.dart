import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/core/helpers/responsive_helper.dart';
import 'package:taxi_app/features/phone_auth/services/user_data_service.dart';
import 'package:taxi_app/widgets/ajustes_ui.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/soporte_chat_screen.dart';

class SeguridadView extends StatefulWidget {
  const SeguridadView({super.key, this.userType = 'cliente'});

  final String userType;

  @override
  State<SeguridadView> createState() => _SeguridadViewState();
}

class _SeguridadViewState extends State<SeguridadView> {
  final UserDataService _userDataService = UserDataService();
  List<String> _emergencyContacts = [];

  @override
  void initState() {
    super.initState();
    _cargarContactos();
  }

  Future<void> _cargarContactos() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final contactos = await _userDataService.obtenerContactosEmergencia(uid);
    if (!mounted) return;
    setState(() => _emergencyContacts = contactos);
  }

  Future<void> _guardarContactos() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _userDataService.guardarContactosEmergencia(
      uid: uid,
      contactos: _emergencyContacts,
    );
  }

  Future<void> _openSupportChat() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SoporteChatScreen(userType: widget.userType),
      ),
    );
  }

  Future<void> _agregarContacto(
    BuildContext sheetContext,
    StateSetter setModalState,
  ) async {
    if (_emergencyContacts.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ya agregaste el máximo de 5 contactos.')),
      );
      return;
    }

    final ctrl = TextEditingController();
    final value = await showDialog<String>(
      context: sheetContext,
      builder: (dialogCtx) => AlertDialog(
        scrollable: true,
        backgroundColor: dialogCtx.palette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Nuevo contacto'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Nombre y teléfono',
            prefixIcon: Icon(Icons.person_add_alt_1_outlined),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.of(dialogCtx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColores.buttonPrimary,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(ctrl.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    ctrl.dispose();

    if (value == null || value.isEmpty || !mounted) return;
    setState(() => _emergencyContacts.add(value));
    setModalState(() {});
    await _guardarContactos();
  }

  Future<void> _showEmergencyContactsModal() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            final palette = sheetContext.palette;
            final lleno = _emergencyContacts.length >= 5;
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  0,
                  20,
                  16 + MediaQuery.of(sheetContext).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Contactos de emergencia',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Personas de confianza a las que avisar si algo pasa '
                      'durante un viaje. Hasta 5.',
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: palette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_emergencyContacts.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 22),
                        decoration: BoxDecoration(
                          color: palette.grey100,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.group_add_outlined,
                              size: 34,
                              color: palette.textSecondary,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Aún no tienes contactos agregados.',
                              style: TextStyle(color: palette.textSecondary),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: palette.borderSubtle),
                        ),
                        child: Column(
                          children: [
                            for (var i = 0; i < _emergencyContacts.length; i++)
                              ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppColores.primary
                                      .withValues(alpha: 0.18),
                                  foregroundColor: acentoMarca(sheetContext),
                                  child: Text(
                                    _emergencyContacts[i].trim().isEmpty
                                        ? '?'
                                        : _emergencyContacts[i]
                                              .trim()[0]
                                              .toUpperCase(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  _emergencyContacts[i],
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: palette.textPrimary,
                                  ),
                                ),
                                trailing: IconButton(
                                  tooltip: 'Quitar contacto',
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: AppColores.error,
                                  ),
                                  onPressed: () async {
                                    setState(
                                      () => _emergencyContacts.removeAt(i),
                                    );
                                    setModalState(() {});
                                    await _guardarContactos();
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 50,
                      child: FilledButton.icon(
                        onPressed: lleno
                            ? null
                            : () =>
                                  _agregarContacto(sheetContext, setModalState),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColores.buttonPrimary,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: Text(
                          lleno
                              ? 'Llegaste al máximo (5/5)'
                              : 'Agregar contacto '
                                    '(${_emergencyContacts.length}/5)',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
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
    final palette = context.palette;
    final resp = ResponsiveHelper.getResponsiveData(context);
    final horizontal = resp.deviceType == DeviceType.mobile
        ? resp.screenWidth * 0.05
        : 32.0;
    final n = _emergencyContacts.length;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: appBarNeutra(context, titulo: 'Seguridad'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 28),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const EncabezadoIcono(
                    icono: Icons.shield_outlined,
                    titulo: 'Viaja con tranquilidad',
                    descripcion:
                        'Ten a mano a quién avisar y cómo pedir ayuda si algo '
                        'no va bien en un viaje.',
                  ),
                  const SizedBox(height: 24),
                  SeccionAgrupada(
                    titulo: 'Tu red de apoyo',
                    children: [
                      FilaOpcion(
                        icono: Icons.contact_phone_outlined,
                        titulo: 'Contactos de emergencia',
                        subtitulo: n == 0
                            ? 'Agrega personas de confianza'
                            : '$n de 5 contactos agregados',
                        destacado: n == 0,
                        onTap: _showEmergencyContactsModal,
                      ),
                      FilaOpcion(
                        icono: Icons.support_agent_rounded,
                        titulo: 'Soporte de seguridad',
                        subtitulo: 'Reporta un incidente por el chat',
                        onTap: _openSupportChat,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const SeccionAgrupada(
                    titulo: 'En una emergencia',
                    children: [
                      FilaDato(
                        icono: Icons.local_police_outlined,
                        etiqueta: 'Línea nacional de emergencias',
                        valor: '123',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
