---
name: run-markdown-server
description: Serve local Markdown files as a live-reloading web page. Use when someone wants to view rendered Markdown instead of raw text, or says things like "start/stop/check the markdown server" or "give me a link to that document".
---

# Run Markdown Server

`mdts` renders a directory of Markdown files as a browsable, live-reloading site.
This skill runs it as a **detached background server on 0.0.0.0**, so the docs stay
up after the current command finishes and are reachable from other devices on the
network.

Two properties matter and are easy to get wrong by hand:

- **Never block.** `npx mdts` in the foreground holds the terminal until killed. An
  agent that does that stalls its own session, so always go through the script below,
  which detaches the process and returns immediately.
- **Never auto-open.** `mdts` opens a browser by default. That's wrong here - the
  point is usually to read on *another* device, and a surprise browser window on a
  remote or headless machine is noise. The script always passes `--no-open`.

## Usage

Everything goes through the bundled script. It handles detaching, port selection,
LAN IP detection, and process bookkeeping.

```bash
SKILL_DIR/scripts/mdts-server.sh start [DIR] [-p PORT] [-g GLOB...]
SKILL_DIR/scripts/mdts-server.sh status
SKILL_DIR/scripts/mdts-server.sh stop [PORT|DIR|--all]
SKILL_DIR/scripts/mdts-server.sh logs [PORT]
```

`start` prints exactly what the user needs:

```
serving   /Users/me/project/docs
tailnet   http://100.x.y.z:8521   <- prefer this: reachable off-LAN, your devices only
lan       http://192.168.x.y:8521
local     http://localhost:8521
log       /Users/me/.local/state/mdts-server/8521.log
stop      .../mdts-server.sh stop 8521
```

The `tailnet` line only appears when Tailscale is running.

Behaviour worth knowing so you don't re-implement it:

- **No install step.** It shells out to `npx -y mdts`. The very first run downloads
  the package and can take up to a minute; the script waits for the port to actually
  accept connections before reporting success, so a slow start is not a failure.
  Give the call a generous timeout (120s+) rather than assuming it hung.
- **Port.** Takes 8521, or the next free port up to 8541. Pass `-p` only if the user
  asks for a specific one - a pinned port that's occupied is a hard error, whereas the
  default scan never fails.
- **Idempotent.** Starting a directory that's already served prints `already running`
  and reuses the existing server. Don't check `status` first just to avoid a duplicate.
- **Files vs directories.** `mdts` serves a tree. Pass a file path and the script
  serves its parent directory instead; link the user to the file (see below).
- **Filtering.** `-g '**/*.md'` narrows a large tree. Skip it unless the directory is
  noisy enough that the file list would be unusable.

## Choosing what to serve

Serve the smallest directory that still contains everything the reader needs. The
repo root is usually wrong - it buries the one document that matters under
`node_modules` and vendored files. Prefer `docs/`, the folder holding the generated
report, or the parent of the single file in question.

## Reporting back to the user

Hand over a routable URL, not localhost - that's the whole reason for binding
0.0.0.0, and it's what they'll paste into a phone.

**Lead with the tailnet URL when the script prints one.** It reaches the machine from
anywhere rather than only the current network, the address never changes, the traffic
is encrypted, and it's readable only by the user's own devices. Offer the LAN URL as
the fallback for a device that isn't on the tailnet. Deep-link to the specific
document by appending its path relative to the served directory:

```
http://100.x.y.z:8521/architecture/overview.md
```

Then stop. Don't screenshot it, don't curl it back and summarise it, don't paste the
Markdown into chat as well. The user asked for a page to read; handing them the URL
is the completed task.

If the LAN IP line says it couldn't be detected, the server is still fine - say so and
give the localhost URL, rather than treating it as a failed start.

## Verifying it works

Check liveness at the **root path only**:

```bash
curl -s -o /dev/null -w '%{http_code}' http://localhost:PORT/
```

`mdts` is a single-page app: every path returns the same HTML shell with a 200, and
routing to a document happens in the browser. So a 200 on `/some/doc.md` proves
nothing about that file existing, and there is no content API to query. If you want
to confirm a document is actually served, check the file exists on disk instead.

## LAN exposure

Binding 0.0.0.0 makes every Markdown file under the served directory readable by
anyone on the network. That needs no ceremony on a home or office LAN, and none at
all if the user sticks to the tailnet URL - Tailscale only admits their own devices.

The exposure that matters is the LAN address on a network the user doesn't control,
like cafe or conference wifi, or when the content is sensitive - credentials, private
notes, a client's material. Say so in one line and point them at the tailnet URL,
which solves it without changing anything. If Tailscale isn't available there, offer
`-H localhost` instead (edit the invocation directly; the script always binds 0.0.0.0
by design).

## Lifecycle

Servers outlive the session that started them - deliberately, so the user can keep
reading. Leave one running unless asked to stop it. `status` prunes dead entries
automatically, so what it lists is what's genuinely up.

When a user says "stop the markdown server", `stop` with no argument does the right
thing if exactly one is running and errors clearly if it's ambiguous. `stop --all`
cleans everything up.

## When called from another skill or workflow

Report the URL up the chain as the result and let the calling flow decide what to
say. Don't leave a server running as an invisible side effect of some larger task -
either surface the URL to the user or shut it down before finishing.

## Troubleshooting

`start` failing prints the last 20 log lines to stderr, which is normally enough.
Beyond that:

- **Nothing on the LAN URL from another device** - the server is fine (`status` and a
  localhost `curl` will confirm). Suspect the host firewall or client isolation on the
  wifi network, not `mdts`.
- **Stale or confusing state** - servers are tracked in
  `~/.local/state/mdts-server/PORT.server` with logs beside them. `stop --all` plus
  removing that directory is a clean reset.
