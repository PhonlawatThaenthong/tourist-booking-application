import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/chat/chat_bloc.dart';
import '../../blocs/chat/chat_event.dart';
import '../../blocs/chat/chat_state.dart';
import '../../models/chat_message.dart';
import '../../theme.dart';

/// Conversation with the resort chatbot. Expects a [ChatBloc] above it —
/// [CustomerHome] provides one so the conversation survives closing this page.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  /// Must match `@MaxLength(1000)` on the backend's ChatbotQueryDto.
  static const maxMessageLength = 1000;

  static const suggestions = [
    'พรุ่งนี้มีห้องว่างไหม ราคาเท่าไหร่',
    'การจองของฉันเป็นยังไงบ้าง',
    'ชำระเงินยังไง',
    'เช็คอินเช็คเอาท์กี่โมง',
  ];

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send(String text) {
    if (text.trim().isEmpty) return;
    context.read<ChatBloc>().add(ChatMessageSent(text));
    _controller.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resort assistant'),
        actions: [
          BlocBuilder<ChatBloc, ChatState>(
            buildWhen: (a, b) =>
                a.messages.isEmpty != b.messages.isEmpty || a.sending != b.sending,
            builder: (context, state) => IconButton(
              tooltip: 'New conversation',
              icon: const Icon(Icons.refresh),
              onPressed: state.messages.isEmpty || state.sending
                  ? null
                  : () => context.read<ChatBloc>().add(const ChatCleared()),
            ),
          ),
        ],
      ),
      body: BlocConsumer<ChatBloc, ChatState>(
        listenWhen: (_, current) => current.errorMessage != null,
        listener: (context, state) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(state.errorMessage!)));
        },
        builder: (context, state) {
          return Column(
            children: [
              Expanded(
                child: state.messages.isEmpty
                    ? _EmptyState(onPick: state.sending ? null : _send)
                    : _MessageList(state: state),
              ),
              _InputBar(
                controller: _controller,
                focusNode: _focus,
                enabled: !state.sending,
                onSend: _send,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({required this.state});

  final ChatState state;

  @override
  Widget build(BuildContext context) {
    final messages = state.messages;
    final count = messages.length + (state.sending ? 1 : 0);

    // Reversed, so the newest message sits at the bottom and the list follows
    // it without any scroll bookkeeping.
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      itemCount: count,
      itemBuilder: (context, i) {
        if (state.sending && i == 0) return const _TypingBubble();
        final index = messages.length - 1 - (i - (state.sending ? 1 : 0));
        final message = messages[index];
        return _Bubble(
          message: message,
          onRetry: message.failed && !state.sending
              ? () => context.read<ChatBloc>().add(ChatRetried(index))
              : null,
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, this.onRetry});

  final ChatMessage message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final mine = message.fromUser;
    final Color background;
    final Color foreground;
    if (mine) {
      background = message.failed ? Colors.red.shade50 : AppTheme.primary;
      foreground = message.failed ? Colors.red.shade900 : Colors.white;
    } else {
      background = message.answered ? Colors.white : Colors.amber.shade50;
      foreground = Colors.black87;
    }

    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.78,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(mine ? 16 : 4),
          bottomRight: Radius.circular(mine ? 4 : 16),
        ),
        border: mine ? null : Border.all(color: Colors.grey.shade200),
      ),
      child: SelectableText(
        message.text,
        style: TextStyle(color: foreground, fontSize: 15, height: 1.4),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                mine ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!mine) ...[const _BotAvatar(), const SizedBox(width: 8)],
              Flexible(child: bubble),
            ],
          ),
          if (onRetry != null)
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('ส่งไม่สำเร็จ แตะเพื่อลองใหม่'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red.shade700,
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}

class _BotAvatar extends StatelessWidget {
  const _BotAvatar();

  @override
  Widget build(BuildContext context) {
    return const CircleAvatar(
      radius: 15,
      backgroundColor: AppTheme.primary,
      child: Icon(Icons.support_agent, size: 18, color: Colors.white),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const _BotAvatar(),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  'กำลังพิมพ์…',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onPick});

  final ValueChanged<String>? onPick;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 24),
        const CircleAvatar(
          radius: 32,
          backgroundColor: AppTheme.primary,
          child: Icon(Icons.support_agent, size: 34, color: Colors.white),
        ),
        const SizedBox(height: 16),
        const Text(
          'สวัสดีค่ะ มีอะไรให้ช่วยไหมคะ',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'ถามเรื่องห้องว่าง ราคา การจองของคุณ การชำระเงิน หรือสิ่งอำนวยความสะดวกได้เลย',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in ChatScreen.suggestions)
              ActionChip(
                label: Text(s),
                onPressed: onPick == null ? null : () => onPick!(s),
              ),
          ],
        ),
      ],
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 6,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: ChatScreen.maxMessageLength,
                  textInputAction: TextInputAction.send,
                  onSubmitted: enabled ? onSend : null,
                  decoration: const InputDecoration(
                    hintText: 'พิมพ์คำถาม…',
                    counterText: '',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => IconButton.filled(
                  tooltip: 'Send',
                  icon: const Icon(Icons.send),
                  onPressed: enabled && value.text.trim().isNotEmpty
                      ? () => onSend(controller.text)
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
