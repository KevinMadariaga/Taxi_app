import 'package:shared_preferences/shared_preferences.dart';

import '../dominio/tour_repository.dart';

/// Guarda en el teléfono (por usuario y por recorrido) que ya se mostró,
/// igual que la bienvenida (`bienvenida_vista_$uid`).
class TourRepositoryImpl implements TourRepository {
  static String _clave(String tourId, String uid) =>
      'tour_visto_${tourId}_$uid';

  @override
  Future<bool> yaVisto(String tourId, String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_clave(tourId, uid)) ?? false;
  }

  @override
  Future<void> marcarVisto(String tourId, String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_clave(tourId, uid), true);
  }
}
