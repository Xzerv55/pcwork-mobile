import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../models/crypto_payment_state.dart';

class CryptoPaymentsScreen extends StatefulWidget {
  const CryptoPaymentsScreen({super.key, required this.api, required this.tokenProvider, required this.english, required this.isDarkTheme, this.initialOrderId, this.initialAsset = 'BTC'});
  final ApiService api;
  final Future<String?> Function() tokenProvider;
  final bool english;
  final bool isDarkTheme;
  final int? initialOrderId;
  final String initialAsset;

  @override
  State<CryptoPaymentsScreen> createState() => _CryptoPaymentsScreenState();
}

class _CryptoPaymentsScreenState extends State<CryptoPaymentsScreen> with WidgetsBindingObserver {
  static const _cyan = Color(0xFF21D4D8);
  static const _assets = <String, Map<String, dynamic>>{
    'BTC': {'name': 'Bitcoin', 'icon': '₿', 'color': Color(0xFFF7931A)},
    'ETH': {'name': 'Ethereum', 'icon': '◆', 'color': Color(0xFF8A9CFF)},
    'SOL': {'name': 'Solana', 'icon': '◎', 'color': Color(0xFF8B6CFF)},
    'ADA': {'name': 'Cardano', 'icon': '₳', 'color': Color(0xFF3978F6)},
    'GIBORIS': {'name': 'GIBORIS', 'icon': 'G', 'color': Color(0xFF21D4D8)},
  };
  final orderIdController = TextEditingController();
  String selectedAsset = 'BTC';
  String? token;
  Map<String, dynamic>? serverStatus;
  Map<String, dynamic>? invoice;
  bool loading = true;
  bool creating = false;
  bool refreshing = false;
  bool refreshingInvoice = false;
  bool _invoiceRefreshInProgress = false;
  DateTime? lastInvoiceRefresh;
  String? error;
  List<Map<String, dynamic>> paymentHistory = <Map<String, dynamic>>[];
  bool historyLoading = false;
  String? historyError;
  Timer? pollTimer;
  Timer? countdownTimer;
  int _pollFailureCount = 0;
  bool _pollingStopped = false;

  bool get en => widget.english;
  bool get dark => widget.isDarkTheme;
  Color get foreground => dark ? Colors.white : const Color(0xFF172033);
  Color get muted => dark ? const Color(0xFFAFBED4) : const Color(0xFF68778B);
  String tr(String bg, String english) => en ? english : bg;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.initialOrderId != null && widget.initialOrderId! > 0) orderIdController.text = widget.initialOrderId.toString();
    selectedAsset = widget.initialAsset.toUpperCase();
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    pollTimer?.cancel();
    countdownTimer?.cancel();
    orderIdController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      token = await widget.tokenProvider();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = _friendlyError(e);
      });
      return;
    }
    if (token == null || token!.isEmpty) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = tr('Влезте в PCWork профила си, за да използвате криптоплащания.', 'Sign in to your PCWork account to use crypto payments.');
      });
      return;
    }
    try {
      final result = await widget.api.getCryptoPaymentStatus(token!);
      if (!mounted) return;
      setState(() {
        serverStatus = result;
        loading = false;
        if (widget.initialOrderId == null && !supportedAssets.contains(selectedAsset) && supportedAssets.isNotEmpty) selectedAsset = supportedAssets.first;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { loading = false; error = _friendlyError(e); });
    }
    await _loadPaymentHistory();
    final initialAsset = widget.initialAsset.toUpperCase();
    if (mounted && widget.initialOrderId != null && widget.initialOrderId! > 0) {
      if (['BTC', 'ADA', 'ETH', 'SOL'].contains(initialAsset) && supportedAssets.contains(initialAsset)) {
        await _createInvoice();
      } else if (mounted) {
        setState(() => error = tr('Избраният за поръчката актив вече не е наличен. Не избирай друга валута за същата поръчка; свържи се с PCWork.', 'The asset selected for this order is no longer available. Do not choose another currency for this order; contact PCWork.'));
      }
    }
  }

  Future<void> _loadPaymentHistory() async {
    if (token == null || token!.isEmpty || historyLoading) return;
    setState(() { historyLoading = true; historyError = null; });
    try {
      final items = await widget.api.getCryptoPaymentHistory(token!);
      if (!mounted) return;
      setState(() { paymentHistory = items; });
    } catch (e) {
      if (mounted) setState(() { historyError = _friendlyError(e); });
    } finally {
      if (mounted) setState(() { historyLoading = false; });
    }
  }

  Future<void> _openHistoryItem(Map<String, dynamic> item) async {
    final id = (item['invoice_id'] ?? '').toString();
    final asset = (item['asset'] ?? '').toString().toUpperCase();
    if (id.isEmpty || !['BTC', 'ADA', 'ETH', 'SOL'].contains(asset) || token == null) return;
    setState(() {
      selectedAsset = asset;
      invoice = Map<String, dynamic>.from(item)..['id'] = id;
      error = null;
    });
    await _refreshInvoice(manual: true);
    await _loadPaymentHistory();
  }

  Future<void> _refreshServerStatus() async {
    if (token == null || token!.isEmpty) return;
    setState(() { refreshing = true; error = null; });
    try {
      final result = await widget.api.getCryptoPaymentStatus(token!);
      if (!mounted) return;
      setState(() { serverStatus = result; if (!supportedAssets.contains(selectedAsset) && supportedAssets.isNotEmpty) selectedAsset = supportedAssets.first; });
    } catch (e) {
      if (mounted) setState(() => error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  String _friendlyError(Object e) {
    final raw = e.toString().replaceFirst('Exception: ', '');
    if (raw.contains('404') || raw.toLowerCase().contains('not found')) {
      return tr('Криптоплащанията все още не са конфигурирани на PCWork сървъра. Не се генерират адреси и не приемаме реални плащания, докато сървърната интеграция не бъде инсталирана и проверена.', 'Crypto payments are not configured on the PCWork server yet. No addresses are generated and real payments are not accepted until the server integration is installed and verified.');
    }
    if (raw.toLowerCase().contains('частично') || raw.toLowerCase().contains('paidpartial')) {
      return tr('По поръчката вече има частично крипто плащане. Не създавай нова заявка и не изпращай повторно пълната сума. Използвай същата платежна заявка или се свържи с PCWork.', 'A partial crypto payment already exists for this order. Do not create another request or resend the full amount. Continue using the same payment request or contact PCWork.');
    }
    return raw;
  }

  bool get enabled => serverStatus?['enabled'] == true;
  List<String> get supportedAssets {
    final configured = serverStatus?['assets'] ?? serverStatus?['active_assets'];
    if (configured is List) return configured.map((e) => e.toString().toUpperCase()).where(_assets.containsKey).toList();
    return <String>[];
  }

  Future<void> _createInvoice() async {
    final id = int.tryParse(orderIdController.text.trim());
    if (id == null || id <= 0) {
      _message(tr('Въведете валиден номер на поръчка.', 'Enter a valid order number.'));
      return;
    }
    if (token == null || !enabled || !supportedAssets.contains(selectedAsset) || creating) {
      _message(tr('Тази валута все още не е активирана от PCWork сървъра.', 'This currency is not yet enabled by the PCWork server.'));
      return;
    }
    if (!_canCreateInvoice) {
      _message(tr('Има активна или вече платена заявка. Използвай съществуващата фактура и не създавай дубликат.', 'An active or already paid invoice exists. Continue with the existing invoice and do not create a duplicate.'));
      return;
    }
    setState(() { creating = true; error = null; invoice = null; });
    try {
      final result = await widget.api.createCryptoPayment(token!, orderId: id, asset: selectedAsset);
      if (!mounted) return;
      final data = result['invoice'] is Map ? Map<String, dynamic>.from(result['invoice']) : result;
      final invoiceId = (data['id'] ?? '').toString();
      if (selectedAsset == 'ETH' || selectedAsset == 'SOL') {
        final address = (data['address'] ?? '').toString();
        final amount = (data['amount'] ?? '').toString();
        final expectedNetwork = selectedAsset == 'ETH' ? 'sepolia' : 'devnet';
        if (!invoiceId.startsWith('${selectedAsset.toLowerCase()}_') || address.isEmpty || amount.isEmpty || (data['network'] ?? '') != expectedNetwork || data['settlement_enabled'] == true) {
          throw Exception(tr('Gateway не върна валидна ETH/SOL testnet заявка.', 'Gateway did not return a valid ETH/SOL testnet payment request.'));
        }
        setState(() => invoice = data);
        _startPolling();
      } else if (selectedAsset == 'ADA') {
        final address = (data['address'] ?? '').toString();
        final amount = (data['amount_ada'] ?? data['amount'] ?? '').toString();
        if (!invoiceId.startsWith('ada_') || !address.startsWith('addr_test1') || amount.isEmpty || (data['network'] ?? 'preprod') != 'preprod') {
          throw Exception(tr('Gateway не върна валидна Cardano Preprod заявка.', 'Gateway did not return a valid Cardano Preprod payment request.'));
        }
        setState(() => invoice = data);
        _startPolling();
      } else {
        final checkout = (data['checkout_link'] ?? '').toString();
        final checkoutUri = Uri.tryParse(checkout);
        if (invoiceId.isEmpty || checkoutUri == null || checkoutUri.scheme != 'https' || checkoutUri.host.isEmpty) {
          throw Exception(tr('Сървърът не върна валидна защитена BTCPay платежна страница.', 'The server did not return a valid secure BTCPay checkout page.'));
        }
        setState(() => invoice = data);
        _startPolling();
        final opened = await launchUrl(checkoutUri, mode: LaunchMode.externalApplication);
        if (!opened && mounted) _message(tr('Не успяхме да отворим BTCPay. Използвай бутона „Отвори плащането“.', 'Could not open BTCPay. Use the Open payment button.'));
      }
    } catch (e) {
      if (mounted) setState(() => error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => creating = false);
    }
  }

  void _startPolling() {
    pollTimer?.cancel();
    countdownTimer?.cancel();
    _pollFailureCount = 0;
    _pollingStopped = false;
    _scheduleInvoicePoll(const Duration(seconds: 12));
    countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  void _scheduleInvoicePoll(Duration delay) {
    pollTimer?.cancel();
    if (!mounted || _pollingStopped) return;
    pollTimer = Timer(delay, () async {
      await _refreshInvoice();
      if (!mounted || _pollingStopped) return;
      final seconds = _pollFailureCount == 0
          ? 12
          : (12 * (1 << (_pollFailureCount.clamp(1, 5).toInt() - 1))).clamp(24, 300).toInt();
      _scheduleInvoicePoll(Duration(seconds: seconds));
    });
  }

  void _stopPolling() {
    _pollingStopped = true;
    pollTimer?.cancel();
    countdownTimer?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && invoice != null && !_pollingStopped) {
      _scheduleInvoicePoll(Duration.zero);
    }
  }

  String _paymentState(Map<String, dynamic> data) => CryptoPaymentState.resolve(data);

  bool get _canCreateInvoice {
    if (invoice == null) return true;
    return _paymentState(invoice!) == 'expired';
  }

  Future<void> _refreshInvoice({bool manual = false}) async {
    final current = invoice;
    final id = current?['id']?.toString();
    if (id == null || id.isEmpty || token == null || _invoiceRefreshInProgress) return;
    _invoiceRefreshInProgress = true;
    if (manual && mounted) setState(() => refreshingInvoice = true);
    try {
      final result = await widget.api.getCryptoPayment(token!, id);
      final data = result['invoice'] is Map ? Map<String, dynamic>.from(result['invoice']) : result;
      if (!mounted) return;
      final merged = {...?invoice, ...data};
      setState(() { invoice = merged; lastInvoiceRefresh = DateTime.now(); });
      _pollFailureCount = 0;
      final terminal = CryptoPaymentState.isTerminal(_paymentState(merged));
      if (terminal) {
        _stopPolling();
        await _loadPaymentHistory();
      }
      if (manual) _message(tr('Статусът е обновен от PCWork сървъра.', 'Payment status refreshed from the PCWork server.'));
    } catch (_) {
      // A temporary network error must not change a payment to failed.
      _pollFailureCount = (_pollFailureCount + 1).clamp(1, 6);
      if (manual && mounted) _message(tr('В момента няма връзка със сървъра. Последният потвърден статус се запазва.', 'The server is temporarily unavailable. The last confirmed status is preserved.'));
    } finally {
      _invoiceRefreshInProgress = false;
      if (manual && mounted) setState(() => refreshingInvoice = false);
    }
  }

  void _message(String value) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF071225) : const Color(0xFFF3F6FB),
      appBar: AppBar(title: Text(tr('Криптоплащания', 'Crypto payments')), backgroundColor: Colors.transparent, foregroundColor: foreground, elevation: 0, actions: [IconButton(tooltip: tr('Обнови статуса', 'Refresh status'), onPressed: refreshing ? null : _refreshServerStatus, icon: refreshing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh))]),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: _cyan))
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 28), children: [
              _hero(),
              const SizedBox(height: 16),
              _chainDiagnostics(),
              const SizedBox(height: 12),
              if (error != null) _notice(error!, isError: true),
              if (!enabled) ...[
                _assetPicker(),
                const SizedBox(height: 12),
                _notice((serverStatus?['message'] ?? tr('Сървърната услуга е изключена или все още не е инсталирана. Не се показват фиктивни адреси или потвърждения.', 'The server service is disabled or not installed yet. No fake addresses or confirmations are shown.')).toString(), isError: false),
                const SizedBox(height: 12),
                _securityNote(),
                const SizedBox(height: 18),
                _historySection(),
              ] else ...[
                _assetPicker(),
                const SizedBox(height: 14),
                _orderForm(),
                if (invoice != null) ...[const SizedBox(height: 16), _invoiceCard()],
                const SizedBox(height: 18),
                _historySection(),
                const SizedBox(height: 14),
                _securityNote(),
              ],
            ]),
    );
  }


  Widget _chainDiagnostics() {
    final readiness = serverStatus?['asset_readiness'];
    if (readiness is! Map) return const SizedBox.shrink();
    final rows = <Map<String, dynamic>>[];
    for (final symbol in ['ETH', 'SOL', 'GIBORIS']) {
      final raw = readiness[symbol];
      if (raw is Map) rows.add({'symbol': symbol, ...Map<String, dynamic>.from(raw)});
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF101F38) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cyan.withValues(alpha: .25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Състояние на допълнителните мрежи', 'Additional network status'), style: TextStyle(color: foreground, fontWeight: FontWeight.w800, fontSize: 14)),
        const SizedBox(height: 8),
        ...rows.map((row) {
          final symbol = row['symbol'].toString();
          final connected = row['connected'] == true;
          final active = row['active'] == true && row['payment_creation_enabled'] == true;
          final network = (row['network'] ?? (symbol == 'GIBORIS' ? 'Cardano' : '—')).toString();
          final detail = symbol == 'GIBORIS'
              ? tr('Идентичността на токена и платежният поток се подготвят.', 'Token identity and payment flow are being prepared.')
              : active
                  ? tr('Testnet адресният пул и RPC са готови. Тестовите трансфери не маркират поръчките като платени.', 'Testnet address pool and RPC are ready. Test transfers do not mark orders as paid.')
                  : connected
                      ? tr('RPC връзката е налична, но адресният пул или готовността за заявки липсва.', 'RPC is connected, but the address pool or invoice readiness is missing.')
                      : tr('Няма активна RPC връзка или мрежата не е конфигурирана.', 'No active RPC connection or network is not configured.');
          return Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 58, child: Text(symbol, style: TextStyle(color: foreground, fontWeight: FontWeight.w900))),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$network · ${active ? tr('Активен', 'Active') : (connected ? tr('Диагностика', 'Diagnostics only') : tr('Неактивен', 'Inactive'))}', style: TextStyle(color: active ? const Color(0xFF27AE80) : muted, fontSize: 11.5, fontWeight: FontWeight.w700)),
                Text(detail, style: TextStyle(color: muted, fontSize: 11, height: 1.3)),
              ])),
              Icon(active ? Icons.check_circle : (connected ? Icons.info_outline : Icons.hourglass_empty), size: 17, color: active ? const Color(0xFF27AE80) : muted),
            ]),
          );
        }),
        const SizedBox(height: 8),
        Text(tr('ETH използва Sepolia, а SOL – Devnet. Използват се предварително генерирани публични адреси и read-only наблюдение. Няма частни ключове, подписване, Mainnet или settlement.', 'ETH uses Sepolia and SOL uses Devnet. Pre-generated public addresses and read-only observation are used. No private keys, signing, Mainnet or settlement.'), style: TextStyle(color: muted, fontSize: 10.5, height: 1.35)),
      ]),
    );
  }

  Widget _hero() => Container(
    padding: const EdgeInsets.all(19),
    decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF102A50), Color(0xFF15204A), Color(0xFF30205C)]), borderRadius: BorderRadius.circular(25), border: Border.all(color: _cyan.withValues(alpha: .55)), boxShadow: [BoxShadow(color: _cyan.withValues(alpha: .12), blurRadius: 24, offset: const Offset(0, 8))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [Icon(Icons.currency_bitcoin_rounded, color: _cyan, size: 25), SizedBox(width: 8), Text('PCWORK CRYPTO', style: TextStyle(color: _cyan, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.6))]),
      const SizedBox(height: 10),
      Text(tr('Криптоплащане към PCWork', 'Crypto payment to PCWork'), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, height: 1.15)),
      const SizedBox(height: 7),
      Text(tr('BTC чрез BTCPay · ADA чрез Cardano Preprod · ETH Sepolia · SOL Devnet · GIBORIS в подготовка', 'BTC via BTCPay · ADA via Cardano Preprod · ETH Sepolia · SOL Devnet · GIBORIS in preparation'), style: const TextStyle(color: Color(0xFFD4E5FF), fontSize: 12, height: 1.35)),
    ]),
  );

  Widget _notice(String text, {required bool isError}) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: (isError ? const Color(0xFFFF647C) : const Color(0xFFFFC857)).withValues(alpha: .10), borderRadius: BorderRadius.circular(16), border: Border.all(color: (isError ? const Color(0xFFFF647C) : const Color(0xFFFFC857)).withValues(alpha: .5))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(isError ? Icons.error_outline : Icons.info_outline, color: isError ? const Color(0xFFFF647C) : const Color(0xFFFFC857)), const SizedBox(width: 10), Expanded(child: Text(text, style: TextStyle(color: foreground, fontSize: 12.5, height: 1.4))) ]),
  );

  Widget _assetPicker() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(tr('Избери криптовалута', 'Choose cryptocurrency'), style: TextStyle(color: foreground, fontSize: 16, fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      ..._assets.keys.where((symbol) => widget.initialOrderId == null || symbol == widget.initialAsset.toUpperCase()).map((symbol) {
        final asset = _assets[symbol]!;
        final active = supportedAssets.contains(symbol);
        final selected = selectedAsset == symbol;
        final color = asset['color'] as Color;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: selected ? color.withValues(alpha: .13) : (dark ? const Color(0xFF101F38) : Colors.white),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: active && widget.initialOrderId == null ? () => setState(() => selectedAsset = symbol) : null,
              child: Opacity(
                opacity: active ? 1 : .58,
                child: Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: selected ? color : (dark ? const Color(0xFF263B5A) : const Color(0xFFDCE4EF)), width: selected ? 1.5 : 1),
                  ),
                  child: Row(children: [
                    Container(
                      width: 40, height: 40, alignment: Alignment.center,
                      decoration: BoxDecoration(color: color.withValues(alpha: .16), shape: BoxShape.circle),
                      child: Text(asset['icon'].toString(), style: TextStyle(color: color, fontSize: 23, fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(asset['name'].toString(), style: TextStyle(color: foreground, fontWeight: FontWeight.w800)),
                      Text(active ? symbol : '$symbol · ${tr('Очаква интеграция', 'Integration pending')}', style: TextStyle(color: muted, fontSize: 12)),
                    ])),
                    Icon(active ? (selected ? Icons.radio_button_checked : Icons.radio_button_off) : Icons.lock_outline, color: selected ? color : muted),
                  ]),
                ),
              ),
            ),
          ),
        );
      }),
    ],
  );

  Widget _orderForm() => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: dark ? const Color(0xFF101F38) : Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: dark ? const Color(0xFF263B5A) : const Color(0xFFDCE4EF))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(tr('Плащане на поръчка', 'Pay an order'), style: TextStyle(color: foreground, fontSize: 16, fontWeight: FontWeight.w800)),
    const SizedBox(height: 6),
    Text(tr('Въведи номера на поръчката. Сумата се определя и валидира от PCWork сървъра, а не от приложението.', 'Enter the order number. The amount is determined and validated by the PCWork server, not by the app.'), style: TextStyle(color: muted, fontSize: 12, height: 1.35)),
    const SizedBox(height: 12),
    TextField(controller: orderIdController, keyboardType: TextInputType.number, style: TextStyle(color: foreground), decoration: InputDecoration(labelText: tr('Номер на поръчка', 'Order number'), prefixIcon: const Icon(Icons.receipt_long_outlined), filled: true, fillColor: dark ? const Color(0xFF09162A) : const Color(0xFFF5F7FA), border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)))),
    const SizedBox(height: 12),
    SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: creating || !_canCreateInvoice || !supportedAssets.contains(selectedAsset) ? null : _createInvoice, icon: creating ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.qr_code_2), label: Text(creating ? tr('Създаване...', 'Creating...') : !_canCreateInvoice ? tr('Има съществуваща заявка', 'Existing payment request') : (selectedAsset == 'ADA' ? tr('Създай ADA заявка', 'Create ADA payment') : (selectedAsset == 'ETH' || selectedAsset == 'SOL') ? tr('Създай testnet заявка', 'Create testnet request') : tr('Генерирай BTC фактура', 'Create BTC invoice'))), style: FilledButton.styleFrom(backgroundColor: const Color(0xFF087BFF), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)))),
  ]));

  Widget _invoiceCard() {
    final data = invoice!;
    final status = (data['status'] ?? 'new').toString();
    final paymentState = _paymentState(data);
    final checkout = (data['checkout_link'] ?? '').toString();
    final expires = int.tryParse((data['expires_at'] ?? '').toString()) ?? 0;
    final remaining = expires > 0 ? expires - DateTime.now().millisecondsSinceEpoch ~/ 1000 : 0;
    final settled = paymentState == 'paid';
    final reviewRequired = CryptoPaymentState.requiresManualReview(paymentState);
    final expired = paymentState == 'expired' || paymentState == 'partial_expired' || paymentState == 'late_payment_review' || paymentState == 'manual_review';
    final partial = paymentState == 'partial' || paymentState == 'partial_expired';
    final uri = Uri.tryParse(checkout);
    final stateColor = settled ? const Color(0xFF20E39A) : expired ? const Color(0xFFFF647C) : partial || reviewRequired ? const Color(0xFFFFC857) : const Color(0xFFFFC857);
    return Container(padding: const EdgeInsets.all(17), decoration: BoxDecoration(color: dark ? const Color(0xFF101F38) : Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: stateColor.withValues(alpha: .75))), child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Text(tr('Крипто платежна заявка', 'Crypto payment request'), style: TextStyle(color: foreground, fontSize: 17, fontWeight: FontWeight.w900)),
      const SizedBox(height: 6),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (lastInvoiceRefresh != null) Text('${tr('Последна проверка', 'Last checked')}: ${TimeOfDay.fromDateTime(lastInvoiceRefresh!).format(context)}', style: TextStyle(color: muted, fontSize: 10.5)),
        if (lastInvoiceRefresh != null) const SizedBox(width: 8),
        TextButton.icon(onPressed: refreshingInvoice ? null : () => _refreshInvoice(manual: true), icon: refreshingInvoice ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh, size: 16), label: Text(tr('Провери сега', 'Check now'))),
      ]),
      const SizedBox(height: 4),
      Text(data['asset']?.toString() == 'ADA' ? 'Cardano (ADA)' : data['asset']?.toString() == 'ETH' ? 'Ethereum (Sepolia)' : data['asset']?.toString() == 'SOL' ? 'Solana (Devnet)' : 'Bitcoin (BTC)', style: const TextStyle(color: _cyan, fontSize: 22, fontWeight: FontWeight.w900)),
      if (remaining > 0 && !settled && !expired) Text('${tr('Оставащо време', 'Time remaining')}: ${remaining ~/ 60} мин. ${remaining % 60} сек.', style: TextStyle(color: muted, fontSize: 12)),
      const SizedBox(height: 12),
      Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: stateColor.withValues(alpha: .12), borderRadius: BorderRadius.circular(13)), child: Row(children: [Icon(settled ? Icons.verified : reviewRequired ? Icons.warning_amber_rounded : expired ? Icons.error_outline : partial ? Icons.payments_outlined : Icons.hourglass_top, color: stateColor), const SizedBox(width: 9), Expanded(child: Text(_statusLabel(paymentState, status), style: TextStyle(color: foreground, fontWeight: FontWeight.w800, fontSize: 13)))])),
      if (!['ADA','ETH','SOL'].contains(data['asset']?.toString()) && ((data['amount'] ?? '').toString().isNotEmpty || (data['paid_amount'] ?? '').toString().isNotEmpty)) ...[
        const SizedBox(height: 10),
        Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: dark ? const Color(0xFF0B1930) : const Color(0xFFF2F6FC), borderRadius: BorderRadius.circular(13)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Разбивка на BTC плащането', 'BTC payment breakdown'), style: TextStyle(color: foreground, fontWeight: FontWeight.w800, fontSize: 12)),
          const SizedBox(height: 7),
          if ((data['amount'] ?? '').toString().isNotEmpty) _amountRow(tr('Изисквана сума', 'Required amount'), '${data['amount']} ${data['currency'] ?? 'EUR'}'),
          if ((data['paid_amount'] ?? '').toString().isNotEmpty) _amountRow(tr('Получена сума', 'Received amount'), '${data['paid_amount']} ${data['currency'] ?? 'EUR'}'),
          Text(tr('Сумите се показват само когато са върнати от сървъра; точната BTC инструкция остава в защитената BTCPay страница.', 'Amounts are shown only when returned by the server; the exact BTC payment instructions remain on the secure BTCPay checkout page.'), style: TextStyle(color: muted, fontSize: 10.5, height: 1.35)),
        ])),
      ],
      if (['ETH','SOL'].contains(data['asset']?.toString())) ...[
        const SizedBox(height: 10),
        Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: dark ? const Color(0xFF0B1930) : const Color(0xFFF2F6FC), borderRadius: BorderRadius.circular(13)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Testnet платежни данни', 'Testnet payment details'), style: TextStyle(color: foreground, fontWeight: FontWeight.w800, fontSize: 12)),
          const SizedBox(height: 7),
          _amountRow(tr('Изисквана сума', 'Required amount'), '${data['amount'] ?? '—'} ${data['asset']}'),
          _amountRow(tr('Получена сума', 'Received amount'), '${data['received_amount'] ?? '0'} ${data['asset']}'),
          _amountRow(tr('Потвърждения', 'Confirmations'), '${data['confirmations'] ?? 0}/${data['required_confirmations'] ?? (data['asset'] == 'ETH' ? 12 : 1)}'),
          if ((data['fiat_amount_eur'] ?? '').toString().isNotEmpty) _amountRow(tr('Стойност на поръчката', 'Order value'), '${data['fiat_amount_eur']} EUR'),
          if (data['transactions'] is List && (data['transactions'] as List).isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(tr('Наблюдавани транзакции', 'Observed transactions'), style: TextStyle(color: foreground, fontWeight: FontWeight.w800, fontSize: 11)),
            ...(data['transactions'] as List).take(8).whereType<Map>().map((tx) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: SelectableText('${tx['tx_hash'] ?? '—'} · ${tx['amount'] ?? ''} · ${tx['confirmations'] ?? 0} conf.', style: TextStyle(color: muted, fontSize: 10)))),
          ],
        ])),
        Padding(padding: const EdgeInsets.only(top: 10), child: Container(width: double.infinity, padding: const EdgeInsets.all(11), decoration: BoxDecoration(color: const Color(0xFFFFC857).withValues(alpha: .12), borderRadius: BorderRadius.circular(12)), child: Text(tr('ТЕСТОВА МРЕЖА: потвърденият трансфер е само testnet verification. WooCommerce поръчката не се маркира като платена и settlement е изключен.', 'TEST NETWORK: a confirmed transfer is testnet verification only. The WooCommerce order is not marked as paid and settlement is disabled.'), style: TextStyle(color: foreground, fontSize: 11.5, height: 1.4, fontWeight: FontWeight.w600)))),
      ],
      if (data['asset']?.toString() == 'ADA' && data['settlement_enabled'] != true) Padding(padding: const EdgeInsets.only(top: 10), child: Container(width: double.infinity, padding: const EdgeInsets.all(11), decoration: BoxDecoration(color: const Color(0xFFFFC857).withValues(alpha: .12), borderRadius: BorderRadius.circular(12)), child: Text(tr('ТЕСТОВА МРЕЖА PREPROD: дори при потвърден трансфер поръчката не се маркира като платена. Това е тест на адреса, наблюдението и известяването, а не реално разплащане.', 'PREPROD TEST NETWORK: even after a confirmed transfer, the order is not marked as paid. This tests address generation, monitoring and notifications—not real settlement.'), style: TextStyle(color: foreground, fontSize: 11.5, height: 1.4, fontWeight: FontWeight.w600)))) ,
      if (partial && !expired) Padding(padding: const EdgeInsets.only(top: 10), child: Text(tr('Получено е частично плащане. Доплати по същата фактура преди изтичането ѝ. Не създавай нова заявка.', 'A partial payment was received. Complete payment using the same invoice before it expires. Do not create another request.'), textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 12, height: 1.4))),
      if (paymentState == 'partial_expired') Padding(padding: const EdgeInsets.only(top: 10), child: Text(tr('Фактурата е изтекла с частично плащане. Не изпращай повторно пълната сума. Свържи се с PCWork за проверка и инструкции.', 'The invoice expired with a partial payment. Do not resend the full amount. Contact PCWork for review and instructions.'), textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 12, height: 1.4))),
      if (paymentState == 'late_payment_review') Padding(padding: const EdgeInsets.only(top: 10), child: Text(['ETH','SOL'].contains(data['asset']?.toString()) ? tr('Testnet трансферът е засечен след изтичане на заявката. Поръчката не се маркира като платена и изисква ръчна проверка.', 'The testnet transfer was detected after the request expired. The order is not marked as paid and requires manual review.') : tr('BTCPay отчита късно плащане след изтичане на фактурата. Поръчката не се маркира автоматично като платена и изисква проверка от PCWork.', 'BTCPay reports a late payment after invoice expiry. The order is not automatically marked as paid and requires PCWork review.'), textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 12, height: 1.4))),
      if (paymentState == 'overpaid') Padding(padding: const EdgeInsets.only(top: 10), child: Text(['ETH','SOL'].contains(data['asset']?.toString()) ? tr('Получената testnet сума е над очакваната. Поръчката не се маркира като платена; необходима е ръчна проверка от PCWork.', 'The received testnet amount exceeds the expected amount. The order is not marked as paid and requires PCWork review.') : tr('BTCPay отчита надплатена сума. Това не е автоматично окончателно потвърждение за поръчката. Не изпращай повторно средства; PCWork трябва да провери сумата.', 'BTCPay reports an overpayment. This is not an automatic final order confirmation. Do not send additional funds; PCWork must review the amount.'), textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 12, height: 1.4))),
      if (paymentState == 'manual_review') Padding(padding: const EdgeInsets.only(top: 10), child: Text(tr('Плащането изисква ръчна проверка от PCWork. Не изпращай повторно средства и не създавай нова заявка.', 'This payment requires manual review by PCWork. Do not resend funds or create another request.'), textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 12, height: 1.4))),
      if (data['asset']?.toString() == 'ADA') ...[
        const SizedBox(height: 10),
        Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: dark ? const Color(0xFF0B1930) : const Color(0xFFF2F6FC), borderRadius: BorderRadius.circular(13)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Разбивка на плащането', 'Payment breakdown'), style: TextStyle(color: foreground, fontWeight: FontWeight.w800, fontSize: 12)),
          const SizedBox(height: 7),
          _amountRow(tr('Изисквана сума', 'Required amount'), '${data['amount_ada'] ?? data['amount'] ?? _formatLovelace(data['expected_lovelace'])} ADA'),
          _amountRow(tr('Получена сума', 'Received amount'), '${_formatLovelace(data['received_lovelace'])} ADA'),
          if (_lovelaceValue(data['expected_lovelace']) > 0) ...[
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: (_lovelaceValue(data['received_lovelace']) / _lovelaceValue(data['expected_lovelace'])).clamp(0.0, 1.0).toDouble(), minHeight: 7, backgroundColor: muted.withValues(alpha: .18), valueColor: AlwaysStoppedAnimation<Color>(settled ? const Color(0xFF20E39A) : const Color(0xFF21A5D8)))),
          ],
          if (data['transactions'] is List && (data['transactions'] as List).isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(tr('Наблюдавани блокчейн транзакции', 'Observed blockchain transactions'), style: TextStyle(color: foreground, fontWeight: FontWeight.w800, fontSize: 12)),
            const SizedBox(height: 5),
            ...(data['transactions'] as List).take(10).whereType<Map>().map((tx) {
              final txId = (tx['tx_id'] ?? '').toString();
              final index = (tx['output_index'] ?? '').toString();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SelectableText(txId.isEmpty ? '—' : '${txId.substring(0, txId.length > 18 ? 18 : txId.length)}… #$index', style: TextStyle(color: muted, fontSize: 10.5)),
                    Text('${tx['confirmations'] ?? 0}/${tx['required_confirmations'] ?? 2160} ${tr('потвърждения', 'confirmations')}', style: TextStyle(color: muted, fontSize: 9.5)),
                  ])),
                  IconButton(tooltip: tr('Копирай transaction ID', 'Copy transaction ID'), visualDensity: VisualDensity.compact, onPressed: txId.isEmpty ? null : () async { await Clipboard.setData(ClipboardData(text: txId)); if (mounted) _message(tr('Transaction ID е копиран.', 'Transaction ID copied.')); }, icon: const Icon(Icons.copy, size: 15)),
                ]),
              );
            }),
          ],
        ])),
      ],
      if (data['asset']?.toString() == 'ADA' && !settled && !expired) ...[
        const SizedBox(height: 12),
        Text('${data['amount_ada'] ?? data['amount'] ?? '—'} ADA', style: TextStyle(color: foreground, fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: QrImageView(data: (data['address'] ?? '').toString(), version: QrVersions.auto, size: 210, backgroundColor: Colors.white)),
        const SizedBox(height: 10),
        SelectableText((data['address'] ?? '').toString(), textAlign: TextAlign.center, style: TextStyle(color: foreground, fontSize: 12)),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: () async { await Clipboard.setData(ClipboardData(text: (data['address'] ?? '').toString())); if (mounted) _message(tr('Cardano адресът е копиран.', 'Cardano address copied.')); }, icon: const Icon(Icons.copy), label: Text(tr('Копирай ADA адреса', 'Copy ADA address'))),
        Text(tr('Мрежа: Cardano Preprod. Изпращай само тестови ADA. QR кодът съдържа адреса; провери сумата отделно преди изпращане.', 'Network: Cardano Preprod. Send test ADA only. The QR contains the address; verify the amount separately before sending.'), textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 11.5, height: 1.35)),
      ],
      if (['ETH','SOL'].contains(data['asset']?.toString()) && !expired) ...[
        const SizedBox(height: 12),
        Text('${data['amount'] ?? '—'} ${data['asset']}', style: TextStyle(color: foreground, fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: QrImageView(data: (data['address'] ?? '').toString(), version: QrVersions.auto, size: 210, backgroundColor: Colors.white)),
        const SizedBox(height: 10),
        SelectableText((data['address'] ?? '').toString(), textAlign: TextAlign.center, style: TextStyle(color: foreground, fontSize: 12)),
        OutlinedButton.icon(onPressed: () async { await Clipboard.setData(ClipboardData(text: (data['address'] ?? '').toString())); if (mounted) _message(tr('Адресът е копиран.', 'Address copied.')); }, icon: const Icon(Icons.copy), label: Text(tr('Копирай адреса', 'Copy address'))),
        Text('Мрежа: ${data['network']}. Изпращай само тестови средства в тази мрежа.', textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 11.5, height: 1.35)),
      ],
      if (data['asset']?.toString() != 'ADA' && !settled && !expired && uri != null && uri.scheme == 'https') Padding(padding: const EdgeInsets.only(top: 12), child: SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => launchUrl(uri, mode: LaunchMode.externalApplication), icon: const Icon(Icons.open_in_new), label: Text(tr('Отвори защитеното BTC плащане', 'Open secure BTC checkout'))))),
      if (!['ADA','ETH','SOL'].contains(data['asset']?.toString()) && !settled && !expired) Padding(padding: const EdgeInsets.only(top: 8), child: Text(tr('QR кодът, точната BTC сума и адресът се показват в защитената BTCPay страница. Статусът се обновява автоматично на всеки 12 секунди.', 'The QR code, exact BTC amount and address are shown on the secure BTCPay page. Status refreshes automatically every 12 seconds.'), textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 11.5, height: 1.35))),
    ]));
  }

  Widget _historySection() => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: dark ? const Color(0xFF101F38) : Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: dark ? const Color(0xFF263B5A) : const Color(0xFFDCE4EF)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(tr('История на криптоплащанията', 'Crypto payment history'), style: TextStyle(color: foreground, fontSize: 16, fontWeight: FontWeight.w900))),
        IconButton(onPressed: historyLoading ? null : _loadPaymentHistory, tooltip: tr('Обнови историята', 'Refresh history'), icon: historyLoading ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh)),
      ]),
      if (historyError != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(historyError!, style: const TextStyle(color: Color(0xFFFF647C), fontSize: 11.5))),
      if (historyLoading && paymentHistory.isEmpty) const LinearProgressIndicator(minHeight: 2),
      if (!historyLoading && paymentHistory.isEmpty && historyError == null)
        Text(tr('Все още няма криптоплащания по този профил.', 'There are no crypto payments for this account yet.'), style: TextStyle(color: muted, fontSize: 12)),
      ...paymentHistory.map((item) {
        final asset = (item['asset'] ?? '').toString().toUpperCase();
        final orderNo = (item['order_number'] ?? item['order_id'] ?? '').toString();
        final status = (item['status'] ?? 'unknown').toString();
        final state = ['ADA','ETH','SOL'].contains(asset) ? status : _paymentState(item);
        final amount = (item['expected_amount'] ?? item['total'] ?? '—').toString();
        final currency = (item['currency'] ?? (['ADA','ETH','SOL'].contains(asset) ? asset : 'EUR')).toString();
        final txCount = item['transactions'] is List ? (item['transactions'] as List).length : 0;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(backgroundColor: asset == 'ADA' ? const Color(0xFF3978F6).withValues(alpha: .15) : asset == 'ETH' ? const Color(0xFF8A9CFF).withValues(alpha: .15) : asset == 'SOL' ? const Color(0xFF8B6CFF).withValues(alpha: .15) : const Color(0xFFF7931A).withValues(alpha: .15), child: Text(asset == 'ADA' ? '₳' : asset == 'ETH' ? '◆' : asset == 'SOL' ? '◎' : '₿', style: TextStyle(color: asset == 'ADA' ? const Color(0xFF3978F6) : asset == 'ETH' ? const Color(0xFF8A9CFF) : asset == 'SOL' ? const Color(0xFF8B6CFF) : const Color(0xFFF7931A), fontWeight: FontWeight.w900))),
          title: Text('#$orderNo · $asset', style: TextStyle(color: foreground, fontWeight: FontWeight.w800, fontSize: 13)),
          subtitle: Text('${_statusLabel(state, status)}${txCount > 0 ? ' · $txCount ${tr('транзакции', 'transactions')}' : ''}', style: TextStyle(color: muted, fontSize: 11)),
          trailing: Text('$amount $currency', style: TextStyle(color: foreground, fontSize: 11, fontWeight: FontWeight.w800)),
          onTap: () => _openHistoryItem(item),
        );
      }),
    ]),
  );

  int _lovelaceValue(dynamic value) => int.tryParse((value ?? '0').toString()) ?? 0;

  String _formatLovelace(dynamic value) {
    final amount = _lovelaceValue(value);
    final whole = amount ~/ 1000000;
    final fraction = (amount % 1000000).toString().padLeft(6, '0');
    return '$whole.$fraction';
  }

  Widget _amountRow(String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [Expanded(child: Text(label, style: TextStyle(color: muted, fontSize: 12))), Text(value, style: TextStyle(color: foreground, fontSize: 12, fontWeight: FontWeight.w800))]));

  String _statusLabel(String paymentState, String rawStatus) {
    switch (paymentState.toLowerCase()) {
      case 'paid': return tr('Плащането е потвърдено', 'Payment confirmed');
      case 'testnet_verified': return tr('Testnet трансферът е потвърден · без settlement', 'Testnet transfer verified · no settlement');
      case 'awaiting_payment': return tr('Очаква се тестов трансфер', 'Awaiting test transfer');
      case 'overpaid': return tr('Надплатена сума – необходима е проверка', 'Overpayment – review required');
      case 'partial': return tr('Получено е частично плащане', 'Partial payment received');
      case 'partial_expired': return tr('Изтекла фактура с частично плащане', 'Expired invoice with partial payment');
      case 'late_payment_review': return tr('Късно плащане – необходима е проверка', 'Late payment – review required');
      case 'manual_review': return tr('Необходима е ръчна проверка – не изпращай повторно', 'Manual review required – do not resend');
      case 'confirming': return tr('Транзакцията е открита – изчакват се потвърждения', 'Transaction detected – awaiting confirmations');
      case 'expired': return tr('Платежната заявка е изтекла или невалидна', 'Payment request expired or invalid');
      case 'pending': return tr('Очаква се плащане', 'Awaiting payment');
      case 'unknown': return tr('Статусът не е потвърден – не изпращай повторно; обнови ръчно или се свържи с PCWork', 'Status is unconfirmed – do not resend; refresh manually or contact PCWork');
      default: return rawStatus.isNotEmpty ? rawStatus : tr('Статусът се проверява', 'Checking payment status');
    }
  }

  Widget _securityNote() => Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: dark ? const Color(0xFF0D1A30) : const Color(0xFFEAF0F7), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [const Icon(Icons.shield_outlined, color: _cyan), const SizedBox(width: 8), Expanded(child: Text(tr('Сигурност на плащанията', 'Payment security'), style: TextStyle(color: foreground, fontWeight: FontWeight.w800)))]), const SizedBox(height: 7), Text(tr('PCWork никога няма да поиска seed фраза или частен ключ. Проверявай внимателно мрежата и адреса преди изпращане. Трансферите в блокчейн обикновено са необратими. Плащане се признава само след независимо сървърно потвърждение.', 'PCWork will never ask for your seed phrase or private key. Carefully verify the network and address before sending. Blockchain transfers are generally irreversible. A payment is accepted only after independent server-side confirmation.'), style: TextStyle(color: muted, fontSize: 11.5, height: 1.45))]));
}
