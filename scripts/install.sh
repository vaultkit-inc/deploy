#!/usr/bin/env bash
set -euo pipefail

echo
echo "🔐 VaultKit installer"
echo "====================="
echo

# Basic checks
command -v docker >/dev/null 2>&1 || {
  echo "❌ Docker is not installed"
  exit 1
}

if ! docker compose version >/dev/null 2>&1; then
  echo "❌ Docker Compose is not available"
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "❌ Docker daemon is not running"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
KEYS_DIR="$ROOT_DIR/secrets/keys"

mkdir -p "$KEYS_DIR"

# Create .env if needed
if [ ! -f "$ENV_FILE" ]; then
  echo "📄 Creating .env from .env.example"
  cp "$ROOT_DIR/.env.example" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  echo
fi

# Generate application secrets if missing
generate_secret () {
  openssl rand -hex "$1"
}

ensure_env_secret () {
  local key="$1"
  local length="$2"

  if ! grep -q "^${key}=" "$ENV_FILE" || grep -q "^${key}=change-me" "$ENV_FILE"; then
    echo "🔑 Generating ${key}"
    local secret
    secret=$(generate_secret "$length")
    if grep -q "^${key}=" "$ENV_FILE"; then
      # Replace existing line
      sed -i.bak "s|^${key}=.*|${key}=${secret}|" "$ENV_FILE"
    else
      # Append if not present
      echo "${key}=${secret}" >> "$ENV_FILE"
    fi
  fi
}

ensure_env_secret "SECRET_KEY_BASE" 64
ensure_env_secret "JWT_SECRET" 32
ensure_env_secret "VAULTKIT_ENCRYPTION_KEY" 32
# sed -i.bak leaves a copy of .env behind, which can hold the secrets above
rm -f "$ENV_FILE.bak"

# Generate signing keys
PRIVATE_KEY="$KEYS_DIR/vkit_priv.pem"
PUBLIC_KEY="$KEYS_DIR/vkit_pub.pem"

if [[ -f "$PRIVATE_KEY" && -f "$PUBLIC_KEY" ]]; then
  echo "✅ Signing keys already exist"
else
  echo "🔑 Generating signing keys"
  openssl genpkey -algorithm RSA -out "$PRIVATE_KEY" -pkeyopt rsa_keygen_bits:2048 >/dev/null 2>&1
  openssl rsa -pubout -in "$PRIVATE_KEY" -out "$PUBLIC_KEY" >/dev/null 2>&1
  chmod 600 "$PRIVATE_KEY"
  chmod 644 "$PUBLIC_KEY"
  echo "✅ Signing keys generated"
fi

# Detect machine IP
PUBLIC_IP=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}' || echo "unknown")

echo
echo "📍 Your machine's public IP: $PUBLIC_IP"
echo
echo "⚠️  Manual setup required before starting VaultKit:"
echo
echo "  Please edit .env and set:"
echo "   - APP_HOST"
echo "     Local:   http://localhost:5173"
echo "     Remote:  http://$PUBLIC_IP:5173"
echo "     Domain:  https://vaultkit.yourdomain.com"
echo "   - FRONTEND_BASE_URL (same as APP_HOST)"
echo "   - POSTGRES_PASSWORD / DATABASE_URL"
echo "   - OIDC settings (if using SSO)"
echo
echo "Once done, run:"
echo "  docker compose up -d"
echo
