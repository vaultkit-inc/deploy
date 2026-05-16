#!/bin/sh
set -e

if [ "$#" -lt 2 ]; then
  echo "Usage: wait-for.sh host port [command...]"
  exit 1
fi

HOST="$1"
PORT="$2"
shift 2

if ! command -v nc >/dev/null 2>&1; then
  echo "❌ nc is required but not installed"
  exit 1
fi

TIMEOUT="${WAIT_FOR_TIMEOUT:-30}"

echo "⏳ Waiting for $HOST:$PORT (timeout: ${TIMEOUT}s)"

start_ts=$(date +%s)

while :; do
  if nc -z "$HOST" "$PORT" >/dev/null 2>&1; then
    echo "✅ $HOST:$PORT is available"
    exec "$@"
  fi

  now_ts=$(date +%s)
  elapsed=$((now_ts - start_ts))

  if [ "$elapsed" -ge "$TIMEOUT" ]; then
    echo "❌ Timeout waiting for $HOST:$PORT"
    exit 1
  fi

  sleep 1
done
