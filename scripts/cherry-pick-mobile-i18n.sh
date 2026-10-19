#!/usr/bin/env bash
# Cherry-pick upstream commits in [FROM, TO] that touch mobile/ or i18n/,
# applying only those paths. Progress is stored next to this script as a
# human-readable status file; a later run resumes after the last successful
# commit (or retries the paused conflict).
#
# Usage:
#   ./scripts/cherry-pick-mobile-i18n.sh --from v2.7.5 --to v3.1.0
#   ./scripts/cherry-pick-mobile-i18n.sh --status
#   ./scripts/cherry-pick-mobile-i18n.sh --dry-run
#   ./scripts/cherry-pick-mobile-i18n.sh --continue
#   ./scripts/cherry-pick-mobile-i18n.sh --skip
#   ./scripts/cherry-pick-mobile-i18n.sh --reset-state
#
# Env still works as defaults: FROM=v2.7.5 TO=v3.1.0

set -euo pipefail

FROM_REF="${FROM:-v2.7.5}"
TO_REF="${TO:-v3.1.0}"
FROM_CLI=0
TO_CLI=0
CMD=""
PATHSPECS=(mobile i18n)

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$SCRIPT_DIR/cherry-pick-mobile-i18n.state"
LEGACY_STATE_FILE="$ROOT/.git/cherry-pick-mobile-i18n.state"
PATHSPEC_RE='^(mobile|i18n)(/|$)'

usage() {
  cat <<EOF
Cherry-pick commits that touch mobile/ or i18n/, keeping only changes under
those directories.

Usage: $(basename "$0") [options] [command]

Options:
  --from REF      Range start (default: ${FROM:-v2.7.5}, or FROM env)
  --to REF        Range end (default: ${TO:-v3.1.0}, or TO env)

Commands:
  (default)       Apply next commits until finished or a conflict
  --continue      Same as default; use after resolving a conflict
  --status        Show progress and pause state
  --dry-run       List commits that would be applied (respects resume point)
  --skip          Drop the paused conflicting commit and continue
  --reset-state   Forget progress (does not change the working tree)
  -h, --help      Show this help

Progress file (human-readable):
  ${STATE_FILE#"$ROOT"/}

On conflict the script stops, updates that file, and leaves markers in
mobile/ / i18n/. Resolve them, git add the files, then:
  $0 --continue
Do not commit manually — the script will create the commit and continue.
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

log() {
  echo "$*"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --from)
        [[ $# -ge 2 ]] || die "--from requires a value"
        FROM_REF="$2"
        FROM_CLI=1
        shift 2
        ;;
      --to)
        [[ $# -ge 2 ]] || die "--to requires a value"
        TO_REF="$2"
        TO_CLI=1
        shift 2
        ;;
      -h|--help|--status|--dry-run|--skip|--reset-state|--continue)
        [[ -z "$CMD" ]] || die "multiple commands: $CMD and $1"
        CMD="$1"
        shift
        ;;
      *)
        usage
        die "unknown argument: $1"
        ;;
    esac
  done
}

read_state_kv() {
  local file="$1"
  local key="$2"
  local line value
  [[ -f "$file" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    case "$line" in
      "$key="*)
        value="${line#"$key="}"
        # strip optional surrounding quotes from legacy shell-quoted values
        value="${value#\'}"
        value="${value%\'}"
        printf '%s' "$value"
        return 0
        ;;
    esac
  done <"$file"
  return 1
}

migrate_legacy_state_if_needed() {
  [[ -f "$STATE_FILE" ]] && return 0
  [[ -f "$LEGACY_STATE_FILE" ]] || return 0

  local legacy_from="" legacy_to="" legacy_last="" legacy_paused=""
  # Legacy file was shell-sourced: FROM_REF_SAVED=... LAST_APPLIED=...
  # shellcheck disable=SC1090
  source "$LEGACY_STATE_FILE"
  legacy_from="${FROM_REF_SAVED:-}"
  legacy_to="${TO_REF_SAVED:-}"
  legacy_last="${LAST_APPLIED:-}"
  legacy_paused="${PAUSED_AT:-}"

  if [[ "$FROM_CLI" -eq 1 && -n "$legacy_from" && "$legacy_from" != "$FROM_REF" ]]; then
    die "legacy state has from=$legacy_from but --from=$FROM_REF was given. Use --reset-state or match --from."
  fi
  if [[ "$TO_CLI" -eq 1 && -n "$legacy_to" && "$legacy_to" != "$TO_REF" ]]; then
    die "legacy state has to=$legacy_to but --to=$TO_REF was given. Use --reset-state or match --to."
  fi
  if [[ "$FROM_CLI" -eq 0 && -n "$legacy_from" ]]; then
    FROM_REF="$legacy_from"
  fi
  if [[ "$TO_CLI" -eq 0 && -n "$legacy_to" ]]; then
    TO_REF="$legacy_to"
  fi
  LAST_APPLIED="$legacy_last"
  PAUSED_AT="$legacy_paused"

  log "Migrating progress from .git/ to ${STATE_FILE#"$ROOT"/}"
  save_state
  rm -f "$LEGACY_STATE_FILE"
}

load_state() {
  LAST_APPLIED=""
  PAUSED_AT=""

  migrate_legacy_state_if_needed

  [[ -f "$STATE_FILE" ]] || return 0

  local saved_from saved_to saved_last saved_paused
  saved_from="$(read_state_kv "$STATE_FILE" from || true)"
  saved_to="$(read_state_kv "$STATE_FILE" to || true)"
  saved_last="$(read_state_kv "$STATE_FILE" last_applied || true)"
  saved_paused="$(read_state_kv "$STATE_FILE" paused_at || true)"

  # Also accept legacy key names if someone copied an old file
  if [[ -z "$saved_from" ]]; then
    saved_from="$(read_state_kv "$STATE_FILE" FROM_REF_SAVED || true)"
  fi
  if [[ -z "$saved_to" ]]; then
    saved_to="$(read_state_kv "$STATE_FILE" TO_REF_SAVED || true)"
  fi
  if [[ -z "$saved_last" ]]; then
    saved_last="$(read_state_kv "$STATE_FILE" LAST_APPLIED || true)"
  fi
  if [[ -z "$saved_paused" ]]; then
    saved_paused="$(read_state_kv "$STATE_FILE" PAUSED_AT || true)"
  fi

  if [[ "$FROM_CLI" -eq 1 ]]; then
    if [[ -n "$saved_from" && "$saved_from" != "$FROM_REF" ]]; then
      die "state has from=$saved_from but --from=$FROM_REF was given. Use --reset-state or match --from."
    fi
  elif [[ -n "$saved_from" ]]; then
    FROM_REF="$saved_from"
  fi

  if [[ "$TO_CLI" -eq 1 ]]; then
    if [[ -n "$saved_to" && "$saved_to" != "$TO_REF" ]]; then
      die "state has to=$saved_to but --to=$TO_REF was given. Use --reset-state or match --to."
    fi
  elif [[ -n "$saved_to" ]]; then
    TO_REF="$saved_to"
  fi

  LAST_APPLIED="$saved_last"
  PAUSED_AT="$saved_paused"
}

progress_snapshot() {
  local total=0 done=0 next="(all done)" status="idle"
  local last_short="(none)" paused_short="(none)" last_subj="" paused_subj=""

  if [[ -n "${COMMITS+x}" && ${#COMMITS[@]} -gt 0 ]]; then
    total="${#COMMITS[@]}"
  fi

  if [[ -n "${LAST_APPLIED:-}" ]]; then
    last_short="${LAST_APPLIED:0:12}"
    last_subj="$(git log -1 --format=%s "$LAST_APPLIED" 2>/dev/null || echo "(missing)")"
    if [[ "$total" -gt 0 ]] && idx="$(index_of_commit "$LAST_APPLIED")"; then
      done=$((idx + 1))
      if (( done < total )); then
        next="${COMMITS[$done]:0:12} $(git log -1 --format=%s "${COMMITS[$done]}")"
        status="in progress"
      else
        status="done"
      fi
    else
      done="?"
      next="last_applied ${last_short} is not in the commit list"
      status="stale"
    fi
  elif (( total > 0 )); then
    next="${COMMITS[0]:0:12} $(git log -1 --format=%s "${COMMITS[0]}")"
    status="ready"
  fi

  if [[ -n "${PAUSED_AT:-}" ]]; then
    paused_short="${PAUSED_AT:0:12}"
    paused_subj="$(git log -1 --format=%s "$PAUSED_AT" 2>/dev/null || echo "(missing)")"
    status="paused"
    next="${paused_short} ${paused_subj} (resolve, then --continue)"
  fi

  PROGRESS_STATUS="$status"
  PROGRESS_DONE="$done"
  PROGRESS_TOTAL="$total"
  PROGRESS_NEXT="$next"
  PROGRESS_LAST_SHORT="$last_short"
  PROGRESS_LAST_SUBJ="$last_subj"
  PROGRESS_PAUSED_SHORT="$paused_short"
  PROGRESS_PAUSED_SUBJ="$paused_subj"
}

save_state() {
  progress_snapshot
  local updated
  updated="$(date '+%Y-%m-%d %H:%M:%S %z')"

  cat >"$STATE_FILE" <<EOF
# Cherry-pick mobile/ + i18n/ progress
# Managed by scripts/cherry-pick-mobile-i18n.sh — safe to read; avoid hand-edits while running.
#
# After a conflict:
#   git add mobile i18n
#   ./scripts/cherry-pick-mobile-i18n.sh --continue
#
# Other: --status | --skip | --reset-state | --dry-run

status:        ${PROGRESS_STATUS}
range:         ${FROM_REF} .. ${TO_REF}
progress:      ${PROGRESS_DONE} / ${PROGRESS_TOTAL} commits applied
last_applied:  ${PROGRESS_LAST_SHORT} ${PROGRESS_LAST_SUBJ}
paused_at:     ${PROGRESS_PAUSED_SHORT} ${PROGRESS_PAUSED_SUBJ}
next:          ${PROGRESS_NEXT}
updated:       ${updated}

# --- machine fields ---
from=${FROM_REF}
to=${TO_REF}
last_applied=${LAST_APPLIED:-}
paused_at=${PAUSED_AT:-}
EOF
}

clear_pause() {
  PAUSED_AT=""
  save_state
  git cherry-pick --quit >/dev/null 2>&1 || true
  rm -f "$ROOT/.git/CHERRY_PICK_HEAD"
}

is_our_path() {
  [[ "$1" =~ $PATHSPEC_RE ]]
}

unmerged_files() {
  git diff --name-only --diff-filter=U
}

worktree_dirty() {
  ! git diff --quiet || ! git diff --cached --quiet
}

drop_unrelated_paths() {
  local file
  local files
  files="$(
    {
      git diff --name-only HEAD 2>/dev/null || true
      git diff --name-only --cached 2>/dev/null || true
      git ls-files -u | awk '{print $4}'
    } | sort -u
  )"

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    if is_our_path "$file"; then
      continue
    fi
    if ! git restore --source=HEAD --staged --worktree -- "$file" 2>/dev/null; then
      git rm -f -- "$file" >/dev/null 2>&1 || rm -rf -- "$file"
    fi
  done <<<"$files"
}

has_staged_pathspec_changes() {
  ! git diff --cached --quiet -- "${PATHSPECS[@]}"
}

commit_filtered() {
  local sha="$1"
  local subject message

  subject="$(git log -1 --format=%s "$sha")"
  message="$(git log -1 --format=%B "$sha")"
  message="${message%"${message##*[![:space:]]}"}"
  message+=$'\n\n'"Cherry-picked from ${sha} (mobile/i18n only)."

  GIT_AUTHOR_NAME="$(git log -1 --format=%an "$sha")"
  GIT_AUTHOR_EMAIL="$(git log -1 --format=%ae "$sha")"
  GIT_AUTHOR_DATE="$(git log -1 --format=%aD "$sha")"
  export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_AUTHOR_DATE

  git commit -m "$message"
  log "  committed: ${sha:0:12} ${subject}"
}

list_commits() {
  git rev-list --reverse --no-merges "${FROM_REF}..${TO_REF}" -- "${PATHSPECS[@]}"
}

index_of_commit() {
  local needle="$1"
  local i=0
  local sha
  for sha in "${COMMITS[@]}"; do
    if [[ "$sha" == "$needle" ]]; then
      echo "$i"
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

pause_on_conflict() {
  local sha="$1"
  local subject
  subject="$(git log -1 --format=%s "$sha")"
  PAUSED_AT="$sha"
  save_state

  echo
  log "CONFLICT at ${sha:0:12} — ${subject}"
  log "Only mobile/ and i18n/ are kept; unrelated paths were dropped."
  log "Status: ${STATE_FILE#"$ROOT"/}"
  if [[ -n "$(unmerged_files)" ]]; then
    log "Unmerged files:"
    unmerged_files | sed 's/^/  /'
  fi
  echo
  log "Resolve conflicts, then:"
  log "  git add mobile i18n"
  log "  $0 --continue"
  log "To skip this commit: $0 --skip"
  exit 1
}

finish_paused_if_possible() {
  [[ -n "${PAUSED_AT:-}" ]] || return 0

  local sha="$PAUSED_AT"
  local subject
  subject="$(git log -1 --format=%s "$sha")"

  if [[ -n "$(unmerged_files)" ]]; then
    log "Still paused on ${sha:0:12} — ${subject}"
    log "Unmerged files:"
    unmerged_files | sed 's/^/  /'
    log "Resolve them, git add, then: $0 --continue"
    log "Or skip: $0 --skip"
    exit 1
  fi

  drop_unrelated_paths

  if has_staged_pathspec_changes; then
    commit_filtered "$sha"
    LAST_APPLIED="$sha"
    clear_pause
    log "Resumed: recorded ${sha:0:12} and continuing."
    return 0
  fi

  if worktree_dirty; then
    die "working tree is dirty after pause on ${sha:0:12}. Commit/stash unrelated changes, or finish resolving mobile/i18n."
  fi

  # Clean tree: user already committed (or reset). Treat as applied so we
  # do not replay the same commit.
  log "Pause commit ${sha:0:12} looks finished; continuing from the next one."
  LAST_APPLIED="$sha"
  clear_pause
}

apply_one() {
  local sha="$1"
  local subject
  subject="$(git log -1 --format=%s "$sha")"

  local rc=0
  git cherry-pick --no-commit "$sha" || rc=$?

  drop_unrelated_paths

  if [[ -n "$(unmerged_files)" ]]; then
    pause_on_conflict "$sha"
  fi

  if [[ "$rc" -ne 0 ]]; then
    # Cherry-pick failed but no unmerged pathspec files remain — usually
    # conflicts lived only in dropped paths, or the apply was empty.
    if ! has_staged_pathspec_changes; then
      git cherry-pick --quit >/dev/null 2>&1 || true
      log "  skip (no mobile/i18n changes after 3-way): ${sha:0:12} ${subject}"
      LAST_APPLIED="$sha"
      save_state
      return 0
    fi
  fi

  if ! has_staged_pathspec_changes; then
    git cherry-pick --quit >/dev/null 2>&1 || true
    log "  skip (empty): ${sha:0:12} ${subject}"
    LAST_APPLIED="$sha"
    save_state
    return 0
  fi

  commit_filtered "$sha"
  git cherry-pick --quit >/dev/null 2>&1 || true
  LAST_APPLIED="$sha"
  save_state
}

print_status() {
  progress_snapshot
  log "status:  ${PROGRESS_STATUS}"
  log "range:   ${FROM_REF}..${TO_REF}"
  log "commits: ${PROGRESS_DONE}/${PROGRESS_TOTAL} applied (mobile/i18n only)"
  log "next:    ${PROGRESS_NEXT}"
  if [[ -n "${PAUSED_AT:-}" ]]; then
    log "paused:  ${PROGRESS_PAUSED_SHORT} ${PROGRESS_PAUSED_SUBJ}"
  fi
  log "file:    ${STATE_FILE#"$ROOT"/}"
}

parse_args "$@"

case "$CMD" in
  -h|--help)
    usage
    exit 0
    ;;
esac

load_state

git rev-parse --verify "${FROM_REF}^{commit}" >/dev/null \
  || die "cannot resolve FROM=${FROM_REF}"
git rev-parse --verify "${TO_REF}^{commit}" >/dev/null \
  || die "cannot resolve TO=${TO_REF}"

COMMITS=()
while IFS= read -r sha; do
  [[ -n "$sha" ]] && COMMITS+=("$sha")
done < <(list_commits)
TOTAL="${#COMMITS[@]}"
(( TOTAL > 0 )) || die "no commits touching mobile/ or i18n/ in ${FROM_REF}..${TO_REF}"

case "$CMD" in
  --status)
    print_status
    # refresh human-readable file even on status
    save_state
    exit 0
    ;;
  --reset-state)
    rm -f "$STATE_FILE" "$LEGACY_STATE_FILE"
    git cherry-pick --quit >/dev/null 2>&1 || true
    log "State cleared (${STATE_FILE#"$ROOT"/}). Next run will start from ${FROM_REF}."
    exit 0
    ;;
  --skip)
    [[ -n "${PAUSED_AT:-}" ]] || die "nothing paused to skip"
    log "Skipping paused commit ${PAUSED_AT:0:12} $(git log -1 --format=%s "$PAUSED_AT")"
    if ! git cherry-pick --abort >/dev/null 2>&1; then
      git restore --staged --worktree -- "${PATHSPECS[@]}" >/dev/null 2>&1 || true
      git cherry-pick --quit >/dev/null 2>&1 || true
    fi
    LAST_APPLIED="$PAUSED_AT"
    clear_pause
    log "Skipped. Continuing with the next commit."
    ;;
  --dry-run|--continue|"")
    ;;
  *)
    usage
    die "unknown command: $CMD"
    ;;
esac

START=0
if [[ -n "${LAST_APPLIED:-}" ]]; then
  if idx="$(index_of_commit "$LAST_APPLIED")"; then
    START=$((idx + 1))
  else
    die "LAST_APPLIED ${LAST_APPLIED} is not in ${FROM_REF}..${TO_REF} mobile/i18n list. Use --reset-state if you want to start over."
  fi
fi

if [[ -n "${PAUSED_AT:-}" ]]; then
  if paused_idx="$(index_of_commit "$PAUSED_AT")"; then
    START="$paused_idx"
  fi
fi

if [[ "$CMD" == "--dry-run" ]]; then
  print_status
  echo
  log "Would apply:"
  i="$START"
  while (( i < TOTAL )); do
    sha="${COMMITS[$i]}"
    printf '  [%d/%d] %s %s\n' "$((i + 1))" "$TOTAL" "${sha:0:12}" "$(git log -1 --format=%s "$sha")"
    i=$((i + 1))
  done
  exit 0
fi

if [[ -z "${PAUSED_AT:-}" ]] && worktree_dirty; then
  die "working tree is dirty. Commit or stash first."
fi

finish_paused_if_possible
if [[ -n "${LAST_APPLIED:-}" ]]; then
  if idx="$(index_of_commit "$LAST_APPLIED")"; then
    START=$((idx + 1))
  fi
fi

if (( START >= TOTAL )); then
  save_state
  log "Already done: ${TOTAL}/${TOTAL} commits applied (${FROM_REF}..${TO_REF}, mobile/i18n only)."
  exit 0
fi

log "Cherry-picking ${FROM_REF}..${TO_REF} (mobile/i18n only), starting at $((START + 1))/${TOTAL}"

i="$START"
while (( i < TOTAL )); do
  sha="${COMMITS[$i]}"
  log "[$((i + 1))/${TOTAL}] ${sha:0:12} $(git log -1 --format=%s "$sha")"
  apply_one "$sha"
  i=$((i + 1))
done

PAUSED_AT=""
save_state
log "Done. Applied ${TOTAL} commits touching mobile/ or i18n/ from ${FROM_REF} to ${TO_REF}."
