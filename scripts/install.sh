#!/usr/bin/env bash
#
# Sets up VaultKit, or moves an install to another release.
#
#   ./scripts/install.sh                      Install the latest release, or
#                                             keep the version already in .env
#   ./scripts/install.sh --version <version>  Install or upgrade to <version>
#
set -euo pipefail

IMAGES=(control-plane funl-runtime console)
REGISTRY="ghcr.io/vaultkit-inc"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
KEYS_DIR="$ROOT_DIR/secrets/keys"

fail () {
  echo "❌ $1" >&2
  exit 1
}

env_value () {
  sed -n "s/^$1=//p" "$2" 2>/dev/null | tail -1
}

set_env () {
  local key="$1"
  local value="$2"

  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i.bak "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
  else
    echo "${key}=${value}" >> "$ENV_FILE"
  fi
  # sed -i.bak leaves a copy of .env behind, which can hold secrets
  rm -f "$ENV_FILE.bak"
}

generate_secret () {
  openssl rand -hex "$1"
}

ensure_env_secret () {
  local key="$1"
  local length="$2"

  if ! grep -q "^${key}=" "$ENV_FILE" || grep -q "^${key}=change-me" "$ENV_FILE"; then
    echo "🔑 Generating ${key}"
    set_env "$key" "$(generate_secret "$length")"
  fi
}

# Succeeds when $1 is older than $2. A prerelease is older than its release,
# so 1.0.0-alpha < 1.0.0, which sort -V alone gets backwards.
version_lt () {
  local a="$1" b="$2"
  local a_core="${a%%-*}" b_core="${b%%-*}"

  [ "$a" = "$b" ] && return 1

  if [ "$a_core" = "$b_core" ]; then
    [ "$a" = "$a_core" ] && return 1
    [ "$b" = "$b_core" ] && return 0
  else
    a="$a_core"
    b="$b_core"
  fi

  [ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -1)" = "$a" ]
}

# The version of an install, from .env or, for one set up before .env held
# it, from the running control plane container.
installed_version () {
  local version
  version="$(env_value VAULTKIT_VERSION "$ENV_FILE")"

  if [ -z "$version" ]; then
    version="$(docker inspect vaultkit-control-plane --format '{{.Config.Image}}' 2>/dev/null || true)"
    version="${version##*:}"
  fi

  echo "$version"
}

check_version () {
  local version="$1"
  local reason image

  if ! git -C "$ROOT_DIR" rev-parse -q --verify "refs/tags/v$version" >/dev/null; then
    fail "VaultKit $version isn't available. Versions you can install: $(git -C "$ROOT_DIR" tag -l 'v*' | sed 's/^v//' | sort -V | tr '\n' ' ')"
  fi

  reason="$(git -C "$ROOT_DIR" show origin/main:BROKEN_VERSIONS 2>/dev/null | sed -n "s/^$version //p")"
  [ -z "$reason" ] || fail "VaultKit $version must not be installed: $reason"

  for image in "${IMAGES[@]}"; do
    docker manifest inspect "$REGISTRY/$image:$version" >/dev/null 2>&1 \
      || fail "$REGISTRY/$image:$version can't be found, so VaultKit $version can't be installed"
  done
}

main () {
  local requested=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --version)
        [ $# -ge 2 ] || fail "--version needs a version, such as --version 0.9.2-alpha"
        requested="${2#v}"
        shift 2
        ;;
      *)
        fail "Unknown option: $1. Usage: ./scripts/install.sh [--version <version>]"
        ;;
    esac
  done

  echo
  echo "🔐 VaultKit installer"
  echo "====================="
  echo

  # Basic checks
  command -v docker >/dev/null 2>&1 || fail "Docker is not installed"
  docker compose version >/dev/null 2>&1 || fail "Docker Compose is not available"
  docker info >/dev/null 2>&1 || fail "Docker daemon is not running"

  git -C "$ROOT_DIR" fetch --quiet --tags origin main \
    || fail "Couldn't reach the deploy repository to check for releases"

  local installed latest target
  installed="$(installed_version)"
  latest="$(git -C "$ROOT_DIR" show origin/main:.env.example | sed -n 's/^VAULTKIT_VERSION=//p')"
  target="${requested:-${installed:-$latest}}"

  # An install from before .env held the version, on a release that's no
  # longer available, moves to the latest one.
  if [ -z "$requested" ] && [ -n "$installed" ] && [ -z "$(env_value VAULTKIT_VERSION "$ENV_FILE")" ] \
    && ! git -C "$ROOT_DIR" rev-parse -q --verify "refs/tags/v$installed" >/dev/null; then
    target="$latest"
  fi

  check_version "$target"

  if [ -n "$installed" ] && version_lt "$target" "$installed"; then
    fail "This install runs $installed, and $target is older. Migrations don't run backwards, so VaultKit can't downgrade in place. To go back, restore the database backup you took before upgrading, then run this again."
  fi

  if ! git -C "$ROOT_DIR" diff --quiet HEAD --; then
    fail "This folder has local changes that the release would overwrite: $(git -C "$ROOT_DIR" diff --name-only HEAD -- | tr '\n' ' '). Move them to .env (see CONSOLE_BIND in .env.example) or undo them, then run this again."
  fi

  # Every file from here on, including this script, matches the release.
  # main has been read in full, so bash isn't affected by it changing.
  git -C "$ROOT_DIR" -c advice.detachedHead=false checkout --quiet "v$target"

  mkdir -p "$KEYS_DIR"

  # Create .env if needed
  if [ ! -f "$ENV_FILE" ]; then
    echo "📄 Creating .env from .env.example"
    cp "$ROOT_DIR/.env.example" "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    echo
  fi

  set_env VAULTKIT_VERSION "$target"

  # Generate application secrets if missing
  ensure_env_secret "SECRET_KEY_BASE" 64
  ensure_env_secret "JWT_SECRET" 32
  ensure_env_secret "VAULTKIT_ENCRYPTION_KEY" 32

  # Generate signing keys
  local private_key="$KEYS_DIR/vkit_priv.pem"
  local public_key="$KEYS_DIR/vkit_pub.pem"

  if [[ -f "$private_key" && -f "$public_key" ]]; then
    echo "✅ Signing keys already exist"
  else
    echo "🔑 Generating signing keys"
    openssl genpkey -algorithm RSA -out "$private_key" -pkeyopt rsa_keygen_bits:2048 >/dev/null 2>&1
    openssl rsa -pubout -in "$private_key" -out "$public_key" >/dev/null 2>&1
    chmod 600 "$private_key"
    chmod 644 "$public_key"
    echo "✅ Signing keys generated"
  fi

  echo
  echo "✅ VaultKit $target is selected"

  if [ -n "$installed" ] && [ "$installed" != "$target" ]; then
    echo
    echo "⬆️  Moving from $installed to $target. To apply it, run:"
    echo "  docker compose pull"
    echo "  docker compose up -d"
    echo
    return
  fi

  if [ -n "$installed" ] && version_lt "$target" "$latest"; then
    echo
    echo "ℹ️  $latest is available. Back up the database, then run:"
    echo "  ./scripts/install.sh --version $latest"
  fi

  # Detect machine IP
  local public_ip
  public_ip=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}' || echo "unknown")

  echo
  echo "📍 Your machine's public IP: $public_ip"
  echo
  echo "⚠️  Manual setup required before starting VaultKit:"
  echo
  echo "  Please edit .env and set:"
  echo "   - APP_HOST"
  echo "     Local:   http://localhost:5173 (also set FORCE_SSL=false)"
  echo "     Remote:  http://$public_ip:5173 (also set FORCE_SSL=false)"
  echo "     Domain:  https://vaultkit.yourdomain.com"
  echo "   - FRONTEND_BASE_URL (same as APP_HOST)"
  echo "   - POSTGRES_PASSWORD / DATABASE_URL"
  echo "   - OIDC settings (if using SSO)"
  echo
  echo "Once done, run:"
  echo "  docker compose up -d"
  echo
}

main "$@"
exit
