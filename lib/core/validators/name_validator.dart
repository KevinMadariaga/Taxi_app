class NameValidator {
  static final RegExp _lettersAndSpaces = RegExp(r'^[A-Za-zÀ-ÿ\s]+$');

  static String? validateRequired(String? value, {required String fieldName}) {
    final input = (value ?? '').trim();

    if (input.isEmpty) {
      return '$fieldName es obligatorio.';
    }

    if (!_lettersAndSpaces.hasMatch(input)) {
      return '$fieldName solo debe contener letras y espacios.';
    }

    return null;
  }
}
