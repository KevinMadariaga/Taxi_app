import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:taxi_app/services/chat_service.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/chat_message.dart';

class UniversalChatWidget extends StatefulWidget {
  final String solicitudId;
  final String? chatTitle;
  final Color? backgroundColor;
  final Color? myMessageColor;
  final Color? otherMessageColor;
  final Color? sendButtonColor;
  final bool autoFocus;

  const UniversalChatWidget({
    Key? key,
    required this.solicitudId,
    this.chatTitle,
    this.backgroundColor,
    this.myMessageColor,
    this.otherMessageColor,
    this.sendButtonColor,
    this.autoFocus = false,
  }) : super(key: key);

  @override
  State<UniversalChatWidget> createState() => _UniversalChatWidgetState();
}

class _UniversalChatWidgetState extends State<UniversalChatWidget> {
  final ChatService _chatService = ChatService();
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final FocusNode _chatFocusNode = FocusNode();
  bool _isSending = false;
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    if (widget.autoFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _chatFocusNode.requestFocus();
      });
    }
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_chatScrollController.hasClients) return;
    final target = _chatScrollController.position.maxScrollExtent + 24;
    if (!animated) {
      _chatScrollController.jumpTo(target);
      return;
    }
    _chatScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _chatController.dispose();
    _chatScrollController.dispose();
    _chatFocusNode.dispose();
    super.dispose();
  }

  Future<void> _sendChatMessage() async {
    if (_isSending) return;
    final texto = _chatController.text.trim();
    if (texto.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null || uid.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo enviar el mensaje')),
      );
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      await _chatService.sendMessage(
        solicitudId: widget.solicitudId,
        senderId: uid,
        texto: texto,
      );
      _chatController.clear();
      await Future.delayed(const Duration(milliseconds: 60));
      if (!mounted) return;
      _scrollToBottom();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _isSending = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: widget.backgroundColor ?? Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Center(
                    child: Text(
                      widget.chatTitle ?? 'Chat',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.black),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: StreamBuilder<List<ChatMessage>>(
                  stream: _chatService.listenMessages(widget.solicitudId),
                  initialData: const [],
                  builder: (context, snapshot) {
                    final mensajes = snapshot.data ?? const <ChatMessage>[];

                    final hasClients = _chatScrollController.hasClients;
                    final nearBottom = hasClients
                        ? (_chatScrollController.position.maxScrollExtent -
                                  _chatScrollController.position.pixels) <=
                              120
                        : true;
                    final hasNewMessages = mensajes.length != _lastMessageCount;

                    if (hasNewMessages) {
                      _lastMessageCount = mensajes.length;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        if (nearBottom || mensajes.isEmpty) {
                          _scrollToBottom();
                        }
                      });
                    }

                    if (mensajes.isEmpty) {
                      return const Center(
                        child: Text(
                          'Aún no hay mensajes.\nEscribe el primero.',
                          textAlign: TextAlign.center,
                        ),
                      );
                    }
                    return ListView.builder(
                      controller: _chatScrollController,
                      itemCount: mensajes.length,
                      itemBuilder: (context, index) {
                        final msg = mensajes[index];
                        final esMio = msg.senderId == uid;
                        return Container(
                          margin: EdgeInsets.only(
                            top: 10,
                            bottom: 10,
                            left: esMio ? 60 : 16,
                            right: esMio ? 16 : 60,
                          ),
                          child: Align(
                            alignment: esMio
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.68,
                                minWidth: 60,
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 18,
                              ),
                              decoration: BoxDecoration(
                                color: esMio
                                    ? (widget.myMessageColor ??
                                          Colors.yellow.shade700)
                                    : (widget.otherMessageColor ??
                                          Colors.white),
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.07),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: Text(
                                      msg.texto,
                                      style: TextStyle(
                                        color: esMio
                                            ? Colors.black
                                            : Colors.black,
                                        fontSize: 17,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    msg.timestamp != null
                                        ? _formatHora(msg.timestamp!)
                                        : '',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: widget.myMessageColor ?? Colors.yellow.shade700,
                        width: 1.2,
                      ),
                    ),
                    child: TextField(
                      controller: _chatController,
                      focusNode: _chatFocusNode,
                      autofocus: widget.autoFocus,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendChatMessage(),
                      decoration: const InputDecoration(
                        hintText: "Escribe un mensaje...",
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: widget.sendButtonColor ?? Colors.yellow.shade700,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: _isSending ? null : _sendChatMessage,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }

  String _formatHora(DateTime fechaHora) {
    return '${fechaHora.hour.toString().padLeft(2, '0')}:${fechaHora.minute.toString().padLeft(2, '0')}';
  }
}
