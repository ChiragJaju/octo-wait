#!/usr/bin/env bash
# Fired on UserPromptSubmit and PreToolUse → the AI is actively working → play.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
oswald_enabled || exit 0
ensure_server
post play
exit 0
