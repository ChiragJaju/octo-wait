#!/usr/bin/env bash
# Fired on Stop and Notification → the AI has stopped / is waiting on you → pause.
# Pausing (rather than stopping) is what makes it resume from the exact same spot.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
oswald_enabled || exit 0
server_up && post pause
exit 0
