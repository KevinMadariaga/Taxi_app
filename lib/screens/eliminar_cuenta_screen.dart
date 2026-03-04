import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

class EliminarCuentaScreen extends StatefulWidget {
  const EliminarCuentaScreen({Key? key}) : super(key: key);

  @override
  State<EliminarCuentaScreen> createState() => _EliminarCuentaScreenState();
}

class _EliminarCuentaScreenState extends State<EliminarCuentaScreen> {
  bool aceptado = false;

  Future<String?> _getCurrentUserUid() async {
    return FirebaseAuth.instance.currentUser?.uid;
  }

  Future<String> _getTipoUsuario(String uid) async {
    // Buscar en ambas colecciones si existe el usuario
    final firestore = FirebaseFirestore.instance;
    final clienteDoc = await firestore.collection('cliente').doc(uid).get();
    if (clienteDoc.exists) return 'cliente';
    final conductorDoc = await firestore.collection('conductor').doc(uid).get();
    if (conductorDoc.exists) return 'conductor';
    // Si no existe en ninguna, retorna cliente por defecto
    return 'cliente';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Eliminar cuenta', style: TextStyle(color: AppColores.textPrimary)),
        centerTitle: true,
      ),
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Text(
              'Antes de eliminar tu cuenta, por favor lee cuidadosamente la siguiente información.',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColores.textPrimary),
            ),
            const SizedBox(height: 16),
            Text(
              'Esta acción eliminará tu cuenta de usuario y tus datos. Por ejemplo:',
              style: TextStyle(fontSize: 15, color: AppColores.textSecondary),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Text(
                '• Al eliminar tu cuenta, tu historial de viajes, información personal y de pagos se perderá de forma permanente. Esta acción no puede deshacerse. Cualquier solicitud enviada para descargar tu información personal se cancelará si eliminas tu cuenta.',
                style: TextStyle(fontSize: 15, color: AppColores.textSecondary),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Sin embargo, se conservará un registro de las infracciones en las que pudieras haber incurrido. La solicitud para eliminar tu cuenta tendrá efecto inmediato y es irreversible. Asegúrate de querer eliminar tu cuenta antes de hacerlo.',
              style: TextStyle(fontSize: 15, color: AppColores.error),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Checkbox(
                  value: aceptado,
                  onChanged: (v) => setState(() => aceptado = v ?? false),
                  activeColor: AppColores.buttonPrimary,
                ),
                Expanded(
                  child: Text(
                    'He leído y estoy de acuerdo con la declaración anterior.',
                    style: TextStyle(fontSize: 15, color: AppColores.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: aceptado
                    ? () async {
                        final uid = await _getCurrentUserUid();
                        if (uid == null) return;
                        // Detectar tipo de usuario
                        final tipoUsuario = await _getTipoUsuario(uid);
                        // Eliminar datos en Firestore
                        try {
                          await FirebaseFirestore.instance
                              .collection(tipoUsuario)
                              .doc(uid)
                              .delete();
                        } catch (e) {}
                        // Eliminar usuario en Auth
                        try {
                          final user = FirebaseAuth.instance.currentUser;
                          if (user != null) await user.delete();
                        } catch (e) {}
                        // Navegar fuera (Home o pantalla de login)
                        if (context.mounted) {
                          Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                        }
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColores.buttonPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: const Text('Siguiente', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
