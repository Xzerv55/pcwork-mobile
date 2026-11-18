#!/usr/bin/env python3
"""Static contract checks for PCWork Mobile ETH/SOL testnet checkout integration."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
API = (ROOT / "lib/services/api_service.dart").read_text()
SHOP = (ROOT / "lib/screens/shop_screen.dart").read_text()
SCREEN = (ROOT / "lib/screens/crypto_payments_screen.dart").read_text()
STATE = (ROOT / "lib/models/crypto_payment_state.dart").read_text()
APP = (ROOT / "lib/app/pcwork_app.dart").read_text()
PUBSPEC = (ROOT / "pubspec.yaml").read_text()

checks = {
    "checkout reads server-confirmed crypto readiness": "getCryptoPaymentStatus(token)" in SHOP and "cryptoStatus['enabled'] == true" in SHOP,
    "checkout allows only BTC/ADA/ETH/SOL from server list": "['BTC', 'ADA', 'ETH', 'SOL'].contains(value)" in SHOP,
    "ETH Sepolia method is offered separately": "value: 'crypto_eth'" in SHOP and "Ethereum ETH – Sepolia" in SHOP,
    "SOL Devnet method is offered separately": "value: 'crypto_sol'" in SHOP and "Solana SOL – Devnet" in SHOP,
    "selected payment method is sent to WordPress order creation": "paymentMethod: selectedPaymentMethod" in SHOP,
    "returned payment method must match selection": "returnedMethod != selectedPaymentMethod" in SHOP,
    "order routes ETH to ETH payment screen": "selectedPaymentMethod == 'crypto_eth' ? 'ETH'" in SHOP,
    "order routes SOL to SOL payment screen": ": 'SOL'" in SHOP and "selectedPaymentMethod == 'crypto_sol'" in SHOP,
    "crypto screen creates through authenticated WordPress API": "createCryptoPayment(token!" in SCREEN and "_uri('crypto/invoices')" in API,
    "ETH invoice validates Sepolia network and address": "expectedNetwork = selectedAsset == 'ETH' ? 'sepolia' : 'devnet'" in SCREEN and "address.isEmpty" in SCREEN,
    "SOL invoice validates Devnet network": "'devnet'" in SCREEN and "'sepolia'" in SCREEN,
    "ETH/SOL payment screen displays QR receiving address": "QrImageView(data: (data['address'] ?? '').toString()" in SCREEN,
    "payment refresh uses authenticated WordPress invoice endpoint": "getCryptoPayment(token!, id)" in SCREEN and "_uri('crypto/invoices/$safeId')" in API,
    "late payment requires manual review": "late_payment_review" in STATE and "late_payment_review" in SCREEN,
    "overpayment requires manual review": "overpaid" in STATE and "overpaid" in SCREEN,
    "testnet verified is not treated as settled": "testnet_verified" in STATE and "testnet_verified" in SCREEN,
    "GIBORIS remains excluded from checkout assets": "['BTC', 'ADA', 'ETH', 'SOL'].contains(value)" in SHOP,
    "pubspec version is 1.95.0+196": re.search(r"^version:\s*1\.95\.0\+196\s*$", PUBSPEC, re.M) is not None,
    "app update build defaults to 196": "defaultValue: 196" in APP,
    "API client build defaults to 196": "this.clientBuild = 196" in API,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("PASS " if ok else "FAIL ") + name)
if failed:
    print(f"FAILED: {len(failed)} of {len(checks)} checks", file=sys.stderr)
    raise SystemExit(1)
print(f"PASS: {len(checks)} of {len(checks)} ETH/SOL checkout contract checks")
