import 'package:flutter/material.dart';

import 'package:taxi_app/core/app_colores.dart';

import '../controladores/chat_controller.dart';

/// Chat del viaje, compartida por cliente y conductor — reemplaza
/// `TripChatScreen` (cliente) y `DriverChatScreen` (conductor), que eran
/// estructuralmente idénticas salvo por a qué controlador leían.
///
/// Dueña de su propio [ChatController] (no depende de un ViewModel ancestro
/// vía `Provider`): se puede abrir desde cualquiera de las dos pantallas de
/// viaje pasando solo los identificadores.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.viajeId,
    required this.currentUserId,
    required this.otherPartyLabel,
    this.title = 'Chat en tiempo real',
  });

  final String viajeId;
  final String currentUserId;
  final String otherPartyLabel;
  final String title;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatController _controller;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller =
        ChatController(
            viajeId: widget.viajeId,
            currentUserId: widget.currentUserId,
            otherPartyLabel: widget.otherPartyLabel,
          )
          ..onChanged = () {
            if (mounted) setState(() {});
          };
    _controller.bind();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) FocusScope.of(context).requestFocus(_focusNode);
      await _controller.markAllAsRead();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
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
