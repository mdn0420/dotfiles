#!/usr/bin/env bash
# Focus a tab by label in the focused workspace, or create it and run a command there.
# If the tab exists but every pane in it is sitting at an idle shell prompt, the
# command is restarted instead of just focusing a dead server.
#
# Usage: tab-run.sh <tab-label> <command...>
# Bound from ~/.config/herdr/config.toml via [[keys.command]] with type = "shell".
set -euo pipefail

label="${1:?usage: tab-run.sh <tab-label> <command...>}"
shift
command="$*"
[ -n "$command" ] || { echo "usage: tab-run.sh <tab-label> <command...>" >&2; exit 2; }

# A pane is idle when its foreground process group is the shell itself, i.e. no
# command is running. Any failure to read the pane counts as busy, so we never
# type into a pane we could not inspect.
pane_is_idle() {
  herdr pane process-info --pane "$1" \
    | jq -e '.result.process_info | .foreground_process_group_id == .shell_pid' >/dev/null 2>&1
}

workspace="$(herdr workspace list | jq -r '.result.workspaces[] | select(.focused) | .workspace_id')"
[ -n "$workspace" ] || { echo "no focused workspace" >&2; exit 1; }

existing="$(herdr tab list --workspace "$workspace" \
  | jq -r --arg label "$label" 'first(.result.tabs[] | select(.label == $label) | .tab_id) // empty')"

if [ -n "$existing" ]; then
  herdr tab focus "$existing" >/dev/null
  panes="$(herdr pane list --workspace "$workspace" \
    | jq -r --arg tab "$existing" '.result.panes[] | select(.tab_id == $tab) | .pane_id')"
  for pane in $panes; do
    pane_is_idle "$pane" || exit 0   # something is running here; leave it alone
  done
  # Every pane is at a prompt: the server is not running, so start it again.
  herdr pane run "$(echo "$panes" | head -1)" "$command" >/dev/null
  exit 0
fi

# No --cwd: terminal.new_cwd = "follow" inherits the workspace's directory.
pane="$(herdr tab create --workspace "$workspace" --label "$label" --focus \
  | jq -r '.result.root_pane.pane_id')"
herdr pane run "$pane" "$command" >/dev/null
