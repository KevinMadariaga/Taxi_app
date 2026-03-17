import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:taxi_app/core/constants/app_constants.dart';

class SplashViewModel extends ChangeNotifier {
  SplashViewModel({Duration? duration})
    : _duration = duration ?? AppConstants.splashDuration;

  final Duration _duration;

  Timer? _timer;
  bool _navigateToLogin = false;

  bool get navigateToLogin => _navigateToLogin;

  void start() {
    if (_timer != null) return;
    _timer = Timer(_duration, () {
      _navigateToLogin = true;
      notifyListeners();
    });
  }

  void consumeNavigation() {
    if (!_navigateToLogin) return;
    _navigateToLogin = false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
