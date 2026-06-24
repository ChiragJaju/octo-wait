#!/usr/bin/env bash
# Fired on UserPromptSubmit and PreToolUse → the AI is actively working → play.
# Pass --focus (UserPromptSubmit only) to also bring the player window forward;
# PreToolUse calls it without --focus so it never yanks focus mid-turn.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
oswald_enabled || exit 0
if [ "${1:-}" = "--focus" ]; then
  record_terminal      # remember where to return to (terminal is frontmost now)
fi
ensure_server
post play
if [ "${1:-}" = "--focus" ]; then
  focus_browser        # look at Oswald while the AI works
fi
exit 0
