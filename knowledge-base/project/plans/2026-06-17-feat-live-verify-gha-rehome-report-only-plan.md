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

## Enhancement Summary

**Deepened on:** 2026-06-17
**Review agents:** architecture-strategist, silent-failure-hunter
**Halt gates passed:** 4.6 User-Brand Impact, 4.7 Observability (5-field), 4.8 PAT-shaped (none), 4.9 UI-wireframe (no UI surface).

### Key improvements (all workflow-side; no `run.ts` change)
1. **Sentry-emit is a NEW integration, not precedent reuse** (arch P1): `sentry-monitors-audit.sh` only PARSES the DSN, never POSTs. Region-aware DSN→ingest-URL (no `us` default), public DSN key as `sentry_key`, bounded retry, fail-loud to `$GITHUB_STEP_SUMMARY` + `::error::`.
2. **Changed-file gate via GH compare API, not `git diff`** (arch P1 / SF F4): `fetch-depth:1` default makes `before..sha` error on the zero-SHA. Compare-API failure → `CANT-RUN:gate-diff-failed`, never a silent SKIPPED.
3. **`${PIPESTATUS[0]}` exit-code capture + `set +e` guard** (SF F1/F2): empty RESULT → `CANT-RUN:no-result-line:exit=<rc>` + redacted stderr tail; extraction + `$GITHUB_OUTPUT` write always run even on harness crash. "Failure cannot fail the job" and "failure still produces a recording" proven independently in Phase 4.
4. **Emit fail-closed on empty `result_line`; SKIPPED as a real `level=info` event** (SF F3/F5) so the post-merge AC's events-API query has a queryable denominator.
5. **ADR-064 amendment restates the C4 edge driver** as the release workflow (arch P2).

### New considerations
- No P0 findings; the report-only-by-topology decision and separate-job decision were validated as architecturally correct. All P1/HIGH findings were in supporting mechanisms (Sentry emit + changed-file gate) that directly threaten the dark-launch signal integrity — folded in above.

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
edge's endpoints. The amendment MUST explicitly restate the edge's **driver** as
the `web-platform-release.yml` release workflow (architecture-review P2 — otherwise
ADR-064 §C4 keeps describing a driver, the agent skill, that no longer owns the
edge). No `.c4` model file edit is required (the edge endpoints are unchanged).

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
  6. **Trigger-paths gate** (`id: gate`): compute changed files for the push via
     the **GH compare API as the PRIMARY mechanism** —
     `gh api repos/${{ github.repository }}/compare/${{ github.event.before }}...${{ github.sha }} --jq '.files[].filename'`
     — NOT a local `git diff`. (Per architecture-review P1: `actions/checkout`
     defaults to `fetch-depth: 1`; `git diff ${{ github.event.before }}..${{ github.sha }}`
     errors on the zero-SHA / shallow-graph case — the repo's other changed-file
     workflows all set `fetch-depth: 0` to avoid this. The compare API needs no
     local history.) Strip `trigger-paths.txt` comments/blanks, `grep -qE -f`; set
     `triggered=0|1` as a step output. **Three distinct outcomes (never collapse them):**
     - changed-file set computed AND no pattern matches → `triggered=0`, record
       `SKIPPED:no-triggering-paths`, skip the harness (legitimate fail-open,
       matches the `trigger-paths.txt` header posture).
     - changed-file set computed AND a pattern matches → `triggered=1`.
     - compare API call **failed** (rate-limit / 5xx / zero-SHA on first push) →
       record `CANT-RUN:gate-diff-failed`, set `triggered=0` BUT mark a separate
       `gate_failed=1` output so step 8 emits it as a real CANT-RUN event, NOT a
       silent SKIPPED (silent-failure-hunter F4: a broken diff must not masquerade
       as an intentional skip).
  7. **Run harness** (`id: harness`, `if: steps.gate.outputs.triggered == '1'`,
     `continue-on-error: true`): run under explicit shell handling so `set -e`
     CANNOT abort the extraction before the output is set (silent-failure-hunter
     F1/F2):
     ```bash
     set +e
     cd apps/web-platform
     doppler run -c prd -- bun run scripts/live-verify/run.ts 2>&1 | tee /tmp/live-verify.out
     rc=${PIPESTATUS[0]}          # bun's exit code, NOT tee's — pipefail-safe
     set -e
     RESULT_LINE=$(grep -E '^RESULT: ' /tmp/live-verify.out | tail -1)
     if [ -z "$RESULT_LINE" ]; then
       TAIL=$(tail -5 /tmp/live-verify.out | tr '\n' ' ')
       RESULT_LINE="RESULT: CANT-RUN:no-result-line:exit=$rc — $TAIL"  # already-redacted stdout
     fi
     echo "result_line=$RESULT_LINE" >> "$GITHUB_OUTPUT"
     echo "rc=$rc" >> "$GITHUB_OUTPUT"
     ```
     `env: DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN_PRD }}`. The empty-RESULT case
     embeds the **process exit code + a stderr tail** so a hard harness/runner/Doppler
     crash is diagnosable, NOT flattened into a bare `CANT-RUN:no-result-line`
     (silent-failure-hunter F1). The `tee` output is already `redact()`-scrubbed
     only for the harness's own RESULT line; the stderr `TAIL` could carry an
     unredacted node stack — re-`redact()` the TAIL via a `bun run -e` one-liner
     calling `redact.ts`, OR cap to the error *name/message* class only. (Decision:
     pipe the TAIL through `redact` before embedding — the redact module is already
     imported in the harness dir.)
  8. **Emit to Sentry** (`if: always() && (steps.gate.outputs.triggered == '1' || steps.gate.outputs.gate_failed == '1' || steps.gate.outputs.triggered == '0')`):
     POST the result as a **real Sentry event** (NOT a breadcrumb — a bare
     breadcrumb is not queryable via the events API, which the post-merge AC relies
     on; silent-failure-hunter F5) to the `store` endpoint derived from
     `NEXT_PUBLIC_SENTRY_DSN`, tagged `gate=live-verify`, `component=web-platform`,
     `result=<PASS|FAIL|CANT-RUN|SKIPPED>`. **Fail-closed on empty:** if
     `steps.harness.outputs.result_line` is empty but the harness ran, POST
     `result=CANT-RUN:no-result-line` at `level=error` with `steps.harness.outcome`
     + `rc` embedded — never POST a blank message (silent-failure-hunter F3). Level
     mapping: FAIL → `level=error`; CANT-RUN → `level=warning` (gate-diff-failed and
     no-result-line → `level=error` since they hide a real failure); SKIPPED →
     `level=info` (queryable "ran, skipped intentionally" — gives the #5463 soak a
     denominator). `env: NEXT_PUBLIC_SENTRY_DSN: ${{ secrets.NEXT_PUBLIC_SENTRY_DSN }}`.

**Report-only invariant (load-bearing):** the deploy is gated by
`needs: [release, migrate, verify-migrations, verify-doppler-secrets, await-ci]`
(L256). `live-verify:` is NOT in any job's `needs:`, so by construction it cannot
gate the deploy or roll it back. This is stronger than `continue-on-error` alone.

### Phase 2 — Sentry emit helper (workflow `run:` block) — NEW outbound integration

**This is a net-new outbound integration pattern, not a precedent reuse**
(architecture-review P1). `sentry-monitors-audit.sh:159-182` only PARSES the DSN
into `dsn_org_id`/`dsn_cluster` for a residency-match assertion — it never
constructs an ingest URL and never POSTs an event. No existing workflow POSTs an
arbitrary event to Sentry. Treat this as a component with its own contract:

- **DSN → ingest URL (region-aware).** `NEXT_PUBLIC_SENTRY_DSN` is the public
  CLIENT DSN (`https://<public_key>@<host>/<project_id>`, where `<host>` is e.g.
  `o123.ingest.de.sentry.io` or `o123.ingest.us.sentry.io`). The POST host MUST be
  the DSN's own `<host>` (carry the region segment through — do NOT default to `us`
  the way the audit script's parse does on an unset DSN, or the event lands in the
  wrong cluster and silently 4xx's). Build `https://<host>/api/<project_id>/store/`.
  `sentry_key` in the auth header is the DSN's PUBLIC key (the `<public_key>` before
  `@`) — NOT the org-scoped audit token used by `sentry-monitors-audit.sh` (a
  different credential). Reuse only the DSN-SPLIT shape from that script's parse
  (and its `{ … || true; }` `set -e` guards), not its cluster-defaulting logic.
- POST a minimal JSON event `{message: <result_line>, level, platform:"other",
  tags:{gate:"live-verify", component:"web-platform", result:<tri-state>}}` with
  header `X-Sentry-Auth: Sentry sentry_version=7, sentry_key=<public_key>`,
  `--max-time 10`, with a **bounded 2-3 attempt retry** (this is the primary
  observability surface feeding #5463; one-shot delivery is too thin).
- **Fail-loud-to-secondary (not silent).** A non-2xx / timeout does NOT red the
  report-only job, BUT it MUST surface as a `::error::` workflow annotation AND a
  line in `$GITHUB_STEP_SUMMARY` (per `cq-silent-fallback-must-mirror-to-sentry`
  spirit: here Sentry IS the mirror target, so a Sentry-POST failure must surface
  on the run-summary page without expanding raw logs — silent-failure-hunter F6).
  A buried stdout warning is invisible.

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
  mechanisms — (a) topology: NO other job lists `live-verify` in its `needs:` array
  (assert by inspecting each job's `needs:`, not a raw substring `grep -c` which
  also matches comments — architecture-review P2); (b) step-level: the harness step
  has `continue-on-error: true`. Add a one-line comment in the workflow citing both.
- **Failure-still-produces-a-recording proof** (silent-failure-hunter F2/F3 — the
  ACTUAL observability invariant, distinct from "failure cannot fail the job"):
  `bash -c` a stub that exits non-zero in place of the harness and confirm (i) the
  `result_line` step output is still populated (the `set +e` + `${PIPESTATUS[0]}`
  guard runs the extraction), and (ii) the emit step would POST a non-empty
  `result` tag (fail-closed to `CANT-RUN:no-result-line:exit=<rc>` at `level=error`).
- Confirm the `deploy:` job's `if:` (L265-273) and `needs:` (L256) are UNCHANGED
  (diff is additive only).

## Acceptance Criteria

### Pre-merge (PR)

- [x] A `live-verify:` job is added to `web-platform-release.yml` with
  `needs: [deploy]`, `runs-on: ubuntu-latest`, gated on `github.event_name == 'push'`,
  and **no other job `needs:` it** (`grep -c 'needs:.*live-verify' web-platform-release.yml` = 0).
- [x] The harness step carries `continue-on-error: true`
  (`grep -A12 'id: harness' web-platform-release.yml | grep -q 'continue-on-error: true'`).
- [x] The harness runs `doppler run -c prd -- bun run scripts/live-verify/run.ts`
  from `apps/web-platform`, with `LIVE_VERIFY_BROWSER_CHANNEL`/`LIVE_VERIFY_BROWSER_PATH`
  NEVER set in the job (`! grep -qE 'LIVE_VERIFY_BROWSER_(CHANNEL|PATH)' web-platform-release.yml`).
- [x] Job runs the trigger-paths gate against `trigger-paths.txt`
  (`grep -q 'trigger-paths.txt' web-platform-release.yml`) via the **GH compare
  API** (not local `git diff` — no `git diff .*\.\..*github\.sha` form in the job);
  on no match it records `SKIPPED:no-triggering-paths` and the harness does not run;
  on a compare-API failure it records `CANT-RUN:gate-diff-failed` (NOT a silent SKIPPED).
- [x] The harness step captures `${PIPESTATUS[0]}` (`grep -q 'PIPESTATUS' web-platform-release.yml`)
  and on an empty RESULT emits `CANT-RUN:no-result-line:exit=<rc>` with a redacted
  stderr tail — a hard harness/runner/Doppler crash is diagnosable, not flattened.
- [x] A Sentry-emit step POSTs the redacted result line as a REAL event (not a
  breadcrumb) using `secrets.NEXT_PUBLIC_SENTRY_DSN`, region-aware host derived from
  the DSN (no hardcoded cluster), tagged `gate=live-verify` + tri-state `result`,
  with `if: always()` so a FAIL/CANT-RUN still emits; fail-closed to
  `result=CANT-RUN:no-result-line` (level=error) when `result_line` is empty.
  Reachable without SSH.
- [x] SKIPPED is emitted as a real `level=info` event (queryable denominator for
  the #5463 soak); a non-2xx Sentry POST surfaces via `::error::` + `$GITHUB_STEP_SUMMARY`
  (does not red the report-only job).
- [x] `actionlint .github/workflows/web-platform-release.yml` passes (0 errors).
- [x] The `deploy:` job's `needs:` (L256) and `if:` (L265-273) are byte-for-byte
  unchanged in the diff (additive-only change).
- [x] ADR-064 §Substrate contains the
  `### Inngest re-home considered and rejected (2026-06-17)` block
  (`grep -q 'Inngest re-home considered and rejected' ADR-064-*.md`).

 (observation — feeds #5463)

- [ ] On the first real qualifying deploy post-merge (a merge touching a
  `trigger-paths.txt` surface), the `live-verify:` job runs and emits a correct
  `PASS`/`FAIL`/`CANT-RUN` Sentry event, recorded on #5463 as the dark-launch
  observation toward the blocking flip. **Automation:** verify via Sentry API query
  (`gate:live-verify` events) per `hr-no-dashboard-eyeball-pull-data-yourself`;
  not an operator dashboard-eyeball step.

## Observability

```yaml
liveness_signal:
  what: "live-verify RESULT Sentry event per push to main — PASS|FAIL|CANT-RUN when a trigger-paths surface changed, SKIPPED (level=info) otherwise; every push produces exactly one queryable event"
  cadence: "per push to main (SKIPPED when no trigger-paths.txt surface changed)"
  alert_target: "Sentry (tag gate=live-verify); FAIL emitted at level=error"
  configured_in: ".github/workflows/web-platform-release.yml live-verify job, Sentry-emit step"
error_reporting:
  destination: "Sentry (region-aware host from NEXT_PUBLIC_SENTRY_DSN) store endpoint; $GITHUB_STEP_SUMMARY + ::error:: annotation as secondary"
  fail_loud: "FAIL → level=error; CANT-RUN(browser/config/teardown) → level=warning; no-result-line:exit=<rc> + gate-diff-failed → level=error (hide a real failure); empty result_line → fail-closed CANT-RUN:no-result-line level=error (never a blank event)"
failure_modes:
  - mode: "harness FAIL (rail regression)"
    detection: "RESULT: FAIL line → Sentry level=error"
    alert_route: "Sentry gate=live-verify result=FAIL"
  - mode: "harness hard crash / Doppler-auth / runner OOM (no RESULT line)"
    detection: "${PIPESTATUS[0]} non-zero + empty RESULT → CANT-RUN:no-result-line:exit=<rc> + redacted stderr tail → Sentry level=error"
    alert_route: "Sentry gate=live-verify result=CANT-RUN (exit code embedded — distinguishes crash from clean pre-launch gate)"
  - mode: "changed-file gate computation fails (zero-SHA / compare-API 5xx)"
    detection: "gate_failed=1 → CANT-RUN:gate-diff-failed (NOT a silent SKIPPED) → Sentry level=warning"
    alert_route: "Sentry gate=live-verify result=CANT-RUN"
  - mode: "Sentry POST itself fails"
    detection: "non-2xx / timeout (after bounded retry) → ::error:: annotation + $GITHUB_STEP_SUMMARY line"
    alert_route: "GH Actions run summary page (degraded-permissive; does not red the report-only job)"
logs:
  where: "GitHub Actions run log for the live-verify job (tee'd RESULT + harness stdout); Sentry event"
  retention: "GH Actions default (90d); Sentry per project retention"
discoverability_test:
  command: "grep -cE '^  live-verify:' .github/workflows/web-platform-release.yml"
  expected_output: "1"
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
- **`cmd | tee` exit code is `tee`'s, not the harness's.** Under `set -o pipefail`
  the pipe returns the harness's non-zero (which aborts the step under `set -e`
  BEFORE the RESULT extraction); without `pipefail` it returns `tee`'s 0 (masking a
  `bun`/Doppler crash as green). BOTH are wrong. Use `set +e` around the run +
  `rc=${PIPESTATUS[0]}` (NOT `$?` after the pipe), then `set -e`, so the extraction
  + `$GITHUB_OUTPUT` write ALWAYS execute. "Failure cannot fail the job" (topology +
  `continue-on-error`) is a DIFFERENT invariant from "failure still produces a
  recording" — Phase 4 must prove both independently.
- **Sentry-emit is a NEW integration, not a precedent reuse.** `sentry-monitors-audit.sh`
  only PARSES the DSN for a residency assertion — it never POSTs. Carry the DSN's
  region segment (`ingest.<region>.sentry.io`) into the POST host; do NOT default to
  `us` (the audit script's parse does, which would silently 4xx an event into the
  wrong cluster). `sentry_key` = the DSN's PUBLIC key, not the org audit token.
- **Empty stdout collapses distinct failure classes.** A Doppler-auth failure, a
  missing `bun install`, a runner OOM, and a chromium hard-crash all produce NO
  RESULT line — embed `${PIPESTATUS[0]}` + a redacted stderr tail in
  `CANT-RUN:no-result-line:exit=<rc>` so the #5463 observer can tell "the prod
  secret store rejected us" from "a rail regressed".
- **SKIPPED must be a real `level=info` Sentry EVENT, not a breadcrumb.** A bare
  breadcrumb is not queryable via the events API the post-merge AC + `discoverability_test`
  rely on. Most merges will SKIP (non-realtime surfaces) — without a queryable
  SKIPPED event, "ran and skipped" is indistinguishable from "never ran" (the
  dark-signal ambiguity #5463 must not inherit).
- **Changed-file gate: GH compare API, not `git diff`.** `actions/checkout` defaults
  to `fetch-depth: 1`; `git diff ${{ github.event.before }}..${{ github.sha }}`
  errors on the zero-SHA (first push / force-push / dispatch). Use
  `gh api repos/.../compare/<before>...<sha>` (no local history needed). A
  compare-API failure → `CANT-RUN:gate-diff-failed`, NEVER a silent SKIPPED.
