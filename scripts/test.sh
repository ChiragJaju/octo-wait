#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Oswald — end-to-end smoke test.
# Spins up the control server on a throwaway port + data dir, drives it the
# same way the Claude Code hooks do, and asserts the play / pause / resume
# behaviour. Exits non-zero if anything fails.
#
#   Usage:  bash scripts/test.sh
# ---------------------------------------------------------------------------
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${OSWALD_TEST_PORT:-8799}"
URL="http://127.0.0.1:${PORT}"
DATA="$(mktemp -d)"
PASS=0
FAIL=0

green() { printf "\033[32m%s\033[0m\n" "$1"; }
red()   { printf "\033[31m%s\033[0m\n" "$1"; }

check() { # check "label" "expected substring" "actual"
  if printf '%s' "$3" | grep -q -- "$2"; then
    green "  PASS  $1"; PASS=$((PASS+1))
  else
    red   "  FAIL  $1"; red "         expected to contain: $2"; red "         got: $3"; FAIL=$((FAIL+1))
  fi
}

cleanup() {
  [ -n "${SRV:-}" ] && kill "$SRV" >/dev/null 2>&1
  rm -rf "$DATA"
}
trap cleanup EXIT

command -v node >/dev/null 2>&1 || { red "node not found on PATH"; exit 2; }

echo "Repo:      $ROOT"
echo "Test port: $PORT"
echo "Data dir:  $DATA"
echo

# --- start server (as ensure-server.sh would) ---
OSWALD_PORT="$PORT" OSWALD_DATA_DIR="$DATA" node "$ROOT/player/server.js" >/dev/null 2>&1 &
SRV=$!
for i in $(seq 1 20); do
  curl -s -m 0.4 -o /dev/null "$URL/health" && break
  sleep 0.2
done

echo "1) Server + endpoints"
check "/health responds ok"        '"ok":true'                            "$(curl -s $URL/health)"
check "/config has playlist id"    'PL'                                   "$(curl -s $URL/config)"
check "player page served (200)"   '200'                                  "$(curl -s -o /dev/null -w '%{http_code}' $URL/)"
check "boots paused"               '"playing":false'                      "$(curl -s $URL/state)"

echo "2) Play / pause (what the hooks do)"
check "play -> playing:true"        '"playing":true'   "$(curl -s -X POST $URL/play)"
check "pause -> playing:false"      '"playing":false'  "$(curl -s -X POST $URL/pause)"
check "toggle flips back to true"   '"playing":true'   "$(curl -s -X POST $URL/toggle)"
curl -s -X POST $URL/pause >/dev/null

echo "3) Resume position is remembered"
curl -s -X POST $URL/position -H 'Content-Type: application/json' -d '{"index":7,"time":123.4}' >/dev/null
check "resume index saved"          '"index":7'        "$(curl -s $URL/state)"
check "resume time saved"           '123.4'            "$(curl -s $URL/state)"

echo "4) Resume survives a server restart"
sleep 1.2                                                 # let the throttled write flush
kill "$SRV" >/dev/null 2>&1; wait "$SRV" 2>/dev/null      # SIGTERM also flushes synchronously
OSWALD_PORT="$PORT" OSWALD_DATA_DIR="$DATA" node "$ROOT/player/server.js" >/dev/null 2>&1 &
SRV=$!
for i in $(seq 1 20); do curl -s -m 0.4 -o /dev/null "$URL/health" && break; sleep 0.2; done
check "index restored after restart" '"index":7'       "$(curl -s $URL/state)"
check "reboots paused (not playing)" '"playing":false' "$(curl -s $URL/state)"

echo "5) Kill switch (turn OFF) makes play.sh a no-op"
touch "$DATA/disabled"
OSWALD_PORT="$PORT" OSWALD_DATA_DIR="$DATA" bash "$ROOT/claude-plugin/hooks/play.sh"
check "stays paused while disabled" '"playing":false'  "$(curl -s $URL/state)"
rm -f "$DATA/disabled"
OSWALD_PORT="$PORT" OSWALD_DATA_DIR="$DATA" OSWALD_OPEN_BROWSER=0 bash "$ROOT/claude-plugin/hooks/play.sh"
check "plays again once re-enabled"  '"playing":true'  "$(curl -s $URL/state)"

echo "6) Focus flags work and don't break the hooks"
OSWALD_PORT="$PORT" OSWALD_DATA_DIR="$DATA" OSWALD_OPEN_BROWSER=0 bash "$ROOT/claude-plugin/hooks/play.sh" --focus
rc_play=$?
check "play.sh --focus exits 0"      '0'               "$rc_play"
check "play.sh --focus still plays"  '"playing":true'  "$(curl -s $URL/state)"
OSWALD_PORT="$PORT" OSWALD_DATA_DIR="$DATA" bash "$ROOT/claude-plugin/hooks/pause.sh" --focus
rc_pause=$?
check "pause.sh --focus exits 0"     '0'               "$rc_pause"
check "pause.sh --focus still pauses" '"playing":false' "$(curl -s $URL/state)"

echo
echo "-----------------------------------------"
green "PASSED: $PASS"
[ "$FAIL" -gt 0 ] && red "FAILED: $FAIL" || echo "FAILED: 0"
echo "-----------------------------------------"
[ "$FAIL" -eq 0 ] || exit 1
