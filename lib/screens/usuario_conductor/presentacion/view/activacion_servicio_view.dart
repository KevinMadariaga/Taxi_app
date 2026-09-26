import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:taxi_app/core/constants/app_constants.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/features/phone_auth/services/user_data_service.dart';
import 'package:taxi_app/core/helpers/responsive_helper.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/widgets/ajustes_ui.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

// ============================================================================
// Datos de pago del gremio.
// Número internacional sin '+' ni espacios (Colombia = 57 + celular).
const String kWhatsappNumero = AppConstants.whatsappContacto;
const String kNequiNumero = '3152987320';
const String kBancolombiaNumero = '912-614617-52';
const int kValorActivacion = 1000;
// ============================================================================

/// Mensaje que el conductor envía por WhatsApp con el comprobante: dice
/// quién es (nombre con el que se registró) y con qué vehículo, para que el
/// administrador lo encuentre en el panel sin tener que preguntar.
String mensajeActivacionWhatsapp(Map<String, dynamic>? usuario) {
  String campo(String k) => (usuario?[k] ?? '').toString().trim();
  final nombre = [
    campo('nombre'),
    campo('apellido'),
  ].where((p) => p.isNotEmpty).join(' ');
  final tipo = campo('tipoVehiculo').toLowerCase() == 'moto' ? 'Moto' : 'Carro';
  final vehiculo = [
    tipo,
    campo('modeloVehiculo'),
    campo('colorVehiculo'),
  ].where((p) => p.isNotEmpty).join(' ');
  final placa = campo('placa').toUpperCase();
  final telefono = campo('telefono');

  return [
    'Hola, quiero activar el servicio de conductor en Ride.',
    '',
    'Soy ${nombre.isEmpty ? 'un conductor registrado' : nombre} y me '
        'registré en la app como conductor.',
    if (telefono.isNotEmpty) 'Celular: $telefono',
    'Vehículo: $vehiculo${placa.isEmpty ? '' : ' — placa $placa'}',
    '',
    'Adjunto el comprobante de pago de la activación. ¡Gracias!',
  ].join('\n');
}

/// Marca la solicitud de activación del conductor. El push al admin ya no lo
/// manda el cliente (auditoría de seguridad: `AdminFcmService` usaba la
/// server key legacy de FCM repartida a todos los dispositivos vía Remote
/// Config); lo dispara `onSolicitudActivacionConductor` en
/// functions/index.js al ver `solicitudConductor: true` en Firestore.
Future<void> _marcarSolicitudActivacion() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  try {
    await UserDataService().marcarSolicitudActivacion(uid);
  } catch (e, st) {
    ErrorReporter.report(e, st, reason: 'activacion_servicio_view');
  }
}

/// Modal de bienvenida/activación que se muestra al conductor cuando toca
/// "Conectado" con la membresía NO `activa`. Se puede cerrar tocando afuera
/// o con back — el conductor puede seguir mirando la interfaz sin activar el
/// servicio. Permite ir a pagar (Activar) o volver a ser cliente
/// ([onVolverCliente]).
Future<void> mostrarBienvenidaConductorDialog(
  BuildContext context, {
  required VoidCallback onVolverCliente,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final palette = ctx.palette;
      return Dialog(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const EncabezadoIcono(
                  icono: Icons.local_taxi_rounded,
                  titulo: 'Bienvenido a Ride',
                  descripcion:
                      'Ya eres conductor. Activa tu servicio para empezar '
                      'a recibir viajes de pasajeros cerca de ti.',
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: palette.background,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: palette.borderSubtle),
                  ),
                  child: Column(
                    children: [
                      const _InfoBienvenida(
                        icono: Icons.payments_outlined,
                        titulo: 'Paga la membresía',
                        detalle: 'Por Nequi o Bancolombia.',
                      ),
                      Divider(height: 1, indent: 58, color: palette.divider),
                      const _InfoBienvenida(
                        icono: Icons.receipt_long_outlined,
                        titulo: 'Envía el comprobante',
                        detalle: 'Por WhatsApp, directo desde la app.',
                      ),
                      Divider(height: 1, indent: 58, color: palette.divider),
                      const _InfoBienvenida(
                        icono: Icons.notifications_active_outlined,
                        titulo: 'Te avisamos al activarla',
                        detalle:
                            'Un administrador la revisa y te llega la '
                            'notificación para conectarte.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.sell_outlined,
                      size: 16,
                      color: palette.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Valor de la activación: ${_pesos(kValorActivacion)}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: palette.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColores.buttonPrimary,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () async {
                      // Registrar solicitud (notifica al admin) y abrir pago
                      // ENCIMA del modal (no lo cierra).
                      await _marcarSolicitudActivacion();
                      if (!context.mounted) return;
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ActivacionServicioView(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.bolt_rounded),
                    label: const Text(
                      'Activar servicio',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: onVolverCliente,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.textPrimary,
                      side: BorderSide(color: palette.grey300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.person_outline_rounded, size: 20),
                    label: const Text(
                      'Volver a ser cliente',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _InfoBienvenida extends StatelessWidget {
  const _InfoBienvenida({
    required this.icono,
    required this.titulo,
    required this.detalle,
  });

  final IconData icono;
  final String titulo;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColores.primary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icono, size: 19, color: AppColores.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  detalle,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _pesos(int valor) =>
    '\$${valor.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.')}';

/// Cómo activa el conductor su servicio: requisitos (los del registro se
/// marcan según lo que ya tiene guardado), los pasos y los datos de pago.
class ActivacionServicioView extends StatefulWidget {
  const ActivacionServicioView({super.key});

  @override
  State<ActivacionServicioView> createState() => _ActivacionServicioViewState();
}

class _ActivacionServicioViewState extends State<ActivacionServicioView> {
  Map<String, dynamic>? _usuario;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final data = await UserDataService().getUsuario(uid);
      if (mounted) setState(() => _usuario = data);
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'activacion_servicio_view');
    }
  }

  bool _tiene(String campo) =>
      (_usuario?[campo] ?? '').toString().trim().isNotEmpty;

  Future<void> _abrirWhatsapp() async {
    final uri = Uri.parse(
      'https://wa.me/$kWhatsappNumero?text='
      '${Uri.encodeComponent(mensajeActivacionWhatsapp(_usuario))}',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir WhatsApp.')),
      );
    }
  }

  void _copiar(String titulo, String numero) {
    Clipboard.setData(ClipboardData(text: numero));
    mostrarAvisoExito(
      context,
      titulo: 'Número copiado',
      mensaje: '$titulo: $numero',
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final resp = ResponsiveHelper.getResponsiveData(context);
    final horizontal = resp.deviceType == DeviceType.mobile
        ? resp.screenWidth * 0.05
        : 32.0;
    final cargado = _usuario != null;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: appBarNeutra(context, titulo: 'Activa tu servicio'),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
        decoration: BoxDecoration(
          color: palette.background,
          border: Border(top: BorderSide(color: palette.borderSubtle)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _abrirWhatsapp,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1FA855),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.chat_rounded),
              label: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Enviar comprobante por WhatsApp',
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ),
      ),
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
                    icono: Icons.verified_user_outlined,
                    titulo: 'Empieza a recibir viajes',
                    descripcion:
                        'Con la membresía activa verás las solicitudes de '
                        'pasajeros cerca de ti y podrás aceptarlas.',
                  ),
                  const SizedBox(height: 24),
                  SeccionAgrupada(
                    titulo: 'Requisitos',
                    children: [
                      _Requisito(
                        titulo: 'Foto de perfil con tu rostro',
                        detalle: 'El pasajero la ve para reconocerte.',
                        estado: !cargado
                            ? null
                            : (_tiene('foto') || _tiene('fotoUrl')),
                      ),
                      _Requisito(
                        titulo: 'Foto del vehículo',
                        detalle: 'Con la placa visible.',
                        estado: !cargado ? null : _tiene('fotoVehiculo'),
                      ),
                      _Requisito(
                        titulo: 'Placa registrada',
                        detalle: 'Tal como aparece en el vehículo.',
                        estado: !cargado ? null : _tiene('placa'),
                      ),
                      const _Requisito(
                        titulo: 'Documentos al día',
                        detalle:
                            'Licencia de conducción vigente, SOAT y revisión '
                            'técnico-mecánica. El administrador puede '
                            'pedírtelos.',
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const SeccionAgrupada(
                    titulo: 'Cómo se activa',
                    children: [
                      _Paso(
                        numero: 1,
                        titulo: 'Paga la membresía',
                        detalle: 'Por Nequi o Bancolombia (datos abajo).',
                      ),
                      _Paso(
                        numero: 2,
                        titulo: 'Envía el comprobante',
                        detalle:
                            'Por WhatsApp con el botón de abajo. El mensaje ya '
                            'lleva tu nombre y tu vehículo para identificarte.',
                      ),
                      _Paso(
                        numero: 3,
                        titulo: 'Un administrador lo revisa',
                        detalle:
                            'Verifica el pago y tus datos, y activa tu '
                            'membresía por los días pagados.',
                      ),
                      _Paso(
                        numero: 4,
                        titulo: '¡Listo para conducir!',
                        detalle:
                            'Te llega la notificación "Membresía activada". '
                            'Conéctate y empieza a recibir viajes.',
                        ultimo: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.only(left: 6, bottom: 8),
                    child: Text(
                      'PAGO DE LA ACTIVACIÓN',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: palette.borderSubtle),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Valor',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: palette.textSecondary,
                          ),
                        ),
                        Text(
                          _pesos(kValorActivacion),
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Divider(height: 1, color: palette.divider),
                        _CuentaPago(
                          icono: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              // Logo con navy sólido: fondo blanco fijo.
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Image.asset(
                              'assets/img/nequi.png',
                              width: 28,
                              height: 28,
                              errorBuilder: (_, _, _) => const Icon(
                                Icons.account_balance_wallet,
                                color: AppColores.secondary,
                              ),
                            ),
                          ),
                          titulo: 'Nequi',
                          numero: kNequiNumero,
                          onCopiar: () => _copiar('Nequi', kNequiNumero),
                        ),
                        Divider(height: 1, color: palette.divider),
                        _CuentaPago(
                          icono: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColores.secondary.withValues(
                                alpha: 0.14,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.account_balance_rounded,
                              color: AppColores.secondary,
                              size: 24,
                            ),
                          ),
                          titulo: 'Bancolombia',
                          numero: kBancolombiaNumero,
                          onCopiar: () =>
                              _copiar('Bancolombia', kBancolombiaNumero),
                        ),
                      ],
                    ),
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

/// Requisito con estado: `true` cumplido (check verde), `false` pendiente
/// (reloj ámbar), `null` informativo o todavía cargando.
class _Requisito extends StatelessWidget {
  const _Requisito({required this.titulo, required this.detalle, this.estado});

  final String titulo;
  final String detalle;
  final bool? estado;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (IconData icono, Color color) = switch (estado) {
      true => (Icons.check_circle_rounded, AppColores.success),
      false => (Icons.schedule_rounded, AppColores.warning),
      null => (Icons.description_outlined, palette.textSecondary),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 22, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  estado == false ? '$detalle Pendiente.' : detalle,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Paso extends StatelessWidget {
  const _Paso({
    required this.numero,
    required this.titulo,
    required this.detalle,
    this.ultimo = false,
  });

  final int numero;
  final String titulo;
  final String detalle;
  final bool ultimo;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ultimo
                  ? AppColores.success
                  : AppColores.primary.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: ultimo
                ? const Icon(Icons.check_rounded, size: 17, color: Colors.white)
                : Text(
                    '$numero',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: acentoMarca(context),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detalle,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CuentaPago extends StatelessWidget {
  const _CuentaPago({
    required this.icono,
    required this.titulo,
    required this.numero,
    required this.onCopiar,
  });

  final Widget icono;
  final String titulo;
  final String numero;
  final VoidCallback onCopiar;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          icono,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: palette.textSecondary,
                  ),
                ),
                Text(
                  numero,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    color: palette.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onCopiar,
            style: TextButton.styleFrom(
              foregroundColor: acentoMarca(context),
              iconColor: AppColores.primary,
            ),
            icon: const Icon(Icons.copy_rounded, size: 17),
            label: const Text(
              'Copiar',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
