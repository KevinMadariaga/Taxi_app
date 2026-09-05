// Tests de UpdateService — el chequeo de "hay una versión nueva" que corre
// en frío (splash_view.dart) y al volver de background (app_update_gate.dart).
//
// Sin esto, cero cobertura protegía la comparación de versiones ni el
// branching mandatory/opcional: un cambio futuro podía romper silenciosamente
// el aviso de actualización y nadie se enteraría hasta producción.
//
// Patrón: fakes por subclassing, sin mockito/mocktail (mismo criterio que
// buscando_taxi_viewmodel_test.dart) — `NewVersionPlus.getVersionStatus()` no
// es final ni la clase está sellada, así que se puede overridear para
// devolver un `VersionStatus` fijo sin HTTP real. `packageInfoProvider` y los
// fetchers de Remote Config ya son funciones inyectadas en el constructor de
// `UpdateService`, no hace falta fake para esos.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new_version_plus/new_version_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:taxi_app/core/services/update_service.dart';

/// Devuelve un [VersionStatus] fijo (o null) sin pegarle a la tienda real.
class _FakeNewVersionPlus extends NewVersionPlus {
  _FakeNewVersionPlus({this.status, this.shouldThrow = false});

  final VersionStatus? status;
  final bool shouldThrow;

  @override
  Future<VersionStatus?> getVersionStatus() async {
    if (shouldThrow) throw Exception('tienda no accesible');
    return status;
  }
}

PackageInfo _packageInfo(String version, {String buildNumber = '1'}) {
  return PackageInfo(
    appName: 'Ride',
    packageName: 'com.taxiya.taxiapp',
    version: version,
    buildNumber: buildNumber,
  );
}

VersionStatus _storeStatus(String storeVersion, {String? appStoreLink}) {
  return VersionStatus(
    localVersion: '0',
    storeVersion: storeVersion,
    appStoreLink: appStoreLink ?? 'https://play.google.com/store/apps/details?id=com.taxiya.taxiapp',
  );
}

UpdateService _buildService({
  required String installedVersion,
  VersionStatus? storeStatus,
  bool storeThrows = false,
  String? minimumRequiredVersion,
  String? latestVersion,
  String? androidId,
  String? iOSAppStoreId,
}) {
  return UpdateService(
    newVersion: _FakeNewVersionPlus(status: storeStatus, shouldThrow: storeThrows),
    packageInfoProvider: () async => _packageInfo(installedVersion),
    minimumRequiredVersionFetcher: minimumRequiredVersion == null
        ? null
        : () async => minimumRequiredVersion,
    latestVersionFetcher: latestVersion == null ? null : () async => latestVersion,
    androidId: androidId,
    iOSAppStoreId: iOSAppStoreId,
  );
}

void main() {
  group('UpdateService.checkForUpdate', () {
    test('sin actualización disponible cuando todo coincide', () async {
      final service = _buildService(
        installedVersion: '1.0.7',
        storeStatus: _storeStatus('1.0.7'),
        latestVersion: '1.0.7',
      );

      final result = await service.checkForUpdate();

      expect(result.hasUpdate, isFalse);
      expect(result.isMandatory, isFalse);
      expect(result.canSkip, isFalse);
    });

    test('actualización opcional detectada solo por la tienda', () async {
      final service = _buildService(
        installedVersion: '1.0.7',
        storeStatus: _storeStatus('1.0.8'),
      );

      final result = await service.checkForUpdate();

      expect(result.hasUpdate, isTrue);
      expect(result.isMandatory, isFalse);
      expect(result.canSkip, isTrue);
      expect(result.storeVersion, '1.0.8');
    });

    test('actualización opcional detectada solo por latest_version de Remote Config', () async {
      final service = _buildService(
        installedVersion: '1.0.7',
        storeStatus: null,
        latestVersion: '1.0.8',
      );

      final result = await service.checkForUpdate();

      expect(result.hasUpdate, isTrue);
      expect(result.isMandatory, isFalse);
      expect(result.canSkip, isTrue);
    });

    test('actualización obligatoria por minimum_required_version, con datos de tienda presentes', () async {
      final service = _buildService(
        installedVersion: '1.0.5',
        storeStatus: _storeStatus('1.0.8'),
        minimumRequiredVersion: '1.0.7',
      );

      final result = await service.checkForUpdate();

      expect(result.hasUpdate, isTrue);
      expect(result.isMandatory, isTrue);
      expect(result.canSkip, isFalse);
    });

    test('actualización obligatoria por minimum_required_version, sin datos de tienda', () async {
      final service = _buildService(
        installedVersion: '1.0.5',
        storeStatus: null,
        minimumRequiredVersion: '1.0.7',
      );

      final result = await service.checkForUpdate();

      expect(result.hasUpdate, isTrue);
      expect(result.isMandatory, isTrue);
      expect(result.canSkip, isFalse);
    });

    test('compara versiones por partes numéricas: 1.0.10 en tienda es mayor que 1.0.9 instalada', () async {
      final service = _buildService(
        installedVersion: '1.0.9',
        storeStatus: _storeStatus('1.0.10'),
      );

      final result = await service.checkForUpdate();

      expect(result.hasUpdate, isTrue);
      expect(result.canSkip, isTrue);
    });

    test('el build number (+62) no afecta la comparación', () async {
      final service = _buildService(
        installedVersion: '1.0.7+62',
        storeStatus: _storeStatus('1.0.7'),
        latestVersion: '1.0.7',
      );

      final result = await service.checkForUpdate();

      expect(result.hasUpdate, isFalse);
    });

    test('si falla el fetch de la tienda, sigue funcionando con Remote Config solo', () async {
      final service = _buildService(
        installedVersion: '1.0.7',
        storeStatus: null,
        storeThrows: true,
        latestVersion: '1.0.8',
      );

      final result = await service.checkForUpdate();

      expect(result.hasUpdate, isTrue);
      expect(result.isMandatory, isFalse);
    });

    test('URL de fallback a la tienda: Android, cuando la tienda no devuelve link', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final service = _buildService(
        installedVersion: '1.0.7',
        storeStatus: null,
        storeThrows: true,
        latestVersion: '1.0.8',
        androidId: 'com.taxiya.taxiapp',
      );

      final result = await service.checkForUpdate();

      expect(
        result.storeUrl,
        'https://play.google.com/store/apps/details?id=com.taxiya.taxiapp',
      );
    });

    test('URL de fallback a la tienda: iOS, cuando la tienda no devuelve link', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final service = _buildService(
        installedVersion: '1.0.7',
        storeStatus: null,
        storeThrows: true,
        latestVersion: '1.0.8',
        iOSAppStoreId: '6761427773',
      );

      final result = await service.checkForUpdate();

      expect(result.storeUrl, 'https://apps.apple.com/app/id6761427773');
    });
  });
}
