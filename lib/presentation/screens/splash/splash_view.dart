import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/constants/app_constants.dart';
import 'package:taxi_app/presentation/viewmodels/splash/splash_viewmodel.dart';
import 'package:taxi_app/presentation/widgets/update_available_dialog.dart';
import 'package:taxi_app/routes/app_routes.dart';
import 'package:taxi_app/caracteristicas/autenticacion/presentacion/vistas/home_screen.dart';
import 'package:taxi_app/core/services/services.dart';

const String _iOSAppStoreId = String.fromEnvironment('IOS_APP_STORE_ID');

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
      androidId: 'com.taxiya.taxiapp',
      iOSAppStoreId: _iOSAppStoreId.isEmpty ? null : _iOSAppStoreId,
      minimumRequiredVersionFetcher: _fetchMinimumRequiredVersion,
      latestVersionFetcher: _remoteConfigService.fetchLatestVersion,
    );

    _startAppFlow();
    // Fallback: navegar tras 2 s aunque otras comprobaciones tarden.
    Future.delayed(const Duration(seconds: 2), () async {
      if (!mounted || _hasNavigated) return;
      await _navigateFromSessionState();
    });
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

  Future<void> _startAppFlow() async {
    final shouldContinue = await _validateAppUpdate();
    if (!mounted || !shouldContinue) return;
    _viewModel.start();
  }

  Future<bool> _validateAppUpdate() async {
    final result = await _updateService.checkForUpdate();
    if (!mounted) return false;
    if (!result.hasUpdate) return true;

    final action = await UpdateAvailableDialog.show(context, result);
    if (!mounted) return false;

    if (action == UpdateDialogAction.updateNow) {
      final didOpenStore = await _updateService.openStore(result);
      if (!didOpenStore && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir la tienda. Intenta nuevamente.'),
          ),
        );
      }
      return !result.isMandatory;
    }

    return result.canSkip;
  }

  Future<String?> _fetchMinimumRequiredVersion() async {
    return _remoteConfigService.fetchMinimumRequiredVersion();
  }

  Future<void> _navigateFromSessionState() async {
    if (_hasNavigated) return;
    _hasNavigated = true;
    final next = await AuthService().determineInitialScreen();
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
