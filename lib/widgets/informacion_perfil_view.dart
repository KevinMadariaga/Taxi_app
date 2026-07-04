import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

/// Pantalla de solo lectura con la información del perfil: foto, nombre,
/// apellido, correo y teléfono. Si es conductor, además muestra el/los
/// vehículo(s) registrados (foto, tipo y placa).
class InformacionPerfilView extends StatelessWidget {
  const InformacionPerfilView({
    super.key,
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

  List<_Vehiculo> _vehiculos() {
    final result = <_Vehiculo>[];
    final raw = data['vehiculos'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        final v = entry.value;
        if (v is Map) {
          final foto = (v['foto'] ?? '').toString();
          final placa = (v['placa'] ?? '').toString();
          if (foto.isNotEmpty || placa.isNotEmpty) {
            result.add(
              _Vehiculo(tipo: entry.key.toString(), foto: foto, placa: placa),
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
        result.add(_Vehiculo(tipo: tipo, foto: foto, placa: placa));
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final avatarRadius = screenWidth * 0.145;
    final nameFontSize = screenWidth * 0.05;
    final sectionFontSize = screenWidth * 0.04;
    final horizontalPadding = screenWidth * 0.04;

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

    return Scaffold(
      backgroundColor: AppColores.background,
      appBar: AppBar(
        title: const Text('Información del perfil'),
        backgroundColor: AppColores.primary,
        foregroundColor: AppColores.textWhite,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                screenHeight * 0.024,
                horizontalPadding,
                screenHeight * 0.035,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: CircleAvatar(
                      radius: avatarRadius,
                      backgroundColor: AppColores.primary.withValues(
                        alpha: 0.18,
                      ),
                      backgroundImage: fotoUrl.isNotEmpty
                          ? CachedNetworkImageProvider(fotoUrl)
                          : null,
                      child: fotoUrl.isEmpty
                          ? Icon(
                              Icons.person,
                              size: avatarRadius,
                              color: AppColores.primaryDark,
                            )
                          : null,
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.015),
                  Center(
                    child: Text(
                      nombreCompleto.isEmpty ? 'Usuario' : nombreCompleto,
                      style: TextStyle(
                        fontSize: nameFontSize,
                        fontWeight: FontWeight.w800,
                        color: AppColores.textPrimary,
                      ),
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.03),
                  _InfoTile(
                    icon: Icons.badge_rounded,
                    label: 'Nombre',
                    value: nombre.isEmpty ? '—' : nombre,
                  ),
                  _InfoTile(
                    icon: Icons.person_outline_rounded,
                    label: 'Apellido',
                    value: apellido.isEmpty ? '—' : apellido,
                  ),
                  _InfoTile(
                    icon: Icons.email_outlined,
                    label: 'Correo',
                    value: correo,
                  ),
                  _InfoTile(
                    icon: Icons.phone_outlined,
                    label: 'Teléfono',
                    value: telefono,
                  ),
                  if (esConductor) ...[
                    SizedBox(height: screenHeight * 0.02),
                    Text(
                      'Vehículos',
                      style: TextStyle(
                        fontSize: sectionFontSize,
                        fontWeight: FontWeight.w800,
                        color: AppColores.textPrimary,
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.012),
                    ...vehiculos.map((v) => _VehiculoCard(vehiculo: v)),
                    if (vehiculos.isEmpty)
                      const Text(
                        'Sin vehículos registrados.',
                        style: TextStyle(color: AppColores.textSecondary),
                      ),
                  ],
                  if (onEditar != null) ...[
                    SizedBox(height: screenHeight * 0.03),
                    SizedBox(
                      width: double.infinity,
                      height: screenHeight * 0.065,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          onEditar!();
                        },
                        icon: const Icon(Icons.edit_rounded, size: 20),
                        label: Text(
                          'Editar datos',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: sectionFontSize,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColores.primary,
                          foregroundColor: AppColores.textPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Vehiculo {
  const _Vehiculo({
    required this.tipo,
    required this.foto,
    required this.placa,
  });
  final String tipo;
  final String foto;
  final String placa;

  String get tipoLabel {
    final t = tipo.toLowerCase();
    if (t == 'moto') return 'Moto';
    if (t == 'carro') return 'Carro';
    return tipo.isEmpty ? 'Vehículo' : tipo;
  }

  IconData get icon =>
      tipo.toLowerCase() == 'moto'
      ? Icons.two_wheeler_rounded
      : Icons.directions_car_filled_rounded;
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColores.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColores.borderSubtle),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColores.primary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: AppColores.primaryDark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColores.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColores.textPrimary,
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

class _VehiculoCard extends StatelessWidget {
  const _VehiculoCard({required this.vehiculo});
  final _Vehiculo vehiculo;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColores.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColores.borderSubtle),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 150,
            child: vehiculo.foto.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: vehiculo.foto,
                    fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 150),
                    placeholder: (_, _) => Container(
                      color: AppColores.grey200,
                      child: const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColores.primaryDark,
                            ),
                          ),
                        ),
                      ),
                    ),
                    errorWidget: (_, _, _) => Container(
                      color: AppColores.grey200,
                      child: Icon(
                        vehiculo.icon,
                        size: 48,
                        color: AppColores.grey400,
                      ),
                    ),
                  )
                : Container(
                    color: AppColores.grey200,
                    child: Icon(
                      vehiculo.icon,
                      size: 48,
                      color: AppColores.grey400,
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(vehiculo.icon, color: AppColores.primaryDark, size: 22),
                const SizedBox(width: 10),
                Text(
                  vehiculo.tipoLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppColores.textPrimary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColores.textPrimary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    vehiculo.placa.isEmpty
                        ? '—'
                        : vehiculo.placa.toUpperCase(),
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
