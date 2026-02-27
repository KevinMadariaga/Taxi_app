import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../components/social_icon_button.dart';
import '../services/google_sign_in_service.dart';
import 'usuario_cliente/presentacion/view/InicioClienteView.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
    Future<void> _onRegisterWithGoogle() async {
      setState(() => _loading = true);
      try {
        final userCredential = await GoogleSignInService().signInWithGoogle();
        final user = userCredential?.user;
        if (user == null) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo obtener la información del usuario.')));
          return;
        }
        // Guardar solo en la colección 'cliente'
        final clienteDoc = await FirebaseFirestore.instance.collection('cliente').doc(user.uid).get();
        if (!clienteDoc.exists) {
          await FirebaseFirestore.instance.collection('cliente').doc(user.uid).set({
            'id': user.uid,
            'nombre': user.displayName ?? '',
            'correo': user.email ?? '',
            'ubicacion': null, // Puedes actualizar esto después con la ubicación real
            'tipoUsuario': 'cliente',
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registro con Google exitoso.')));
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const InicioClienteView()));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al registrar con Google: $e')));
      } finally {
        setState(() => _loading = false);
      }
    }
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _onRegister() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingresa un email')));
      return;
    }
    final password = _passwordCtrl.text;
    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingresa una contraseña')));
      return;
    }

    setState(() => _loading = true);
    try {
      // Create Firebase Auth user
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
      final uid = cred.user?.uid;
      if (uid != null) {
        // Guardar solo en la colección 'cliente'
        final clienteDoc = await FirebaseFirestore.instance.collection('cliente').doc(uid).get();
        if (!clienteDoc.exists) {
          await FirebaseFirestore.instance.collection('cliente').doc(uid).set({
            'id': uid,
            'nombre': '',
            'correo': email,
            'ubicacion': null, // Puedes actualizar esto después con la ubicación real
            'tipoUsuario': 'cliente',
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registro guardado')));
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const InicioClienteView()));
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Auth error: ${e.message}')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      appBar: AppBar(title: const Text('Registro')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Column(
                children: [
                  SizedBox(
                    height: size.height * 0.22,
                    child: Image.asset(
                      'assets/img/taxi.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.local_taxi,
                        size: 140,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            TextField(
              controller: _emailCtrl,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordCtrl,
              decoration: const InputDecoration(labelText: 'Contraseña'),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else
              ElevatedButton(onPressed: _onRegister, child: const Text('Registrar')),

            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: Divider(color: Colors.grey, thickness: 1),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: Text(
                    'Regístrate con',
                    style: TextStyle(color: Colors.grey, fontSize: 15),
                  ),
                ),
                Expanded(
                  child: Divider(color: Colors.grey, thickness: 1),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SocialIconButton(
                  asset: 'assets/img/icon_google.png',
                  onTap: _onRegisterWithGoogle,
                ),
                const SizedBox(width: 24),
                SocialIconButton(
                  asset: 'assets/img/icon_facebook.png',
                  onTap: () {}, // Aquí puedes implementar el registro con Facebook
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
