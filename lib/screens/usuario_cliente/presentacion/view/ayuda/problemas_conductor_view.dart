import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

/// Formulario para reportar problemas con el conductor. Guarda el reporte en la
/// colección `reportes` de Firestore.
class ProblemasConductorView extends StatefulWidget {
  const ProblemasConductorView({
    super.key,
    required this.solicitudId,
    this.nombreConductor = '',
  });

  final String solicitudId;
  final String nombreConductor;

  @override
  State<ProblemasConductorView> createState() => _ProblemasConductorViewState();
}

class _ProblemasConductorViewState extends State<ProblemasConductorView> {
  static const List<String> _motivos = [
    'Conducción peligrosa',
    'No siguió la ruta',
    'Comportamiento inadecuado',
    'Vehículo en mal estado',
    'Cobro incorrecto',
    'Otro',
  ];

  final Set<String> _seleccionados = {};
  final TextEditingController _comentario = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _comentario.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_seleccionados.isEmpty || _enviando) return;
    setState(() => _enviando = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      await FirebaseFirestore.instance.collection('reportes').add({
        'tipo': 'problema_conductor',
        'solicitudId': widget.solicitudId,
        'clienteId': uid,
        'conductor': widget.nombreConductor,
        'motivos': _seleccionados.toList(),
        'comentario': _comentario.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      await _mostrarExito();
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo enviar el reporte: $e')),
      );
    }
  }

  Future<void> _mostrarExito() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColores.success.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: AppColores.success,
                  size: 40,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Reporte enviado',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColores.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Gracias por avisarnos. Revisaremos tu reporte.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColores.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColores.buttonPrimary,
                    foregroundColor: AppColores.textWhite,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Entendido',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColores.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColores.textPrimary,
        elevation: 0,
        title: const Text(
          'Problemas con el conductor',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          if (widget.nombreConductor.isNotEmpty) ...[
            Text(
              'Conductor: ${widget.nombreConductor}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColores.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
          ],
          const Text(
            '¿Qué problema tuviste?',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColores.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ..._motivos.map((m) {
            final sel = _seleccionados.contains(m);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  setState(() {
                    if (sel) {
                      _seleccionados.remove(m);
                    } else {
                      _seleccionados.add(m);
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: sel
                        ? AppColores.buttonPrimary.withValues(alpha: 0.08)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: sel
                          ? AppColores.buttonPrimary
                          : AppColores.borderSubtle,
                      width: sel ? 1.6 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        sel
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        color: sel
                            ? AppColores.buttonPrimary
                            : AppColores.grey400,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          m,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: sel
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: AppColores.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          const Text(
            'Comentario (opcional)',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColores.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _comentario,
            maxLines: 4,
            maxLength: 300,
            decoration: InputDecoration(
              hintText: 'Cuéntanos qué pasó...',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColores.borderSubtle),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColores.borderSubtle),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColores.buttonPrimary),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_seleccionados.isEmpty || _enviando) ? null : _enviar,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColores.error,
                foregroundColor: AppColores.textWhite,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _enviando
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColores.textWhite,
                      ),
                    )
                  : const Text(
                      'Enviar reporte',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
