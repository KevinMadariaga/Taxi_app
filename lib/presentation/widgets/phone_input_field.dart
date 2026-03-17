import 'package:flutter/material.dart';

class PhoneInputField extends StatelessWidget {
  const PhoneInputField({
    super.key,
    required this.dialCode,
    required this.onChanged,
    this.enabled = true,
  });

  final String dialCode;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      enabled: enabled,
      keyboardType: TextInputType.phone,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: 'Numero de telefono',
        prefixText: '$dialCode ',
        border: const OutlineInputBorder(),
      ),
    );
  }
}
