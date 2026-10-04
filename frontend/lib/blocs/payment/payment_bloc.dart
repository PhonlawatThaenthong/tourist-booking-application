import 'package:flutter_bloc/flutter_bloc.dart';

import '../../repositories/payment_repository.dart';
import '../../repositories/repository_exception.dart';
import 'payment_event.dart';
import 'payment_state.dart';

/// Back-office payment verification. Loads slips awaiting review and lets staff
/// approve or reject them; after each action the list is reloaded under the
/// current filter, so an approved slip drops out of the "awaiting" view.
class PaymentAdminBloc extends Bloc<PaymentAdminEvent, PaymentAdminState> {
  PaymentAdminBloc(this._repository) : super(const PaymentAdminState()) {
    on<PaymentsLoadRequested>(_onLoad);
    on<PaymentApproveRequested>(_onApprove);
    on<PaymentRejectRequested>(_onReject);
  }

  final PaymentRepository _repository;

  Future<void> _onLoad(
    PaymentsLoadRequested event,
    Emitter<PaymentAdminState> emit,
  ) async {
    final filter = event.status;
    emit(state.copyWith(loading: true, error: null, filter: filter));
    try {
      final rows = await _repository.fetchPending(status: filter);
      emit(state.copyWith(payments: rows, loading: false));
    } on RepositoryException catch (e) {
      emit(state.copyWith(loading: false, error: e.message));
    }
  }

  Future<void> _onApprove(
    PaymentApproveRequested event,
    Emitter<PaymentAdminState> emit,
  ) => _verify(emit, () => _repository.verify(event.paymentId, approve: true));

  Future<void> _onReject(
    PaymentRejectRequested event,
    Emitter<PaymentAdminState> emit,
  ) => _verify(
    emit,
    () => _repository.verify(
      event.paymentId,
      approve: false,
      reason: event.reason,
    ),
  );

  Future<void> _verify(
    Emitter<PaymentAdminState> emit,
    Future<void> Function() action,
  ) async {
    emit(state.copyWith(loading: true, error: null));
    try {
      await action();
      final rows = await _repository.fetchPending(status: state.filter);
      emit(
        state.copyWith(
          payments: rows,
          loading: false,
          actionSeq: state.actionSeq + 1,
        ),
      );
    } on RepositoryException catch (e) {
      emit(state.copyWith(loading: false, error: e.message));
    }
  }
}
