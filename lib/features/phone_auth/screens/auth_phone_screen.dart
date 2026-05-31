import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/casos_uso/send_client_phone_otp_usecase.dart';
import 'package:taxi_app/core/app_colores.dart';

import '../controllers/phone_auth_controller.dart';
import 'otp_verification_screen.dart';
import '../widgets/phone_input_form.dart';

class AuthPhoneScreen extends StatelessWidget {
  const AuthPhoneScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<PhoneAuthController>(
      create: (context) {
        try {
          return PhoneAuthController(
            sendClientPhoneOtpUseCase: Provider.of<SendClientPhoneOtpUseCase>(
              context,
              listen: false,
            ),
          );
        } catch (_) {
          return PhoneAuthController();
        }
      },
      child: Consumer<PhoneAuthController>(
        builder: (context, vm, _) {
          return Scaffold(
            backgroundColor: AppColores.background,
            resizeToAvoidBottomInset: false,
            body: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFFF0B8), Colors.white],
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: IconButton(
                                onPressed: vm.loading
                                    ? null
                                    : () {
                                        Navigator.of(context).maybePop();
                                      },
                                icon: const Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                ),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: AppColores.textPrimary,
                                  side: const BorderSide(
                                    color: AppColores.grey300,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            PhoneInputForm(
                              onPhoneChanged: vm.setPhone,
                              loading: vm.loading,
                              adminMode: vm.adminMode,
                              onSubmit: () async {
                                await _sendCode(context, vm);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    AnimatedPadding(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      padding: EdgeInsets.fromLTRB(
                        16,
                        10,
                        16,
                        12 + MediaQuery.of(context).viewInsets.bottom,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ElevatedButton(
                            onPressed: vm.loading
                                ? null
                                : () async {
                                    await _sendCode(context, vm);
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColores.buttonPrimary,
                              foregroundColor: AppColores.textPrimary,
                              minimumSize: const Size(double.infinity, 56),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: vm.loading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColores.textPrimary,
                                    ),
                                  )
                                : const Text(
                                    'Enviar codigo',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 18,
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: vm.loading
                                  ? null
                                  : () async {
                                      await _showAdminKeyDialog(context, vm);
                                    },
                              icon: Icon(
                                Icons.admin_panel_settings_outlined,
                                size: 16,
                                color: AppColores.textSecondary.withValues(
                                  alpha: 0.65,
                                ),
                              ),
                              label: Text(
                                'Acceso gremio',
                                style: TextStyle(
                                  color: AppColores.textSecondary.withValues(
                                    alpha: 0.72,
                                  ),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
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
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
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
