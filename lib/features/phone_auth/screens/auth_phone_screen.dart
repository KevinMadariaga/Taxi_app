import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/core/app_colores.dart';

import '../controllers/phone_auth_controller.dart';
import 'otp_verification_screen.dart';
import '../widgets/phone_input_form.dart';

class AuthPhoneScreen extends StatelessWidget {
  const AuthPhoneScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<PhoneAuthController>(
      create: (_) => PhoneAuthController(),
      child: Consumer<PhoneAuthController>(
        builder: (context, vm, _) {
          return Scaffold(
            backgroundColor: AppColores.background,
            body: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFFF6D6), AppColores.background],
                ),
              ),
              child: SafeArea(
                child: Stack(
                  children: [
                    Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: PhoneInputForm(
                            countryCode: vm.countryCode,
                            countryOptions: vm.countryOptions,
                            onCountryCodeChanged: (value) {
                              if (value != null) vm.setCountryCode(value);
                            },
                            onPhoneChanged: vm.setPhone,
                            loading: vm.loading,
                            adminMode: vm.adminMode,
                            onSubmit: () async {
                              await _sendCode(context, vm);
                            },
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: TextButton.icon(
                        onPressed: vm.loading
                            ? null
                            : () async {
                                await _showAdminKeyDialog(context, vm);
                              },
                        icon: Icon(
                          Icons.admin_panel_settings_outlined,
                          size: 16,
                          color: AppColores.textSecondary.withValues(alpha: 0.65),
                        ),
                        label: Text(
                          'Acceso gremio',
                          style: TextStyle(
                            color: AppColores.textSecondary.withValues(alpha: 0.72),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _sendCode(BuildContext context, PhoneAuthController vm) async {
    try {
      final result = await vm.sendCode();
      if (!context.mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            verificationId: result.verificationId,
            resendToken: result.resendToken,
            phoneNumber: vm.fullPhone,
            isAdminMode: vm.adminMode,
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
      );
    }
  }

  Future<void> _showAdminKeyDialog(
    BuildContext context,
    PhoneAuthController vm,
  ) async {
    final controller = TextEditingController();

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Acceso administrador'),
          content: TextField(
            controller: controller,
            obscureText: true,
            decoration: const InputDecoration(hintText: 'Clave secreta'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Validar'),
            ),
          ],
        );
      },
    );

    if (accepted != true) return;

    final ok = vm.enableAdminMode(controller.text);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Modo administrador habilitado.'
              : 'Clave incorrecta. No se habilito el modo administrador.',
        ),
      ),
    );
  }
}
