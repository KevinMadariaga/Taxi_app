/// Estilo oscuro de Google Maps — mismo estilo "Night" que documenta Google,
/// reutilizado en dos formatos porque la app dibuja mapas de dos maneras
/// distintas:
///
/// - [googleMapJson]: JSON de `stylers` para el widget `GoogleMap.style`
///   (mapa embebido interactivo — `MapaGoogle` y `viaje_cliente_screen`).
/// - [staticMapsQueryParams]: la MISMA paleta pero como parámetros
///   `style=feature:...|element:...|color:0x...` repetidos, el formato que
///   exige la Static Maps API (usada por el mapa-imagen del home de cliente,
///   del home de conductor y de "buscando taxi" — no aceptan el JSON).
class MapStyle {
  MapStyle._();

  static const String googleMapJson = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#1d2129"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#1d2129"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#8b93a0"}]},
  {"featureType": "administrative.locality", "elementType": "labels.text.fill", "stylers": [{"color": "#c7cdd6"}]},
  {"featureType": "poi", "elementType": "labels.text.fill", "stylers": [{"color": "#8b93a0"}]},
  {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#26302a"}]},
  {"featureType": "poi.park", "elementType": "labels.text.fill", "stylers": [{"color": "#7a9c7f"}]},
  {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#2e343d"}]},
  {"featureType": "road", "elementType": "geometry.stroke", "stylers": [{"color": "#212529"}]},
  {"featureType": "road", "elementType": "labels.text.fill", "stylers": [{"color": "#9098a3"}]},
  {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#3a4150"}]},
  {"featureType": "road.highway", "elementType": "geometry.stroke", "stylers": [{"color": "#212529"}]},
  {"featureType": "road.highway", "elementType": "labels.text.fill", "stylers": [{"color": "#d3d7dc"}]},
  {"featureType": "transit", "elementType": "geometry", "stylers": [{"color": "#2b3138"}]},
  {"featureType": "transit.station", "elementType": "labels.text.fill", "stylers": [{"color": "#8b93a0"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#141a21"}]},
  {"featureType": "water", "elementType": "labels.text.fill", "stylers": [{"color": "#5a6470"}]}
]
''';

  /// Mismos colores que [googleMapJson], en la sintaxis de `style=` que
  /// espera Static Maps API (sin `#`, con `0x` y separado por `|`).
  static const List<String> staticMapsQueryParams = [
    'feature:all|element:geometry|color:0x1d2129',
    'feature:all|element:labels.text.stroke|color:0x1d2129',
    'feature:all|element:labels.text.fill|color:0x8b93a0',
    'feature:poi.park|element:geometry|color:0x26302a',
    'feature:road|element:geometry|color:0x2e343d',
    'feature:road|element:geometry.stroke|color:0x212529',
    'feature:road.highway|element:geometry|color:0x3a4150',
    'feature:transit|element:geometry|color:0x2b3138',
    'feature:water|element:geometry|color:0x141a21',
  ];
}
