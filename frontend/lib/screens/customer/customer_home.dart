import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/chat/chat_bloc.dart';
import '../../repositories/chatbot_repository.dart';
import 'chat_screen.dart';
import 'my_bookings_screen.dart';
import 'restaurants_screen.dart';
import 'room_search_screen.dart';
import 'profile_screen.dart';

/// Customer shell with bottom navigation across the four main areas, plus a
/// chat button that opens the resort chatbot from any of them.
class CustomerHome extends StatefulWidget {
  const CustomerHome({super.key});

  @override
  State<CustomerHome> createState() => _CustomerHomeState();
}

class _CustomerHomeState extends State<CustomerHome> {
  int _index = 0;

  final _pages = const [
    RoomSearchScreen(),
    MyBookingsScreen(),
    RestaurantsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // Scoped to this shell: the conversation survives closing the chat page,
    // and signing out (which replaces this widget) discards it.
    return BlocProvider(
      create: (ctx) => ChatBloc(ctx.read<ChatbotRepository>()),
      child: Builder(
        builder: (ctx) => Scaffold(
          body: IndexedStack(index: _index, children: _pages),
          floatingActionButton: FloatingActionButton(
            tooltip: 'Chat with us',
            onPressed: () => Navigator.of(ctx).push(
              MaterialPageRoute(
                builder: (_) => BlocProvider.value(
                  value: ctx.read<ChatBloc>(),
                  child: const ChatScreen(),
                ),
              ),
            ),
            child: const Icon(Icons.chat_bubble_outline),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.search), label: 'Search'),
              NavigationDestination(
                  icon: Icon(Icons.event_note_outlined),
                  selectedIcon: Icon(Icons.event_note),
                  label: 'Bookings'),
              NavigationDestination(
                  icon: Icon(Icons.restaurant_outlined),
                  selectedIcon: Icon(Icons.restaurant),
                  label: 'Dining'),
              NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Profile'),
            ],
          ),
        ),
      ),
    );
  }
}
