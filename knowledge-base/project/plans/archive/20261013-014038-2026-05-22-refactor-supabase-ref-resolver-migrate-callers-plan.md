---
date: 2026-05-22
type: refactor
issue: 4323
branch: feat-one-shot-4323-supabase-ref-resolver-migrate-callers
lane: cross-domain
requires_cpo_signoff: false
---

# refactor: migrate workflow YAML + Inngest TS callers onto supabase-ref-resolver

Closes #4323. Refs PR #4320 (parent extraction).

## Enhancement Summary

**Deepened on:** 2026-05-22
**Sections enhanced:** Overview, Acceptance Criteria, Files to Edit, Risks, Test Strategy
**Research lenses applied:** node:dns API surface (verified `@types/node` v22.x), vitest config (`unit` project `include` pattern), workflow runner shell semantics (`ubuntu-latest` `dnsutils` availability + `dig` flag-set), tsconfig path alias verification, parity-test isolation pattern (PATH-shimmed fake `dig` per `supabase-ref-resolver.test.sh` T5/T6).

### Key Improvements
1. **Timeout asymmetry surfaced.** Migrating workflow from inline `dig +time=3 +tries=2` (~6s ceiling) to helper's `dig +time=5 +tries=2` (~10s ceiling) relaxes the workflow's DNS wall-clock budget by ~4s. Deliberate trade — added explicit callout under Risks + AC11 verification.
2. **TS resolver error-code shape pinned.** `dnsPromises.resolveCname` throws `NodeJS.ErrnoException` with `err.code === "ENOTFOUND"` on NXDOMAIN (verified against `@types/node` dns.d.ts comment). The TS helper's catch block returns `null` for ALL error codes (ENOTFOUND, ENODATA, ESERVFAIL, network errors) — matching the bash helper's `2>/dev/null` swallow.
3. **Test path resolved against vitest `unit` project.** Per `vitest.config.ts:44` the `unit` project's `include: ["test/**/*.test.ts", "lib/**/*.test.ts"]` matches the planned parity test at `test/lib/supabase/resolve-ref-parity.test.ts`. `environment: "node"` (line 43) supports `child_process.spawnSync` for the bash-side invocation. No vitest config edit needed.
4. **`@/` alias verified.** `tsconfig.json paths: { "@/*": ["./*"] }` resolves `@/lib/supabase/resolve-ref` to `apps/web-platform/lib/supabase/resolve-ref.ts`. Confirmed via `ws-client.ts:4` precedent (`import { createClient } from "@/lib/supabase/client"`).
5. **Workflow source-path verified for repo-root resolution.** The `reusable-release.yml` callers (`web-platform-release.yml`) check out the full tree; `working-directory:` is not set on the validate step, so `. apps/web-platform/scripts/lib/supabase-ref-resolver.sh` resolves correctly from `$GITHUB_WORKSPACE`.

### New Considerations Discovered
- `dnsPromises.resolveCname` returns the **CNAME chain** (array of intermediate targets, not just the final A-record host). The bash helper's `dig +short CNAME ... | head -1` mirrors `cnames[0]` semantically — both pick the **first hop**. The TS helper MUST take `cnames[0]` (not `cnames[cnames.length-1]`) for parity. AC4 parity test asserts this; Risks section calls it out explicitly.
- Per AGENTS.md SE on `dig` flag-pinning: the helper is the single source for timeout/tries; future tuning lives in one place (AC4's parity test catches drift).

## Overview

PR #4320 extracted the canonical bash helper `apps/web-platform/scripts/lib/supabase-ref-resolver.sh` and wired the new `postgrest-reload-schema.sh` caller through it. The two pre-existing inline forms of the same CNAME-resolution shape were deliberately scoped out as the cross-cutting half (review CONCUR-flow split). This plan migrates them:

1. `.github/workflows/reusable-release.yml:483-496` — workflow YAML inline `sed -E 's#^https://##; s#/.*$##'` form for the URL-vs-JWT-ref cross-check on prod builds.
2. `apps/web-platform/server/inngest/functions/cron-oauth-probe.ts:280-289` — TypeScript `resolveSupabaseRefFromCname` for the SUPABASE_PROJECT_REF drift probe.

Both sites duplicate the security-critical subdomain-bypass regex `^[a-z0-9]{20}\.supabase\.co$`. A future widening of the canonical (e.g., to `^[a-z0-9]{20,21}\.supabase\.(co|io)$` for preview envs) would update the bash lib + script but silently leave the workflow YAML and TS function drifting against the stale regex.

The migration introduces a TypeScript sibling helper at `apps/web-platform/lib/supabase/resolve-ref.ts` and consumes the existing bash helper from the workflow via `source` in a `run:` block (same shape as `scheduled-ruleset-bypass-audit.yml:235` for `strip-log-injection.sh`). A parity test asserts bash and TS implementations produce the same ref across the existing fixtures.

## User-Brand Impact

**If this lands broken, the user experiences:** the `Validate NEXT_PUBLIC_SUPABASE_ANON_KEY build-arg` step in `reusable-release.yml` fails on prd builds (custom domain `api.soleur.ai`), blocking releases; OR the OAuth probe cron emits false `supabase_project_ref_drift` alerts (resolver mismatch between bash and TS implementations).

**If this leaks, the user's data is exposed via:** N/A — this is a pure refactor of an existing security gate. The gate's behavior is preserved by the parity test; no new data path is introduced.

**Brand-survival threshold:** none — this is a refactor of an existing security-critical regex. The subdomain-bypass guard `^[a-z0-9]{20}\.supabase\.co$` is preserved verbatim in both the bash and TS implementations. The refactor reduces drift risk (single-source the regex) without changing the gate's contract.

**Threshold: `none`, reason:** This refactor touches `.github/workflows/`, `apps/web-platform/server/`, and `apps/web-platform/lib/supabase/` (all sensitive paths per preflight Check 6 regex), but the behavior change is zero — both new consumers produce the same ref the existing inline forms produce, on the same regex, with the same subdomain-bypass guard. The parity test is the single-source contract. Per `2026-05-21-worm-ledger-rls-owner-insert-policy-is-an-rpc-bypass.md` SE#3 (API surface claims), the parity assertion is a verifiable artifact, not a prose mitigation.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1.** `.github/workflows/reusable-release.yml` step `Validate NEXT_PUBLIC_SUPABASE_ANON_KEY build-arg` consumes the canonical bash helper via `. apps/web-platform/scripts/lib/supabase-ref-resolver.sh` in a `run:` block. The inline `sed -E 's#^https://##; s#/.*$##'` + `dig +short CNAME` block (lines 483-496) is deleted. Verify: `grep -nE 'sed -E .s#\^https://##' .github/workflows/reusable-release.yml` returns 0 matches.
- [ ] **AC2.** `apps/web-platform/lib/supabase/resolve-ref.ts` exists and exports an `async function resolveSupabaseRef(url: string): Promise<string | null>` whose semantics mirror `resolve_supabase_ref` in the bash helper. The TS function uses `node:dns` `promises.resolveCname` for the CNAME fallback (matches the existing `resolveSupabaseRefFromCname` import shape). Verify: `grep -n 'export async function resolveSupabaseRef' apps/web-platform/lib/supabase/resolve-ref.ts` returns 1 match.
- [ ] **AC3.** `apps/web-platform/server/inngest/functions/cron-oauth-probe.ts` deletes the local `resolveSupabaseRefFromCname` (lines 280-289) and imports `resolveSupabaseRef` from `@/lib/supabase/resolve-ref`. The call site at line 351 (`const cnameRef = (await resolveSupabaseRefFromCname(apiHost)) ?? supabaseProjectRef`) is updated to pass the full URL (e.g., `https://${apiHost}`) so the TS helper sees the same input shape as the bash helper. Verify: `grep -n 'resolveSupabaseRefFromCname' apps/web-platform/server/inngest/functions/cron-oauth-probe.ts` returns 0 matches.
- [ ] **AC4.** New test file `apps/web-platform/test/lib/supabase/resolve-ref-parity.test.ts` asserts the bash and TS implementations produce the **same ref** for the same input across these fixtures: (a) canonical `https://abcdefghijklmnopqrst.supabase.co` → ref, (b) trailing-slash form, (c) custom-domain (`https://api.example.com`) via mocked CNAME target `abcdefghijklmnopqrst.supabase.co.`, (d) subdomain-bypass attempt CNAME `abcdefghijklmnopqrst.supabase.co.evil.com.` → null/rejected, (e) uppercase host → null/rejected, (f) empty string → null/rejected. The bash impl is invoked via `child_process.spawnSync("bash", ["-c", "source apps/web-platform/scripts/lib/supabase-ref-resolver.sh; resolve_supabase_ref $1", "--", url], { env: { PATH: shimPath + ":" + process.env.PATH } })` with a PATH-shimmed fake `dig` mirroring the existing `supabase-ref-resolver.test.sh` T5/T6 shape. Verify: `vitest run apps/web-platform/test/lib/supabase/resolve-ref-parity.test.ts` exits 0 and the test count is ≥ 6.
- [ ] **AC5.** `apps/web-platform/scripts/lib/supabase-ref-resolver.test.sh` continues to pass 7/7 unchanged (the bash helper is not modified by this PR). Verify: `bash apps/web-platform/scripts/lib/supabase-ref-resolver.test.sh` exits 0.
- [ ] **AC6.** `cron-oauth-probe.test.ts` continues to pass — update the mock from `vi.mock("node:dns", ...)` to a `vi.mock("@/lib/supabase/resolve-ref", () => ({ resolveSupabaseRef: vi.fn(...) }))` returning the canonical ref `ifsccnjhymdmidffkzhl` for the happy-path, and `null` for drift cases. Verify: `vitest run apps/web-platform/test/server/inngest/cron-oauth-probe.test.ts` exits 0.
- [ ] **AC7.** Preflight Check 4 prose pointer updated. `plugins/soleur/skills/preflight/SKILL.md` Step 4.2 — replace the inline regex/strip/`dig` recipe with a one-line reference: "See the canonical resolver at `apps/web-platform/scripts/lib/supabase-ref-resolver.sh` (`resolve_supabase_ref`). The same shape is mirrored in `apps/web-platform/lib/supabase/resolve-ref.ts` for TS callers and consumed by `.github/workflows/reusable-release.yml` via `source`." The 3 sub-bullets (rc semantics, A-record fallback, subdomain-bypass guard) remain — they describe Check 4's wrapper semantics on top of the resolver, not the resolver itself. Verify: `grep -n 'apps/web-platform/scripts/lib/supabase-ref-resolver.sh' plugins/soleur/skills/preflight/SKILL.md` returns ≥ 1 match.
- [ ] **AC8.** TypeScript build passes: `cd apps/web-platform && bun tsc --noEmit` exits 0.
- [ ] **AC9.** Cross-consumer grep verifies no other inline duplicates linger. Verify: `git grep -nE '\^\[a-z0-9\]\{20\}\\?\.supabase\\?\.co\\?\$' -- ':!apps/web-platform/scripts/lib/supabase-ref-resolver.sh' ':!apps/web-platform/scripts/lib/supabase-ref-resolver.test.sh' ':!apps/web-platform/lib/supabase/resolve-ref.ts' ':!apps/web-platform/test/lib/supabase/resolve-ref-parity.test.ts' ':!plugins/soleur/skills/preflight/SKILL.md' ':!apps/web-platform/lib/supabase/validate-url.ts' ':!apps/web-platform/lib/supabase/validate-anon-key.ts' ':!apps/web-platform/scripts/verify-required-secrets.sh' ':!knowledge-base/' ':!.github/workflows/reusable-release.yml'` returns 0 matches. (The `validate-url.ts` + `validate-anon-key.ts` + `verify-required-secrets.sh` URL-shape guards are intentional siblings — they enforce the canonical URL shape on a different surface and are out of scope per #4323's Acceptance list. Workflow YAML retains the canonical-shape regex `^https://([a-z0-9]{20}\.supabase\.co|api\.soleur\.ai)$` at line 411 — that's the URL build-arg validator, not the JWT-ref derivation; only the ref-derivation `sed`/`dig` block at lines 483-496 is migrated.)
- [ ] **AC10.** PR body cites: `Closes #4323`. Refs `PR #4320` (parent extraction).
- [ ] **AC11.** DNS wall-clock budget delta documented. The migration changes the workflow's DNS timeout from inline `dig +time=3 +tries=2` (~6s ceiling) to the helper's `dig +time=5 +tries=2` (~10s ceiling). This is a deliberate trade — the helper is the single source of truth, and tuning lives in one place. Verify: `grep -nE 'dig.*time=' apps/web-platform/scripts/lib/supabase-ref-resolver.sh` returns exactly `+time=5 +tries=2`; `grep -nE 'dig.*time=' .github/workflows/reusable-release.yml` returns 0 matches (the inline form is gone). Per AGENTS.md SE (`When a plan prescribes 'dig', 'nslookup', 'curl', or any network call inside a CI step, pin a timeout`), the helper's timeout pin is preserved.

### Research Insights

**API surface (verified at deepen-time):**

- `node:dns` `promises.resolveCname(hostname)` returns `Promise<string[]>` — array of CNAME chain hops. On NXDOMAIN throws `NodeJS.ErrnoException` with `err.code === "ENOTFOUND"` (verified at `apps/web-platform/node_modules/@types/node/dns.d.ts` `resolveCname` JSDoc). The TS helper's try/catch returning `null` covers ENOTFOUND + ENODATA + ESERVFAIL + network errors uniformly — matches the bash helper's `dig ... 2>/dev/null` swallow.
- `node:child_process` `spawnSync` is available in `environment: "node"` (vitest `unit` project, `vitest.config.ts:43`). The parity test uses `spawnSync` (NOT `exec`) — args are passed as an array, no shell-interpretation of the URL fixture. No vitest config edit needed.
- The bash-side invocation in the parity test passes the URL as `argv[1]` to a bash `-c` invocation that does `resolve_supabase_ref "$1"` — the URL never enters shell-expansion context.

**TS helper sketch (Phase 1):**

```typescript
// apps/web-platform/lib/supabase/resolve-ref.ts
import { promises as dnsPromises } from "node:dns";

const CANONICAL_URL_RE = /^https?:\/\/([a-z0-9]{20})\.supabase\.co\/?$/;
const CANONICAL_HOST_RE = /^([a-z0-9]{20})\.supabase\.co$/;

/**
 * Mirrors apps/web-platform/scripts/lib/supabase-ref-resolver.sh
 * (resolve_supabase_ref). Returns the 20-char project ref, or null on
 * any failure (empty input, non-canonical host, NXDOMAIN, subdomain-bypass
 * attempt). Security-critical regex `^[a-z0-9]{20}\.supabase\.co$` MUST stay
 * in sync with the bash form — parity asserted by
 * test/lib/supabase/resolve-ref-parity.test.ts.
 */
export async function resolveSupabaseRef(url: string): Promise<string | null> {
  if (!url) return null;
  const fast = CANONICAL_URL_RE.exec(url);
  if (fast) return fast[1] ?? null;

  // Custom-domain fallback: strip protocol + path, CNAME-resolve, validate.
  let host = url.replace(/^https?:\/\//, "");
  host = host.split("/")[0] ?? "";
  if (!host) return null;

  let cnames: string[];
  try {
    cnames = await dnsPromises.resolveCname(host);
  } catch {
    return null;
  }
  const first = cnames[0];
  if (!first) return null;
  const stripped = first.replace(/\.$/, "");
  const match = CANONICAL_HOST_RE.exec(stripped);
  return match?.[1] ?? null;
}
```

**Workflow `run:` block sketch (Phase 3):**

The replacement block at `.github/workflows/reusable-release.yml` lines 483-496:

```bash
# Resolve expected_ref via canonical helper (single source for the
# subdomain-bypass anchored regex + DNS timeout). dig timeout widens
# from +time=3 to +time=5 (helper-pinned) — see AC11.
# shellcheck source=apps/web-platform/scripts/lib/supabase-ref-resolver.sh
. apps/web-platform/scripts/lib/supabase-ref-resolver.sh
if ! expected_ref=$(resolve_supabase_ref "$SUPABASE_URL" 2>&1); then
  expected_ref_safe="${expected_ref//[$'\n\r']/}"
  echo "::error::${expected_ref_safe}"
  exit 1
fi
```

Strict-mode safety: the `if !` guard suppresses the `set -e` auto-exit so the diagnostic on stderr can be captured into `expected_ref` and logged via `::error::` annotation with CR/LF strip. Mirrors `postgrest-reload-schema.sh:103-105`.

**References:**

- `apps/web-platform/scripts/lib/supabase-ref-resolver.sh` (canonical bash form, PR #4320).
- `apps/web-platform/scripts/lib/supabase-ref-resolver.test.sh` (7-case bash test, T1-T7).
- `apps/web-platform/scripts/postgrest-reload-schema.sh:99-105` (existing bash consumer pattern).
- `.github/workflows/scheduled-ruleset-bypass-audit.yml:234-235` (precedent for `source <repo-rel>.sh` from workflow `run:` block).
- `apps/web-platform/node_modules/@types/node/dns.d.ts` (verified `resolveCname` signature + error semantics).
- `apps/web-platform/vitest.config.ts:40-54` (`unit` project `include` pattern + `environment: "node"`).
- `apps/web-platform/tsconfig.json` (verified `@/*` path alias).

### Post-merge (operator)

(None — this is a code-only refactor. The workflow `reusable-release.yml` fires on the next push to `main` and validates itself via the existing `Validate NEXT_PUBLIC_SUPABASE_ANON_KEY build-arg` step on that build. The inngest cron `cron-oauth-probe` runs on its existing schedule; first post-merge fire validates the TS migration end-to-end via the production CNAME against `api.soleur.ai`.)

## Files to Edit

- `.github/workflows/reusable-release.yml` — replace inline `sed`/`dig` block (lines 483-496) with `source apps/web-platform/scripts/lib/supabase-ref-resolver.sh; expected_ref=$(resolve_supabase_ref "$SUPABASE_URL")`. Keep CR/LF strip + `cname_safe`/`host_safe` sanitization on the failure path. Sparse-checkout note: the `web-platform-release.yml` caller already does `actions/checkout@v4` (line 73 of reusable-release.yml — top of job), so the script path is available on the runner; no checkout change needed.
- `apps/web-platform/server/inngest/functions/cron-oauth-probe.ts` — delete `resolveSupabaseRefFromCname` (lines 280-289) and its `node:dns` `promises` import (line 32 — only this caller uses it; verify with grep). Import `resolveSupabaseRef` from `@/lib/supabase/resolve-ref`. Update line 351 call: `const cnameRef = (await resolveSupabaseRef(`https://${apiHost}`)) ?? supabaseProjectRef;`.
- `apps/web-platform/test/server/inngest/cron-oauth-probe.test.ts` — replace `vi.mock("node:dns", ...)` (lines 23-29) with `vi.mock("@/lib/supabase/resolve-ref", () => ({ resolveSupabaseRef: vi.fn(async () => "ifsccnjhymdmidffkzhl") }))`. The `resolveCnameSpy` references in the test body (search for `resolveCnameSpy`) need to be renamed to `resolveSupabaseRefSpy` and their return shape changed from `["ifsccnjhymdmidffkzhl.supabase.co."]` (CNAME array) to `"ifsccnjhymdmidffkzhl"` (bare ref).
- `plugins/soleur/skills/preflight/SKILL.md` — Check 4 Step 4.2 prose update per AC7.

## Files to Create

- `apps/web-platform/lib/supabase/resolve-ref.ts` — TS sibling helper. Mirrors the bash helper's two-phase resolution (fast-path canonical regex, then CNAME fallback through `node:dns` `promises.resolveCname` with subdomain-bypass anchored regex). Returns `string | null` (no exceptions — the workflow's bash form uses rc; the TS form uses null so the existing `?? supabaseProjectRef` fallback pattern in `cron-oauth-probe.ts` line 351 continues to work).
- `apps/web-platform/test/lib/supabase/resolve-ref-parity.test.ts` — vitest parity test asserting bash + TS produce the same ref across the 6 fixtures listed in AC4. Uses `child_process.spawnSync` for the bash invocation with PATH-shimmed fake `dig`, mirroring the existing `supabase-ref-resolver.test.sh` T5/T6 mocking shape.

## Research Reconciliation — Spec vs. Codebase

| Spec/Issue claim | Codebase reality | Plan response |
| --- | --- | --- |
| Issue cites `cron-oauth-probe.ts:277` as the `resolveCname` function location | Actual location is `cron-oauth-probe.ts:280-289` (function name is `resolveSupabaseRefFromCname`, not `resolveCname`). The "277" cited in the issue is the comment header line above the function | Plan uses correct line range (280-289). Function name in the issue body is paraphrased; the actual TS identifier is preserved in the deletion sweep. |
| Issue cites `reusable-release.yml:483-496` as the workflow inline form | Verified at lines 483-496 in the current `feat-one-shot-4323-...` worktree (canonical-host regex line 411 is a separate URL-shape gate, not migrated) | Plan correctly scopes the migration to lines 483-496. Line 411's URL-shape regex `^https://([a-z0-9]{20}\.supabase\.co|api\.soleur\.ai)$` is a different validator (build-arg shape, not ref-derivation) and is explicitly excluded from AC9's cross-consumer grep. |
| AC suggests new file at `apps/web-platform/lib/supabase/resolve-ref.ts` | `apps/web-platform/lib/supabase/` exists with sibling validators (`validate-url.ts`, `validate-anon-key.ts`, `client.ts`, `server.ts`, `service.ts`, `tenant.ts`). Tests live at `apps/web-platform/test/lib/supabase/` (e.g., `anon-key-prod-guard.test.ts`) | Plan creates `resolve-ref.ts` alongside the existing validators; parity test lands at `test/lib/supabase/resolve-ref-parity.test.ts` matching the sibling convention. |
| AC4 calls for "parity test ... across the existing fixtures" | The bash test `supabase-ref-resolver.test.sh` has 7 cases (T1-T7): canonical, trailing-slash, empty, non-supabase, custom-domain, subdomain-bypass, uppercase | Plan enumerates 6 parity cases in AC4 (canonical, trailing-slash, custom-domain, subdomain-bypass, uppercase, empty). T4 (non-supabase, no CNAME match) collapses to the same expected output as the custom-domain miss (null/rejected), so 6 is sufficient. |

## Open Code-Review Overlap

Queried open `code-review` issues for paths the plan touches:

- `apps/web-platform/server/inngest/functions/cron-oauth-probe.ts` — 0 matches.
- `.github/workflows/reusable-release.yml` — 0 matches.
- `apps/web-platform/lib/supabase/` — #2963 (Supabase typegen for ConversationPatch). **Acknowledge** — unrelated concern (typegen for conversation patches vs. ref resolver migration); does not affect this PR's scope.
- `plugins/soleur/skills/preflight/SKILL.md` — 0 matches.

**Disposition:** No fold-in needed. The single match (#2963) is in a sibling file class but unrelated semantically.

## Infrastructure (IaC)

N/A — pure code refactor. No new resources, no new vendor accounts, no secrets, no DNS records, no terraform changes.

## Observability

```yaml
liveness_signal:
  what: cron-oauth-probe `step.run("probe-oauth", ...)` returning `failureMode: "supabase_project_ref_drift"` or empty
  cadence: every 15 minutes (existing inngest cron schedule, unchanged by this PR)
  alert_target: Sentry monitor slug `scheduled-oauth-probe` (existing) + tracking issue filed via mocked Octokit on failure (existing)
  configured_in: apps/web-platform/server/inngest/functions/cron-oauth-probe.ts (existing schedule; unchanged)

error_reporting:
  destination: Sentry (existing `reportSilentFallback` + `Sentry.captureException` in `cron-oauth-probe.ts`)
  fail_loud: yes — `failureMode: "supabase_project_ref_drift"` returns a non-empty failure_mode that triggers the issue-filing branch (existing GHA-equivalent first-failure-wins semantics preserved)

failure_modes:
  - mode: TS resolver rejects a CNAME that the bash resolver accepts (or vice versa)
    detection: AC4 parity test fails locally before PR opens; CI vitest run blocks merge
    alert_route: vitest exit code → CI status check on PR
  - mode: workflow `source` fails because `apps/web-platform/scripts/lib/supabase-ref-resolver.sh` is missing from the runner checkout
    detection: `reusable-release.yml` step exits non-zero on the first prd build after merge; release blocks
    alert_route: GHA status → `web-platform-release.yml` job failure → operator sees red check on main
  - mode: drift between bash regex and TS regex (e.g., future widening to `^[a-z0-9]{20,21}\.supabase\.(co|io)$` updates only one side)
    detection: AC4 parity test catches the next time a fixture is added; AC9 cross-consumer grep catches at preflight
    alert_route: vitest CI failure + preflight Check 4 prose pointer routes operator to single-source location

logs:
  where: GHA workflow logs (existing); Inngest function logs (existing); local vitest output during dev
  retention: GHA logs 90 days (default); Inngest logs per inngest plan; vitest local-only

discoverability_test:
  command: bash apps/web-platform/scripts/lib/supabase-ref-resolver.test.sh && cd apps/web-platform && bun vitest run test/lib/supabase/resolve-ref-parity.test.ts test/server/inngest/cron-oauth-probe.test.ts
  expected_output: "Results: 7 passed, 0 failed" from bash; "Test Files 2 passed (2)" from vitest with all parity cases green
```

## Domain Review

**Domains relevant:** Engineering (security-critical regex single-sourcing)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Single-sourcing a security-critical anchored regex across bash and TS reduces drift risk. The parity test is the canonical contract enforcement. Recommended pattern: TS helper returns `string | null` (matches existing `??` fallback at cron-oauth-probe.ts:351); bash helper's rc-on-failure shape stays unchanged. Workflow `source` pattern is already proven (`scheduled-ruleset-bypass-audit.yml:235` sources `strip-log-injection.sh`).

## Implementation Phases

### Phase 0: Preconditions

1. Verify the bash helper exists at `apps/web-platform/scripts/lib/supabase-ref-resolver.sh` and tests pass: `bash apps/web-platform/scripts/lib/supabase-ref-resolver.test.sh` → 7/7 pass.
2. Verify `apps/web-platform/scripts/lib/supabase-ref-resolver.sh` is checked into the `web-platform-release.yml`/`reusable-release.yml` runner checkout (it is — `apps/**` is included; the workflow's checkout at line 73 is full-tree). Grep: `grep -A2 'actions/checkout' .github/workflows/reusable-release.yml | head -5` — confirm no `sparse-checkout:` clause excludes `apps/web-platform/scripts/lib/`.
3. Verify TS test runner is vitest: `grep -nE '"(test|test:ci)":' apps/web-platform/package.json` → confirms `"test": "vitest"` and `"test:ci": "vitest run"`.
4. Verify the `node:dns` `promises.resolveCname` API surface against the installed version: `grep -n 'resolveCname' apps/web-platform/node_modules/@types/node/dns.d.ts | head -5` — confirm shape `(hostname: string) => Promise<string[]>`. The TS helper inherits this contract.
5. Verify `child_process.spawnSync` is usable from vitest (no sandbox restriction): existing tests do this — `grep -rn 'spawnSync\|spawn(' apps/web-platform/test/ | head -5`.

### Phase 1: TS helper + parity test (RED)

1. Write `apps/web-platform/lib/supabase/resolve-ref.ts` exporting `async function resolveSupabaseRef(url: string): Promise<string | null>`. Mirror the bash helper's logic:
   - Fast path: regex `^https?:\/\/([a-z0-9]{20})\.supabase\.co\/?$` extract via `.match()`. Return `match[1]` if matched.
   - Custom-domain fallback: strip protocol + trailing path → host. Call `dnsPromises.resolveCname(host)` (wrap in try/catch returning `null`). Take first CNAME, strip trailing `.`. Apply subdomain-bypass anchored regex `^[a-z0-9]{20}\.supabase\.co$`. Extract first label if matched.
   - Empty URL → return `null` (the bash form rcs 1 with a diagnostic; TS form returns null so the existing `?? supabaseProjectRef` fallback pattern works).
2. Write `apps/web-platform/test/lib/supabase/resolve-ref-parity.test.ts` with 6 parity cases per AC4. For each case, invoke both:
   - TS: `await resolveSupabaseRef(url)` with `vi.mock("node:dns", ...)` providing the CNAME fixture per case.
   - Bash: `spawnSync("bash", ["-c", "source apps/web-platform/scripts/lib/supabase-ref-resolver.sh; resolve_supabase_ref \"$1\"", "--", url], { env: { PATH: shimPath + ":" + process.env.PATH } })`. Capture stdout, trim. For cases that need a CNAME mock, write a fake `dig` to a tempdir and prepend that dir to PATH (same shape as `supabase-ref-resolver.test.sh` T5/T6).
   - Assert: TS result === bash result (both null/empty for rejection cases, both equal to the 20-char ref for acceptance cases).
3. Run `vitest run test/lib/supabase/resolve-ref-parity.test.ts` → confirm green.

### Phase 2: Migrate cron-oauth-probe.ts (GREEN)

1. Edit `apps/web-platform/server/inngest/functions/cron-oauth-probe.ts`:
   - Delete `resolveSupabaseRefFromCname` function (lines 280-289).
   - Delete `import { promises as dnsPromises } from "node:dns";` (line 32) — verify no other usage in the file via `grep -n 'dnsPromises' cron-oauth-probe.ts` returns 0 after the function delete.
   - Add `import { resolveSupabaseRef } from "@/lib/supabase/resolve-ref";`.
   - Update line 351: `const cnameRef = (await resolveSupabaseRef(\`https://${apiHost}\`)) ?? supabaseProjectRef;`.
2. Update `apps/web-platform/test/server/inngest/cron-oauth-probe.test.ts`:
   - Replace the `vi.mock("node:dns", ...)` block (lines 23-29) with `vi.mock("@/lib/supabase/resolve-ref", () => ({ resolveSupabaseRef: vi.fn(async (_url: string) => "ifsccnjhymdmidffkzhl") }))`.
   - Rename `resolveCnameSpy` references to `resolveSupabaseRefSpy` and update spy return shape (bare ref string, not CNAME array).
   - Update drift test cases: where the test set `resolveCnameSpy.mockResolvedValueOnce(["other.supabase.co."])`, replace with `resolveSupabaseRefSpy.mockResolvedValueOnce("other")`.
3. Run `vitest run test/server/inngest/cron-oauth-probe.test.ts` → confirm green.
4. Run `bun tsc --noEmit` → confirm green.

### Phase 3: Migrate reusable-release.yml workflow (GREEN)

1. Edit `.github/workflows/reusable-release.yml` step `Validate NEXT_PUBLIC_SUPABASE_ANON_KEY build-arg`:
   - Replace the inline block at lines 483-496:

     ```bash
     # Before:
     host=$(printf '%s' "$SUPABASE_URL" | sed -E 's#^https://##; s#/.*$##')
     if [[ "$host" =~ ^[a-z0-9]{20}\.supabase\.co$ ]]; then
       expected_ref="${host%%.*}"
     else
       cname=$(dig +short +time=3 +tries=2 CNAME "$host" | sed 's/\.$//' | head -1)
       if [[ "$cname" =~ ^([a-z0-9]{20})\.supabase\.co$ ]]; then
         expected_ref="${BASH_REMATCH[1]}"
       else
         cname_safe="${cname//[$'\n\r']/}"
         host_safe="${host//[$'\n\r']/}"
         echo "::error::Cannot resolve canonical ref from URL host $host_safe (CNAME=$cname_safe)"
         exit 1
       fi
     fi

     # After:
     # shellcheck source=apps/web-platform/scripts/lib/supabase-ref-resolver.sh
     . apps/web-platform/scripts/lib/supabase-ref-resolver.sh
     if ! expected_ref=$(resolve_supabase_ref "$SUPABASE_URL" 2>&1); then
       expected_ref_safe="${expected_ref//[$'\n\r']/}"
       echo "::error::${expected_ref_safe}"
       exit 1
     fi
     ```

2. Run `actionlint .github/workflows/reusable-release.yml` → confirm no errors.

### Phase 4: Update preflight Check 4 prose pointer (DOCS)

1. Edit `plugins/soleur/skills/preflight/SKILL.md` Step 4.2 per AC7. Add a one-line pointer sentence near the top of Step 4.2 referencing the canonical resolver path. Keep the rc/A-record-fallback/subdomain-bypass-guard sub-bullets — they describe Check 4's wrapper semantics on top of the resolver (e.g., "FAIL on A-record-only routing" is not in the resolver; it's a Check-4 policy on the resolver's output).

### Phase 5: Cross-consumer grep + final verification

1. Run AC9's negative grep (no inline regex duplicates outside the canonical sources).
2. Run all test suites:
   - `bash apps/web-platform/scripts/lib/supabase-ref-resolver.test.sh` → 7/7 pass.
   - `cd apps/web-platform && bun vitest run test/lib/supabase/resolve-ref-parity.test.ts` → 6/6 pass.
   - `bun vitest run test/server/inngest/cron-oauth-probe.test.ts` → all pass.
   - `bun tsc --noEmit` → clean.
   - `actionlint .github/workflows/reusable-release.yml` → clean.
3. Update PR body with `Closes #4323` and `Refs PR #4320`.

## Risks

- **Workflow `source` path resolution.** The bash `source` form `. apps/web-platform/scripts/lib/supabase-ref-resolver.sh` resolves relative to the workflow's `working-directory` (default: `${{ github.workspace }}`). If a future change adds a `working-directory:` override to this step or job, the source path breaks silently. Mitigation: the path is repo-root-relative, matching `scheduled-ruleset-bypass-audit.yml:235`'s precedent (`. scripts/lib/strip-log-injection.sh` works there because that workflow also runs from repo root).
- **TS resolver returns null vs. bash exits non-zero.** The bash helper rcs 1 on failure with a diagnostic on stderr; the TS helper returns null. The two callers handle this differently: workflow uses the bash rc semantics; `cron-oauth-probe.ts` uses the `??` fallback to `supabaseProjectRef` (preserved). AC4's parity test treats both null-from-TS and rc=1-from-bash as "rejection" for fairness — neither emits a positive ref.
- **`node:dns` `promises.resolveCname` exception shape.** On NXDOMAIN, `resolveCname` rejects with a `NodeJS.ErrnoException` (`code: "ENOTFOUND"`). The TS helper wraps in try/catch returning null — verified against `node_modules/@types/node/dns.d.ts` in Phase 0 step 4.
- **Cross-PR cap coupling** (per `2026-05-06-cap-coupling-between-adjacent-prs.md`): the regex `^[a-z0-9]{20}\.supabase\.co$` is ALSO inlined in `apps/web-platform/lib/supabase/validate-url.ts:20`, `validate-anon-key.ts`, and `apps/web-platform/scripts/verify-required-secrets.sh` (`SUPABASE_URL_RE`). These are intentional sibling shape-validators (different concern: URL build-arg shape vs. ref derivation) and are explicitly excluded from AC9's grep. A future PR widening the canonical (e.g., `.io` support) would need to touch the resolver + all four shape validators — flag this in the resolver's header comment.
- **DNS timeout widening (CI wall-clock).** Migrating the workflow from inline `dig +time=3 +tries=2` (~6s max) to the helper's `dig +time=5 +tries=2` (~10s max) widens the worst-case wall-clock budget on the `Validate NEXT_PUBLIC_SUPABASE_ANON_KEY build-arg` step by ~4s. The trade is: single-source the timeout tuning (helper-pinned) vs. CI step duration. Justification: this step runs ONCE per release build (not per-PR); 4s on a build is well within the workflow's existing budget. Documented in AC11 + Enhancement Summary.
- **Parity test working directory.** vitest runs from `apps/web-platform/` (its `package.json` dir). The parity test's bash invocation uses a relative path `scripts/lib/supabase-ref-resolver.sh`, resolved from `process.cwd()`. If a future vitest config edit changes the working directory (unlikely — no current `cwd:` override exists), the parity test breaks at the bash `source` call. Mitigation: the test can hardcode the path via `path.resolve(__dirname, "../../../scripts/lib/supabase-ref-resolver.sh")` if relative-path resolution becomes fragile.
- **vitest mock hoisting for `node:dns`.** The parity test mocks `node:dns` for the TS-side fixtures. Because the bash invocation runs in a child process via `spawnSync`, the mock does NOT leak across to bash — bash sees the real shell environment with the PATH-shimmed fake `dig`. The two sides are cleanly isolated. Confirmed pattern with `cron-oauth-probe.test.ts:27` (which also mocks `node:dns` for the same module).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's threshold is `none` with an explicit reason citing the sensitive-path overlap and the parity-test mitigation per `2026-05-21-worm-ledger-rls-owner-insert-policy-is-an-rpc-bypass.md` SE#3.
- `.github/workflows/reusable-release.yml` is a reusable workflow; its caller chain is `web-platform-release.yml` → `reusable-release.yml`. Verify any concurrent edits to the caller don't restrict the `apps/web-platform/scripts/` checkout path.
- The TS helper's `node:dns` `promises.resolveCname` API differs from `dig +short CNAME` in one subtle way: `resolveCname` returns an array of CNAME targets (the chain), while `dig +short CNAME ... | head -1` returns only the first hop. The bash helper's `head -1` mirrors `cnames[0]` in the TS helper; the parity test asserts this equivalence.
- Per `2026-05-15-plan-time-grep-all-agent-invocation-surfaces-not-just-named-entry-point.md`, the `cron-oauth-probe.ts:resolveSupabaseRefFromCname` function has exactly one call site (line 351). Grep verification at Phase 0 step 4b: `grep -n 'resolveSupabaseRefFromCname' apps/web-platform/server/inngest/functions/cron-oauth-probe.ts` returns 2 matches (definition + call). After Phase 2 delete, both go to zero.
- Per `cq-union-widening-grep-three-patterns` — the canonical regex is NOT a union; the future widening to `^[a-z0-9]{20,21}\.supabase\.(co|io)$` (mentioned in the issue body) is a separate plan, not this one. Out of scope.
- Workflow `source` from a `run:` block: bash `set -euo pipefail` and `set +e` interactions. The new form `if ! expected_ref=$(resolve_supabase_ref "$SUPABASE_URL" 2>&1); then` captures both stdout and stderr into `expected_ref`; on failure, `expected_ref` contains the diagnostic message. The `set -e` `if` guard suppresses the auto-exit. This matches the `postgrest-reload-schema.sh:103` precedent (`if ! project_ref=$(resolve_supabase_ref ...); then fail_or_skip 2 "$project_ref"; fi`).

## Test Strategy

- **Unit (TS):** `vitest run test/lib/supabase/resolve-ref-parity.test.ts` — 6 parity fixtures (vitest `unit` project, `environment: "node"`, matches the project's `include: ["test/**/*.test.ts", "lib/**/*.test.ts"]` pattern).
- **Unit (bash):** existing `supabase-ref-resolver.test.sh` unchanged — 7/7 pass.
- **Integration (TS):** existing `cron-oauth-probe.test.ts` updated to mock `@/lib/supabase/resolve-ref` instead of `node:dns`. All existing scenarios continue to pass.
- **Type check:** `bun tsc --noEmit` on `apps/web-platform`.
- **Workflow lint:** `actionlint .github/workflows/reusable-release.yml`.
- **Shell lint:** `shellcheck` on the modified workflow snippet (extract the `run:` block content and run inline). Note: shellcheck's `source` directive (`# shellcheck source=apps/web-platform/scripts/lib/supabase-ref-resolver.sh`) requires the path be resolvable from the script's location; mirror the form at `scheduled-ruleset-bypass-audit.yml:234` precedent.
- **Parity-test isolation:** the test mocks `node:dns` for the TS-side fixtures, AND uses a PATH-shimmed fake `dig` for the bash-side child-process invocation. The two mocking surfaces never collide because the bash invocation runs in a separate process via `spawnSync` — confirmed pattern in `supabase-ref-resolver.test.sh` T5/T6.

## Skill Description Budget

N/A — no SKILL.md `description:` field edits in this plan. The only SKILL.md edit (preflight Check 4 prose) is in the body, not the description.

## References

- Parent PR #4320 (extracted the bash helper).
- Issue #4323 (this issue — the cross-cutting half).
- `apps/web-platform/scripts/lib/supabase-ref-resolver.sh` (canonical bash form).
- `apps/web-platform/scripts/lib/supabase-ref-resolver.test.sh` (existing bash tests, 7 cases).
- `apps/web-platform/scripts/postgrest-reload-schema.sh:99-105` (existing bash caller — pattern to copy for the workflow).
- `.github/workflows/scheduled-ruleset-bypass-audit.yml:234-235` (existing `source <repo-rel>.sh` from `run:` block pattern).
- `plugins/soleur/skills/preflight/SKILL.md` Check 4 Step 4.2 (documented shape pointer to update).
