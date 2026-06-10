import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/services/soporte_chat_service.dart';

class SoporteChatDetalleAdminScreen extends StatefulWidget {
  const SoporteChatDetalleAdminScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  final String userId;
  final String userName;

  @override
  State<SoporteChatDetalleAdminScreen> createState() =>
      _SoporteChatDetalleAdminScreenState();
}

class _SoporteChatDetalleAdminScreenState
    extends State<SoporteChatDetalleAdminScreen> {
  final _service = SoporteChatService();
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();

  DateTime? _ultimoMensajeUsuario;
  Timer? _expiryTimer;

  static const _tiempoExpiracion = Duration(minutes: 6);

  bool get _usuarioInactivo {
    if (_ultimoMensajeUsuario == null) return false;
    return DateTime.now().difference(_ultimoMensajeUsuario!) >= _tiempoExpiracion;
  }

  @override
  void initState() {
    super.initState();
    _service.marcarLeidoPorAdmin(widget.userId);
    _expiryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;

    _textCtrl.clear();
    await _service.sendMensaje(
      userId: widget.userId,
      userName: widget.userName,
      userType: 'usuario',
      texto: text,
      esAdmin: true,
    );

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.userName),
        backgroundColor: AppColores.background,
        foregroundColor: AppColores.textPrimary,
        elevation: 0,
      ),
      backgroundColor: AppColores.background,
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _service.watchMensajes(widget.userId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];

                // Actualiza timestamp del último mensaje del usuario
                DateTime? ultimo;
                for (final d in docs.reversed) {
                  final data = d.data();
                  if (data['esAdmin'] as bool? ?? false) continue;
                  final ts = data['creadoEn'] as Timestamp?;
                  if (ts != null) {
                    ultimo = ts.toDate();
                    break;
                  }
                }
                if (ultimo != null && ultimo != _ultimoMensajeUsuario) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _ultimoMensajeUsuario = ultimo);
                  });
                }

                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'Sin mensajes aún.',
                      style: TextStyle(color: AppColores.textSecondary),
                    ),
                  );
                }

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollCtrl.hasClients) {
                    _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
                  }
                });

                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final esAdmin = data['esAdmin'] as bool? ?? false;
                    final texto = data['texto'] as String? ?? '';
                    final ts = data['creadoEn'] as Timestamp?;
                    final hora = ts != null
                        ? '${ts.toDate().hour.toString().padLeft(2, '0')}:${ts.toDate().minute.toString().padLeft(2, '0')}'
                        : '';

                    // desde el admin: sus propios mensajes se ven a la derecha
                    final align = esAdmin
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start;
                    final bg = esAdmin
                        ? AppColores.primary.withValues(alpha: 0.22)
                        : AppColores.grey200;

                    return Column(
                      crossAxisAlignment: align,
                      children: [
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          constraints: BoxConstraints(
                            maxWidth:
                                MediaQuery.of(context).size.width * 0.75,
                          ),
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: esAdmin
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              if (!esAdmin)
                                Text(
                                  widget.userName,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColores.textSecondary,
                                  ),
                                ),
                              Text(texto),
                              Text(
                                hora,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColores.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          if (_usuarioInactivo)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: AppColores.warning.withValues(alpha: 0.15),
              child: Row(
                children: [
                  const Icon(Icons.access_time,
                      size: 16, color: AppColores.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${widget.userName} no ha respondido en más de 6 minutos.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColores.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textCtrl,
                      focusNode: _focusNode,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Responder a ${widget.userName}...',
                        filled: true,
                        fillColor: AppColores.grey100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _send,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColores.buttonPrimary,
                      foregroundColor: AppColores.textPrimary,
                    ),
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
