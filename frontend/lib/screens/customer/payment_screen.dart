import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/booking.dart';
import '../../models/payment.dart';
import '../../models/room.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/booking/booking_bloc.dart';
import '../../blocs/booking/booking_event.dart';
import '../../blocs/booking/booking_state.dart';
import '../../repositories/payment_repository.dart';
import '../../repositories/repository_exception.dart';
import '../../utils/formatters.dart';

/// Manual PromptPay payment: the customer scans the resort's static QR, transfers
/// the amount in their banking app, then uploads the transfer slip. Staff verify
/// the slip manually — this screen never marks the booking paid on its own.
///
/// Two entry points:
///  * [PaymentScreen] with room + dates → creates the booking first, then shows
///    the QR and slip upload.
///  * [PaymentScreen] with [existingBooking] → for an already-created booking
///    that is still unpaid (e.g. re-upload after a rejected slip).
class PaymentScreen extends StatefulWidget {
  final Room? room;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final int? guests;
  final double? total;
  final Booking? existingBooking;

  const PaymentScreen({
    super.key,
    this.room,
    this.checkIn,
    this.checkOut,
    this.guests,
    this.total,
    this.existingBooking,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late final PaymentRepository _payments;

  Booking? _booking;
  PaymentInfo? _info;
  PaymentView? _payment;

  bool _creating = false;
  bool _uploading = false;
  String? _fatalError;

  // Hold countdown: how long the room is reserved before auto-cancel.
  Timer? _ticker;
  Duration _remaining = Duration.zero;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    _payments = context.read<PaymentRepository>();
    _loadInfo();

    if (widget.existingBooking != null) {
      _booking = widget.existingBooking;
      _loadPayment();
    } else {
      // Reserve the room by creating the (pending) booking; the BlocListener
      // picks up the result. Guarded so a rebuild never creates twice.
      _creating = true;
      final user = context.read<AuthBloc>().state.currentUser!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<BookingBloc>().add(BookingCreateRequested(
              roomId: widget.room!.id,
              roomName: widget.room!.name,
              customerId: user.id,
              customerName: user.name,
              checkIn: widget.checkIn!,
              checkOut: widget.checkOut!,
              guests: widget.guests!,
              totalPrice: widget.total!,
            ));
      });
    }
  }

  double get _amount =>
      _booking?.totalPrice ?? widget.total ?? _payment?.amount ?? 0;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Starts (once) the hold countdown when a booking + info are available and
  /// no slip has been uploaded yet. Stops it otherwise.
  void _maybeStartCountdown() {
    final booking = _booking;
    final info = _info;
    if (booking == null || info == null) return;

    final status = _payment?.status;
    final holdApplies = status == null ||
        status == PaymentState.pending ||
        status == PaymentState.rejected;
    if (!holdApplies) {
      _stopCountdown();
      return;
    }
    if (_ticker != null) return; // already running

    final deadline = booking.createdAt.add(Duration(minutes: info.holdMinutes));
    void update() {
      if (!mounted) return;
      final rem = deadline.difference(DateTime.now());
      if (rem.inSeconds <= 0) {
        setState(() {
          _remaining = Duration.zero;
          _expired = true;
        });
        _stopCountdown();
      } else {
        setState(() => _remaining = rem);
      }
    }

    update();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => update());
  }

  void _stopCountdown() {
    _ticker?.cancel();
    _ticker = null;
  }

  Future<void> _loadInfo() async {
    try {
      final info = await _payments.fetchInfo();
      if (mounted) {
        setState(() => _info = info);
        _maybeStartCountdown();
      }
    } on RepositoryException {
      // QR info is non-critical; the amount + account text still render.
    }
  }

  Future<void> _loadPayment() async {
    final booking = _booking;
    if (booking == null) return;
    try {
      final p = await _payments.fetchForBooking(booking.id);
      if (mounted) {
        setState(() => _payment = p);
        _maybeStartCountdown();
      }
    } on RepositoryException {
      // No payment yet, or transient — the QR + upload UI still shows.
    }
  }

  void _onBookingCreated(Booking booking) {
    setState(() {
      _booking = booking;
      _creating = false;
    });
    _loadPayment();
  }

  Future<void> _pickAndUpload() async {
    final booking = _booking;
    if (booking == null) return;

    final XFile? picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final view = await _payments.uploadSlip(
        bookingId: booking.id,
        bytes: bytes,
        filename: picked.name,
      );
      if (!mounted) return;
      setState(() {
        _payment = view;
        _uploading = false;
      });
      _maybeStartCountdown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Slip uploaded — awaiting staff confirmation.')),
      );
    } on RepositoryException catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<BookingBloc, BookingState>(
      listenWhen: (_, _) => widget.existingBooking == null,
      listener: (context, state) {
        final created = state.lastCreatedBooking;
        if (created != null && _booking == null) {
          _onBookingCreated(created);
          return;
        }
        final error = state.errorMessage;
        if (error != null && _creating) {
          setState(() {
            _creating = false;
            _fatalError = error;
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Payment')),
        body: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_fatalError != null) {
      return _errorState(_fatalError!);
    }
    if (_creating || _booking == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final status = _payment?.status;
    return AbsorbPointer(
      absorbing: _uploading,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _amountCard(),
          const SizedBox(height: 16),
          if (status == PaymentState.succeeded)
            _confirmedCard()
          else if (status == PaymentState.awaitingVerification)
            _awaitingCard()
          else if (_expired)
            _expiredCard()
          else ...[
            if (status == PaymentState.rejected) _rejectedBanner(),
            _countdownBanner(),
            _qrCard(),
            const SizedBox(height: 16),
            _uploadButton(),
            const SizedBox(height: 12),
            _secureNote(),
          ],
        ],
      ),
    );
  }

  Widget _amountCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Amount due', style: TextStyle(fontSize: 16)),
            Text(
              Format.money(_amount),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF00796B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _countdownBanner() {
    final m = _remaining.inMinutes.toString().padLeft(2, '0');
    final sec = (_remaining.inSeconds % 60).toString().padLeft(2, '0');
    final warn = _remaining.inSeconds <= 60;
    final color = warn ? Colors.red : Colors.orange.shade800;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, color: color, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Pay and upload your slip within',
                style: TextStyle(fontSize: 13)),
          ),
          Text('$m:$sec',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 20, color: color)),
        ],
      ),
    );
  }

  Widget _expiredCard() {
    return Column(
      children: [
        Card(
          color: Colors.red.shade50,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(Icons.timer_off, color: Colors.red.shade600, size: 56),
                const SizedBox(height: 12),
                const Text('Payment time expired',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 6),
                Text(
                  'This booking was released so others can book the room. '
                  'Please search and book again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          child: const Text('Back to home'),
        ),
      ],
    );
  }

  Widget _qrCard() {
    // Dynamic PromptPay QR with the booking amount embedded.
    final url = _amount > 0 ? _payments.qrUrl(_amount) : '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            SizedBox(
              height: 220,
              width: 220,
              child: url.isEmpty
                  ? const Icon(Icons.qr_code_2, size: 200)
                  : Image.network(
                      url,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.qr_code_2, size: 200),
                      loadingBuilder: (_, child, progress) => progress == null
                          ? child
                          : const Center(child: CircularProgressIndicator()),
                    ),
            ),
            const SizedBox(height: 16),
            if (_info != null) ...[
              Text(
                _info!.accountName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 2),
              Text('PromptPay: ${_info!.promptPayId}',
                  style: TextStyle(color: Colors.grey.shade700)),
              const SizedBox(height: 10),
              Text(
                _info!.note,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ] else
              Text('Scan with your banking app to pay via PromptPay',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700)),
          ],
        ),
      ),
    );
  }

  Widget _uploadButton() {
    return FilledButton.icon(
      onPressed: _uploading ? null : _pickAndUpload,
      icon: _uploading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.upload_file),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      label: Text(_uploading ? 'Uploading…' : 'Upload payment slip'),
    );
  }

  Widget _secureNote() {
    return Row(
      children: [
        Icon(Icons.info_outline, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Transfer the amount above, then upload your slip. Staff will '
            'confirm your payment shortly.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _rejectedBanner() {
    final reason = _payment?.rejectReason;
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Your previous slip was rejected',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  if (reason != null && reason.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('Reason: $reason'),
                  ],
                  const SizedBox(height: 4),
                  const Text('Please transfer again and upload a new slip.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _awaitingCard() {
    return Column(
      children: [
        Card(
          color: Colors.orange.shade50,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(Icons.hourglass_top, color: Colors.orange.shade700, size: 56),
                const SizedBox(height: 12),
                const Text('Slip received',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 6),
                Text(
                  'We are verifying your payment. Your booking will be confirmed '
                  'once staff approve the slip.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _uploading ? null : _pickAndUpload,
          icon: const Icon(Icons.refresh),
          label: const Text('Re-upload a different slip'),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          child: const Text('Back to home'),
        ),
      ],
    );
  }

  Widget _confirmedCard() {
    return Column(
      children: [
        Card(
          color: Colors.green.shade50,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade600, size: 64),
                const SizedBox(height: 12),
                const Text('Payment confirmed',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 6),
                Text('Your booking is confirmed. Thank you!',
                    style: TextStyle(color: Colors.grey.shade700)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          child: const Text('Back to home'),
        ),
      ],
    );
  }

  Widget _errorState(String message) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 56, color: Colors.red.shade400),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Go back'),
          ),
        ],
      ),
    );
  }
}
