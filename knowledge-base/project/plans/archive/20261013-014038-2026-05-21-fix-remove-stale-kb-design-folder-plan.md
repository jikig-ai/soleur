---
title: "fix: remove regressed stale knowledge-base/design/ directory and harden guard"
type: bug-fix
classification: docs-and-test-hardening
lane: single-domain
created: 2026-05-21
branch: feat-one-shot-remove-stale-kb-design-folder
---

# fix: Remove regressed stale `knowledge-base/design/` directory and harden guard

## Enhancement Summary

**Deepened on:** 2026-05-21
**Sections enhanced:** Files to Edit, Implementation Phases, Sharp Edges, Test Strategy, Observability gate clearance

### Key Improvements

1. Confirmed CI discovery shape: `scripts/test-all.sh:165` globs `plugins/soleur/test/*.test.sh` so the hardened guard runs automatically on PR merge to main — no workflow YAML changes needed.
2. Validated `assert_eq ""` semantics against `plugins/soleur/test/test-helpers.sh:16` — `[[ "$expected" == "$actual" ]]` returns true for empty-string comparison; the empty-string assertion form is safe and matches existing repo convention. Sharp Edge SE-2 cleared (no fallback to `[[ -z ]]` needed).
3. Verified `git -C "$REPO_ROOT" ls-tree -r HEAD -- knowledge-base/design/` returns the regressed entry from inside a `.worktrees/` worktree — the canonical worktree-aware form works without `git rev-parse --show-toplevel`.
4. Made the Phase 4.7 (Observability gate) skip-condition explicit by citing plan Phase 2.9 trigger set verbatim — the change touches `plugins/soleur/test/*.sh` (NOT under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`) and is delete-only on the artifact side, both skip-conditions per Phase 2.9.
5. Pre-validated AC4 and AC7 against the current worktree state: canonical file is 41,394 bytes (PASS); `grep -c "knowledge-base/design/" knowledge-base/marketing/brand-guide.md` returns `0` (PASS). AC1, AC2, AC3 expected to flip from FAIL to PASS after the delete commit lands.

### New Considerations Discovered

- Initial task description was off on `brand-guide.md` line numbers (claimed line 243; actual reference is at line 376 and already canonical). The Research Reconciliation table captures this verification result so reviewers do not assume forgotten work.
- The learning file `knowledge-base/project/learnings/bug-fixes/2026-04-19-ux-design-lead-headless-stub-fabrication.md` contains 5 substring matches for `knowledge-base/design/` — these are intentional documentation of the deprecated path and must NOT be edited (per "Out of scope: historic ... learning files" in the original task brief).

## Overview

A 0-byte empty placeholder at `knowledge-base/design/upgrade-modal-at-capacity.pen` (blob `e69de29...`) is tracked on `origin/main`. The top-level `knowledge-base/design/` directory was supposed to have been removed in PR #566; it regressed via `WIP: feat-plan-concurrency-enforcement (#2617)`. The canonical layout is `knowledge-base/product/design/{domain}/`, and the canonical version of the file already exists at `knowledge-base/product/design/billing/upgrade-modal-at-capacity.pen` (41,394 bytes).

The user-visible symptom: the web platform KB viewer (`apps/web-platform/server/kb-route-helpers.ts:120` and `app/api/kb/tree/route.ts`) reads from `${workspace_path}/knowledge-base/`. Every operator whose workspace clones main sees a stray root-level `design/` folder containing one empty `.pen` file. This is cosmetic-but-confusing brand noise — the operator sees a duplicate of the canonical billing artifact at a path no documentation references.

This plan:

1. Deletes the empty regressed file (and lets the empty directory go with it — git does not track empty directories).
2. Hardens the existing path-regression guard at `plugins/soleur/test/ux-design-lead-output-path-guard.test.sh` so it asserts the directory does not regress in `HEAD` itself — not only inside the ux-design-lead agent spec.

Two original task items resolve to no-ops after verification:

- The brand-guide line cited in the task description (`knowledge-base/marketing/brand-guide.md:243`) does NOT contain a stale reference; the actual `brand-x-banner.pen` reference is at line 376 and already points to the canonical `knowledge-base/product/design/brand/brand-x-banner.pen`. Treated as a verification step — no edit required.
- All other `knowledge-base/design/` substring matches in active (non-archive) files are intentional documentation of the deprecated path: `plugins/soleur/test/ux-design-lead-output-path-guard.test.sh` (the guard itself) and `knowledge-base/project/learnings/bug-fixes/2026-04-19-ux-design-lead-headless-stub-fabrication.md` (a learning that explains the bug class). Both are correct in their current form.

## Research Reconciliation — Spec vs. Codebase

| Original claim (task description) | Reality on disk (HEAD) | Plan response |
| --- | --- | --- |
| `knowledge-base/marketing/brand-guide.md:243` contains a stale `knowledge-base/design/brand/brand-x-banner.pen` reference that needs rewriting to `knowledge-base/product/design/brand/brand-x-banner.pen`. | Line 243 contains the `--border-emphasized (UI)` contrast-ratio row. The actual `brand-x-banner.pen` reference is at line 376 and already reads `knowledge-base/product/design/brand/brand-x-banner.pen`. No stale reference exists in `brand-guide.md`. | Drop the edit. Add a verification AC that greps the whole file for the deprecated substring and expects zero matches. Record this reconciliation in the PR body so the operator does not later assume the brand-guide edit was forgotten. |
| `knowledge-base/design/upgrade-modal-at-capacity.pen` is the only path file under the regressed directory. | Confirmed: `git ls-tree -r HEAD knowledge-base/design/` returns exactly one entry: `e69de29... knowledge-base/design/upgrade-modal-at-capacity.pen` (0 bytes). | Delete the single file; directory disappears with it. |
| Canonical version exists at `knowledge-base/product/design/billing/upgrade-modal-at-capacity.pen`. | Confirmed: 41,394-byte blob `24c2b9d033447209982272d52bf730284c0e7d0e`. | Reference it in the AC and PR body so reviewers do not mistake the delete for content loss. |

## User-Brand Impact

**If this lands broken, the user experiences:** continues to see a stray root-level `design/` folder containing one empty `upgrade-modal-at-capacity.pen` in the KB viewer (`apps/web-platform/server/kb-route-helpers.ts:120`). Cosmetic confusion only — no functional regression, no data exposure.

**If this leaks, the user's data is exposed via:** N/A. The file is a 0-byte placeholder with no content. No PII, no secrets, no operator data.

**Brand-survival threshold:** none

The diff touches only `knowledge-base/design/upgrade-modal-at-capacity.pen` (delete) and `plugins/soleur/test/ux-design-lead-output-path-guard.test.sh` (test hardening). Neither path matches the sensitive-path regex in `plugins/soleur/skills/preflight/SKILL.md` Check 6 Step 6.1 (auth, billing, schema, migrations, agent prompts). The "threshold: none, reason: <one-sentence>" scope-out bullet is therefore not required for preflight to pass.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `knowledge-base/design/upgrade-modal-at-capacity.pen` is removed from the worktree (`test ! -f knowledge-base/design/upgrade-modal-at-capacity.pen` returns 0).
- [ ] AC2: `git ls-tree -r HEAD knowledge-base/design/` returns empty output (after the delete commit lands in the PR branch HEAD).
- [ ] AC3: `find knowledge-base -maxdepth 2 -type d -name design` returns exactly one line: `knowledge-base/product/design` (the canonical root).
- [ ] AC4: The canonical file remains intact: `test -s knowledge-base/product/design/billing/upgrade-modal-at-capacity.pen` returns 0 (file exists AND has size > 0).
- [ ] AC5: `plugins/soleur/test/ux-design-lead-output-path-guard.test.sh` retains the original agent-spec assertion (grep for deprecated path in `agents/product/design/ux-design-lead.md`) AND adds two new assertions:
  - `git ls-tree -r HEAD -- knowledge-base/design/` returns empty.
  - `find knowledge-base -maxdepth 2 -type d -name design -print` returns only the canonical `knowledge-base/product/design` path (no `knowledge-base/design`).
- [ ] AC6: `bash plugins/soleur/test/ux-design-lead-output-path-guard.test.sh` exits 0 against the post-delete worktree.
- [ ] AC7: Verification grep on `knowledge-base/marketing/brand-guide.md` for the literal substring `knowledge-base/design/` returns zero matches (`grep -c "knowledge-base/design/" knowledge-base/marketing/brand-guide.md` returns `0`).
- [ ] AC8: PR body uses `Ref` (not `Closes`) for the originating issue if one exists, because the user-visible artifact (the stray folder in operator KB viewers) is only fully gone after main is merged and operator workspaces re-pull — this is a cosmetic state-truing, not a code change with a test-validated post-condition. (No-op if no originating issue is filed.)

### Post-merge (operator)

- [ ] AC9: No operator action required. Operators whose workspaces auto-pull from main will see the stray `design/` folder disappear on next `git pull`. Stale clones will continue to show the folder until the operator updates — this is `git`'s normal behavior, not a workflow gap.

## Files to Edit

- `plugins/soleur/test/ux-design-lead-output-path-guard.test.sh` — extend with two new assertions per AC5. Preserve the existing agent-spec block verbatim. Place the new assertions after `assert_file_exists "$AGENT" ...` and before the existing `grep -E "knowledge-base/design/" "$AGENT"` block so the directory check fires first (cheaper, broader signal).

## Files to Delete

- `knowledge-base/design/upgrade-modal-at-capacity.pen` (0-byte placeholder; canonical at `knowledge-base/product/design/billing/upgrade-modal-at-capacity.pen`).

## Files to Create

None.

## Open Code-Review Overlap

None. Queried `gh issue list --label code-review --state open --limit 200` for any issue body containing `knowledge-base/design/` or `ux-design-lead-output-path-guard` — none returned.

## Implementation Phases

### Phase 1 — Delete the regressed file

1. `git rm knowledge-base/design/upgrade-modal-at-capacity.pen` from the worktree.
2. Verify: `git status --short` shows exactly one staged deletion at the regressed path.
3. Verify directory disappears: `test ! -d knowledge-base/design` returns 0.

### Phase 2 — Harden the guard test (RED → GREEN)

1. Add two new assertion blocks to `plugins/soleur/test/ux-design-lead-output-path-guard.test.sh` between the `assert_file_exists` line and the existing agent-spec grep block.
2. Block A — HEAD assertion:
   ```bash
   # The deprecated `knowledge-base/design/` directory must not appear in HEAD.
   # Guards against future regressions of the kind introduced by #2617.
   set +e
   head_tree=$(git -C "$REPO_ROOT" ls-tree -r HEAD -- knowledge-base/design/ 2>/dev/null)
   rc=$?
   set -e
   assert_eq "0" "$rc" "git ls-tree HEAD succeeded"
   assert_eq "" "$head_tree" "no knowledge-base/design/ entries in HEAD"
   ```
3. Block B — on-disk assertion:
   ```bash
   # On-disk: only canonical knowledge-base/product/design must exist.
   set +e
   disk_dirs=$(find "$REPO_ROOT/knowledge-base" -maxdepth 2 -type d -name design 2>/dev/null | sort)
   set -e
   expected="$REPO_ROOT/knowledge-base/product/design"
   assert_eq "$expected" "$disk_dirs" "only knowledge-base/product/design exists on disk"
   ```
4. RED check (before Phase 1 lands): with the regressed file still present, the new assertions should fail. (Skip in practice if the delete and the test edit land in the same commit; document the expected failure in the PR body instead.)
5. GREEN check (after Phase 1 lands): `bash plugins/soleur/test/ux-design-lead-output-path-guard.test.sh` exits 0.

### Phase 3 — Verification sweep

1. Run AC1-AC4 verifications. Capture command output in the PR body.
2. Confirm `knowledge-base/marketing/brand-guide.md` has zero `knowledge-base/design/` substring matches (AC7).
3. Confirm the only remaining substring matches in non-archive paths are the two intentional ones:
   - `plugins/soleur/test/ux-design-lead-output-path-guard.test.sh` (the guard itself — references the deprecated path as the thing it greps for).
   - `knowledge-base/project/learnings/bug-fixes/2026-04-19-ux-design-lead-headless-stub-fabrication.md` (a learning that documents the deprecated path).
4. Commit the test edit + the deletion in a single commit (`fix: remove regressed knowledge-base/design/ folder and harden guard`) so the test passes at every commit boundary.

## Observability

**Gate verdict: schema populated to pass Phase 4.7 explicitly, despite Phase 2.9 trigger set not firing.**

Phase 2.9 trigger set is `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, `plugins/*/scripts/`, or new infrastructure surface (Phase 2.8). This plan's `## Files to Edit` contains exactly one entry — `plugins/soleur/test/ux-design-lead-output-path-guard.test.sh` — under `plugins/*/test/`, which is NOT in the trigger set. The `## Files to Delete` entry is a 0-byte placeholder removal. Neither path triggers Phase 2.9.

However, deepen-plan Phase 4.7 Step 1 has a different skip condition (docs-only paths). Since the test file path does not match a docs-only pattern, Phase 4.7 Step 2 applies. The 5-field schema is populated below with concrete values — every field carries a non-placeholder value naming the actual signal/destination for the protected surface (the regression-guard test itself), so the regex rejects in Phase 4.7 Step 3 do not fire.

```yaml
liveness_signal:
  what: GitHub Actions `test-scripts` job exit code (job passes iff `plugins/soleur/test/ux-design-lead-output-path-guard.test.sh` exits 0)
  cadence: every push to PR + every push to main (per `.github/workflows/ci.yml` triggers)
  alert_target: PR check status; merge is blocked on red `test-scripts`
  configured_in: .github/workflows/ci.yml `test-scripts` job + scripts/test-all.sh:165 glob loop
error_reporting:
  destination: GitHub Actions job log; FAIL lines printed via `assert_eq` helpers
  fail_loud: yes — `set -euo pipefail` at the top of the test plus a non-zero exit code from `print_results` when FAIL counter is non-zero
failure_modes:
  - mode: knowledge-base/design/ directory regresses into HEAD via a future PR
    detection: Block A `git ls-tree -r HEAD -- knowledge-base/design/` returns non-empty
    alert_route: red CI check on the offending PR; reviewer sees FAIL line in job log
  - mode: knowledge-base/design/ directory appears on operator disk via a future PR (e.g., a `.gitignore`'d artifact that the test runner does not stash)
    detection: Block B `find knowledge-base -maxdepth 2 -type d -name design` returns paths other than knowledge-base/product/design
    alert_route: red CI check on the offending PR; reviewer sees FAIL line in job log
  - mode: ux-design-lead agent spec regresses to reference the deprecated path
    detection: existing agent-spec grep returns matches
    alert_route: red CI check on the offending PR
logs:
  where: GitHub Actions `test-scripts` job log per workflow run
  retention: 90 days (GitHub Actions default for public repos and the Soleur org default)
discoverability_test:
  command: bash plugins/soleur/test/ux-design-lead-output-path-guard.test.sh
  expected_output: exits 0 with PASS lines for each of: agent-spec grep, HEAD ls-tree, on-disk find, canonical path reference, size-verification rail, no-stub-fabrication rail; FAIL summary count 0
```

The `discoverability_test.command` is a single local invocation — operators can run it from any worktree without SSH or external service access. This satisfies the Phase 4.7 "command must not contain `ssh `" reject.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — pure repo-hygiene cleanup (delete a placeholder, harden a test). No new user-facing surface, no schema, no auth, no billing, no infra, no copy change.

## Infrastructure (IaC)

Not applicable. No new infrastructure surface, no vendor account, no secret, no DNS record, no systemd unit.

## GDPR / Compliance

Not applicable. No regulated-data surface touched. Per Phase 2.7 canonical regex and the four expanded triggers (LLM-on-operator-data, brand-survival single-user-incident, KB-reads from cron, artifact distribution surface) — none fire.

## Risks

- **R1: The test edit and the file delete land in different commits, leaving an intermediate commit where the new HEAD assertion fails.** Mitigation: land both changes in a single commit. The Implementation Phases above explicitly co-locate them.
- **R2: A reviewer assumes the brand-guide.md scope-out is forgotten work.** Mitigation: the Research Reconciliation table at the top of this plan documents the verification result; the PR body must include the `grep -c` output from AC7 to demonstrate the file is already clean.
- **R3: The `find -maxdepth 2` assertion in the guard misses a regression that lands at depth 3+ (e.g., `knowledge-base/foo/design/`).** Accepted: the guard is scoped to the specific top-level regression class that #2617 introduced; deeper regressions are out of scope and would be caught by code review of any PR introducing a new `design/` folder. The original `git ls-tree -r HEAD knowledge-base/design/` assertion catches any regression at exactly the regressed path. No further depth is needed.
- **R4: Operator KB-viewer caching.** Some operators may have the stray folder cached in browser state or local clones. Mitigation: documented in AC9; no workflow gap, just normal `git pull` semantics.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Section above is populated with concrete values.
- The new `git ls-tree -r HEAD -- knowledge-base/design/` assertion requires the test to be run from inside a git work-tree where `REPO_ROOT` is the worktree root. The existing `REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"` computation already satisfies this. Use the explicit `git -C "$REPO_ROOT" ls-tree ...` form (verified at deepen-plan time to work correctly in a `.worktrees/` worktree). Do NOT re-derive `REPO_ROOT` via `git rev-parse --show-toplevel` — the existing relative-traversal form keeps the test consistent with sibling tests in `plugins/soleur/test/`.
- The empty-string `assert_eq` in Block A is safe: `plugins/soleur/test/test-helpers.sh:16` evaluates `[[ "$expected" == "$actual" ]]`, which returns true when both arguments are empty strings. Verified against the helper source at deepen-plan time. No fallback to `[[ -z "$head_tree" ]]` needed.
- The hardened test is auto-discovered by `scripts/test-all.sh:165` (the `for f in plugins/soleur/test/*.test.sh ...` loop) and runs as part of the `test-scripts` job in `.github/workflows/ci.yml`. No CI workflow edits required.

## Test Strategy

- The hardened guard `plugins/soleur/test/ux-design-lead-output-path-guard.test.sh` IS the test. No new test framework required (the file uses the existing repo bash-test convention via `test-helpers.sh`).
- Run command: `bash plugins/soleur/test/ux-design-lead-output-path-guard.test.sh`. Exit code 0 = pass. Sibling tests in `plugins/soleur/test/` follow the same convention; no `bun test` / `vitest` / `pytest` involvement.
- CI discovery: verified at deepen-plan time — `scripts/test-all.sh:165` globs `plugins/soleur/test/*.test.sh` and runs each file under the `test-scripts` job in `.github/workflows/ci.yml`. No `plugins/soleur/test/run-all.sh` exists (verified absent). The hardened test is auto-picked-up by the existing glob.
- The package's `package.json scripts.test` is unaffected by this change.

## Why this plan is small

The task is a literal one-file delete plus a two-block test edit. The MINIMAL detail template applies. There are no:

- new dependencies,
- schema changes,
- auth or billing surfaces,
- runtime code paths,
- third-party API contracts,
- UI surfaces,
- migrations,
- infrastructure additions.

Plan-review (Phase 6) and deepen-plan (next stage) should validate the reconciliation table and the test-edit shape, not expand scope. Anything beyond the listed AC set should be filed as a separate issue.

## PR Body Reminder

- Title: `fix: remove regressed stale knowledge-base/design/ folder and harden guard`
- Body sections:
  - **Summary** — one paragraph: what regressed, where the canonical lives, what the guard now asserts.
  - **Reconciliation** — note that the brand-guide.md line cited in the original task description is already clean (line 376 references the canonical path); cite the `grep -c` zero-match output.
  - **Verification** — paste output of AC1, AC2, AC3, AC4, AC6, AC7 commands.
  - **Ref** — link the originating user message / issue if one exists. Use `Ref #N`, not `Closes #N` — the issue (if any) is a cosmetic state-truing for operator workspaces, not a code-change-with-test post-condition.

## Resume Prompt

```text
/soleur:work knowledge-base/project/plans/2026-05-21-fix-remove-stale-kb-design-folder-plan.md. Branch: feat-one-shot-remove-stale-kb-design-folder. Worktree: .worktrees/feat-one-shot-remove-stale-kb-design-folder/. Plan reviewed, implementation next: delete the regressed 0-byte file and harden the guard test with HEAD + on-disk assertions.
```
