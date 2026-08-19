# global agent instructions

- Never use the em dash "—". Use plain dash "-" instead
- When writing commit messages, NEVER auto-add your agent name as co-author
- Never manually modify CHANGELOG.md files or any files that are marked as auto-generated
- When making technical decisions, do not give much weight to development cost.
  Instead, prefer quality, simplicity, robustness, scalability, and long term maintainability.
- For one-off or infrequent operational work, start with the simplest direct end-to-end path. Do not build wrappers, control planes, policy layers, custom verifiers, or automation unless the direct path exposes a concrete blocker or repeated need that justifies the added machinery.
- When doing bug fixes, always start with reproducing the bug in an E2E setting as closely aligned with how an end user would experience it as possible.
  This makes sure you find the real problem so your fix will actually solve it.
- When end-to-end testing a product, be picky about the UI you see and be obsessed with pixel perfection.
  If something clearly looks off, even if it is not directly related to what you are doing, try to get it fixed along the way.
- Apply that same high standard to engineering excellence: lint, test failures, and test flakiness.
  If you see one, even if it is not caused by what you are working on right now, still get it fixed.
- Before using "dynamic workflows", "ultra code" or any harness feature that immediately spawns a large swarm of subagents, always explain the tradeoffs and ask the user for explicit approval.
- Always use context7 when I need code generation, setup or configuration steps, or
library/API documentation. This means you should automatically use the Context7 MCP
tools to resolve library id and get library docs without me having to explicitly ask.

## superpowers:subagent-driven-development — model assignment

This OVERRIDES the skill's "Model Selection" section. That section tells you to
scale down by diff size and use the cheapest tier that fits. Ignore it. The table
below is an assignment, not a ceiling to optimize below.

| Role (by the skill's own dispatch prompt) | Model |
|---|---|
| Implementer — `implementer-prompt.md`, 1-2 files with a complete spec | Sonnet |
| Implementer — anything else | Opus |
| Fix-loop escalation implementer (rounds 4-5) | Opus |
| Task review — `task-reviewer-prompt.md` | **Opus**, regardless of diff size |
| Scoped re-review — `re-review-prompt.md` | **Opus**. "Small fix diff" is not an exception |
| Final whole-branch review | Fable |

Haiku is never used for any subagent under this skill.

If you are about to pick a cheaper model than this table because the diff looks
small, mechanical, or low-risk — that is the exact rationalization this override
exists to block. Cost is my call, not yours.

## superpowers:brainstorming and superpowers:writing-plans - serve the doc for review

Both skills end by handing me a Markdown file to review, and a path in the terminal is
a poor way to read a long spec or plan. At each of these two gates, use the
`run-markdown-server` skill and give me the rendered URL alongside the file path:

- **brainstorming** - at the User Review Gate, once the spec is saved under
  `docs/superpowers/specs/` and the spec self-review has passed
- **writing-plans** - when the plan is saved under `docs/superpowers/plans/` and the
  execution options are presented

Serve `docs/superpowers/` rather than either subdirectory, so one server covers the
specs and plans for the whole session, and deep-link to the document just written.
Leave it running; I read these on a second device while you keep working.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
