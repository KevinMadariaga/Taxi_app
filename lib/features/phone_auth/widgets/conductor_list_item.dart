import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

import '../models/driver_model.dart';

class ConductorListItem extends StatelessWidget {
  const ConductorListItem({
    super.key,
    required this.driver,
    required this.onTap,
  });

  final DriverModel driver;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: AppColores.primary,
          backgroundImage: driver.fotoConductor.isNotEmpty
              ? NetworkImage(driver.fotoConductor)
              : null,
          child: driver.fotoConductor.isEmpty
              ? const Icon(Icons.person, color: AppColores.textPrimary)
              : null,
        ),
        title: Text(
          driver.nombre,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text('Placa: ${driver.placa}'),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
