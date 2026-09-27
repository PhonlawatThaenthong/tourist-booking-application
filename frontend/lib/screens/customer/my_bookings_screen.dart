import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/booking.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/booking/booking_bloc.dart';
import '../../blocs/booking/booking_event.dart';
import '../../blocs/booking/booking_state.dart';
import '../../utils/formatters.dart';
import 'payment_screen.dart';

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  /// The booking whose cancel is in flight. The listener below only reacts
  /// while this is set: the screen lives in the home IndexedStack and stays
  /// mounted on every tab, so an unconditional listener would also pop up
  /// errors that belong to other screens (e.g. a 409 on the payment page).
  String? _cancellingId;

  @override
  void initState() {
    super.initState();
    // Re-fetch on open so an auto-cancelled hold no longer shows as Pending.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<BookingBloc>().add(const BookingStarted());
    });
  }

  Future<void> _refresh() async =>
      context.read<BookingBloc>().add(const BookingStarted());

  Future<void> _cancel(Booking booking) async {
    final refundNote = booking.paymentStatus == PaymentStatus.paid
        ? 'The ${Format.money(booking.totalPrice)} you paid will be refunded.'
        : 'This cannot be undone.';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel booking?'),
        content: Text(
          'Cancel your stay in ${booking.roomName} on '
          '${Format.date(booking.checkIn)}? $refundNote',
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Keep booking'),
              ),
              const SizedBox(height: 8),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red,
                  textStyle: const TextStyle(fontSize: 13),
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Yes, cancel'),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _cancellingId = booking.id);
    context.read<BookingBloc>().add(BookingCustomerCancelRequested(booking.id));
  }

  void _onBookingState(BuildContext context, BookingState state) {
    final id = _cancellingId!;
    final error = state.errorMessage;
    final cancelled = state.bookings
        .any((b) => b.id == id && b.status == BookingStatus.cancelled);
    // Some other emission (e.g. a pull-to-refresh) landed first; keep waiting.
    if (error == null && !cancelled) return;
    setState(() => _cancellingId = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? 'Booking cancelled')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final bookings = context.watch<BookingBloc>().forCustomer(
      auth.currentUser!.id,
    );

    return BlocListener<BookingBloc, BookingState>(
      listenWhen: (_, _) => _cancellingId != null,
      listener: _onBookingState,
      child: Scaffold(
        appBar: AppBar(title: const Text('My bookings')),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: bookings.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 100),
                    Icon(Icons.luggage_outlined,
                        size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    const Center(child: Text('No bookings yet')),
                    Center(
                      child: Text('Find a room to get started',
                          style: TextStyle(color: Colors.grey.shade600)),
                    ),
                  ],
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: bookings.length,
                  itemBuilder: (_, i) => _BookingTile(
                    booking: bookings[i],
                    cancelling: _cancellingId == bookings[i].id,
                    onCancel: () => _cancel(bookings[i]),
                  ),
                ),
        ),
      ),
    );
  }
}

class _BookingTile extends StatelessWidget {
  final Booking booking;
  final bool cancelling;
  final VoidCallback onCancel;
  const _BookingTile({
    required this.booking,
    required this.cancelling,
    required this.onCancel,
  });

  Color _statusColor() {
    switch (booking.status) {
      case BookingStatus.approved:
        return Colors.green;
      case BookingStatus.pending:
        return Colors.orange;
      case BookingStatus.cancelled:
        return Colors.red;
      case BookingStatus.checkedIn:
        return Colors.blue;
      case BookingStatus.checkedOut:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    booking.roomName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor().withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    booking.status.label,
                    style: TextStyle(
                      color: _statusColor(),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _line(Icons.login, 'Check-in: ${Format.checkIn(booking.checkIn)}'),
            _line(
              Icons.logout,
              'Check-out: ${Format.checkOut(booking.checkOut)}',
            ),
            _line(
              Icons.nights_stay,
              '${booking.nights} nights · '
              '${booking.guests} guests',
            ),
            _line(Icons.confirmation_number_outlined, 'Ref: ${booking.id}'),
            const Divider(),
            Row(
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(booking.paymentStatus.label),
                  avatar: Icon(
                    booking.paymentStatus == PaymentStatus.paid
                        ? Icons.check_circle
                        : Icons.pending,
                    size: 16,
                  ),
                ),
                const Spacer(),
                Text(
                  Format.money(booking.totalPrice),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF00796B),
                  ),
                ),
              ],
            ),
            // A checked-out stay is closed; any balance is settled at the
            // desk rather than reopened from here.
            if (booking.paymentStatus == PaymentStatus.unpaid &&
                booking.status != BookingStatus.cancelled &&
                booking.status != BookingStatus.checkedOut) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PaymentScreen(existingBooking: booking),
                    ),
                  ),
                  icon: const Icon(Icons.qr_code_2, size: 18),
                  label: const Text('Pay / upload slip'),
                ),
              ),
            ],
            if (booking.customerCanCancel) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  // Disabled while in flight so a double tap cannot fire a
                  // second request, which the server would reject with 409.
                  onPressed: cancelling ? null : onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                  icon: cancelling
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cancel_outlined, size: 18),
                  label: const Text('Cancel booking'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _line(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
