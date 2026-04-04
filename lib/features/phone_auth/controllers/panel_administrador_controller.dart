import 'package:flutter/foundation.dart';

import '../models/admin_model.dart';
import '../models/driver_model.dart';
import '../services/user_data_service.dart';

class PanelAdministradorController extends ChangeNotifier {
  PanelAdministradorController({
    required this.adminId,
    UserDataService? userDataService,
  }) : _userDataService = userDataService ?? UserDataService();

  final String adminId;
  final UserDataService _userDataService;

  Stream<AdminModel?> get adminStream =>
      _userDataService.streamAdministrador(adminId);

  Stream<List<DriverModel>> get conductoresStream =>
      _userDataService.streamConductores(adminId: adminId);

  Stream<DriverModel?> conductorStream(String conductorId) {
    return _userDataService.streamConductor(conductorId);
  }
}
