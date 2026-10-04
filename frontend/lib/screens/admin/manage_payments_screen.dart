import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/payment.dart';
import '../../blocs/booking/booking_bloc.dart';
import '../../blocs/booking/booking_event.dart';
import '../../blocs/payment/payment_bloc.dart';
import '../../blocs/payment/payment_event.dart';
import '../../blocs/payment/payment_state.dart';
import '../../repositories/payment_repository.dart';
import '../../utils/formatters.dart';
import '../../widgets/pull_to_refresh.dart';

/// Back office — manual verification of PromptPay transfer slips. Staff see the
/// uploaded slip, then approve (confirms the booking) or reject (customer
/// re-uploads).
class ManagePaymentsScreen extends StatelessWidget {
  const ManagePaymentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (ctx) =>
          PaymentAdminBloc(ctx.read<PaymentRepository>())
            ..add(const PaymentsLoadRequested(status: 'awaiting_verification')),
      child: const _ManagePaymentsView(),
    );
  }
}

class _ManagePaymentsView extends StatelessWidget {
  const _ManagePaymentsView();

  static const _filters = <String, String?>{
    'Awaiting': 'awaiting_verification',
    'Confirmed': 'succeeded',
    'Rejected': 'rejected',
    'All': null,
  };

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PaymentAdminBloc, PaymentAdminState>(
      listenWhen: (prev, cur) => prev.actionSeq != cur.actionSeq,
      listener: (context, state) {
        // An approval flipped a booking to paid/approved — refresh the list.
        context.read<BookingBloc>().add(const BookingStarted());
      },
      builder: (context, state) {
        return Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: _filters.entries.map((e) {
                  final selected = state.filter == e.value;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(e.key),
                      selected: selected,
                      onSelected: (_) => context.read<PaymentAdminBloc>().add(
                        PaymentsLoadRequested(status: e.value),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            Expanded(child: _body(context, state)),
          ],
        );
      },
    );
  }

  Widget _body(BuildContext context, PaymentAdminState state) {
    // Waits for the reload to land (the bloc emits `loading: true` first).
    Future<void> refresh() => reloadBloc(
      context.read<PaymentAdminBloc>(),
      PaymentsLoadRequested(status: state.filter),
      until: (s) => !s.loading,
    );

    if (state.loading && state.payments.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return RefreshableBody(
        onRefresh: refresh,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
                const SizedBox(height: 12),
                Text(state.error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.read<PaymentAdminBloc>().add(
                    PaymentsLoadRequested(status: state.filter),
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (state.payments.isEmpty) {
      return RefreshableBody(
        onRefresh: refresh,
        child: const Center(child: Text('No payments in this category')),
      );
    }
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        itemCount: state.payments.length,
        itemBuilder: (_, i) => _PaymentCard(payment: state.payments[i]),
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  final StaffPayment payment;
  const _PaymentCard({required this.payment});

  Color _color() {
    switch (payment.status) {
      case PaymentState.succeeded:
        return Colors.green;
      case PaymentState.awaitingVerification:
        return Colors.orange;
      case PaymentState.rejected:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _dates() {
    final ci = payment.checkIn, co = payment.checkOut;
    if (ci == null || co == null) return '';
    try {
      return '${Format.date(DateTime.parse(ci))} → ${Format.date(DateTime.parse(co))}';
    } catch (_) {
      return '$ci → $co';
    }
  }

  Future<void> _viewSlip(BuildContext context) async {
    final repo = context.read<PaymentRepository>();
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Transfer slip',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: FutureBuilder<Uint8List>(
                  future: repo.fetchSlipBytes(payment.id),
                  builder: (ctx, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator(),
                      );
                    }
                    if (snap.hasError || snap.data == null) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Could not load slip'),
                      );
                    }
                    return InteractiveViewer(
                      child: Image.memory(snap.data!, fit: BoxFit.contain),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _reject(BuildContext context) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject slip'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Reason',
            hintText: 'e.g. amount does not match',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.of(ctx).pop(text);
            },
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (reason != null && reason.isNotEmpty && context.mounted) {
      context.read<PaymentAdminBloc>().add(
        PaymentRejectRequested(payment.id, reason),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final awaiting = payment.status == PaymentState.awaitingVerification;
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
                    payment.roomName.isEmpty ? 'Booking' : payment.roomName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _color().withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    payment.status.label,
                    style: TextStyle(
                      color: _color(),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (payment.customerName.isNotEmpty)
              Text('Guest: ${payment.customerName}'),
            if (_dates().isNotEmpty) Text(_dates()),
            Text(
              Format.money(payment.amount),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF00796B),
              ),
            ),
            if (payment.status == PaymentState.rejected &&
                (payment.rejectReason?.isNotEmpty ?? false))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Rejected: ${payment.rejectReason}',
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (payment.hasSlip)
                  OutlinedButton.icon(
                    onPressed: () => _viewSlip(context),
                    icon: const Icon(Icons.image_outlined, size: 18),
                    label: const Text('View slip'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                    ),
                  ),
                if (awaiting) ...[
                  FilledButton.icon(
                    onPressed: () => context.read<PaymentAdminBloc>().add(
                      PaymentApproveRequested(payment.id),
                    ),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Approve'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _reject(context),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      minimumSize: const Size(0, 40),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
