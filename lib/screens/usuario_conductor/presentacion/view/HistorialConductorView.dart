import 'package:flutter/material.dart';

class HistorialConductorView extends StatelessWidget {
  const HistorialConductorView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: AppBar(
          backgroundColor: Colors.yellow[700],
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false, // Sin flecha de volver
          title: const Text(
            'Historial de Viajes',
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 22,
            ),
          ),
        ),
      ),
      body: const Center(
        child: Text(
          'No hay viajes registrados.',
          style: TextStyle(color: Colors.black54, fontSize: 18),
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 16, right: 8),
        child: SizedBox(
          width: 180,
          height: 56,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.yellow[700],
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              elevation: 2,
            ),
            onPressed: () {},
            icon: const Icon(Icons.bar_chart, color: Colors.white),
            label: const Text(
              'Ver detalle',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}
