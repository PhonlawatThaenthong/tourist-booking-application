import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/chat_message.dart';
import '../../repositories/chatbot_repository.dart';
import '../../repositories/repository_exception.dart';
import 'chat_event.dart';
import 'chat_state.dart';

/// Lives as long as the customer shell, so closing and reopening the chat
/// keeps the conversation; signing out disposes it.
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc(this._repository) : super(const ChatState()) {
    on<ChatMessageSent>(_onSent);
    on<ChatRetried>(_onRetried);
    on<ChatCleared>((_, emit) => emit(const ChatState()));
  }

  final ChatbotRepository _repository;

  Future<void> _onSent(ChatMessageSent event, Emitter<ChatState> emit) async {
    final text = event.text.trim();
    if (text.isEmpty || state.sending) return;
    await _ask(text, [...state.messages, ChatMessage.user(text)], emit);
  }

  Future<void> _onRetried(ChatRetried event, Emitter<ChatState> emit) async {
    if (state.sending) return;
    // Moved to the end, so the answer lands right under its question.
    final failed = state.messages[event.index];
    final messages = [...state.messages]
      ..removeAt(event.index)
      ..add(ChatMessage.user(failed.text));
    await _ask(failed.text, messages, emit);
  }

  Future<void> _ask(
    String text,
    List<ChatMessage> messages,
    Emitter<ChatState> emit,
  ) async {
    emit(state.copyWith(messages: messages, sending: true));
    try {
      final reply = await _repository.ask(
        message: text,
        sessionId: state.sessionId,
        language: languageOf(text),
      );
      emit(
        state.copyWith(
          messages: [
            ...state.messages,
            ChatMessage.bot(reply.answer, answered: reply.answered),
          ],
          sessionId: reply.sessionId,
          sending: false,
        ),
      );
    } on RepositoryException catch (e) {
      // Mark the question itself as failed, so it can be retried in place.
      final marked = [...state.messages];
      final i = marked.lastIndexWhere((m) => m.fromUser && m.text == text);
      if (i >= 0) marked[i] = ChatMessage.user(text, failed: true);
      emit(
        state.copyWith(
          messages: marked,
          sending: false,
          errorMessage: e.message,
        ),
      );
    }
  }
}

/// `en` only when the message has no Thai letters at all — the resort's
/// customers write Thai by default.
String languageOf(String text) => RegExp(r'[฀-๿]').hasMatch(text) ? 'th' : 'en';
