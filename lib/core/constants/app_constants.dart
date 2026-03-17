class AppConstants {
  static const String appTitle = 'Taxi Ya';
  static const String splashMessage =
      'Consigue un taxi de manera facil y segura';

  static const Duration splashDuration = Duration(milliseconds: 2500);

  // Set true only for local QA with fictional phone numbers.
  // Example: flutter run --dart-define=PHONE_AUTH_TEST_MODE=true
  static const bool phoneAuthTestMode = bool.fromEnvironment(
    'PHONE_AUTH_TEST_MODE',
    defaultValue: false,
  );
}
