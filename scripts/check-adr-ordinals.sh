#!/usr/bin/env bash
# Sentinel: ADR ordinal collision + required-content guard.
#
# Source-of-truth for ordinal-collision detection in
# knowledge-base/engineering/architecture/decisions/. The brainstorm at
# 2026-05-25-pr-b-anthropic-leader-loop-brainstorm.md flagged that ADR-039
# was stale-cited in issue #4379 (collision: departed-member-removal-ledger
# landed #4294 holds the ordinal). ADR INDEX.md does NOT exist in the
# decisions/ directory — scan filenames directly.
#
# Three layers (per AC18 in 2026-05-25-feat-anthropic-leader-loop-pr-b-plan.md):
#   1. Exact-ordinal collision: two files named ADR-NNN-*.md for the same NNN.
#   2. Required files exist with non-empty content: ADR-042 + ADR-041 (PR-B).
#   3. Required-heading completeness: each file has ## Status / ## Context /
#      ## Decision / ## Consequences (rules out stub-shaped ADRs).
#
# Fails closed: exit 1 on any check trip. Stdout names the failing condition
# so CI logs surface the specific drift.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
ADR_DIR=knowledge-base/engineering/architecture/decisions

# Known pre-existing collisions on main, accepted as tech debt (renumber
# deferred to a single cleanup PR; brainstorm flagged at
# 2026-05-25-pr-b-anthropic-leader-loop-brainstorm.md "Sharp Edges").
# Any NEW collision (e.g., a future ADR-042 duplicate) trips the gate.
# When the cleanup issue lands, shrink this allowlist accordingly.
#
# ADR-068 was resolved (#5274 Phase 3): the graceful-cron-drain ADR was renumbered
# to ADR-078-graceful-cron-drain-before-container-swap, leaving ADR-068 uniquely
# the multi-host-workspaces coordinator ADR. Dropped from the allowlist here.
#
# ADR-086 WAS a three-way concurrent-merge collision that landed on main directly
# (#6035 declarative-skill-context-injection + fail-closed-redaction-engine +
# freshness-last-reviewed-source-fix all authored ADR-086 and merged in the same
# window). Resolved in #6054: declarative-skill-context-injection kept ADR-086,
# fail-closed-redaction-engine → ADR-095, freshness-last-reviewed-source-fix → ADR-094.
# (redaction took 095 not 093 — a sibling ADR claimed 093 on main mid-pipeline.)
# Dropped from the allowlist here.
ALLOWED_COLLISIONS=(ADR-027 ADR-030 ADR-031 ADR-033 ADR-038)

# (1) New (non-allowlisted) ordinal collisions.
all_dups=$(ls "$ADR_DIR" | grep -oE '^ADR-[0-9]{3}' | sort | uniq -d || true)
if [ -n "$all_dups" ]; then
  new_dups=""
  while IFS= read -r dup; do
    is_allowed=0
    for allowed in "${ALLOWED_COLLISIONS[@]}"; do
      if [ "$dup" = "$allowed" ]; then
        is_allowed=1
        break
      fi
    done
    if [ "$is_allowed" -eq 0 ]; then
      new_dups="${new_dups}${dup} "
    fi
  done <<< "$all_dups"
  if [ -n "$new_dups" ]; then
    echo "NEW ADR ordinal collision (not in pre-existing allowlist): $new_dups" >&2
    exit 1
  fi
fi

# (2) + (3) Required files exist with non-empty content + required headings.
for required in ADR-042 ADR-041; do
  matches=$(ls "$ADR_DIR" | grep "^${required}-" || true)
  if [ -z "$matches" ]; then
    echo "Expected exactly 1 file matching ${required}-*, found 0" >&2
    exit 1
  fi
  count=$(echo "$matches" | grep -c . || true)
  if [ "$count" -ne 1 ]; then
    echo "Expected exactly 1 file matching ${required}-*, found ${count}" >&2
    exit 1
  fi
  file="$ADR_DIR/$matches"
  if [ ! -s "$file" ]; then
    echo "${required} file is empty: $file" >&2
    exit 1
  fi
  for required_heading in "## Status" "## Context" "## Decision" "## Consequences"; do
    if ! grep -q "^${required_heading}" "$file"; then
      echo "${required} file missing heading '${required_heading}': $file" >&2
      exit 1
    fi
  done
done

# (4) No frontmatter ordinal key (#6800). The FILENAME is the sole authoritative
# ordinal; a frontmatter `adr:` key can disagree with it (ADR-037's read `035`),
# making an `ADR-NNN` reference resolve to two documents. Removing the key makes
# that disagreement structurally impossible rather than merely currently-absent.
adr_key_files=$(grep -lE '^adr:' "$ADR_DIR"/ADR-*.md 2>/dev/null || true)
if [ -n "$adr_key_files" ]; then
  echo "ADR frontmatter ordinal key found — remove the 'adr:' key (the filename is authoritative, #6800):" >&2
  echo "$adr_key_files" >&2
  exit 1
fi

echo "ADR ordinal + content checks passed."
