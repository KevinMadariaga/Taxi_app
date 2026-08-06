import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/core/utils/direccion_format.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/location_model.dart';

import '../entidades/solicitud_borrador.dart';
import '../modelos/crear_solicitud_resultado.dart';
import '../repositorios/cliente_repository.dart';
import '../repositorios/solicitud_repository.dart';

/// Crea la solicitud de viaje. Si el cliente ya tiene una activa, la
/// reutiliza (devuelve su id) en vez de duplicarla — si no, resuelve
/// cliente + direcciones legibles y la crea. Único punto de entrada de este
/// flujo: ni la vista ni el ViewModel tocan Firestore/Auth/geocoding
/// directamente.
class CrearSolicitudUseCase {
  CrearSolicitudUseCase({
    required SolicitudRepository solicitudRepository,
    required ClienteRepository clienteRepository,
  }) : _solicitudRepository = solicitudRepository,
       _clienteRepository = clienteRepository;

  final SolicitudRepository _solicitudRepository;
  final ClienteRepository _clienteRepository;

  // Etiquetas de origen que no aportan nada como dirección final del viaje
  // ("Tu ubicación", "Origen"...) — cuando el título/subtítulo del origen es
  // una de estas, hay que resolver la dirección real por geocodificación en
  // vez de guardar la etiqueta genérica en la solicitud.
  static const _etiquetasGenericasOrigen = {
    'tu ubicacion',
    'ubicacion',
    'ubicacion actual',
    'mi ubicacion',
    'origen',
  };

  Future<CrearSolicitudResultado> call(SolicitudBorrador borrador) async {
    final cliente = await _clienteRepository.obtenerActual();
    if (cliente == null) {
      return const CrearSolicitudFallo('No hay una sesión activa.');
    }

    // Falla CERRADA: si no se puede comprobar si ya hay una solicitud activa,
    // se aborta en vez de crear otra. Antes cualquier error devolvía `null`,
    // que se interpretaba como "no hay ninguna activa", así que un fallo
    // transitorio permitía acumular solicitudes simultáneas del mismo cliente.
    final String? activa;
    try {
      activa = await _solicitudRepository.buscarActivaDeCliente(cliente.id);
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'crear_solicitud_usecase');
      return const CrearSolicitudFallo(
        'No pudimos verificar si ya tienes un viaje en curso. '
        'Revisa tu conexión e intenta de nuevo.',
      );
    }
    if (activa != null) return SolicitudActivaExistente(activa);

    final origenDireccion = await _resolverDireccionOrigen(borrador.origen);
    final destinoDireccion = _resolverDireccionDestino(borrador.destino);

    final id = await _solicitudRepository.crear(
      cliente: cliente,
      origen: borrador.origen,
      origenDireccion: origenDireccion,
      destino: borrador.destino,
      destinoDireccion: destinoDireccion,
      tipoVehiculo: borrador.tipoVehiculo,
      metodoPago: borrador.metodoPago.trim().isEmpty
          ? 'Efectivo'
          : borrador.metodoPago.trim(),
      comentario: borrador.comentario.trim(),
      valorServicio: _parseValor(borrador.valorServicio),
    );
    return SolicitudCreada(id);
  }

  double _parseValor(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 0;
    return double.tryParse(digits) ?? 0;
  }

  bool _esEtiquetaGenerica(String? value) {
    if (value == null) return true;
    final normalizado = _normalizar(value);
    return normalizado.isEmpty ||
        _etiquetasGenericasOrigen.contains(normalizado);
  }

  String _normalizar(String value) {
    return value
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<String> _resolverDireccionOrigen(LocationModel origen) async {
    final subtitle = origen.subtitle?.trim();
    if (!_esEtiquetaGenerica(subtitle)) {
      final formatted = formatearDireccion(subtitle);
      return formatted.isNotEmpty ? formatted : subtitle!;
    }

    final title = origen.title?.trim();
    if (!_esEtiquetaGenerica(title)) {
      final formatted = formatearDireccion(title);
      return formatted.isNotEmpty ? formatted : title!;
    }

    return _resolverDesdeCoordenadas(origen.position);
  }

  String _resolverDireccionDestino(LocationModel destino) {
    final subtitle = formatearDireccion(destino.subtitle);
    if (subtitle.isNotEmpty) return subtitle;

    final title = formatearDireccion(destino.title);
    if (title.isNotEmpty) return title;

    return _coordsText(destino.position);
  }

  Future<String> _resolverDesdeCoordenadas(LatLng position) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        final resuelta = _friendlyDesdePlacemark(placemarks.first);
        if (resuelta.trim().isNotEmpty) return resuelta.trim();
      }
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'crear_solicitud_usecase');
    }
    return _coordsText(position);
  }

  String _friendlyDesdePlacemark(Placemark p) {
    final name = p.name?.trim() ?? '';
    final street = p.street?.trim() ?? '';
    final subLocality = p.subLocality?.trim() ?? '';
    final locality = p.locality?.trim() ?? '';

    if (name.isNotEmpty && street.isNotEmpty) {
      return formatearDireccion('$name, $street');
    }
    if (street.isNotEmpty && locality.isNotEmpty) {
      return formatearDireccion('$street, $locality');
    }
    final parts = [
      name,
      street,
      subLocality,
      locality,
    ].where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    return formatearDireccion(parts.take(2).join(', '));
  }

  String _coordsText(LatLng point) {
    return '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';
  }
}
