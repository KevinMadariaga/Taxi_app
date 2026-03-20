import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:taxi_app/core/app_colores.dart';

class PhoneInputForm extends StatelessWidget {
  const PhoneInputForm({
    super.key,
    required this.onPhoneChanged,
    required this.onSubmit,
    required this.loading,
    required this.adminMode,
  });

  final ValueChanged<String> onPhoneChanged;
  final VoidCallback onSubmit;
  final bool loading;
  final bool adminMode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (adminMode)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColores.warning.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'Modo administrador activo',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColores.textPrimary,
              ),
            ),
          ),
        const Text(
          'Introduce tu numero de telefono',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: AppColores.textPrimary,
            height: 1.08,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Te enviaremos un codigo para verificar tu telefono',
          style: TextStyle(color: AppColores.textSecondary, fontSize: 15),
        ),
        const SizedBox(height: 26),
        Container(
          constraints: const BoxConstraints(minHeight: 62),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColores.grey400),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.phone_rounded,
                color: AppColores.textSecondary,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  keyboardType: TextInputType.phone,
                  enabled: !loading,
                  onChanged: (value) {
                    onPhoneChanged(value.replaceAll(' ', ''));
                  },
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                    _ColombiaPhoneFormatter(),
                  ],
                  style: const TextStyle(
                    color: AppColores.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w400,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Ingresa un numero valido de 10 digitos',
          style: TextStyle(color: AppColores.textSecondary, fontSize: 13),
        ),
      ],
    );
  }
}

class _ColombiaPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final limited = digitsOnly.length > 10
        ? digitsOnly.substring(0, 10)
        : digitsOnly;

    String formatted;
    if (limited.length <= 3) {
      formatted = limited;
    } else {
      formatted = '${limited.substring(0, 3)} ${limited.substring(3)}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
