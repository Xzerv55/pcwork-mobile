#!/usr/bin/env python3
"""Static contract checks for the PCWork Mobile Marketplace checkout flow."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
API = (ROOT / "lib/services/api_service.dart").read_text()
SHOP = (ROOT / "lib/screens/shop_screen.dart").read_text()
SCREEN = (ROOT / "lib/screens/crypto_payments_screen.dart").read_text()
APP = (ROOT / "lib/app/pcwork_app.dart").read_text()
PUBSPEC = (ROOT / "pubspec.yaml").read_text()

checks = {
    "pending checkout ID persisted in secure storage": "_offlineStorage.write(key: key" in API and "_offlineStorage.read(key: key)" in API,
    "checkout fingerprint includes payload": "jsonEncode(payload)" in API and "crypto.sha256.convert" in API,
    "request ID sent to WordPress": "'client_request_id': requestId" in API,
    "specific HTTP 409 in-progress response retried": "pcw_order_request_in_progress" in API and "Duration(seconds: 2)" in API,
    "pending ID cleared after successful response": "_clearShopOrderRequestId(token, fingerprint)" in API,
    "checkout consumes only server-confirmed BTC and ADA assets": "value == 'BTC' || value == 'ADA'" in SHOP and "checkoutCryptoAssets.contains('BTC')" in SHOP and "checkoutCryptoAssets.contains('ADA')" in SHOP,
    "BTC and ADA payment methods are offered separately": "value: 'crypto_btc'" in SHOP and "value: 'crypto_ada'" in SHOP,
    "selected crypto method is sent to WordPress": "paymentMethod: selectedPaymentMethod" in SHOP,
    "returned payment method must match selected method": "returnedMethod != selectedPaymentMethod" in SHOP,
    "payment_required is checked before opening invoice screen": "createdOrder['payment_required'] == true" in SHOP and "if (!paymentRequired)" in SHOP,
    "matching BTC/ADA invoice screen is opened with order ID": "initialOrderId: orderId" in SHOP and "initialAsset: selectedPaymentMethod == 'crypto_btc' ? 'BTC' : 'ADA'" in SHOP,
    "Marketplace order asset is locked in the payment screen": "widget.initialOrderId == null || symbol == widget.initialAsset.toUpperCase()" in SCREEN and "active && widget.initialOrderId == null" in SCREEN,
    "payment screen auto-creates only the original active BTC/ADA asset": "(initialAsset == 'BTC' || initialAsset == 'ADA')" in SCREEN and "supportedAssets.contains(initialAsset)" in SCREEN,
    "app build metadata is 184": "defaultValue: 184" in APP and "version: 1.84.0+184" in PUBSPEC and "clientBuild = 184" in API,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("PASS " if ok else "FAIL ") + name)
if failed:
    print(f"FAILED: {len(failed)} of {len(checks)} checks", file=sys.stderr)
    raise SystemExit(1)
print(f"PASS: {len(checks)} of {len(checks)} Marketplace checkout contract checks")
