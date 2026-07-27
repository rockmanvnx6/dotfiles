#!/usr/bin/env bash
# PreToolUse hook: every tool proves its agent is active, including autonomous resumes
# that have no UserPromptSubmit hook. Input tools stop the spinner until answered.
source "$HOME/.copilot/hooks/lib.sh"
hook_read_input
hook_debug
hook_in_tmux || exit 0
hook_lock_window || exit 0
if hook_is_input_tool; then
  state="$(hook_state_read)"
  hook_agent_mark_active
  hook_render_static input "$hook_marker_input" "$hook_style_input" "$(hook_session_name)"
  [ "$state" = input ] || hook_play "$hook_sound_input"
else
  state="$(hook_state_read)"
  if [ "$state" = working ]; then
    hook_agent_mark_active
  elif [ "$state" = input ] || hook_pane_working "$(hook_pane)"; then
    hook_agent_mark_active
    hook_start_working "$(hook_session_name)"
  fi
fi
exit 0
