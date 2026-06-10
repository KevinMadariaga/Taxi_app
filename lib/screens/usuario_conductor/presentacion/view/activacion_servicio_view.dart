import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/services/admin_fcm_service.dart';
import 'package:taxi_app/widgets/boton.dart';

// ============================================================================
// Datos de pago del gremio.
// Número internacional sin '+' ni espacios (Colombia = 57 + celular).
const String kWhatsappNumero = '573152987320';
const String kNequiNumero = '3152987320';
const String kBancolombiaNumero = '912-614617-52';
const int kValorActivacion = 1000;
// ============================================================================

const String _kMensajeWhatsapp = 'Quiero activar el servicio de Taxi Ya';

/// Marca la solicitud de activación del conductor (dispara push al admin).
Future<void> _marcarSolicitudActivacion() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  try {
    final doc = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
    final nombre = (doc.data()?['nombre'] ?? 'Conductor').toString();

    await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
      'solicitudConductor': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    AdminFcmService.instance.sendToAllAdmins(
      title: 'Solicitud de activación',
      body: '$nombre quiere activar el servicio de conductor',
      type: 'solicitud_activacion',
    );
  } catch (_) {}
}

/// Modal de bienvenida/activación que se muestra sobre [InicioConductor]
/// mientras la membresía NO esté `activa`. No se descarta (back ni tap fuera).
/// Permite ir a pagar (Activar) o volver a ser cliente ([onVolverCliente]).
Future<void> mostrarBienvenidaConductorDialog(
  BuildContext context, {
  required VoidCallback onVolverCliente,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.local_taxi, color: AppColores.primary),
            SizedBox(width: 8),
            Expanded(child: Text('Bienvenido a Taxi Ya')),
          ],
        ),
        content: const Text(
          'Bienvenido a Taxi Ya como conductor. Activa el servicio para continuar.',
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColores.buttonPrimary,
                    foregroundColor: AppColores.textWhite,
                    minimumSize: const Size.fromHeight(48),
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
                  child: const Text('Activar'),
                ),
              ),
              TextButton(
                onPressed: onVolverCliente,
                child: const Text('Volver a ser cliente'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class ActivacionServicioView extends StatelessWidget {
  const ActivacionServicioView({super.key});

  Future<void> _abrirWhatsapp(BuildContext context) async {
    final uri = Uri.parse(
      'https://wa.me/$kWhatsappNumero?text=${Uri.encodeComponent(_kMensajeWhatsapp)}',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir WhatsApp.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activación del servicio'),
        backgroundColor: AppColores.primary,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Text(
                    'Para activar el servicio debes pagar el valor de '
                    '\$${kValorActivacion.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.')} pesos, '
                    'los cuales puedes hacer envío por Nequi o Bancolombia.',
                    style: const TextStyle(fontSize: 16, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  _MetodoPago(
                    icono: Image.asset(
                      'assets/img/nequi.png',
                      width: 34,
                      height: 34,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.account_balance_wallet,
                        color: AppColores.primary,
                      ),
                    ),
                    titulo: 'Nequi',
                    numero: kNequiNumero,
                  ),
                  const SizedBox(height: 12),
                  const _MetodoPago(
                    icono: Icon(Icons.account_balance,
                        color: AppColores.primary),
                    titulo: 'Bancolombia',
                    numero: kBancolombiaNumero,
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Debes enviar el comprobante al WhatsApp.',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  CustomButton(
                    text: 'Enviar comprobante por WhatsApp',
                    icon: const Icon(Icons.chat, color: AppColores.textWhite),
                    onPressed: () => _abrirWhatsapp(context),
                    color: const Color(0xFF25D366),
                    height: 52,
                    fontSize: 15,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetodoPago extends StatelessWidget {
  final Widget icono;
  final String titulo;
  final String numero;

  const _MetodoPago({
    required this.icono,
    required this.titulo,
    required this.numero,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: SizedBox(width: 38, height: 38, child: Center(child: icono)),
        title: Text(titulo,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(numero, style: const TextStyle(fontSize: 15)),
        trailing: IconButton(
          icon: const Icon(Icons.copy, size: 20),
          tooltip: 'Copiar',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: numero));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$titulo copiado')),
            );
          },
        ),
      ),
    );
  }
}
