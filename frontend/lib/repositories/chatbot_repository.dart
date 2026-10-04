import '../models/chat_message.dart';

/// The resort's chatbot, proxied by the backend.
///
/// Backend endpoint: `POST /api/chatbot/query` — login optional. A signed-in
/// customer's token is forwarded so the bot can answer about their own
/// bookings; without it the bot only knows rooms, prices and policies.
abstract class ChatbotRepository {
  /// [sessionId] is null on the first message; pass back the one returned.
  /// [language] is `th` or `en`.
  Future<ChatReply> ask({
    required String message,
    String? sessionId,
    String language = 'th',
  });
}
