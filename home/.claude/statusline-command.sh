#!/usr/bin/env bash
# Status line: project dir [wt] | git branch | context tokens | Claude.ai rate limits (5h/7d) | model display name

input=$(cat)

# --- Segment 1: model display name ---
model=$(printf '%s' "$input" | jq -r '.model.display_name // empty' 2>/dev/null)
[ -z "$model" ] && model="Claude"

# --- Segment 2: project directory (abbreviate $HOME to ~), suffixed [wt] in a worktree ---
# cwd is still needed below for git lookups; project_dir is what gets displayed.
cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"
proj=$(printf '%s' "$input" | jq -r '.workspace.project_dir // empty' 2>/dev/null)
[ -z "$proj" ] && proj="$cwd"

# Resolve what to display to the project's MAIN root. `git worktree list` always
# reports the main tree first, so a session inside a linked worktree still shows
# the project root rather than the worktree's own path. Outside a git repo this
# stays as project_dir.
# Linked-worktree marker: prefer workspace.git_worktree (absent in the main tree),
# else compare git-dir against git-common-dir — a linked worktree's git-dir is
# <main>/.git/worktrees/<name> while its common-dir is <main>/.git, so they differ
# only outside the main tree. The fallback keeps [wt] working if the field is absent.
root="$proj"
in_worktree=$(printf '%s' "$input" | jq -r '.workspace.git_worktree // empty' 2>/dev/null)
if [ -d "$proj" ] && git -C "$proj" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  main_root=$(git -C "$proj" --no-optional-locks worktree list --porcelain 2>/dev/null \
    | awk 'NR==1 && /^worktree /{print substr($0,10); exit}')
  [ -n "$main_root" ] && root="$main_root"
  if [ -z "$in_worktree" ]; then
    gd=$(git -C "$proj" --no-optional-locks rev-parse --absolute-git-dir 2>/dev/null)
    gcd=$(git -C "$proj" --no-optional-locks rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    [ -n "$gd" ] && [ -n "$gcd" ] && [ "$gd" != "$gcd" ] && in_worktree=1
  fi
fi

dir_display="$root"
case "$root" in
  "$HOME") dir_display="~" ;;
  "$HOME"/*) dir_display="~${root#$HOME}" ;;
esac
[ -n "$in_worktree" ] && dir_display="${dir_display} [wt]"

# --- Segment 3: git branch, cleanly omitted when cwd is not inside a git repo ---
# Derived from $proj, not $cwd, so the branch always describes the directory
# actually shown in segment 2 (the two differ only if cwd changes mid-session).
branch=""
if [ -d "$proj" ] && git -C "$proj" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$proj" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)
fi

# --- Segment 4: context-window tokens currently resident in the window ---
# Resident occupancy = current_usage.input_tokens + cache_creation_input_tokens +
# cache_read_input_tokens (this is what used_percentage is derived from).
# Deliberately NOT total_input_tokens, which accumulates across the whole
# session and reads far higher than what is actually in the window right now;
# current_usage.output_tokens is also excluded since that's newly generated
# output from the last turn, not (yet) resident input context.
ctx_raw=$(printf '%s' "$input" | jq -r '
  if .context_window.current_usage then
    ((.context_window.current_usage.input_tokens // 0)
     + (.context_window.current_usage.cache_creation_input_tokens // 0)
     + (.context_window.current_usage.cache_read_input_tokens // 0))
  else empty end' 2>/dev/null)

format_tokens() {
  awk -v n="$1" 'BEGIN {
    if (n < 1000) {
      printf "%d", n
    } else if (n < 1000000) {
      printf "%dk", int(n / 1000 + 0.5)
    } else {
      val = n / 1000000
      s = sprintf("%.1f", val)
      sub(/\.0$/, "", s)
      printf "%sM", s
    }
  }'
}

ctx_disp="--"
[ -n "$ctx_raw" ] && ctx_disp=$(format_tokens "$ctx_raw")

# --- Segment 5: Claude.ai rate limits (5h / 7d usage); "--" placeholder when unavailable ---
five=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
week=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)
five_disp="--"
week_disp="--"
[ -n "$five" ] && five_disp=$(printf '%.0f%%' "$five" 2>/dev/null)
[ -n "$week" ] && week_disp=$(printf '%.0f%%' "$week" 2>/dev/null)
rate="5h:${five_disp} 7d:${week_disp}"

# --- ANSI colors (built via printf so escapes are always interpreted) ---
RESET=$(printf '\033[0m')
DIM=$(printf '\033[2m')
MODEL_COLOR=$(printf '\033[36m')   # cyan
DIR_COLOR=$(printf '\033[33m')     # yellow
BRANCH_COLOR=$(printf '\033[32m')  # green
CTX_COLOR=$(printf '\033[34m')     # blue
RATE_COLOR=$(printf '\033[35m')    # magenta
SEP="${DIM} | ${RESET}"

out="${DIR_COLOR}${dir_display}${RESET}"
[ -n "$branch" ] && out="${out}${SEP}${BRANCH_COLOR}⎇ ${branch}${RESET}"
out="${out}${SEP}${CTX_COLOR}${ctx_disp}${RESET}"
out="${out}${SEP}${RATE_COLOR}${rate}${RESET}"
out="${out}${SEP}${MODEL_COLOR}${model}${RESET}"

printf '%s' "$out"
