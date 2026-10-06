#!/usr/bin/env bash
# watch-registration-narrowing-9564.sh — watch part (a) of the re-evaluation
# trigger on the deferred registration-only narrowing tracker (#9564) and post
# ONE notice when it first holds. NOTIFY-ONLY: the tracker is never closed,
# reopened, relabelled or edited by this script; its only GitHub writes are one
# `issue comment` per threshold, and its only reads are `issue view`.
#
# Why a dedicated workflow and not a follow-through sweeper probe: the sweeper
# comments on every non-pass verdict with no per-verdict dedup, so a notify-only
# probe would comment every sweep (followthrough-convention.md directs this shape
# to a dedicated scheduled workflow). Spec: feat-runner-sut-registration-narrowing,
# section "Re-evaluation trigger"; the retirement checklist is in the workflow header.
#
# Trigger (the spec's section above):
#   (a) >= THRESHOLD registration-only runner runs after ADR-242 decision 20, and
#   (b) the two PR-gated batteries exceed 20% of the median observed wait.
# Only (a) is mechanical, approximated by an UPPER BOUND: commits on the default
# branch since BASE_SHA that touch the two runner files, delete no line in either,
# and add at least one `run_suite` line to the runner (a registration-only edit is
# purely additive and registers a suite). (b) has no recorded data source, so the
# notice hands it to a human. The workflow job runs only on the default branch.
#
# SELF-DISABLE: once the tracker is not OPEN every run is a cheap no-op.
#
# Modes:
#   (default)      measure; post the notice at the threshold (once)
#   --print-count  read-only: print `threshold=<N> base=<sha>` then the count
# Env: GH_TOKEN + GH_REPO (injected by the workflow); WATCH_BASE_SHA is a test
# seam (a fixture repo cannot contain the real base commit).
#
# Exit: 0 ok / below threshold / already notified / tracker not open
#         (--print-count always exits 0, even when it prints count=unknown);
#       1 comment post failed; 2 usage; 3 cannot establish (read failed, base or a
#       runner path missing); 78 refusing to run under xtrace.
# A red run is the only failure signal (Actions tab + GitHub's default failure
# email): exit 3 is deliberately loud, a silently broken watcher is the worse state.
set -uo pipefail

case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script holds a live GitHub token and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

ISSUE=9564
BASE_SHA="${WATCH_BASE_SHA:-2cfef66506c67207fc65b4250689842ff5ea20ba}"
THRESHOLD=3
RUNNER=scripts/test-all.sh
RUNNER_INDEX=scripts/lib/test-affected-paths.sh
PATHS=("$RUNNER" "$RUNNER_INDEX")
SENTINEL="<!-- registration-narrowing-watch:v1 threshold=${THRESHOLD} -->"

case "${1:-}" in
  ""|--print-count) ;;
  *) echo "usage: ${0##*/} [--print-count]" >&2; exit 2 ;;
esac

# count_registration_shaped: sets COUNT, EXCLUDED, LIST (one `sha date subject` per
# counted commit, subject sanitised and cut to 100 chars). Returns non-zero when git
# cannot answer (base missing/off-branch, a runner path gone, a read failed).
COUNT=0; EXCLUDED=0; LIST=""
count_registration_shaped() {
  local out recs kind line sha patch added p
  git cat-file -e "${BASE_SHA}^{commit}" 2>/dev/null || return 1
  git merge-base --is-ancestor "$BASE_SHA" HEAD 2>/dev/null || return 1
  # A renamed/split runner would make the pathspec match nothing and the count read
  # 0 forever with a green run: refuse instead.
  for p in "${PATHS[@]}"; do git cat-file -e "HEAD:${p}" 2>/dev/null || return 1; done
  # --no-merges is defence in depth: a merge commit has no numstat and its combined
  # diff can never carry a `+run_suite` line, so it could not be counted either way.
  out="$(git log --no-merges --numstat --format='C %h %cs %s' "${BASE_SHA}..HEAD" -- "${PATHS[@]}" 2>/dev/null)" || return 1
  # ONE pass over the numstat: `Q<TAB><line>` for a touching commit that deletes
  # nothing, `X` for one that deletes a line (a `-` binary field counts as a deletion,
  # so a commit this cannot read is excluded, never counted).
  recs="$(printf '%s\n' "$out" | awk '
    function flush() { if (have) print (del == 0 ? "Q\t" line : "X") }
    /^C / { flush(); have = 1; del = 0; line = substr($0, 3); next }
    /^[0-9-]+\t[0-9-]+\t/ { split($0, f, "\t"); if (f[2] == "-" || f[2] + 0 > 0) del++ }
    END { flush() }')" || return 1
  while IFS=$'\t' read -r kind line; do
    case "$kind" in
      Q)
        sha="${line%% *}"
        patch="$(git show --format= -U0 "$sha" -- "$RUNNER" 2>/dev/null)" || return 1
        added="$(grep -cE '^\+[[:space:]]*run_suite[[:space:]]' <<<"$patch" || true)"
        if [[ "${added:-0}" -gt 0 ]]; then
          COUNT=$((COUNT + 1))
          line="$(printf '%s' "$line" | tr '`@<>' '    ')"
          LIST+="${line:0:100}"$'\n'
        else
          EXCLUDED=$((EXCLUDED + 1))
        fi ;;
      X) EXCLUDED=$((EXCLUDED + 1)) ;;
    esac
  done <<<"$recs"
  return 0
}

if [[ "${1:-}" == "--print-count" ]]; then
  echo "threshold=${THRESHOLD} base=${BASE_SHA:0:10}"
  if count_registration_shaped; then
    echo "count=${COUNT} excluded=${EXCLUDED}"
  else
    echo "count=unknown (base ${BASE_SHA:0:10} is not an ancestor of HEAD, a runner path is missing, or git failed)"
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
  echo "::notice::issue ${ISSUE} is '${state}' (not OPEN) — nothing to watch; delete the watcher per the RETIREMENT block in registration-narrowing-watch.yml"
  exit 0
fi

# (2) Measure. On an OPEN tracker a broken base is a broken watcher: be loud.
if ! count_registration_shaped; then
  echo "::error::cannot measure: base ${BASE_SHA} is missing or not an ancestor of HEAD, or a runner path no longer exists (update PATHS)" >&2
  exit 3
fi
echo "count=${COUNT} excluded=${EXCLUDED} threshold=${THRESHOLD}"
if [[ "$COUNT" -lt "$THRESHOLD" ]]; then
  echo "count=${COUNT} below threshold=${THRESHOLD}; no action"
  exit 0
fi

# (3) Once per threshold. Only comments authored by the Actions bot count: any
# account can paste the sentinel string, so a human-authored one never suppresses.
# A jq failure (e.g. `comments` is null) is a failed read, never "no sentinel".
notified="$(printf '%s' "$issue_json" | jq -r --arg s "$SENTINEL" '
     [.comments[] | select(((.author.login // "") == "github-actions" or (.author.login // "") == "github-actions[bot]")
                           and ((.body // "") | contains($s)))] | length' 2>/dev/null)" || notified=""
if [[ ! "$notified" =~ ^[0-9]+$ ]]; then
  echo "::error::could not evaluate the comments of #${ISSUE}; posting nothing" >&2
  exit 3
fi
if [[ "$notified" -gt 0 ]]; then
  echo "already notified — sentinel present on #${ISSUE}"
  exit 0
fi

# (4) Post exactly one notice. Part (b) is handed to a human with the arithmetic
# (figures are the manifest weights at plan time, 2026-10-06).
body="$(cat <<EOF
### Re-evaluation watch: part (a) reached (${COUNT} registration-shaped runner commits since ${BASE_SHA:0:10})

Commits on the default branch since the decision-20 merge that touch \`scripts/test-all.sh\` or \`scripts/lib/test-affected-paths.sh\`, delete no line in either, and add a \`run_suite\` line (an upper bound on registration-only runs; ${EXCLUDED} other touching commits had a deleted line or no new \`run_suite\` line and were not counted):

$(printf '%s' "$LIST" | sed 's/^/- /')

**What this does not show:** part (b) (the two PR-gated batteries exceeding 20% of the median observed wait) and the "gate is again the slowest step of a suite-adding PR" arm have no recorded data, so a human has to measure them. Take the wall time of the next registration-only local runs (the \`[affected]\` summary line and per-suite timing on the contributor's machine) and compare it with the two batteries' 653 s. At the manifest weights at plan time, 653 s / 3516 s is 18.6%, so (b) holds only if the median observed wait is under about 54.4 min.

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
