import 'package:flutter/material.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/services/fcm_service.dart';

import '../controladores/chat_controller.dart';

/// Chat del viaje, compartida por cliente y conductor — reemplaza
/// `TripChatScreen` (cliente) y `DriverChatScreen` (conductor), que eran
/// estructuralmente idénticas salvo por a qué controlador leían.
///
/// **Pasar siempre el [controller] del ViewModel del viaje.** Los dos
/// ViewModels (`ViajeConductorViewModel`, `ViajeClienteViewModel`) ya crean y
/// bindean un `ChatController` para el mismo viaje. Cuando esta pantalla
/// creaba el suyo propio quedaban DOS listeners sobre la misma subcolección
/// `mensajes` y cada mensaje entrante disparaba la notificación local dos
/// veces (visto en dispositivo real: notificación duplicada por mensaje).
///
/// El [controller] recibido NO se dispone acá: pertenece al ViewModel, que lo
/// dispone junto con la pantalla de viaje.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.viajeId,
    required this.currentUserId,
    required this.otherPartyLabel,
    this.controller,
    this.title = 'Chat en tiempo real',
  });

  final String viajeId;
  final String currentUserId;
  final String otherPartyLabel;

  /// Controlador ya bindeado del ViewModel del viaje. Si es `null` la pantalla
  /// crea (y dispone) uno propio — solo para usos sueltos, fuera del flujo de
  /// viaje.
  final ChatController? controller;
  final String title;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatController _controller;

  /// Solo cuando esta pantalla creó el controller es responsable de disponerlo.
  late final bool _ownsController;

  VoidCallback? _previousOnChanged;

  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final externo = widget.controller;
    _ownsController = externo == null;
    _controller =
        externo ??
        ChatController(
          viajeId: widget.viajeId,
          currentUserId: widget.currentUserId,
          otherPartyLabel: widget.otherPartyLabel,
        );

    // El ViewModel también escucha `onChanged`; se encadena en vez de pisarlo
    // para que su UI (badge de no leídos) siga actualizándose con el chat
    // abierto, y se restaura al salir.
    _previousOnChanged = _controller.onChanged;
    _controller.onChanged = () {
      _previousOnChanged?.call();
      if (mounted) setState(() {});
    };

    if (_ownsController) _controller.bind();

    // Con el chat en pantalla el usuario ya está viendo los mensajes: no tiene
    // sentido notificarle de lo que está leyendo. Se silencian las dos vías —
    // el aviso del listener y el del handler de FCM en primer plano.
    _controller.notificacionesSilenciadas = true;
    FcmService.instance.registrarChatAbierto(widget.viajeId);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) FocusScope.of(context).requestFocus(_focusNode);
      await _controller.markAllAsRead();
    });
  }

  @override
  void dispose() {
    _controller.notificacionesSilenciadas = false;
    FcmService.instance.limpiarChatAbierto(widget.viajeId);
    _controller.onChanged = _previousOnChanged;
    if (_ownsController) _controller.dispose();
    _focusNode.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();
    await _controller.sendMessage(text);
    await _controller.markAllAsRead();

    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent + 80,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = _controller.messages;

    return PopScope(
      // Cierra el teclado ANTES de salir para no romper la vista al volver.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        FocusScope.of(context).unfocus();
        await Future<void>.delayed(const Duration(milliseconds: 120));
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          centerTitle: true,
          backgroundColor: AppColores.background,
          foregroundColor: AppColores.textPrimary,
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final msg = messages[index];
                  final mine = msg.senderId == widget.currentUserId;
                  // Leído por la otra persona: cualquier entrada en `readBy`
                  // que no sea la del propio remitente y esté en `true`.
                  final leido =
                      mine &&
                      msg.readBy.entries.any(
                        (e) => e.key != msg.senderId && e.value == true,
                      );

                  return Align(
                    alignment: mine
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: mine ? AppColores.primary : AppColores.grey200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            msg.texto,
                            style: const TextStyle(
                              color: AppColores.textPrimary,
                            ),
                          ),
                          if (mine) ...[
                            const SizedBox(height: 3),
                            Icon(
                              leido ? Icons.done_all : Icons.done,
                              size: 15,
                              color: leido
                                  ? AppColores.secondary
                                  : AppColores.textSecondary,
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
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
                        controller: _textController,
                        focusNode: _focusNode,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: 'Escribe un mensaje...',
                          hintStyle: const TextStyle(
                            color: AppColores.textSecondary,
                          ),
                          filled: true,
                          fillColor: AppColores.grey100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _send,
                      style: IconButton.styleFrom(
                        backgroundColor: AppColores.buttonPrimary,
                        foregroundColor: AppColores.textWhite,
                      ),
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
