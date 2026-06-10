import 'dart:io' show Platform;

import 'package:new_version_plus/new_version_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

typedef MinimumRequiredVersionFetcher = Future<String?> Function();

class UpdateCheckResult {
  const UpdateCheckResult({
    required this.installedVersion,
    required this.hasUpdate,
    required this.isMandatory,
    this.storeVersion,
    this.minimumRequiredVersion,
    this.storeUrl,
    this.errorMessage,
  });

  final String installedVersion;
  final String? storeVersion;
  final String? minimumRequiredVersion;
  final String? storeUrl;
  final bool hasUpdate;
  final bool isMandatory;
  final String? errorMessage;

  bool get canSkip => hasUpdate && !isMandatory;
}

class UpdateService {
  UpdateService({
    required NewVersionPlus newVersion,
    required Future<PackageInfo> Function() packageInfoProvider,
    MinimumRequiredVersionFetcher? minimumRequiredVersionFetcher,
    MinimumRequiredVersionFetcher? latestVersionFetcher,
    String? androidId,
    String? iOSAppStoreId,
  }) : _newVersion = newVersion,
       _packageInfoProvider = packageInfoProvider,
       _minimumRequiredVersionFetcher = minimumRequiredVersionFetcher,
       _latestVersionFetcher = latestVersionFetcher,
       _androidId = androidId,
       _iOSAppStoreId = iOSAppStoreId;

  factory UpdateService.production({
    String? androidId,
    String? iOSAppStoreId,
    MinimumRequiredVersionFetcher? minimumRequiredVersionFetcher,
    MinimumRequiredVersionFetcher? latestVersionFetcher,
  }) {
    return UpdateService(
      newVersion: NewVersionPlus(androidId: androidId, iOSId: iOSAppStoreId),
      packageInfoProvider: PackageInfo.fromPlatform,
      minimumRequiredVersionFetcher: minimumRequiredVersionFetcher,
      latestVersionFetcher: latestVersionFetcher,
      androidId: androidId,
      iOSAppStoreId: iOSAppStoreId,
    );
  }

  final NewVersionPlus _newVersion;
  final Future<PackageInfo> Function() _packageInfoProvider;
  final MinimumRequiredVersionFetcher? _minimumRequiredVersionFetcher;
  final MinimumRequiredVersionFetcher? _latestVersionFetcher;
  final String? _androidId;
  final String? _iOSAppStoreId;

  Future<UpdateCheckResult> checkForUpdate() async {
    try {
      final packageInfo = await _packageInfoProvider();
      final installedVersion = packageInfo.version;

      final minimumRequiredVersion = await _minimumRequiredVersionFetcher
          ?.call();
      final latestVersion = await _latestVersionFetcher?.call();

      String? storeVersion;
      String? storeUrl;
      try {
        final versionStatus = await _newVersion.getVersionStatus();
        storeVersion = versionStatus?.storeVersion;
        storeUrl = versionStatus?.appStoreLink;
      } catch (_) {
        // Si la tienda no es accesible (ej. app aún no publicada), seguimos
        // con la comparación de versiones por Remote Config.
      }

      final hasStoreUpdate =
          storeVersion != null &&
          _isLowerVersion(installedVersion, storeVersion);

      final hasLatestUpdate =
          latestVersion != null &&
          latestVersion.trim().isNotEmpty &&
          _isLowerVersion(installedVersion, latestVersion);

      final isMandatory =
          minimumRequiredVersion != null &&
          minimumRequiredVersion.trim().isNotEmpty &&
          _isLowerVersion(installedVersion, minimumRequiredVersion);

      return UpdateCheckResult(
        installedVersion: installedVersion,
        storeVersion: storeVersion ?? latestVersion,
        minimumRequiredVersion: minimumRequiredVersion,
        storeUrl: storeUrl ?? _fallbackStoreUrl(),
        hasUpdate: hasStoreUpdate || hasLatestUpdate || isMandatory,
        isMandatory: isMandatory,
      );
    } catch (error) {
      final packageInfo = await _packageInfoProvider();
      return UpdateCheckResult(
        installedVersion: packageInfo.version,
        hasUpdate: false,
        isMandatory: false,
        errorMessage: error.toString(),
      );
    }
  }

  Future<bool> openStore(UpdateCheckResult result) async {
    final url = result.storeUrl ?? _fallbackStoreUrl();
    if (url == null || url.isEmpty) return false;

    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// URL de tienda de respaldo construida a partir del id de la app, por si la
  /// detección automática de la tienda no devuelve enlace.
  String? _fallbackStoreUrl() {
    try {
      if (Platform.isIOS) {
        final id = _iOSAppStoreId;
        if (id != null && id.isNotEmpty) {
          return 'https://apps.apple.com/app/id$id';
        }
        return null;
      }
      if (Platform.isAndroid) {
        final id = _androidId;
        if (id != null && id.isNotEmpty) {
          return 'https://play.google.com/store/apps/details?id=$id';
        }
      }
    } catch (_) {}
    return null;
  }

  bool _isLowerVersion(String currentVersion, String targetVersion) {
    final current = _toComparableParts(currentVersion);
    final target = _toComparableParts(targetVersion);
    final maxLength = current.length > target.length
        ? current.length
        : target.length;

    for (var i = 0; i < maxLength; i++) {
      final currentPart = i < current.length ? current[i] : 0;
      final targetPart = i < target.length ? target[i] : 0;
      if (currentPart < targetPart) return true;
      if (currentPart > targetPart) return false;
    }

    return false;
  }

  List<int> _toComparableParts(String version) {
    final normalized = version.split('+').first;
    return normalized
        .split(RegExp(r'[^0-9]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
  }
}
