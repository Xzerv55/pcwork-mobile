/// Canonical client-side interpretation of the BTCPay invoice status pair.
/// BTCPay additionalStatus exceptions must override a base Settled status
/// and any stale server-provided summary field.
class CryptoPaymentState {
  static const Set<String> _knownStates = {
    'paid', 'overpaid', 'partial', 'partial_expired', 'late_payment_review',
    'manual_review', 'confirming', 'expired', 'pending', 'unknown',
  };

  /// Resolves the canonical payment state. BTCPay additionalStatus exceptions
  /// always take precedence over base status and any cached summary field.
  static String resolve(Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString().trim().toLowerCase()
        .replaceAll(RegExp(r'[\s-]+'), '_');
    final snakeAdditional = (data['additional_status'] ?? '').toString().trim();
    final camelAdditional = (data['additionalStatus'] ?? '').toString().trim();
    final additional = (snakeAdditional.isNotEmpty ? snakeAdditional : camelAdditional)
        .toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');

    if (additional == 'paidlate') return 'late_payment_review';
    if (additional == 'paidpartial') {
      return const {'expired', 'invalid', 'partial_expired'}.contains(status)
          ? 'partial_expired'
          : 'partial';
    }
    if (additional == 'paidover') return 'overpaid';

    // Canonical BTCPay base statuses must override stale client-side summaries.
    if (status == 'settled') return 'paid';
    if (const {'expired', 'invalid'}.contains(status)) return 'expired';
    if (status == 'processing') return 'confirming';
    if (status == 'new') return 'pending';

    // Cardano and PCWork normalized states are already canonical server states.
    if (_knownStates.contains(status)) return status;
    if (status == 'creating') return 'pending';

    // A supplied state is accepted only when the raw status is absent; unknown
    // raw provider statuses must never be promoted to paid by stale cached data.
    if (status.isEmpty) {
      final supplied = (data['payment_state'] ?? '').toString().trim().toLowerCase();
      if (_knownStates.contains(supplied)) return supplied;
    }
    return 'unknown';
  }
}
