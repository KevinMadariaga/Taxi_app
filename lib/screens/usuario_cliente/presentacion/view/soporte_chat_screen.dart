import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/services/soporte_chat_service.dart';

class SoporteChatScreen extends StatefulWidget {
  const SoporteChatScreen({super.key, this.userType = 'cliente'});

  final String userType;

  @override
  State<SoporteChatScreen> createState() => _SoporteChatScreenState();
}

class _SoporteChatScreenState extends State<SoporteChatScreen> {
  final _service = SoporteChatService();
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();

  late final String _userId;
  late final String _userName;

  DateTime? _ultimoMensajeUsuario;
  Timer? _expiryTimer;

  static const _tiempoExpiracion = Duration(minutes: 6);

  bool get _expirado {
    if (_ultimoMensajeUsuario == null) return false;
    return DateTime.now().difference(_ultimoMensajeUsuario!) >= _tiempoExpiracion;
  }

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _userId = user?.uid ?? '';
    _userName = user?.displayName ?? user?.email ?? 'Usuario';

    // Revisa expiración cada 30 s para actualizar el banner sin esperar un evento Firestore.
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
    if (text.isEmpty || _userId.isEmpty) return;

    _textCtrl.clear();
    setState(() => _ultimoMensajeUsuario = DateTime.now());

    await _service.sendMensaje(
      userId: _userId,
      userName: _userName,
      userType: widget.userType,
      texto: text,
      esAdmin: false,
    );

    _scrollToBottom();
  }

  Future<void> _nuevaConversacion() async {
    await _service.resetearChat(_userId);
    if (mounted) setState(() => _ultimoMensajeUsuario = null);
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
    if (_userId.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Inicia sesión para usar el soporte.')),
      );
    }

    final expirado = _expirado;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat de soporte'),
        backgroundColor: AppColores.surface,
        foregroundColor: AppColores.textPrimary,
        elevation: 0,
      ),
      backgroundColor: AppColores.background,
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _service.watchMensajes(_userId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];

                // Actualiza _ultimoMensajeUsuario con el último msg del usuario
                // sin setState para no disparar rebuilds en loop.
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
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Bienvenido al soporte.\nEscríbenos y te atenderemos pronto.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColores.textSecondary),
                      ),
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

                    final align = esAdmin
                        ? CrossAxisAlignment.start
                        : CrossAxisAlignment.end;
                    final bg = esAdmin
                        ? AppColores.grey200
                        : AppColores.buttonPrimary.withValues(alpha: 0.22);

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
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: esAdmin
                                ? CrossAxisAlignment.start
                                : CrossAxisAlignment.end,
                            children: [
                              if (esAdmin)
                                const Text(
                                  'Soporte',
                                  style: TextStyle(
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

          // Banner de sesión expirada
          if (expirado)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: AppColores.grey200,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Sesión finalizada por inactividad.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColores.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColores.buttonPrimary,
                        foregroundColor: AppColores.textPrimary,
                        minimumSize: const Size.fromHeight(42),
                      ),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Nuevo chat'),
                      onPressed: _nuevaConversacion,
                    ),
                  ),
                ],
              ),
            ),

          // Input — solo visible cuando la sesión NO está expirada
          if (!expirado)
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
                          hintText: 'Escribe tu mensaje...',
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
