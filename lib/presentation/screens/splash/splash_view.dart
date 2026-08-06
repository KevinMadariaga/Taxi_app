import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/constants/app_constants.dart';
import 'package:taxi_app/presentation/viewmodels/splash/splash_viewmodel.dart';
import 'package:taxi_app/presentation/widgets/update_available_dialog.dart';
import 'package:taxi_app/routes/app_routes.dart';
import 'package:taxi_app/caracteristicas/autenticacion/presentacion/vistas/home_screen.dart';
import 'package:taxi_app/core/services/services.dart';
import 'package:taxi_app/core/services/initial_screen_resolver.dart';

/// Fondo del splash: blanco, en sintonía con el splash nativo para que NO
/// haya salto de color ni pantalla negra entre el arranque nativo y el primer
/// frame de Flutter.
const Color _fondoSplash = Colors.white;

class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView>
    with TickerProviderStateMixin {
  late final AnimationController _entrada;
  late final AnimationController _pulso;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _textoFade;

  late final SplashViewModel _viewModel;
  late final UpdateService _updateService;
  late final AppRemoteConfigService _remoteConfigService;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    // Entrada (una sola vez): logo aparece con fade + escala, luego el texto.
    _entrada = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _logoFade = CurvedAnimation(
      parent: _entrada,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
    );
    _logoScale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(
        parent: _entrada,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOutBack),
      ),
    );
    _textoFade = CurvedAnimation(
      parent: _entrada,
      curve: const Interval(0.45, 1.0, curve: Curves.easeIn),
    );
    _entrada.forward();

    // Pulso continuo y sutil del logo: comunica "cargando" sin peso.
    _pulso = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _viewModel = context.read<SplashViewModel>();
    _viewModel.addListener(_handleNavigation);
    _remoteConfigService = AppRemoteConfigService.instance;

    _updateService = UpdateService.production(
      androidId: AppConstants.androidPackageId,
      iOSAppStoreId: AppConstants.iosAppStoreId,
      minimumRequiredVersionFetcher: _fetchMinimumRequiredVersion,
      latestVersionFetcher: _remoteConfigService.fetchLatestVersion,
    );

    // El fallback de navegación NO se arma acá: se arma dentro de
    // `_startAppFlow`, recién cuando el chequeo de actualización resolvió.
    // Antes era un `Future.delayed(2s)` en paralelo que navegaba por debajo
    // del diálogo de actualización — con una actualización OBLIGATORIA el
    // usuario terminaba dentro de la app en una versión prohibida. Además
    // ganaba siempre la carrera contra `splashDuration` (2500 ms), dejando a
    // `SplashViewModel` como código muerto.
    _startAppFlow();
  }

  @override
  void dispose() {
    _viewModel.removeListener(_handleNavigation);
    _entrada.dispose();
    _pulso.dispose();
    super.dispose();
  }

  void _handleNavigation() {
    if (!_viewModel.navigateToLogin || !mounted) return;
    _viewModel.consumeNavigation();
    _navigateFromSessionState();
  }

  /// Techo duro del chequeo de actualización: `checkForUpdate()` encadena dos
  /// fetch de Remote Config más una consulta HTTP a la tienda, ninguna con
  /// timeout propio. Sin esta cota, una red mala dejaba el splash colgado.
  static const Duration _updateCheckTimeout = Duration(seconds: 6);

  /// Red de seguridad por si el timer de `SplashViewModel` no dispara. Va
  /// DESPUÉS de `splashDuration` a propósito: el camino normal es el del
  /// ViewModel, este solo rescata.
  static const Duration _navFallbackDelay = Duration(milliseconds: 4000);

  Future<void> _startAppFlow() async {
    final shouldContinue = await _validateAppUpdate();
    // Actualización obligatoria (o widget desmontado): no se navega y NO se
    // arma el fallback — el usuario debe quedarse en el gate.
    if (!mounted || !shouldContinue) return;
    _viewModel.start();

    Future.delayed(_navFallbackDelay, () async {
      if (!mounted || _hasNavigated) return;
      await _navigateFromSessionState();
    });
  }

  Future<bool> _validateAppUpdate() async {
    UpdateCheckResult result;
    try {
      result = await _updateService.checkForUpdate().timeout(
        _updateCheckTimeout,
      );
    } catch (_) {
      // Si no se pudo determinar si hay actualización, se deja pasar: bloquear
      // el arranque por un fallo de red sería peor que no verificar.
      return true;
    }
    if (!mounted) return false;
    if (!result.hasUpdate) return true;

    // Con actualización obligatoria el gate se re-muestra al volver de la
    // tienda: `show()` ya cerró el diálogo, y como en ese caso no se navega,
    // el usuario quedaría mirando un splash vacío sin salida. El bucle solo
    // avanza con un tap real en "Actualizar", así que no puede girar solo.
    while (true) {
      final action = await UpdateAvailableDialog.show(context, result);
      if (!mounted) return false;

      if (action != UpdateDialogAction.updateNow) {
        // El diálogo obligatorio no es descartable (`barrierDismissible` y
        // `canPop` van con `canSkip`), así que acá solo se llega si era
        // opcional.
        return result.canSkip;
      }

      final didOpenStore = await _updateService.openStore(result);
      if (!mounted) return false;
      if (!didOpenStore) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir la tienda. Intenta nuevamente.'),
          ),
        );
      }
      if (!result.isMandatory) return true;
    }
  }

  Future<String?> _fetchMinimumRequiredVersion() async {
    return _remoteConfigService.fetchMinimumRequiredVersion();
  }

  Future<void> _navigateFromSessionState() async {
    if (_hasNavigated) return;
    _hasNavigated = true;
    final next = await InitialScreenResolver().determineInitialScreen();
    if (!mounted) return;

    if (next is HomeView) {
      Navigator.of(context).pushReplacementNamed(AppRoutes.login);
      return;
    }

    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => next));
  }

  @override
  Widget build(BuildContext context) {
    // El wordmark (ícono + "IDE" en un solo PNG, proporción ancha ~3:1) se
    // dimensiona por ancho, acotado para que no se vea ni chico ni desbordado
    // en tablets.
    final double logoWidth =
        (MediaQuery.of(context).size.width * 0.48).clamp(160.0, 260.0);

    return Scaffold(
      backgroundColor: _fondoSplash,
      body: Stack(
        children: [
          // ── Logo + marca: centrados en el medio exacto de la pantalla ──
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeTransition(
                  opacity: _logoFade,
                  child: ScaleTransition(
                    scale: _logoScale,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.97, end: 1.03).animate(
                        CurvedAnimation(
                          parent: _pulso,
                          curve: Curves.easeInOut,
                        ),
                      ),
                      child: Image.asset(
                        'assets/img/RIDE_transparent.png',
                        width: logoWidth,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => Icon(
                          Icons.local_taxi_rounded,
                          size: logoWidth * 0.4,
                          color: AppColores.primary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FadeTransition(
                  opacity: _textoFade,
                  child: Column(
                    children: [
                      Text(
                        AppConstants.splashMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                          color: AppColores.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Indicador de carga anclado abajo ──────────────────────────
          // Padding = inset real de la barra de navegación (gestos/3 botones)
          // + margen, para que SIEMPRE quede por encima de la barra de Android
          // en modo edge-to-edge y se vea completa.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewPaddingOf(context).bottom + 28,
              ),
              child: Center(
                child: FadeTransition(
                  opacity: _textoFade,
                  child: SizedBox(
                    width: 130,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        minHeight: 3.5,
                        backgroundColor: AppColores.primary.withValues(
                          alpha: 0.18,
                        ),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColores.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
