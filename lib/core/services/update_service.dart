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
  }) : _newVersion = newVersion,
       _packageInfoProvider = packageInfoProvider,
       _minimumRequiredVersionFetcher = minimumRequiredVersionFetcher;

  factory UpdateService.production({
    String? androidId,
    String? iOSAppStoreId,
    MinimumRequiredVersionFetcher? minimumRequiredVersionFetcher,
  }) {
    return UpdateService(
      newVersion: NewVersionPlus(androidId: androidId, iOSId: iOSAppStoreId),
      packageInfoProvider: PackageInfo.fromPlatform,
      minimumRequiredVersionFetcher: minimumRequiredVersionFetcher,
    );
  }

  final NewVersionPlus _newVersion;
  final Future<PackageInfo> Function() _packageInfoProvider;
  final MinimumRequiredVersionFetcher? _minimumRequiredVersionFetcher;

  Future<UpdateCheckResult> checkForUpdate() async {
    try {
      final packageInfo = await _packageInfoProvider();
      final installedVersion = packageInfo.version;

      final minimumRequiredVersion = await _minimumRequiredVersionFetcher
          ?.call();

      final versionStatus = await _newVersion.getVersionStatus();
      final storeVersion = versionStatus?.storeVersion;
      final storeUrl = versionStatus?.appStoreLink;

      final hasStoreUpdate =
          storeVersion != null &&
          _isLowerVersion(installedVersion, storeVersion);

      final isMandatory =
          minimumRequiredVersion != null &&
          minimumRequiredVersion.trim().isNotEmpty &&
          _isLowerVersion(installedVersion, minimumRequiredVersion);

      return UpdateCheckResult(
        installedVersion: installedVersion,
        storeVersion: storeVersion,
        minimumRequiredVersion: minimumRequiredVersion,
        storeUrl: storeUrl,
        hasUpdate: hasStoreUpdate || isMandatory,
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
    final url = result.storeUrl;
    if (url == null || url.isEmpty) return false;

    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    return launchUrl(uri, mode: LaunchMode.externalApplication);
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
