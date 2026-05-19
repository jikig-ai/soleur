---
title: "fix(ci): secret-scan blocks main on jwt.io fixture in colocated lib test"
type: bug-fix
lane: single-domain
issue: 4099
related_issues: [4090, 4066]
requires_cpo_signoff: false
status: draft
classification: ci-gate-restore
created: 2026-05-19
deepened: 2026-05-19
---

## Enhancement Summary

**Deepened on:** 2026-05-19
**Sections enhanced:** 7 (Overview, Research Reconciliation, ACs, Implementation Phases, Sharp Edges, Files to Edit, plus new Research Insights subsection)
**Research artifacts:**
- Live `gitleaks git --no-banner --exit-code 0 --verbose` reproduction against the worktree (confirmed 2 findings, both at `apps/web-platform/lib/safety/redaction-allowlist.test.ts:101` reachable via commits `0def2e2d` and `7cad1fa5`).
- Live verification of 16 `[[rules]]` blocks each carrying 1 `apps/web-platform/test/.*\.test\.(ts|tsx)$` entry → AC3's pairing count is **16**.
- Live verification of all cited PR/issue numbers: #4099 OPEN, #4090 OPEN, #4066 OPEN (head: `feat-daily-priorities-multi-source`), #4085 MERGED (`2c245478…`).
- Live verification of all 8 cited AGENTS.md rule IDs (none retired; all present as active rules).
- Live verification of all cited GitHub labels (`secret-scan-allowlist-ack`, `bug`, `domain/engineering` all exist).
- Cross-referenced learning [`2026-05-16-allowlist-diff-shadowed-widening-and-gitleaks-verbose-flag.md`](../learnings/2026-05-16-allowlist-diff-shadowed-widening-and-gitleaks-verbose-flag.md) — confirmed the `allowlist-diff` gate uses a deduped-union parser; this PR's path is brand-new across all 16 rules, so the gate WILL fire (ack-label + trailer requirement is real, not vestigial).
- Cross-referenced [`2026-05-04-gitleaks-secret-scanning-floor-rollout.md`](../learnings/2026-05-04-gitleaks-secret-scanning-floor-rollout.md) — (a) non-capturing group convention (applies to regexes, not paths — N/A here), (b) GitHub push-protection blocks Doppler-shape literals in workflow files (relevant: the new smoke-matrix case uses the existing split `FAKE_DOPPLER_PREFIX`/`FAKE_DOPPLER_BODY` pattern verbatim, no new literal).

### Key Improvements
1. **AC4 + diagnostic snippets** now mandate `--redact -v` (verbose + redacted) per the 2026-05-16 learning — `gitleaks ... --no-banner --exit-code 1` alone prints only the count, not the per-finding metadata. Without `-v`, a future operator diagnosing a regression cannot identify the offending file:line without a second invocation.
2. **AC3 pairing count fixed at 16** with the literal block-line numbers (lines 103, 120, 133, 150, 162, 176, 188, 200, 215, 227, 241, 258, 278, 297, 308, 318) so the implementation pass can verify completion mechanically with `grep -c`.
3. **Smoke-matrix case fixture** explicitly uses the existing `FAKE_DOPPLER_PREFIX`/`FAKE_DOPPLER_BODY` runtime concatenation per the 2026-05-04 learning (b) — committing a contiguous Doppler-shape literal in the workflow YAML would be blocked by GitHub push protection.
4. **Phase 5 advisory comment is conditional** — if PR #4066 has already merged before this PR lands, skip Phase 5 entirely (the allowlist now covers the path, so the inline waiver is no longer load-bearing).
5. **Risk-side annotation:** the `allowlist-diff` gate is union-based (per the 2026-05-16 learning); my widening adds a path that is genuinely new across all 16 rules, so the gate fires correctly. No deferred parser-improvement work is needed for THIS PR.

### New Considerations Discovered
- The 4 sibling colocated `.test.ts` files under `apps/web-platform/lib/` (`auth/validate-origin`, `auth/csrf-coverage`, `auth/error-messages`, `feature-flags/server`) are the structural-class beneficiaries. None of them currently contain JWT/Doppler/Supabase shapes (verified by inspection of file purposes), but the convention drift would have re-tripped the gate the next time one of them adopted a synthesized token shape.
- The `private-key` and `database-url-with-password` rules (lines 247, 311) carry an additional `knowledge-base/project/learnings/.*\.md$` carve-out (per #3268 and #3874). My widening adds a DIFFERENT path; no interaction with those carve-outs.

# fix(ci): secret-scan failing on main since #4085 — jwt.io fixture in colocated lib test

## Overview

`secret-scan` workflow has failed on every push to `main` since 2026-05-19 18:51Z (`5408712d`, `cfc59fa6`, `25b0f9e4`, `8ee74051`, `c0e98702`, `2c245478` — 6 consecutive runs). The gate is a load-bearing CI floor — every push to `main` should be green.

**Root cause (verified by local `gitleaks git --no-banner` run, 2026-05-19 21:57 UTC):**

The leak is the canonical jwt.io HS256 example token

```
eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTYifQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c
```

at `apps/web-platform/lib/safety/redaction-allowlist.test.ts:101`, reachable via commits `0def2e2d` and `7cad1fa5` on branch `feat-daily-priorities-multi-source` (PR #4066). The token decodes to `{"sub":"123456"}` and is signed with the published demo secret `your-256-bit-secret` — zero credential value. It is the canonical JWT.io "Hello, World" fixture.

The `jwt` rule's path allowlist at `.gitleaks.toml:297` covers `apps/web-platform/test/.*\.test\.(ts|tsx)$` but NOT `apps/web-platform/lib/.*\.test\.(ts|tsx)$`. The test file is colocated with its source (`apps/web-platform/lib/safety/redaction-allowlist.ts`), per the project's colocated-test convention — and the convention was never reflected in the gitleaks rule allowlists.

This is the **same leak** that issue #4090 already identified independently (surfaced via PR #4045's post-merge scan on 2026-05-19 21:01Z). #4099 and #4090 are duplicates; #4090 proposes inline waiver / mutation / allowlist-path as the three fix shapes. This plan picks the third path (structural class fix) because four other colocated `.test.ts` files already exist under `lib/` (`auth/validate-origin`, `auth/csrf-coverage`, `auth/error-messages`, `feature-flags/server`) and the next one to ship a JWT/Doppler/Supabase shape will re-trip the gate identically.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue #4099 body) | Reality (verified) | Plan response |
|---|---|---|
| "regression introduced by #4085" | #4085's diff scan returns 0 leaks (`gitleaks git --log-opts="2c245478~1..2c245478"`). #4085 is innocent. The actual leaking commits are `0def2e2d` / `7cad1fa5` from `feat-daily-priorities-multi-source` (PR #4066, May 19 15:20Z, 3.5h before #4085 merged). | Treat #4085 attribution as wrong. Don't bisect inside #4085. Quote `feat-daily-priorities-multi-source` as the true source and reference #4066. |
| "likely Inngest webhook signing key / bootstrap env var / JWT-shape migration" | None of those — the leak is a canonical jwt.io demo token in a colocated test file unrelated to Inngest. | Replace assumptions with the empirically-confirmed file:line `apps/web-platform/lib/safety/redaction-allowlist.test.ts:101`. |
| "gitleaks-allowlist the fixture path OR rewrite the value" | Both viable. Path allowlist is the structural class fix (covers next 4 sibling files); inline waiver is the per-file fix. | Land path allowlist on main (this PR). Recommend inline waiver to PR #4066 author as belt-and-suspenders (see Phase 4). |
| Issue #4090 says "this should be fixed in `feat-daily-priorities-multi-source` PR, not in a separate branch" | Partially correct — inline waiver MUST land on PR #4066's branch. But the structural class fix (path widening) belongs on main and unblocks `main`'s secret-scan immediately regardless of when #4066 merges. | Split: structural fix on main (this PR), inline waiver advised to #4066 author. |
| "Related: #4090" | Confirmed — #4090 is the original triage of the same leak surfaced on 2026-05-19 21:01Z (PR #4045 post-merge). #4099 was filed 50min later from PR #4092 post-merge ship Phase 7 without the author having seen #4090. | Close one as duplicate at merge time. Pick #4099 (this issue) as canonical because it has wider failure-history evidence; close #4090 as dup. |

## User-Brand Impact

**If this lands broken, the user experiences:** every PR to `main` is blocked by a red `secret-scan / gitleaks scan (push)` check on main; ship Phase 7 verification reports red on every PR; eventually the team learns to ignore the red check, eroding the CI floor's value as a real-leak detector.

**If this leaks, the user's data / workflow / money is exposed via:** N/A — this PR widens the allowlist for a known-synthetic shape under a path scoped to `*.test.ts` files only. No production-code path is allowlisted. The token in question is the canonical jwt.io demo signed with a published demo secret.

**Brand-survival threshold:** none — `lib/<module>/*.test.ts` files are colocated-test scaffolding; the lefthook `lint-fixture-content` gate and GitHub push protection both still scan these paths independently. The compensating controls in `.gitleaks.toml:65-72` apply. Scope-out: threshold none, reason: allowlist widening targets `*.test.ts` files only, defense-in-depth (lint-fixture-content + GitHub push protection) covers the same paths, and the `allowlist-diff` workflow already gates this PR with CODEOWNERS + ack-label review.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — `.gitleaks.toml` rule `jwt` (line 289-297) `[[rules.allowlists]] paths` list contains `'''apps/web-platform/lib/.*\.test\.(ts|tsx)$'''` as a new entry. Verify with `grep -nE "apps/web-platform/lib/\.\*\\\\\\.test" .gitleaks.toml` returning ≥1 match.
- [ ] AC2 — Same path entry added to the `generic-api-key` rule's allowlist (line 306-308) — colocated `lib/<module>/*.test.ts` files can legitimately host synthesized `api_key="..."` shapes in CSRF/auth-token tests. Verify with the same grep against the `generic-api-key` block (use `awk '/^\[\[rules\]\]/,0' | grep ...` scoped form to confirm it's in the right block, NOT a self-match-trap awk range).
- [ ] AC3 — Same path entry added to all 13 custom-rule allowlists in `.gitleaks.toml` (`soleur-byok-key`, `doppler-api-token`, `supabase-service-role-jwt`, `supabase-anon-jwt`, `supabase-access-token`, `stripe-webhook-secret`, `anthropic-api-key`, `resend-api-key`, `cf-scoped-token`, `sentry-auth-token`, `discord-webhook-url`, `database-url-with-password`, `vapid-private-key`) AND the three default-pack overrides (`jwt`, `generic-api-key`, `private-key`). Verification: `grep -c "apps/web-platform/lib/\.\*\\\\\\.test" .gitleaks.toml` returns the number of rules-with-allowlists currently in the file (count via baseline: `grep -c "apps/web-platform/test/\.\*\\\\\\.test" .gitleaks.toml` — the new count MUST equal the baseline).
- [ ] AC4 — Local full-tree scan returns 0 leaks: `gitleaks git --no-banner --exit-code 1 --redact -v` exits 0. Capture the output line `scanned ~64 MB in <Ns>` and `no leaks found` (or `leaks found: 0`) and paste into the PR body. Note: `-v` (verbose) is required to surface per-finding metadata if the scan fails — `--redact` alone prints only the count and is insufficient for diagnosis per learning `2026-05-16-allowlist-diff-shadowed-widening-and-gitleaks-verbose-flag.md`.
- [ ] AC5 — Smoke matrix in `.github/workflows/secret-scan.yml` (jobs.smoke-tests.strategy.matrix.case) gains a new case `colocated-lib-test-allowlist`. The case stages `apps/web-platform/lib/safety/__smoke__/with-secret.test.ts` containing the `$FAKE_DOPPLER` synthesized token and asserts `./gitleaks git --pre-commit --staged --redact --no-banner --exit-code 1` exits 0 (allowlist hit). Mirror the `allowlist-positive` case's shape verbatim with the path swap.
- [ ] AC6 — PR labeled `secret-scan-allowlist-ack` AND PR body contains `Allowlist-Widened-By: jean.deruelle@jikigai.com` commit trailer (defense-in-depth — either alone satisfies `allowlist-diff.sh`; both gives a graceful failure mode if one is dropped). Verify: `git log -1 --format=%B | grep -E "^Allowlist-Widened-By:"` returns 1 line.
- [ ] AC7 — `Ref #4099`, `Closes #4090` in PR body (canonical issue stays open until merged; #4090 is a duplicate closed on merge). Per `wg-use-closes-n-in-pr-body-not-title-to`.
- [ ] AC8 — Smoke matrix run in CI returns green for ALL 10 cases (9 existing + 1 new). Confirmed via `gh run watch <run-id>` or `gh pr checks <PR-N>` after push.
- [ ] AC9 — `secret-scan / gitleaks scan (push)` job in CI on this PR's HEAD-branch returns green (PR-event runs the diff-scan branch which already returned 0 leaks against PR #4085; the new test is that it ALSO stays green after the config change). Verify via `gh pr checks <N>`.
- [ ] AC10 — `secret-scan / waiver-discipline` and `secret-scan / allowlist-diff` jobs return green. The latter MUST emit a `gh pr comment` with the path-widening diff body; verify by reading the comment under `gh pr view <N> --comments`.

### Post-merge (operator + automated)

- [ ] AC11 — First push to `main` (the merge commit of this PR) triggers `secret-scan / gitleaks scan (push)`; conclusion = `success`. Automated check via `/soleur:ship` Phase 7 (operator-driven trigger is `gh pr merge --auto`; the workflow runs on push).
- [ ] AC12 — Post a comment on PR #4066 (`feat-daily-priorities-multi-source`) recommending an inline waiver as belt-and-suspenders. Automation: `gh pr comment 4066 --body-file <comment>` from a Phase 5 step. The comment cites the canonical waiver shape from `.gitleaks.toml:21`. Skip if PR #4066 has already merged (the structural fix here already covers it).
- [ ] AC13 — Capture a learning at `knowledge-base/project/learnings/bug-fixes/<topic>.md` (date and exact filename chosen at write-time, NOT in this plan per the dates-drift sharp-edge rule). Topic: "colocated lib `*.test.ts` files were not in gitleaks `*.test.*` allowlist — convention drift between `apps/web-platform/test/` (test root) and `apps/web-platform/lib/<m>/*.test.ts` (colocated). Structural fix: widen allowlists to cover both. Companion sharp edge: when adopting colocated tests, audit ALL gate path-patterns scoped to the legacy `test/` root."

## Files to Edit

- `.gitleaks.toml` — add `'''apps/web-platform/lib/.*\.test\.(ts|tsx)$'''` to the 16 `[[rules.allowlists]] paths` lists (13 custom rules + 3 default-pack overrides). One mechanical sweep. Pair every existing `apps/web-platform/test/.*\.test\.(ts|tsx)$` with the new `lib/` sibling.
- `.github/workflows/secret-scan.yml` — extend the smoke matrix at lines 266-274 with case `colocated-lib-test-allowlist` (added to the `case:` list) and a new branch in the `case` switch (lines 318-455) following the `allowlist-positive` shape.

## Files to Create

- None (the smoke fixture is staged at runtime inside the matrix case, not a committed file — matching the existing matrix pattern).

## Implementation Phases

### Phase 0 — Preconditions

- Verify local gitleaks v8.24.2 install: `gitleaks version` → `8.24.2`.
- Confirm current baseline failure: `gitleaks git --no-banner --exit-code 0 --verbose` reports exactly 2 findings (the same JWT in two commits `0def2e2d` and `7cad1fa5`), both at `apps/web-platform/lib/safety/redaction-allowlist.test.ts:101`. If the count differs, halt — a new leak appeared post-plan-write.
- Read `.gitleaks.toml` and enumerate the 16 allowlist blocks (lines 103, 120, 133, 150, 162, 176, 188, 200, 215, 227, 241, 258, 278, 297, 308, 318 — verified at deepen time, 2026-05-19); count `apps/web-platform/test/.*\.test\.(ts|tsx)$` occurrences: `grep -c "apps/web-platform/test/\.\*\\\\\\.test\\\\\.(ts|tsx)" .gitleaks.toml` → expect 16. The new `lib` occurrences MUST equal 16 after Phase 1 edits.
- Confirm the new path string is not yet present: `grep -c "apps/web-platform/lib/\.\*\\\\\\.test\\\\\.(ts|tsx)" .gitleaks.toml` → expect 0 (verified at deepen time).

### Phase 1 — Widen `.gitleaks.toml` allowlists

Mechanical edit: for every `[[rules.allowlists]]` block in `.gitleaks.toml`, add `'''apps/web-platform/lib/.*\.test\.(ts|tsx)$'''` to the `paths` list, positioned immediately after the existing `'''apps/web-platform/test/.*\.test\.(ts|tsx)$'''` entry. Do NOT touch `paths` lines that lack the `test/` entry (none currently exist; defensive). Do NOT introduce a path that captures non-test files (no glob `**/*.ts`).

Verification post-edit: `gitleaks git --no-banner --exit-code 1` exits 0.

### Phase 2 — Smoke matrix case

Add `colocated-lib-test-allowlist` to `jobs.smoke-tests.strategy.matrix.case` list (line ~267) and a new `case` branch in the runner script (lines ~318-455). Mirror `allowlist-positive` exactly except for the path:

```yaml
colocated-lib-test-allowlist)
  mkdir -p apps/web-platform/lib/safety/__smoke__
  echo "$FAKE_DOPPLER" > apps/web-platform/lib/safety/__smoke__/with-secret.test.ts
  git add apps/web-platform/lib/safety/__smoke__/with-secret.test.ts
  ./gitleaks git --pre-commit --staged --redact --no-banner --exit-code 1
  echo "PASS: colocated lib test path didn't trip"
  ;;
```

Rationale: The matrix is the canonical regression gate for allowlist semantics — without this case, the next gitleaks bump or config drift that drops the new path entry would silently regress.

### Phase 3 — Local verification

Run from worktree root using the canonical diagnostic form (per learning `2026-05-16-allowlist-diff-shadowed-widening-and-gitleaks-verbose-flag.md`):

```bash
gitleaks git --no-banner --exit-code 1 --redact -v 2>&1 | tail -40
# expect: ~1980 commits scanned, ~64 MB, "no leaks found", exit 0
echo "Exit: $?"  # expect 0
```

If non-zero exit, the `-v` flag surfaces per-finding `Finding / Secret / RuleID / File / Line / Commit` metadata so the missing-block diagnosis is one-shot. Most likely root cause: the `lib/` path was added to fewer than 16 blocks — confirm with `grep -c "apps/web-platform/lib/\.\*\\\\\\.test\\\\\.(ts|tsx)" .gitleaks.toml` → must equal 16.

### Phase 4 — PR creation

Body MUST contain:
- `Closes #4090` (the older duplicate issue; auto-close at merge is correct because this PR fully resolves it on main).
- `Ref #4099` (canonical issue stays open via `Ref` until manually closed; this avoids the ops-remediation `Closes` trap, though this PR is NOT ops-remediation — applying `Closes #4099` is also acceptable; chose `Closes #4090, Closes #4099` final form pending /work-phase reconsideration).
- `Allowlist-Widened-By: jean.deruelle@jikigai.com` commit trailer.
- Local-run output paste: `gitleaks git --no-banner --exit-code 1` → `leaks found: 0`.
- Pre-existing failure context (the 6-commit failure run-id list).

Apply label `secret-scan-allowlist-ack` immediately after PR creation: `gh pr edit <N> --add-label secret-scan-allowlist-ack`.

### Phase 5 — Cross-PR advisory comment

Automation: `gh pr comment 4066 --body <comment>` (skip if PR #4066 has merged before this PR lands). The comment recommends an inline waiver on the leaking line:

```ts
// gitleaks:allow # issue:#4099 canonical jwt.io HS256 example, signed with published demo secret "your-256-bit-secret"
const jwt = "eyJhbGc...";
```

The structural fix in this PR is sufficient on its own; the inline waiver is a belt-and-suspenders self-documenting marker for future readers.

### Phase 6 — Post-merge verification (automated via /soleur:ship Phase 7)

`/soleur:ship` Phase 7 already runs `gh run watch` on the merge commit's `secret-scan` workflow. No new tooling — this is the existing gate exercising the new config.

## Open Code-Review Overlap

Query: `gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json`, then per-file grep for `.gitleaks.toml` and `secret-scan.yml`.

Result: None. (Verified at plan-write time via `jq -r --arg path ".gitleaks.toml" '...' /tmp/open-review-issues.json` and equivalent for `secret-scan.yml` — no open code-review label items reference these files.)

## Domain Review

**Domains relevant:** Engineering (CI-gate infrastructure).

### Engineering

**Status:** carry-forward from `wg-ship-push-before-merge` + `cq-test-fixtures-synthesized-only` (both apply; both satisfied by this plan's choices). No fresh domain-leader spawn needed — pure CI-gate restoration with no behavioral change outside the gate itself.

**Assessment:** Allowlist widening is scoped to `*.test.ts` files only. Compensating controls (lefthook `lint-fixture-content`, GitHub push protection) cover the same paths. The `allowlist-diff` job is the change-control gate; this PR exercises it as designed. No GDPR/privacy/security regression — the fixture is a public canonical token with zero credential value.

## Infrastructure (IaC)

Not applicable. No infrastructure surface (servers, vendor accounts, DNS, certs, secrets, firewall rules) created or modified. Pure repository-config edit + CI-workflow matrix extension.

## GDPR / Compliance Gate

Plan touches only `.gitleaks.toml` (CI config) and `.github/workflows/secret-scan.yml` (CI workflow). No regulated-data surface per the `hr-gdpr-gate-on-regulated-data-surfaces` canonical regex — no schemas, migrations, auth flows, API routes, or `.sql` files. None of the (a)-(d) expanded triggers apply (no new LLM/external API on operator-session data, brand-survival threshold is `none`, no new cron/workflow reading learnings/specs, no new artifact distribution surface). Skip silently.

## Hypotheses

(Phase 1.4 network-outage checklist gate — N/A. Issue body keywords are CI/gitleaks/secret-scan; none match the SSH/network triggers.)

## Sharp Edges

- **Issue #4099's premise is wrong about #4085.** Do NOT bisect inside #4085 — its diff scan is clean. The real leaking commits are `0def2e2d` and `7cad1fa5` on `feat-daily-priorities-multi-source` (PR #4066), introduced 3.5h before #4085 merged. The timing coincidence with #4085 is a red herring caused by `gitleaks git`'s full-history walk picking up the (then-newly-reachable) feat-branch commits on the first `push:main` run after #4066 was pushed.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.**
- The `cq-test-fixtures-synthesized-only` rule: the jwt.io fixture IS synthesized (canonical public demo). The widening is consistent with the rule's intent. If a future maintainer wants stricter local hygiene, the inline waiver path remains available — both fixes coexist cleanly.
- Verify that the `lib/` path entry is added to **every** `[[rules.allowlists]] paths` array, not just the `jwt` block. The 16-block count is load-bearing: a partial sweep leaves a future Stripe-webhook / Doppler / Supabase-token fixture under a colocated `lib/auth/*.test.ts` re-tripping the gate on a different rule.
- Per `cq-rule-ids-are-immutable` — no rule IDs change in this PR; only `paths` arrays. No AGENTS.md rule-ID edits.
- When the smoke matrix case is added, the staged fixture path `apps/web-platform/lib/safety/__smoke__/with-secret.test.ts` MUST be under `lib/` (the path being tested), not `test/` (which already passes). Verify by reading the case body before commit.
- The `allowlist-diff` workflow at `.github/workflows/secret-scan.yml:228-250` will fire and require `secret-scan-allowlist-ack` label OR `Allowlist-Widened-By:` commit trailer. Apply both (belt-and-suspenders) per AC6.
- When the smoke case is added, the matrix has fail-fast: false (line 264) so a new case failure doesn't mask sibling failures. Verify after the YAML edit that the new case is positioned within the existing `case:` list (line ~267) and that the case-branch in the runner script (line ~318) does NOT shadow another case via fall-through.
- The verification regex in AC1 (`grep -nE "apps/web-platform/lib/\.\*\\\\\\.test" .gitleaks.toml`) escapes the `.` characters correctly for awk/grep — the literal in the TOML file is `apps/web-platform/lib/.*\.test\.(ts|tsx)$`. Don't paraphrase the regex; copy-paste from this plan.
- **Deduped-union gate behavior (per learning `2026-05-16-allowlist-diff-shadowed-widening-and-gitleaks-verbose-flag.md`):** `parse-gitleaks-allowlists.mjs` extracts ALL `[[rules.allowlists]] paths` across every rule as a flat deduped union; `allowlist-diff.sh` then diffs base-union vs head-union. If a widening adds a path to rule A that was already present under rule B, the gate silently passes. In THIS PR, the new path `apps/web-platform/lib/.*\.test\.(ts|tsx)$` is genuinely new across ALL 16 rules (verified by `grep -c` returning 0 at plan time), so the gate WILL fire and require ack-label/trailer. The belt-and-suspenders in AC6 (BOTH label + trailer) is intentional, not vestigial. **Do NOT assume future maintainers reading this plan will know the union nuance** — keep the dual-ack pattern.
- **Reachable-but-not-on-main commits:** `gitleaks git` (no log-opts) walks every reachable commit in the object DB, including commits on feature branches that have been pushed to `origin` but not merged to `main`. The leak surfaces from `feat-daily-priorities-multi-source` (PR #4066) even though that branch hasn't merged. This is the same class as #4090 (different feature branch, same fixture, same leak). Both #4099 and #4090 are duplicates of the same underlying issue; `Closes #4090` in this PR's body is the canonical dedup.
- **Phase 5 conditional skip:** If PR #4066 (`feat-daily-priorities-multi-source`) merges before this PR lands, skip the Phase 5 advisory comment. Once the allowlist widens to cover `lib/*.test.ts`, the inline waiver is no longer load-bearing for the gate — only useful as self-documenting prose. Verify PR state with `gh pr view 4066 --json state`; if `MERGED`, skip.

## Alternative Approaches Considered

| Approach | Why considered | Why rejected | Tracking |
|---|---|---|---|
| Inline waiver on PR #4066 only (no main-side fix) | Smallest blast-radius; #4090 originally proposed this | Doesn't prevent recurrence on the next 4 sibling `lib/<m>/*.test.ts` files. The convention drift (colocated tests not in `test/.*` allowlist) is the real bug. | Recommended as belt-and-suspenders in Phase 5 |
| Mutate the jwt fixture to break entropy | Surgical; no allowlist widening | Doesn't prevent recurrence on next synthesized JWT in another colocated `*.test.ts` | Not pursued |
| Add a single top-level `[allowlist]` path entry (line 78-90 block) instead of per-rule | Less diff; one edit point | The top-level block silences ALL rules including default-pack. The per-rule pattern in lines 100+ deliberately lets default-pack rules fire so a stray AWS key in a fixture is caught. Preserve that design. | Not pursued — rejecting per-rule pattern would weaken the gate |
| Use a `# gitleaks:allow # issue:#4099 ...` waiver in `redaction-allowlist.test.ts:101` only | Per-file fix; self-documenting | Cannot be done from this branch — requires edit on PR #4066's branch. Doesn't fix sibling files. | Phase 5 advisory comment to #4066 |
| Rewrite git history to remove the fixture from `feat-daily-priorities-multi-source` commits | "Properly" removes the leak | Destructive on an active feature branch; #4090's analysis correctly notes the fixture is a known-public canonical token with zero credential value. Rotation/rewrite is the wrong tool. | Not pursued |
| Allowlist `apps/web-platform/**/.*\.test\.(ts|tsx)$` (catch-all) | One pattern covers `lib/`, `server/`, `app/`, `components/`, future moves | Over-broad — `server/` and `app/route.ts` files could legitimately host real prod tokens during dev iteration. Keep the carve-out tight on `lib/` for now; widen later iff a sibling drift surfaces. | Future-only if another path tripping emerges |

## Mermaid — Allowlist Coverage Before vs. After

```mermaid
flowchart LR
  subgraph Before [Before — paths in jwt rule allowlist]
    A1[apps/web-platform/test/*.test.ts] --> P1[PASS]
    A2[apps/web-platform/lib/safety/redaction-allowlist.test.ts] -.X.-> F1[FAIL gitleaks]
    A3[apps/web-platform/lib/auth/csrf-coverage.test.ts] -.X.-> F2[would FAIL if it had JWT]
  end
  subgraph After [After — widened]
    B1[apps/web-platform/test/*.test.ts] --> Q1[PASS]
    B2[apps/web-platform/lib/**/.test.ts] --> Q2[PASS]
    B3[apps/web-platform/server/*.test.ts] -.X.-> F3[FAIL — intentional carve-out]
  end
```

## Notes

- Per `wg-plan-prescribed-skills-must-run-inline`, `/soleur:gdpr-gate` evaluated inline above and skipped (no regulated-data surface). `/soleur:deepen-plan` runs after this plan is written.
- Per `cq-test-fixtures-synthesized-only`, the jwt.io fixture qualifies (synthesized public canonical token, signed with published demo secret). No fixture content change needed.
- No new external dependencies, no version pins, no migration. The plan is a 16-line config diff plus a 10-line smoke matrix case.
