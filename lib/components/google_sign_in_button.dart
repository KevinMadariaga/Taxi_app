import 'package:flutter/material.dart';
import '../services/google_sign_in_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class GoogleSignInButton extends StatelessWidget {
  final void Function(UserCredential?)? onSignIn;
  const GoogleSignInButton({super.key, this.onSignIn});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: Image.asset(
        'assets/img/google_logo.png',
        height: 18,
        width: 18,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(Icons.mail, color: Colors.red, size: 18),
      ),
      label: const Text('Iniciar sesión con Google'),
      onPressed: () async {
        final userCredential = await GoogleSignInService().signInWithGoogle();
        if (onSignIn != null) onSignIn!(userCredential);
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
