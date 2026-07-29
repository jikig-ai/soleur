#!/usr/bin/env bash
# Executable AC walk for #6750 / PR #7032. Read-only; run from the repo root.
#
# Why this exists: the plan's AC preamble documented three measured grep-scoping
# traps in prose, and the final walk re-sprung two of them anyway -- in the same
# session that wrote them. Prose traps do not prevent recurrence; executable ones
# do. See knowledge-base/project/learnings/
# 2026-07-29-a-per-producer-fix-left-seven-siblings-live-and-four-misread-signals.md
#
# Exit 0 = every mechanically-checkable AC passes.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 2

D=apps/web-platform/server/inngest/functions
PARITY=apps/web-platform/test/server/inngest/cron-safe-commit-parity.test.ts
C4=knowledge-base/engineering/architecture/diagrams/model.c4
ADR=knowledge-base/engineering/architecture/decisions/ADR-126-cron-liveness-must-assert-the-consumed-artifact.md

fails=0
r() { # name, want, got, label
  if [ "$2" = "$3" ]; then s=PASS; else s=FAIL; fails=$((fails + 1)); fi
  printf '%-8s %-4s got=%-4s want=%-4s %s\n' "$1" "$s" "$3" "$2" "$4"
}

# TRAP 1 -- roster scoping. $MP is the parity roster (8), NOT a directory glob:
# `let heartbeatOk` matches 9 files directory-wide (the 8 plus EXEMPT
# cron-roadmap-review) and the safe-commit-pr shape matches 12.
MP=$(sed -n '/^const MIGRATED_PROMPT = \[/,/^\];/p' "$PARITY" \
     | grep -oE '"cron-[a-z-]+\.ts"' | tr -d '"' | sed "s|^|$D/|")
[ "$(echo "$MP" | wc -l)" -eq 8 ] || { echo "FATAL: roster drifted (want 8)"; exit 1; }

# TRAP 1b -- the COHORT is 7, not 8. The 8th ($REFERENCE) is cron-community-monitor,
# the pre-existing #6714 implementation this work widens. ACs about the cohort's
# probe split must exclude it or they read 2-where-1.
REFERENCE=$D/cron-community-monitor.ts
COHORT=$(echo "$MP" | grep -v "^$REFERENCE$")
[ "$(echo "$COHORT" | wc -l)" -eq 7 ] || { echo "FATAL: cohort drifted (want 7)"; exit 1; }

# TRAP 2 -- count FILES (grep -l), never occurrences: `git grep -c` is per-file and
# cron-community-monitor.ts carries `retryEligible` twice (field + comment).
r AC1  8 "$(echo "$MP" | xargs grep -l 'retryEligible: false' | wc -l)" "retryEligible: false"
r AC2a 8 "$(echo "$MP" | xargs grep -lE 'const commitResult = await step\.run\("safe-commit-pr"' | wc -l)" "bound commitResult"
# TRAP 3 -- the unbound form must be LINE-ANCHORED; unanchored also matches the bound line.
r AC2b 0 "$(echo "$MP" | xargs grep -lE '^\s+await step\.run\("safe-commit-pr"' | wc -l)" "unbound (anchored)"
r AC3a 8 "$(echo "$MP" | xargs grep -l 'let livenessOk = false;' | wc -l)" "let livenessOk"
r AC3b 8 "$(echo "$MP" | xargs grep -l 'let heartbeatOk = false;' | wc -l)" "heartbeatOk kept (addition, never rename)"
r AC4  8 "$(echo "$MP" | xargs grep -l 'if (!livenessOk) heartbeatOk = false;' | wc -l)" "liveness gate present"

# AC4 ordering: the gate must sit AFTER the persistence block, per file.
bad=0
for f in $MP; do
  sc=$(grep -nE 'step\.run\("safe-commit-pr"' "$f" | head -1 | cut -d: -f1)
  lv=$(grep -n 'if (!livenessOk) heartbeatOk = false;' "$f" | head -1 | cut -d: -f1)
  [ -n "$sc" ] && [ -n "$lv" ] && [ "$lv" -gt "$sc" ] || { echo "  ORDER FAIL $(basename "$f")"; bad=1; }
done
r AC4b 0 "$bad" "gate after safe-commit-pr in all 8"

# TRAP 4 -- scope the prompt extraction to the const body. The closing backtick MUST
# be escaped inside a double-quoted sed program, or it opens a command substitution,
# the range runs to EOF, and it swallows the `<today>` CODE COMMENT 245 lines below.
GA=$D/cron-growth-audit.ts
END=$(awk 'NR>1 && /^`;/{print NR; exit}' "$GA")
PROMPT=$(awk -v e="$END" 'NR>=1 && NR<=e' "$GA" | sed -n '/^const GROWTH_AUDIT_PROMPT = /,$p')
r AC6a1 0 "$(printf '%s' "$PROMPT" | grep -c '<today>')" "<today> gone from prompt body"
r AC6a2 4 "$(printf '%s' "$PROMPT" | grep -o '{{RUN_DATE}}-' | wc -l)" "{{RUN_DATE}}- pins"

r AC6   8 "$(echo "$MP" | xargs grep -l 'dedup-digest-committed-check' | wc -l)" "dedup committed-check"
# AC6b anti-vacuity: an existence probe is sound ONLY for the date-named artifact.
r AC6b1 1 "$(echo "$COHORT" | xargs grep -l 'digestCommittedOnDefaultBranch(' | wc -l)" "existence probe (cohort of 7)"
r AC6b2 6 "$(echo "$COHORT" | xargs grep -l 'artifactCommittedSince(' | wc -l)" "freshness probe (cohort of 7)"

r AC7   8 "$(echo "$MP" | xargs grep -l 'emitCronDigestLiveness' | wc -l)" "liveness marker"
r AC8   0 "$(git grep -l 'emitCronPersistResult' -- "$D/" | grep -vc '_cron-safe-commit.ts')" "no handler emitCronPersistResult"
r AC9a  2 "$(grep -cE '^\s*api -> kb' "$C4")" "api -> kb edges"
r AC9b  0 "$(grep -cE '^\s*inngest -> kb' "$C4")" "no inngest -> kb edge"
r AC11  1 "$(grep -c '## Amendment 2026-07-28 (#6750)' "$ADR")" "ADR amendment heading"
for d in 15 22 46 75; do
  got=$(grep -cE "\b${d}\s*d\b|\b${d}[ -]day" "$ADR")
  [ "$got" -ge 1 ] || { echo "  MISSING residual day-number: ${d}"; fails=$((fails + 1)); }
done

# AC12 -- ordering discipline. Note $sha^, not $sha: the both-in-one-commit fixture
# is what catches that bug.
bad=0
for sha in $(git rev-list origin/main..HEAD); do
  git show "$sha" -- "$D/" | grep -q '^+.*let livenessOk = false;' || continue
  for f in $(git show --name-only --format= "$sha" -- "$D/"); do
    git show "$sha" -- "$f" | grep -q '^+.*let livenessOk = false;' || continue
    git show "$sha^:$f" 2>/dev/null | grep -q 'retryEligible: false' \
      || { echo "  ORDER VIOLATION $sha $f"; bad=1; }
  done
done
r AC12  0 "$bad" "no livenessOk before retryEligible"
r AC12b 1 "$(grep -c 'retryEligible: false,' "$PARITY")" "call-site regex (not bare token)"
r AC17  0 "$(git diff --numstat origin/main -- "$PARITY" | awk '{print $2}')" "parity test deletions"

echo
if [ "$fails" -eq 0 ]; then echo "AC walk: all checks PASS"; else echo "AC walk: $fails FAILED"; fi
exit "$fails"
