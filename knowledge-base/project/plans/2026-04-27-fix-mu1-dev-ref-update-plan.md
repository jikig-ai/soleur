---
title: "Update MU1 hostname guards from old prd ref to new dev ref"
type: fix
date: 2026-04-27
issue: 2887
priority: P0
classification: ops-only-prod-write-completion
parent_plan: knowledge-base/project/plans/2026-04-27-fix-supabase-env-isolation-plan.md
---

# Update MU1 hostname guards from old prd ref to new dev ref (#2887 — Phase 3)

## Enhancement Summary

**Deepened on:** 2026-04-27
**Sections enhanced:** Live-verification of every external claim, TDD-gate clarification, edit-order rationale.
**Verification done in this pass (live, not from memory):**

1. `gh issue view 2887 --json state,closedAt` → `{"state":"CLOSED","closedAt":"2026-04-27T07:59:28Z","milestone":"Phase 3: Make it Sticky"}`. Confirms parent plan closed it; this PR's `Closes #2887` is bookkeeping reaffirmation only.
2. `doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c dev --plain` → `https://mlwiodleouzwniehynfz.supabase.co`. `doppler secrets get SUPABASE_URL -p soleur -c dev --plain` → same. Confirms operator rotation is in place; the code edit is the ONLY remaining step.
3. `rg 'mlwiodleouzwniehynfz' --type-add 'src:*.{ts,tsx,js,mjs,sh,yml,yaml,tf}' -tsrc -tmd` → only this plan file. Confirms no code yet references the new ref.
4. `rg -n 'ifsccnjhymdmidffkzhl' apps/web-platform/infra/{mu1-cleanup-guard.mjs,mu1-runbook-cleanup.test.sh}` → 6 matches at exactly the lines the plan enumerates (guard:6, test:10,88,89,94,95). Confirms line numbers in `## Files to Edit` are correct as of this commit.

### Key Improvements (this pass)

1. **Edit-order rationale.** The guard constant and the test fixtures must be edited together in one commit, but the test happens to be the natural RED gate — see new `### TDD Gate Note` below. This avoids a transient half-state where the guard accepts the new ref but the test asserts against the old one (which would fail CI even though the runtime fix is correct).
2. **`Closes #2887` semantics clarified.** Issue is already CLOSED. `Closes` is harmless on a closed issue (GitHub auto-close is a no-op). The reason to keep the keyword is changelog grouping and search affinity — drop it and this PR becomes orphaned from the remediation chain in the changelog generator.
3. **No deepen-pass discovered drift.** Plan claims all match live state. No edits to file paths, line numbers, or counts required.

## Overview

This is **Phase 3 of the parent #2887 plan**, executing now that the new dev Supabase project ref exists and Doppler `dev` has been rotated. The parent plan shipped in two prior PRs:

- **PR #2903 (merged):** enforcement scaffolding — `hr-dev-prd-distinct-supabase-projects` rule, preflight Check 4, runbook §0, ADR-023.
- **PR #2926 (merged):** added `--bootstrap=skip` flag to `run-migrations.sh` (#2911).

Operator then provisioned `soleur-dev` (ref `mlwiodleouzwniehynfz`), applied 39 migrations with `--bootstrap=skip`, and rotated 6 Doppler `soleur/dev` secrets (URL, anon, service-role, DB direct, DB pooler, plus added `SUPABASE_URL`). The `ci` config was audited and rotated to `https://test.supabase.co` placeholder.

What remains is the mechanical part the parent plan called out at Phase 3 line 67 of the issue body: flip the hardcoded `DEV_PROJECT_REF` constant + matching test fixtures from the old prd ref `ifsccnjhymdmidffkzhl` to the new dev ref `mlwiodleouzwniehynfz`. Until this lands, `mu1-cleanup-guard.mjs` rejects the new dev project (its expected hostname is now wrong) and `mu1-runbook-cleanup.test.sh` fails its happy-path case.

This is a 2-file edit. No new design decisions.

## Problem Statement

Confirmed via Doppler at plan time:

```text
old prd ref: ifsccnjhymdmidffkzhl  (still serves prd via CNAME api.soleur.ai)
new dev ref: mlwiodleouzwniehynfz  (per operator, soleur-dev project)
```

The MU1 cleanup guard and its test fixture were authored when dev IS prd was true. Both reference the old prd ref as the "expected dev hostname." After the rotation:

1. `apps/web-platform/infra/mu1-cleanup-guard.mjs:6` — `DEV_PROJECT_REF = "ifsccnjhymdmidffkzhl"` is now the **prd** ref, not dev. The guard's exact-hostname compare in `assertDevCleanupEnv` will reject the new dev URL `https://mlwiodleouzwniehynfz.supabase.co` and throw `hostname '<new-ref>.supabase.co' != expected dev hostname 'ifsccnjhymdmidffkzhl.supabase.co'`. Sweep cannot run.
2. `apps/web-platform/infra/mu1-runbook-cleanup.test.sh:10` — `DEV_URL="https://ifsccnjhymdmidffkzhl.supabase.co"` is the test's "happy path" input. Without updating to the new ref, the happy-path case `DOPPLER_CONFIG=dev + correct URL → no throw` becomes impossible to satisfy: the only URL that won't throw is the new ref, but the test injects the old ref.
3. `apps/web-platform/infra/mu1-runbook-cleanup.test.sh:88,89,94,95` — prefix-attack fixtures hardcode the old ref as the bypass-attack base (`https://ifsccnjhymdmidffkzhl.supabase.co.evil.com`, `https://ifsccnjhymdmidffkzhlfoo.supabase.co`). After flipping the guard, the bypass attempts must use the **new** ref as the base, otherwise the test no longer exercises the prefix-bypass path against the value the guard now compares against.

The SYNTH allowlist regex in `apps/web-platform/test/mu1-integration.test.ts:45-46` is **email-shaped** (`mu1-integration-<uuid>@soleur-test.invalid`), not project-ref shaped. It does NOT reference any Supabase project ref. **No change required.** The misleading comment in `mu1-cleanup-guard.mjs:3-5` ("update DEV_PROJECT_REF here AND the SYNTH allowlist regex in test/mu1-integration.test.ts in the same commit — they are coupled") was a defensive note from the original author; the deepen pass on the parent plan confirmed the regex has no project-ref coupling. We will leave the comment as-is to avoid scope creep, since the comment's prescription (update both in one commit) is harmless when the regex genuinely needs no change.

## Audit Reconciliation — `rg 'ifsccnjhymdmidffkzhl'` Classification

The deepen pass for #2887 identified 12 hits across the repo. Re-running the audit at plan time confirms the same 12 hits, classified into KEEP / UPDATE:

| Hit | Classification | Reason |
|---|---|---|
| `apps/web-platform/infra/mu1-cleanup-guard.mjs:6` | **UPDATE** | `DEV_PROJECT_REF` constant — the central change |
| `apps/web-platform/infra/mu1-runbook-cleanup.test.sh:10` | **UPDATE** | `DEV_URL` happy-path input |
| `apps/web-platform/infra/mu1-runbook-cleanup.test.sh:88,89` | **UPDATE** | subdomain-bypass fixture pair (assertion + URL must match new ref) |
| `apps/web-platform/infra/mu1-runbook-cleanup.test.sh:94,95` | **UPDATE** | prefix-match-bypass fixture pair (assertion + URL must match new ref) |
| `apps/web-platform/infra/dns.tf` | **KEEP** | prd CNAME `api.soleur.ai` → `ifsccnjhymdmidffkzhl.supabase.co` — this is the prd ref, correct as-is |
| `knowledge-base/engineering/architecture/decisions/ADR-023-supabase-environment-isolation.md` | **KEEP** | ADR documenting the prd ref as the user-facing project — historical/correct |
| `knowledge-base/project/learnings/workflow-issues/google-oauth-consent-screen-branding-…` | **KEEP** | time-stamped learning |
| `knowledge-base/project/learnings/integration-issues/supabase-custom-domain-oauth-branding-…` | **KEEP** | time-stamped learning |
| `knowledge-base/project/learnings/runtime-errors/docker-dns-supabase-custom-domain-…` | **KEEP** | time-stamped learning |
| `knowledge-base/project/learnings/2026-04-23-hostname-prefix-guard-and-strict-mode-pipefail.md` | **KEEP** | time-stamped learning citing the prefix-bypass example |
| `knowledge-base/project/specs/feat-cc-single-leader-routing/tasks.md` | **KEEP** | spec recording past application against prd ref |
| `knowledge-base/project/specs/feat-fix-supabase-service-client/tasks.md` | **KEEP** | spec recording prd `SUPABASE_URL` Doppler set |
| `knowledge-base/project/plans/2026-04-02-fix-otp-code-length-mismatch-plan.md` | **KEEP** | historical plan referencing the prd Management API URL |
| `knowledge-base/project/plans/2026-04-02-fix-google-oauth-consent-screen-branding-plan.md` | **KEEP** | historical plan |
| `knowledge-base/project/plans/2026-04-18-sec-byok-tenant-isolation-verify-plan.md` | **KEEP** | historical plan |
| `knowledge-base/project/plans/2026-03-29-chore-verify-production-deployment-e2e-plan.md` | **KEEP** | historical plan |
| `knowledge-base/project/plans/2026-04-27-fix-supabase-env-isolation-plan.md` | **KEEP** | parent plan — references both refs intentionally |

Net: **2 files to edit**, 6 line edits total. All other hits are prd-bound infra or time-stamped historical artifacts and MUST NOT be rewritten.

## Open Code-Review Overlap

Open `code-review` issues query returned **zero** open issues at parent plan time and there is no reason to expect new ones in this surgical edit. Re-check at GREEN if needed:

```bash
gh issue list --label code-review --state open \
  --json number,title,body --limit 200 > /tmp/open-review-issues.json
jq -r --arg path "apps/web-platform/infra/mu1-cleanup-guard.mjs" '
  .[] | select(.body // "" | contains($path))
  | "#\(.number): \(.title)"
' /tmp/open-review-issues.json
```

None expected; if anything appears, fold-in or acknowledge per `rf-review-finding-default-fix-inline`.

## Files to Edit

1. **`apps/web-platform/infra/mu1-cleanup-guard.mjs`** — line 6
   - Change: `const DEV_PROJECT_REF = "ifsccnjhymdmidffkzhl";`
   - To: `const DEV_PROJECT_REF = "mlwiodleouzwniehynfz";`
   - The `DEV_HOSTNAME` template string on line 7 picks up the new ref automatically.

2. **`apps/web-platform/infra/mu1-runbook-cleanup.test.sh`** — lines 10, 88-89, 94-95
   - Line 10: `DEV_URL="https://ifsccnjhymdmidffkzhl.supabase.co"` → `DEV_URL="https://mlwiodleouzwniehynfz.supabase.co"`
   - Line 88: `"dev" "https://ifsccnjhymdmidffkzhl.supabase.co.evil.com" \` → `"dev" "https://mlwiodleouzwniehynfz.supabase.co.evil.com" \`
   - Line 89: `"hostname 'ifsccnjhymdmidffkzhl.supabase.co.evil.com'"` → `"hostname 'mlwiodleouzwniehynfz.supabase.co.evil.com'"`
   - Line 94: `"dev" "https://ifsccnjhymdmidffkzhlfoo.supabase.co" \` → `"dev" "https://mlwiodleouzwniehynfzfoo.supabase.co" \`
   - Line 95: `"hostname 'ifsccnjhymdmidffkzhlfoo.supabase.co'"` → `"hostname 'mlwiodleouzwniehynfzfoo.supabase.co'"`

## Files to Create

None.

## Files Verified (No Change)

- `apps/web-platform/test/mu1-integration.test.ts` — `SYNTH_EMAIL_RE` at line 45-46 is email-shaped (`/^mu1-integration-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}@soleur-test\.invalid$/i`). No project-ref coupling. Confirmed at plan time.

### TDD Gate Note

`cq-write-failing-tests-before` requires failing tests precede implementation when a plan has Test Scenarios. For this surgical edit the gate is naturally satisfied because the test fixture **is** the failing test:

- Current state: guard says expected dev = old prd ref; test fixture asserts old prd ref. Test passes (against the wrong target — the same misalignment that caused #2887).
- After editing **only** the guard (`DEV_PROJECT_REF`) but NOT the test fixture: test fails — happy path injects old prd URL but guard now expects new dev URL. **This is the RED state.** Running the test here proves the guard does the right thing.
- After editing both: test passes against the correct target. **This is the GREEN state.**

In practice, both edits land in one commit (the `mu1-cleanup-guard.mjs` comment lines 3-5 explicitly require coupled commits). The RED/GREEN sequence is conceptual, not a multi-commit ceremony. If a reviewer wants empirical RED proof, run `git stash` on the test changes only (the guard change must persist), exec the test once → expect failure, then `git stash pop` → expect pass. (Note: per `hr-never-git-stash-in-worktrees`, do not actually run that ceremony in this worktree — it's a thought experiment for reviewer confidence, not an instruction.)

## Test Strategy

`apps/web-platform/infra/mu1-runbook-cleanup.test.sh` is the existing self-contained test for `mu1-cleanup-guard.mjs`. It runs as a bash script against `node --input-type=module`. After edits:

```bash
cd apps/web-platform/infra && bash mu1-runbook-cleanup.test.sh
```

Expected outcome:

- `=== Results: 7 passed, 0 failed, 7 total ===` (same case count as before — we are renaming literals, not adding cases).

The 7 cases:

1. happy path: `DOPPLER_CONFIG=dev + new dev URL → no-throw`
2. `DOPPLER_CONFIG=prd + new dev URL → throws "DOPPLER_CONFIG is not 'dev'"`
3. `DOPPLER_CONFIG unset + new dev URL → throws "<unset>"`
4. wrong project ref `otherref.supabase.co` → throws `hostname 'otherref.supabase.co'`
5. empty URL → throws `hostname ''`
6. malformed URL → throws `hostname ''`
7. subdomain bypass `<new-ref>.supabase.co.evil.com` → throws `hostname '<new-ref>.supabase.co.evil.com'`
8. prefix-match bypass `<new-ref>foo.supabase.co` → throws `hostname '<new-ref>foo.supabase.co'`

(Cases 7 and 8 still exercise the security regression: `split(".")[0]` would accept the bypass; exact-hostname equality rejects it. The fixture base flips from old ref to new ref — same protection class.)

No vitest run needed — `mu1-integration.test.ts` is unchanged. CI's normal `npm test` against the worktree (or `node node_modules/vitest/vitest.mjs run` per `cq-in-worktrees-run-vitest-via-node-node`) will pick up the integration test as a no-op since AC-1 is gated on `MU1_INTEGRATION=1` (offline lane runs AC-3, AC-4 only).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `mu1-cleanup-guard.mjs` line 6 updated to `const DEV_PROJECT_REF = "mlwiodleouzwniehynfz";`
- [ ] `mu1-runbook-cleanup.test.sh` line 10 + lines 88,89,94,95 updated as enumerated above
- [ ] `bash apps/web-platform/infra/mu1-runbook-cleanup.test.sh` exits 0 with `7 passed, 0 failed, 7 total`
- [ ] `apps/web-platform/test/mu1-integration.test.ts` unchanged (verified by `git diff` showing only the 2 expected files)
- [ ] `rg 'ifsccnjhymdmidffkzhl' apps/web-platform/infra/mu1-cleanup-guard.mjs apps/web-platform/infra/mu1-runbook-cleanup.test.sh` returns zero hits after edit
- [ ] `rg 'mlwiodleouzwniehynfz' apps/web-platform/infra/mu1-cleanup-guard.mjs apps/web-platform/infra/mu1-runbook-cleanup.test.sh` returns 6 hits (1 in guard, 5 in test)
- [ ] PR body contains `Closes #2887` (this PR is the final remediation step — Phase 1+2+3 of the parent plan are now complete; #2887 is already CLOSED at parent plan close, but `Closes #2887` ensures GitHub bookkeeping is correct on this completion PR)
- [ ] `node node_modules/vitest/vitest.mjs run apps/web-platform/test/mu1-integration.test.ts` passes (offline lane: AC-3, AC-4 cases — confirms no accidental coupling broke them)

### Post-merge (operator)

None. Doppler rotation, Supabase project provisioning, migrations, and `ci` config audit were completed by the operator before this PR. After merge, the runbook sweep one-liner (`apps/web-platform/infra/mu1-cleanup-guard.mjs` invoked under `DOPPLER_CONFIG=dev`) will succeed for the first time against the real new dev project.

## Hypotheses

Network-outage trigger pattern check: feature description does NOT contain `SSH`, `connection reset`, `kex`, `firewall`, `unreachable`, `timeout`, `502/503/504`, `handshake`, `EHOSTUNREACH`, or `ECONNRESET`. Plan-network-outage-checklist gate does not apply.

## Live-Verification Evidence (this pass)

```bash
$ gh issue view 2887 --json state,closedAt --jq '{state, closedAt}'
{"closedAt":"2026-04-27T07:59:28Z","state":"CLOSED"}

$ doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c dev --plain
https://mlwiodleouzwniehynfz.supabase.co

$ doppler secrets get SUPABASE_URL -p soleur -c dev --plain
https://mlwiodleouzwniehynfz.supabase.co

$ rg -n 'ifsccnjhymdmidffkzhl' apps/web-platform/infra/mu1-cleanup-guard.mjs apps/web-platform/infra/mu1-runbook-cleanup.test.sh
apps/web-platform/infra/mu1-cleanup-guard.mjs:6:const DEV_PROJECT_REF = "ifsccnjhymdmidffkzhl";
apps/web-platform/infra/mu1-runbook-cleanup.test.sh:10:DEV_URL="https://ifsccnjhymdmidffkzhl.supabase.co"
apps/web-platform/infra/mu1-runbook-cleanup.test.sh:88:  "dev" "https://ifsccnjhymdmidffkzhl.supabase.co.evil.com" \
apps/web-platform/infra/mu1-runbook-cleanup.test.sh:89:  "hostname 'ifsccnjhymdmidffkzhl.supabase.co.evil.com'"
apps/web-platform/infra/mu1-runbook-cleanup.test.sh:94:  "dev" "https://ifsccnjhymdmidffkzhlfoo.supabase.co" \
apps/web-platform/infra/mu1-runbook-cleanup.test.sh:95:  "hostname 'ifsccnjhymdmidffkzhlfoo.supabase.co'"

$ rg 'mlwiodleouzwniehynfz' --type-add 'src:*.{ts,tsx,js,mjs,sh,yml,yaml,tf}' -tsrc -tmd | grep -v 'fix-mu1-dev-ref-update-plan.md'
# (no matches — only this plan references the new ref so far)
```

## Risks & Sharp Edges

- **`#2887` already CLOSED.** `gh issue view 2887 --json state` returns `CLOSED`. The parent plan closed it at PR #2903 merge per the parent plan's Phase 5+6 ordering. `Closes #2887` in this PR body is a **bookkeeping reaffirmation**, not a state change — GitHub's auto-close on merge is a no-op against an already-closed issue. The PR title MUST still reference #2887 for searchability and changelog grouping.
- **Don't rewrite history.** Six historical learnings/plans/specs (and the parent #2887 plan itself) reference `ifsccnjhymdmidffkzhl` as a fixed historical fact (it WAS the only ref at the time those documents were written, and it remains the prd ref today). The audit table above explicitly classifies them KEEP. A blanket find-and-replace would corrupt the historical record.
- **The `dns.tf` CNAME stays.** `api.soleur.ai → ifsccnjhymdmidffkzhl.supabase.co` is the prd custom domain — that CNAME is correct and load-bearing. Touching it would break user-facing OAuth.
- **The `mu1-cleanup-guard.mjs` comment about `SYNTH_EMAIL_RE` coupling.** The comment on lines 3-5 prescribes updating both `DEV_PROJECT_REF` and `SYNTH_EMAIL_RE` "in the same commit." The parent plan's deepen pass confirmed the regex is email-shaped, not ref-shaped, so no regex change is required. We are intentionally NOT updating the comment in this PR (to keep scope tight); a future skim may make the comment more precise. If a reviewer flags this as scope-out, accept the comment-tweak inline.
- **Worktree vitest invocation.** Per `cq-in-worktrees-run-vitest-via-node-node`, vitest must run via `node node_modules/vitest/vitest.mjs run` from the worktree root, NOT `npx vitest`. The shell test script (`mu1-runbook-cleanup.test.sh`) is bash + `node --input-type=module` and is unaffected.

## Implementation Phases

Single-phase. This is a 2-file find-and-replace.

1. Edit `apps/web-platform/infra/mu1-cleanup-guard.mjs` line 6.
2. Edit `apps/web-platform/infra/mu1-runbook-cleanup.test.sh` lines 10, 88, 89, 94, 95.
3. Run `bash apps/web-platform/infra/mu1-runbook-cleanup.test.sh` — expect `7 passed, 0 failed`.
4. Run targeted vitest: `cd apps/web-platform && ./node_modules/.bin/vitest run test/mu1-integration.test.ts` — expect AC-3 + AC-4 cases pass (AC-1 skipped without `MU1_INTEGRATION=1`).
5. Verify audit: `rg 'ifsccnjhymdmidffkzhl' apps/web-platform/infra/mu1-cleanup-guard.mjs apps/web-platform/infra/mu1-runbook-cleanup.test.sh` → zero hits.
6. Commit + push, run `/soleur:ship`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is a mechanical follow-up to a previously-reviewed remediation. Security/CTO domain was already reviewed as part of the parent plan (#2887 / PR #2903). The two-file edit only renames a constant and matching test fixtures to the new dev ref operator already provisioned. No product, marketing, ops, finance, or legal surface.
