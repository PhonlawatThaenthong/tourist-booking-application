import '../../models/chat_message.dart';

class ChatState {
  final List<ChatMessage> messages;

  /// Issued by the backend on the first reply; null until then.
  final String? sessionId;

  /// A question is in flight — the input is locked and a typing bubble shows.
  final bool sending;

  /// Transient: set on the failing transition only, never carried forward.
  final String? errorMessage;

  const ChatState({
    this.messages = const [],
    this.sessionId,
    this.sending = false,
    this.errorMessage,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    String? sessionId,
    bool? sending,
    String? errorMessage,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      sessionId: sessionId ?? this.sessionId,
      sending: sending ?? this.sending,
      errorMessage: errorMessage,
    );
  }
}
