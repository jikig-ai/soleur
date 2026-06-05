---
title: "Drain #3399 test-infra follow-ups — kb-template health probe (#3413) + synthesized GitHub fixtures (#3415)"
deepened: 2026-06-05
date: 2026-06-05
type: fix
branch: feat-one-shot-drain-p4-3399-3413-3415
issues: [3413, 3415]
references_pr: [3399, 2486]
milestone: "Phase 4: Validate + Scale"
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
labels_for_tracking: [code-review, deferred-scope-out, domain/engineering]
---

# Drain #3399 test-infra follow-ups in one PR

## Enhancement Summary

**Deepened on:** 2026-06-05

### Key Improvements
1. **Phase 4.4 precedent-diff gate ran and is decisive:** 39 Inngest crons vs 4 GH-Actions scheduled workflows → the #3413 probe MUST be an Inngest cron (`cron-kb-template-health.ts`), NOT the `.github/workflows/kb-template-health-probe.yml` the issue body names. Governing ADR-030 cited (path-verified).
2. **Precedent-diff table against `cron-github-app-drift-guard.ts`** — every reuse claim grounded to a line number: `assertNoLeak` is EXPORTED (reuse directly); `handleFailureIssue`/`handleLeakIssue` are file-private (co-locate a mirror); `PROBE_ISSUE_OWNER/REPO` + `createProbeOctokit` exported from `probe-octokit.ts`.
3. **Verify-the-negative pass** confirmed the `hr-github-app-auth-not-pat` claim: `createProbeOctokit()` mints via `@octokit/auth-app` internally, no PAT/JWT literal — the new cron must reuse it, not re-implement minting.

### New Considerations Discovered
- The directional divergence (Inngest vs GH-Actions) is real and `requires_cpo_signoff` — the PR body must note the workflow file was intentionally not created so the #3413 author sees it.
- `assertNoLeak` reuse means the leak tripwire is free; only the issue-handling shape needs mirroring (its dedup title-phrase differs anyway).
- All 8 cited AGENTS rule IDs verified active; all heading gates (4.6/4.7) pass after stripping emoji from `## User-Brand Impact` / `## Observability`.

🐛 **fix** — closes two `deferred-scope-out` / `code-review` issues filed against the merged PR #3399 (route user-installation repo create through template `/generate`). Both are in-repo, automatable, no DB migration, no external account. One coherent PR following the #2486 one-PR-multiple-closures precedent.

- **#3413** — operational gap: every user-account "Create Project" routes through `jikig-ai/kb-template`'s `/generate` endpoint. If an operator deletes/renames/privatizes the template or drops its `is_template` flag, every create returns 404/422 — detected only post-hoc via Sentry. Needs a proactive hourly probe + runbook.
- **#3415** — test-fixture-vs-real-API drift class: `github-app-create-repo.test.ts` (and siblings) mock `globalThis.fetch` with hand-rolled JSON literals. #3399's own root cause was a mock returning 201 while prod returned 403 for ~30 days. Replace inline literals with **synthesized** fixtures loaded via a helper.

---

## ⚠️ Research Reconciliation — Spec vs. Codebase

The issue body for #3413 prescribes a **new `.github/workflows/kb-template-health-probe.yml` GitHub Actions cron**. Codebase reality contradicts this prescription on the architecture axis (the *outcome* — hourly proactive probe + auto-filed P0 issue + runbook — is unchanged):

| Issue-body claim | Codebase reality (verified) | Plan response |
|---|---|---|
| Add a new GitHub Actions cron workflow `.github/workflows/kb-template-health-probe.yml` | The codebase runs ~45 `cron-*.ts` Inngest functions under `apps/web-platform/server/inngest/functions/`; **only 4** `scheduled-*.yml` GH-Actions crons remain (drift/probe/sweeper legacy). The canonical hourly-health-probe sibling is **`cron-github-app-drift-guard.ts`** (`{ cron: "0 * * * *" }`, TR9 PR-4, #4235). | **Implement as an Inngest cron** `cron-kb-template-health.ts` mirroring the drift-guard sibling, NOT a GH-Actions workflow. See **Directional Decision** below. The issue's *intent* (hourly proactive probe) is fully satisfied. |
| "Use the existing GitHub App installation-token auth surface; do NOT mint a new PAT" (`hr-github-app-auth-not-pat`) | `apps/web-platform/server/github/probe-octokit.ts` exports `createProbeOctokit()` → installation-scoped Octokit (auto-refreshing installation token via `@octokit/auth-app`), already used by `cron-github-app-drift-guard` + `cron-oauth-probe`. | **Reuse `createProbeOctokit()`** verbatim. Satisfies `hr-github-app-auth-not-pat` by construction; no new auth surface, no PAT. |
| "opens/updates a P0 ops issue on failure, records last-success" | `cron-github-app-drift-guard.ts` already has dedup-search → comment-or-open → auto-close-on-success machinery (`GET /search/issues`, `POST /repos/{owner}/{repo}/issues`, `PATCH .../issues/{n}`) against `jikig-ai/soleur`, plus a PEM/JWT leak-tripwire and `reportSilentFallback` Sentry mirror. | **Reuse the same issue-handling shape**; factor shared helpers if `cron-github-app-drift-guard` already exposes them, else co-locate a minimal mirror. Probe failure files `[ops/kb-template-broken]` titled issue with `priority/p1-high`. |
| "Files: new `apps/web-platform/test/fixtures/github/*.json`; new loader helper" (#3415) | `apps/web-platform/test/fixtures/` exists (4 `.ts` fixtures); **no `github/` subdir**, **no JSON-fixture loader convention** (tests use inline literals). | Create `test/fixtures/github/` + a loader helper. Confirmed greenfield. |

**Premise validation:** #3413 OPEN, #3415 OPEN, both carry milestone #4 "Phase 4: Validate + Scale" on the issue already. #3399 MERGED, #3401 CLOSED, #2486 MERGED (one-PR-multiple-closures precedent confirmed). 10 `github-app-*.test.ts` files exist; `is_template`/`KB_TEMPLATE_OWNER`/`KB_TEMPLATE_NAME` live at `apps/web-platform/server/github-app.ts:888-891`. No external premises stale.

---

## 🧭 Directional Decision — Inngest cron vs. GitHub Actions cron (REQUIRES sign-off)

The issue literally names a GH-Actions workflow file. The plan deliberately diverges to an Inngest cron. **This is a directional-ambiguity gate (plan Phase 0.5) that MUST be confirmed before `/work`.**

**Why Inngest is correct here:**
1. **Precedent (`hr-verify-repo-capability-claim-before-assert` + deepen-plan Phase 4.4 precedent-diff):** `cron-github-app-drift-guard.ts` is a byte-for-byte structural sibling — hourly cron, App-JWT/installation-token auth, GitHub-API probe, issue open/update/auto-close, leak tripwire, Sentry mirror, a runbook, and a unit-test harness. #3413's probe is the same shape against a different endpoint.
2. **Auth reuse:** `createProbeOctokit()` already solves the exact "installation token, no PAT" requirement the issue calls out. A GH-Actions workflow would have to re-implement JWT minting in inline shell (the silent-failure-trap class in `2026-05-05-workflow-jwt-mint-silent-failure-traps.md`).
3. **Observability convention:** Inngest crons land in the `inngest-heartbeat` Better Stack monitor + Sentry; a standalone GH-Actions cron is a separate dark surface (cf. `#4116` inngest-heartbeat dark-zone learning).
4. **The `soleur:schedule` skill scaffolds GH-Actions crons for *agent-invoking* tasks (push commits, run skills). This is a server-side API probe, not an agent task — Inngest is the right substrate.**

**Cost of divergence:** the PR-body `Closes #3413` text must note the architecture deviation so the issue author sees the workflow file was intentionally not created. If sign-off rejects the divergence, fall back to a `scheduled-*.yml` GH-Actions cron with inline JWT minting per `2026-05-05-workflow-jwt-mint-silent-failure-traps.md` (three traps pre-addressed) — but this is the dispreferred path.

---

## User-Brand Impact

**If this lands broken, the user experiences (for #3413):** the probe silently fails to detect kb-template drift, so a non-technical founder clicking "Create Project" gets an opaque 404/422 and a broken onboarding — the exact #3401 failure the probe exists to pre-empt. **For #3415:** a future mock-vs-real-API drift (the #3399 class: 201-mocked / 403-real) ships green for ~30 days, breaking real repo creation for every user.

**If this leaks, the user's data is exposed via:** the probe handler captures GitHub API responses into issue bodies / logs. A leaked installation token or App PEM in captured step output would expose the org's GitHub App credentials → all connected user KB repos. Mitigated by reusing the existing drift-guard **leak tripwire** (PEM-block / JWT-shape detection) before any capture is written.

**Brand-survival threshold:** `single-user incident` — one user's broken "Create Project" or one leaked token is a brand-survival event. `requires_cpo_signoff: true`; `user-impact-reviewer` runs at review time (review/SKILL.md conditional-agent block).

---

## 🎯 Acceptance Criteria

### Pre-merge (PR)

**#3413 — kb-template health probe (Inngest cron path):**
- [ ] `apps/web-platform/server/inngest/functions/cron-kb-template-health.ts` exists, registers an hourly `{ cron: "0 * * * *" }` Inngest function, and is wired into `apps/web-platform/app/api/inngest/route.ts`'s function array (grep: `grep -n cronKbTemplateHealth apps/web-platform/app/api/inngest/route.ts` returns ≥1).
- [ ] The handler calls `createProbeOctokit()` from `server/github/probe-octokit.ts` (NO new PAT, NO new JWT-mint code — `hr-github-app-auth-not-pat`; grep confirms `createProbeOctokit` import and zero `process.env.*PAT*`/`ghp_` literals in the new file).
- [ ] The handler probes `GET /repos/{owner}/{repo}` with `owner=KB_TEMPLATE_OWNER`, `repo=KB_TEMPLATE_NAME` (imported from `server/github-app.ts`, not re-literalized) and asserts the **documented success shape**: `data.is_template === true` AND `data.private === false`. A response missing either field, or a non-object body, is a guard failure (distinct label from drift).
- [ ] On probe failure: dedup-search + open-or-comment a P1 ops issue against `jikig-ai/soleur` titled `[ops/kb-template-broken] …` with labels `["priority/p1-high", <failure-label>]`; on success: auto-close any open such issue (records last-success by closing). Mirrors `cron-github-app-drift-guard.ts` issue-handling.
- [ ] Probe failures `reportSilentFallback(...)` to Sentry (`cq-silent-fallback-must-mirror-to-sentry`); captured GitHub output passes a PEM/JWT leak tripwire before any issue-body write.
- [ ] Unit test `apps/web-platform/test/server/inngest/cron-kb-template-health.test.ts` covers: (a) happy path (`is_template:true, private:false` → no issue, auto-close path); (b) `is_template:false` → issue filed; (c) `private:true` → issue filed; (d) 404 (repo missing/renamed) → issue filed; (e) malformed body (missing fields) → guard-broken label; (f) success auto-closes a prior open issue. All fetches/Octokit stubbed — no real network. Runner: `./node_modules/.bin/vitest run test/server/inngest/cron-kb-template-health.test.ts` (NOT `bun test` — `apps/web-platform/bunfig.toml` sets `pathIgnorePatterns=["**"]`).
- [ ] **Dry-run assertion of documented success shape:** a test (or a `--dry-run`-style exported pure function) exercises the probe's success-shape predicate against a synthesized `GET /repos` 200 fixture and asserts the pass verdict — proving the probe asserts the documented shape, not just HTTP 200.
- [ ] Runbook `knowledge-base/engineering/operations/runbooks/kb-template-health.md` exists with: title/owners/`applies_to`/`related_issues:[3413,3399,3401]` frontmatter; the three failure-label families and their meaning; alert-response steps (verify template state via `gh repo view jikig-ai/kb-template --json isTemplate,visibility`; remediation = re-mark template / make public / un-rename); and a "substrate-down false-positive" cross-check against `inngest-heartbeat` mirroring `github-app-drift.md`.

**#3415 — synthesized GitHub fixtures:**
- [ ] `apps/web-platform/test/fixtures/github/` contains synthesized JSON fixtures for the GitHub API response shapes the github-app tests mock: at minimum `installation-account.json` (org + user variants), `installation-access-token.json`, `repo-create-201.json`, `template-generate-201.json`, `error-403.json`, `error-404.json`, `error-422-duplicate.json`, `error-422-not-template.json`. **All synthesized per `cq-test-fixtures-synthesized-only`:** `@example.com`/`@test.local` emails only, NO prod-shape UUIDs, NO live tokens (token fixtures use obvious placeholders like `ghs_<<synthetic>>`), all IDs small synthetic integers. Field names/types/status codes match GitHub's public REST API docs.
- [ ] A loader helper (e.g. `apps/web-platform/test/fixtures/github/load.ts` exporting `loadGithubFixture(name)`) reads + parses the JSON and returns a typed object. Helper is the single read path; tests import it rather than `readFileSync` inline.
- [ ] `github-app-create-repo.test.ts` (and every sibling identified by the enumeration grep below) replaces its inline `mockFetch.mockResolvedValueOnce({ ok, status, json: async () => ({...}) })` JSON literals with `loadGithubFixture(...)`-sourced bodies. The `ok`/`status` wrapper stays inline (it's vitest mock mechanics, not API data); only the **response body** moves to the fixture.
- [ ] Enumeration is grep-derived, NOT issue-body-derived: `git grep -lnE 'mockResolvedValueOnce|json: async' apps/web-platform/test/github-app-*.test.ts` produces the file list; every file with a literal API-shaped body is in scope or explicitly scoped-out with a one-line reason.
- [ ] The synthesized fixtures' `is_template`/`private` shape for the kb-template `/repos` response is shared between the #3413 dry-run test and the #3415 fixture set (one canonical synthesized repo-metadata fixture, not two divergent copies).
- [ ] Full github-app test suite green: `./node_modules/.bin/vitest run test/github-app-create-repo.test.ts <…siblings…>`.
- [ ] `tsc --noEmit` clean for `apps/web-platform`.

### Post-merge (operator)
- [ ] First hourly Inngest tick of `cron-kb-template-health` fires and records a success (auto-close path with no open issue) — verify via `inngest-heartbeat` monitor + Sentry absence-of-error. **Automation:** the merge to `apps/web-platform/**` redeploys the container (`web-platform-release.yml` path-filtered push) which registers the new Inngest function; no separate operator step. On-demand verification available via the `inngest-server.md` runbook "On-demand cron trigger (HTTP)" path if needed.

---

## Research Insights (deepen-plan 2026-06-05)

### Phase 4.4 Precedent-Diff Gate — scheduled-work pattern (DECISIVE for #3413)

Ran the prescribed checks:

```
$ git ls-files | grep -cE "apps/web-platform/server/inngest/functions/cron-"
39
$ git ls-files | grep -E "^\.github/workflows/scheduled-" | wc -l
4
```

39 Inngest crons vs 4 legacy GH-Actions scheduled workflows → **Inngest is canonical**; the new probe MUST be an Inngest cron, not a `scheduled-*.yml`. This confirms the Directional Decision. The GH-Actions path fails the deepen-plan precedent-check criteria: the work is NOT purely git/repo-scoped — it needs app context (`createProbeOctokit()`), app secrets (GitHub App PEM in Doppler `prd`), Sentry integration (`reportSilentFallback`), and benefits from `step.run` memoization. **Governing ADR: ADR-030 "Inngest as durable trigger layer for server-side agents"** (`knowledge-base/engineering/architecture/decisions/ADR-030-inngest-as-durable-trigger-layer.md`, status: accepted) — the substrate decision for scheduled server-side work. (ADR-033 also exists but is narrower — "Inngest cron functions invoke claude-code via child_process.spawn" — it governs *agent-task* crons, not a pure API-probe cron; ADR-030 is the correct citation here.)

### Precedent diff — `cron-github-app-drift-guard.ts` (the structural sibling)

| Concern | Sibling (`cron-github-app-drift-guard.ts`) | New `cron-kb-template-health.ts` |
|---|---|---|
| Schedule | `inngest.createFunction(..., { cron: "0 * * * *" }, handler)` (line 868-878) | identical — hourly |
| Auth | `createAppJwtOctokit()` (App-JWT, hits `GET /app` + `GET /app/installations`) | `createProbeOctokit()` (installation-scoped, auto-refreshing installation token via `@octokit/auth-app`) — correct for `GET /repos/{owner}/{repo}` repo-metadata read. **No PAT.** |
| Probe | `GET /app`; assert `id`+`client_id` byte-for-byte | `GET /repos/{owner}/{repo}`; assert `is_template===true` AND `private===false` |
| Leak tripwire | `assertNoLeak(label, s)` — **EXPORTED** at line 121 | **Reuse `assertNoLeak` directly** (import from the sibling) — guards every issue-body/comment before write |
| Issue handling | `handleFailureIssue` (line 542) — dedup `GET /search/issues` by label+title-phrase → comment-or-`POST /issues` → success auto-closes via `PATCH .../issues/{n}` state:closed | **file-private in the sibling** (`handleFailureIssue`/`handleLeakIssue` NOT exported). Mirror the same shape co-located in the new cron, OR extract a shared `server/github/probe-issue-handler.ts` helper. deepen-plan recommends the **co-located mirror** first (smaller blast radius; the dedup query differs by title-phrase anyway — "GitHub App drift-guard" vs a kb-template phrase) and notes the duplication for a future dedup issue. |
| Issue target repo | `PROBE_ISSUE_OWNER`/`PROBE_ISSUE_REPO` = `jikig-ai`/`soleur` (exported from `probe-octokit.ts:94-95`) | reuse the same exports |
| Sentry mirror | `reportSilentFallback` (warn/error) | reuse `@/server/observability` |
| Registration | served in `apps/web-platform/app/api/inngest/route.ts` | add `cronKbTemplateHealth` to the same array |
| Runbook | `knowledge-base/engineering/operations/runbooks/github-app-drift.md` (3 failure-label families + inngest-heartbeat false-positive cross-check) | author `kb-template-health.md` mirroring its structure |

**Implication for `## Files to Edit`:** prefer the co-located-mirror approach → the only edit to the sibling file is none (import `assertNoLeak` from it). If `/work` finds the issue-handling extraction is clean, that becomes a new shared file under `server/github/` rather than an edit to the drift-guard.

### Verify-the-negative pass — `hr-github-app-auth-not-pat`

Plan asserts "NO new PAT, NO new JWT-mint code". Verified against the implementation surface: `createProbeOctokit()` (`probe-octokit.ts:116`) mints via `@octokit/auth-app` `App` + `getInstallationOctokit(installation.id)` — the installation token is internal and auto-refreshed; the caller never sees a raw token. There is no `process.env.*PAT*` / `ghp_` / `github_pat_` literal in `probe-octokit.ts`. **Confirms** the negative claim. The new cron MUST NOT introduce its own `jsonwebtoken`/`openssl` minting (the GH-Actions-fallback silent-failure-trap class, `2026-05-05-workflow-jwt-mint-silent-failure-traps.md`) — reuse `createProbeOctokit()`.

### #3415 — fixture loader convention (greenfield, confirmed)

No existing JSON-fixture-loader helper in `apps/web-platform/test/` (the 4 existing `test/fixtures/*.ts` are TS module fixtures, not JSON loaded via a helper). The loader is genuinely new. The mock bodies to replace are inline `vi.fn().mockResolvedValueOnce({ ok, status, json: async () => ({...}) })` literals (verified in `github-app-create-repo.test.ts:88-110, 138-150, ...`). Only the `({...})` **body** moves to a fixture; `ok`/`status` stay inline (vitest mock mechanics). GitHub's real `/repos` response carries `is_template`, `private`, `full_name`, `html_url`, `default_branch`, `owner.login`, etc.; synthesize to that shape with `@example.com`/synthetic-integer-IDs.

## Files to Create

- `apps/web-platform/server/inngest/functions/cron-kb-template-health.ts` — hourly Inngest cron, `createProbeOctokit()` → `GET /repos/{owner}/{repo}`, success-shape assertion, issue open/update/close, leak tripwire, Sentry mirror.
- `apps/web-platform/test/server/inngest/cron-kb-template-health.test.ts` — unit tests (stubs, no network).
- `apps/web-platform/test/fixtures/github/*.json` — synthesized fixtures (list above).
- `apps/web-platform/test/fixtures/github/load.ts` — fixture loader helper.
- `knowledge-base/engineering/operations/runbooks/kb-template-health.md` — alert-response runbook.

## ✏️ Files to Edit

- `apps/web-platform/app/api/inngest/route.ts` — register `cronKbTemplateHealth` in the served-functions array.
- `apps/web-platform/test/github-app-create-repo.test.ts` — swap inline JSON literals → `loadGithubFixture(...)`.
- Sibling `github-app-*.test.ts` files surfaced by the enumeration grep (candidates from density scan: `github-app-pr.test.ts`, `github-app-default-branch-commit.test.ts`, `github-app-find-installation.test.ts`, `github-app-token-hardening.test.ts`) — confirm-or-scope-out each at /work Phase 1.
- (Optional, deepen-plan to confirm) extract shared issue-handling helpers from `cron-github-app-drift-guard.ts` if reuse is clean; otherwise co-locate a minimal mirror in the new cron and note the duplication for a future dedup issue.

---

## 🧩 Open Code-Review Overlap

`code-review`/`deferred-scope-out` issues touching the planned files were checked. **#3413 and #3415 are themselves the overlap** — both are folded in (`Closes #3413`, `Closes #3415`). No *other* open scope-out names `cron-kb-template-health.ts` (new file), `test/fixtures/github/**` (new dir), or the `github-app-*.test.ts` mock bodies. If `/work` Phase 1 enumeration surfaces a sibling test file already tracked by another open scope-out, fold-in or acknowledge per the overlap rule. Recorded so the next planner sees the check ran.

---

## Observability

```yaml
liveness_signal:
  what: cron-kb-template-health hourly tick (success = auto-close path, no open issue)
  cadence: hourly ("0 * * * *")
  alert_target: inngest-heartbeat Better Stack monitor (shared substrate) + auto-filed [ops/kb-template-broken] issue on drift
  configured_in: apps/web-platform/server/inngest/functions/cron-kb-template-health.ts
error_reporting:
  destination: Sentry via reportSilentFallback (warn/error) — cq-silent-fallback-must-mirror-to-sentry
  fail_loud: true (probe failure opens a priority/p1-high ops issue; never silently swallowed)
failure_modes:
  - {mode: kb-template deleted/renamed (404), detection: GET /repos 404, alert_route: "[ops/kb-template-broken] issue + Sentry"}
  - {mode: is_template flag dropped, detection: data.is_template !== true, alert_route: same}
  - {mode: flipped to private, detection: data.private !== false, alert_route: same}
  - {mode: malformed/empty body, detection: non-object or missing fields, alert_route: "[ci/guard-broken]-style issue (guard malfunction, not drift)"}
  - {mode: token/PEM leak in captured output, detection: leak tripwire (PEM-block / JWT shape), alert_route: "[security/leak-suspected] issue"}
logs:
  where: Inngest run logs + Sentry events; issue bodies on jikig-ai/soleur
  retention: Sentry default; issues persist until auto-closed on next success
discoverability_test:
  command: "./node_modules/.bin/vitest run apps/web-platform/test/server/inngest/cron-kb-template-health.test.ts"
  expected_output: "all tests pass — happy path asserts is_template===true && private===false; failure modes file issues; success auto-closes"
```

(No `ssh` in `discoverability_test.command`.)

---

## 🔐 GDPR / Compliance Gate

Probe reads **public repo metadata** (`is_template`, `private`) of an org-owned template — no operator personal data, no regulated-data surface (no schema/migration/auth/API-route change). Fixtures are synthesized (no real user data — `cq-test-fixtures-synthesized-only`). Trigger (a) "LLM/external API on operator-session-derived data" does NOT fire (GitHub metadata, not session data). **gdpr-gate skipped** — no regulated-data surface. (deepen-plan may re-confirm.)

---

## 🏗 Infrastructure (IaC)

No new infrastructure. The Inngest substrate (`apps/web-platform/infra/inngest.tf`, ADR-030 self-hosted) and the GitHub App secrets in Doppler `prd` already exist and are consumed by `createProbeOctokit()`. The new cron is application code registered into the existing `/api/inngest` serve route — no server, secret, vendor, or persistent process is added. **Phase 2.8 skipped** (pure code against already-provisioned surface). If sign-off forces the GH-Actions fallback path, that workflow uses the existing GitHub App secrets via repo secrets — still no new infra.

---

## 🧪 Test Strategy

Runner: `vitest run` (per `apps/web-platform/package.json scripts.test`; **never `bun test`** — `bunfig.toml pathIgnorePatterns=["**"]`). New cron test lives at `test/server/inngest/cron-kb-template-health.test.ts` (matches vitest node project glob `test/**/*.test.ts`). Fixtures under `test/fixtures/github/*.json` are data, not tests — not collected by any vitest project (`.json` ∉ `*.test.ts`/`*.test.tsx`). RED-first per `cq-write-failing-tests-before`: write the cron + fixture tests failing, then implement.

---

## 🔁 Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| New `.github/workflows/kb-template-health-probe.yml` GH-Actions cron (issue-body literal) | Diverges from the 45-cron Inngest convention + the direct `cron-github-app-drift-guard` sibling; forces inline JWT-mint re-implementation (silent-failure-trap class); separate dark observability surface. Kept as documented fallback if sign-off rejects the Inngest path. |
| Literal-capture fixtures from real GitHub responses | Violates `cq-test-fixtures-synthesized-only` (real IDs/tokens). Value is shape-fidelity, not data-fidelity — synthesize to the public-API shape. |
| Two PRs (one per issue) | #2486 precedent + the shared synthesized repo-metadata fixture (used by both the #3413 dry-run and the #3415 fixture set) make one coherent PR cheaper and DRY. |

---

## 📌 Sharp Edges

- A plan whose `## User-Brand Impact` section is empty / `TBD` / lacks the threshold fails `deepen-plan` Phase 4.6. (Filled above; threshold = single-user incident.)
- The fixture **token** fields must use a non-`[a-zA-Z0-9]` placeholder shape (`ghs_<<synthetic>>`, not a literal 40-char token) or GitHub push-protection rejects the push even for synthetic data (`2026-05-15-github-push-protection-rejects-synthetic-tokens-in-plan-prose.md`). The real fixture FILE may carry an obviously-fake token only if `cq-test-fixtures-synthesized-only`-compliant and gitleaks-allowlisted.
- Enumerate the github-app mock files via `git grep`, NOT the issue body — the issue names `github-app-create-repo.test.ts` but the density scan shows ≥5 files with literal API bodies.
- Test path must satisfy the vitest `include` glob (`test/**/*.test.ts`) AND avoid `bun test` (bunfig blocks discovery). Use `./node_modules/.bin/vitest run <path>`.
- Reuse `KB_TEMPLATE_OWNER`/`KB_TEMPLATE_NAME` from `server/github-app.ts:888-891` — do not re-literalize `jikig-ai`/`kb-template` in the new cron.

---

## 🚢 PR Requirements

- PR body MUST include `Closes #3413` and `Closes #3415` (in body, not title — `wg-use-closes-n-in-pr-body-not-title-to`). This is a code change merged atomically (not an ops-remediation), so `Closes` is correct (not `Ref`).
- Reference PR **#2486** as the one-PR-multiple-closures precedent.
- Note the **architecture deviation** for #3413 (Inngest cron, not the GH-Actions workflow the issue names) in the PR body so the issue author sees the workflow file was intentionally not created.
- Set milestone **"Phase 4: Validate + Scale"** on the PR (`gh pr edit <n> --milestone "Phase 4: Validate + Scale"`).
- `requires_cpo_signoff: true` — CPO sign-off on the technical approach at plan time; `user-impact-reviewer` at review time.
