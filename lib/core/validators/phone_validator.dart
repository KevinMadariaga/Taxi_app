class PhoneValidator {
  static final RegExp _digitsOnly = RegExp(r'^\d+$');

  static String? validateTenDigits(String? value) {
    final input = (value ?? '').trim();

    if (input.isEmpty) {
      return 'Telefono es obligatorio.';
    }

    if (!_digitsOnly.hasMatch(input)) {
      return 'Telefono solo debe contener numeros.';
    }

    if (input.length != 10) {
      return 'Telefono debe tener exactamente 10 digitos.';
    }

    return null;
  }
}
