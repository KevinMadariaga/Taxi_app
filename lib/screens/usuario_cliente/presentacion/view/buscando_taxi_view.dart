import 'package:flutter/material.dart';
import 'package:taxi_app/helper/responsive_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/inicio_cliente_view.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/ruta_cliente_view.dart';
import 'package:taxi_app/services/notificacion_servicio.dart';
import 'package:taxi_app/widgets/map_loading_widget.dart';

class BuscandoTaxiView extends StatefulWidget {
  final String? solicitudId;

  const BuscandoTaxiView({Key? key, this.solicitudId}) : super(key: key);

  @override
  State<BuscandoTaxiView> createState() => _BuscandoTaxiViewState();
}

class _BuscandoTaxiViewState extends State<BuscandoTaxiView> {
  StreamSubscription<DocumentSnapshot>? _sub;
  bool _assignedHandled = false;

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  void _startListening() {
    final id = widget.solicitudId;
    if (id == null || id.isEmpty) return;
    _sub = FirebaseFirestore.instance.collection('solicitudes').doc(id).snapshots().listen((snap) async {
      if (!mounted) return;
      if (!snap.exists) return;
      final data = snap.data();
      if (data == null) return;
      final status = data['status'] ?? data['estado'];
      if (status != null && status.toString() == 'asignado' && !_assignedHandled) {
        _assignedHandled = true;
        // Try to fetch conductor info (la notificación se mostrará luego, justo antes de abrir la ruta)
        try {
          final conductorId = (data['conductor'] is Map ? (data['conductor']['id'] ?? data['conductorId'] ?? data['driverId']) : (data['conductorId'] ?? data['driverId']))?.toString();
          String? nombre;
          String? telefono;
          if (conductorId != null && conductorId.isNotEmpty) {
            final doc = await FirebaseFirestore.instance.collection('conductor').doc(conductorId).get();
            final cd = doc.data();
            nombre = cd?['nombre']?.toString();
            telefono = cd?['telefono']?.toString();
          }
          if (!mounted) return;
          // Reemplazar pantalla "Buscando taxi" por pantalla de loader
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => LoaderMapaView(
                solicitudId: id,
                conductorId: conductorId,
                conductorName: nombre,
                conductorPhone: telefono,
              ),
            ),
          );
        } catch (_) {
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => LoaderMapaView(
                solicitudId: id,
                conductorId: null,
                conductorName: null,
                conductorPhone: null,
              ),
            ),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _cancelSolicitud() async {
    final id = widget.solicitudId;
    if (id != null && id.isNotEmpty) {
      final docRef = FirebaseFirestore.instance.collection('solicitudes').doc(id);
      try {
        // Intentar eliminar el documento directamente
        await docRef.delete();
      } catch (_) {
        // Si la eliminación falla, dejar el registro marcado como cancelado
        try {
          await docRef.update({
            'status': 'cancelado',
            'cancelledAt': FieldValue.serverTimestamp(),
          });
        } catch (_) {}
      }
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => InicioClienteView(),
    ));
   // Navigator.of(context).pop({'cancelado': true});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(ResponsiveHelper.wp(context, 4)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 24),
              const Icon(Icons.local_taxi, size: 72, color: Colors.black87),
              const SizedBox(height: 24),
              const Text('Buscando taxi', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.0),
                child: Text(
                  'Estamos buscando un conductor disponible. Esto puede tardar algunos segundos.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54, fontSize: 14),
                ),
              ),
              const SizedBox(height: 24),
              //const CircularProgressIndicator(),
              const SizedBox(height: 36),
              Center(
                child: SizedBox(
                  width: ResponsiveHelper.wp(context, 35),
                  height: ResponsiveHelper.wp(context, 12),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colores.amarillo,
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _cancelSolicitud,
                    child: Text('Cancelar', style: TextStyle(fontWeight: FontWeight.w700, fontSize: ResponsiveHelper.sp(context, 18)))
                    
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pantalla intermedia que muestra el loader de mapa durante 5 segundos
/// antes de navegar a la vista de ruta del cliente.
class LoaderMapaView extends StatefulWidget {
  final String solicitudId;
  final String? conductorId;
  final String? conductorName;
  final String? conductorPhone;

  const LoaderMapaView({
    Key? key,
    required this.solicitudId,
    this.conductorId,
    this.conductorName,
    this.conductorPhone,
  }) : super(key: key);

  @override
  State<LoaderMapaView> createState() => _LoaderMapaViewState();
}

class _LoaderMapaViewState extends State<LoaderMapaView> {
  @override
  void initState() {
    super.initState();
    _goToRouteAfterDelay();
  }

  void _goToRouteAfterDelay() async {
    Future.delayed(const Duration(seconds: 5), () async {
      if (!mounted) return;
      // Mostrar notificación justo al abrir la ruta del cliente
      try {
        final nombre = widget.conductorName;
        await NotificacionesServicio.instance.showAssignmentNotification(
          title: 'Conductor asignado',
          body: nombre != null && nombre.isNotEmpty
              ? '$nombre está en camino'
              : 'Se asignó un conductor',
        );
      } catch (_) {}

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => RutaClienteView(
            solicitudId: widget.solicitudId,
            conductorId: widget.conductorId,
            conductorName: widget.conductorName,
            conductorPhone: widget.conductorPhone,
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: MapLoadingWidget(),
        ),
      ),
    );
  }
}
