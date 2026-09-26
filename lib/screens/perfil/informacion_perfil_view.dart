import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/core/helpers/responsive_helper.dart';
import 'package:taxi_app/core/validators/vehiculo_validator.dart';
import 'package:taxi_app/features/phone_auth/services/user_data_service.dart';
import 'package:taxi_app/widgets/ajustes_ui.dart';

/// Pantalla de solo lectura con la información del perfil: foto, nombre,
/// apellido, correo y teléfono. Si es conductor, además muestra el/los
/// vehículo(s) registrados (foto, tipo y placa).
///
/// Resuelve sus propios datos a partir de [uid] (en vez de recibir el mapa
/// completo del padre) para no acoplar esta pantalla al ciclo de carga de
/// `PaginaPerfilUsuario`.
class InformacionPerfilView extends StatefulWidget {
  const InformacionPerfilView({
    super.key,
    required this.uid,
    required this.esConductor,
    this.onEditar,
  });

  final String uid;
  final bool esConductor;

  /// Acción de "Editar datos". Si es null, no se muestra el botón.
  final VoidCallback? onEditar;

  @override
  State<InformacionPerfilView> createState() => _InformacionPerfilViewState();
}

class _InformacionPerfilViewState extends State<InformacionPerfilView> {
  late final Future<Map<String, dynamic>?> _future;

  @override
  void initState() {
    super.initState();
    _future = UserDataService().getUsuario(widget.uid);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            backgroundColor: context.palette.background,
            appBar: appBarNeutra(context, titulo: 'Información del perfil'),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        return _InformacionPerfilContent(
          data: snapshot.data ?? const <String, dynamic>{},
          esConductor: widget.esConductor,
          onEditar: widget.onEditar,
        );
      },
    );
  }
}

class _InformacionPerfilContent extends StatelessWidget {
  const _InformacionPerfilContent({
    required this.data,
    required this.esConductor,
    this.onEditar,
  });

  final Map<String, dynamic> data;
  final bool esConductor;

  /// Acción de "Editar datos". Si es null, no se muestra el botón.
  final VoidCallback? onEditar;

  String _str(List<String> keys, [String fallback = '']) {
    for (final k in keys) {
      final v = data[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString();
    }
    return fallback;
  }

  static String _primero(Object? a, Object? b) {
    final x = (a ?? '').toString().trim();
    return x.isNotEmpty ? x : (b ?? '').toString().trim();
  }

  List<_Vehiculo> _vehiculos() {
    final result = <_Vehiculo>[];
    final raw = data['vehiculos'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        final v = entry.value;
        if (v is Map) {
          final foto = (v['foto'] ?? '').toString();
          final placa = (v['placa'] ?? '').toString();
          final tipo = entry.key.toString();
          // El vehículo en uso puede tener modelo/color solo en la raíz
          // (lo escribe el registro de conductor).
          final enUso =
              tipo == (data['tipoVehiculo'] ?? '').toString().toLowerCase();
          if (foto.isNotEmpty || placa.isNotEmpty) {
            result.add(
              _Vehiculo(
                tipo: tipo,
                foto: foto,
                placa: placa,
                modelo: _primero(
                  v['modelo'],
                  enUso ? data['modeloVehiculo'] : null,
                ),
                color: _primero(
                  v['color'],
                  enUso ? data['colorVehiculo'] : null,
                ),
              ),
            );
          }
        }
      }
    }
    // Fallback a campos legacy si no hay mapa de vehículos.
    if (result.isEmpty) {
      final foto = (data['fotoVehiculo'] ?? '').toString();
      final placa = (data['placa'] ?? '').toString();
      final tipo = (data['tipoVehiculo'] ?? '').toString();
      if (foto.isNotEmpty || placa.isNotEmpty) {
        result.add(
          _Vehiculo(
            tipo: tipo,
            foto: foto,
            placa: placa,
            modelo: (data['modeloVehiculo'] ?? '').toString(),
            color: (data['colorVehiculo'] ?? '').toString(),
          ),
        );
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final resp = ResponsiveHelper.getResponsiveData(context);
    final esMovil = resp.deviceType == DeviceType.mobile;
    final horizontal = esMovil ? resp.screenWidth * 0.05 : 32.0;
    final avatar = esMovil ? 92.0 : 112.0;

    final nombre = _str(['nombre']);
    final apellido = _str(['apellido']);
    final correo = _str(['correo', 'email'], 'Sin correo registrado');
    final telefono = _str(['telefono'], 'Sin teléfono registrado');
    final fotoUrl = _str(['foto', 'fotoUrl']);
    final nombreCompleto = [
      nombre,
      apellido,
    ].where((p) => p.trim().isNotEmpty).join(' ').trim();
    final vehiculos = esConductor ? _vehiculos() : const <_Vehiculo>[];
    final cache = (avatar * MediaQuery.devicePixelRatioOf(context)).round();

    return Scaffold(
      backgroundColor: palette.background,
      appBar: appBarNeutra(context, titulo: 'Información del perfil'),
      bottomNavigationBar: onEditar == null
          ? null
          : BarraAccionInferior(
              texto: 'Editar datos',
              icono: Icons.edit_rounded,
              onPressed: () {
                Navigator.of(context).pop();
                onEditar!();
              },
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
                  Center(
                    child: ClipOval(
                      child: SizedBox.square(
                        dimension: avatar,
                        child: fotoUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: fotoUrl,
                                fit: BoxFit.cover,
                                memCacheWidth: cache,
                                fadeInDuration: const Duration(
                                  milliseconds: 150,
                                ),
                                errorWidget: (_, _, _) => _sinFoto(palette),
                              )
                            : _sinFoto(palette),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    nombreCompleto.isEmpty ? 'Usuario' : nombreCompleto,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    esConductor ? 'Conductor' : 'Pasajero',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SeccionAgrupada(
                    titulo: 'Datos personales',
                    children: [
                      FilaDato(
                        icono: Icons.person_outline_rounded,
                        etiqueta: 'Nombre',
                        valor: nombre.isEmpty ? '—' : nombre,
                      ),
                      FilaDato(
                        icono: Icons.badge_outlined,
                        etiqueta: 'Apellido',
                        valor: apellido.isEmpty ? '—' : apellido,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SeccionAgrupada(
                    titulo: 'Contacto',
                    children: [
                      FilaDato(
                        icono: Icons.phone_iphone_rounded,
                        etiqueta: 'Celular',
                        valor: telefono,
                      ),
                      FilaDato(
                        icono: Icons.alternate_email_rounded,
                        etiqueta: 'Correo',
                        valor: correo,
                      ),
                    ],
                  ),
                  if (esConductor) ...[
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.only(left: 6, bottom: 8),
                      child: Text(
                        'VEHÍCULOS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: palette.textSecondary,
                        ),
                      ),
                    ),
                    ...vehiculos.map((v) => _VehiculoCard(vehiculo: v)),
                    if (vehiculos.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(
                          'Sin vehículos registrados.',
                          style: TextStyle(color: palette.textSecondary),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sinFoto(AppPalette palette) => ColoredBox(
    color: palette.grey200,
    child: Icon(Icons.person_rounded, size: 46, color: palette.textSecondary),
  );
}

class _Vehiculo {
  const _Vehiculo({
    required this.tipo,
    required this.foto,
    required this.placa,
    this.modelo = '',
    this.color = '',
  });
  final String tipo;
  final String foto;
  final String placa;
  final String modelo;
  final String color;

  String get tipoLabel {
    final t = tipo.toLowerCase();
    if (t == 'moto') return 'Moto';
    if (t == 'carro') return 'Carro';
    return tipo.isEmpty ? 'Vehículo' : tipo;
  }

  IconData get icon => tipo.toLowerCase() == 'moto'
      ? Icons.two_wheeler_rounded
      : Icons.directions_car_filled_rounded;
}

class _VehiculoCard extends StatelessWidget {
  const _VehiculoCard({required this.vehiculo});
  final _Vehiculo vehiculo;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.palette.borderSubtle),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: vehiculo.foto.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: vehiculo.foto,
                    fit: BoxFit.cover,
                    memCacheWidth: 900,
                    fadeInDuration: const Duration(milliseconds: 150),
                    placeholder: (_, _) => Container(
                      color: context.palette.grey200,
                      child: const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColores.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    errorWidget: (_, _, _) => Container(
                      color: context.palette.grey200,
                      child: Icon(
                        vehiculo.icon,
                        size: 48,
                        color: context.palette.grey400,
                      ),
                    ),
                  )
                : Container(
                    color: context.palette.grey200,
                    child: Icon(
                      vehiculo.icon,
                      size: 48,
                      color: context.palette.grey400,
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(vehiculo.icon, color: AppColores.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vehiculo.tipoLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: context.palette.textPrimary,
                        ),
                      ),
                      if (VehiculoValidator.descripcion(
                        vehiculo.modelo,
                        vehiculo.color,
                      ).isNotEmpty)
                        Text(
                          VehiculoValidator.descripcion(
                            vehiculo.modelo,
                            vehiculo.color,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: context.palette.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    // Fondo oscuro fijo (como una placa real): con
                    // `context.palette.textPrimary` el fondo se volvía casi
                    // blanco en modo oscuro y el texto blanco desaparecía.
                    color: AppColores.ink900,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    vehiculo.placa.isEmpty ? '—' : vehiculo.placa.toUpperCase(),
                    style: const TextStyle(
                      color: AppColores.textWhite,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      letterSpacing: 1,
                    ),
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
