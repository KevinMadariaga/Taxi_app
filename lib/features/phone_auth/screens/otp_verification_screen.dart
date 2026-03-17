import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/home_cliente_view.dart';

import '../controllers/otp_verification_controller.dart';
import '../models/phone_code_result_model.dart';
import '../widgets/otp_code_field.dart';
import 'panel_administrador_screen.dart';
import 'registro_administrador_screen.dart';
import 'registro_cliente_phone_screen.dart';

class OtpVerificationScreen extends StatelessWidget {
  const OtpVerificationScreen({
    super.key,
    required this.verificationId,
    required this.resendToken,
    required this.phoneNumber,
    required this.isAdminMode,
  });

  final String verificationId;
  final int? resendToken;
  final String phoneNumber;
  final bool isAdminMode;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<OtpVerificationController>(
      create: (_) => OtpVerificationController(
        verificationId: verificationId,
        resendToken: resendToken,
        phoneNumber: phoneNumber,
        isAdminMode: isAdminMode,
      )..startTimer(),
      child: Consumer<OtpVerificationController>(
        builder: (context, vm, _) {
          return Scaffold(
            backgroundColor: AppColores.background,
            appBar: AppBar(
              elevation: 0,
              backgroundColor: AppColores.background,
              foregroundColor: AppColores.textPrimary,
              title: const Text('Verificacion'),
            ),
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Ingresa el codigo',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: AppColores.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'El codigo fue enviado a $phoneNumber',
                              style: const TextStyle(color: AppColores.textSecondary),
                            ),
                            const SizedBox(height: 16),
                            OtpCodeField(
                              enabled: !vm.loading,
                              onChanged: vm.setCode,
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.center,
                              child: TextButton(
                                onPressed: vm.canResend
                                    ? () async {
                                        try {
                                          await vm.resendCode();
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('Codigo reenviado correctamente.'),
                                            ),
                                          );
                                        } catch (e) {
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text(e.toString())),
                                          );
                                        }
                                      }
                                    : null,
                                child: Text(
                                  vm.canResend
                                      ? 'Reenviar codigo'
                                      : 'Reenviar en ${vm.resendCountdown}s',
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: vm.loading
                                  ? null
                                  : () async {
                                      await _verifyAndNavigate(context, vm);
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColores.buttonPrimary,
                                foregroundColor: AppColores.textWhite,
                                minimumSize: const Size(double.infinity, 50),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: vm.loading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Text('Verificar codigo'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _verifyAndNavigate(
    BuildContext context,
    OtpVerificationController vm,
  ) async {
    try {
      final resolution = await vm.verifyCode();
      if (!context.mounted) return;

      switch (resolution.destination) {
        case AuthNextDestination.clientHome:
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => HomeClienteView(authUid: resolution.uid),
            ),
            (route) => false,
          );
          break;
        case AuthNextDestination.clientRegistration:
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => RegistroClientePhoneScreen(
                uid: resolution.uid,
                telefono: resolution.phoneNumber,
              ),
            ),
            (route) => false,
          );
          break;
        case AuthNextDestination.adminPanel:
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => PanelAdministradorScreen(adminId: resolution.uid),
            ),
            (route) => false,
          );
          break;
        case AuthNextDestination.adminRegistration:
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => RegistroAdministradorScreen(
                uid: resolution.uid,
                telefono: resolution.phoneNumber,
              ),
            ),
            (route) => false,
          );
          break;
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Bad state: ', ''))),
      );
    }
  }
}
