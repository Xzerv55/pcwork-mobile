import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';

class CryptoPaymentsScreen extends StatefulWidget {
  const CryptoPaymentsScreen({super.key, required this.api, required this.tokenProvider, required this.english, required this.isDarkTheme});
  final ApiService api;
  final Future<String?> Function() tokenProvider;
  final bool english;
  final bool isDarkTheme;

  @override
  State<CryptoPaymentsScreen> createState() => _CryptoPaymentsScreenState();
}

class _CryptoPaymentsScreenState extends State<CryptoPaymentsScreen> {
  static const _cyan = Color(0xFF21D4D8);
  static const _assets = <String, Map<String, dynamic>>{
    'BTC': {'name': 'Bitcoin', 'icon': '₿', 'color': Color(0xFFF7931A)},
    'ETH': {'name': 'Ethereum', 'icon': '◆', 'color': Color(0xFF8A9CFF)},
    'SOL': {'name': 'Solana', 'icon': '◎', 'color': Color(0xFF8B6CFF)},
    'ADA': {'name': 'Cardano', 'icon': '₳', 'color': Color(0xFF3978F6)},
  };
  final orderIdController = TextEditingController();
  String selectedAsset = 'BTC';
  String? token;
  Map<String, dynamic>? serverStatus;
  Map<String, dynamic>? invoice;
  bool loading = true;
  bool creating = false;
  bool refreshing = false;
  String? error;
  Timer? pollTimer;

  bool get en => widget.english;
  bool get dark => widget.isDarkTheme;
  Color get foreground => dark ? Colors.white : const Color(0xFF172033);
  Color get muted => dark ? const Color(0xFFAFBED4) : const Color(0xFF68778B);
  String tr(String bg, String english) => en ? english : bg;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    pollTimer?.cancel();
    orderIdController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      token = await widget.tokenProvider();
      if (token == null || token!.isEmpty) {
        setState(() { loading = false; error = tr('Влезте в PCWork профила си, за да използвате криптоплащания.', 'Sign in to your PCWork account to use crypto payments.'); });
        return;
      }
      final result = await widget.api.getCryptoPaymentStatus(token!);
      if (!mounted) return;
      setState(() { serverStatus = result; loading = false; if (!supportedAssets.contains(selectedAsset) && supportedAssets.isNotEmpty) selectedAsset = supportedAssets.first; });
    } catch (e) {
      if (!mounted) return;
      setState(() { loading = false; error = _friendlyError(e); });
    }
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
    return raw;
  }

  bool get enabled => serverStatus?['enabled'] == true;
  List<String> get supportedAssets {
    final configured = serverStatus?['assets'];
    if (configured is List) return configured.map((e) => e.toString().toUpperCase()).where(_assets.containsKey).toList();
    return <String>[];
  }

  Future<void> _createInvoice() async {
    final id = int.tryParse(orderIdController.text.trim());
    if (id == null || id <= 0) {
      _message(tr('Въведете валиден номер на поръчка.', 'Enter a valid order number.'));
      return;
    }
    if (token == null || !enabled || creating) return;
    setState(() { creating = true; error = null; invoice = null; });
    try {
      final result = await widget.api.createCryptoPayment(token!, orderId: id, asset: selectedAsset);
      if (!mounted) return;
      final data = result['invoice'] is Map ? Map<String, dynamic>.from(result['invoice']) : result;
      final checkout = (data['checkout_link'] ?? '').toString();
      final invoiceId = (data['id'] ?? '').toString();
      final checkoutUri = Uri.tryParse(checkout);
      if (invoiceId.isEmpty || checkoutUri == null || checkoutUri.scheme != 'https' || checkoutUri.host.isEmpty) {
        throw Exception(tr('Сървърът не върна валидна защитена BTCPay платежна страница.', 'The server did not return a valid secure BTCPay checkout page.'));
      }
      setState(() => invoice = data);
      _startPolling();
      final opened = await launchUrl(checkoutUri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) _message(tr('Не успяхме да отворим BTCPay. Използвай бутона „Отвори плащането“.', 'Could not open BTCPay. Use the Open payment button.'));
    } catch (e) {
      if (mounted) setState(() => error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => creating = false);
    }
  }

  void _startPolling() {
    pollTimer?.cancel();
    pollTimer = Timer.periodic(const Duration(seconds: 12), (_) => _refreshInvoice());
  }

  Future<void> _refreshInvoice() async {
    final current = invoice;
    final id = current?['id']?.toString();
    if (id == null || id.isEmpty || token == null) return;
    try {
      final result = await widget.api.getCryptoPayment(token!, id);
      final data = result['invoice'] is Map ? Map<String, dynamic>.from(result['invoice']) : result;
      if (!mounted) return;
      setState(() => invoice = {...?invoice, ...data});
      final status = (data['status'] ?? '').toString().toLowerCase();
      if (['settled', 'expired', 'invalid'].contains(status)) pollTimer?.cancel();
    } catch (_) {
      // A temporary network error must not change a payment to failed.
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
              if (error != null) _notice(error!, isError: true),
              if (!enabled) ...[
                _notice((serverStatus?['message'] ?? tr('Сървърната услуга е изключена или все още не е инсталирана. Не се показват фиктивни адреси или потвърждения.', 'The server service is disabled or not installed yet. No fake addresses or confirmations are shown.')).toString(), isError: false),
                const SizedBox(height: 12),
                _securityNote(),
              ] else ...[
                _assetPicker(),
                const SizedBox(height: 14),
                _orderForm(),
                if (invoice != null) ...[const SizedBox(height: 16), _invoiceCard()],
                const SizedBox(height: 14),
                _securityNote(),
              ],
            ]),
    );
  }

  Widget _hero() => Container(
    padding: const EdgeInsets.all(19),
    decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF102A50), Color(0xFF15204A), Color(0xFF30205C)]), borderRadius: BorderRadius.circular(25), border: Border.all(color: _cyan.withValues(alpha: .55)), boxShadow: [BoxShadow(color: _cyan.withValues(alpha: .12), blurRadius: 24, offset: const Offset(0, 8))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [Icon(Icons.currency_bitcoin_rounded, color: _cyan, size: 25), SizedBox(width: 8), Text('PCWORK CRYPTO', style: TextStyle(color: _cyan, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.6))]),
      const SizedBox(height: 10),
      Text(tr('Сигурно BTC плащане към PCWork', 'Secure BTC payment to PCWork'), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, height: 1.15)),
      const SizedBox(height: 7),
      Text(tr('Bitcoin · BTCPay Hosted Checkout · автоматично потвърждение', 'Bitcoin · BTCPay Hosted Checkout · automatic confirmation'), style: const TextStyle(color: Color(0xFFD4E5FF), fontSize: 12, height: 1.35)),
    ]),
  );

  Widget _notice(String text, {required bool isError}) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: (isError ? const Color(0xFFFF647C) : const Color(0xFFFFC857)).withValues(alpha: .10), borderRadius: BorderRadius.circular(16), border: Border.all(color: (isError ? const Color(0xFFFF647C) : const Color(0xFFFFC857)).withValues(alpha: .5))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(isError ? Icons.error_outline : Icons.info_outline, color: isError ? const Color(0xFFFF647C) : const Color(0xFFFFC857)), const SizedBox(width: 10), Expanded(child: Text(text, style: TextStyle(color: foreground, fontSize: 12.5, height: 1.4))) ]),
  );

  Widget _assetPicker() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(tr('Избери криптовалута', 'Choose cryptocurrency'), style: TextStyle(color: foreground, fontSize: 16, fontWeight: FontWeight.w800)),
    const SizedBox(height: 10),
    ...supportedAssets.map((symbol) {
      final asset = _assets[symbol]!;
      final selected = selectedAsset == symbol;
      final color = asset['color'] as Color;
      return Padding(padding: const EdgeInsets.only(bottom: 8), child: Material(color: selected ? color.withValues(alpha: .13) : (dark ? const Color(0xFF101F38) : Colors.white), borderRadius: BorderRadius.circular(16), child: InkWell(borderRadius: BorderRadius.circular(16), onTap: () => setState(() => selectedAsset = symbol), child: Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: selected ? color : (dark ? const Color(0xFF263B5A) : const Color(0xFFDCE4EF)), width: selected ? 1.5 : 1)), child: Row(children: [Container(width: 40, height: 40, alignment: Alignment.center, decoration: BoxDecoration(color: color.withValues(alpha: .16), shape: BoxShape.circle), child: Text(asset['icon'].toString(), style: TextStyle(color: color, fontSize: 23, fontWeight: FontWeight.w900))), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(asset['name'].toString(), style: TextStyle(color: foreground, fontWeight: FontWeight.w800)), Text(symbol, style: TextStyle(color: muted, fontSize: 12))])), Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? color : muted)])))));
    }),
  ]);

  Widget _orderForm() => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: dark ? const Color(0xFF101F38) : Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: dark ? const Color(0xFF263B5A) : const Color(0xFFDCE4EF))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(tr('Плащане на поръчка', 'Pay an order'), style: TextStyle(color: foreground, fontSize: 16, fontWeight: FontWeight.w800)),
    const SizedBox(height: 6),
    Text(tr('Въведи номера на поръчката. Сумата се определя и валидира от PCWork сървъра, а не от приложението.', 'Enter the order number. The amount is determined and validated by the PCWork server, not by the app.'), style: TextStyle(color: muted, fontSize: 12, height: 1.35)),
    const SizedBox(height: 12),
    TextField(controller: orderIdController, keyboardType: TextInputType.number, style: TextStyle(color: foreground), decoration: InputDecoration(labelText: tr('Номер на поръчка', 'Order number'), prefixIcon: const Icon(Icons.receipt_long_outlined), filled: true, fillColor: dark ? const Color(0xFF09162A) : const Color(0xFFF5F7FA), border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)))),
    const SizedBox(height: 12),
    SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: creating ? null : _createInvoice, icon: creating ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.qr_code_2), label: Text(creating ? tr('Създаване...', 'Creating...') : tr('Генерирай адрес и QR код', 'Generate address and QR code')), style: FilledButton.styleFrom(backgroundColor: const Color(0xFF087BFF), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)))),
  ]));

  Widget _invoiceCard() {
    final data = invoice!;
    final status = (data['status'] ?? 'new').toString();
    final checkout = (data['checkout_link'] ?? '').toString();
    final expires = int.tryParse((data['expires_at'] ?? '').toString()) ?? 0;
    final remaining = expires > 0 ? expires - DateTime.now().millisecondsSinceEpoch ~/ 1000 : 0;
    final settled = status.toLowerCase() == 'settled';
    final expired = ['expired', 'invalid'].contains(status.toLowerCase());
    final uri = Uri.tryParse(checkout);
    return Container(padding: const EdgeInsets.all(17), decoration: BoxDecoration(color: dark ? const Color(0xFF101F38) : Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: settled ? const Color(0xFF20E39A) : const Color(0xFF168BFF).withValues(alpha: .55))), child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Text(tr('BTC платежна заявка', 'BTC payment request'), style: TextStyle(color: foreground, fontSize: 17, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      Text('Bitcoin (BTC)', style: const TextStyle(color: _cyan, fontSize: 22, fontWeight: FontWeight.w900)),
      if (remaining > 0 && !settled && !expired) Text('${tr('Оставащо време', 'Time remaining')}: ${remaining ~/ 60} мин. ${remaining % 60} сек.', style: TextStyle(color: muted, fontSize: 12)),
      const SizedBox(height: 12),
      Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: (settled ? const Color(0xFF20E39A) : expired ? const Color(0xFFFF647C) : const Color(0xFFFFC857)).withValues(alpha: .12), borderRadius: BorderRadius.circular(13)), child: Row(children: [Icon(settled ? Icons.verified : expired ? Icons.error_outline : Icons.hourglass_top, color: settled ? const Color(0xFF20E39A) : expired ? const Color(0xFFFF647C) : const Color(0xFFFFC857)), const SizedBox(width: 9), Expanded(child: Text(_statusLabel(status), style: TextStyle(color: foreground, fontWeight: FontWeight.w800, fontSize: 13)))])),
      if (!settled && !expired && uri != null && uri.scheme == 'https') Padding(padding: const EdgeInsets.only(top: 12), child: SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => launchUrl(uri, mode: LaunchMode.externalApplication), icon: const Icon(Icons.open_in_new), label: Text(tr('Отвори защитеното BTC плащане', 'Open secure BTC checkout'))))),
      if (!settled && !expired) Padding(padding: const EdgeInsets.only(top: 8), child: Text(tr('QR кодът, точната BTC сума, адресът и таймерът се показват в защитената страница на BTCPay. Статусът тук се обновява автоматично на всеки 12 секунди.', 'The QR code, exact BTC amount, address and countdown are displayed on the secure BTCPay page. Status here refreshes automatically every 12 seconds.'), textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 11.5, height: 1.35))),
    ]));
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'settled': case 'confirmed': case 'paid': case 'completed': return tr('Плащането е потвърдено', 'Payment confirmed');
      case 'confirming': case 'detected': case 'processing': return tr('Транзакцията е открита – изчакват се потвърждения', 'Transaction detected – awaiting confirmations');
      case 'expired': case 'invalid': return tr('Платежната заявка е изтекла или невалидна', 'Payment request expired or invalid');
      case 'underpaid': return tr('Получена е по-ниска сума', 'Underpayment received');
      case 'overpaid': return tr('Получена е по-висока сума', 'Overpayment received');
      case 'cancelled': return tr('Плащането е отменено', 'Payment cancelled');
      default: return tr('Очаква се плащане', 'Awaiting payment');
    }
  }

  Widget _securityNote() => Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: dark ? const Color(0xFF0D1A30) : const Color(0xFFEAF0F7), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [const Icon(Icons.shield_outlined, color: _cyan), const SizedBox(width: 8), Expanded(child: Text(tr('Сигурност на плащанията', 'Payment security'), style: TextStyle(color: foreground, fontWeight: FontWeight.w800)))]), const SizedBox(height: 7), Text(tr('PCWork никога няма да поиска seed фраза или частен ключ. Проверявай внимателно мрежата и адреса преди изпращане. Трансферите в блокчейн обикновено са необратими. Плащане се признава само след независимо сървърно потвърждение.', 'PCWork will never ask for your seed phrase or private key. Carefully verify the network and address before sending. Blockchain transfers are generally irreversible. A payment is accepted only after independent server-side confirmation.'), style: TextStyle(color: muted, fontSize: 11.5, height: 1.45))]));
}
