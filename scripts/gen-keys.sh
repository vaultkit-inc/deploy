#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY_DIR="$ROOT/secrets/keys"

mkdir -p "$KEY_DIR"

PRIV="$KEY_DIR/vkit_priv.pem"
PUB="$KEY_DIR/vkit_pub.pem"

if [[ -f "$PRIV" && -f "$PUB" ]]; then
  if openssl rsa -check -in "$PRIV" >/dev/null 2>&1; then
    echo "✅ Keys already exist:"
    echo "  - $PRIV"
    echo "  - $PUB"
    exit 0
  else
    echo "⚠️  Existing keys are invalid, regenerating..."
  fi
fi

echo "🔐 Generating VaultKit RSA keys..."
openssl genpkey -algorithm RSA -out "$PRIV" -pkeyopt rsa_keygen_bits:2048 >/dev/null 2>&1
openssl rsa -pubout -in "$PRIV" -out "$PUB" >/dev/null 2>&1

chmod 600 "$PRIV"
chmod 644 "$PUB"

echo "✅ Generated:"
echo "  - $PRIV"
echo "  - $PUB"
