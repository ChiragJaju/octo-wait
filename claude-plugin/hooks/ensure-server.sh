#!/usr/bin/env bash
# Fired on SessionStart → make sure the player server is running and the window is
# open (paused), so the very first prompt starts playback instantly.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
oswald_enabled || exit 0
ensure_server
exit 0
