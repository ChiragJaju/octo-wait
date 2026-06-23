#!/usr/bin/env bash
# Convenience CLI for turning Oswald on/off and poking the player.
#
#   bash scripts/oswald.sh on       # enable auto play/pause (default)
#   bash scripts/oswald.sh off      # disable: hooks become no-ops + pause now
#   bash scripts/oswald.sh status   # show enabled/disabled + server state
#   bash scripts/oswald.sh play     # manual play
#   bash scripts/oswald.sh pause    # manual pause
#   bash scripts/oswald.sh open     # open the player in your browser
#
# Honors OSWALD_PORT (default 8730) and OSWALD_DATA_DIR (default ~/.oswald-while-you-wait).

PORT="${OSWALD_PORT:-8730}"
URL="http://127.0.0.1:${PORT}"
DATA="${OSWALD_DATA_DIR:-$HOME/.oswald-while-you-wait}"
FLAG="$DATA/disabled"

case "${1:-status}" in
  on)
    rm -f "$FLAG"
    echo "Oswald is ON — episodes will auto play while the AI works."
    ;;
  off)
    mkdir -p "$DATA"; touch "$FLAG"
    curl -s -m 0.6 -X POST "$URL/pause" >/dev/null 2>&1
    echo "Oswald is OFF — hooks are now no-ops and playback is paused."
    ;;
  status)
    if [ -f "$FLAG" ]; then echo "switch:  OFF (remove $FLAG to re-enable)"; else echo "switch:  ON"; fi
    state="$(curl -s -m 0.6 "$URL/state" 2>/dev/null)"
    if [ -n "$state" ]; then echo "server:  up   $state"; else echo "server:  not running on $URL"; fi
    ;;
  play)  curl -s -m 0.6 -X POST "$URL/play"  >/dev/null 2>&1 && echo "▶ playing" ;;
  pause) curl -s -m 0.6 -X POST "$URL/pause" >/dev/null 2>&1 && echo "⏸ paused"  ;;
  open)
    if command -v open >/dev/null 2>&1; then open "$URL"
    elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$URL"
    else echo "Open this in your browser: $URL"; fi
    ;;
  *)
    echo "usage: bash scripts/oswald.sh {on|off|status|play|pause|open}"; exit 1 ;;
esac
