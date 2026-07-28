import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/services/reportes_service.dart';

class ReportarProblemaScreen extends StatefulWidget {
  const ReportarProblemaScreen({super.key, required this.solicitudId});

  final String solicitudId;

  @override
  State<ReportarProblemaScreen> createState() => _ReportarProblemaScreenState();
}

const _tiposProblema = [
  'Cliente no llegó al punto',
  'Problema con el pago',
  'Comportamiento inapropiado del cliente',
  'Ruta incorrecta',
  'Accidente o incidente',
  'Otro',
];

class _ReportarProblemaScreenState extends State<ReportarProblemaScreen> {
  String? _tipoSeleccionado;
  final _descController = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  bool get _puedeEnviar =>
      _tipoSeleccionado != null && !_enviando;

  Future<void> _enviar() async {
    if (!_puedeEnviar) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _enviando = true);
    try {
      await ReportesService.instance.enviarReporteDeConductor(
        solicitudId: widget.solicitudId,
        conductorId: uid,
        tipo: _tipoSeleccionado!,
        descripcion: _descController.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reporte enviado. Gracias por informarnos.'),
          backgroundColor: AppColores.success,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al enviar el reporte: $e'),
          backgroundColor: AppColores.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColores.background,
      appBar: AppBar(
        title: const Text('Reportar problema'),
        backgroundColor: AppColores.background,
        foregroundColor: AppColores.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Ícono
              Center(
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: AppColores.warning.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.report_problem_rounded,
                    color: AppColores.warning,
                    size: 34,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Tipo de problema',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _tiposProblema.map((tipo) {
                  final sel = _tipoSeleccionado == tipo;
                  return ChoiceChip(
                    label: Text(tipo),
                    selected: sel,
                    onSelected: _enviando
                        ? null
                        : (_) => setState(() => _tipoSeleccionado = tipo),
                    selectedColor: AppColores.primary,
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: sel ? AppColores.textPrimary : AppColores.textSecondary,
                    ),
                    backgroundColor: AppColores.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: sel ? AppColores.primary : AppColores.grey300,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              const Text(
                'Descripción (opcional)',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _descController,
                enabled: !_enviando,
                maxLines: 4,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Describe brevemente lo ocurrido...',
                  filled: true,
                  fillColor: AppColores.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColores.grey300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColores.grey300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColores.primary, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _puedeEnviar ? _enviar : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColores.primary,
                    disabledBackgroundColor: AppColores.grey300,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _enviando
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColores.textPrimary,
                          ),
                        )
                      : const Text(
                          'Enviar reporte',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColores.textPrimary,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
