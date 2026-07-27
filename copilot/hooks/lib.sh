#!/usr/bin/env bash
# Shared helpers for Copilot CLI tmux/sound hooks.
# Source this, then call hook_read_input once and use the helpers below.

copilot_db="$HOME/.copilot/session-store.db"
sound_dir="/usr/share/sounds/freedesktop/stereo"

# Sounds (freedesktop .oga names under $sound_dir).
hook_sound_input="bell.oga"
hook_sound_done="complete.oga"

# Tools that mean "agent is waiting on the user" (names as seen in hook payloads).
hook_input_tools="AskUserQuestion exit_plan_mode"

# Window-status styles per state (tmux style strings) and static markers.
hook_style_working="bg=blue,fg=white"
hook_style_input="bg=yellow,fg=black"
hook_style_done="bg=green,fg=black"
hook_style_cancel="bg=red,fg=white"
hook_marker_input="(?)"
hook_marker_done="✓"
hook_marker_cancel="✗"

# Copilot fires NO hook when a turn is cancelled by the user (esc) or aborts with
# an error - it just returns to the idle prompt. The spinner detects the *end* of a
# turn by positively matching copilot's idle-prompt footer (ready for input). We
# match the idle footer rather than the absence of "esc cancel" so that any
# working/thinking/streaming phase keeps the spinner spinning, even if a given phase
# does not render the cancel affordance.
hook_idle_footer_re='commands.*\? help|tab next tab|space hold to record'

# Working spinner: space-separated frames + frame delay (~8 fps).
hook_spinner_frames="⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏"
hook_spinner_delay="0.12"

# Per-window hook state, spinner pid, lock, and active-agent markers.
hook_state_dir="${XDG_RUNTIME_DIR:-/tmp}/copilot-hooks"

hook_read_input() {
  HOOK_INPUT="$(cat 2>/dev/null)"
}

# Append the raw hook payload to debug.log when ~/.copilot/hooks/.debug exists.
hook_debug() {
  [ -e "$HOME/.copilot/hooks/.debug" ] || return 0
  printf '%s | %s\n' "$(date '+%F %T')" "$HOOK_INPUT" >> "$HOME/.copilot/hooks/debug.log"
}

hook_field() {
  printf '%s' "$HOOK_INPUT" | jq -r --arg k "$1" '.[$k] // empty' 2>/dev/null
}

hook_session_id() {
  local sid
  sid="$(hook_field session_id)"
  [ -z "$sid" ] && sid="$(hook_field sessionId)"
  case "$sid" in
    ""|*[!A-Za-z0-9_.-]*) return 1 ;;
  esac
  printf '%s' "$sid"
}

# True when the current tool_name is one of $hook_input_tools.
hook_is_input_tool() {
  local t; t="$(hook_field tool_name)"
  [ -n "$t" ] || return 1
  case " $hook_input_tools " in *" $t "*) return 0 ;; esac
  return 1
}

# True only for a Notification that is a *pending* request the user must answer
# (permission prompt / MCP elicitation). Everything else a Notification carries -
# agent_completed (fired once per finished subagent, e.g. by /research), idle, and the
# *_completed/_response/_denied resolutions - is informational and must not ding or grab
# the window status.
hook_notification_is_input() {
  case "$(hook_field notification_type)" in
    permission|permission_prompt|permission_request|permission_requested) return 0 ;;
    elicitation|elicitation_requested|elicitation_dialog) return 0 ;;
    *) return 1 ;;
  esac
}

# Running inside a tmux pane? Headless/piped copilot runs have neither var set.
hook_in_tmux() { [ -n "${TMUX:-}" ] || [ -n "${TMUX_PANE:-}" ]; }

hook_pane() {
  if [ -n "${TMUX_PANE:-}" ]; then
    printf '%s' "$TMUX_PANE"
  elif [ -n "${TMUX:-}" ]; then
    tmux display-message -p '#{pane_id}' 2>/dev/null
  fi
}

hook_window_id() {
  local pane
  pane="$(hook_pane)"
  [ -n "$pane" ] && tmux display-message -p -t "$pane" '#{window_id}' 2>/dev/null
}

hook_strip_marker() {
  printf '%s' "$1" | LC_ALL=C sed -E 's/^(\xE2\x9C\x93|\xE2\x9D\x93|\(\?\)|\xE2[\xA0-\xA3][\x80-\xBF]) //'
}

# Authoritative session title as shown in Copilot (what /rename writes).
hook_workspace_name() {
  local sid f n
  sid="$(hook_field session_id)"; [ -z "$sid" ] && sid="$(hook_field sessionId)"; [ -n "$sid" ] || return 1
  f="$HOME/.copilot/session-state/$sid/workspace.yaml"
  [ -f "$f" ] || return 1
  n="$(sed -nE 's/^name:[[:space:]]*(.*)$/\1/p' "$f" | head -1)"
  n="${n%\"}"; n="${n#\"}"; n="${n%\'}"; n="${n#\'}"
  [ -n "$n" ] && printf '%s' "$n"
}

# Resolve a display name: workspace.yaml title -> stdin session_name -> db summary
# -> current window name -> copilot.
hook_session_name() {
  local name sid win
  name="$(hook_workspace_name)"
  [ -z "$name" ] && name="$(hook_field session_name)"
  if [ -z "$name" ]; then
    sid="$(hook_field session_id)"
    [ -n "$sid" ] && name="$(sqlite3 "$copilot_db" "select summary from sessions where id='$sid';" 2>/dev/null)"
  fi
  if [ -z "$name" ]; then
    win="$(hook_window_id)"
    [ -n "$win" ] && name="$(hook_strip_marker "$(tmux display-message -p -t "$win" '#{window_name}' 2>/dev/null)")"
  fi
  printf '%s' "${name:-copilot}"
}

hook_play() {
  canberra-gtk-play -f "$sound_dir/$1" >/dev/null 2>&1 || printf '\a'
}

# Current state token for this window ("working"|"finishing"|"input"|"done"|"idle"|"").
hook_state_read() {
  local win f st
  win="$(hook_window_id)"; [ -z "$win" ] && return 0
  f="$(hook_state_file "$win")"; [ -f "$f" ] || return 0
  read -r st _ < "$f" 2>/dev/null && printf '%s' "$st"
}

hook_state_file() { printf '%s/%s.state' "$hook_state_dir" "${1#@}"; }
hook_pid_file()   { printf '%s/%s.pid'   "$hook_state_dir" "${1#@}"; }
hook_lock_file()  { printf '%s/%s.lock'  "$hook_state_dir" "${1#@}"; }
hook_agents_dir() { printf '%s/%s.agents' "$hook_state_dir" "${1#@}"; }

hook_lock_window_id() {
  local win="$1"
  [ -n "$win" ] || return 1
  mkdir -p "$hook_state_dir" 2>/dev/null || return 1
  exec 8>"$(hook_lock_file "$win")" || return 1
  if command -v flock >/dev/null 2>&1; then
    flock -x 8 || return 1
  fi
}

hook_lock_window() {
  local win
  win="$(hook_window_id)"
  hook_lock_window_id "$win"
}

hook_unlock_window() {
  command -v flock >/dev/null 2>&1 && flock -u 8 2>/dev/null
  exec 8>&-
}

hook_agent_mark_active() {
  local win sid dir
  win="$(hook_window_id)"; [ -n "$win" ] || return 0
  sid="$(hook_session_id)" || return 0
  dir="$(hook_agents_dir "$win")"
  mkdir -p "$dir" 2>/dev/null || return 0
  : > "$dir/$sid"
}

hook_agent_mark_inactive() {
  local win sid dir
  win="$(hook_window_id)"; [ -n "$win" ] || return 0
  sid="$(hook_session_id)" || return 0
  dir="$(hook_agents_dir "$win")"
  rm -f -- "$dir/$sid"
  rmdir -- "$dir" 2>/dev/null || true
}

hook_agents_active() {
  local win dir marker
  win="${1:-$(hook_window_id)}"; [ -n "$win" ] || return 1
  dir="$(hook_agents_dir "$win")"
  for marker in "$dir"/*; do
    [ -f "$marker" ] && return 0
  done
  return 1
}

hook_agents_clear() {
  local dir marker
  dir="$(hook_agents_dir "$1")"
  for marker in "$dir"/*; do
    [ -f "$marker" ] && rm -f -- "$marker"
  done
  rmdir -- "$dir" 2>/dev/null || true
}

# Write "<state> [gen]" for a window.
hook_state_write() {
  mkdir -p "$hook_state_dir" 2>/dev/null
  printf '%s %s\n' "$2" "${3:-}" > "$(hook_state_file "$1")"
}

# Bounded wait (<=~0.3s) until the spinner for a window has removed its pid file.
hook_spin_wait_stopped() {
  local p i; p="$(hook_pid_file "$1")"
  for i in 1 2 3 4 5 6; do [ -e "$p" ] || return 0; sleep 0.05; done
}

hook_rename() {
  tmux set-window-option -t "$1" automatic-rename off 2>/dev/null
  tmux rename-window -t "$1" "$2" 2>/dev/null
}

# Set or (with "-") unset the window-status-style.
hook_set_style() {
  if [ "$2" = "-" ]; then
    tmux set-window-option -u -t "$1" window-status-style 2>/dev/null
  else
    tmux set-window-option -t "$1" window-status-style "$2" 2>/dev/null
  fi
}

# True while the copilot TUI in <pane> is still busy (working / thinking / streaming
# / running a tool). Returns false ONLY when the pane's footer positively shows the
# idle prompt (copilot has returned to "ready for input"). We inspect and flatten the
# final four non-blank lines because narrow panes can wrap the controls above the
# model/context line. This still excludes body text behind the input box. If the pane
# can't be read, we assume busy so a live turn is never flipped to cancelled.
hook_pane_working() {
  local body footer
  body="$(tmux capture-pane -p -t "$1" 2>/dev/null)" || return 0
  footer="$(printf '%s\n' "$body" | grep -vE '^[[:space:]]*$' | tail -4 | tr '\n' ' ')"
  printf '%s' "$footer" | grep -qE "$hook_idle_footer_re" && return 1
  return 0
}

# Stop any spinner, then statically render "<marker> <name>" with <style>.
# hook_render_static <state> <marker|""> <style|"-"> <name>
hook_render_static() {
  local win; win="$(hook_window_id)"; [ -z "$win" ] && return 0
  hook_state_write "$win" "$1"
  hook_spin_wait_stopped "$win"
  hook_rename "$win" "${2:+$2 }${4:-copilot}"
  hook_set_style "$win" "$3"
}

# Stop any old spinner, then launch a fresh one in the requested active state.
# hook_start_spinner <working|finishing> <name>
hook_start_spinner() {
  local state="$1" name="$2" win gen pane
  win="$(hook_window_id)"; [ -z "$win" ] && return 0
  pane="$(hook_pane)"
  hook_state_write "$win" "idle"
  hook_spin_wait_stopped "$win"
  gen="$$$RANDOM$RANDOM"
  hook_state_write "$win" "$state" "$gen"
  tmux set-window-option -t "$win" automatic-rename off 2>/dev/null
  hook_set_style "$win" "$hook_style_working"
  setsid bash "$HOME/.copilot/hooks/copilot-spin.sh" "$win" "${name:-copilot}" "$gen" "$pane" 8>&- >/dev/null 2>&1 &
}

hook_start_working() {
  hook_start_spinner working "$1"
}

hook_start_finishing() {
  hook_start_spinner finishing "$1"
}
