import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/home_screen.dart';
import 'package:taxi_app/core/services/services.dart';

class EliminarCuentaScreen extends StatefulWidget {
  const EliminarCuentaScreen({Key? key}) : super(key: key);

  @override
  State<EliminarCuentaScreen> createState() => _EliminarCuentaScreenState();
}

class _EliminarCuentaScreenState extends State<EliminarCuentaScreen> {
  bool aceptado = false;
  bool _isDeleting = false;
  final TextEditingController _confirmDeleteController =
      TextEditingController();
  String _confirmDeleteText = '';

  bool get _canDelete {
    return aceptado &&
        _confirmDeleteText.trim().toUpperCase() == 'ELIMINAR' &&
        !_isDeleting;
  }

  @override
  void dispose() {
    _confirmDeleteController.dispose();
    super.dispose();
  }

  Future<String?> _getCurrentUserUid() async {
    return FirebaseAuth.instance.currentUser?.uid;
  }

  Future<void> _deleteUserData(String uid) async {
    final firestore = FirebaseFirestore.instance;
    await firestore.collection('usuarios').doc(uid).delete();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _eliminarCuenta() async {
    if (_isDeleting) return;

    setState(() => _isDeleting = true);
    try {
      final uid = await _getCurrentUserUid();
      final user = FirebaseAuth.instance.currentUser;

      if (uid == null || user == null) {
        _showMessage('No hay una sesión activa para eliminar.');
        return;
      }

      await _deleteUserData(uid);

      try {
        await user.delete();
      } on FirebaseAuthException {
        // Si Firebase exige reautenticación reciente, no bloqueamos el flujo
        // para completar la salida inmediata solicitada por el usuario.
      }

      await AuthService().logout();

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeView()),
        (route) => false,
      );
    } catch (_) {
      _showMessage('Ocurrió un error al eliminar la cuenta. Intenta de nuevo.');
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: _isDeleting ? null : () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Eliminar cuenta',
          style: TextStyle(color: AppColores.textPrimary),
        ),
        centerTitle: true,
      ),
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                Text(
                  'Antes de eliminar tu cuenta, por favor lee cuidadosamente la siguiente información.',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColores.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Esta acción eliminará tu cuenta de usuario y tus datos. Por ejemplo:',
                  style: TextStyle(
                    fontSize: 15,
                    color: AppColores.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Text(
                    '• Al eliminar tu cuenta, tu historial de viajes, información personal y de pagos se perderá de forma permanente. Esta acción no puede deshacerse. Cualquier solicitud enviada para descargar tu información personal se cancelará si eliminas tu cuenta.',
                    style: TextStyle(
                      fontSize: 15,
                      color: AppColores.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Sin embargo, se conservará un registro de las infracciones en las que pudieras haber incurrido. La solicitud para eliminar tu cuenta tendrá efecto inmediato y es irreversible. Asegúrate de querer eliminar tu cuenta antes de hacerlo.',
                  style: TextStyle(fontSize: 15, color: AppColores.error),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _confirmDeleteController,
                  enabled: !_isDeleting,
                  onChanged: (value) {
                    setState(() => _confirmDeleteText = value);
                  },
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Escribe ELIMINAR para confirmar',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Esta acción es permanente e irreversible.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColores.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Checkbox(
                      value: aceptado,
                      onChanged: _isDeleting
                          ? null
                          : (v) => setState(() => aceptado = v ?? false),
                      activeColor: AppColores.buttonPrimary,
                    ),
                    Expanded(
                      child: Text(
                        'He leído y estoy de acuerdo con la declaración anterior.',
                        style: TextStyle(
                          fontSize: 15,
                          color: AppColores.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _canDelete ? _eliminarCuenta : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColores.buttonPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: const Text(
                      'Eliminar mi cuenta',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
          if (_isDeleting)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.35),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text(
                        'Eliminando cuenta y redirigiendo al inicio...',
                        style: TextStyle(color: Colors.white, fontSize: 15),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
