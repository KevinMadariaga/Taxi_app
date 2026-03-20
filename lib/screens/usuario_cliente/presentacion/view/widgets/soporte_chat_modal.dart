import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

class SoporteChatModal extends StatefulWidget {
  const SoporteChatModal({
    super.key,
    this.title = 'Chat de soporte',
    this.welcomeMessage =
        'Hola, soy el equipo de soporte. Cuentanos como podemos ayudarte.',
  });

  final String title;
  final String welcomeMessage;

  @override
  State<SoporteChatModal> createState() => _SoporteChatModalState();
}

class _SoporteChatModalState extends State<SoporteChatModal> {
  final TextEditingController _messageCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  late final List<_ChatMessage> _messages;

  @override
  void initState() {
    super.initState();
    _messages = [
      _ChatMessage(
        text: widget.welcomeMessage,
        isAgent: true,
        createdAt: DateTime.now(),
      ),
    ];
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _messageCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(
        _ChatMessage(text: text, isAgent: false, createdAt: DateTime.now()),
      );
      _messageCtrl.clear();
    });
    _scrollToBottom();

    Timer(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      setState(() {
        _messages.add(
          _ChatMessage(
            text:
                'Gracias por escribir. Recibimos tu mensaje y en breve te atendemos.',
            isAgent: true,
            createdAt: DateTime.now(),
          ),
        );
      });
      _scrollToBottom();
    });
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
    final media = MediaQuery.of(context);
    final bottomInset = media.viewInsets.bottom;
    final safeBottom = media.padding.bottom;
    final bottomReserved = bottomInset + safeBottom;
    final topInset = media.padding.top;
    final desiredHeight = media.size.height * 0.72;
    final maxHeight = media.size.height - topInset - 12;
    final availableWithKeyboard = math.max(240.0, maxHeight - bottomReserved);
    final sheetHeight = math.min(desiredHeight, availableWithKeyboard);

    return SafeArea(
      top: true,
      bottom: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.only(bottom: bottomReserved),
        child: SizedBox(
          height: sheetHeight,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColores.grey300,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.support_agent),
                title: Text(
                  widget.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: _scrollCtrl,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final m = _messages[index];
                    final align = m.isAgent
                        ? CrossAxisAlignment.start
                        : CrossAxisAlignment.end;
                    final bg = m.isAgent
                        ? AppColores.grey200
                        : AppColores.buttonPrimary.withValues(alpha: 0.25);
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
                          child: Text(m.text),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageCtrl,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: const InputDecoration(
                          hintText: 'Escribe tu mensaje',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _sendMessage,
                      icon: const Icon(Icons.send),
                      label: const Text('Enviar'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage({
    required this.text,
    required this.isAgent,
    required this.createdAt,
  });

  final String text;
  final bool isAgent;
  final DateTime createdAt;
}
