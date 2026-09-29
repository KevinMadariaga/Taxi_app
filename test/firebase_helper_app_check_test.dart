import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/helpers/firebase_helper.dart';

void main() {
  test(
    'App Check se activa en release móvil (Android e iOS), no en debug ni web',
    () {
      expect(
        FirebaseHelper.debeActivarAppCheck(esDebug: false, esWeb: false),
        isTrue,
      );
      expect(
        FirebaseHelper.debeActivarAppCheck(esDebug: true, esWeb: false),
        isFalse,
      );
      expect(
        FirebaseHelper.debeActivarAppCheck(esDebug: false, esWeb: true),
        isFalse,
      );
    },
  );
}
