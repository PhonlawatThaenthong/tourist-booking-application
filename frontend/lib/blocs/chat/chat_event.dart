abstract class ChatEvent {
  const ChatEvent();
}

class ChatMessageSent extends ChatEvent {
  final String text;
  const ChatMessageSent(this.text);
}

/// Re-sends the failed user message at [index].
class ChatRetried extends ChatEvent {
  final int index;
  const ChatRetried(this.index);
}

/// Starts a new conversation (new session id on the next message).
class ChatCleared extends ChatEvent {
  const ChatCleared();
}
