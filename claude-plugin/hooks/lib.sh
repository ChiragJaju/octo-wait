#!/usr/bin/env bash
# Shared helpers for the Oswald hooks. Sourced by play.sh / pause.sh / ensure-server.sh.

OSWALD_PORT="${OSWALD_PORT:-8730}"
OSWALD_URL="http://127.0.0.1:${OSWALD_PORT}"

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Prefer the path Claude Code injects; fall back to walking up from this script.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$HOOK_DIR/.." && pwd)}"
SERVER_JS="$PLUGIN_ROOT/player/server.js"
OSWALD_DATA_DIR="${OSWALD_DATA_DIR:-$HOME/.oswald-while-you-wait}"
TERM_FILE="$OSWALD_DATA_DIR/terminal-app"
case "$(uname -s)" in Darwin) IS_MAC=true;; *) IS_MAC=false;; esac

# Master on/off switch. Returns non-zero (disabled) when either:
#   - OSWALD_DISABLED=1 is set in the environment, or
#   - a sentinel file  $OSWALD_DATA_DIR/disabled  exists.
# Hooks call this first and exit quietly when disabled.
oswald_enabled() {
  [ "${OSWALD_DISABLED:-0}" = "1" ] && return 1
  [ -f "$OSWALD_DATA_DIR/disabled" ] && return 1
  return 0
}

# Returns 0 if the control server answers /health quickly.
server_up() {
  curl -s -m 0.4 -o /dev/null "$OSWALD_URL/health"
}

# Start the control server (detached) if it isn't already running.
ensure_server() {
  if server_up; then return 0; fi
  if ! command -v node >/dev/null 2>&1; then
    echo "[oswald] node not found on PATH; cannot start player server." >&2
    return 1
  fi
  OSWALD_PORT="$OSWALD_PORT" nohup node "$SERVER_JS" >/dev/null 2>&1 &
  disown 2>/dev/null || true
  # Wait briefly for it to come up (max ~2s, only happens once per machine boot).
  local i
  for i in $(seq 1 10); do
    server_up && break
    sleep 0.2
  done
  open_viewer_once
}

# Open the player in the default browser once per port (skipped if OSWALD_OPEN_BROWSER=0,
# e.g. when you're viewing it inside the VSCode panel instead).
open_viewer_once() {
  [ "${OSWALD_OPEN_BROWSER:-1}" = "0" ] && return 0
  local flag="${TMPDIR:-/tmp}/oswald-opened-${OSWALD_PORT}"
  [ -f "$flag" ] && return 0
  touch "$flag" 2>/dev/null || true
  if command -v open >/dev/null 2>&1; then
    open "$OSWALD_URL" >/dev/null 2>&1 || true            # macOS
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$OSWALD_URL" >/dev/null 2>&1 || true        # Linux
  elif command -v cmd.exe >/dev/null 2>&1; then
    cmd.exe /c start "" "$OSWALD_URL" >/dev/null 2>&1 || true  # WSL
  fi
}

# Fire a control command at the server (play / pause / toggle). Never blocks long.
post() {
  curl -s -m 0.6 -X POST "$OSWALD_URL/$1" >/dev/null 2>&1 || true
}

# ---- window focus (macOS only) --------------------------------------------
# Enabled by default; set OSWALD_FOCUS=0 to disable the focus-switching.
focus_on() { [ "${OSWALD_FOCUS:-1}" = "1" ] && $IS_MAC; }

# Which browser to bring forward. Override with OSWALD_BROWSER="Google Chrome",
# otherwise detect the system default browser.
browser_app() {
  if [ -n "${OSWALD_BROWSER:-}" ]; then echo "$OSWALD_BROWSER"; return; fi
  local name
  name=$(osascript 2>/dev/null <<'OSA'
use framework "AppKit"
use scripting additions
set theURL to current application's |NSURL|'s URLWithString:"https://example.com"
set theApp to current application's |NSWorkspace|'s sharedWorkspace()'s URLForApplicationToOpenURL:theURL
if theApp is missing value then return ""
return (theApp's lastPathComponent()) as text
OSA
)
  name="${name%.app}"
  [ -z "$name" ] && name="Safari"
  echo "$name"
}

# Remember the terminal that's frontmost right now (called at prompt-submit time,
# when you've just hit Enter, so the terminal is in front).
record_terminal() {
  focus_on || return 0
  local name
  name=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null)
  if [ -n "$name" ]; then
    mkdir -p "$OSWALD_DATA_DIR"
    printf '%s' "$name" > "$TERM_FILE"
  fi
}

# Bring the player's browser to the front (so you watch Oswald while AI works).
focus_browser() {
  focus_on || return 0
  local app; app="$(browser_app)"
  [ -n "$app" ] && osascript -e "tell application \"$app\" to activate" >/dev/null 2>&1 || true
}

# Return focus to the terminal we recorded (so you're back at the prompt).
focus_terminal() {
  focus_on || return 0
  local name; name=$(cat "$TERM_FILE" 2>/dev/null)
  [ -n "$name" ] && osascript -e "tell application \"System Events\" to set frontmost of process \"$name\" to true" >/dev/null 2>&1 || true
}
