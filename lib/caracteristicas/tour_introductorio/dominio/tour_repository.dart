/// Recuerda si un usuario ya vio un recorrido introductorio.
abstract class TourRepository {
  Future<bool> yaVisto(String tourId, String uid);
  Future<void> marcarVisto(String tourId, String uid);
}
