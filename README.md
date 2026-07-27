Simply:


`cp -r nvim ~/.config/nvim`
`cp -r neovide ~/.config/neovide`


Download JetbrainsMono Nerd Font

## Copilot CLI
`cp copilot/settings.json copilot/copilot-instructions.md ~/.copilot/`
`mkdir -p ~/.copilot/hooks && cp copilot/hooks/*.sh ~/.copilot/hooks/ && chmod +x ~/.copilot/hooks/*.sh`
Hooks (share `hooks/lib.sh`) drive a per-window tmux state machine named after the session: while any parent agent, background agent, or agent-owned shell command works, an animated braille spinner (`copilot-spin.sh`, ~8fps, blue) runs on the window. UserPromptSubmit and PreToolUse register the active session ID, including autonomous resumes that have no new user prompt; Stop removes only that session. After the final agent stops, the window enters a `finishing` spinner state until Copilot's own footer reports idle, so a remote build running in another pane does not produce a premature green `✓`. The done marker and completion sound appear only after that idle transition. Per-window locking serializes concurrent lifecycle hooks. When the agent needs input it shows a yellow `(?)`; `AskUserQuestion` (ask_user) and `exit_plan_mode` (plan ready for review) also sound once when entering that state, while permission and elicitation notifications remain silent. The matching PostToolUse hook resumes the spinner once the answer or plan is resolved. The cancellation watchdog clears stale active-agent markers when Copilot returns to its idle prompt without firing Stop. Styles, markers, spinner frames and sounds are centralised in `lib.sh` (`hook_style_*`, `hook_marker_*`, `hook_spinner_frames`, `hook_spinner_delay`, `hook_sound_*`). For debugging, `touch ~/.copilot/hooks/.debug` to log raw hook payloads to `hooks/debug.log` (`rm` the sentinel to stop). The hooks are global across every running Copilot session, so each hook first checks `hook_in_tmux` (`$TMUX`/`$TMUX_PANE`) and no-ops for headless or piped runs: those make no sound and never grab the active pane (`hook_pane` only falls back to `tmux display-message` when `$TMUX` is set).

## lazygit
`mkdir -p ~/.config/lazygit && cp lazygit/config.yml ~/.config/lazygit/config.yml`

## WezTerm
`cp .wezterm.lua ~/`
JetBrainsMono Nerd Font Mono @ 12 (download the Nerd Font above), `Dark+` color scheme (VSCode's default dark theme, bundled with WezTerm), 0.95 background opacity, minimal window (title-bar buttons integrated into the tab bar, which hides itself at a single tab), zeroed top/bottom padding so content fills the height, and system + visual bell. `custom_block_glyphs` is off so braille (e.g. the tmux copilot spinner) renders from the font on the baseline. WezTerm auto-reloads the config on save.
