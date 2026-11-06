#!/usr/bin/env bash
# Remove obsolete third-party chat source files left behind by in-place GitHub uploads.
set -euo pipefail

if [[ ! -d lib ]]; then
  echo "ERROR: lib/ directory not found. Run this script from the Flutter project root."
  exit 1
fi

legacy_name='chat''y'
legacy_method='getChat''yUrl'
find lib -type f -iname "*${legacy_name}*" -print -delete

if grep -RIniE "${legacy_name}|${legacy_method}" lib --include='*.dart'; then
  echo "ERROR: Obsolete third-party chat references remain in lib/. Remove them before building."
  exit 1
fi

echo "Legacy chat source cleanup passed."
