import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key, required this.api, required this.tokenProvider, required this.english});
  final ApiService api;
  final Future<String?> Function() tokenProvider;
  final bool english;

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  final TextEditingController search = TextEditingController();
  final Map<String, int> cart = {};
  final Map<String, Map<String, dynamic>> cartProducts = {};
  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> categories = [];
  bool loading = true;
  bool placingOrder = false;
  String? error;
  int category = 0;

  String tr(String bg, String en) => widget.english ? en : bg;
  String get currencyCode => products.isNotEmpty ? (products.first['currency']?.toString() ?? 'BGN') : 'BGN';
  int get cartCount => cart.values.fold(0, (a, b) => a + b);
  double get cartTotal => cart.entries.fold<double>(0, (sum, entry) => sum + ((double.tryParse('${cartProducts[entry.key]?['price'] ?? 0}') ?? 0) * entry.value));

  String money(dynamic value) => '${value ?? '0.00'} $currencyCode';

  @override
  void initState() {
    super.initState();
    _restoreCart();
    _load();
  }

  Future<void> _restoreCart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('pcwork_shop_cart_v33');
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final row in decoded.whereType<Map>()) {
        final product = Map<String, dynamic>.from(row['product'] as Map);
        final key = '${row['key']}';
        final quantity = (row['quantity'] as num?)?.toInt() ?? 1;
        if (quantity > 0) { cart[key] = quantity; cartProducts[key] = product; }
      }
      if (mounted) setState(() {});
    } catch (_) { /* Ignore a damaged local cart and allow a fresh one. */ }
  }

  Future<void> _saveCart() async {
    final prefs = await SharedPreferences.getInstance();
    final rows = cart.entries.map((e) => {'key': e.key, 'quantity': e.value, 'product': cartProducts[e.key]}).toList();
    await prefs.setString('pcwork_shop_cart_v33', jsonEncode(rows));
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        widget.api.getShopProducts(search: search.text.trim(), categoryId: category),
        widget.api.getShopCategories(),
      ]);
      if (!mounted) return;
      setState(() {
        products = results[0] as List<Map<String, dynamic>>;
        categories = results[1] as List<Map<String, dynamic>>;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _message(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _add(Map<String, dynamic> product) {
    final productId = (product['id'] as num).toInt();
    final variationId = (product['selected_variation_id'] as num?)?.toInt() ?? 0;
    final key = '$productId:$variationId';
    final cartProduct = Map<String, dynamic>.from(product)..['cart_key'] = key;
    setState(() {
      cart[key] = (cart[key] ?? 0) + 1;
      cartProducts[key] = cartProduct;
    });
    _saveCart();
    _message(tr('Добавено в количката', 'Added to cart'));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('PCWORK STORE', style: TextStyle(color: Color(0xFF21D4D8), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                    Text(tr('Технологии и аксесоари', 'Tech & accessories'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              IconButton(onPressed: _orders, tooltip: tr('Моите поръчки', 'My orders'), icon: const Icon(Icons.receipt_long_outlined)),
              Badge(
                label: Text('$cartCount'),
                isLabelVisible: cartCount > 0,
                child: IconButton(onPressed: _showCart, icon: const Icon(Icons.shopping_bag_outlined, color: Color(0xFF21D4D8))),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: search,
            onSubmitted: (_) {
              category = 0;
              _load();
            },
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: tr('Търси продукти...', 'Search products...'),
              suffixIcon: IconButton(
                onPressed: () {
                  search.clear();
                  category = 0;
                  _load();
                },
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        ),
        if (categories.isNotEmpty) _categoryChips(),
        Expanded(child: _productBody()),
      ],
    );
  }

  Widget _categoryChips() {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(tr('Всички', 'All')),
              selected: category == 0,
              onSelected: (_) {
                setState(() => category = 0);
                _load();
              },
            ),
          ),
          ...categories.map((c) {
            final id = (c['id'] as num).toInt();
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text('${c['name']}'),
                selected: category == id,
                onSelected: (_) {
                  setState(() => category = id);
                  _load();
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _productBody() {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 42, color: Colors.orangeAccent),
              const SizedBox(height: 12),
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: Text(tr('Опитай отново', 'Retry'))),
            ],
          ),
        ),
      );
    }
    if (products.isEmpty) return Center(child: Text(tr('Няма намерени продукти.', 'No products found.')));
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: .66),
        itemCount: products.length,
        itemBuilder: (ctx, i) => _productCard(products[i]),
      ),
    );
  }

  Widget _productCard(Map<String, dynamic> product) {
    final imageUrl = product['image']?.toString() ?? '';
    final canBuy = product['purchasable'] == true || (product['type'] == 'variable' && (product['variations'] is List) && (product['variations'] as List).isNotEmpty);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showProduct(product),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                color: const Color(0xFF0D1724),
                child: imageUrl.isNotEmpty
                    ? Image.network(imageUrl, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.devices_other, size: 54, color: Color(0xFF21D4D8)))
                    : const Icon(Icons.devices_other, size: 54, color: Color(0xFF21D4D8)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 2),
              child: Text('${product['name']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(money(product['price']), style: const TextStyle(color: Color(0xFF21D4D8), fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 7),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: canBuy ? () { if (product['type'] == 'variable') { _showProduct(product); } else { _add(product); } } : null,
                  icon: const Icon(Icons.add_shopping_cart, size: 16),
                  label: Text(product['type'] == 'variable' && canBuy ? tr('Избери опции', 'Choose options') : canBuy ? tr('Добави', 'Add') : tr('Изчерпан', 'Unavailable'), style: const TextStyle(fontSize: 11)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showProduct(Map<String, dynamic> product) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111B29),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((product['image']?.toString().isNotEmpty ?? false))
                Center(child: Image.network(product['image'].toString(), height: 190, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.devices_other, size: 80))),
              const SizedBox(height: 12),
              Text('${product['name']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(money(product['price']), style: const TextStyle(color: Color(0xFF21D4D8), fontSize: 19, fontWeight: FontWeight.w800)),
              if ((product['description'] ?? '').toString().isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 10), child: Text(product['description'].toString())),
              const SizedBox(height: 14),
              if (product['type'] == 'variable') ...[
                const SizedBox(height: 8),
                Text(tr('Избери вариант', 'Choose a variation'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                ...((product['variations'] as List? ?? []).whereType<Map>().map((raw) {
                  final variation = Map<String, dynamic>.from(raw);
                  final attrs = variation['attributes'] is Map ? (variation['attributes'] as Map).entries.map((e) => '${e.value}').join(' · ') : '';
                  final available = variation['purchasable'] == true && variation['in_stock'] == true;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: SizedBox(width: double.infinity, child: OutlinedButton(
                      onPressed: available ? () { final selected = Map<String, dynamic>.from(product); selected['selected_variation_id'] = variation['id']; selected['price'] = variation['price']; selected['variation_label'] = attrs; _add(selected); Navigator.pop(ctx); } : null,
                      child: Text('${attrs.isEmpty ? tr('Вариант', 'Variation') : attrs} · ${variation['price']} $currencyCode${available ? '' : ' · ${tr('Изчерпан', 'Unavailable')}'}'),
                    )),
                  );
                })),
              ] else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: product['purchasable'] == true ? () { _add(product); Navigator.pop(ctx); } : null,
                    icon: const Icon(Icons.add_shopping_cart),
                    label: Text(tr('Добави в количката', 'Add to cart')),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _orders() async {
    final token = await widget.tokenProvider();
    if (token == null) {
      _message(tr('Влезте в профила си, за да видите поръчките.', 'Sign in to view your orders.'));
      return;
    }
    try {
      final rows = await widget.api.getShopOrders(token);
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF111B29),
        builder: (_) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * .72,
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Text(tr('Моите поръчки', 'My orders'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (rows.isEmpty) Text(tr('Все още нямате поръчки.', 'You have no orders yet.')),
                ...rows.map((o) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.receipt_long, color: Color(0xFF21D4D8)),
                        title: Text('#${o['number'] ?? o['id']}'),
                        subtitle: Text('${o['date'] ?? ''} · ${o['status'] ?? ''}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _orderDetails(token, o),
                      ),
                    )),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      _message('$e');
    }
  }

  Future<void> _orderDetails(String token, Map<String, dynamic> order) async {
    try {
      final id = (order['id'] as num).toInt();
      final detail = await widget.api.getShopOrder(token, id);
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context, isScrollControlled: true, backgroundColor: const Color(0xFF111B29),
        builder: (_) => SafeArea(child: Padding(
          padding: const EdgeInsets.all(18),
          child: ListView(shrinkWrap: true, children: [
            Text(tr('Поръчка', 'Order') + ' #${detail['number'] ?? id}', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('${detail['date'] ?? ''} · ${detail['status'] ?? ''}'),
            const SizedBox(height: 8),
            ...(detail['items'] is List ? (detail['items'] as List).whereType<Map>().map((line) => ListTile(
              contentPadding: EdgeInsets.zero, title: Text('${line['name'] ?? ''}'),
              subtitle: Text('${line['quantity'] ?? 1} × ${line['price'] ?? ''}'),
              trailing: Text('${line['total'] ?? ''}'),
            )) : <Widget>[]),
            const Divider(),
            ListTile(title: Text(tr('Общо', 'Total')), trailing: Text('${detail['total'] ?? order['total'] ?? ''} ${detail['currency'] ?? currencyCode}', style: const TextStyle(color: Color(0xFF21D4D8), fontWeight: FontWeight.bold))),
            if ((detail['payment_url'] ?? '').toString().isNotEmpty)
              FilledButton.icon(onPressed: () => widget.api.openExternal(detail['payment_url'].toString()), icon: const Icon(Icons.payment), label: Text(tr('Плащане', 'Payment'))),
          ]),
        )),
      );
    } catch (e) { _message('$e'); }
  }

  void _showCart() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111B29),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(tr('Количка', 'Shopping cart'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold))),
                    Text('${cartTotal.toStringAsFixed(2)} $currencyCode', style: const TextStyle(color: Color(0xFF21D4D8), fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 10),
                if (cart.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(tr('Количката е празна.', 'Your cart is empty.'))),
                ...cart.entries.map((entry) {
                  final product = cartProducts[entry.key] ?? {'name': 'Product', 'price': '0'};
                  return ListTile(
                    title: Text('${product['name']}'),
                    subtitle: Text('${product['variation_label'] ?? ''} ${product['price']} × ${entry.value}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () {
                            setSheet(() {
                              if (entry.value <= 1) {
                                cart.remove(entry.key);
                                cartProducts.remove(entry.key);
                              } else {
                                cart[entry.key] = entry.value - 1;
                              }
                            });
                            setState(() {});
                            _saveCart();
                          },
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text('${cart[entry.key] ?? 0}'),
                        IconButton(
                          onPressed: () {
                            setSheet(() => cart[entry.key] = entry.value + 1);
                            setState(() {});
                            _saveCart();
                          },
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: cart.isEmpty || placingOrder
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            _checkout();
                          },
                    icon: const Icon(Icons.lock_outline),
                    label: Text(placingOrder ? tr('Обработка...', 'Processing...') : tr('Към поръчка', 'Checkout')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _checkout() async {
    final token = await widget.tokenProvider();
    if (token == null) {
      _message(tr('За поръчка е необходимо да влезете в профила си.', 'Please sign in to place an order.'));
      return;
    }
    if (cart.isEmpty) return;

    final name = TextEditingController();
    final email = TextEditingController();
    final phone = TextEditingController();
    final address = TextEditingController();
    final city = TextEditingController();
    final postcode = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151F2E),
        title: Text(tr('Данни за поръчката', 'Order details')),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _checkoutField(name, tr('Име и фамилия', 'Full name')),
                  _checkoutField(email, 'Email', keyboard: TextInputType.emailAddress),
                  _checkoutField(phone, tr('Телефон', 'Phone'), keyboard: TextInputType.phone),
                  _checkoutField(address, tr('Адрес за доставка', 'Delivery address')),
                  _checkoutField(city, tr('Град', 'City')),
                  _checkoutField(postcode, tr('Пощенски код', 'Postcode')),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Отказ', 'Cancel'))),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: Text(tr('Продължи', 'Continue')),
          ),
        ],
      ),
    );

    if (accepted != true) return;
    setState(() => placingOrder = true);
    try {
      final result = await widget.api.createShopOrder(
        token,
        items: cart.entries.map((e) { final p = cartProducts[e.key] ?? {}; return {'product_id': p['id'], 'variation_id': p['selected_variation_id'] ?? 0, 'quantity': e.value}; }).toList(),
        billing: {
          'first_name': name.text.trim(), 'last_name': '', 'email': email.text.trim(),
          'phone': phone.text.trim(), 'address_1': address.text.trim(), 'city': city.text.trim(),
          'postcode': postcode.text.trim(), 'country': 'BG',
        },
        shipping: {
          'first_name': name.text.trim(), 'last_name': '', 'address_1': address.text.trim(),
          'city': city.text.trim(), 'postcode': postcode.text.trim(), 'country': 'BG',
        },
      );
      if (!mounted) return;
      setState(() { cart.clear(); cartProducts.clear(); });
      await _saveCart();
      _message(tr('Поръчката е създадена. Отварям страницата за плащане.', 'Order created. Opening payment page.'));
      final paymentUrl = result['payment_url']?.toString() ?? '';
      if (paymentUrl.isNotEmpty) await widget.api.openExternal(paymentUrl);
    } catch (e) {
      _message('$e');
    } finally {
      if (mounted) setState(() => placingOrder = false);
    }
  }

  Widget _checkoutField(TextEditingController controller, String label, {TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label),
        validator: (value) => (value == null || value.trim().isEmpty) ? tr('Задължително поле', 'Required field') : null,
      ),
    );
  }
}
