#!/usr/bin/env bash
# Reparent claude-mem memories from deleted git worktrees back onto their repo.
#
# claude-mem files a worktree session under "<repo>/<worktree-dir>" and a session
# in the repo itself only ever reads "<repo>" — an exact match, no prefix
# expansion. So the moment a worktree is deleted, everything learned in it
# becomes unreachable from the repo it belongs to.
#
# The plugin ships `worker-service.cjs adopt` for this, but it only considers
# worktrees still present in `git worktree list`, which is never true once the
# branch is merged and the worktree cleaned up. This sweep covers that gap:
# any child project whose worktree is gone is folded back into the parent.
#
# Idempotent — live worktrees are left alone, reparented rows no-op.
# The original name is kept in observations.metadata.original_project.
set -euo pipefail

DRY_RUN=0
TARGET="$PWD"
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --cwd)     TARGET="${2:?--cwd needs a path}"; shift 2 ;;
    *) echo "usage: $(basename "$0") [--dry-run] [--cwd <repo>]" >&2; exit 1 ;;
  esac
done

DATA_DIR="${CLAUDE_MEM_DATA_DIR:-$HOME/.claude-mem}"
DB="$DATA_DIR/claude-mem.db"
CHROMA_DB="$DATA_DIR/chroma/chroma.sqlite3"
[ -f "$DB" ] || exit 0

# Resolve the main worktree even when invoked from inside a worktree.
COMMON_DIR=$(git -C "$TARGET" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
REPO_ROOT=${COMMON_DIR%/.git}
REPO_ROOT=${REPO_ROOT%/}
[ -d "$REPO_ROOT" ] || exit 0
PARENT=$(basename "$REPO_ROOT")

# SQL string literal, single quotes doubled.
q() { printf "'%s'" "${1//\'/\'\'}"; }

# Basenames of worktrees that still exist; their memories stay where they are.
LIVE_SQL=""
while IFS= read -r wt; do
  [ -n "$wt" ] || continue
  [ "$wt" = "$REPO_ROOT" ] && continue
  LIVE_SQL="${LIVE_SQL:+$LIVE_SQL,}$(q "$(basename "$wt")")"
done < <(git -C "$REPO_ROOT" worktree list --porcelain 2>/dev/null | sed -n 's|^worktree ||p')
[ -n "$LIVE_SQL" ] || LIVE_SQL="''"

PQ=$(q "$PARENT")
PREFIX=$(q "$PARENT/")
DEAD_PREDICATE="substr(project, 1, length($PQ) + 1) = $PREFIX
                 AND substr(project, length($PQ) + 2) NOT IN ($LIVE_SQL)"

DEAD=$(sqlite3 -readonly -cmd ".timeout 10000" "$DB" "
  SELECT DISTINCT project FROM (
    SELECT project FROM observations
    UNION SELECT project FROM session_summaries
    UNION SELECT project FROM sdk_sessions
  ) WHERE $DEAD_PREDICATE ORDER BY project;")

if [ -z "$DEAD" ]; then
  [ "$DRY_RUN" = 1 ] && echo "[$PARENT] no memories stranded in deleted worktrees"
  exit 0
fi

COUNT=$(sqlite3 -readonly -cmd ".timeout 10000" "$DB" "
  SELECT COUNT(*) FROM observations WHERE $DEAD_PREDICATE;")
WT_COUNT=$(printf '%s\n' "$DEAD" | wc -l | tr -d ' ')

if [ "$DRY_RUN" = 1 ]; then
  echo "[$PARENT] would reparent $COUNT observations from $WT_COUNT deleted worktree(s):"
  printf '%s\n' "$DEAD" | sed 's/^/  /'
  exit 0
fi

sqlite3 "$DB" <<SQL
.timeout 30000
BEGIN IMMEDIATE;
UPDATE observations
   SET metadata = json_set(
         CASE WHEN metadata IS NOT NULL AND json_valid(metadata) THEN metadata ELSE '{}' END,
         '\$.original_project', project),
       project = $PQ,
       merged_into_project = NULL
 WHERE $DEAD_PREDICATE;
UPDATE session_summaries
   SET project = $PQ, merged_into_project = NULL
 WHERE $DEAD_PREDICATE;
UPDATE sdk_sessions
   SET project = $PQ
 WHERE $DEAD_PREDICATE;
COMMIT;
SQL

# Keep the vector store's project metadata in step, or semantic search filtered
# by the parent keeps missing these documents.
if [ -f "$CHROMA_DB" ]; then
  DEAD_SQL=""
  while IFS= read -r p; do DEAD_SQL="${DEAD_SQL:+$DEAD_SQL,}$(q "$p")"; done <<< "$DEAD"
  sqlite3 -cmd ".timeout 30000" "$CHROMA_DB" "
    UPDATE embedding_metadata SET string_value = $PQ
     WHERE key = 'project' AND string_value IN ($DEAD_SQL);" \
    || echo "[$PARENT] warning: chroma metadata not patched (store busy?)" >&2
fi

echo "[$PARENT] reparented $COUNT observations from $WT_COUNT deleted worktree(s)"
