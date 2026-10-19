---
title: "feat: /sys sandbox denyRead + report-only cross-workspace isolation canary probe"
type: feat
date: 2026-10-09
slug: sys-denyread-isolation-deploy-gate
branch: feat-one-shot-1285-2640-sys-denyread-deploy-gate
issue: 2640
closes: [1285, 2640]
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
lane: cross-domain
---

# feat: /sys sandbox denyRead + report-only cross-workspace isolation canary probe

## Enhancement Summary

**Deepened on:** 2026-10-09
**Sections enhanced:** Observability (probe contract), Guard Contract (lint-verified), Encryption Posture (new), Risks (Network-Outage Deep-Dive), Files to Edit (baseline-probe bump), Implementation Phases (soak accumulation, followthrough shape, markdownlint)
**Research agents used:** none — `Reviewed-Coverage: sequential-fallback` (this deepen ran inside a Task subagent with no subagent-spawn tool; all gates were executed mechanically and sequentially in-process)

### Key Improvements

1. `write_workspace_isolation_state` now spec'd to accumulate `consecutive_pass`/`first_pass_at` — found by reading the sibling `canary-promotion-5875.sh` probe, which is only a stateless GET because `write_sandbox_canary_state` maintains the counter.
2. `BASELINE_DECLARED_PROBES` bump added (the `credentials_required` declaration moves the repo-global corpus ratchet).
3. `discoverability_test.command` de-shellified to survive Check 10's byte-level reject.
4. Encryption Posture + Network-Outage Deep-Dive added; a fabricated `hr-*` citation was corrected to `wg-dark-launch-deploy-gates` (caught by the rule-ID registry check).

### New Considerations Discovered

- The deploy-order coupling window (script delivered before vitest image) is handled by the `canary_infra_error` classification; the Network-Outage deep-dive confirmed non-delivery reads as field-absence, never a false green.
- `follow-through` label verified live (`gh label list`).

### Gate Record (deepen-plan 4.5–4.12, run mechanically)

- 4.5 network-outage: FIRED on the resource-shape trigger (`deploy_pipeline_fix` SSH provisioners) → Deep-Dive subsection emitted.
- 4.55 downtime halt: not triggered — no infra reboot/replace, no DDL, no request-dropping change (canary→prod swap unchanged).
- 4.6 user-brand impact: PASS (threshold `single-user incident`, concrete content).
- 4.7 observability: PASS (5-field schema; `curl` verb allowlisted; literal `expected_output`; non-placeholder `credentials_required`).
- 4.8 PAT sweep: PASS (clean).
- 4.9 UI wireframe: not triggered (no UI-surface files).
- 4.10 encryption posture: FIRED (new persistent state file) → section added.
- 4.11 guard contract: PASS (`lint-guard-contract.py` — 3 guards, structural assemblies, ≥3-row mutation matrices).
- 4.12 scope check: PASS (Ask Mapping/Provenance/Split Assessment present; no unmapped rows; `Recommendation:` present).

## Overview

Two related security-hardening items land in one PR:

- **#1285** — add `"/sys"` to the agent-sandbox `denyRead` constant so the realized bwrap namespace masks the `/sys` pseudo-filesystem (MAC addresses, CPU topology, kernel parameters), consistent with the `/proc` defense-in-depth precedent (#1047 / PR #1282).
- **#2640** — promote `apps/web-platform/test/sandbox-isolation.test.ts` (merged by PR #2610) into a **deploy-time canary probe**: the runner image gains a pinned vitest, `ci-deploy.sh` runs the deterministic direct-bwrap tier inside the canary container between the existing sandbox probes and the prod swap, and the verdict is recorded to deploy-state and surfaced on `/hooks/deploy-status`.

Per `wg-dark-launch-deploy-gates`, the probe ships **report-only** — it runs, logs, writes state, and pages Sentry on a red verdict, but never rolls back — and is promoted to blocking in a separate change only after it is observed passing on at least one real deploy. The gate-vs-report decision is recorded in the design note (issue #2640 AC 1), which is what the issue's "deploy-GATE vs deploy-REPORT" open question resolves to.

## Problem Statement / Motivation

- `/sys` leaks host topology into the sandbox. The tool-layer check (`isPathInWorkspace`) and the default mount set already limit exposure, but the SDK's realized argv `--ro-bind`s `/` — so `/sys` IS visible inside the agent sandbox today, and nothing masks it at the OS layer. `/proc` got the same treatment in #1047; `/sys` was explicitly scoped out and tracked as #1285 (security-sentinel P3).
- The cross-workspace isolation suite only runs in the test matrix. A sandbox regression that builds green (e.g., a Dockerfile/SDK drift that weakens the mount set) currently deploys unmeasured; the deploy pipeline is the last point where the *real image* can be exercised before it serves tenants. The faithful-canary precedent (#5875 / ADR-079) shows the value of measuring the loaded profile inside the canary — but that probe replays one captured argv; it does not exercise cross-workspace data isolation with sibling trees.

## Proposed Solution

1. **`/sys` deny** — append `"/sys"` to the constant deny set in `buildAgentSandboxConfig` (`apps/web-platform/server/agent-runner-sandbox-config.ts`, `denyRead` construction immediately after `"/proc"`), keeping `denyReadExtra` last. Update the literal `toEqual` pins in `agent-sandbox-tenant-deny.test.ts` and `agent-runner-helpers.test.ts`. No shim change: the `/sys` tmpfs landing is not re-bound by the vendored builder's `enableWeakerNestedSandbox` tail (that tail re-binds only `/proc`), so the mask is realized, not intent-only.
2. **vitest in the runner image** — `npm install -g vitest@4.1.11 --before=<pin-date> --ignore-scripts` in the existing `cli-tools` stage (the stage that already carries the `claude-code` and `likec4` global installs), plus a three-file test payload (`test/sandbox-isolation.test.ts`, `test/helpers/sandbox-isolation-fixtures.ts`, new `test/vitest.canary.config.ts`) COPYed from `builder` and re-included via exact-path `.dockerignore` bangs. Single image: the canary still runs `VERIFIED_REF`, so the probe measures the exact artifact prod will run, and the sign/push/verify/freshness machinery is untouched.
3. **Report-only deploy probe** — `run_workspace_isolation_probe` in `ci-deploy.sh`, called with `|| true` immediately after `run_faithful_sandbox_canary || true` inside the `CANARY_HEALTHY` branch: `timeout <cap> docker exec -w /app -e SOLEUR_ISOLATION_TEST_HOST=1 -e SOLEUR_ISOLATION_TIERS=direct soleur-web-platform-canary /usr/local/bin/vitest run --config test/vitest.canary.config.ts`, with docker-exec rc classification mirroring `run_faithful_sandbox_canary` (125/126/127 → `canary_infra_error`; 124 via host `timeout` → `workspace_isolation_timeout`; other non-zero → `workspace_isolation_failed`; 0 → `pass`). Verdict persists to a new `/mnt/data/ci-deploy-workspace-isolation.json` via `write_workspace_isolation_state`, is surfaced by `cat-deploy-state.sh` as `.workspace_isolation`, logs a `WORKSPACE_ISOLATION:` journald line on every run, and Sentry-pages on `workspace_isolation_failed`/`workspace_isolation_timeout` only. The state file ALSO accumulates `consecutive_pass` (increments on `pass`, resets on `workspace_isolation_failed`/`workspace_isolation_timeout`, holds on `canary_infra_error`) and `first_pass_at`, exactly as `write_sandbox_canary_state` does — that on-host accumulation is what lets the promotion probe be a stateless GET.
4. **Suite tier knob** — `SOLEUR_ISOLATION_TIERS` env filter in `sandbox-isolation.test.ts` so the canary runs only the deterministic direct-bwrap tier; the query tier (live `ANTHROPIC_API_KEY`, present in the canary's env) and FR9 (needs `ANTHROPIC_ISOLATION_TEST_OK`) stay out of the deploy path.
5. **Promotion tracking** — committed `scripts/followthroughs/workspace-isolation-verdict-2640.sh` (modeled verbatim on `canary-promotion-5875.sh`: HMAC + CF-Access GET of `/hooks/deploy-status`, reads `.workspace_isolation`) so the promotion issue can carry the `<!-- soleur:followthrough … -->` directive; blocking promotion itself is a Non-Goal of this PR.

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 1285` / `gh issue view 2640`: both **OPEN**, no `closedByPullRequestsReferences`. Premise fresh.
- PR #1282 MERGED (added `/proc` — diff touched `apps/web-platform/server/agent-runner.ts` + `test/sandbox-hook.test.ts` at that time); #1047 CLOSED; PR #2610 MERGED (the isolation suite); #1450 CLOSED.
- All cited paths exist on `origin/main`: `agent-runner.ts`, `test/sandbox-isolation.test.ts`, `Dockerfile`, `infra/ci-deploy.sh`, `infra/ci-deploy.test.sh`.
- **Stale references reconciled below** (agent-runner.ts deny site moved; #2640 line numbers stale).
- ADR corpus grep for the proposed mechanisms: ADR-079 (faithful canary dark-launch — the pattern this plan mirrors), ADR-272 (credential deny — warns that sandbox-flag changes need the runtime re-measurement test), ADR-272/ADR-075 context in `agent-runner-sandbox-config.ts` comments, ADR-122 (boot-time delivery of sandbox controls). No ADR rejects a `/sys` deny or a canary isolation probe; the faithful canary is the established arc this extends.
- `hr-verify-repo-capability-claim-before-assert`: verified `vitest --config <path>` exists (local `./node_modules/.bin/vitest --help`, vitest 4.1.11); verified `/hooks/deploy-status` is HMAC + CF-Access gated (`infra/hooks.json.tmpl`, `web-platform-release.yml` curl with `X-Signature-256`); verified canary runs `VERIFIED_REF` (`ci-deploy.sh` `docker run … "$VERIFIED_REF"`); verified `test/` is `.dockerignore`d with an exact-path `!` re-include convention.
- Verified `scripts/followthroughs/canary-promotion-5875.sh` exists and is the exact promotion-probe template (`.sandbox_canary.consecutive_pass`/`first_pass_at` read via HMAC+CF GET of `/hooks/deploy-status`, `WEBHOOK_DEPLOY_SECRET`/`CF_ACCESS_*` already wired in the sweeper `env:` block at `scheduled-followthrough-sweeper.yml`); `BASELINE_DECLARED_PROBES = 50` at `preflight-discoverability-test.test.ts:2858` — a `credentials_required` declaration in this plan moves that corpus count and the bump lands in the same PR.

### Sharp edges applied (Phase 6.5)

- `discoverability_test.command` carries no `|`/`;`/`&`/`<`/`>`/`$`/backtick bytes (Check 10's reject is a byte-level token match) — command is a plain `curl` to the probe URL; `credentials_required` SKIP-DECLAREDs execution.
- `credentials_required` declaration → `BASELINE_DECLARED_PROBES` bump task added (the gate is repo-global; no file-scoped suite reaches it).
- Test-runner gate: runner is vitest (`package.json scripts.test` = `vitest`); new files land under `test/**/*.test.ts` matching the unit project's include glob; `test/vitest.canary.config.ts` is under `test/`, not the context root, so `docker-context-import-containment.test.ts` does not enumerate it.
- Knowledge-base path sweep run at plan-write time: the only non-existent `knowledge-base/*.md` reference is the design note this plan creates.
- `wg-dark-launch-deploy-gates` + the faithful-canary soak precedent: state accumulates `consecutive_pass`/`first_pass_at` on the host so the promotion probe is a stateless GET — a probe keyed on state that doesn't exist is a non-starter (#6604-class "guard reads a fact no writer produces").
- markdownlint gate added to Phase 4 (plan body is linted by lefthook at work-phase first commit).

### Property List (Phase 0.6b)

| # | Property |
|---|----------|
| P1 | `/sys` is unreadable by processes inside the agent bwrap sandbox (OS-layer defense-in-depth alongside the tool-layer path check). |
| P2 | Every canary-phase web-platform deploy runs the direct-tier cross-workspace isolation suite inside the canary container and records a classified verdict — without being able to roll back the deploy (dark-launch). |
| P3 | The verdict is observable without SSH: deploy-state JSON surfaced on `/hooks/deploy-status`, a journald line per run, and a Sentry page on red verdicts. |
| P4 | Blocking promotion happens only after the probe is observed passing on ≥1 real deploy (`wg-dark-launch-deploy-gates`), via a tracked follow-through. |

### Cut List (Phase 0.6b)

| Proposed mechanism | Property | Verdict |
|---|---|---|
| `"/sys"` in `denyRead` | P1 | keep — the ask names it and no existing OS-layer entry covers `/sys` (`isPathInWorkspace` is tool-layer; the realized argv ro-binds `/`, so the tmpfs is a real mask) |
| vitest in runner image | P2 | keep — the suite's runner must exist inside the canary container; no substitute (host has no node; `npx` is egress-blocked in prod) |
| `run_workspace_isolation_probe` + state/Sentry wiring | P2, P3 | keep — `run_faithful_sandbox_canary` replays one captured argv and cannot exercise cross-workspace data isolation; it is the template, not the mechanism |
| `SOLEUR_ISOLATION_TIERS` knob | P2 | keep — without it the query tier would fire live Anthropic API calls during the deploy window (canary env carries `ANTHROPIC_API_KEY`); a `-t` name filter is rename-fragile |
| `vitest.canary.config.ts` | P2 | keep — the repo `vitest.config.ts` loads `globalSetup` and project setup files that are `.dockerignore`d out of the image |
| blocking promotion flip | P4 | cut from this PR — report-only first per `wg-dark-launch-deploy-gates`; tracked via follow-through enrollment |

### Repo findings

- `denyRead` is built in `buildAgentSandboxConfig` (`apps/web-platform/server/agent-runner-sandbox-config.ts`, the `denyRead` const) — NOT `agent-runner.ts` (stale site in #1285; the config was extracted after PR #1282). Consumers: `agent-runner-query-options.ts` and `cc-dispatcher.ts`, both via the shared helper — one chokepoint.
- Literal-equality pins to update: `test/agent-sandbox-tenant-deny.test.ts` (≈7 `toEqual([root, "/var/lib/soleur/worktrees", staging, "/proc"])` sites) and `test/agent-runner-helpers.test.ts` (≈5 `toEqual` sites + `toContain("/proc")` rows). Mock `denyRead` arrays in `cc-dispatcher-*.test.ts` are inputs, not assertions — optional consistency touch.
- Captured-argv fixture (`infra/sandbox-canary-argv.json`) shows `--ro-bind / /` then `--tmpfs /proc` then the tail `--bind /proc /proc`: confirms `/sys` is reachable today and that a `/sys` tmpfs lands as a real mask (nothing re-binds `/sys`). The fixture is a captured artifact; the next SDK-bump re-capture (`scripts/sdk-bump-sandbox-gate.sh`) will diff in `--tmpfs /sys` — expected, not a defect.
- `ci-deploy.sh` (4481 lines): `run_faithful_sandbox_canary` (~line 2573) is the report-only template (state write → `cat-deploy-state.sh` → Sentry-on-FAIL-only, `|| true` call site ~line 4067 inside the `CANARY_HEALTHY` block, before `github_app_key_canary_check` and the swap at ~line 4075). `ci-deploy.sh` reaches existing hosts via `apply-deploy-pipeline-fix.yml` (paths-filtered), so the new script can precede the first vitest-carrying image — infra-error classification makes that window benign by design.
- `.dockerignore` prunes `test/`; exact-path `!` bangs are the established re-include convention (`test/docker-context-import-containment.test.ts` guards config-import parity — unaffected since new files aren't imported by context-root configs).
- `probeSkip` (`test/helpers/sandbox-isolation-fixtures.ts`): direct tier needs `bwrap` + `socat` (both in the runner image); `SOLEUR_ISOLATION_TEST_HOST=1` converts a silent skip into a throw — set in the canary exec. Query tier needs `ANTHROPIC_API_KEY` — present in the canary env — hence the tier knob.
- `sandbox-credential-deny-runtime.test.ts` measures the runtime deny outcome inside real bwrap (control vs treatment) — the re-measurement the config comment demands after a sandbox-flag change; it runs in the existing suite.
- `probeSkip`/fixtures use `os.tmpdir()` (canary `/tmp` is a tmpfs mount — writable, cleaned with the container); `/workspaces` is only used when the `.soleur-fixture-root` sentinel exists (absent in the canary → no tenant-volume writes).
- `ci-deploy.test.sh` mock-docker: specialized exec arms (github-app-key-probe at the top of `create_docker_mock`) record to a `MOCK_*_LOG` without a `DOCKER_TRACE` line — the shape for the vitest arm; `assert_canary_trace_order` expects `image|pull|stop|rm|run|exec|stop|rm|stop|rm|ps|run` — output-captured execs don't reach the trace, so a captured probe keeps existing traces stable.
- Open code-review issues touching planned files: #3053 (plugin-seed empty-mount window in ci-deploy.sh) — different concern, **acknowledge** (see `## Open Code-Review Overlap`).

### Learnings applied

- `wg-dark-launch-deploy-gates` (#4932/#4941): new deploy-gating checks ship non-blocking and are observed on a real deploy first — drives the report-only shape and the infra-vs-verdict classification.
- `2026-10-01-docker-exec-pdeathsig-race-sigkills-bwrap-probe.md`: `--die-with-parent` is absent from the synthetic probe; not applicable to the vitest exec, but the classification-by-exit-code lesson is.
- `hr-all-infrastructure-provisioning-servers` / `hr-no-ssh-fallback-in-runbooks`: no manual provisioning steps; host delivery of `ci-deploy.sh` is the existing `apply-deploy-pipeline-fix.yml` path.
- The `cli-tools` stage comment documents the `npm install -g <pkg>@<pin> --before=<date> --ignore-scripts` convention used for `likec4` — mirrored for vitest, with a pin-consistency test (the `playwright-mcp-version-pin`/`claude-cli-pin-knows-models` precedent).

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Codebase reality | Plan response |
|---|---|---|
| #1285: "add `/sys` to `denyRead` array in `apps/web-platform/server/agent-runner.ts`" | `denyRead` is constructed in `buildAgentSandboxConfig` in `apps/web-platform/server/agent-runner-sandbox-config.ts` (extracted post-#1282); `agent-runner.ts` has no `denyRead` | Edit the constant set in `agent-runner-sandbox-config.ts`; update the two literal-pin test files |
| #2640: "bwrap-minimum probe (line 284) … canary→prod swap (line 298)" | `ci-deploy.sh` is now 4481 lines; the bwrap probe is ~line 3999, the faithful canary ~line 4067, the swap ~line 4075 | Insert the probe immediately after `run_faithful_sandbox_canary || true` — preserves the issue's ordering intent |
| #2640 snippet: `final_write_state 1 "canary_isolation_failed"; exit 1` (blocking) | `wg-dark-launch-deploy-gates` requires non-blocking-first for any new deploy-gating check | Ship report-only (`|| true`, classified verdict, page on red); blocking promotion is a tracked Non-Goal |
| #2640 option list for vitest (surgical copy / canary-only layer / Dockerfile.canary) | Canary runs `VERIFIED_REF` — the same verified digest as prod; a second image doubles sign/verify/freshness surface | Fourth option: global `vitest` install in the existing `cli-tools` stage of the SAME image — zero pipeline wiring, canary still measures the prod artifact |
| #2640: run `test/sandbox-isolation.test.ts` wholesale | The query tier makes live Anthropic API calls (canary env carries `ANTHROPIC_API_KEY`); repo `vitest.config.ts` needs files pruned from the image | `SOLEUR_ISOLATION_TIERS=direct` + dedicated minimal `vitest.canary.config.ts` |

## Technical Considerations

- **Architecture:** single-image strategy keeps `canary == prod` (`VERIFIED_REF`), so the probe measures the artifact that will serve tenants; no new image means cosign/zot/freshness machinery untouched.
- **Security:** `/sys` lands as a `--tmpfs` mask under `--ro-bind / /`; unlike `/proc` nothing re-binds it after the deny entries, so it is effective immediately. Masking `/sys` also hides `/sys/fs/cgroup` inside the sandbox — sandboxed subprocesses (e.g., a Node child) size resources to host totals rather than container limits; the kernel cgroup still enforces, so this is a heap-sizing behavior change, not an isolation break. Recorded as an accepted trade-off in the design note.
- **Image size:** `npm install -g vitest` adds vitest + its tree (~vitest→vite→esbuild chain) to the runner image; the delta is measured at build time and noted in the PR body (issue AC). The `--before` bound matches the `likec4` convention; transitive deps float within the bound — accepted for a canary-only tool, and the report-only window absorbs behavioral drift risk.
- **Container runtime details:** `docker exec` inherits image `USER soleur`; `/app/node_modules` is root-owned, so `vitest.canary.config.ts` sets `cacheDir: "/tmp/vitest-cache"` (canary `/tmp` is a writable tmpfs). `-w /app` makes the vitest root `/app` so `test/sandbox-isolation.test.ts` resolves.
- **NFR:** probe adds ≤ ~5 min worst-case to the deploy (host `timeout` cap); observed suite runtime for the direct tier is seconds–low-tens-of-seconds on a capable host.

### Attack Surface Enumeration

- Agent file-read vectors: (a) tool-layer `Read`/`Grep`/`Glob` gated by `isPathInWorkspace` — unchanged; (b) `Bash` inside bwrap — `/sys` now masked at the mount layer by this change; (c) `/proc/<pid>/environ` — masked by the shim's pidns-scoped `--proc` tail splice (#9723), unchanged; (d) symlink escapes — `linkEscape`/realpath handling, unchanged; (e) support-persona `denyReadExtra` — additive base unchanged.
- New exec surface: `docker exec soleur-web-platform-canary vitest …` runs test code inside the canary. The suite is self-contained (node builtins + SDK + vitest aliases), spawns only `bwrap`, writes only under `os.tmpdir()`, and runs as `soleur` with the canary's own env — same trust class as the existing `sandbox-canary.mjs --replay` exec.

## User-Brand Impact

- **If this lands broken, the user experiences:** a wrong-green `workspace_isolation` verdict on `/hooks/deploy-status` while a real cross-tenant isolation regression ships (detection debt, not new exposure) — or, if the `/sys` tmpfs landing misbehaves on a host shape, sandboxed agent commands failing to spawn (surfaced loudly via `failIfUnavailable`, not silently unsandboxed).
- **If this leaks, the user's data is exposed via:** one tenant's workspace files becoming readable inside another tenant's agent session — the precise property the deployed suite verifies at every deploy.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** a realized cross-tenant read exposes exactly one customer's private workspace content — a single-user breach is the honest blast radius; `none` understates it and `aggregate pattern` would require the regression to hit many tenants at once, which the per-session isolation model does not imply.

`requires_cpo_signoff: true` is set in frontmatter per the threshold. Pipeline note: this plan was authored headless inside a Task subagent; no CPO consult was spawned — the review phase's `soleur:engineering:review:user-impact-reviewer` covers the diff-level check.

## Observability

```yaml
liveness_signal:
  what: "WORKSPACE_ISOLATION journald line per canary-phase deploy + .workspace_isolation field in /hooks/deploy-status JSON"
  cadence: "per web-platform deploy (release merges to main)"
  alert_target: "Sentry (verdicts workspace_isolation_failed, workspace_isolation_timeout)"
  configured_in: "apps/web-platform/infra/ci-deploy.sh (run_workspace_isolation_probe, write_workspace_isolation_state); apps/web-platform/infra/cat-deploy-state.sh (workspace_isolation_json)"
error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN (workspace_isolation_sentry_event mirrors sandbox_canary_sentry_event)"
  fail_loud: "WORKSPACE_ISOLATION_FAIL journald line + Sentry captureMessage on failed/timeout verdicts; canary_infra_error records state only (expected while pre-tooling images still deploy)"
failure_modes:
  - mode: "cross-workspace isolation regression reaches the canary image"
    detection: "direct-tier suite exits non-zero inside the canary → verdict=workspace_isolation_failed → Sentry page; deploy continues (report-only)"
    alert_route: "Sentry issue → operator"
  - mode: "canary image predates/lacks the vitest tooling"
    detection: "docker exec rc 126/127 → verdict=canary_infra_error → state JSON + journald only, no page"
    alert_route: "/hooks/deploy-status .workspace_isolation field; journald WORKSPACE_ISOLATION line"
  - mode: "suite hangs inside the canary (bwrap deadlock)"
    detection: "host-side timeout → rc 124 → verdict=workspace_isolation_timeout → Sentry page"
    alert_route: "Sentry issue → operator"
logs:
  where: "journald -t ci-deploy (WORKSPACE_ISOLATION* lines); /mnt/data/ci-deploy-workspace-isolation.json surfaced via /hooks/deploy-status"
  retention: "journald per infra/journald-soleur.conf; state file is last-write-wins per deploy"
discoverability_test:
  command: "curl -fsS https://deploy.soleur.ai/hooks/deploy-status"
  expected_output: "workspace_isolation"
  credentials_required: "WEBHOOK_DEPLOY_SECRET HMAC signature + CF_ACCESS_CLIENT_ID / CF_ACCESS_CLIENT_SECRET headers — /hooks/deploy-status answers 403 without them; no unauthenticated local substitute verifies the live verdict"
```

## Encryption Posture

```yaml
at_rest:
  - store: "/mnt/data/ci-deploy-workspace-isolation.json (deploy verdict state, last-write-wins)"
    mechanism: "host data volume under /mnt/data — inherits the sibling deploy-state files' posture (same class as ci-deploy-state.json / ci-deploy-sandbox-canary.json); contents are verdict strings, timestamps, and counters only — no secrets, no personal data"
    evidence: "written by ci-deploy.sh write_workspace_isolation_state (atomic tmp+rename) on the deploy host; read by cat-deploy-state.sh into the /hooks/deploy-status payload"
    defends_against: "nothing beyond the host boundary — the file intentionally holds no sensitive material"
    does_not_defend: "read access on the deploy host itself (same trust class as the existing deploy-state surface)"
    disclosed_as: "operational deploy state; not a personal-data store (no Art. 30 row needed)"
    live_verification: "the .workspace_isolation field on /hooks/deploy-status"
in_transit:
  - connection: "docker exec into the canary container (host-local, no network hop); the followthrough's GET of /hooks/deploy-status over the pre-existing CF tunnel + HTTPS"
    tls: "existing deploy.soleur.ai TLS — unchanged by this plan"
    cert_verification: "platform default (curl -fsS verifies; the followthrough reuses canary-promotion-5875.sh's curl config)"
    does_not_defend: "nothing new — both channels predate this plan"
    disclosed_as: "pre-existing channels; no new in-transit surface"
```

## Guard Contract

### Guard 1 — workspace-isolation canary probe (report-only)

**Property.** Every web-platform deploy that reaches the post-bwrap canary stage runs the direct-tier isolation suite inside the canary container and records a classified verdict to deploy-state — and no verdict blocks the deploy during dark-launch.

**Assembly.** The single call site inside the `CANARY_HEALTHY` block of `ci-deploy.sh` (after `run_faithful_sandbox_canary`, before `github_app_key_canary_check` — the one path every reaching deploy traverses); the `docker exec … vitest` invocation and its rc classification; `write_workspace_isolation_state` + `cat-deploy-state.sh`'s `workspace_isolation` field (the report surface); the mock-docker vitest arm + `assert_cross_workspace_isolation` in `ci-deploy.test.sh` (the harness).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `run_workspace_isolation_probe \|\| true` call site | RED — no probe exec recorded, no `.workspace_isolation` state |
| 2 | Move the call site after `docker run -d --name soleur-web-platform` | RED — ordering assertion (probe echo precedes swap echo in deploy output) |
| 3 | Drop `\|\| true` so a vitest failure aborts the deploy | RED — mock-fail arm asserts deploy exits 0 during dark-launch |
| 4 | Classify `docker exec` rc 127 (vitest absent) as `workspace_isolation_failed` | RED — classification assert expects `canary_infra_error` |
| 5 | Mock arm answers success unconditionally (vacuous mock) | RED — `MOCK_CWI_PROBE_RC=1` arm must still drive a `workspace_isolation_failed` verdict + Sentry arm |
| 6 | Image without vitest tooling (rc 127) | PASS — deploy completes, verdict `canary_infra_error`, no Sentry page (contract-permitted non-canonical input) |

**Anchor.** The verdict lands in the committed deploy-state file read back by `cat-deploy-state.sh` and is asserted against the mock's recorded exec argv — a weakening must change the script, the mock, and the assertion consistently, and the recorded-argv check (not just exit code) ties the report to a real `docker exec` reaching the canary.

### Guard 2 — `/sys` constant-deny pin

**Property.** The constant `denyRead` set emitted by `buildAgentSandboxConfig` contains `/sys` — so every agent session's realized bwrap argv carries the `/sys` tmpfs landing.

**Assembly.** One chokepoint: the `denyRead` set literal in `buildAgentSandboxConfig` (`agent-runner-sandbox-config.ts`), shared by both consumers (`agent-runner-query-options.ts`, `cc-dispatcher.ts` via the helper); pinned by the literal `toEqual` assertions in `agent-sandbox-tenant-deny.test.ts` and `agent-runner-helpers.test.ts`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `"/sys"` from the set literal | RED — every `toEqual` pin on the constant set |
| 2 | Respell it (`"/sys/"`, `"sys"`, `"/sys/*"`) | RED — exact-literal equality |
| 3 | Move it into the `denyReadExtra` spread so it is opt-in | RED — constant-set order pins (extra entries append after the base) |
| 4 | Weaken an assertion to `toContain` | RED — harness row: membership-only assertions would pass on reorder/injection; the `toEqual` pins are the contract |
| 5 | Add a compliant `denyReadExtra` entry | PASS — extras still append after the constant base (existing pin) |

**Anchor.** Beyond the literal pins, `sandbox-credential-deny-runtime.test.ts` measures the realized sandbox outcome inside real bwrap (control vs treatment) — a verifier outside the config file; a wrong-shape deny change that compiles but alters the realized argv surface is what the runtime arm re-measures after any sandbox-flag change.

### Guard 3 — Dockerfile vitest version pin

**Property.** The vitest the canary executes is the vitest the repo tests against: the Dockerfile's global install pin equals `package-lock.json`'s resolved `vitest` version.

**Assembly.** The single `npm install -g vitest@<ver> …` line in the `cli-tools` stage (Dockerfile) vs `node_modules/vitest`.version in `package-lock.json`; asserted by new `test/dockerfile-vitest-version-pin.test.ts` (the `playwright-mcp-version-pin.test.ts` precedent).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Dockerfile pin drifts from the lockfile version | RED |
| 2 | Pin relaxes to a range (`vitest@^4`) | RED — exact pin required |
| 3 | Install line loses the `--before` bound | RED — flag shape asserted (unbounded floating tree) |
| 4 | Test anchors a bare `vitest` substring | RED — harness row: must anchor the install-line form, so a comment cannot satisfy it |
| 5 | A second `npm install -g` line for an unrelated tool | PASS — the guard is scoped to the vitest pin, not the global-install mechanism |

**Anchor.** `package-lock.json` is the independently maintained reference (`npm ci` parity is itself gated); the Dockerfile pin is compared to the lock, not to a second copy of itself.

## Implementation Phases

### Phase 1 — `/sys` denyRead (#1285)

1. Update the literal `toEqual` expectations in `test/agent-sandbox-tenant-deny.test.ts` and `test/agent-runner-helpers.test.ts` to include `"/sys"` immediately after `"/proc"` (constant base stays `[…denyRoots, c4StagingRoot, "/proc", "/sys"]`, extras still last). Red first (`cq-write-failing-tests-before`).
2. Add `"/sys"` to the set literal in `buildAgentSandboxConfig` and update the adjacent comment to name `/sys` alongside `/proc`.
3. Run `npx vitest run test/agent-sandbox-tenant-deny.test.ts test/agent-runner-helpers.test.ts test/agent-runner-query-options.test.ts` (and the sandbox runtime tests locally if bwrap/socat permit) — green.

### Phase 2 — vitest tooling in the runner image (#2640, part 1)

1. `cli-tools` stage: `RUN npm install -g vitest@4.1.11 --before=<pin-date> --ignore-scripts` (pin-date per the `likec4` convention; exact date recorded in the design note).
2. `runner` stage: `COPY --from=builder` the three-file test payload to `/app/test/…`.
3. `.dockerignore`: exact-path bangs `!test/sandbox-isolation.test.ts`, `!test/helpers/sandbox-isolation-fixtures.ts`, `!test/vitest.canary.config.ts`.
4. New `test/vitest.canary.config.ts`: `environment: "node"`, `include: ["test/sandbox-isolation.test.ts"]`, `cacheDir: "/tmp/vitest-cache"`, no `globalSetup`/`setupFiles`, explicit `testTimeout`/`hookTimeout`.
5. `SOLEUR_ISOLATION_TIERS` filter in `sandbox-isolation.test.ts` (`"direct"` skips the query-tier probe evaluation without touching `probeSkip` internals).
6. New `test/dockerfile-vitest-version-pin.test.ts` asserting the Dockerfile pin equals `package-lock`'s vitest and the `--before` flag shape.
7. Verify: `docker build` reaches the runner stage (or `web-platform-build` CI job builds `cli-tools`); exec the baked suite inside a locally built image if Docker is available in the work env, else rely on the mock harness + report-only observation window.

### Phase 3 — report-only deploy probe + surfaces (#2640, part 2)

1. `ci-deploy.sh`: `WORKSPACE_ISOLATION_STATE_FILE`, `write_workspace_isolation_state` (atomic, always-returns-0 — mirror `write_sandbox_canary_state` INCLUDING the `consecutive_pass`/`first_pass_at` accumulation), `workspace_isolation_sentry_event` (mirror `sandbox_canary_sentry_event`), `run_workspace_isolation_probe` (mirror `run_faithful_sandbox_canary` incl. `set +o pipefail` capture arm and stderr tail), call site `run_workspace_isolation_probe || true` after the faithful-canary call inside the `CANARY_HEALTHY` block.
2. `cat-deploy-state.sh`: `workspace_isolation_json` reader + `workspace_isolation: $wi` in the merged JSON.
3. `ci-deploy.test.sh`: mock-docker vitest arm (records exec argv to `MOCK_CWI_LOG`, answers `MOCK_CWI_PROBE_OUT`/`MOCK_CWI_PROBE_RC`/`MOCK_DOCKER_EXEC_FAIL_CANARY_VITEST`), `assert_cross_workspace_isolation` (ordering: probe echo before swap echo; deploy exits 0 on vitest fail; state reasons `workspace_isolation_failed` / `canary_infra_error` / `workspace_isolation_timeout` per rc).
4. `plugins/soleur/test/preflight-discoverability-test.test.ts`: `BASELINE_DECLARED_PROBES` 50 → 51 + PLACEMENT/TRUTH/NO-SUBSTITUTE comment — this plan's `credentials_required` declaration moves the corpus count (sharp edge #8651/#7393).
5. `knowledge-base/engineering/operations/runbooks/canary-probe-set.md`: document the new probe layer.
6. New `knowledge-base/engineering/operations/runbooks/workspace-isolation-canary-probe.md` design note: chosen image strategy + size delta, gate-vs-report decision + promotion criteria, tier scoping rationale.
7. New `scripts/followthroughs/workspace-isolation-verdict-2640.sh`, modeled on `canary-promotion-5875.sh` (same xtrace refusal, `_bearer_ok`/`_refuse` credential-shape arm, HMAC-over-empty-body + CF-Access GET, `TRANSIENT` exit 2 contract): reads `.workspace_isolation.consecutive_pass` + `.first_pass_at`, exits 0 when `consecutive_pass ≥ 5` AND the span since `first_pass_at` ≥ 3 days (mirroring the faithful-canary soak; the directive `earliest=` self-pins the window), exit 1 on a recorded `workspace_isolation_failed` verdict (investigate before promoting), TRANSIENT otherwise. Required env / `secrets=` clause: `WEBHOOK_DEPLOY_SECRET, CF_ACCESS_CLIENT_ID, CF_ACCESS_CLIENT_SECRET` — all three already wired in `scheduled-followthrough-sweeper.yml`.

### Phase 4 — verification + docs

1. `bash apps/web-platform/infra/ci-deploy.test.sh` green; vitest unit suites green; `docker-context-import-containment.test.ts` green. (Plan-author run note: the suite exceeds ~5 min in a constrained sandbox and showed pre-existing mock-canary FAIL rows on an untouched tree — the authoritative gate is `infra-validation.yml`'s `deploy-script-tests` job; treat local sandbox FAILs on the unchanged file as environmental, verify the new arms specifically.)
2. `npx markdownlint-cli2 <plan>` green (the authored plan is linted by lefthook at the work phase's first commit — catch MD010/MD032 here).
3. PR body: image-size delta note + `Closes #1285`, `Closes #2640` on their own lines; promotion issue filed at ship time with the `<!-- soleur:followthrough script=… earliest=… secrets=WEBHOOK_DEPLOY_SECRET,CF_ACCESS_CLIENT_ID,CF_ACCESS_CLIENT_SECRET -->` directive + `follow-through` label.

## Files to Edit

- `apps/web-platform/server/agent-runner-sandbox-config.ts` — `"/sys"` in the constant deny set + comment.
- `apps/web-platform/test/agent-sandbox-tenant-deny.test.ts` — literal `toEqual` pins.
- `apps/web-platform/test/agent-runner-helpers.test.ts` — literal `toEqual`/`toContain` pins.
- `apps/web-platform/test/sandbox-isolation.test.ts` — `SOLEUR_ISOLATION_TIERS` knob.
- `apps/web-platform/Dockerfile` — `cli-tools` vitest install; `runner` test-payload COPYs.
- `apps/web-platform/.dockerignore` — three exact-path `!test/…` bangs.
- `apps/web-platform/infra/ci-deploy.sh` — probe function, state writer, Sentry arm, call site.
- `apps/web-platform/infra/ci-deploy.test.sh` — mock arm + `assert_cross_workspace_isolation` + classification assertions.
- `apps/web-platform/infra/cat-deploy-state.sh` — `workspace_isolation_json` + merge field.
- `plugins/soleur/test/preflight-discoverability-test.test.ts` — `BASELINE_DECLARED_PROBES` bump 50→51 with the PLACEMENT/TRUTH/NO-SUBSTITUTE comment the suite's failure text requires (this plan declares `credentials_required`).
- `knowledge-base/engineering/operations/runbooks/canary-probe-set.md` — probe-layer documentation.

## Files to Create

- `apps/web-platform/test/vitest.canary.config.ts` — minimal in-image config.
- `apps/web-platform/test/dockerfile-vitest-version-pin.test.ts` — pin-consistency guard.
- `knowledge-base/engineering/operations/runbooks/workspace-isolation-canary-probe.md` — design note (issue AC 1).
- `scripts/followthroughs/workspace-isolation-verdict-2640.sh` — promotion-precondition probe.

## Open Code-Review Overlap

- #3053 "review: empty-mount window during ci-deploy seed (Ref #3045)" — touches `ci-deploy.sh` but concerns the plugin-seed `docker cp` window, not the canary probe chain. **Acknowledge**: orthogonal concern, correctly deferred to #2608's venue by the issue's own scope-out; remains open.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Add `\"/sys\"` to `denyRead` array in `apps/web-platform/server/agent-runner.ts`" [#1285] | Phase 1 / `agent-runner-sandbox-config.ts` edit (site reconciled — see Research Reconciliation) | mapped |
| 2 | "Run existing tests to verify no regressions" [#1285] | Phase 1.3, Phase 4.1 | mapped |
| 3 | "vitest in the canary image" [#2640] | Phase 2 / Dockerfile, .dockerignore, canary config | mapped |
| 4 | "Deploy gate wiring in `apps/web-platform/infra/ci-deploy.sh`" [#2640] | Phase 3 / `run_workspace_isolation_probe` (report-only form — see Research Reconciliation) | mapped |
| 5 | "Trace-order assertion in `apps/web-platform/infra/ci-deploy.test.sh` … `assert_cross_workspace_isolation` … exit-code disambiguation for vitest failures vs infrastructure failures" [#2640] | Phase 3.3 / mock arm + assertions | mapped |
| 6 | "Design note in `knowledge-base/` documenting chosen image strategy and gate-vs-report decision" [#2640 AC] | Phase 3.5 / `workspace-isolation-canary-probe.md` | mapped |
| 7 | "Dockerfile changes land with image-size delta noted in PR description" [#2640 AC] | Phase 4.2 | mapped |
| 8 | "`ci-deploy.sh` invokes the isolation suite during canary verification" [#2640 AC] | Phase 3.1 | mapped |
| 9 | "`ci-deploy.test.sh` `assert_cross_workspace_isolation` passes with mocked docker" [#2640 AC] | Phase 3.3, Phase 4.1 | mapped |
| 10 | "Rollback path tested via `MOCK_DOCKER_EXEC_FAIL_CANARY_VITEST=1` (new mock hook)" [#2640 AC] | Phase 3.3 — adapted: the report-only shape has no rollback; the arm asserts verdict + deploy continuation instead | descoped — justification: `wg-dark-launch-deploy-gates` forbids a new gating check shipping blocking-first; the mock hook still lands, wired to the report-only contract |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `"/sys"` in `buildAgentSandboxConfig` deny set | "Add `\"/sys\"` to `denyRead` array" | asked |
| Literal-pin updates in the two deny test files | "Run existing tests to verify no regressions" | asked |
| `npm install -g vitest` + test payload in runner image | "vitest in the canary image" | asked |
| `test/vitest.canary.config.ts` | "vitest in the canary image" | inferred — justification: repo `vitest.config.ts` loads setup files `.dockerignore`d out of the image; a runnable in-image config is required for the suite to execute at all |
| `SOLEUR_ISOLATION_TIERS` knob | "Deploy gate wiring in `apps/web-platform/infra/ci-deploy.sh`" | inferred — justification: the query tier makes live Anthropic API calls under the canary's env; the gate must run only the deterministic tier |
| `run_workspace_isolation_probe` + state/Sentry wiring | "Deploy gate wiring in `apps/web-platform/infra/ci-deploy.sh`" | asked |
| `cat-deploy-state.sh` field | "exit-code disambiguation for vitest failures vs infrastructure failures (different `final_write_state` reasons)" | inferred — justification: classified verdicts need the no-SSH report surface (`hr-no-ssh-fallback-in-runbooks` / observability gate) |
| mock arm + `assert_cross_workspace_isolation` | "Trace-order assertion in `apps/web-platform/infra/ci-deploy.test.sh`" | asked |
| `dockerfile-vitest-version-pin.test.ts` | — | inferred — justification: unguarded Dockerfile-vs-lockfile drift would silently run a different vitest in the canary than CI tests against; repo precedent (`playwright-mcp-version-pin`) |
| `workspace-isolation-canary-probe.md` design note | "Design note in `knowledge-base/` documenting chosen image strategy and gate-vs-report decision" | asked |
| `canary-probe-set.md` update | — | inferred — justification: the file is the documented contract for the probe set; a probe absent from it is an undocumented deploy surface |
| `scripts/followthroughs/workspace-isolation-verdict-2640.sh` | — | inferred — justification: `wg-dark-launch-deploy-gates` requires observed real-deploy passing before gating; the soak-gated promotion needs a committed probe (plan Phase 2.9.1); shape mirrors `canary-promotion-5875.sh` |
| `BASELINE_DECLARED_PROBES` bump in `preflight-discoverability-test.test.ts` | — | inferred — justification: this plan's `credentials_required` declaration moves the repo-global corpus ratchet (#7393/#8651); the bump must land in the same PR |

### Split Assessment

- Subsystems touched: 3 — `apps/web-platform`, `knowledge-base`, `scripts`
- Planned files: 14 | Estimated changed lines: ~400
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Domain Review

**Domains relevant:** engineering, operations

### Engineering

**Status:** reviewed
**Assessment:** Deploy-pipeline + agent-sandbox change. Two-chokepoint diff (sandbox config constant; ci-deploy canary block); the dark-launch report-only shape matches the faithful-canary arc (ADR-079). Deploy-order coupling handled: `ci-deploy.sh` updates reach hosts via `apply-deploy-pipeline-fix.yml` ahead of the first vitest image, and the rc-127 `canary_infra_error` classification makes that window benign. (Assessed inline — Task subagent spawn unavailable in this pipeline context.)

### Operations

**Status:** reviewed
**Assessment:** No new infrastructure, vendors, secrets, or manual steps. Host-side script delivery reuses the existing apply workflow; fresh hosts get the script through the established image-baked host-scripts path. Rollback of the PR reverts to the prior probe set. (Assessed inline — no subagent spawn available.)

No cross-domain user-facing implications beyond engineering/operations — no UI, no copy, no data-model change.

## Acceptance Criteria

<!-- founder-stated check: interactive-only per plan-founder-check.md; skipped headless -->

- [ ] `buildAgentSandboxConfig` emits `"/sys"` in `filesystem.denyRead` after `"/proc"`; all literal deny pins updated and green.
- [ ] Existing sandbox test suite shows no regressions (`agent-sandbox-tenant-deny`, `agent-runner-helpers`, `agent-runner-query-options`, plus bwrap-gated runtime tests where the runner supports it).
- [ ] Runner image contains a pinned `vitest` (global install, `--before` bound, `--ignore-scripts`) and the three-file test payload under `/app/test/`; image-size delta recorded in the PR body.
- [ ] `test/vitest.canary.config.ts` runs only `test/sandbox-isolation.test.ts` with no repo-config dependencies.
- [ ] `SOLEUR_ISOLATION_TIERS=direct` restricts the suite to the deterministic direct-bwrap tier.
- [ ] `ci-deploy.sh` executes the suite inside the canary between the faithful-canary probe and the prod swap, classifies `docker exec` rc into `pass` / `workspace_isolation_failed` / `workspace_isolation_timeout` / `canary_infra_error`, records the verdict to `ci-deploy-workspace-isolation.json`, logs `WORKSPACE_ISOLATION:` per run, Sentry-pages on failed/timeout, and never blocks the deploy.
- [ ] `cat-deploy-state.sh` surfaces `.workspace_isolation` on `/hooks/deploy-status`.
- [ ] `ci-deploy.test.sh` mock vitest arm + `assert_cross_workspace_isolation` green, including `MOCK_DOCKER_EXEC_FAIL_CANARY_VITEST=1` (deploy continues, failed verdict recorded) and an rc-127 arm (`canary_infra_error`, no page).
- [ ] `test/dockerfile-vitest-version-pin.test.ts` pins Dockerfile vitest to the lockfile version.
- [ ] `knowledge-base/engineering/operations/runbooks/workspace-isolation-canary-probe.md` committed, documenting image strategy + delta and the gate-vs-report decision with promotion criteria; `canary-probe-set.md` updated.
- [ ] `scripts/followthroughs/workspace-isolation-verdict-2640.sh` committed; ship-phase reminder notes the promotion tracker needs the `<!-- soleur:followthrough … -->` directive.
- [ ] `BASELINE_DECLARED_PROBES` in `plugins/soleur/test/preflight-discoverability-test.test.ts` bumped 50 → 51 with the PLACEMENT/TRUTH/NO-SUBSTITUTE comment.
- [ ] `write_workspace_isolation_state` accumulates `consecutive_pass`/`first_pass_at` (reset on failed/timeout, hold on `canary_infra_error`), so the promotion probe is a stateless GET.

## Test Scenarios

- Given a fresh `buildAgentSandboxConfig` call, when `filesystem.denyRead` is inspected, then it equals `[…denyRoots, c4StagingRoot, "/proc", "/sys", …extras]` — `unit` (`agent-sandbox-tenant-deny.test.ts`, `agent-runner-helpers.test.ts`).
- Given the runner image build, when `docker exec` runs the canary config, then vitest executes the direct tier and exits 0 — `integration` (verified in-image or via the report-only observation window).
- Given a canary deploy where the suite fails (`MOCK_DOCKER_EXEC_FAIL_CANARY_VITEST=1`), when `ci-deploy.sh` runs, then the deploy completes, verdict `workspace_isolation_failed` is recorded, and a Sentry event is armed — `integration` (`ci-deploy.test.sh`).
- Given a canary image without vitest (mock exec rc 127), when the probe runs, then verdict `canary_infra_error` is recorded and no Sentry page fires — `integration` (`ci-deploy.test.sh`).
- Given the host-side timeout fires (mock rc 124), when the probe runs, then verdict `workspace_isolation_timeout` is recorded and pages — `integration` (`ci-deploy.test.sh`).
- Given the vitest Dockerfile pin drifts from the lockfile, when the pin test runs, then it fails — `unit` (`dockerfile-vitest-version-pin.test.ts`).

Commands:

```bash
cd apps/web-platform
npx vitest run test/agent-sandbox-tenant-deny.test.ts test/agent-runner-helpers.test.ts test/agent-runner-query-options.test.ts
npx vitest run test/dockerfile-vitest-version-pin.test.ts test/docker-context-import-containment.test.ts
bash infra/ci-deploy.test.sh
```

## Non-Goals

- **Blocking promotion of the probe** — deferred per `wg-dark-launch-deploy-gates`; tracked by the follow-through enrollment + a promotion issue filed at ship time (observed `pass` on ≥1 real deploy is the flip precondition).
- **Query-tier / FR9 arms in the deploy path** — live-API calls are wrong for a deploy gate; they stay in the test matrix.
- **FR10/FR11/FR12 coverage** — already deferred by #2610's coverage matrix.
- **Recapturing `sandbox-canary-argv.json`** — the committed fixture is regenerated by the SDK-bump gate, not by this config change; the `--tmpfs /sys` entry will appear at the next capture (expected diff).
- **Editing `todos/001-complete-p3-add-sys-to-denyread.md`** — a closed review-backlog artifact; left as the historical record.

## Alternative Approaches Considered

| Approach | Verdict | Reason |
|---|---|---|
| Surgical `COPY` of `node_modules/vitest` + transitive deps (issue option 1) | rejected | transitive-dep enumeration (~50+ packages) is fragile; a missed dep fails only at deploy time — the worst place |
| Canary-only image stage/tag or `Dockerfile.canary` (issue options 2–3) | rejected | a second image doubles sign/push/verify/freshness surface and weakens `canary == prod`; additive global install keeps one verified artifact |
| Reuse repo `vitest.config.ts` | rejected | loads `globalSetup` + project setup files pruned from the image; cascades more `.dockerignore` re-includes |
| `vitest -t "direct bwrap"` name filter | rejected | describe-name string matching breaks on rename; an env tier knob is an explicit contract |
| Second minimal `package.json`+lock for canary tools | rejected | a floating `--before`-bounded global install matches the established `cli-tools` convention; a second lockfile is heavier maintenance |
| Blocking deploy gate from day one | rejected | `wg-dark-launch-deploy-gates` — never validate a gate change with the same deploy it gates |

## Risks & Sharp Edges

- **Deploy-order coupling**: `ci-deploy.sh` updates reach hosts before a vitest-carrying image deploys → rc 127 → `canary_infra_error` by design (no page, state recorded). First successful deploy of a tooling image starts emitting real verdicts.
- **`/sys` cgroup visibility**: masked `/sys` hides `/sys/fs/cgroup` inside the sandbox — heap-sizing behavior change for sandboxed subprocesses, not an isolation break (kernel cgroup still enforces). Documented in the design note.
- **`.dockerignore` three-surface rule**: each baked file needs Dockerfile COPY + `!` bang (the #5922/#7666 release-break class); the exact-path bang form is mandatory — a bare `!test/` directory bang cascades.
- **vitest in-container specifics**: exec runs as `soleur` → `cacheDir` under `/tmp`; `-w /app` for module resolution; `CI=true` env set.
- **Captured-argv drift**: the next `sdk-bump-sandbox-gate.sh` capture will show `--tmpfs /sys` — expected, not a regression.
- **Mock vacuity**: the vitest exec's stdout is captured (like the faithful canary's), so `DOCKER_TRACE` markers do not shift — ordering is asserted on script echo lines + `MOCK_CWI_LOG`, not trace position.
- **ADvisor consult skipped**: Step 4.5's scoped advisor Task could not be spawned (no Task tool in this subagent context) — flagged as a coverage gap rather than silently omitted.
- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails deepen-plan — filled above.

### Network-Outage Deep-Dive

The 4.5 gate's resource-shape trigger fires: merging this plan's `infra/ci-deploy.sh` edit auto-drives `apply-deploy-pipeline-fix.yml` → `terraform apply -target=terraform_data.deploy_pipeline_fix`, whose file/remote-exec provisioners reach the host over SSH through the Cloudflare tunnel (the #3061 class). This is a delivery-path dependency check, not an incident diagnosis — the plan introduces no NEW SSH dependency; it rides the standing path every deploy-pipeline-fix merge already uses.

| Layer | Verification status | Artifact |
|---|---|---|
| L3 firewall allow-list | verified — not the operative path: provisioners POST file payloads through `deploy.`/`ssh.` CF-tunnel ingress (origin-relative since #6594), not an admin-IP firewall rule | `apply-deploy-pipeline-fix.yml` header comments (SSH-provisioner serialization note); `tunnel.tf` three-ingress model |
| L3 DNS/routing | verified — `deploy.soleur.ai` / `ssh.soleur.ai` ingress is the standing production path used by every merge on these paths | `hooks.json.tmpl`, workflow history for `apply-deploy-pipeline-fix.yml` |
| L7 TLS/proxy | verified — CF Access service-token + HMAC at the hook surface; standing contract | `infra/hooks.json.tmpl`; the probe's own `WORKSPACE_ISOLATION` journald line is the deploy-side witness |
| L7 application | self-detecting — if the new script never reaches the host, `.workspace_isolation` stays ABSENT on `/hooks/deploy-status` (distinguishable from a `failed` verdict), and the promotion followthrough reads absent-field as TRANSIENT, never green | `cat-deploy-state.sh` field shape; `workspace-isolation-verdict-2640.sh` contract |

Residual risk: an apply-time SSH break (`connection reset`) is the standing pipeline risk, unchanged by this plan; the observable symptom is an absent field, not a false verdict.

## Architecture Decision (ADR/C4)

**Not required.** The plan extends an established pattern (ADR-079's non-blocking canary probe; the existing deny-list mechanism) without moving a boundary: no ownership/tenancy change, no new substrate, no ADR reversal. C4 check — enumerated actors (none new), external systems (none new — Sentry already modeled), containers/data-stores (same image, same containers, one new tmpfs state file on the host's existing deploy-state surface), access relationships (unchanged): no `.c4` edit needed. The gate-vs-report decision is recorded in the committed design note, which is the granularity the issue asks for.

## References

- Issues: #1285 (`Closes #1285`), #2640 (`Closes #2640`); context #1047, #1450, #1557, #2610, PR #1282, #5875/ADR-079, #9723
- Files: `apps/web-platform/server/agent-runner-sandbox-config.ts`, `apps/web-platform/test/sandbox-isolation.test.ts`, `apps/web-platform/test/helpers/sandbox-isolation-fixtures.ts`, `apps/web-platform/Dockerfile`, `apps/web-platform/.dockerignore`, `apps/web-platform/infra/{ci-deploy.sh,ci-deploy.test.sh,cat-deploy-state.sh,sandbox-canary-argv.json}`, `apps/web-platform/scripts/sandbox-canary.mjs`, `apps/web-platform/infra/hooks.json.tmpl`
- Rules: `wg-dark-launch-deploy-gates`, `hr-no-ssh-fallback-in-runbooks`, `hr-observability-as-plan-quality-gate`
- Verified: `vitest --config <path>` flag exists — `<!-- verified: 2026-10-09 source: local vitest 4.1.11 --help -->`
