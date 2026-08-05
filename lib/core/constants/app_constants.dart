class AppConstants {
  static const String appTitle = 'Ride';
  static const String splashMessage =
      'Tu servicio de transporte de manera facil y segura';

  static const Duration splashDuration = Duration(milliseconds: 2500);

  // Set true only for local QA with fictional phone numbers.
  // Example: flutter run --dart-define=PHONE_AUTH_TEST_MODE=true
  static const bool phoneAuthTestMode = bool.fromEnvironment(
    'PHONE_AUTH_TEST_MODE',
    defaultValue: false,
  );

  // Key para Google Static Maps API (imagen estática del mapa de inicio del
  // cliente). Distinta de la key nativa de Android/iOS embebida en
  // AndroidManifest/AppDelegate: esa está restringida por package/bundle id
  // y no sirve para peticiones HTTP directas desde Dart. Pasar por build:
  // flutter run --dart-define=STATIC_MAPS_API_KEY=TU_KEY
  static const String staticMapsApiKey = String.fromEnvironment(
    'STATIC_MAPS_API_KEY',
  );

  // Identificadores de la app en cada tienda, usados por UpdateService para
  // consultar la versión publicada. No son secretos (son públicos en la
  // ficha de cada tienda) ni cambian entre builds de la misma app, así que
  // van fijos en vez de por --dart-define: un flag que se puede olvidar
  // pasar en un build de release dejaría la verificación de actualización
  // desactivada en silencio.
  static const String androidPackageId = 'com.taxiya.taxiapp';
  // apps.apple.com/.../id6761427773
  static const String iosAppStoreId = '6761427773';
}
