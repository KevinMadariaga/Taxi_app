import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/caracteristicas/seleccion_destino/datos/repositorios/geocodificacion_repository_impl.dart';
import 'package:taxi_app/core/utils/direccion_format.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('esPlusCode', () {
    test('reconoce Plus Codes, solos o con localidad', () {
      expect(esPlusCode('7GJ3+X4'), isTrue);
      expect(esPlusCode('7GJ3+X4 Ocaña'), isTrue);
      expect(esPlusCode('CFGH+2Q, Norte de Santander'), isTrue);
    });

    test('no confunde direcciones normales', () {
      expect(esPlusCode('Cra. 10ª # 20-10'), isFalse);
      expect(esPlusCode('Barrio Santa Clara'), isFalse);
      expect(esPlusCode(''), isFalse);
      expect(esPlusCode(null), isFalse);
    });
  });

  // Sin plugin nativo de geocoding en tests la resolución falla: es el mismo
  // camino que sin red en el teléfono.
  test('si no se resuelve la dirección no se muestran coordenadas', () async {
    final texto = await GeocodificacionRepositoryImpl().direccionDesde(
      const LatLng(8.230462, -73.346230),
    );
    expect(texto, textoSinDireccion);
    expect(texto, isNot(contains('8.23')));
  });
}
