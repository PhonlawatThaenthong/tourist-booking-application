import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/booking.dart';
import '../../models/room.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/booking/booking_bloc.dart';
import '../../blocs/booking/booking_event.dart';
import '../../blocs/booking/booking_state.dart';
import '../../services/notification_service.dart';
import '../../utils/formatters.dart';
import 'booking_confirmation_screen.dart';

/// Simulated secure online payment. In production this screen would hand off to
/// a PCI-compliant gateway SDK (Stripe / Omise / 2C2P) — the card details never
/// touch our servers. Here we mock the charge and mark the booking paid.
class PaymentScreen extends StatefulWidget {
  final Room room;
  final DateTime checkIn;
  final DateTime checkOut;
  final int guests;
  final double total;

  const PaymentScreen({
    super.key,
    required this.room,
    required this.checkIn,
    required this.checkOut,
    required this.guests,
    required this.total,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  bool _processing = false;

  Future<void> _pay() async {
    setState(() => _processing = true);

    final user = context.read<AuthBloc>().state.currentUser!;

    // Simulate contacting the payment gateway.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;

    // Create + mark paid only after the (simulated) charge succeeds. The
    // BlocListener below reacts once the booking bloc emits it.
    context.read<BookingBloc>().add(BookingCreateAndPayRequested(
          roomId: widget.room.id,
          roomName: widget.room.name,
          customerId: user.id,
          customerName: user.name,
          checkIn: widget.checkIn,
          checkOut: widget.checkOut,
          guests: widget.guests,
          totalPrice: widget.total,
        ));
  }

  Future<void> _onBookingCreated(BuildContext context, Booking booking) async {
    final user = context.read<AuthBloc>().state.currentUser!;

    // Fire the automatic email/SMS confirmation.
    final message = await NotificationService.sendBookingConfirmation(
      booking: booking,
      email: user.email,
      phone: user.phone,
    );

    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => BookingConfirmationScreen(
        booking: booking,
        confirmationMessage: message,
        sentToEmail: user.email,
        sentToPhone: user.phone,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<BookingBloc, BookingState>(
      listener: (context, state) {
        final booking = state.lastCreatedBooking;
        if (booking != null) _onBookingCreated(context, booking);
      },
      child: Scaffold(
      appBar: AppBar(title: const Text('Secure payment')),
      body: AbsorbPointer(
        absorbing: _processing,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Amount due',
                        style: TextStyle(fontSize: 16)),
                    Text(Format.money(widget.total),
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00796B))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _qr(),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.lock, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Payments are encrypted and processed by a secure '
                    'gateway. (Demo — no real charge is made.)',
                    style: TextStyle(
                        color: Colors.grey.shade600, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: _processing ? null : _pay,
          icon: _processing
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.lock),
          label: Text(_processing
              ? 'Processing…'
              : 'Pay ${Format.money(widget.total)}'),
        ),
      ),
      ),
    );
  }

  Widget _qr() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.qr_code_2, size: 160),
            const SizedBox(height: 12),
            Text('Scan with your banking app to pay via PromptPay',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700)),
          ],
        ),
      ),
    );
  }
}
