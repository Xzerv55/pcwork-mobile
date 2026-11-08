import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key, required this.api, required this.tokenProvider, required this.profileProvider, required this.english, this.notificationOrderId, this.openOrdersOnEntry = false, this.onNotificationHandled});
  final ApiService api;
  final Future<String?> Function() tokenProvider;
  final Future<AuthUser?> Function() profileProvider;
  final bool english;
  final int? notificationOrderId;
  final bool openOrdersOnEntry;
  final VoidCallback? onNotificationHandled;

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
  int? _handledNotificationOrderId;
  bool _handledOrdersEntry = false;

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleNotificationIntent());
  }

  @override
  void didUpdateWidget(covariant ShopScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.notificationOrderId == null) _handledNotificationOrderId = null;
    if (!widget.openOrdersOnEntry) _handledOrdersEntry = false;
    if (oldWidget.notificationOrderId != widget.notificationOrderId ||
        oldWidget.openOrdersOnEntry != widget.openOrdersOnEntry) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleNotificationIntent());
    }
  }

  Future<void> _handleNotificationIntent() async {
    final orderId = widget.notificationOrderId;
    if (orderId != null && orderId > 0 && orderId != _handledNotificationOrderId) {
      _handledNotificationOrderId = orderId;
      try {
        final token = await widget.tokenProvider();
        if (token != null && token.isNotEmpty && mounted) await _orderDetails(token, {'id': orderId});
      } catch (e) {
        if (mounted) _message('${tr('Поръчката не може да бъде отворена:', 'Could not open order:')} $e');
      } finally {
        widget.onNotificationHandled?.call();
      }
      return;
    }
    if (widget.openOrdersOnEntry && !_handledOrdersEntry) {
      _handledOrdersEntry = true;
      await _orders();
      widget.onNotificationHandled?.call();
    }
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

  // Mirrors the website's WooCommerce 'Вземи' action inside the app cart;
  // it never redirects to the external cart page.
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
                        child: Text(isVariable && canBuy ? tr('Избери вариант', 'Choose option') : canBuy ? tr('Вземи', 'Get it') : tr('Изчерпан', 'Unavailable'), maxLines: 1, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
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
                    label: Text(tr('Вземи', 'Get it')),
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
    final ordersFuture = widget.api.getShopOrders(token);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * .62,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 8, 10),
              child: Row(children: [
                Expanded(child: Text(tr('Моите поръчки', 'My orders'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold))),
                IconButton(tooltip: tr('Затвори', 'Close'), onPressed: () => Navigator.of(sheetContext).pop(), icon: const Icon(Icons.close_rounded)),
              ]),
            ),
            Expanded(child: FutureBuilder<List<Map<String, dynamic>>>(
              future: ordersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('${snapshot.error}', textAlign: TextAlign.center)));
                final rows = snapshot.data ?? <Map<String, dynamic>>[];
                if (rows.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(tr('Все още нямате поръчки.', 'You have no orders yet.'))));
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final order = rows[index];
                    return Card(child: ListTile(
                      leading: const Icon(Icons.receipt_long, color: Color(0xFF21D4D8)),
                      title: Text('#${order['number'] ?? order['id']}'),
                      subtitle: Text('${order['date'] ?? ''} · ${order['status'] ?? ''}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _orderDetails(token, order),
                    ));
                  },
                );
              },
            )),
          ]),
        ),
      ),
    );
  }

  Future<void> _orderDetails(String token, Map<String, dynamic> order) async {
    try {
      final id = int.tryParse('${order['id']}') ?? 0;
      if (id <= 0) throw Exception('Невалиден номер на поръчката.');
      Map<String, dynamic> detail = Map<String, dynamic>.from(order);
      if (detail['items'] is! List) {
        try { detail = await widget.api.getShopOrder(token, id); }
        catch (_) {
          final rows = await widget.api.getShopOrders(token);
          final match = rows.where((row) => int.tryParse('${row['id']}') == id).toList();
          if (match.isEmpty) rethrow;
          detail = match.first;
        }
      }
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
            ListTile(contentPadding: EdgeInsets.zero, title: Text(tr('Метод на плащане', 'Payment method')), subtitle: Text((detail['payment_method_title'] ?? tr('Наложен платеж', 'Cash on delivery')).toString())),
            if (detail['shipping_methods'] is List && (detail['shipping_methods'] as List).isNotEmpty) ListTile(contentPadding: EdgeInsets.zero, title: Text(tr('Куриерска услуга', 'Courier service')), subtitle: Text((detail['shipping_methods'] as List).join(', '))),
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
    const couriers = <String, String>{'econt': 'Econt', 'speedy': 'Speedy', 'pigeon': 'Pigeon'};
    String selectedCourier = couriers.containsKey((shipping['courier'] ?? '').toString().toLowerCase())
        ? (shipping['courier'] ?? '').toString().toLowerCase()
        : '';
    final phone = TextEditingController(text: (billing['phone'] ?? profile?.phone ?? '').toString());
    final email = profile?.email ?? '';
    final orderItems = cart.entries.map((e) { final p = cartProducts[e.key] ?? {}; return {'product_id': p['id'], 'variation_id': p['selected_variation_id'] ?? 0, 'quantity': e.value}; }).toList();
    List<Map<String, dynamic>> shippingRates = [];
    String selectedShippingRateId = '';
    bool loadingShippingRates = false;
    String? shippingRateError;
    Future<void> refreshShippingRates(StateSetter setDialogState) async {
      if (selectedCourier.isEmpty || city.text.trim().isEmpty || address.text.trim().isEmpty) {
        setDialogState(() { shippingRates = []; selectedShippingRateId = ''; shippingRateError = tr('Изберете куриер и попълнете град и адрес.', 'Select a courier and enter a city and address.'); });
        return;
      }
      setDialogState(() { loadingShippingRates = true; shippingRateError = null; });
      try {
        final rows = await widget.api.getShopShippingRates(token, items: orderItems, shipping: {'city': city.text.trim(), 'address_1': address.text.trim(), 'postcode': postcode.text.trim(), 'state': (shipping['state'] ?? billing['state'] ?? '').toString(), 'country': 'BG', 'courier': selectedCourier});
        setDialogState(() { shippingRates = rows; selectedShippingRateId = rows.isNotEmpty ? '${rows.first['id']}' : ''; if (rows.isEmpty) shippingRateError = tr('Няма активен метод за избрания куриер на този адрес.', 'No active method is available for the selected courier at this address.'); });
      } catch (e) { setDialogState(() { shippingRates = []; selectedShippingRateId = ''; shippingRateError = '$e'; }); }
      finally { setDialogState(() => loadingShippingRates = false); }
    }
    bool initialRatesRequested = false;
    if (!mounted) { for (final c in [firstName, lastName, city, address, postcode, phone]) { c.dispose(); } return; }
    final formKey = GlobalKey<FormState>();

    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        if (!initialRatesRequested && selectedCourier.isNotEmpty && city.text.trim().isNotEmpty && address.text.trim().isNotEmpty) {
          initialRatesRequested = true;
          WidgetsBinding.instance.addPostFrameCallback((_) { if (ctx.mounted) unawaited(refreshShippingRates(setDialogState)); });
        }
        return AlertDialog(
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
                DropdownButtonFormField<String>(
                  initialValue: selectedCourier.isEmpty ? null : selectedCourier,
                  decoration: InputDecoration(labelText: tr('Избор на куриер *', 'Choose courier *')),
                  hint: Text(tr('Изберете куриер', 'Select courier')),
                  items: couriers.entries.map((entry) => DropdownMenuItem<String>(value: entry.key, child: Text(entry.value))).toList(),
                  validator: (value) => value == null || value.isEmpty ? tr('Изберете куриер.', 'Select a courier.') : null,
                  onChanged: (value) {
                    setDialogState(() { selectedCourier = value ?? ''; shippingRates = []; selectedShippingRateId = ''; shippingRateError = null; });
                    if (value != null && city.text.trim().isNotEmpty && address.text.trim().isNotEmpty) unawaited(refreshShippingRates(setDialogState));
                  },
                ),
                _checkoutField(phone, tr('Телефон *', 'Phone *'), keyboard: TextInputType.phone),
                TextFormField(
                  initialValue: email, readOnly: true,
                  decoration: InputDecoration(labelText: tr('Email *', 'Email *'), helperText: tr('Имейлът се взима автоматично от регистрацията и не може да се редактира.', 'Email is taken from your registration and cannot be edited.')),
                  validator: (value) => (value == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim())) ? tr('Невалиден регистрационен имейл.', 'Invalid registration email.') : null,
                ),
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: Text(tr('Метод на плащане', 'Payment method'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
                Card(margin: const EdgeInsets.only(top: 6, bottom: 10), child: ListTile(dense: true, leading: const Icon(Icons.payments_outlined, color: Color(0xFF21D4D8)), title: Text(tr('Наложен платеж', 'Cash on delivery'), style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(tr('Плащане при получаване на поръчката.', 'Pay when the order is delivered.')))),
                Align(alignment: Alignment.centerLeft, child: Text(tr('Куриерска услуга', 'Courier service'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
                Align(alignment: Alignment.centerLeft, child: TextButton.icon(
                  onPressed: loadingShippingRates ? null : () => refreshShippingRates(setDialogState),
                  icon: loadingShippingRates ? const SizedBox(width:14,height:14,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.refresh_rounded, size:17),
                  label: Text(tr('Обнови', 'Refresh')),
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
      ); }),
    );

    if (!mounted || accepted != true) { for (final c in [firstName, lastName, city, address, postcode, phone]) { c.dispose(); } return; }
    setState(() => placingOrder = true);
    final first = firstName.text.trim();
    final last = lastName.text.trim();
    final selectedAddress = address.text.trim();
    final selectedCity = city.text.trim();
    try {
      await widget.api.createShopOrder(
        token,
        items: orderItems,
        billing: {
          'first_name': first, 'last_name': last, 'email': email,
          'phone': phone.text.trim(), 'address_1': selectedAddress, 'city': selectedCity, 'postcode': postcode.text.trim(),
          'state': (billing['state'] ?? '').toString(), 'country': 'BG',
        },
        shipping: {
          'first_name': first, 'last_name': last, 'address_1': selectedAddress,
          'city': selectedCity, 'postcode': postcode.text.trim(), 'state': (shipping['state'] ?? billing['state'] ?? '').toString(), 'country': 'BG', 'courier': selectedCourier,
        },
        shippingRateId: selectedShippingRateId,
      );
      if (!mounted) return;
      setState(() { cart.clear(); cartProducts.clear(); });
      await _saveCart();
      // The server sends a transactional push notification; keep the in-app flow free of duplicate info cards.
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
        decoration: InputDecoration(labelText: label, floatingLabelBehavior: FloatingLabelBehavior.auto, contentPadding: const EdgeInsets.fromLTRB(14, 19, 14, 15), isDense: false),
        validator: (value) => required && (value == null || value.trim().isEmpty) ? tr('Задължително поле', 'Required field') : null,
      ),
    );
  }
}
