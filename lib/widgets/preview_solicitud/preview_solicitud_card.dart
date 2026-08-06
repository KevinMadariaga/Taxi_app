import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodels/preview_solicitud.dart';

import 'widgets/acciones_solicitud_buttons.dart';
import 'widgets/cliente_header_row.dart';
import 'widgets/comentario_cliente_box.dart';
import 'widgets/info_recogida_pago_row.dart';
import 'widgets/mapa_previsualizacion_solicitud.dart';
import 'widgets/precio_oferta_box.dart';

/// Tarjeta de previsualización de una solicitud, para que el conductor
/// decida aceptarla o contraofertar sin salir del mapa principal.
///
/// Mitad superior: mapa estático (Google Static Maps) con la perspectiva
/// del conductor hacia el cliente — encuadra ambos puntos y marca el
/// vehículo del conductor + el pin de marca (`map_pin_red.png`) sobre la
/// ubicación del cliente (ver [MapaPrevisualizacionSolicitud]).
///
/// Mitad inferior: datos del cliente (foto, nombre, distancia), punto de
/// recogida, método de pago, valor ofrecido/contraofertado, comentario y
/// los botones "Ofertar"/"Aceptar".
///
/// Widget puramente de presentación — no toca Firestore ni ningún estado
/// propio: toda la lógica de negocio (aceptar, contraofertar, ubicación en
/// vivo del conductor) vive en `InicioConductorViewmodel`/
/// `PreviewRouteController`, que le pasan los datos ya resueltos y reciben
/// los callbacks de acción.
class PreviewSolicitudCard extends StatelessWidget {
  const PreviewSolicitudCard({
    super.key,
    required this.preview,
    required this.driverLocation,
    this.clientPhotoUrl,
    this.isMoto = false,
    this.routePoints = const [],
    this.isLoadingRoute = false,
    this.isAcceptLoading = false,
    required this.onClose,
    required this.onAccept,
    required this.onCounterOffer,
  });

  final PreviewSolicitud preview;

  /// Ubicación actual del conductor — `null` mientras el GPS todavía no
  /// entrega el primer fix (el mapa cae a mostrar solo al cliente).
  final LatLng? driverLocation;
  final String? clientPhotoUrl;

  /// Ruta real (OSRM) conductor→cliente ya resuelta — dibuja la
  /// trazabilidad entre los dos marcadores en el mapa. Vacía mientras se
  /// calcula o si no hay ubicación del conductor todavía.
  final List<LatLng> routePoints;

  /// `true` mientras se resuelve la ruta OSRM conductor→cliente — el mapa
  /// se mantiene en placeholder hasta que se resuelve (con o sin ruta) para
  /// no pedir la imagen estática dos veces (una sin traza, otra con traza
  /// apenas llega) — ver [MapaPrevisualizacionSolicitud].
  final bool isLoadingRoute;

  /// Determina qué ícono de vehículo se dibuja en el mapa (carro/moto) —
  /// viene del perfil del conductor, no de la solicitud.
  final bool isMoto;

  /// `true` mientras la transacción de aceptar está en curso.
  final bool isAcceptLoading;

  final VoidCallback onClose;
  final VoidCallback onAccept;
  final VoidCallback onCounterOffer;

  @override
  Widget build(BuildContext context) {
    final geo = preview.solicitud.ubicacionInicial;
    final clientLocation = LatLng(geo.latitude, geo.longitude);

    final photoUrl = clientPhotoUrl ?? preview.clientPhotoUrl;
    final comentario = ComentarioClienteBox.normalizar(
      preview.comentarioCliente,
    );
    final valorCliente = preview.valorServicio;

    // `usableHeight` resta la barra de estado y la barra de navegación
    // nativa de Android (`viewPadding`, cubre tanto la barra de 3 botones
    // como el gesture bar) — un equipo con barra de navegación grande cae
    // a `isCompactHeight` aunque `MediaQuery.size.height` sea "alto" en
    // teoría, porque lo que importa es el espacio real disponible para el
    // contenido.
    final viewPaddingBottom = MediaQuery.of(context).viewPadding.bottom;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final usableHeight =
        MediaQuery.of(context).size.height - viewPaddingBottom - statusBarHeight;
    final isCompactHeight = usableHeight < 700;

    // Con contraoferta, `PrecioOfertaBox` pasa de una fila simple a dos
    // columnas (servicio tachado + contraoferta) — pero en modo compacto
    // (`isCompactPanel`, más abajo) esas dos columnas usan fuentes y
    // paddings más chicos, así que el contenido real termina siendo MÁS
    // bajo que el de la fila simple sin contraoferta, no más alto — por
    // eso ese caso necesita todavía más mapa (menos info) que el caso sin
    // comentario "normal", no el mismo ratio.
    final hayContraoferta = preview.valorContraoferta != null;
    final isCompactPanel = isCompactHeight || hayContraoferta;

    // Sin comentario el panel de info tiene menos contenido (solo tarjeta
    // de cliente/dirección + precio) — si se le deja el mismo 50% que con
    // comentario, sobra aire y ese aire termina como un `Spacer` en blanco
    // antes de "Aceptar". En vez de dejar ese hueco, el mapa sube (más
    // flex) y el panel de info baja al tamaño que su contenido real
    // necesita — y baja todavía más (mapa más grande aún) si además hay
    // contraoferta, por lo explicado arriba.
    //
    // Con comentario Y contraoferta juntos es el caso con MÁS contenido
    // (tarjeta cliente/dirección + comentario + precio de dos columnas +
    // botón) — ahí el mapa baja un poco más que el 50/50 base para darle
    // a la info el aire que ese contenido extra necesita.
    final comentarioVisible = comentario != null;
    final int mapFlex;
    final int infoFlex;
    if (comentarioVisible && hayContraoferta) {
      mapFlex = 46;
      infoFlex = 54;
    } else if (comentarioVisible) {
      mapFlex = 50;
      infoFlex = 50;
    } else if (hayContraoferta) {
      mapFlex = 68;
      infoFlex = 32;
    } else {
      mapFlex = 60;
      infoFlex = 40;
    }

    // Gap fijo y chico entre la tarjeta de cliente/dirección y la de
    // precio, siempre — un `Spacer` ahí (probado y descartado) deja un
    // hueco en blanco ENTRE dos tarjetas con borde que se lee como
    // contenido faltante, no como diseño. El aire de sobra restante (si
    // queda alguno) se concentra en un solo lugar: el `Spacer` antes de
    // "Aceptar" — mismo patrón que un CTA anclado al fondo de una hoja
    // (esperable, no se ve roto).
    final espacioAntesDePrecio = isCompactPanel ? 8.h : 10.h;

    // Sin alto manual: el llamador (`InicioConductorView`) envuelve esta
    // tarjeta en un `Positioned.fill`, así que ya recibe exactamente el
    // alto real disponible — calcularlo acá aparte con `MediaQuery` corría
    // el riesgo de no coincidir con ese alto real.
    //
    // Sin `AppBar`: el mapa ocupa hasta el borde superior real (más alto
    // que con la barra fija) y la flecha de volver flota sobre él — el
    // inset del status bar/notch se resuelve a mano acá (`statusBarHeight`)
    // en vez de que lo resuelva un `AppBar`.
    return Scaffold(
      // `false`: la tarjeta no tiene campos de texto propios, solo el modal
      // de contraoferta (otra ruta, con su propio manejo de
      // `viewInsets.bottom`). Sin esto, el teclado de ESE modal encogía el
      // `body` de este `Scaffold` (mapa + info) porque `viewInsets` es
      // global a todo el árbol, no solo a la ruta que abrió el teclado.
      resizeToAvoidBottomInset: false,
      backgroundColor: AppColores.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: mapFlex,
            child: Stack(
              children: [
                Positioned.fill(
                  child: MapaPrevisualizacionSolicitud(
                    driverLocation: driverLocation,
                    clientLocation: clientLocation,
                    isMoto: isMoto,
                    routePoints: routePoints,
                    isLoadingRoute: isLoadingRoute,
                  ),
                ),
                // Flecha de volver flotando — reemplaza al `AppBar` fijo,
                // deja ver más mapa arriba. `statusBarHeight` porque acá no
                // hay `AppBar`/`SafeArea` que ya haya corrido el contenido.
                Positioned(
                  top: statusBarHeight + 12,
                  left: 12,
                  child: Material(
                    color: AppColores.surface,
                    shape: const CircleBorder(),
                    elevation: 3,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onClose,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.arrow_back,
                          color: AppColores.textPrimary,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),
                // "Ofertar" flota sobre el mapa (no compite por ancho con
                // "Aceptar" abajo, que ahora es el único CTA de esa fila).
                Positioned(
                  top: statusBarHeight + 12,
                  right: 12,
                  child: Material(
                    color: AppColores.surface,
                    borderRadius: BorderRadius.circular(24),
                    elevation: 3,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: isAcceptLoading ? null : onCounterOffer,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.local_offer_outlined,
                              size: 16,
                              color: isAcceptLoading
                                  ? AppColores.grey400
                                  : AppColores.buttonPrimary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Ofertar',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: isAcceptLoading
                                    ? AppColores.grey400
                                    : AppColores.buttonPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: infoFlex,
            child: Padding(
              // `viewPadding.bottom` directo (no `SafeArea`): el `SafeArea`
              // ancestro de `InicioConductorView` ya puso en 0
              // `MediaQuery.padding` para todo lo de acá abajo, así que un
              // `SafeArea` anidado acá no reserva nada — `viewPadding` es
              // el inset físico real, ajeno a lo que un `SafeArea` de más
              // arriba ya haya "consumido" para sus descendientes.
              padding: EdgeInsets.only(bottom: viewPaddingBottom),
              // `LayoutBuilder` + `ConstrainedBox(minHeight)` +
              // `IntrinsicHeight`: el truco estándar de Flutter para que un
              // `Column` con un `Spacer` viva dentro de un
              // `SingleChildScrollView` — en pantallas altas/tablets el
              // sobrante se reparte como aire ENTRE el contenido y
              // "Aceptar" (se adapta como el mapa, que llena su Expanded
              // completo) en vez de quedar todo pegado en un solo bloque
              // muerto; en pantallas chicas, si el contenido no entra,
              // este mismo bloque scrollea en vez de recortarse.
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            16.w,
                            12.h,
                            16.w,
                            8.h,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Cliente + recogida + pago agrupados en UNA
                              // sola tarjeta (mismo lenguaje visual que la
                              // de precio y la de comentario, en vez de
                              // filas sueltas sobre el fondo) — separa
                              // claramente "quién y a dónde" del resto, y
                              // el borde propio evita que el texto largo
                              // de dirección se confunda con el fondo de
                              // la tarjeta.
                              Container(
                                padding: EdgeInsets.all(
                                  isCompactPanel ? 8.w : 12.w,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColores.background,
                                  borderRadius: BorderRadius.circular(14.r),
                                  border: Border.all(
                                    color: AppColores.borderSubtle,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    ClienteHeaderRow(
                                      nombre: preview.clientName ?? 'Cliente',
                                      photoUrl: photoUrl,
                                      distanciaKm: preview.distanciaKm,
                                      compact: isCompactPanel,
                                    ),
                                    SizedBox(height: isCompactPanel ? 8.h : 12.h),
                                    const Divider(
                                      color: AppColores.borderSubtle,
                                      height: 1,
                                    ),
                                    SizedBox(height: isCompactPanel ? 8.h : 12.h),
                                    InfoRecogidaPagoRow(
                                      direccionRecogida: _pickupText(preview),
                                      metodoPago: preview.paymentMethod,
                                    ),
                                  ],
                                ),
                              ),
                              if (comentario != null) ...[
                                SizedBox(height: isCompactPanel ? 8.h : 10.h),
                                ComentarioClienteBox(comentario: comentario),
                              ],
                              if (valorCliente != null) ...[
                                SizedBox(height: espacioAntesDePrecio),
                                PrecioOfertaBox(
                                  valorCliente: valorCliente,
                                  valorContraoferta: preview.valorContraoferta,
                                  compact: isCompactPanel,
                                ),
                              ],
                              const Spacer(),
                              SizedBox(height: isCompactPanel ? 4.h : 8.h),
                              AccionesSolicitudButtons(
                                isAcceptLoading: isAcceptLoading,
                                onAccept: onAccept,
                                compact: isCompactPanel,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _pickupText(PreviewSolicitud preview) {
    final title = preview.solicitud.origenTitle?.trim();
    if (title != null && title.isNotEmpty) return title;

    final address = preview.solicitud.direccion?.trim();
    if (address != null && address.isNotEmpty) return address;

    final lat = preview.solicitud.ubicacionInicial.latitude.toStringAsFixed(5);
    final lng = preview.solicitud.ubicacionInicial.longitude.toStringAsFixed(5);
    return '$lat, $lng';
  }
}
