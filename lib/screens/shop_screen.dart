import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key, required this.api, required this.tokenProvider, required this.profileProvider, required this.english});
  final ApiService api;
  final Future<String?> Function() tokenProvider;
  final Future<AuthUser?> Function() profileProvider;
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
  bool categoriesLoaded = false;
  int _loadGeneration = 0;
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
    final generation = ++_loadGeneration;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final productRequest = widget.api.getShopProducts(search: search.text.trim(), categoryId: category);
      final categoryRequest = categoriesLoaded
          ? Future<List<Map<String, dynamic>>>.value(categories)
          : widget.api.getShopCategories();
      final results = await Future.wait<dynamic>([productRequest, categoryRequest]);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        products = results[0] as List<Map<String, dynamic>>;
        categories = results[1] as List<Map<String, dynamic>>;
        categoriesLoaded = true;
      });
    } catch (e) {
      if (mounted && generation == _loadGeneration) setState(() => error = e.toString());
    } finally {
      if (mounted && generation == _loadGeneration) setState(() => loading = false);
    }
  }

  void _message(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _add(Map<String, dynamic> product) {
    final productId = int.tryParse('${product['id']}') ?? 0;
    if (productId <= 0) return;
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
            final id = int.tryParse('${c['id']}') ?? 0;
            if (id <= 0) return const SizedBox.shrink();
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
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: .76),
        itemCount: products.length,
        itemBuilder: (ctx, i) => _productCard(products[i]),
      ),
    );
  }

  Widget _productCard(Map<String, dynamic> product) {
    final imageUrl = product['image']?.toString() ?? '';
    final canBuy = product['purchasable'] == true;
    final isVariable = product['type'] == 'variable';
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => _showProduct(product),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 112,
              width: double.infinity,
              child: imageUrl.isNotEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(8),
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.contain,
                          cacheWidth: 480,
                          filterQuality: FilterQuality.low,
                          errorBuilder: (_, __, ___) => const Icon(Icons.devices_other, size: 42, color: Color(0xFF21D4D8)),
                          loadingBuilder: (context, child, progress) => progress == null
                              ? child
                              : const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                        ),
                      )
                    : const Center(child: Icon(Icons.devices_other, size: 42, color: Color(0xFF21D4D8))),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text('${product['name']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, height: 1.2, fontWeight: FontWeight.w700))),
                    const SizedBox(height: 4),
                    Text(money(product['price']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Color(0xFF21D4D8), fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 34,
                      width: double.infinity,
                      child: FilledButton.tonal(
                        onPressed: canBuy ? () { if (isVariable) { _showProduct(product); } else { _add(product); } } : null,
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), visualDensity: VisualDensity.compact),
                        child: Text(isVariable && canBuy ? tr('Избери вариант', 'Choose option') : canBuy ? tr('Добави', 'Add') : tr('Изчерпан', 'Unavailable'), maxLines: 1, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
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
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .82),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((product['image']?.toString().isNotEmpty ?? false))
                Center(child: Image.network(product['image'].toString(), height: 190, cacheWidth: 600, filterQuality: FilterQuality.low, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.devices_other, size: 80))),
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
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: widget.api.getShopProductVariations(int.tryParse('${product['id']}') ?? 0),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()));
                    if (snapshot.hasError) return Text('${tr('Вариантите не могат да се заредят:', 'Could not load options:')} ${snapshot.error}');
                    final variations = snapshot.data ?? const <Map<String, dynamic>>[];
                    if (variations.isEmpty) return Text(tr('Няма налични варианти.', 'No available options.'));
                    return Column(children: variations.map((variation) {
                      final attrs = variation['attributes'] is Map ? (variation['attributes'] as Map).entries.map((e) => '${e.value}').where((v) => v.isNotEmpty).join(' · ') : '';
                      final available = variation['purchasable'] == true && variation['in_stock'] == true;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: SizedBox(width: double.infinity, child: OutlinedButton(
                          onPressed: available ? () { final selected = Map<String, dynamic>.from(product); selected['selected_variation_id'] = variation['id']; selected['price'] = variation['price']; selected['variation_label'] = attrs; _add(selected); Navigator.pop(ctx); } : null,
                          child: Text('${attrs.isEmpty ? tr('Вариант', 'Variation') : attrs} · ${variation['price']} $currencyCode${available ? '' : ' · ${tr('Изчерпан', 'Unavailable')}'}'),
                        )),
                      );
                    }).toList());
                  },
                ),
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
      ),
    );
  }

  Future<void> _orders() async {
    final token = await widget.tokenProvider();
    if (!mounted) return;
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
        backgroundColor: Theme.of(context).colorScheme.surface,
        builder: (sheetContext) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * .72,
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
            Text('${tr('Поръчка', 'Order')} #${detail['number'] ?? id}', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
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
      backgroundColor: Theme.of(context).colorScheme.surface,
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
                  final cartImage = (product['image'] ?? '').toString();
                  return ListTile(
                    leading: cartImage.isEmpty ? const SizedBox(width: 48, height: 48, child: Icon(Icons.devices_other)) : ClipRRect(borderRadius: BorderRadius.circular(8), child: Container(width: 48, height: 48, color: Colors.transparent, alignment: Alignment.center, child: Image.network(cartImage, fit: BoxFit.contain, filterQuality: FilterQuality.medium, errorBuilder: (_, __, ___) => const Icon(Icons.devices_other)))),
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
    if (!mounted) return;
    if (token == null) {
      _message(tr('За поръчка е необходимо да влезете в профила си.', 'Please sign in to place an order.'));
      return;
    }
    if (cart.isEmpty) return;

    AuthUser? profile;
    try { profile = await widget.profileProvider(); } catch (_) {}
    if (!mounted) return;
    final billing = profile?.billing ?? const <String, dynamic>{};
    final shipping = profile?.shipping ?? const <String, dynamic>{};
    final firstName = TextEditingController(text: (billing['first_name'] ?? '').toString());
    final lastName = TextEditingController(text: (billing['last_name'] ?? '').toString());
    final city = TextEditingController(text: (shipping['city'] ?? billing['city'] ?? '').toString());
    final address = TextEditingController(text: (shipping['address_1'] ?? billing['address_1'] ?? '').toString());
    final postcode = TextEditingController(text: (shipping['postcode'] ?? billing['postcode'] ?? '').toString());
    final phone = TextEditingController(text: (billing['phone'] ?? profile?.phone ?? '').toString());
    final email = profile?.email ?? '';
    final orderItems = cart.entries.map((e) { final p = cartProducts[e.key] ?? {}; return {'product_id': p['id'], 'variation_id': p['selected_variation_id'] ?? 0, 'quantity': e.value}; }).toList();
    List<Map<String, dynamic>> shippingRates = [];
    String selectedShippingRateId = '';
    bool loadingShippingRates = false;
    String? shippingRateError;
    if (city.text.trim().isNotEmpty && address.text.trim().isNotEmpty) {
      try {
        shippingRates = await widget.api.getShopShippingRates(token, items: orderItems, shipping: {'city': city.text.trim(), 'address_1': address.text.trim(), 'postcode': postcode.text.trim(), 'state': (shipping['state'] ?? billing['state'] ?? '').toString(), 'country': 'BG'});
        if (shippingRates.isNotEmpty) selectedShippingRateId = '${shippingRates.first['id']}';
      } catch (e) { shippingRateError = '$e'; }
    }
    if (!mounted) { for (final c in [firstName, lastName, city, address, postcode, phone]) { c.dispose(); } return; }
    final formKey = GlobalKey<FormState>();

    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: const Color(0xFF151F2E),
        title: Text(tr('Данни за поръчката', 'Order details')),
        content: SizedBox(
          width: MediaQuery.of(ctx).size.width < 700 ? double.maxFinite : 620,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _checkoutField(firstName, tr('Име *', 'First name *')),
                _checkoutField(lastName, tr('Фамилия *', 'Last name *')),
                _checkoutField(city, tr('Град/село *', 'City/village *'), onChanged: (_) => setDialogState(() { selectedShippingRateId = ''; shippingRates = []; })),
                _checkoutField(address, tr('Личен адрес или офис / Box на куриер *', 'Home address or courier office / Box *'), onChanged: (_) => setDialogState(() { selectedShippingRateId = ''; shippingRates = []; })),
                _checkoutField(postcode, tr('Пощенски код (ако е приложимо)', 'Postcode (if applicable)'), required: false, keyboard: TextInputType.number, onChanged: (_) => setDialogState(() { selectedShippingRateId = ''; shippingRates = []; })),
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerLeft, child: Text(tr('Метод за доставка от WooCommerce *', 'Shipping method from WooCommerce *'), style: const TextStyle(fontWeight: FontWeight.w700))),
                Align(alignment: Alignment.centerLeft, child: Text(tr('Опциите се зареждат според адреса и активните методи в магазина.', 'Options are loaded based on the address and active store methods.'), style: const TextStyle(fontSize: 11, color: Colors.white60))),
                Align(alignment: Alignment.centerLeft, child: TextButton.icon(
                  onPressed: loadingShippingRates ? null : () async {
                    setDialogState(() { loadingShippingRates = true; shippingRateError = null; });
                    try {
                      final rows = await widget.api.getShopShippingRates(token, items: orderItems, shipping: {'city': city.text.trim(), 'address_1': address.text.trim(), 'postcode': postcode.text.trim(), 'state': (shipping['state'] ?? billing['state'] ?? '').toString(), 'country': 'BG'});
                      setDialogState(() { shippingRates = rows; selectedShippingRateId = rows.isNotEmpty ? '${rows.first['id']}' : ''; if (rows.isEmpty) shippingRateError = tr('WooCommerce не върна активни методи за този адрес.', 'WooCommerce returned no active methods for this address.'); });
                    } catch (e) { setDialogState(() { shippingRates = []; selectedShippingRateId = ''; shippingRateError = '$e'; }); }
                    finally { setDialogState(() => loadingShippingRates = false); }
                  },
                  icon: loadingShippingRates ? const SizedBox(width:14,height:14,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.refresh_rounded, size:17),
                  label: Text(tr('Обнови методите', 'Refresh methods')),
                )),
                if (shippingRates.isNotEmpty) RadioGroup<String>(
                  groupValue: selectedShippingRateId,
                  onChanged: (value) => setDialogState(() => selectedShippingRateId = value ?? ''),
                  child: Column(mainAxisSize: MainAxisSize.min, children: shippingRates.map((rate) => RadioListTile<String>(
                    dense: true, contentPadding: EdgeInsets.zero, value: '${rate['id']}',
                    title: Text((rate['label'] ?? rate['method_id'] ?? '').toString()),
                    subtitle: Text((rate['formatted_cost'] ?? '${rate['cost'] ?? ''}').toString()),
                  )).toList()),
                ),
                if (shippingRateError != null) Align(alignment: Alignment.centerLeft, child: Text(shippingRateError!, style: const TextStyle(color: Colors.orange, fontSize: 11))),
                _checkoutField(phone, tr('Телефон *', 'Phone *'), keyboard: TextInputType.phone),
                TextFormField(
                  initialValue: email, readOnly: true,
                  decoration: InputDecoration(labelText: tr('Email *', 'Email *'), helperText: tr('Имейлът се взима автоматично от регистрацията и не може да се редактира.', 'Email is taken from your registration and cannot be edited.')),
                  validator: (value) => (value == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim())) ? tr('Невалиден регистрационен имейл.', 'Invalid registration email.') : null,
                ),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Отказ', 'Cancel'))),
          FilledButton(onPressed: () {
            if (formKey.currentState!.validate() && selectedShippingRateId.isNotEmpty) {
              Navigator.pop(ctx, true);
            } else {
              _message(tr('Обновете и изберете метод за доставка от WooCommerce.', 'Refresh and select a WooCommerce shipping method.'));
            }
          }, child: Text(tr('Продължи', 'Continue'))),
        ],
      )),
    );

    if (!mounted || accepted != true) { for (final c in [firstName, lastName, city, address, postcode, phone]) { c.dispose(); } return; }
    setState(() => placingOrder = true);
    final first = firstName.text.trim();
    final last = lastName.text.trim();
    final selectedAddress = address.text.trim();
    final selectedCity = city.text.trim();
    try {
      final result = await widget.api.createShopOrder(
        token,
        items: orderItems,
        billing: {
          'first_name': first, 'last_name': last, 'email': email,
          'phone': phone.text.trim(), 'address_1': selectedAddress, 'city': selectedCity, 'postcode': postcode.text.trim(),
          'state': (billing['state'] ?? '').toString(), 'country': 'BG',
        },
        shipping: {
          'first_name': first, 'last_name': last, 'address_1': selectedAddress,
          'city': selectedCity, 'postcode': postcode.text.trim(), 'state': (shipping['state'] ?? billing['state'] ?? '').toString(), 'country': 'BG',
        },
        shippingRateId: selectedShippingRateId,
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
      for (final c in [firstName, lastName, city, address, postcode, phone]) { c.dispose(); }
    }
  }

  Widget _checkoutField(TextEditingController controller, String label, {TextInputType? keyboard, bool required = true, ValueChanged<String>? onChanged}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboard,
        onChanged: onChanged,
        decoration: InputDecoration(labelText: label),
        validator: (value) => required && (value == null || value.trim().isEmpty) ? tr('Задължително поле', 'Required field') : null,
      ),
    );
  }
}
