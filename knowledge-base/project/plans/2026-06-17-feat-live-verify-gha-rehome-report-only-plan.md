---
date: 2026-06-17
issue: 5487
branch: feat-one-shot-5487-live-verify-gha-rehome
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: plan-complete
---

# feat(live-verify): re-home harness into web-platform-release.yml deploy job (report-only, GHA substrate)

## Overview

Re-home the live-verify harness (`apps/web-platform/scripts/live-verify/run.ts`)
from the agent-driven `/soleur:postmerge` skill into a **REPORT-ONLY** step in the
`deploy:` job of `.github/workflows/web-platform-release.yml`, on `ubuntu-latest`.
This is item 3 of the #5463 prereq chain (the deterministic CI substrate the
report-only→blocking flip is gated on per ADR-064 §Substrate).

**Substrate = GitHub Actions, NOT Inngest** (CTO ruling, 2026-06-17). A blocking
deploy-gate needs a **deterministic, synchronous, host-isolated exit-code signal**.
An Inngest async result on the same prod host whose deploy is being gated would
reintroduce the #4932 non-deterministic-blocking-gate class (`wg-dark-launch-deploy-gates`):
gating on an async result needs poll-with-timeout = silent-pass/flaky-block, it
perturbs the system under test, and it couples a mutating prod session to the
cron-platform concurrency slot. The browser objection does NOT decide it (prod
bakes Chromium; `ubuntu-latest` installs the bundled chromium cleanly) —
determinism does.

Two deliverables, one PR:
1. A trigger-paths-gated, **report-only** (`continue-on-error: true`) live-verify
   step in the `deploy:` job, AFTER "Verify deploy health and version", running
   `run.ts` under the existing `doppler run -c prd` pattern, with the `RESULT:`
   line emitted to Sentry (ADR-033 Option C shape) for SSH-free observability.
2. The ADR-064 amendment: append the CTO's
   "### Inngest re-home considered and rejected (2026-06-17)" decision-of-record
   block to ADR-064 §Substrate (substrate unchanged; capture via `/soleur:architecture`).

## Premise Validation

Checked against the worktree + live GitHub state (2026-06-17):

- **#5487 OPEN**, title + body match the task verbatim (item 3 of the #5463 chain). Not stale.
- **#5463 OPEN** ("flip live-verification postmerge gate from report-only to blocking") — the dark-launch this PR feeds; this PR does NOT flip it.
- **#5486 MERGED** (item 1, harness auth + non-bundled-chromium), **#5473 MERGED** (item 2, bootstrap scripts). The harness is bootstrap-ready in prod.
- **Target files all exist:** `.github/workflows/web-platform-release.yml` (deploy job, "Verify deploy health and version" at L467-529), `apps/web-platform/scripts/live-verify/run.ts`, `.../trigger-paths.txt`, `.../redact.ts`, and `ADR-064-live-production-verification-harness.md` (§Substrate at L128-136).
- **`wg-dark-launch-deploy-gates` confirmed verbatim** (`AGENTS.rest.md`): "ships NON-BLOCKING first and is observed passing on ≥1 real deploy before it gates" — exactly the report-only posture; the FAIL-blocks flip is #5463.
- **Mechanism vs ADR corpus:** ADR-064 §Substrate (L131-136) *names this exact re-home* as the blocking-flip precondition ("re-homing the harness into a GitHub Action / `workflow_dispatch`-from-`web-platform-release.yml` with a Sentry-observable result"). The plan implements an ADR-recorded decision; it does NOT re-litigate a rejected alternative. The Inngest path is the alternative being formally rejected in the amendment, consistent with the ruling.
- **`run.ts` runner = `bun`** (header L9: "Runner: bun … NOT bare node"); driver = chromium bundled in `@playwright/test` (`package.json`: `"@playwright/test": "^1.58.2"`); `LIVE_VERIFY_BROWSER_CHANNEL/PATH` are `optional()` (L109-110) and unset → bundled chromium (ADR-064 §"Runner browser", L143-150).

## Research Reconciliation — Spec vs. Codebase

| Claim (issue/brainstorm) | Codebase reality | Plan response |
|---|---|---|
| "Run `run.ts` via the existing in-step `doppler run -c prd` pattern already used in the deploy job" | The `doppler run -c prd` pattern exists in **sibling jobs** (`migrate` L120-124, `verify-migrations` L148-152, `verify-doppler-secrets` L249-253), each with its own `actions/checkout` + `dopplerhq/cli-action` setup. The **`deploy:` job itself has NO checkout, NO Doppler CLI, NO bun, NO `node_modules`, NO Playwright chromium** — it is a pure curl/webhook job. | The new step CANNOT just append `doppler run`. It needs prerequisite setup steps inside the `deploy:` job (checkout, Doppler CLI, setup-bun, `bun install`, `playwright install --with-deps chromium`), OR the harness runs in a **separate gated job** with `needs: deploy`. Decision in §Architecture below: separate report-only `live-verify:` job (cleaner; keeps the deploy job's curl-only shape and concurrency semantics intact). The issue's "step AFTER health-verify in the deploy job" intent is honored by ordering `needs: [deploy]` (runs after the deploy job's health-verify completes), not by literally nesting in the same job. |
| "Emit the RESULT line to Sentry (ADR-033 Option C shape)" | `run.ts` emits `RESULT:` **only to stdout via `console.log`** (L505-512); it does NOT emit to Sentry. No existing workflow POSTs an arbitrary message to Sentry via envelope (`grep` for `envelope`/`store/` in `.github/` returned no event-ingest pattern). | The **workflow step** owns the Sentry emission: capture the `RESULT:` line from stdout, POST it as a Sentry event (envelope/`store` API) using `NEXT_PUBLIC_SENTRY_DSN` (already a workflow secret, used in `reusable-release.yml` L370, `apply-sentry-infra.yml`, `sentry-audit-gate.yml`). The RESULT line is **already `redact()`-scrubbed** before `console.log` (run.ts:509 → redact.ts), so forwarding it is leak-safe. |
| "report-only … does NOT fail the deploy" | `run.ts` sets `process.exitCode = 1` on **FAIL (L541), CANT-RUN (L521, L547), and CONFIG (L521)**. Only PASS exits 0. | **`continue-on-error: true` is MANDATORY** on the harness step (or a separate non-needed-by-anything job). Without it a FAIL/CANT-RUN non-zero exit fails the job. This is the single load-bearing report-only mechanism. Because the live-verify job is in a **separate job that nothing `needs:`**, even a job-level failure cannot block the deploy or "done". |
| "gate it on the trigger-paths.txt changed-file set" | `trigger-paths.txt` is POSIX-ERE, one pattern per line, consumed via `grep -vE '^[[:space:]]*#\|^[[:space:]]*$'` then `grep -qE -f` (file header L5-8). The workflow fires only on `push` to `main` `paths: ['apps/web-platform/**']` (L4-6). | The gate compares the **commit's changed files** (`git diff --name-only ${{ github.event.before }} ${{ github.sha }}`, or the GH API compare) against the stripped patterns. On `workflow_dispatch` there is no `before` SHA → treat as "always run" (operator escape hatch) OR skip; chosen: skip on dispatch (the report-only signal targets real merges). If no path matches → record `SKIPPED` and exit 0 (fail-open, matching the postmerge skill L368-369). |

## User-Brand Impact

- **If this lands broken, the user experiences:** a deploy that is wrongly blocked
  or wrongly rolled back by a report-only step that was not actually report-only
  (the #4932 class), OR the live-verify signal silently never runs and the #5463
  blocking flip is gated on a dark signal that produces false confidence.
- **If this leaks, the user's prod session data is exposed via:** the harness drives
  a real synthetic-prod session and captures WS/DOM/network; an un-redacted RESULT
  line forwarded to Sentry or a workflow log could carry the synthetic principal's
  live tokens/cookies/emails. Mitigated: `run.ts` `redact()`s the RESULT line
  before `console.log` (run.ts:509), and the workflow forwards ONLY that line.
- **Brand-survival threshold:** single-user incident.

CPO sign-off required at plan time (threshold = single-user incident). The CTO/CLO
framing is carried from the #5452 brainstorm (synthetic-principal guardrails:
UID-allowlist code gate, redact-before-persist, ephemeral session). `user-impact-reviewer`
will be invoked at review-time.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-064** (`knowledge-base/engineering/architecture/decisions/ADR-064-live-production-verification-harness.md`).
The decision-of-record: the live-verify substrate is **GitHub Actions
(`web-platform-release.yml` deploy stage), NOT Inngest**. Append a
`### Inngest re-home considered and rejected (2026-06-17)` block to **§Substrate**
(after L136), capturing the CTO's reasoning verbatim:

- A blocking deploy-gate needs a deterministic, synchronous, host-isolated
  exit-code signal.
- An Inngest async result is async, on the same prod host whose deploy is being
  gated, and gating on it needs a poll-with-timeout fallback = silent-pass/flaky-block
  = the #4932 non-deterministic-blocking-gate class ADR-064 forbids.
- It perturbs the system under test and couples a mutating prod session to the
  cron-platform concurrency slot.
- The browser objection does NOT decide it (prod bakes Chromium; `cron-ux-audit`
  already drives a browser in-container) — determinism does.
- Aligns with ADR-033 Option C scope-note (credential-heavy real-stack execution
  with a Sentry-observable result).

**Substrate is UNCHANGED** (ADR-064 already named the GHA re-home as the precondition);
this amendment records the formal rejection of the considered Inngest alternative.
No ADR-033 Option-set change. Capture via `/soleur:architecture` (amend flow).

### C4 views

No new C4 edge. ADR-064 §C4 already records the "live-verify harness → deployed
web-platform (HTTPS) + prod Supabase (auth)" edge as `status: adopting`. This PR
moves the *execution location* of that edge (skill → GHA) but does not change the
edge's endpoints. Note in the amendment that the edge's driver is now the release
workflow; no `.c4` model file edit is required (the edge already exists).

### Sequencing

The amendment is authored now (this PR), describing the GHA substrate as the
report-only-v1 substrate. The blocking flip (#5463) is a separate PR gated on
observing ≥1 real green PASS from this step.

## Implementation Phases

### Phase 0 — Preconditions (verify, no code)

- Confirm the `deploy:` job's last step is "Verify deploy health and version"
  (L467-529) — the seam the new job orders after.
- Confirm `NEXT_PUBLIC_SENTRY_DSN` is an available workflow secret
  (`grep -n NEXT_PUBLIC_SENTRY_DSN .github/workflows/reusable-release.yml` → L370).
- Confirm `DOPPLER_TOKEN_PRD` is the secret name used by sibling `doppler run -c prd`
  steps (L122, L150, L251).
- Confirm the live-verify env contract via `grep -nE 'required\(|optional\(' run.ts`
  (L102-110): `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`,
  `LIVE_VERIFY_USER_PASSWORD`, `LIVE_VERIFY_EXPECTED_UID`, `LIVE_VERIFY_EXPECTED_REF`,
  `PRODUCTION_URL`|`DEPLOY_URL`. All resolve from Doppler `prd`.
- Pin the playwright Docker image digest / version used by `ci.yml` e2e (L441,
  `mcr.microsoft.com/playwright:v1.58.2-jammy`) as the precedent for browser setup,
  OR confirm `playwright install --with-deps chromium` on bare `ubuntu-latest`.

### Phase 1 — Add the report-only live-verify job to `web-platform-release.yml`

Add a new job `live-verify:` (NOT a step inside `deploy:`, per Research Reconciliation
row 1 — the deploy job is curl-only and nothing should make the harness's setup
re-shape it). The job:

- `needs: [deploy]` and `if: always() && needs.deploy.result == 'success' && github.event_name == 'push'`
  — runs AFTER the deploy job's health-verify, only on real merges (skip on
  `workflow_dispatch`), and only when the deploy actually happened.
- `runs-on: ubuntu-latest`.
- **Nothing `needs:` this job** → a job-level failure can NEVER block the deploy
  or "done" (report-only by topology). The harness step ALSO carries
  `continue-on-error: true` (defense-in-depth: keeps the job green so the Sentry-emit
  step always runs).
- Steps:
  1. `actions/checkout@…` (pinned SHA, mirror L117).
  2. `dopplerhq/cli-action@…` (pinned SHA, mirror L119).
  3. `oven-sh/setup-bun@…` (pinned SHA, mirror `ci.yml` L252).
  4. `bun install --frozen-lockfile` in `apps/web-platform` (mirror `ci.yml` L276).
  5. `npx playwright install --with-deps chromium` in `apps/web-platform` (bundled
     chromium per `@playwright/test`; `--with-deps` installs the OS libs on
     `ubuntu-latest`). Leave `LIVE_VERIFY_BROWSER_CHANNEL/PATH` UNSET.
  6. **Trigger-paths gate** (`id: gate`): compute changed files for the push
     (`git diff --name-only ${{ github.event.before }} ${{ github.sha }}` with a
     fallback to the GH compare API if `before` is the zero-SHA), strip
     `trigger-paths.txt` comments/blanks, `grep -qE -f`; set
     `triggered=0|1` as a step output. On `triggered=0`: emit
     `RESULT: SKIPPED (no triggering paths)` to the log + Sentry breadcrumb-level,
     skip the harness.
  7. **Run harness** (`id: harness`, `if: steps.gate.outputs.triggered == '1'`,
     `continue-on-error: true`): `cd apps/web-platform && doppler run -c prd -- bun run scripts/live-verify/run.ts 2>&1 | tee /tmp/live-verify.out`;
     extract `RESULT_LINE=$(grep -E '^RESULT: ' /tmp/live-verify.out | tail -1)`;
     empty → `RESULT: CANT-RUN:no-result-line` (fail-closed for the *recording*,
     not for "done"). Set `RESULT_LINE` as a step output (already redacted by run.ts).
     `env: DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN_PRD }}`.
  8. **Emit to Sentry** (`if: always() && steps.gate.outputs.triggered == '1'`):
     POST the `RESULT_LINE` as a Sentry event (message-level, tagged
     `gate=live-verify`, `component=web-platform`, `result=<PASS|FAIL|CANT-RUN|SKIPPED>`)
     to the `store`/envelope endpoint derived from `NEXT_PUBLIC_SENTRY_DSN`.
     `env: NEXT_PUBLIC_SENTRY_DSN: ${{ secrets.NEXT_PUBLIC_SENTRY_DSN }}`. This is
     the SSH-free observability surface (ADR-033 Option C shape). On a FAIL, set
     the Sentry event `level=error` so it surfaces for the #5463 flip observation.

**Report-only invariant (load-bearing):** the deploy is gated by
`needs: [release, migrate, verify-migrations, verify-doppler-secrets, await-ci]`
(L256). `live-verify:` is NOT in any job's `needs:`, so by construction it cannot
gate the deploy or roll it back. This is stronger than `continue-on-error` alone.

### Phase 2 — Sentry emit helper (workflow `run:` block)

Inline bash in the emit step (no new file): parse the DSN
(`https://<key>@<host>/<project_id>`), build the
`https://<host>/api/<project_id>/store/` URL, POST a minimal JSON event
(`{message, level, tags, platform:"other"}`) with header
`X-Sentry-Auth: Sentry sentry_version=7, sentry_key=<key>`, `--max-time 10`.
Degraded-permissive: a non-2xx Sentry response logs a warning but does NOT fail
the step (the GH Actions log + step summary is the secondary observability surface;
Sentry is primary but a Sentry outage must not red the report-only job). Mirror the
DSN-parse shape already in `apps/web-platform/scripts/sentry-monitors-audit.sh:159-182`
(use that as the canonical parse precedent — do NOT hand-roll a new regex).

### Phase 3 — ADR-064 amendment (via /soleur:architecture)

Append the `### Inngest re-home considered and rejected (2026-06-17)` block to
ADR-064 §Substrate (after L136, before §"Runner browser + cookie shape"). Content
per §Architecture Decision above. No status change to ADR-064 (stays Accepted).

### Phase 4 — Workflow validation (the PR edits a release workflow)

- `actionlint` over `web-platform-release.yml` (catch YAML + `${{ }}` expression
  errors). NOT `bash -n` on the YAML file (parses the header as bash — Sharp Edge).
- `bash -n` / `bash -c` over each NEW embedded `run:` snippet (gate, harness,
  emit) extracted in isolation.
- **Harness-step-failure-cannot-fail-the-job proof:** confirm via two independent
  mechanisms — (a) topology: `grep -n 'needs:' web-platform-release.yml` shows no
  job `needs: live-verify`; (b) step-level: the harness step has
  `continue-on-error: true`. Add a one-line comment in the workflow citing both.
- Confirm the `deploy:` job's `if:` (L265-273) and `needs:` (L256) are UNCHANGED
  (diff is additive only).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] A `live-verify:` job is added to `web-platform-release.yml` with
  `needs: [deploy]`, `runs-on: ubuntu-latest`, gated on `github.event_name == 'push'`,
  and **no other job `needs:` it** (`grep -c 'needs:.*live-verify' web-platform-release.yml` = 0).
- [ ] The harness step carries `continue-on-error: true`
  (`grep -A12 'id: harness' web-platform-release.yml | grep -q 'continue-on-error: true'`).
- [ ] The harness runs `doppler run -c prd -- bun run scripts/live-verify/run.ts`
  from `apps/web-platform`, with `LIVE_VERIFY_BROWSER_CHANNEL`/`LIVE_VERIFY_BROWSER_PATH`
  NEVER set in the job (`! grep -qE 'LIVE_VERIFY_BROWSER_(CHANNEL|PATH)' web-platform-release.yml`).
- [ ] Job runs the trigger-paths gate against `trigger-paths.txt`
  (`grep -q 'trigger-paths.txt' web-platform-release.yml`); on no match it records
  `SKIPPED` and the harness step does not run.
- [ ] A Sentry-emit step POSTs the redacted `RESULT:` line using
  `secrets.NEXT_PUBLIC_SENTRY_DSN`, tagged with the tri-state result and
  `gate=live-verify`. Reachable without SSH.
- [ ] `actionlint .github/workflows/web-platform-release.yml` passes (0 errors).
- [ ] The `deploy:` job's `needs:` (L256) and `if:` (L265-273) are byte-for-byte
  unchanged in the diff (additive-only change).
- [ ] ADR-064 §Substrate contains the
  `### Inngest re-home considered and rejected (2026-06-17)` block
  (`grep -q 'Inngest re-home considered and rejected' ADR-064-*.md`).

### Post-merge (observation — feeds #5463)

- [ ] On the first real qualifying deploy post-merge (a merge touching a
  `trigger-paths.txt` surface), the `live-verify:` job runs and emits a correct
  `PASS`/`FAIL`/`CANT-RUN` Sentry event, recorded on #5463 as the dark-launch
  observation toward the blocking flip. **Automation:** verify via Sentry API query
  (`gate:live-verify` events) per `hr-no-dashboard-eyeball-pull-data-yourself`;
  not an operator dashboard-eyeball step.

## Observability

```yaml
liveness_signal:
  what: "live-verify RESULT (PASS|FAIL|CANT-RUN|SKIPPED) Sentry event per qualifying merge"
  cadence: "per push to main touching a trigger-paths.txt surface"
  alert_target: "Sentry (tag gate=live-verify); FAIL emitted at level=error"
  configured_in: ".github/workflows/web-platform-release.yml live-verify job, Sentry-emit step"
error_reporting:
  destination: "Sentry via NEXT_PUBLIC_SENTRY_DSN store endpoint; GH Actions step log + job summary as secondary"
  fail_loud: "harness FAIL → Sentry level=error; CANT-RUN → level=warning; empty RESULT → CANT-RUN:no-result-line (never silently dropped)"
failure_modes:
  - mode: "harness FAIL (rail regression)"
    detection: "RESULT: FAIL line → Sentry level=error"
    alert_route: "Sentry gate=live-verify result=FAIL"
  - mode: "harness CANT-RUN (browser launch / config / teardown)"
    detection: "RESULT: CANT-RUN:<reason> → Sentry level=warning"
    alert_route: "Sentry gate=live-verify result=CANT-RUN"
  - mode: "Sentry POST itself fails"
    detection: "non-2xx from store endpoint → workflow log warning + job summary"
    alert_route: "GH Actions job log (degraded-permissive; does not red the report-only job)"
logs:
  where: "GitHub Actions run log for the live-verify job (tee'd RESULT + harness stdout); Sentry event"
  retention: "GH Actions default (90d); Sentry per project retention"
discoverability_test:
  command: "gh run view <run-id> --job live-verify --log  # AND Sentry API query tag gate:live-verify (no ssh)"
  expected_output: "a RESULT: line and a corresponding Sentry event with result tag"
```

## Domain Review

**Domains relevant:** Engineering, Product, Legal

### Engineering (CTO)

**Status:** carried from #5452 brainstorm + #5487 issue (CTO ruling 2026-06-17).
**Assessment:** GHA over Inngest for determinism/host-isolation/synchronous exit
code. Separate report-only job (not a deploy-job step) keeps the deploy job's
curl-only shape and concurrency intact; report-only enforced by topology
(nothing `needs:` it) + `continue-on-error`. The harness's setup needs (checkout,
bun, playwright chromium) are the load-bearing reason it is a separate job.

### Product (CPO) — sign-off required (single-user incident)

**Status:** required at plan time.
**Assessment:** The report-only-first posture is the lever (`wg-dark-launch-deploy-gates`);
the blocking flip is deliberately out of scope (#5463), gated on a real green PASS.
This matches the CPO brainstorm position (fail-closed gate is the lever; observe
a real PASS before flipping).

### Legal (CLO)

**Status:** carried from #5452 brainstorm.
**Assessment:** The synthetic-principal guardrails (UID-allowlist code gate,
redact-before-persist, ephemeral session) are unchanged by the re-home — they live
in `run.ts`/`redact.ts`, not in the substrate. The new surface is forwarding the
ALREADY-redacted RESULT line to Sentry; no new raw-capture persistence. No new
regulated-data surface introduced by this PR (no schema/migration/auth-flow edit).

### Product/UX Gate

**Tier:** none — no UI surface. The plan's `## Files to Edit`/`Create` contain only
a `.github/workflows/*.yml` and an ADR `.md`; no `components/**`, `app/**/page.tsx`,
or `app/**/layout.tsx`. NONE.

## Open Code-Review Overlap

None (verified `gh issue list --label code-review --state open` against the two
edited paths: `web-platform-release.yml`, `ADR-064-*.md`).

## Infrastructure (IaC)

Skip — no new infrastructure. The harness runs against already-provisioned prod
(deployed web-platform + prod Supabase); all secrets (`LIVE_VERIFY_*`,
`NEXT_PUBLIC_SUPABASE_*`, `NEXT_PUBLIC_SENTRY_DSN`, `DOPPLER_TOKEN_PRD`) already
exist in Doppler `prd` / as workflow secrets (provisioned by #5486/#5473 +
pre-existing release-workflow secrets). No new server, secret, vendor, or
persistent runtime process.

## Files to Edit

- `.github/workflows/web-platform-release.yml` — add the `live-verify:` job
  (checkout + Doppler CLI + setup-bun + bun install + playwright chromium +
  trigger-paths gate + report-only harness run + Sentry emit). Additive; the
  `deploy:` job is unchanged.
- `knowledge-base/engineering/architecture/decisions/ADR-064-live-production-verification-harness.md`
  — append the Inngest-rejected decision-of-record block to §Substrate.

## Files to Create

None. (No new script: the Sentry-emit is an inline `run:` block reusing the
`sentry-monitors-audit.sh` DSN-parse precedent; the harness already exists.)

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. (This section is filled; threshold = single-user incident.)
- **`run.ts` exits non-zero on FAIL/CANT-RUN/CONFIG** (process.exitCode = 1 at
  L521/L541/L547). `continue-on-error: true` on the harness step is mandatory, AND
  the job must be needed by nothing — either alone is insufficient if the other is
  later removed. Keep both; comment both.
- **`actionlint`, not `bash -n`, for the workflow YAML.** `bash -n web-platform-release.yml`
  parses the YAML header as bash and reports spurious errors. Validate embedded
  `run:` snippets separately with `bash -c '<snippet>'`.
- **Sentry DSN parse:** reuse the `sentry-monitors-audit.sh:159-182` parse (it
  handles `ingest.<region>.sentry.io` and bare `ingest.sentry.io` clusters); do NOT
  hand-roll a new DSN regex.
- **`workflow_dispatch` has no `github.event.before` SHA** for the changed-file
  diff. The gate must branch on `github.event_name`: on `workflow_dispatch`, skip
  the harness (the report-only signal targets real merges); never `git diff` against
  a zero-SHA.
- **The deploy-job poll-window drift assertion (L319-326) is in the `deploy:` job
  only.** The new `live-verify:` job does NOT inherit `deploy:` job env; do not
  reference `STATUS_POLL_*`/`HEALTH_POLL_*`/`IN_FLIGHT_CEILING_S` from it.
- **Playwright chromium on `ubuntu-latest`** needs `--with-deps` to install OS libs;
  a bare `playwright install chromium` may leave `chromium.launch()` failing on
  missing shared libs → a spurious `CANT-RUN:browser-launch:…`. Pin the same
  playwright version as `apps/web-platform/package.json` (1.58.2).
