import 'package:flutter_test/flutter_test.dart';
import 'package:pcwork_mobile/models/crypto_payment_state.dart';

void main() {
  group('CryptoPaymentState review policy', () {
    test('overpayment is terminal but requires manual review', () {
      expect(CryptoPaymentState.isTerminal('overpaid'), isTrue);
      expect(CryptoPaymentState.requiresManualReview('overpaid'), isTrue);
    });

    test('normal settled payment does not require manual review', () {
      expect(CryptoPaymentState.isTerminal('paid'), isTrue);
      expect(CryptoPaymentState.requiresManualReview('paid'), isFalse);
    });

    test('partial payment remains non-terminal until expiry or settlement', () {
      expect(CryptoPaymentState.isTerminal('partial'), isFalse);
      expect(CryptoPaymentState.requiresManualReview('partial'), isFalse);
    });
  });

  group('CryptoPaymentState.resolve', () {
    test('PaidLate overrides Settled and stale supplied paid state', () {
      expect(CryptoPaymentState.resolve({
        'status': 'Settled',
        'additional_status': 'PaidLate',
        'payment_state': 'paid',
      }), 'late_payment_review');
    });

    test('PaidPartial overrides Processing and stale supplied paid state', () {
      expect(CryptoPaymentState.resolve({
        'status': 'Processing',
        'additional_status': 'PaidPartial',
        'payment_state': 'paid',
      }), 'partial');
    });

    test('PaidPartial after expiry requires manual contact', () {
      expect(CryptoPaymentState.resolve({
        'status': 'Expired',
        'additional_status': 'PaidPartial',
      }), 'partial_expired');
    });

    test('PaidOver overrides stale supplied paid state', () {
      expect(CryptoPaymentState.resolve({
        'status': 'Settled',
        'additional_status': 'PaidOver',
        'payment_state': 'paid',
      }), 'overpaid');
    });

    test('BTCPay camelCase additionalStatus is accepted', () {
      expect(CryptoPaymentState.resolve({
        'status': 'Settled',
        'additionalStatus': 'PaidLate',
      }), 'late_payment_review');
    });

    test('stale paid summary cannot promote unknown provider status', () {
      expect(CryptoPaymentState.resolve({
        'status': 'Unexpected',
        'payment_state': 'paid',
      }), 'unknown');
    });

    test('canonical Cardano state remains supported', () {
      expect(CryptoPaymentState.resolve({'status': 'partial'}), 'partial');
      expect(CryptoPaymentState.resolve({'status': 'confirming'}), 'confirming');
    });

    test('server state is used when no BTCPay exception exists', () {
      expect(CryptoPaymentState.resolve({
        'status': 'New',
        'payment_state': 'pending',
      }), 'pending');
    });

    test('camelCase additional status wins when snake_case field is empty', () {
      expect(CryptoPaymentState.resolve({
        'status': 'Settled',
        'additional_status': '',
        'additionalStatus': 'PaidOver',
      }), 'overpaid');
    });

    test('provider status whitespace and hyphen aliases are normalized', () {
      expect(CryptoPaymentState.resolve({'status': 'Processing'}), 'confirming');
      expect(CryptoPaymentState.resolve({'status': 'partial-expired'}), 'partial_expired');
    });

    test('additionalStatus separator variants normalize', () {
      expect(CryptoPaymentState.resolve({'status': 'Settled', 'additionalStatus': 'Paid_Late'}), 'late_payment_review');
      expect(CryptoPaymentState.resolve({'status': 'Expired', 'additional_status': 'Paid-Partial'}), 'partial_expired');
    });


    test('unknown provider state never promotes stale cached paid state', () {
      expect(CryptoPaymentState.resolve({
        'status': 'UnknownProviderState',
        'payment_state': 'paid',
      }), 'unknown');
    });

    test('empty provider state with no cached state remains unknown', () {
      expect(CryptoPaymentState.resolve({'status': ''}), 'unknown');
    });

    test('unknown status remains unknown', () {
      expect(CryptoPaymentState.resolve({'status': 'Unexpected'}), 'unknown');
    });

    test('empty provider status accepts only a known normalized cached state', () {
      expect(CryptoPaymentState.resolve({'status': '', 'payment_state': 'partial'}), 'partial');
      expect(CryptoPaymentState.resolve({'status': '', 'payment_state': 'paid_by_mistake'}), 'unknown');
    });
  });
}


// Regression coverage for absent provider state and stale cached summaries.
