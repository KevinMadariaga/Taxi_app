import 'package:taxi_app/caracteristicas/verificacion_recogida/dominio/entidades/codigo_verificacion_entity.dart';
import 'package:taxi_app/caracteristicas/verificacion_recogida/dominio/repositorios/codigo_verificacion_repository.dart';

import '../fuentes/codigo_verificacion_firestore_datasource.dart';

class CodigoVerificacionRepositoryImpl implements CodigoVerificacionRepository {
  CodigoVerificacionRepositoryImpl({
    CodigoVerificacionFirestoreDatasource? datasource,
  }) : _datasource = datasource ?? CodigoVerificacionFirestoreDatasource();

  final CodigoVerificacionFirestoreDatasource _datasource;

  @override
  Future<CodigoVerificacionEntity?> obtenerCodigo(String viajeId) {
    return _datasource.obtenerCodigo(viajeId);
  }

  @override
  Stream<CodigoVerificacionEntity?> watchCodigo(String viajeId) {
    return _datasource.watchCodigo(viajeId);
  }

  @override
  Future<void> guardarCodigo(String viajeId, CodigoVerificacionEntity codigo) {
    return _datasource.guardarCodigo(viajeId, codigo);
  }

  @override
  Future<void> marcarValidado(String viajeId) {
    return _datasource.marcarValidado(viajeId);
  }

  @override
  Future<void> incrementarIntentoFallido(String viajeId) {
    return _datasource.incrementarIntentoFallido(viajeId);
  }
}
