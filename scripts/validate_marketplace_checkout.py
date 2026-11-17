#!/usr/bin/env python3
"""Static contract checks for the PCWork Mobile Marketplace checkout flow."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
API = (ROOT / "lib/services/api_service.dart").read_text()
SHOP = (ROOT / "lib/screens/shop_screen.dart").read_text()
APP = (ROOT / "lib/app/pcwork_app.dart").read_text()
PUBSPEC = (ROOT / "pubspec.yaml").read_text()

checks = {
    "pending checkout ID persisted in secure storage": "_offlineStorage.write(key: key" in API and "_offlineStorage.read(key: key)" in API,
    "checkout fingerprint includes payload": "jsonEncode(payload)" in API and "crypto.sha256.convert" in API,
    "request ID sent to WordPress": "'client_request_id': requestId" in API,
    "specific HTTP 409 in-progress response retried": "pcw_order_request_in_progress" in API and "Duration(seconds: 2)" in API,
    "pending ID cleared after successful response": "_clearShopOrderRequestId(token, fingerprint)" in API,
    "ADA response method checked": "returnedMethod != 'crypto_ada'" in SHOP,
    "ADA payment_required checked before invoice screen": "createdOrder['payment_required'] == true" in SHOP and "if (!paymentRequired)" in SHOP,
    "app build metadata is 181": "defaultValue: 181" in APP and "version: 1.81.0+181" in PUBSPEC and "clientBuild = 181" in API,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("PASS " if ok else "FAIL ") + name)
if failed:
    print(f"FAILED: {len(failed)} of {len(checks)} checks", file=sys.stderr)
    raise SystemExit(1)
print(f"PASS: {len(checks)} of {len(checks)} Marketplace checkout contract checks")
