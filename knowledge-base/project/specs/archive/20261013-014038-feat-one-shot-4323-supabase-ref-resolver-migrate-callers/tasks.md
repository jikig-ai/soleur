---
date: 2026-05-22
plan: knowledge-base/project/plans/2026-05-22-refactor-supabase-ref-resolver-migrate-callers-plan.md
issue: 4323
lane: cross-domain
---

# Tasks: migrate workflow YAML + Inngest TS callers onto supabase-ref-resolver

## Phase 0: Preconditions

- [x] 0.1 Verify bash helper tests pass — `bash apps/web-platform/scripts/lib/supabase-ref-resolver.test.sh` → 7/7 pass
- [x] 0.2 Verify reusable-release.yml uses full checkout (no sparse-checkout excluding `apps/web-platform/scripts/lib/`) — `grep -A2 'actions/checkout' .github/workflows/reusable-release.yml | head -5`
- [x] 0.3 Verify vitest is the TS runner — `grep -nE '"(test|test:ci)":' apps/web-platform/package.json`
- [x] 0.4 Verify `node:dns` `promises.resolveCname` shape — `grep -n 'resolveCname' apps/web-platform/node_modules/@types/node/dns.d.ts | head -5`
- [x] 0.5 Verify `spawnSync` is usable from vitest — `grep -rn 'spawnSync\|spawn(' apps/web-platform/test/ | head -5`

## Phase 1: TS helper + parity test (RED)

- [x] 1.1 Create `apps/web-platform/lib/supabase/resolve-ref.ts` exporting `async function resolveSupabaseRef(url: string): Promise<string | null>`
  - [x] 1.1.1 Fast-path regex: `^https?:\/\/([a-z0-9]{20})\.supabase\.co\/?$`
  - [x] 1.1.2 Custom-domain fallback via `dnsPromises.resolveCname` with subdomain-bypass anchored regex
  - [x] 1.1.3 Empty URL → `null`
  - [x] 1.1.4 Try/catch wraps `resolveCname` (NXDOMAIN throws) — returns null
- [x] 1.2 Create `apps/web-platform/test/lib/supabase/resolve-ref-parity.test.ts` with 6 parity cases
  - [x] 1.2.1 Canonical URL fixture
  - [x] 1.2.2 Trailing-slash fixture
  - [x] 1.2.3 Custom-domain via mocked CNAME target
  - [x] 1.2.4 Subdomain-bypass attempt → rejected
  - [x] 1.2.5 Uppercase host → rejected
  - [x] 1.2.6 Empty string → rejected
  - [x] 1.2.7 Bash invocation via `spawnSync` + PATH-shimmed fake `dig`
  - [x] 1.2.8 Assert TS result === bash result for each case
- [x] 1.3 Run `vitest run test/lib/supabase/resolve-ref-parity.test.ts` — confirm green

## Phase 2: Migrate cron-oauth-probe.ts (GREEN)

- [x] 2.1 Delete `resolveSupabaseRefFromCname` function from `apps/web-platform/server/inngest/functions/cron-oauth-probe.ts` (lines 280-289)
- [x] 2.2 Delete `import { promises as dnsPromises } from "node:dns";` (line 32) — verify no other usage
- [x] 2.3 Add `import { resolveSupabaseRef } from "@/lib/supabase/resolve-ref";`
- [x] 2.4 Update call site (line 351): `const cnameRef = (await resolveSupabaseRef(\`https://${apiHost}\`)) ?? supabaseProjectRef;`
- [x] 2.5 Update `apps/web-platform/test/server/inngest/cron-oauth-probe.test.ts`:
  - [x] 2.5.1 Replace `vi.mock("node:dns", ...)` with `vi.mock("@/lib/supabase/resolve-ref", () => ({ resolveSupabaseRef: vi.fn(async () => "ifsccnjhymdmidffkzhl") }))`
  - [x] 2.5.2 Rename `resolveCnameSpy` → `resolveSupabaseRefSpy`, update return shapes from arrays to bare strings
  - [x] 2.5.3 Update drift test cases' `mockResolvedValueOnce` shape
- [x] 2.6 Run `vitest run test/server/inngest/cron-oauth-probe.test.ts` — confirm green
- [x] 2.7 Run `bun tsc --noEmit` — confirm clean

## Phase 3: Migrate reusable-release.yml workflow (GREEN)

- [x] 3.1 Replace inline block in `.github/workflows/reusable-release.yml` lines 483-496 with `. apps/web-platform/scripts/lib/supabase-ref-resolver.sh` + `resolve_supabase_ref` call
- [x] 3.2 Preserve CR/LF strip via `expected_ref_safe` on failure path
- [x] 3.3 Run `actionlint .github/workflows/reusable-release.yml` — confirm clean
- [x] 3.4 Run `shellcheck` on the extracted `run:` block content

## Phase 4: Preflight Check 4 prose pointer (DOCS)

- [x] 4.1 Edit `plugins/soleur/skills/preflight/SKILL.md` Step 4.2 — add one-line pointer to `apps/web-platform/scripts/lib/supabase-ref-resolver.sh`
- [x] 4.2 Preserve existing sub-bullets describing Check 4's wrapper semantics (rc semantics, A-record fallback, subdomain-bypass guard)

## Phase 5: Cross-consumer grep + final verification

- [x] 5.1 Run AC9 negative grep — no inline regex duplicates outside the canonical sources
- [x] 5.2 `bash apps/web-platform/scripts/lib/supabase-ref-resolver.test.sh` → 7/7 pass
- [x] 5.3 `cd apps/web-platform && bun vitest run test/lib/supabase/resolve-ref-parity.test.ts` → 6/6 pass
- [x] 5.4 `bun vitest run test/server/inngest/cron-oauth-probe.test.ts` → all pass
- [x] 5.5 `bun tsc --noEmit` → clean
- [x] 5.6 `actionlint .github/workflows/reusable-release.yml` → clean
- [x] 5.7 Update PR body with `Closes #4323` + `Refs PR #4320`
- [x] 5.8 Verify AC11 — DNS timeout delta: `grep -nE 'dig.*time=' apps/web-platform/scripts/lib/supabase-ref-resolver.sh` returns `+time=5 +tries=2`; `grep -nE 'dig.*time=' .github/workflows/reusable-release.yml` returns 0 matches

## Post-merge (operator)

(None — workflow validates itself on next push to `main`; inngest cron validates TS migration on next scheduled fire.)
