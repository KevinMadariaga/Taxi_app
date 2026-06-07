import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/core/app_colores.dart';

import '../viewmodels/trip_tracking_viewmodel.dart';

class TripChatScreen extends StatefulWidget {
  const TripChatScreen({super.key});

  @override
  State<TripChatScreen> createState() => _TripChatScreenState();
}

class _TripChatScreenState extends State<TripChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) FocusScope.of(context).requestFocus(_focusNode);
      final vm = context.read<TripTrackingViewModel>();
      await vm.markChatAsRead();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final vm = context.read<TripTrackingViewModel>();
    _textController.clear();
    await vm.sendMessage(text);
    await vm.markChatAsRead();

    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent + 80,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TripTrackingViewModel>(
      builder: (context, vm, _) {
        final messages = vm.messages;

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
              title: const Text('Chat en tiempo real'),
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
                      final mine = msg.senderId == vm.currentUserId;

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
                            color: mine
                                ? AppColores.primary
                                : AppColores.grey200,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            msg.texto,
                            style: const TextStyle(
                              color: AppColores.textPrimary,
                            ),
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
      },
    );
  }
}
