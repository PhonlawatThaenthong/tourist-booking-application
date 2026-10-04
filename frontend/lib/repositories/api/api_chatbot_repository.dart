import '../../models/chat_message.dart';
import '../chatbot_repository.dart';
import 'api_client.dart';

class ApiChatbotRepository implements ChatbotRepository {
  ApiChatbotRepository(this._api);

  final ApiClient _api;

  @override
  Future<ChatReply> ask({
    required String message,
    String? sessionId,
    String language = 'th',
  }) async {
    // auth: true sends the token when signed in and, on a 401, refreshes it
    // and retries once — the backend rejects an expired token rather than
    // quietly answering as an anonymous guest.
    final data = await _api.post('/api/chatbot/query', body: {
      'message': message,
      'sessionId': ?sessionId,
      'language': language,
    }) as Map<String, dynamic>;
    return ChatReply(
      sessionId: data['sessionId'] as String,
      answer: data['answer'] as String,
      answered: data['answered'] as bool,
    );
  }
}
