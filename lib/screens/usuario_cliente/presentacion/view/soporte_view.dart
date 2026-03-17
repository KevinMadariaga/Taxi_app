import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/widgets/soporte_chat_modal.dart';

class SoporteView extends StatefulWidget {
  const SoporteView({super.key});

  @override
  State<SoporteView> createState() => _SoporteViewState();
}

class _SoporteViewState extends State<SoporteView> {
  bool _isSendingTicket = false;

  Future<void> _openChat() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const SoporteChatModal(),
    );
  }

  Future<void> _sendTicket() async {
    final asuntoCtrl = TextEditingController();
    final detalleCtrl = TextEditingController();

    final payload = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Crear ticket de soporte'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: asuntoCtrl,
                decoration: const InputDecoration(labelText: 'Asunto'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: detalleCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Detalle',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final asunto = asuntoCtrl.text.trim();
              final detalle = detalleCtrl.text.trim();
              if (asunto.isEmpty || detalle.isEmpty) return;
              Navigator.of(ctx).pop({'asunto': asunto, 'detalle': detalle});
            },
            child: const Text('Enviar'),
          ),
        ],
      ),
    );

    if (!mounted || payload == null) return;

    setState(() => _isSendingTicket = true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _isSendingTicket = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ticket enviado correctamente.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Soporte'),
        backgroundColor: AppColores.surface,
        foregroundColor: AppColores.textPrimary,
        elevation: 0,
      ),
      backgroundColor: AppColores.background,
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.chat_bubble_outline),
            title: const Text('Chat en vivo'),
            subtitle: const Text('Habla con un agente de soporte.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openChat,
          ),
          ListTile(
            leading: _isSendingTicket
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.assignment_outlined),
            title: const Text('Crear ticket'),
            subtitle: Text(
              _isSendingTicket
                  ? 'Enviando solicitud...'
                  : 'Reporta un problema con detalle.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _isSendingTicket ? null : _sendTicket,
          ),
        ],
      ),
    );
  }
}
