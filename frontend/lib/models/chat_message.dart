/// One bubble in the chatbot conversation.
class ChatMessage {
  final String text;
  final bool fromUser;

  /// Bot replies only: false when the bot could not find an answer and fell
  /// back to "please contact the resort". Shown with a softer style.
  final bool answered;

  /// User messages only: the request failed, so the bubble offers a retry.
  final bool failed;

  const ChatMessage({
    required this.text,
    required this.fromUser,
    this.answered = true,
    this.failed = false,
  });

  const ChatMessage.user(String text, {bool failed = false})
      : this(text: text, fromUser: true, failed: failed);

  const ChatMessage.bot(String text, {bool answered = true})
      : this(text: text, fromUser: false, answered: answered);
}

/// What `POST /api/chatbot/query` returns.
class ChatReply {
  final String sessionId;
  final String answer;
  final bool answered;

  const ChatReply({
    required this.sessionId,
    required this.answer,
    required this.answered,
  });
}
