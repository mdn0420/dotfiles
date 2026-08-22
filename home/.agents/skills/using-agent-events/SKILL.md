---
name: using-agent-events
description: Use when you need to know what ANOTHER Claude session on this machine is doing - waiting until a peer session finishes its turn or goes idle, noticing it is blocked on a permission prompt, or reacting when it starts or exits. For coordinating with sibling agents, orchestrator/worker handoffs, and blocking until a peer is done.
---

# Using Agent Events

`agent-events` streams **lifecycle events for other Claude Code sessions on this
machine**: when a session starts, submits a prompt, finishes a turn, blocks on an
approval, or exits.

```
SKILL_DIR/scripts/agent-events sessions
SKILL_DIR/scripts/agent-events listen --session <sel> --event <list> [flags]
```

Installed path: `~/.claude/skills/using-agent-events/scripts/agent-events`

It is a **pure reader**. It derives events by polling moshi-hook's per-session state
store (`~/Library/Application Support/Moshi/claude-sessions/*.json`) — files moshi
already writes on every hook fire. It registers no hooks, installs nothing, starts no
daemon, and needs no rebuild. Running it cannot affect the sessions it watches.

## When to use this instead of the native tools

| You want | Native tool | Why it falls short |
|---|---|---|
| "Is session X busy right now?" | `ListAgents` | Point-in-time snapshot. No watch, no history — you'd have to poll it yourself. |
| "Tell me when X is done" | `SendMessage` `notify_when_idle` | One-shot, idle-or-exit only, and only for sessions it can address. No permission blocks, no prompt submissions, no tool use. |
| "Stream everything X does until I say stop" | — | Nothing native does this. |
| "Wake me when *any* peer blocks on approval" | — | Nothing native does this. |

Use `ListAgents` for a one-off "who's running". Use this skill when you need to
**wait on** or **react to** a peer.

## Quick reference

```bash
agent-events sessions            # live sessions, one per line:
                                 #   status  age  id  name  model  pid  cwd
                                 # age = how long ago that session's state was last
                                 # written, NOT how long it has been running

agent-events listen \
  --session <selector>            # default: all
  --event Stop,SessionEnd         # comma-separated; default: all
  --exclude-session <selector>    # suppress matches (see "Don't wake on yourself")
  --since <epoch>                 # replay events at/after this time, then follow
  --once                          # exit on first match
  --no-follow                     # replay only, don't follow
  --json                          # JSON lines instead of text
  --interval 1.0                  # poll seconds
```

**Selectors**

| Form | Example | Matches |
|---|---|---|
| `all` | `all` | every session |
| uuid prefix (4+ hex) | `c569997e` | that session id |
| `@name` | `@feature-eng-98` | herdr workspace, or cwd basename |
| glob | `'*hyperscout*'` | cwd, or the transcript project slug |

**Events**

| Event | Fires when |
|---|---|
| `SessionStart` | a new session appears with a live process |
| `UserPromptSubmit` | the session was given a new prompt |
| `Stop` | the turn finished — **this is "the session went idle"** |
| `PermissionRequest` | blocked awaiting approval |
| `PermissionResolved` | that approval was answered |
| `ToolUse` | tool changed (only `AskUserQuestion`, `ExitPlanMode` — see caveats) |
| `SessionEnd` | the session's process is gone |

## The two patterns

**Block until a peer finishes.** `--once` exits on first match, so this is a
one-line "wait for":

```bash
agent-events listen --session @feature-eng-98 --event Stop --once
```

Run it with Bash `run_in_background` and you get re-invoked when it exits — no
polling loop, no sleep.

**Watch a stream of events.** Output is flushed per line, so it feeds a `Monitor`
call directly:

```bash
agent-events listen --session all --event Stop,PermissionRequest \
  --exclude-session <your-own-uuid-prefix>
```

**Catch up on what you missed.** `--since` replays from the state store before
following, which recovers events that happened while you weren't listening:

```bash
agent-events listen --session all --event Stop --since 1755865740 --no-follow
```

## Don't wake on yourself

`--session all` includes **your own session**. An agent that listens for `Stop` on
`all` and then acts will see its own `Stop`, act, emit another `Stop`, and spin.

Always pass `--exclude-session` with your own uuid prefix or `@name` when the
selector could match you. Get your own id from `agent-events sessions` (yours is the
one showing `working`) or from your transcript path.

## Caveats — read these before trusting the output

These are inherent to deriving events from a rewritten-in-place state store rather
than from an event log. None of them are bugs to be fixed here.

- **Same-kind events inside one poll interval collapse into one.** Two `Stop`s from
  the same session 200ms apart at `--interval 1.0` surface as one `Stop`. Different
  event kinds are unaffected. Lower `--interval` narrows the window; it never closes
  it.

- **`SubagentStop`, `PreCompact` and `Notification` are not observable at all.**
  moshi does not register for those hooks, so nothing is recorded to read. Don't try
  to detect subagent completion with this.

- **`ToolUse` covers only `AskUserQuestion` and `ExitPlanMode`.** It is not general
  tool tracing. A session running Bash all day emits no `ToolUse`.

- **`sessions` liveness is best-effort, not authoritative.** Sessions with no
  terminal (background jobs) carry no `agentPid` and no `cwd`; they are named from
  the transcript project slug and their liveness falls back to recent file mtime.

- **A live session whose hook stream stalls reads `idle` forever.** Status is
  *derived* from the last recorded state, so a session that stopped firing hooks is
  indistinguishable from one that finished. **The `age` column is the tell:**

  ```
  working    47s  e025cf18 gitrepos-dotfiles  opus-5  pid=None
  idle       14h  0965e30b hyperscout         opus-5  pid=85148  /Users/mnguyen/gitrepos/hyperscout
  ```

  That second row has a live pid and reads `idle`, but its state has not been touched
  in 14 hours — and `/list-agents` reports it busy. A large age next to a live pid
  means the status is stale, not that the session is quiet. **Never trust this tool
  over your own eyes** — if `/list-agents` or the user says otherwise, they're right.

- **`SessionEnd` lags by up to one poll interval**, since it's inferred from process
  death rather than announced.

## Common mistakes

| Mistake | Fix |
|---|---|
| Listening on `all` and reacting → infinite self-trigger | `--exclude-session <your own>` |
| Polling `sessions` in a loop to wait for a peer | `listen --once`, backgrounded |
| Expecting `ToolUse` to trace every tool | Only `AskUserQuestion` / `ExitPlanMode` |
| Waiting on `SubagentStop` | Not observable — use `Stop` on the parent session |
| Treating `idle` as proof a session is done | Check the `age` column; see caveats |
