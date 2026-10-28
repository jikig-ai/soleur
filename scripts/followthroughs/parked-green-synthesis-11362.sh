#!/usr/bin/env bash
# parked-green-synthesis-11362.sh — NOTIFY-ONLY publish-window probe for #11362.
#
# The arc-synthesis distribution file
#   knowledge-base/marketing/distribution-content/2026-11-19-first-we-made-green-mean-something.md
# ships with `status: parked` — a deliberate hold: the prescribed social window opens
# 2026-11-19, and the daily publisher (scripts/content-publisher.sh) only fires files
# that read `status: scheduled`. If nobody flips the one-line lever, the post's social
# wave silently never goes out and nothing anywhere alerts. This probe is the wake:
# inside the window it reports ACTION REQUIRED until the file reads scheduled or
# published, and the operator ends the tracker by closing it AND removing the
# `follow-through` label.
#
# Exit semantics (sweep-followthroughs.sh contract — NOTIFY-ONLY vocabulary):
#   0  NEVER TAKEN — closing the tracker is an operator judgement, not this probe's.
#   1  NEVER TAKEN — a not-yet condition must never read as FAIL/regression.
#   2  NOT YET — today is before 2026-11-19, or the lever is already pulled
#      (status: scheduled/published).
#   3  CANNOT ESTABLISH — the distribution file is missing, or its frontmatter has
#      no readable `status:` field.
#   5  ACTION REQUIRED — inside the window while the file still reads
#      `status: parked`/`draft` (a draft in-window is already a violation — the
#      promotion machinery rewrites its slot), or any other non-done status.
#
# CREDENTIAL POSTURE: none — `secrets=` is empty on the tracker directive. The probe
# reads one tracked repo file and calls `date`; it binds no credential, touches no
# network, and runs correctly under the sweeper's `env -i` (PATH only).
# SOLEUR_PROBE_TODAY is a test seam ONLY: the sweeper forwards nothing but PATH plus
# declared secrets, so in production the var is always unset and the real clock wins.
#
# RETIREMENT: when the #11362 tracker closes, delete this file and disposition every
# hit of `git grep parked-green-synthesis-11362` — today that lists: the
# `<!-- soleur:followthrough script=... -->` directive comment on issue #11362, the
# plan (knowledge-base/project/plans/2026-10-28-content-testsuite-arc-synthesis-plan.md),
# the tasks file (knowledge-base/project/specs/feat-one-shot-11362-arc-synthesis/tasks.md),
# and this file itself. The distribution file stays — it is the published wave's record.
set -euo pipefail

# Standard #7797 refusal: this probe declares no secrets, so nothing should ever
# bind a token here — but if a caller runs it traced with a credential in scope,
# 78 (EX_CONFIG) lands in the TRANSIENT bucket, the fail-safe direction.
case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}${GITHUB_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

# never-0/never-1 backstop: under `set -e` an unguarded failure aborts with the
# failed command's own status — usually 1, the sweeper's FAIL verb. Every command
# below is guarded, and this trap converts any unplanned 0/1 landing into CANNOT
# ESTABLISH so the invariant holds structurally rather than by review.
trap 'rc=$?; case "$rc" in 0|1) printf "CANNOT ESTABLISH: unplanned exit path (rc=%s)\n" "$rc" >&2; exit 3;; esac' EXIT

WINDOW_DATE="2026-11-19"
DIST_REL="knowledge-base/marketing/distribution-content/2026-11-19-first-we-made-green-mean-something.md"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
DIST_FILE="$REPO_ROOT/$DIST_REL"

cannot_establish() { printf 'CANNOT ESTABLISH: %s\n' "$1" >&2; exit 3; }

command -v date >/dev/null 2>&1 || cannot_establish "'date' is not on this probe's PATH"

TODAY="${SOLEUR_PROBE_TODAY:-}"
if [[ -z "$TODAY" ]]; then
  TODAY="$(date -u +%F)" || cannot_establish "'date -u +%F' failed"
fi
[[ "$TODAY" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] \
  || cannot_establish "could not establish today's date (got '${TODAY}')"

[[ -f "$DIST_FILE" ]] || cannot_establish "distribution file is missing: ${DIST_REL}"
[[ "$(head -1 "$DIST_FILE" 2>/dev/null || true)" == "---" ]] \
  || cannot_establish "${DIST_REL} has no frontmatter block (first line is not '---')"
fence_count="$(awk '/^---$/{c++} END{print c+0}' "$DIST_FILE")" \
  || cannot_establish "could not read ${DIST_REL}"
[[ "$fence_count" =~ ^[0-9]+$ ]] \
  || cannot_establish "frontmatter fence count is not numeric in ${DIST_REL}"
[[ "$fence_count" -ge 2 ]] \
  || cannot_establish "${DIST_REL} has an unterminated frontmatter block"

# Same frontmatter/`status:` extraction as scripts/lib/validate-tweet-draft.sh.
frontmatter="$(awk 'NR==1 && $0!="---"{exit} /^---$/{c++; if(c==2) exit; next} c==1' "$DIST_FILE")" \
  || cannot_establish "could not parse frontmatter in ${DIST_REL}"
status="$(printf '%s\n' "$frontmatter" | sed -n 's/^status:[[:space:]]*//p' | head -1 \
  | sed 's/^"//; s/"$//; s/^[[:space:]]*//; s/[[:space:]]*$//')"
[[ -n "$status" ]] \
  || cannot_establish "${DIST_REL} has no 'status:' field in its frontmatter"

case "$status" in
  scheduled|published)
    printf 'NOT YET: nothing to wake for — %s already reads status: %s (the lever was pulled).\n' "$DIST_REL" "$status"
    exit 2
    ;;
esac

if [[ "$TODAY" < "$WINDOW_DATE" ]]; then
  printf 'NOT YET: publish window opens %s (today %s); %s reads status: %s.\n' "$WINDOW_DATE" "$TODAY" "$DIST_REL" "$status"
  exit 2
fi

case "$status" in
  parked|draft)
    printf 'ACTION REQUIRED: window open since %s and %s still reads status: %s — flip `status: parked → scheduled` in a one-line commit so the daily publisher fires it.\n' "$WINDOW_DATE" "$DIST_REL" "$status"
    exit 5
    ;;
  *)
    printf 'ACTION REQUIRED: window open since %s and %s reads an unexpected status: %s — a human must reconcile it.\n' "$WINDOW_DATE" "$DIST_REL" "$status"
    exit 5
    ;;
esac
