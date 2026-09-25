import 'package:flutter/material.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/core/services/fcm_service.dart';
import 'package:taxi_app/widgets/ajustes_ui.dart';

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
        backgroundColor: context.palette.background,
        appBar: appBarNeutra(context, titulo: widget.title),
        body: Column(
          children: [
            Expanded(
              child: messages.isEmpty
                  ? _ChatVacio(otherPartyLabel: widget.otherPartyLabel)
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        final mine = msg.senderId == widget.currentUserId;
                        // Leído por la otra persona: cualquier entrada en
                        // `readBy` que no sea la del propio remitente y esté
                        // en `true`.
                        final leido =
                            mine &&
                            msg.readBy.entries.any(
                              (e) => e.key != msg.senderId && e.value == true,
                            );
                        return _Burbuja(
                          texto: msg.texto,
                          hora: msg.timestamp,
                          mine: mine,
                          leido: leido,
                        );
                      },
                    ),
            ),
            Container(
              decoration: BoxDecoration(
                color: context.palette.surface,
                border: Border(
                  top: BorderSide(color: context.palette.borderSubtle),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          focusNode: _focusNode,
                          textInputAction: TextInputAction.send,
                          textCapitalization: TextCapitalization.sentences,
                          onSubmitted: (_) => _send(),
                          style: TextStyle(color: context.palette.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'Escribe un mensaje...',
                            hintStyle: TextStyle(
                              color: context.palette.textSecondary,
                            ),
                            filled: true,
                            fillColor: context.palette.grey100,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: const BorderSide(
                                color: AppColores.primary,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Enviar',
                        onPressed: _send,
                        style: IconButton.styleFrom(
                          backgroundColor: AppColores.buttonPrimary,
                          foregroundColor: colorContenidoSobre(
                            AppColores.buttonPrimary,
                          ),
                        ),
                        icon: const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Burbuja de mensaje. La propia va sobre el ámbar de marca, así que su texto
/// y sus íconos son oscuros fijos (`colorContenidoSobre`): con
/// `palette.textPrimary`, en modo oscuro el texto casi blanco quedaba en
/// 1.65:1 sobre el ámbar. La ajena usa la paleta del tema.
class _Burbuja extends StatelessWidget {
  const _Burbuja({
    required this.texto,
    required this.hora,
    required this.mine,
    required this.leido,
  });

  final String texto;
  final DateTime? hora;
  final bool mine;
  final bool leido;

  /// Azul de "leído" oscurecido para que se distinga sobre el ámbar (4.4:1;
  /// el azul de marca queda en 3.1:1).
  static const _azulLeido = Color(0xFF0B4F9C);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fondo = mine ? AppColores.primary : palette.grey200;
    final colorTexto = mine
        ? colorContenidoSobre(AppColores.primary)
        : palette.textPrimary;
    final colorMeta = mine ? AppColores.ink700 : palette.textSecondary;
    final hora = this.hora;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 6),
          decoration: BoxDecoration(
            color: fondo,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(texto, style: TextStyle(color: colorTexto, fontSize: 15)),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hora != null)
                    Text(
                      '${hora.hour.toString().padLeft(2, '0')}:'
                      '${hora.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(color: colorMeta, fontSize: 11),
                    ),
                  if (mine) ...[
                    const SizedBox(width: 4),
                    Icon(
                      leido ? Icons.done_all : Icons.done,
                      size: 15,
                      color: leido ? _azulLeido : colorMeta,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatVacio extends StatelessWidget {
  const _ChatVacio({required this.otherPartyLabel});

  final String otherPartyLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 40,
              color: palette.textSecondary,
            ),
            const SizedBox(height: 10),
            Text(
              'Aún no hay mensajes.\nEscríbele al $otherPartyLabel.',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textSecondary, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
