import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/core/app_colores.dart';

import '../controllers/panel_administrador_controller.dart';
import '../models/driver_model.dart';
import '../widgets/conductor_list_item.dart';
import 'conductor_detalle_screen.dart';
import 'registro_conductor_screen.dart';

class PanelAdministradorScreen extends StatelessWidget {
  const PanelAdministradorScreen({super.key, required this.adminId});

  final String adminId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<PanelAdministradorController>(
      create: (_) => PanelAdministradorController(adminId: adminId),
      child: Consumer<PanelAdministradorController>(
        builder: (context, vm, _) {
          return Scaffold(
            backgroundColor: AppColores.background,
            appBar: AppBar(
              title: const Text('Panel administrador'),
              backgroundColor: AppColores.background,
              foregroundColor: AppColores.textPrimary,
              elevation: 0,
            ),
            body: SafeArea(
              child: Column(
                children: [
                  StreamBuilder(
                    stream: vm.adminStream,
                    builder: (context, snapshot) {
                      final admin = snapshot.data;
                      return Container(
                        margin: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: AppColores.primary,
                              backgroundImage: admin?.foto.isNotEmpty == true
                                  ? NetworkImage(admin!.foto)
                                  : null,
                              child: admin?.foto.isNotEmpty == true
                                  ? null
                                  : const Icon(Icons.admin_panel_settings),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    admin?.nombre ?? 'Administrador',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    admin?.gremio.isNotEmpty == true
                                        ? admin!.gremio
                                        : 'Sin gremio configurado',
                                    style: const TextStyle(
                                      color: AppColores.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  Expanded(
                    child: StreamBuilder<List<DriverModel>>(
                      stream: vm.conductoresStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        if (snapshot.hasError) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: Text(
                                'Error cargando conductores: ${snapshot.error}',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        }

                        final conductores = snapshot.data ?? const <DriverModel>[];
                        if (conductores.isEmpty) {
                          return const Center(
                            child: Text('Aun no hay conductores registrados.'),
                          );
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: conductores.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 4),
                          itemBuilder: (context, index) {
                            final conductor = conductores[index];
                            return ConductorListItem(
                              driver: conductor,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ConductorDetalleScreen(
                                      conductorId: conductor.idConductor,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RegistroConductorScreen(adminId: adminId),
                  ),
                );
              },
              backgroundColor: AppColores.buttonPrimary,
              foregroundColor: AppColores.textWhite,
              icon: const Icon(Icons.person_add),
              label: const Text('Registrar conductor'),
            ),
          );
        },
      ),
    );
  }
}
