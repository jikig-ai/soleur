---
title: "Tasks — feat(secret-scan): widen database-url placeholder allowlist regex for *** redaction"
date: 2026-05-16
lane: cross-domain
issue: 3877
plan: knowledge-base/project/plans/2026-05-16-feat-secret-scan-database-url-placeholder-regex-widening-plan.md
---

# Tasks — secret-scan placeholder-regex widening (#3877)

Derived from the finalized plan. Implementation is intentionally compact (one-line regex edit + fixture + runbook); the task tree below captures every AC.

## 1. Setup

- 1.1. Confirm gitleaks v8.24.2 binary available (`gitleaks version`). Expected: matches `.gitleaks.toml` schema lock.
- 1.2. Capture pre-fix baseline by running gitleaks against `/tmp/fix-pos.txt` (asterisk-shape) — expected exit=1 with `database-url-with-password` finding. Confirms the gap is real before editing.

## 2. Core Implementation

- 2.1. Edit `.gitleaks.toml` line 260: extend the password alternation in the `[[rules.allowlists]] regexes` for `database-url-with-password` from
  `(?:PASSWORD|password|secret|<[^>]+>)`
  to
  `(?:PASSWORD|password|secret|<[^>]+>|\*+)`
  (AC1).
- 2.2. Update the inline comment on `.gitleaks.toml` line 259 to mention #3877 alongside the existing #3874 reference.
- 2.3. Run local positive repro (AC2): `gitleaks detect --no-banner --no-git --redact -v -c .gitleaks.toml --source /tmp/fix-pos.txt` — expected exit=0, no finding.
- 2.4. Run local negative repro (AC3): `gitleaks detect --no-banner --no-git --redact -v -c .gitleaks.toml --source /tmp/fix-neg.txt` — expected exit=1, ONE `database-url-with-password` finding.

## 3. Synthesized fixture

- 3.1. Choose fixture path under `apps/web-platform/test/__synthesized__/` (already covered by per-rule path-allowlist for `database-url-with-password`). Confirm via `grep -A1 'database-url-with-password' .gitleaks.toml | grep '__synthesized__'`.
- 3.2. Create or extend the fixture file with BOTH a positive line (`postgres://user:***@host`) AND a negative-control line (`postgres://USER:PASSWORD@host`) (AC4).
- 3.3. Stage the fixture, then run `gitleaks git --no-banner --exit-code 1 --redact -v` over the worktree — confirm `database-url-with-password` does NOT fire.

## 4. Operator runbook + frontmatter

- 4.1. Edit `knowledge-base/engineering/operations/secret-scanning.md` lines 82-91 carve-out paragraph: add one bulleted sub-line noting the `\*+` extension and the `***` redaction convention recognition (AC7).
- 4.2. Append `#3877` to the runbook's top-matter `related:` list (lines 5-8).
- 4.3. Confirm `last_updated:` field is current (`2026-05-16`); re-touch if stale.

## 5. Commit-trailer + label

- 5.1. Stage all changes (`.gitleaks.toml`, fixture, runbook, plan, tasks). Commit with body trailer `Allowlist-Widened-By: Jean Deruelle` (case-sensitive, exact key) (AC5).
- 5.2. After PR opens, apply label `secret-scan-allowlist-ack` via `gh pr edit <N> --add-label secret-scan-allowlist-ack` (AC6).

## 6. Sibling deferral issue (AC9)

- 6.1. Before marking the PR ready-for-review, run:
  ```bash
  gh issue create \
    --title "secret-scan: allowlist-diff parser should surface per-rule paths AND regexes" \
    --label "domain/engineering,priority/p3-low,deferred-scope-out" \
    --body "Follow-up from #3877 / learning 2026-05-16-allowlist-diff-shadowed-widening-and-gitleaks-verbose-flag.md §'Fix surface (deferred)'.

  The current allowlist-diff gate (apps/web-platform/scripts/allowlist-diff.sh + apps/web-platform/scripts/parse-gitleaks-allowlists.mjs) has two shadowing blind spots:
  1. Parser emits a deduped UNION of paths across all rules — adding a path to rule A that already exists on rule B silently bypasses the gate.
  2. Parser ONLY scans paths = [...] — regexes = [...] entries (per-rule content-regex allowlists) are invisible to the diff.

  Fix surface: emit per-rule (rule_id, path) tuples AND include regexes = [...] entries in the diff. The gate's sticky comment can then surface which rule gained relaxation.

  Refs #3877."
  ```
- 6.2. Capture the returned issue number; add `Refs #<N> (sibling parser refactor)` to the PR body for #3877.

## 7. Final pre-merge checks

- 7.1. AC8 (path-allowlist retained): `grep -A1 'database-url-with-password' .gitleaks.toml | grep learnings` returns a match for `knowledge-base/project/learnings/.*\.md$`.
- 7.2. Verify CI `secret-scan-detect` job passes on the PR.
- 7.3. Verify CI `allowlist-diff` job reports "no allowlist path changes (regex re-orderings only)" — this is the known shadowing blind spot; the trailer + label are the operator-side compensating control.
- 7.4. Verify CI `smoke-tests` matrix passes all 9 cases unchanged.

## Done definition

All 9 ACs in the plan check off; CI is green; trailer + label both present on the PR; sibling deferral issue filed and referenced.
