import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Adds [event] to [bloc] and completes once the bloc has answered it, so a
/// [RefreshIndicator] keeps spinning until the new data is actually on screen
/// instead of vanishing the instant the request is sent.
///
/// [until] picks the state that counts as "answered" for blocs that emit
/// more than once per load (e.g. a `loading: true` state first). Without it
/// the next emission, data or error, ends the wait. Never throws: a request
/// that hangs is cut off after [timeout] and the bloc reports its own errors.
Future<void> reloadBloc<E, S>(
  Bloc<E, S> bloc,
  E event, {
  bool Function(S state)? until,
  Duration timeout = const Duration(seconds: 15),
}) async {
  // Subscribe before adding, so a fast answer cannot slip past unseen.
  final answered = until == null
      ? bloc.stream.first
      : bloc.stream.firstWhere(until);
  bloc.add(event);
  try {
    await answered.timeout(timeout);
  } on TimeoutException {
    // Leave the spinner; the bloc surfaces failures through its state.
  } on StateError {
    // Bloc closed mid-refresh (e.g. signed out).
  }
}

/// Pull-to-refresh for a body that does not scroll on its own, such as a
/// fixed-height calendar grid or an empty/error message. The child keeps
/// exactly the viewport's size; the scroll view around it only exists so
/// the overscroll gesture has something to pull.
class RefreshableBody extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final Widget child;

  const RefreshableBody({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: child,
          ),
        ),
      ),
    );
  }
}
