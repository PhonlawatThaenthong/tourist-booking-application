import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/room.dart';
import '../../blocs/auth_cubit.dart';
import '../../blocs/booking_cubit.dart';
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
  final _formKey = GlobalKey<FormState>();
  final _cardCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _expiryCtrl = TextEditingController();
  final _cvvCtrl = TextEditingController();
  _PayMethod _method = _PayMethod.card;
  bool _processing = false;

  @override
  void dispose() {
    _cardCtrl.dispose();
    _nameCtrl.dispose();
    _expiryCtrl.dispose();
    _cvvCtrl.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    if (_method == _PayMethod.card && !_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _processing = true);

    final auth = context.read<AuthCubit>();
    final bookings = context.read<BookingCubit>();
    final user = auth.currentUser!;

    // Simulate contacting the payment gateway.
    await Future<void>.delayed(const Duration(milliseconds: 1500));

    // Create + mark paid only after the (simulated) charge succeeds.
    final booking = bookings.createBooking(
      roomId: widget.room.id,
      roomName: widget.room.name,
      customerId: user.id,
      customerName: user.name,
      checkIn: widget.checkIn,
      checkOut: widget.checkOut,
      guests: widget.guests,
      totalPrice: widget.total,
    );
    bookings.markPaid(booking.id);

    // Fire the automatic email/SMS confirmation.
    final message = await NotificationService.sendBookingConfirmation(
      booking: booking,
      email: user.email,
      phone: user.phone,
    );

    if (!mounted) return;
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
    return Scaffold(
      appBar: AppBar(title: const Text('Secure payment')),
      body: AbsorbPointer(
        absorbing: _processing,
        child: Form(
          key: _formKey,
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
              const SizedBox(height: 16),
              SegmentedButton<_PayMethod>(
                segments: const [
                  ButtonSegment(
                      value: _PayMethod.card,
                      label: Text('Card'),
                      icon: Icon(Icons.credit_card)),
                  ButtonSegment(
                      value: _PayMethod.promptpay,
                      label: Text('PromptPay'),
                      icon: Icon(Icons.qr_code)),
                ],
                selected: {_method},
                onSelectionChanged: (s) =>
                    setState(() => _method = s.first),
              ),
              const SizedBox(height: 20),
              if (_method == _PayMethod.card) ..._cardFields() else _qr(),
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
    );
  }

  List<Widget> _cardFields() {
    return [
      TextFormField(
        controller: _nameCtrl,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(
          labelText: 'Cardholder name',
          prefixIcon: Icon(Icons.person_outline),
        ),
        validator: (v) =>
            (v == null || v.trim().isEmpty) ? 'Required' : null,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _cardCtrl,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(16),
        ],
        decoration: const InputDecoration(
          labelText: 'Card number',
          prefixIcon: Icon(Icons.credit_card),
          hintText: '1234 5678 9012 3456',
        ),
        validator: (v) =>
            (v == null || v.length < 15) ? 'Enter a valid card number' : null,
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: _expiryCtrl,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: 'Expiry (MM/YY)',
                prefixIcon: Icon(Icons.date_range),
              ),
              validator: (v) =>
                  (v == null || v.length < 4) ? 'Required' : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _cvvCtrl,
              keyboardType: TextInputType.number,
              obscureText: true,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              decoration: const InputDecoration(
                labelText: 'CVV',
                prefixIcon: Icon(Icons.password),
              ),
              validator: (v) =>
                  (v == null || v.length < 3) ? 'Required' : null,
            ),
          ),
        ],
      ),
    ];
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

enum _PayMethod { card, promptpay }
