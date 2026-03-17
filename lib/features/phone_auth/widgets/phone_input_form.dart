import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

class PhoneInputForm extends StatelessWidget {
  const PhoneInputForm({
    super.key,
    required this.countryCode,
    required this.countryOptions,
    required this.onCountryCodeChanged,
    required this.onPhoneChanged,
    required this.onSubmit,
    required this.loading,
    required this.adminMode,
  });

  final String countryCode;
  final List<String> countryOptions;
  final ValueChanged<String?> onCountryCodeChanged;
  final ValueChanged<String> onPhoneChanged;
  final VoidCallback onSubmit;
  final bool loading;
  final bool adminMode;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (adminMode)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
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
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColores.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Te enviaremos un codigo para verificar tu cuenta.',
              style: TextStyle(color: AppColores.textSecondary),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColores.grey200),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: countryCode,
                      items: countryOptions
                          .map(
                            (item) => DropdownMenuItem<String>(
                              value: item,
                              child: Text(item),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: loading ? null : onCountryCodeChanged,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    keyboardType: TextInputType.phone,
                    onChanged: onPhoneChanged,
                    enabled: !loading,
                    decoration: InputDecoration(
                      hintText: 'Numero de telefono',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: loading ? null : onSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColores.buttonPrimary,
                foregroundColor: AppColores.textWhite,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Enviar codigo',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
