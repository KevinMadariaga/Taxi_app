import 'package:flutter/material.dart';
import 'package:taxi_app/core/constants/app_constants.dart';
import 'package:taxi_app/core/services/services.dart';
import 'package:taxi_app/presentation/widgets/update_available_dialog.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

/// Envuelve la app y vuelve a chequear si hay una nueva versión cada vez que la
/// app regresa de segundo plano (además del chequeo de arranque en el splash).
/// Muestra el modal central "Nueva actualización" usando el [navigatorKey].
class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate>
    with WidgetsBindingObserver {
  late final UpdateService _updateService;
  DateTime? _lastCheck;
  bool _checking = false;
  bool _dialogVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final rc = AppRemoteConfigService.instance;
    _updateService = UpdateService.production(
      androidId: AppConstants.androidPackageId,
      iOSAppStoreId: AppConstants.iosAppStoreId,
      minimumRequiredVersionFetcher: rc.fetchMinimumRequiredVersion,
      latestVersionFetcher: rc.fetchLatestVersion,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _maybeCheck();
    }
  }

  Future<void> _maybeCheck() async {
    if (_checking || _dialogVisible) return;
    // Throttle: evita rechequear en cada resume rápido.
    final now = DateTime.now();
    if (_lastCheck != null &&
        now.difference(_lastCheck!) < const Duration(minutes: 30)) {
      return;
    }
    _lastCheck = now;
    _checking = true;
    try {
      final result = await _updateService.checkForUpdate();
      if (!result.hasUpdate || !mounted) return;

      final ctx = widget.navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;

      _dialogVisible = true;
      final action = await UpdateAvailableDialog.show(ctx, result);
      _dialogVisible = false;

      if (action == UpdateDialogAction.updateNow) {
        await _updateService.openStore(result);
      }
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'app_update_gate');
    } finally {
      _checking = false;
      _dialogVisible = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
