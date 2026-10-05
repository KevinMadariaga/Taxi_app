import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:taxi_app/core/modelos/contacto_emergencia.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';
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
  List<ContactoEmergencia> _emergencyContacts = [];

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

  /// Guarda la lista completa. Si falla (sin red, permisos), restaura
  /// [anterior] y avisa: antes el contacto quedaba en pantalla aunque no se
  /// hubiera guardado, y desaparecía al volver a abrir.
  Future<bool> _guardarContactos(List<ContactoEmergencia> anterior) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    try {
      await _userDataService.guardarContactosEmergencia(
        uid: uid,
        contactos: _emergencyContacts,
      );
      return true;
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'seguridad: guardar contactos');
      if (!mounted) return false;
      setState(() => _emergencyContacts = anterior);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo guardar. Revisa tu conexión e inténtalo de nuevo.',
          ),
        ),
      );
      return false;
    }
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

    final nuevo = await showDialog<ContactoEmergencia>(
      context: sheetContext,
      builder: (_) => _NuevoContactoDialog(
        telefonosExistentes: {for (final c in _emergencyContacts) c.telefono},
      ),
    );
    if (nuevo == null || !mounted) return;

    final anterior = List<ContactoEmergencia>.of(_emergencyContacts);
    setState(() => _emergencyContacts = [..._emergencyContacts, nuevo]);
    setModalState(() {});
    await _guardarContactos(anterior);
    setModalState(() {});
  }

  Future<void> _quitarContacto(int i, StateSetter setModalState) async {
    final anterior = List<ContactoEmergencia>.of(_emergencyContacts);
    setState(() => _emergencyContacts = [..._emergencyContacts]..removeAt(i));
    setModalState(() {});
    await _guardarContactos(anterior);
    setModalState(() {});
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
                      // Solo la lista se desplaza: con 5 contactos (nombre +
                      // número) el panel se pasaba del alto disponible en
                      // pantallas chicas o con el teclado abierto, y así el
                      // título y "Agregar" siguen siempre a la vista.
                      Flexible(
                        child: Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: palette.borderSubtle),
                          ),
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                for (
                                  var i = 0;
                                  i < _emergencyContacts.length;
                                  i++
                                )
                                  ListTile(
                                    visualDensity: VisualDensity.compact,
                                    leading: CircleAvatar(
                                      backgroundColor: AppColores.primary
                                          .withValues(alpha: 0.18),
                                      foregroundColor: acentoMarca(
                                        sheetContext,
                                      ),
                                      child: Text(
                                        _emergencyContacts[i].nombre.isEmpty
                                            ? '?'
                                            : _emergencyContacts[i].nombre[0]
                                                  .toUpperCase(),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      _emergencyContacts[i].nombre.isEmpty
                                          ? 'Sin nombre'
                                          : _emergencyContacts[i].nombre,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: palette.textPrimary,
                                      ),
                                    ),
                                    subtitle: Text(
                                      _emergencyContacts[i].telefonoLegible,
                                      style: TextStyle(
                                        color: palette.textSecondary,
                                      ),
                                    ),
                                    trailing: IconButton(
                                      tooltip: 'Quitar contacto',
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: AppColores.error,
                                      ),
                                      onPressed: () =>
                                          _quitarContacto(i, setModalState),
                                    ),
                                  ),
                              ],
                            ),
                          ),
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

/// Formulario de un contacto nuevo: nombre y número por separado, validados
/// antes de devolver el resultado.
class _NuevoContactoDialog extends StatefulWidget {
  const _NuevoContactoDialog({required this.telefonosExistentes});

  final Set<String> telefonosExistentes;

  @override
  State<_NuevoContactoDialog> createState() => _NuevoContactoDialogState();
}

class _NuevoContactoDialogState extends State<_NuevoContactoDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _telefono = TextEditingController();

  @override
  void dispose() {
    _nombre.dispose();
    _telefono.dispose();
    super.dispose();
  }

  void _guardar() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      ContactoEmergencia(
        nombre: _nombre.text.trim(),
        telefono: ContactoEmergencia.normalizarTelefono(_telefono.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      backgroundColor: context.palette.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Nuevo contacto'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nombre,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                hintText: 'Ej. Mamá, Juan Pérez',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: ContactoEmergencia.validarNombre,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _telefono,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(
                  ContactoEmergencia.digitosTelefono,
                ),
              ],
              decoration: const InputDecoration(
                labelText: 'Número de celular',
                hintText: '3001234567',
                prefixText: '+57 ',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              validator: (v) {
                final error = ContactoEmergencia.validarTelefono(v);
                if (error != null) return error;
                final t = ContactoEmergencia.normalizarTelefono(v ?? '');
                if (widget.telefonosExistentes.contains(t)) {
                  return 'Ese número ya está en tus contactos';
                }
                return null;
              },
              onFieldSubmitted: (_) => _guardar(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColores.buttonPrimary,
            foregroundColor: Colors.black,
          ),
          onPressed: _guardar,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
