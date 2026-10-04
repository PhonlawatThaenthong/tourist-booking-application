import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../models/booking.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/booking/booking_bloc.dart';
import '../../blocs/booking/booking_event.dart';
import '../../utils/formatters.dart';
import '../../widgets/pull_to_refresh.dart';
import 'payment_screen.dart';

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  @override
  void initState() {
    super.initState();
    // Re-fetch on open so an auto-cancelled hold no longer shows as Pending.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<BookingBloc>().add(const BookingStarted());
    });
  }

  Future<void> _refresh() =>
      reloadBloc(context.read<BookingBloc>(), const BookingStarted());

  /// Guests cannot cancel in the app; staff do it, so refunds and the
  /// freed room are handled at the desk. This shows who to contact instead.
  Future<void> _showCancelContact(Booking booking) {
    final paid = booking.paymentStatus == PaymentStatus.paid;
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.support_agent, size: 36),
        title: const Text('Contact us to cancel'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'To cancel your stay in ${booking.roomName} on '
                '${Format.date(booking.checkIn)}, please contact '
                '${AppConfig.adminContactName}'
                '${paid ? ', who will also arrange your refund' : ''}. '
                'Quote the booking reference below.',
              ),
              const SizedBox(height: 12),
              _ContactRow(
                icon: Icons.confirmation_number_outlined,
                label: 'Booking ref',
                value: booking.id,
              ),
              _ContactRow(
                icon: Icons.phone_outlined,
                label: 'Phone',
                value: AppConfig.adminPhone,
                onTap: () => _launch(
                  Uri(
                    scheme: 'tel',
                    path: AppConfig.adminPhone.replaceAll(
                      RegExp(r'[^0-9+]'),
                      '',
                    ),
                  ),
                ),
              ),
              if (AppConfig.adminEmail.isNotEmpty)
                _ContactRow(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  value: AppConfig.adminEmail,
                  onTap: () => _launch(
                    Uri(
                      scheme: 'mailto',
                      path: AppConfig.adminEmail,
                      query: 'subject=Cancel booking ${booking.id}',
                    ),
                  ),
                ),
              if (AppConfig.adminLineId.isNotEmpty)
                _ContactRow(
                  icon: Icons.chat_outlined,
                  label: 'LINE',
                  value: AppConfig.adminLineId,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () => _launch(
              Uri(
                scheme: 'tel',
                path: AppConfig.adminPhone.replaceAll(RegExp(r'[^0-9+]'), ''),
              ),
            ),
            icon: const Icon(Icons.call, size: 18),
            label: const Text('Call'),
          ),
        ],
      ),
    );
  }

  Future<void> _launch(Uri uri) async {
    final opened = await launchUrl(uri).catchError((_) => false);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No app on this device can open that')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final bookings = context.watch<BookingBloc>().forCustomer(
      auth.currentUser!.id,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('My bookings')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: bookings.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 100),
                  Icon(
                    Icons.luggage_outlined,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  const Center(child: Text('No bookings yet')),
                  Center(
                    child: Text(
                      'Find a room to get started',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
                ],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: bookings.length,
                itemBuilder: (_, i) => _BookingTile(
                  booking: bookings[i],
                  onCancel: () => _showCancelContact(bookings[i]),
                ),
              ),
      ),
    );
  }
}

/// One line of contact detail in the cancel dialog: tap to act on it (call,
/// email) where that makes sense, long-press or the copy icon to copy.
class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label copied')));
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      onTap: onTap,
      onLongPress: () => _copy(context),
      trailing: IconButton(
        tooltip: 'Copy',
        icon: const Icon(Icons.copy, size: 18),
        onPressed: () => _copy(context),
      ),
    );
  }
}

class _BookingTile extends StatelessWidget {
  final Booking booking;
  final VoidCallback onCancel;
  const _BookingTile({required this.booking, required this.onCancel});

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
                  // Opens the front-desk contact details; staff cancel.
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  icon: const Icon(Icons.cancel_outlined, size: 18),
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
