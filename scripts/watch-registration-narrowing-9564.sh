#!/usr/bin/env bash
# watch-registration-narrowing-9564.sh — watch part (a) of the re-evaluation
# trigger on the deferred registration-only narrowing tracker (#9564) and post
# ONE notice when it first holds. NOTIFY-ONLY: the tracker is never closed,
# reopened, relabelled or edited by this script; its only GitHub writes are one
# `issue comment` per threshold, and its only reads are `issue view`.
#
# Why a dedicated workflow and not a follow-through sweeper probe: the sweeper
# comments on every non-pass verdict with no per-verdict dedup, so a notify-only
# probe would comment every sweep. See knowledge-base/project/plans/
# 2026-10-06-chore-registration-narrowing-reeval-watch-plan.md.
#
# Trigger (spec: feat-runner-sut-registration-narrowing, "Re-evaluation trigger"):
#   (a) >= THRESHOLD registration-only runner runs after ADR-242 decision 20, and
#   (b) the two PR-gated batteries exceed 20% of the median observed wait.
# Only (a) is mechanical, approximated by an UPPER BOUND: commits on the default
# branch since BASE_SHA that touch the two runner files with zero deleted lines
# (a registration-only edit is purely additive; any deletion rules a commit out).
# (b) has no recorded data source, so the notice hands it to a human.
#
# SELF-DISABLE: once the tracker is not OPEN every run is a cheap no-op.
#
# Modes:
#   (default)      measure; post the notice at the threshold (once)
#   --print-count  read-only: print `threshold=<N> base=<sha>` then the count
# Env: GH_TOKEN + GH_REPO (injected by the workflow); WATCH_BASE_SHA is a test
# seam (a fixture repo cannot contain the real base commit).
#
# Exit: 0 ok / below threshold / already notified / tracker not open;
#       1 comment post failed; 3 cannot establish (read failed, base missing).
set -uo pipefail

case "$-" in *x*) echo "refusing to run under xtrace" >&2; exit 2 ;; esac

ISSUE=9564
BASE_SHA="${WATCH_BASE_SHA:-2cfef66506c67207fc65b4250689842ff5ea20ba}"
THRESHOLD=3
PATHS=(scripts/test-all.sh scripts/lib/test-affected-paths.sh)
SENTINEL="<!-- registration-narrowing-watch:v1 threshold=${THRESHOLD} -->"

# count_registration_shaped: sets COUNT, EXCLUDED, LIST (one `sha date subject` per
# qualifying commit, subject truncated). Returns non-zero when git cannot answer.
COUNT=""; EXCLUDED=""; LIST=""
count_registration_shaped() {
  local out
  git cat-file -e "${BASE_SHA}^{commit}" 2>/dev/null || return 1
  git merge-base --is-ancestor "$BASE_SHA" HEAD 2>/dev/null || return 1
  out="$(git log --no-merges --numstat --format='C %h %cs %s' "${BASE_SHA}..HEAD" -- "${PATHS[@]}" 2>/dev/null)" || return 1
  # One record per commit: a `-` numstat field (binary) counts as a deletion, so a
  # commit this cannot read is excluded, never counted.
  COUNT="$(printf '%s\n' "$out" | awk '
    /^C / { if (have && del == 0) n++; have = 1; del = 0; next }
    /^[0-9-]+\t[0-9-]+\t/ { split($0, f, "\t"); if (f[2] == "-" || f[2] + 0 > 0) del++ }
    END { if (have && del == 0) n++; print n + 0 }')"
  EXCLUDED="$(printf '%s\n' "$out" | awk '
    /^C / { if (have && del > 0) x++; have = 1; del = 0; next }
    /^[0-9-]+\t[0-9-]+\t/ { split($0, f, "\t"); if (f[2] == "-" || f[2] + 0 > 0) del++ }
    END { if (have && del > 0) x++; print x + 0 }')"
  LIST="$(printf '%s\n' "$out" | awk '
    function flush() { if (have && del == 0) print line }
    /^C / { flush(); have = 1; del = 0; line = substr($0, 3); if (length(line) > 100) line = substr(line, 1, 100); next }
    /^[0-9-]+\t[0-9-]+\t/ { split($0, f, "\t"); if (f[2] == "-" || f[2] + 0 > 0) del++ }
    END { flush() }')"
  return 0
}

if [[ "${1:-}" == "--print-count" ]]; then
  echo "threshold=${THRESHOLD} base=${BASE_SHA:0:10}"
  if count_registration_shaped; then
    echo "count=${COUNT} excluded=${EXCLUDED}"
  else
    echo "count=unknown (base ${BASE_SHA:0:10} is not an ancestor of HEAD or git failed)"
  fi
  exit 0
fi

# (1) Issue state and comments first, so a retired watcher cannot go red on a
# history rewrite. A failed read posts nothing: it must never risk a duplicate.
issue_json="$(gh issue view "$ISSUE" --json state,comments 2>/dev/null)" || issue_json=""
state="$(printf '%s' "$issue_json" | jq -r '.state // empty' 2>/dev/null)" || state=""
if [[ -z "$issue_json" || -z "$state" ]]; then
  echo "::error::could not read #${ISSUE} (state/comments); posting nothing" >&2
  exit 3
fi
if [[ "$state" != "OPEN" ]]; then
  echo "issue ${ISSUE} is '${state}' (not OPEN) — nothing to watch"
  exit 0
fi

# (2) Measure. On an OPEN tracker a broken base is a broken watcher: be loud.
if ! count_registration_shaped; then
  echo "::error::cannot measure: base ${BASE_SHA} is missing or not an ancestor of HEAD" >&2
  exit 3
fi
echo "count=${COUNT} excluded=${EXCLUDED} threshold=${THRESHOLD}"
if [[ "$COUNT" -lt "$THRESHOLD" ]]; then
  echo "count=${COUNT} below threshold=${THRESHOLD}; no action"
  exit 0
fi

# (3) Once per threshold. Only comments authored by the Actions bot count: any
# account can paste the sentinel string, so a human-authored one never suppresses.
if printf '%s' "$issue_json" | jq -e --arg s "$SENTINEL" '
     [.comments[] | select(((.author.login // "") == "github-actions" or (.author.login // "") == "github-actions[bot]")
                           and ((.body // "") | contains($s)))] | length > 0' >/dev/null 2>&1; then
  echo "already notified — sentinel present on #${ISSUE}"
  exit 0
fi

# (4) Post exactly one notice. Part (b) is handed to a human with the arithmetic.
body="$(cat <<EOF
### Re-evaluation watch: part (a) reached (${COUNT} registration-shaped runner commits since ${BASE_SHA:0:10})

Commits on the default branch since the decision-20 merge that touch \`scripts/test-all.sh\` or \`scripts/lib/test-affected-paths.sh\` with no deleted lines (an upper bound on registration-only runs; ${EXCLUDED} other touching commits had deletions and were not counted):

$(printf '%s\n' "$LIST" | sed 's/^/- /')

**What this does not show:** part (b) (the two PR-gated batteries exceeding 20% of the median observed wait) and the "gate is again the slowest step of a suite-adding PR" arm have no recorded data, so a human has to measure them. Take the wall time of the next registration-only local runs (the \`[affected]\` summary line and per-suite timing on the contributor's machine) and compare it with the two batteries' 653 s. At manifest weights 653 s / 3516 s is 18.6%, so (b) holds only if the median observed wait is under about 54.4 min.

**Ask:** a contributor decides whether to re-open the design (spec FR1/FR2, brainstorm alternatives) or leave it deferred. This issue stays open; this notice is posted once. To stop the watch, delete \`.github/workflows/registration-narrowing-watch.yml\` and this script (see the RETIREMENT block in the workflow).

${SENTINEL}
EOF
)"
if ! printf '%s\n' "$body" | gh issue comment "$ISSUE" --body-file - >/dev/null 2>&1; then
  echo "::error::posting the notice on #${ISSUE} failed" >&2
  exit 1
fi
echo "posted the one-time notice on #${ISSUE} (count=${COUNT})"
exit 0
