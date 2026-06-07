import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

import 'gestion_conductores_viewmodel.dart';

/// Pantalla de admin: gestiona conductores (clientes que cambiaron a rol
/// conductor) y sus solicitudes de activación con días límite.
class GestionConductoresScreen extends StatefulWidget {
  const GestionConductoresScreen({super.key});

  @override
  State<GestionConductoresScreen> createState() =>
      _GestionConductoresScreenState();
}

class _GestionConductoresScreenState extends State<GestionConductoresScreen>
    with SingleTickerProviderStateMixin {
  late final GestionConductoresViewModel _vm;
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _vm = GestionConductoresViewModel()..iniciar();
    _vm.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _vm.removeListener(_rebuild);
    _vm.dispose();
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pendientes = _vm.pendientes;
    final activos = _vm.activos;

    return Scaffold(
      backgroundColor: AppColores.background,
      appBar: AppBar(
        title: const Text(
          'Gestión de conductores',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: AppColores.primary,
        foregroundColor: Colors.black,
        elevation: 0,
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.black,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.black54,
          tabs: [
            Tab(text: 'Solicitudes (${pendientes.length})'),
            Tab(text: 'Activos (${activos.length})'),
          ],
        ),
      ),
      body: _vm.isLoading
          ? const Center(child: CircularProgressIndicator())
          : _vm.errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _vm.errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                )
              : TabBarView(
                  controller: _tab,
                  children: [
                    _buildLista(
                      pendientes,
                      'No hay solicitudes de activación.',
                      Icons.hourglass_empty_rounded,
                    ),
                    _buildLista(
                      activos,
                      'No hay conductores activos.',
                      Icons.local_taxi_outlined,
                    ),
                  ],
                ),
    );
  }

  Widget _buildLista(
    List<ConductorAdminItem> items,
    String vacio,
    IconData icono,
  ) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icono, size: 56, color: AppColores.grey400),
            const SizedBox(height: 12),
            Text(
              vacio,
              style: const TextStyle(color: AppColores.textSecondary),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _ConductorCard(
        item: items[i],
        onActivar: () => _activar(items[i]),
        onRechazar: () => _rechazar(items[i]),
      ),
    );
  }

  Future<void> _activar(ConductorAdminItem item) async {
    final dias = await _pedirDias(context);
    if (dias == null || !mounted) return;
    try {
      await _vm.activarConductor(item.uid, dias);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${item.nombre} activado por $dias día(s).'),
          backgroundColor: AppColores.success,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo activar.')),
      );
    }
  }

  Future<void> _rechazar(ConductorAdminItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Desactivar conductor?'),
        content: Text('Se desactivará el servicio de ${item.nombre}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Desactivar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _vm.rechazarConductor(item.uid);
  }

  /// Selector de días activos.
  Future<int?> _pedirDias(BuildContext context) {
    const opciones = [1, 2, 3, 7, 15, 30];
    final customCtrl = TextEditingController();
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Días de servicio activo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: opciones
                  .map(
                    (d) => ActionChip(
                      label: Text('$d día${d > 1 ? 's' : ''}'),
                      backgroundColor:
                          AppColores.primary.withValues(alpha: 0.15),
                      onPressed: () => Navigator.pop(ctx, d),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: customCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Otra cantidad de días',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final v = int.tryParse(customCtrl.text.trim());
              if (v != null && v > 0) Navigator.pop(ctx, v);
            },
            child: const Text('Activar'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ConductorCard extends StatelessWidget {
  const _ConductorCard({
    required this.item,
    required this.onActivar,
    required this.onRechazar,
  });

  final ConductorAdminItem item;
  final VoidCallback onActivar;
  final VoidCallback onRechazar;

  String _restanteTexto() {
    final r = item.tiempoRestante;
    if (r == null) return '';
    if (r.inDays >= 1) return 'Quedan ${r.inDays} día(s)';
    if (r.inHours >= 1) return 'Quedan ${r.inHours} h';
    return 'Quedan ${r.inMinutes} min';
  }

  @override
  Widget build(BuildContext context) {
    final hasFoto = item.foto.isNotEmpty;
    final esModoActivar = item.pendiente; // pendiente o expirado
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColores.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColores.borderSubtle),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AppColores.grey200,
            backgroundImage: hasFoto ? NetworkImage(item.foto) : null,
            child: !hasFoto
                ? const Icon(Icons.person, color: AppColores.textSecondary)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.nombre.isNotEmpty ? item.nombre : 'Conductor',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppColores.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.placa.isNotEmpty || item.tipoVehiculo.isNotEmpty)
                  Text(
                    [item.tipoVehiculo, item.placa]
                        .where((s) => s.isNotEmpty)
                        .join(' · '),
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColores.textSecondary,
                    ),
                  ),
                const SizedBox(height: 4),
                _estadoChip(),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (esModoActivar)
            ElevatedButton(
              onPressed: onActivar,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColores.primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(item.expirado ? 'Reactivar' : 'Activar'),
            )
          else
            OutlinedButton(
              onPressed: onRechazar,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Desactivar'),
            ),
        ],
      ),
    );
  }

  Widget _estadoChip() {
    late Color c;
    late String t;
    if (item.activo) {
      c = AppColores.success;
      t = _restanteTexto().isEmpty ? 'Activo' : 'Activo · ${_restanteTexto()}';
    } else if (item.expirado) {
      c = Colors.red;
      t = 'Servicio expirado';
    } else if (item.estadoSolicitud == 'rechazado') {
      c = Colors.red;
      t = 'Rechazado';
    } else {
      c = AppColores.warning;
      t = 'Solicita activación';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        t,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c),
      ),
    );
  }
}
