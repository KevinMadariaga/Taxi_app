import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/constants/app_constants.dart';
import 'package:taxi_app/presentation/viewmodels/splash/splash_viewmodel.dart';
import 'package:taxi_app/presentation/widgets/update_available_dialog.dart';
import 'package:taxi_app/routes/app_routes.dart';
import 'package:taxi_app/screens/home_screen.dart';
import 'package:taxi_app/core/services/services.dart';

const String _iOSAppStoreId = String.fromEnvironment('IOS_APP_STORE_ID');

class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<Offset> _carSlide;
  late final SplashViewModel _viewModel;
  late final UpdateService _updateService;
  late final AppRemoteConfigService _remoteConfigService;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _logoFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.35, curve: Curves.easeIn),
    );

    _logoScale = Tween<double>(begin: 0.86, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOutBack),
      ),
    );

    _carSlide =
        Tween<Offset>(
          begin: const Offset(-1.25, 0),
          end: const Offset(1.25, 0),
        ).animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.2, 1.0, curve: Curves.easeInOut),
          ),
        );

    _viewModel = context.read<SplashViewModel>();
    _viewModel.addListener(_handleNavigation);
    _remoteConfigService = AppRemoteConfigService.instance;

    _updateService = UpdateService.production(
      androidId: 'com.taxiya.taxiapp',
      iOSAppStoreId: _iOSAppStoreId.isEmpty ? null : _iOSAppStoreId,
      minimumRequiredVersionFetcher: _fetchMinimumRequiredVersion,
    );

    _startAppFlow();
  }

  @override
  void dispose() {
    _viewModel.removeListener(_handleNavigation);
    _controller.dispose();
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: FadeTransition(
                      opacity: _logoFade,
                      child: ScaleTransition(
                        scale: _logoScale,
                        child: SizedBox(
                          width: 220,
                          height: 220,
                          child: Image.asset(
                            'assets/img/foreground_car.png',
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                                  Icons.local_taxi,
                                  size: 120,
                                  color: AppColores.primary,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 45.0),
                  child: Text(
                    AppConstants.splashMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColores.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
