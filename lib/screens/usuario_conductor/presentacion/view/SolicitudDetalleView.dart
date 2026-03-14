import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodel/InicioConductorViewModel.dart';

class SolicitudDetalleView extends StatelessWidget {
  final SolicitudPendiente solicitud;
  final LatLng? conductorPos;
  const SolicitudDetalleView({Key? key, required this.solicitud, required this.conductorPos}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final clientePos = LatLng(solicitud.latitud, solicitud.longitud);
    final Set<Marker> markers = {
      Marker(
        markerId: const MarkerId('cliente'),
        position: clientePos,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'Cliente'),
      ),
      if (conductorPos != null)
        Marker(
          markerId: const MarkerId('conductor'),
          position: conductorPos!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'Conductor'),
        ),
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final isSmall = width < 350;
        final isMedium = width < 500;
        final double avatarRadius = isSmall ? 28 : (isMedium ? 34 : 38);
        final double titleFont = isSmall ? 15 : (isMedium ? 18 : 20);
        final double labelFont = isSmall ? 12 : (isMedium ? 14 : 16);
        final double iconSize = isSmall ? 16 : (isMedium ? 18 : 20);
        final double buttonFont = isSmall ? 13 : 16;
        final double buttonPadding = isSmall ? 10 : 16;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            automaticallyImplyLeading: false,
            title: Text('Solicitud seleccionada', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: titleFont)),
            centerTitle: true,
          ),
          body: Column(
            children: [
              Padding(
                padding: EdgeInsets.all(isSmall ? 8 : 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: avatarRadius,
                      backgroundImage: solicitud.fotoCliente.isNotEmpty ? NetworkImage(solicitud.fotoCliente) : null,
                      backgroundColor: Colors.grey[200],
                    ),
                    SizedBox(width: isSmall ? 8 : 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            solicitud.nombreCliente,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: titleFont),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: isSmall ? 4 : 8),
                          Row(
                            children: [
                              Icon(Icons.location_on, color: Colors.red, size: iconSize),
                              SizedBox(width: 4),
                              Text('Recoger en:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: labelFont)),
                            ],
                          ),
                          Text(solicitud.direccion, style: TextStyle(fontSize: labelFont), maxLines: 2, overflow: TextOverflow.ellipsis),
                          SizedBox(height: isSmall ? 4 : 8),
                          Row(
                            children: [
                              Icon(Icons.attach_money, color: Colors.amber, size: iconSize),
                              SizedBox(width: 4),
                              Text('Pagará con:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: labelFont)),
                              SizedBox(width: 4),
                              Flexible(child: Text(solicitud.metodoPago, style: TextStyle(fontSize: labelFont), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Distancia', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: labelFont)),
                        Text(_formatDistancia(solicitud.distanciaMetros), style: TextStyle(fontWeight: FontWeight.bold, fontSize: labelFont)),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: isSmall ? 8 : 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black,
                          side: const BorderSide(color: Colors.amber, width: 1.5),
                          padding: EdgeInsets.symmetric(vertical: buttonPadding),
                          textStyle: TextStyle(fontSize: buttonFont),
                        ),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    SizedBox(width: isSmall ? 8 : 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.black,
                          padding: EdgeInsets.symmetric(vertical: buttonPadding),
                          textStyle: TextStyle(fontSize: buttonFont),
                        ),
                        child: const Text('Aceptar'),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: isSmall ? 8 : 16),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: isSmall ? 4 : 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: clientePos,
                        zoom: 15,
                      ),
                      markers: markers,
                      myLocationEnabled: true,
                      myLocationButtonEnabled: true,
                      zoomControlsEnabled: false,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDistancia(double metros) {
    if (metros >= 1000) {
      return '${(metros / 1000).toStringAsFixed(2)} km';
    } else {
      return '${metros.toStringAsFixed(0)} m';
    }
  }
}
