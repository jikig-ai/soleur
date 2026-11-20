---
date: 2026-11-13
type: learning
source_pr: 12699
issues: [12666, 12583, 9340]
tags: [ci, enforcement, test-all, merge-queue, contention, review]
---

# Learning: post-merge merge-bypass audit + PR-battery gate follow-ups (PR #12699)

## Problem

Three tracked issues closed in one PR: #12666 (a required `test` check was red
when PR #12565 merged — no detective control existed), #12583 (the
skill-security-scan calibration suite flaked past its 180 s bound under
contention), and #9340 (PR-battery gate follow-ups: reaper/next-tier
admissions, gated-suite arms, workflow-prefix edges, merge-queue residuals).

## Solution

- New `scripts/merge-bypass-audit.sh` + `.github/workflows/merge-bypass-audit.yml`:
  a push-to-main / dispatch probe that re-derives whether each merge SHA had
  valid green authority at merge time — `merge_group` success scoped to the
  ci.yml workflow, or the source PR's head `test` check-run — and files a
  deduped compliance-critical issue on `bypass`, an unlabeled deduped
  unread-notice on `unread` (exit 2), never OK on an unread answer. A
  `compare/<sha>...main` ancestry gate rejects diverged SHAs before check-run
  reads; check-run matching is `{context, app.id}`, never name-only (a
  foreign-app check with the same context name is not the required check).
- `skill-security-scan` calibration timeouts 180 s → 600 s on both tests.
- ADR-262's admission rule widened from self-test machinery to a closed
  declarable edge set: 9 new `--pr-gated` suites, `RELEVANCE_ARRAYS` rows +
  floors, counted `skip_suite` else-arms on every gated registration,
  `LINT_ORPHAN_BATTERY_PATHS`'s workflow edge narrowed to an explicit
  consumed-workflow enumeration (`lint-orphan-consumed-workflows.txt`) with
  strict-equality parity in BOTH directions, a live floor (>=20), and M36–M40
  mutation rows on the completeness arm itself.

## Key Insight

- A completeness enumeration needs parity in both directions AND a mutation
  battery on the parity arm — first-round review caught live ⊆ .txt enforced
  but .txt ⊆ live unenforced, with zero mutation coverage on the arm.
- Historical arm-rate replay that skips merge commits silently undercounts:
  `git log --diff-merges=first-parent` is required or the rates are floors,
  not measurements — label them as such in the ADR.
- A red run is not a durable artifact: an `unread` verdict needs a deduped
  issue or the failure evaporates with the Actions retention window.
- Fixture discipline that made review cheap: every verdict-class arm asserts
  message text/state beyond rc, and the suite floor is flush against the
  executed count (164 = 164, zero slack).

## Session Errors

1. **Affected gate `runner-refused` (x2)** — sibling worktree full-gate runs
   held capacity; a refusal is not a pass and cannot be reported as one.
   **Prevention:** use the sanctioned `battery-refusal-wait.sh` recipe
   (30-min bounded wait → CI_IS_THE_GATE or relaunch) immediately on a
   sibling-run refusal instead of ad-hoc retries.
2. **FULL gate run killed mid-flight** — 4 suites SIGTERM'd (rc=143) when the
   sibling worktree's test-all restarted; ~40 suites UNACCOUNTED, run ended
   `failed-before-budget`. Filed as #12728 (cross-worktree kill boundary).
   **Prevention:** track #12728; until it lands, treat concurrent-worktree
   full runs as a kill hazard and prefer the bounded-wait path.
3. **CI `test` red on a pushed head** — traced to `encryption-posture`: two
   `in_transit` ledger exceptions expired 2026-11-12; pre-existing on main
   (main's 00:00 run failed identically) and owner/CLO-gated for renewal —
   not agent-fixable, not our diff.
   **Prevention:** on a red `test` aggregator, read the leg results before
   assuming the diff; `gh run view --job` on the aggregator names the leg.
4. **markdownlint MD032/MD004 on the new postmortem** — our defect; fixed
   via `markdownlint --fix` (neither rule is in the forbidden four).
   **Prevention:** run `bash scripts/markdown-lint.sh --repo-sweep` before
   pushing new kb prose, not after CI reports it.
5. **`fix-round-seats.sh` positional-args misuse** — interface is `--files`.
   **Prevention:** read the script's usage header before invoking a seat
   resolver.
6. **Infra-coverage suite 58/241 mass-fail under contention** — every
   sandboxed sub-run was runner-refused; empty output made all downstream
   assertions fail. Environmental, not a diff defect.
   **Prevention:** a mass-fail where every row reports empty output is one
   cause (the refusal), not N defects — check the runner's refusal marker
   first.
7. **`CLAUDE_PLUGIN_ROOT` unexported in a fresh shell** — `bash
   "$CLAUDE_PLUGIN_ROOT/scripts/..."` resolved to `/scripts/...`.
   **Prevention:** export the literal root path in the same command, or
   inline the absolute path.
8. **`emit-review-trailer.sh --fix-round` without `--since`** — rc=2 usage.
   **Prevention:** fix-round attestation always needs `--since <panel-sha>`.

## Prevention (durable)

- battery-refusal-wait recipe is the sanctioned answer to sibling-run
  refusals — rc 42 = CI is the gate (recorded verbatim in the PR body).
- The `merge-bypass-audit` probe is itself the durable artifact for #12666:
  future required-check bypasses file deduped issues automatically.
