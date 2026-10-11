---
title: "agent sandbox shim: fresh procfs mount fails under docker's masked /proc (H6)"
date: 2026-10-11
slug: fix-agent-sandbox-proc-mask-systempaths
branch: feat-sandbox-proc-shim-h6
issue: 10032
closes: []
type: fix
priority: p1
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# fix: agent sandbox shim — fresh procfs refused under docker's masked /proc (H6)

Ref #10032 and Ref #9860. Neither is closed by this PR's merge: both close only after the faithful canary passes on the deployed image (see Phase 7).

## Overview

Every agent Bash sandbox spawn fails closed in production while the app reports healthy. The shim (`apps/web-platform/infra/bwrap-shim/bwrap`) splices a mandatory fresh `--proc /proc` as the cross-tenant `/proc` mask. Docker's default masked `/proc` refuses that mount (`bwrap: Can't mount proc on /newroot/proc: Operation not permitted`). The faithful canary is report-only, so deploys ship the failing image: production runs it today (Better Stack, v0.338.9 and v0.338.10: `SANDBOX_CANARY_FAIL ... report-only canary, never gated`).

Operator decision (2026-10-11): add `--security-opt systempaths=unconfined` at the three `docker run` sites, plus a docker regression test, a Sentry mirror for Bash bwrap failures, and the stale-comment fixes with an ADR-075 addendum. The shim is not changed: its tail mask stays the cross-tenant control; docker's masks were never the control for `/proc/<pid>/environ`.

**Verification caveat (plan-review, measured):** the docker CLI consumes `systempaths=unconfined` client-side and never records it in `HostConfig.SecurityOpt` — a local `docker create --security-opt systempaths=unconfined` inspected as `SecOpt=[...] Masked=[] RO=[]`. So the flag is verified through `HostConfig.MaskedPaths` (empty after, the default list before), never through a `systempaths=` string in `hostsec`. The issue's reading "no `systempaths=` in hostsec → default masks in force" was therefore not evidence either way; the evidence for H6 is the CTO's local control/treatment delta (rc=1 → rc=0) plus the bwrap error text.

Brainstorm: `knowledge-base/project/brainstorms/2026-10-11-sandbox-proc-shim-h6-brainstorm.md`. Spec: `knowledge-base/project/specs/feat-sandbox-proc-shim-h6/spec.md`.

## Research Insights

**Premise Validation (Phase 0.6).** Held: #10032, #9860, #10050 open; draft PR #10043 open; every cited file exists on `origin/main` (shim, `ci-deploy.sh`, `cloud-init.yml`, `agent-runner-sandbox-config.ts`, AppArmor profile, `cat-deploy-state.sh`, classifier). Stale or wrong, now corrected: (1) CPO's "failed canary leaves prod on the last good image" is false (canary never gates); (2) ADR-075's 2026-10-08 `#9723` addendum records the shim `--proc` as "verified live", while its own `#5863` addendum records fresh `--proc` EPERM under docker's masked paths (bubblewrap#284) — the first verification ran without docker's masks. ADR corpus: the mechanism (`systempaths=unconfined`) sits in ADR-075's `#5863` addendum as "a widening, not a fix" and in `2026-10-08-feat-tenant-fs-isolation-plan.md:204-206,222` as deferred to #9773; this plan deliberately supersedes that position and the addendum says so.

**Property List.**
- P1. The SDK's real sandbox argv spawns in the production container (faithful canary passes).
- P2. A sibling session's processes are not visible from inside a tenant sandbox (`/proc/<sibling-pid>/environ` unreachable).
- P3. A change that re-breaks P1 or P2 under the production container posture cannot merge green.
- P4. A failed Bash sandbox spawn in prod is observable in Sentry without SSH.
- P5. The recorded architecture and legal posture describe the container as it actually runs.

**Cut List.**
- Procfs-free argv (buys P1) → needs the vendor command string rewritten; CTO measured a wrong fd table for `apply-seccomp /proc/self/fd/N`; cut.
- Shim edits (buys P2) → the shim's tail `--proc /proc` already provides P2; untouched.
- Wiring `infra/sandbox-hardening-contract.sh` (buys P3) → wired to nothing today (`git grep -n sandbox-hardening-contract` hits only itself); not adopted, the new docker suite replaces the need.
- Per-host edits (P1) → `ci-deploy.sh` is the one script both hosts run; no per-host change.
- Standalone parity suite (buys P3) → `ci-deploy.test.sh` already asserts the apparmor option on every `DOCKER_RUN_ARGS` line; the derive-and-assert grep folds into that suite (DHH + simplicity reviewers).
- `agent-env` pin file for `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` → a negative-existence test buying nothing in P1-P5; replaced by one assertion in the existing sandbox-config test that `enableWeakerNestedSandbox` stays `true`.
- ADR-272 cross-note → one line with no property behind it; the ADR-075 addendum carries the correction.
- Sentry alert-rule changes (P4 paging) → the live `sandbox-startup-failure` rule is inert to edits until #7985 (`ignore_changes = all`); the new event is queryable, paging is a tracked follow-up.

**Resolved brainstorm questions.**
- `Gd()`/`Gd()&&u5()` (vendored gate): `Gd` reads only `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB`, `u5` only whether a bwrap binary resolves. Our env allowlist (`server/agent-env.ts`) never sets that variable, so `enableWeakerNestedSandbox` stays `true` and the SDK emits `--bind /proc /proc` (the arm the shim masks). A future operator setting that variable would silently flip the arm → Phase 1.4 pins the resulting property (`enableWeakerNestedSandbox` stays `true`) in the existing sandbox-config test. The `--bind /proc /proc` arm in `server/agent-outer-wrap.ts` is a different, DEAD arm (`AGENT_OUTER_WRAP` is flag-off in prod per the 2026-10-09 ADR-075 addendum); the live `--bind /proc /proc` is the vendored SDK tail bind the shim masks.
- `apply-seccomp` helper's nested procfs: not measurable offline; asserted by the docker suite's treatment arm (the replay runs the real helper) and by the first post-deploy canary.
- H7 (AppArmor): not excludable locally (CTO's runs used `apparmor=unconfined`; the dev host cannot load the profile). The docker suite loads the real `soleur-bwrap` profile on the ubuntu runner (apparmor available), so CI is the AppArmor-faithful lab; the production canary is the final arbiter.

**Institutional learnings applied.** `bwrap-args-payload-outer-resume-proc-mask-20261009` (mask must be a procfs mount, spliced at the outer setup end); `2026-10-11-every-fixture-of-the-kernel-denial-row...` (fixtures use the tool's real stderr channel); `2026-07-19-the-harness-broke-the-rule-it-enforced-and-the-canary-could-not-fail` (show the guard goes red); ADR-079 (a bare standalone repro can pass while the real argv fails → use the canary replay); `2026-10-11-a-green-sandbox-probe...` (a pass is a claim about what ran).

**Existing precedent reused.** `apps/web-platform/scripts/sandbox-canary-regression.test.sh` section B is the opt-in docker proof; it is deliberately NEVER-FAIL (skips on an unusable runner), which is the property this plan must not copy. The new suite follows `workspaces-luks-loopback.test.sh` instead: it never self-skips in CI and fails loudly with a literal token.

**Delivery path (verified).** `ci-deploy.sh` reaches the hosts through `terraform_data.deploy_pipeline_fix` (web-1) and `deploy_pipeline_fix_web2` (web-2 twin), applied by `.github/workflows/apply-deploy-pipeline-fix.yml`. Parity instrument: `bash scripts/check-deploy-script-parity.sh --bs-only` (read-only).

## Open Code-Review Overlap

- #3243 (decompose `cc-dispatcher.ts`) and #3242 (`tool_use` WS event raw name): **Acknowledge** — different concerns; this plan adds one self-contained try/catch inside the existing `onToolResult` handler and does not decompose the file.
- #8735 and #7942 (`infra-validation.yml` notify gap; unregistered `*.mutation.sh` batteries): **Acknowledge** — unrelated to adding one registered step; the new suite is registered, not a `*.mutation.sh`.
- No open code-review issue names `ci-deploy.sh`, `cloud-init.yml`, `sandbox-startup-classifier.ts`, `agent-runner-sandbox-config.ts` or `audit-bwrap-uid.sh`.

## Architecture Decision (ADR/C4)

### ADR
Amend ADR-075 (`ADR-075-agent-sandbox-tenant-read-isolation.md`) with a 2026-10-11 addendum, status `adopting` until the first faithful-canary pass on the deployed image: supersedes the `#5863` "widening, not a fix" position; states that docker's masked paths were never the `/proc/<pid>/environ` control and that the shim's pidns-scoped fresh `--proc` is; names the new container-wide scope: `systempaths=unconfined` drops BOTH maskedPaths and readonlyPaths, so `/proc/{sys,irq,bus,fs,sysrq-trigger}` become rw-mounted and `/proc/{acpi,kcore,keys,timer_list,sched_debug,scsi,interrupts}` unmasked for the server process and the CLI file tools. Real compensation is DAC plus capabilities (non-root `USER soleur`, no `SYS_ADMIN`, root-owned files); the AppArmor profile only denies `/proc/kcore`, `/proc/sysrq-trigger` and writes under `/proc/sys/kernel/`, so it is NOT claimed as broad compensation. Also names the new in-sandbox information leak: the sandbox's fresh procfs now exposes the global world-readable `/proc/{timer_list,sched_debug,interrupts}` (host-wide task names and pids, cross-tenant, information-level); bounds the mask-absent interval from about 2026-10-09T04:52Z; corrects the "verified live" claim of the 2026-10-08 `#9723` addendum to name the unmasked environment it ran in; does not claim the residual closed (wrapped-CLI tier `/proc` visibility stays the open #9773 residual). Correct ADR-075's own `#5863` addendum line ("a widening, not a fix") explicitly so the file does not contradict itself. No ADR-272 edit.

### C4 views
Provisional "no C4 impact": no new external human actor, external system, container or data store, and no actor-to-surface access relationship changes — the change is a docker security-option on an existing container. Phase 5 must READ all three files (`diagrams/{model.c4,views.c4,spec.c4}`), confirm no element description names docker's masked `/proc`, and run `plugins/soleur/test/c4-count-parity.test.sh` (no cardinality in `model.c4` moves). If a description is falsified, the `.c4` edit is part of this PR.

### Sequencing
ADR addendum is authored in this PR as `adopting`; the `adopting → accepted` flip ships as a small docs-only PR the agent opens after the verified canary pass (reviewed, CLO acknowledging), not an unreviewed post-merge edit and not a follow-up issue.

## Infrastructure (IaC)

### Terraform changes
None. No `.tf` file changes. The flag lives in `ci-deploy.sh` (canary and prod `docker run`) and `cloud-init.yml` (first-boot `docker run`).

### Apply path
`ci-deploy.sh`/`cloud-init.yml` edits reach running hosts via `apply-deploy-pipeline-fix.yml` (`terraform_data.deploy_pipeline_fix` and `deploy_pipeline_fix_web2`); the running container only takes the flag at its next `docker run`, i.e. the next release deploy. Cloud-init is frozen on running hosts (`ignore_changes = [user_data, ...]`), so its edit only matters at a future `-replace`. `apply-deploy-pipeline-fix.yml` auto-fires on merge (its `paths:` filter carries `ci-deploy.sh`; `cloud-init.yml` is NOT in it, harmless because cloud-init is frozen on running hosts). The release workflow fires on the same merge and the two share no concurrency group, so the release can win and run the OLD host copy; the canary then fails once more with the flag absent. A second release deploy is therefore expected and needs the operator's explicit go-ahead (merge, `workflow_dispatch` of the apply workflow, any release re-run). Verify the provisioner writes `ci-deploy.sh` atomically before relying on that ordering (bash reads a script lazily; an in-place replace mid-run can corrupt a running deploy). Docker option risk: `systempaths=unconfined` exists since docker 20.10 and prod runs 29.3.0; the canary container carries the same flag and starts BEFORE prod is touched, so a rejected option fails the canary start, not the prod swap (Phase 2.1 confirms by reading the canary-start failure path). The recreate stops prod with `docker stop --time=12`, which ends in-flight agent sessions: a user-visible drop, stated here rather than hidden as "the existing deploy path".

### Host fan-out
`deploy_pipeline_fix` (web-1) and `deploy_pipeline_fix_web2` (web-2) are twins, so no new provisioner and nothing to classify: both hosts receive the same `ci-deploy.sh`. Delivery proof is the apply workflow's result for BOTH host jobs. `check-deploy-script-parity.sh --bs-only` reads the `DEPLOY_SCRIPT_SHA` marker `ci-deploy.sh` emits when it runs: it proves the script that ran at the LAST deploy, after the fact, and cannot gate the deploy it measures (web-2's marker only moves when `ci-deploy.sh` next runs there). Use it to confirm the second deploy ran the new script.

### Distinctness / drift safeguards
The `ci-deploy.test.sh` parity assertion pins the flag across the docker-run sites and the mock; the no-SSH integrity anchor is the post-deploy `host` diag row (`masked=0`). `audit-bwrap-uid.sh` is an operator SSH runbook (not a no-SSH anchor, red on the old container until the recreate); its extension reads `HostConfig.MaskedPaths`.

### Vendor-tier reality check
Not applicable: no vendor resource is created.

## User-Brand Impact

- **If this lands broken, the user experiences:** every agent Bash command in a hosted session fails with the generic "An unexpected error occurred. Please try again." (retry cannot help), or — if the fix over-widens — one tenant's agent can see another tenant's process environment.
- **If this leaks, the user's workflow and credentials are exposed via:** `/proc/<sibling-pid>/environ` and `/proc/<pid>/{root,cwd,ns}` of a same-uid process in the shared container, if the sandbox's fresh pidns-scoped `/proc` is not in force.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one tenant reading another's environment is brand-ending for the first affected user, and a silently down sandbox is a per-user outage; both are single-user events, so aggregate-pattern is too low.

CPO sign-off: carried from the brainstorm CPO assessment (2026-10-11), to be re-confirmed at the plan-review gate. `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carried forward from the brainstorm `## Domain Assessments`; no fresh sweep)

### Engineering (CTO)
**Status:** reviewed. Recommends `systempaths=unconfined`; procfs-free argv and mask-without-fresh-mount rejected; validate through the canary replay under the real security-opts; CI job on an ubuntu runner is the permanent gate; pin the flag on all three `docker run` sites.

### Product (CPO)
**Status:** reviewed. Presumed live impact; generic client error; the live Sentry alert needs more than 2 users per hour and is unreachable at one or a few testers; isolation outranks availability; no customer comms until the production image check confirms impact. The CPO's rollback claim was corrected by a live read (canary is report-only).

### Legal (CLO)
**Status:** reviewed. No public claim falsified; no Art. 33/34 trigger on present facts; ADR addendum, CLO attestation under `knowledge-base/legal/audits/`, and a new Art. 32 TOM cell required; feed the named choice into the owed #9723-window Art. 33(5) assessment; no DPIA/LIA touch.

### Product/UX Gate
**Tier:** none (no new or changed user-facing UI file). **Decision:** n/a. **Agents invoked:** none. **Skipped specialists:** none. **Pencil available:** N/A (no UI surface).

**Brainstorm-recommended specialists:** none named.

## GDPR / Compliance Gate

Trigger (b) fired (brand-survival threshold `single-user incident`). `soleur:gdpr-gate` ran against this plan (2026-10-11): no Critical finding; one Important finding (Art. 5(1)(c)) — the Sentry mirror must send only the matched bwrap line, not the whole Bash tool output — now folded into Phase 4.2 and the acceptance criteria. The five v1 checks otherwise have no trigger (no schema column, FK to `users`, or new vendor; Sentry is the existing EU-cluster processor). The CLO assessment above covers Art. 32/33.

## Encryption Posture

No persistent store and no new cross-component connection is introduced (an existing `docker run` line gains one security option), so the gate is skipped per its skip clause. `cloud-init.yml` is touched only at a `docker run` flag.

## Observability

```yaml
liveness_signal:
  what: "Faithful sandbox canary verdict per deploy (SANDBOX_CANARY_FAIL absent, consecutive_pass incrementing) plus the SOLEUR_CANARY_SANDBOX_DIAG host row carrying masked=0 (HostConfig.MaskedPaths count; docker never records systempaths in SecurityOpt)"
  cadence: "per deploy, for web-1 and web-2"
  alert_target: "Better Stack DEPLOY_ROLLBACK logs alert (betterstack-logs-alerts.tf) and the deploy-status hook"
  configured_in: "apps/web-platform/infra/ci-deploy.sh (canary block, _canary_diag_emit) and apps/web-platform/scripts/sandbox-canary.mjs"

error_reporting:
  destination: "Sentry web-platform project (SENTRY_DSN) via reportSilentFallback, tags feature=agent-sandbox op=bash-tool-result; existing op=sdk-startup events unchanged"
  fail_loud: "A Bash tool_result whose output carries a bwrap namespace token plus Operation not permitted is mirrored to Sentry (debounced per user) regardless of the command_stream posture gate"

failure_modes:
  - mode: "flag missing on one docker-run site (drift)"
    detection: "ci-deploy.test.sh parity assertion red in CI; post-deploy host diag row shows masked=<n> with n>0 on the running canary"
    alert_route: "CI required checks; deploy audit output"
  - mode: "flag present, faithful canary still fails (H7 AppArmor or another denial)"
    detection: "SANDBOX_CANARY_FAIL and sdk_probe rc != 0 in the same diag bundle; kdeny row is src=none (blind) until #10050"
    alert_route: "Better Stack DEPLOY_ROLLBACK alert; operator reads the bundle with scripts/betterstack-query.sh"
  - mode: "tenant Bash spawn fails in prod (any cause)"
    detection: "Sentry event feature=agent-sandbox op=bash-tool-result with errorCode and sandboxStderr, queried via the Sentry API"
    alert_route: "queryable now; paging is a tracked follow-up because the live sandbox-startup-failure rule is inert to edits until #7985"
  - mode: "mask not in force after the fix (cross-tenant exposure)"
    detection: "canary proc_mask probe (host pid absent from the sandbox's /proc) and the docker suite's sibling-pid-absence assertion"
    alert_route: "canary verdict proc_mask_defeated in the diag bundle; CI red"

logs:
  where: "journald ci-deploy and SOLEUR_CANARY_SANDBOX_DIAG rows shipped to Better Stack; Sentry for the app-side event"
  retention: "Better Stack source retention plan default; Sentry 90 days"

discoverability_test:
  command: bash scripts/betterstack-query.sh --since 3h --grep SOLEUR_CANARY_SANDBOX_DIAG
  expected_output: masked=0
  credentials_required: "Better Stack ClickHouse read credentials (Doppler soleur/prd_terraform) — log rows are not readable without them and no unauthenticated substitute verifies the deployed host posture"
```

Affected-surface observability (blind surface: agent bwrap sandbox): the in-surface probes are the canary's own in-container probes (`sdk_probe`, `sdk_noproc`, `proc_mask`, `direct_probe`), emitted from inside the container. The Sentry event carries `errorCode` (`bwrap_eperm` / `bwrap_error` / `proc_mount_eperm`), `sandboxKind` and `sdkVersion`, so one event discriminates a proc-mount denial from a userns/seccomp denial.

## Guard Contract

### Guard 1 — systempaths parity pin (inside `ci-deploy.test.sh`)

**Property.** Every `docker run` that creates the production container posture carries `--security-opt systempaths=unconfined` alongside the apparmor and seccomp options, and the running container reports an empty `MaskedPaths`.

**Assembly.** The derivation is scoped to lines inside a `docker run ... \` continuation block that carry `--security-opt seccomp=/etc/docker/seccomp-profiles/soleur-bwrap.json`: `ci-deploy.sh` canary, `ci-deploy.sh` prod, `cloud-init.yml`. It joins backslash continuations, strips comment lines first, and excludes fixtures and test files, because the bare profile path also appears in `audit-bwrap-uid.sh`, `cat-deploy-state.sh`, `server.tf`, `soleur-host-bootstrap.sh` and comments (measured by review). Chokepoint: the one derivation helper; a fourth site is covered the day it appears. The mock `docker inspect` models the REAL docker behaviour (flag absent from SecurityOpt, `MaskedPaths` empty), and the `host` diag row gains `masked=<n>` from `{{len .HostConfig.MaskedPaths}}` (mock whitelist and the row regex updated in lockstep).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the flag from the canary `docker run` | RED |
| 2 | Add a fourth `docker run` with the seccomp option and no flag | RED |
| 3 | Make the derivation match zero sites (rename the profile path) | RED (exits non-zero on `sites=0`) |
| 4 | Spell the flag `systempaths=confined` | RED |
| 5 | Move the flag into a comment on the prod site | RED (comments stripped before the check) |

**Harness rows.** Suite mutation: delete the final assertion summary line → the suite must red (an empty run cannot pass). Must-PASS non-canonical: a `docker run` with different whitespace and an extra `--security-opt` between the three options still passes.

**Anchor.** The pinned value is checked against the CODE; the integrity anchor outside the commit is the post-deploy `host` diag row (`masked=0` on the running canary), which a source edit cannot forge.

### Guard 2 — masked-/proc docker regression suite

**Property.** Under the production container posture (default docker masks, the committed seccomp and AppArmor profiles, uid 1001, the Debian bubblewrap), the SDK's replayed sandbox argv spawns through the shim, a fresh procfs mounts, and a process started outside the sandbox is invisible inside it.

**Assembly.** `sandbox-masked-proc-docker.test.sh` runs the same `sandbox-canary.mjs --replay` the deploy runs, through the shim at `infra/bwrap-shim/bwrap`, in a container started by the same security options as the three sites (the suite builds the option string from the parity guard's derived set, not a copy). Two arms: control (flag absent) and treatment (flag present). Chokepoint: the one `docker run` helper in the suite, used by both arms. The option set is hardcoded in the suite with a comment, and Guard 1 asserts the production sites carry the same tuple (no cross-suite coupling). The sibling sleeper is launched with `docker exec` in the SAME container, so it shares the sandbox's pid namespace; otherwise mutation 4 could not go red. Image: a lean image pinned to the Debian release that supplies bubblewrap 0.8.0, plus node for `sandbox-canary.mjs`, built in the job (measure its duration in the sandbox first; the step gets an explicit `timeout-minutes`). The suite sets `kernel.apparmor_restrict_unprivileged_userns=0` and treats a failed sysctl or a failed `apparmor_parser -r` as a hard failure.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop `systempaths=unconfined` from the treatment arm | RED (treatment fails `Can't mount proc`) |
| 2 | Run the control arm WITH the flag | RED (control must reproduce EPERM; a control that passes means the runner has no masks and the suite proves nothing) |
| 3 | Make the suite's docker unavailable / daemon down in CI mode | RED with literal token `DOCKER_UNAVAILABLE` (never exit 0) |
| 4 | Remove `--proc /proc` handling from the shim (revert the tail mask) | RED (sibling-pid-absence arm fails: host pid visible) |
| 5 | Start the sibling sleeper AFTER the sandbox spawns | RED (the arm asserts the sleeper's pid exists before spawn, so an ordering bug cannot pass) |

**Harness rows.** Suite mutations: replace the replay with `true` → red (non-vacuity row asserts the replay printed a verdict line); hand the suite an empty security-opt list → red. Must-PASS non-canonical: run the treatment arm with an extra harmless `--security-opt no-new-privileges=false` and a different container name; still passes.

**Anchor.** None stored; the suite compares two live arms, so it proves discrimination rather than consistency. The AppArmor arm needs the profile loaded on the runner: the suite loads it through `apparmor_parser -r` under sudo and fails loudly if it cannot. Registration: the suite is privileged, so it goes into `PRIVILEGED_WHY` in `run-registered-suites.sh` (otherwise the infra-glob derives it onto an unprivileged matrix leg), gets a `DOUBLE_COVERED_ACK` row in `lint-orphan-test-suites.sh`, a `suite-shard-legs.tsv` row, and an explicit `sudo bash` step in `deploy-script-tests-fixed` (the `workspaces-luks-loopback` pattern; a second `docker info` job exists near line 681, the fixed job near 838 is the one wanted).

**Property preserved by ordering.** The sibling-pid-absence assertion observes INSIDE the window (the sleeper is running when the sandbox spawns and is checked from within it), per the reorder-row rule.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "systempaths=unconfined (Recommended)" [brainstorm decision] | Phase 2 | mapped |
| 2 | "Regression test in docker (Recommended)" | Phase 1 / Guard 2 / Phase 3 | mapped |
| 3 | "Mirror Bash bwrap failures to Sentry" | Phase 4 | mapped |
| 4 | "Fix stale comments + ADR addendum" | Phase 5 | mapped |
| 5 | "CLO attestation under `knowledge-base/legal/audits/` and a new Art. 32 TOM cell are required" [brainstorm] | Phase 6 | mapped |
| 6 | "validate on the real image (bubblewrap 0.8.0, loaded soleur-bwrap AppArmor profile), and if the faithful canary still fails after the flag stop and treat H7 as live" [spec TR1/TR2] | Phase 7 + Guard 2 | mapped |
| 7 | "trace what Gd() and u5() check" [spec TR3] | Research Insights (resolved) + Phase 4.4 property assertion | mapped |
| 8 | "check the apply-seccomp helper's nested procfs mount after the fix" | Guard 2 treatment arm + Phase 7 | mapped |
| 9 | "Observability plan required" | `## Observability` | mapped |
| 10 | "the probably-empty `oom_journal_tail` in cat-deploy-state.sh" [issue comment] | — | descoped — justification: filed as #10050 per the CTO's assessment (host-IaC, own apply and gate) |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `ci-deploy.sh` flag (2 sites), `host` diag row `masked=` | "systempaths=unconfined (Recommended)" | asked |
| `cloud-init.yml` flag | "systempaths=unconfined (Recommended)" | asked |
| `ci-deploy.test.sh` parity assertion + mock correction | "systempaths=unconfined (Recommended)" | asked |
| `audit-bwrap-uid.sh` (+test) `MaskedPaths` read | — | inferred — justification: the operator SSH audit would otherwise keep asserting a `SecurityOpt` string docker never writes |
| `sandbox-masked-proc-docker.test.sh` + `infra-validation.yml` step + `run-registered-suites.sh` / `lint-orphan-test-suites.sh` / `suite-shard-legs.tsv` rows | "Regression test in docker (Recommended)" | asked |
| `sandbox-startup-classifier.ts`, `cc-dispatcher.ts`, classifier test | "Mirror Bash bwrap failures to Sentry" | asked |
| sandbox-config test assertion (`enableWeakerNestedSandbox` stays `true`) | "trace what Gd() and u5() check" | asked |
| `agent-runner-sandbox-config.ts` comments | "Fix stale comments + ADR addendum" | asked |
| ADR-075 addendum | "Fix stale comments + ADR addendum" | asked |
| `canary-probe-set.md` H6 row update | — | inferred — justification: the runbook names H6 PROBABLE and its `systempaths=` reading is wrong; the next reader would rebuild the stale model |
| `article-30-register.md` TOM cell, CLO attestation file | "CLO attestation under `knowledge-base/legal/audits/` and a new Art. 32 TOM cell are required" | asked |
| `cloud-init-user-data-size.test.ts` run | — | inferred — justification: the cloud-init edit is size-budgeted and the test reds on overflow |

### Split Assessment

- Subsystems touched: 4 — `apps/web-platform`, `.github`, `knowledge-base`, `scripts`
- Planned files: 19 | Estimated changed lines: 650
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — PR-B = Phase 4 (Sentry mirror: `cc-dispatcher.ts`, classifier, tests), PR-A = everything else. The operator selected the single-PR scope on 2026-10-11 ("Regression test in docker (Recommended), Mirror Bash bwrap failures to Sentry, Fix stale comments + ADR addendum"), so this plan stays one PR with Phase 4 as the last, independently revertable commit. Reviewers (DHH, simplicity) did not push the split; it is surfaced at the apply gate as a taste call.

## Implementation Phases

### Phase 1 — RED first (cq-write-failing-tests-before)
1.1 `ci-deploy.test.sh`: add the parity assertion (Guard 1) with the corrected mock (`MaskedPaths` empty, flag absent from SecurityOpt); red today.
1.2 `apps/web-platform/infra/sandbox-masked-proc-docker.test.sh` (Guard 2): control arm (EPERM reproduces) and treatment arm; red on the treatment arm until Phase 2 lands. Measure its duration in the allocated sandbox before wiring CI.
1.3 `apps/web-platform/test/sandbox-startup-classifier.test.ts`: cases for the Bash tool_result classifier using bwrap's REAL stderr text (`bwrap: Can't mount proc on /newroot/proc: Operation not permitted`) and at least two records (a denial and a non-sandbox permission error that must classify `other`).
1.4 Existing sandbox-config test (the one that already asserts the sandbox options in `agent-runner-sandbox-config.ts`; locate with `git grep -ln enableWeakerNestedSandbox apps/web-platform/test`): assert `enableWeakerNestedSandbox` stays `true`.
Run all in an allocated sandbox (`scripts/soleur-sandbox.sh new/run-isolated/rm`); measure assertion floors on the live tree (the sandbox has no `.git`).

### Phase 2 — the flag
2.1 Add `--security-opt systempaths=unconfined` to the canary (`ci-deploy.sh` near the `soleur-web-platform-canary` run) and prod (`soleur-web-platform` run) sites, with a comment naming the ADR-075 addendum and why. Read the canary-start failure path and confirm a rejected option fails before the prod stop.
2.2 Same in `cloud-init.yml`'s first-boot run; keep the edit within the user-data size budget and run `cloud-init-user-data-size.test.ts`.
2.3 `ci-deploy.sh` `host` diag row: add `masked=<n>` via `{{len .HostConfig.MaskedPaths}}`; update the `ci-deploy.test.sh` mock field whitelist and the D1g-style row regex in lockstep.
2.4 `audit-bwrap-uid.sh`: replace the would-be `SecurityOpt` assertion with a `HostConfig.MaskedPaths` read (expect `[]`); extend `audit-bwrap-uid.test.sh` with red and green fixtures.

### Phase 3 — CI wiring
3.1 `.github/workflows/infra-validation.yml`: an explicit `sudo bash` step for the docker suite in `deploy-script-tests-fixed` (the job that asserts a docker daemon), with `timeout-minutes` from the Phase 1.2 measurement.
3.2 Registration: `PRIVILEGED_WHY` in `run-registered-suites.sh`, a `DOUBLE_COVERED_ACK` row in `lint-orphan-test-suites.sh`, and a `suite-shard-legs.tsv` row. (The `ci-deploy.test.sh` assertion needs none: infra `*.test.sh` presence is registration, ADR-252.)

### Phase 4 — observability (last commit)
4.1 `sandbox-startup-classifier.ts`: add `classifyBashSandboxFailure(output)` reusing the namespace-token regex and the `Operation not permitted` requirement (do not fork them), adding the `Can't mount proc` shape as `proc_mount_eperm`.
4.2 `cc-dispatcher.ts` `onToolResult`: a sibling try/catch next to the posture-independent strand backstop (before the `command_stream` posture gate), mirroring through `mirrorWithDebounce` with `feature: agent-sandbox`, `op: bash-tool-result`. Data minimisation (gdpr-gate Art. 5(1)(c)): a `tool_result` is arbitrary command output, so the event carries ONLY the matched bwrap line(s), capped at ~300 characters, plus `errorCode`/`sandboxKind`/`sdkVersion` and the pseudonymized ids the startup mirror already carries — never the full output, the command, or workspace paths.
4.3 Legacy `agent-runner.ts` loop: out of scope — it has no tool-result observer and its session-level catch already classifies startup exits; recorded as the stated limit in the code comment.
4.4 A one-line comment in `server/agent-env.ts` that `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` is deliberately never set (it would force the weaker-sandbox arm off).

### Phase 5 — docs and records
5.1 Correct `agent-runner-sandbox-config.ts` comments (lines 36 and 571): the flag emits `--bind /proc /proc`; the shim masks it.
5.2 ADR-075 addendum (see `## Architecture Decision`); `canary-probe-set.md` H6 row (drop the `systempaths=` reading; the evidence is the control/treatment delta and `masked=`).
5.3 Read all three `.c4` files, record the actor/system/relationship check, run `c4-count-parity`.

### Phase 6 — legal records
6.1 `knowledge-base/legal/audits/2026-10-11-clo-attestation-sandbox-systempaths.md` (v1 internal attestation, drafted for the operator's CLO review) and the new Art. 32 TOM cell in `article-30-register.md`; name the choice as an input to the owed #9723-window Art. 33(5) assessment; name the in-sandbox `timer_list`/`sched_debug`/`interrupts` exposure.

### Phase 7 — ship and post-merge verification (agent-run reads and docs; only the production writes need the operator's explicit go-ahead)
7.1 Pre-merge: full test battery in the sandbox, CI green, review panel, `user-impact-reviewer`.
7.2 Merge (operator go-ahead). The apply workflow and the release workflow fire together; read the apply run's result for BOTH host jobs. Expect the first release deploy to have used the old host copy (failing canary, flag absent). Ask the operator for the go-ahead to re-run the release deploy; do not dispatch it unasked.
7.3 After the second deploy, the agent reads the bundle with `doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 3h --grep SOLEUR_CANARY_SANDBOX_DIAG` using Monitor with an until-loop, never sleep. Pass criteria are POSITIVE and tied to the deploy: rows for BOTH `soleur-web-platform` and `soleur-web-2` carrying the new image tag; `host` row `masked=0`; `sdk_probe rc=0`; `proc_mask` passes; plus `DEPLOY_SCRIPT_SHA` parity for both hosts. Absence of `SANDBOX_CANARY_FAIL` alone is not a pass (a deploy that never reached the canary produces the same absence).
7.4 If `sdk_probe` still fails with `masked=0`: STOP, read `kdeny`/`lsm`, treat H7 as live, comment the finding on #10032. The flag then buys nothing and widens the container; the follow-up is a revert PR (operator decision) unless the H7 fix is bundled. The failing state is not worse than today's, because the sandbox is already failing closed.
7.5 Only on a faithful pass: open the docs-only PR flipping the ADR addendum to `accepted` (CLO acknowledges), comment the bundle on #10032 and #9860, and close #10032 (and #9860 per the operator). PR bodies use `Ref`, never `Closes`.

## Files to Edit

- `apps/web-platform/infra/ci-deploy.sh`
- `apps/web-platform/infra/cloud-init.yml`
- `apps/web-platform/infra/ci-deploy.test.sh`
- `apps/web-platform/infra/audit-bwrap-uid.sh`
- `apps/web-platform/infra/audit-bwrap-uid.test.sh`
- `apps/web-platform/server/sandbox-startup-classifier.ts`
- `apps/web-platform/server/cc-dispatcher.ts`
- `apps/web-platform/server/agent-runner-sandbox-config.ts`
- `apps/web-platform/server/agent-env.ts` (comment only)
- `apps/web-platform/test/sandbox-startup-classifier.test.ts`
- the existing sandbox-config test (located in Phase 1.4)
- `.github/workflows/infra-validation.yml`
- `apps/web-platform/infra/run-registered-suites.sh` (or its repo path; locate with `git ls-files | grep run-registered-suites`)
- `scripts/lint-orphan-test-suites.sh`
- `scripts/suite-shard-legs.tsv`
- `knowledge-base/engineering/architecture/decisions/ADR-075-agent-sandbox-tenant-read-isolation.md`
- `knowledge-base/engineering/operations/runbooks/canary-probe-set.md`
- `knowledge-base/legal/article-30-register.md`

## Files to Create

- `apps/web-platform/infra/sandbox-masked-proc-docker.test.sh`
- `knowledge-base/legal/audits/2026-10-11-clo-attestation-sandbox-systempaths.md`

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `ci-deploy.test.sh` parity assertion is green and all five Guard 1 mutations drive it RED; the mock models docker's real behaviour (no `systempaths` in SecurityOpt, empty `MaskedPaths`); the `host` row reads `masked=0` in the fixture.
- [ ] `bash apps/web-platform/infra/sandbox-masked-proc-docker.test.sh` passes in `infra-validation.yml` under `sudo`: control arm reproduces `Can't mount proc` without the flag; treatment arm passes the canary replay (fresh procfs mounted, sibling pid absent inside the sandbox) with the real seccomp and AppArmor profiles loaded; all five Guard 2 mutations exit non-zero; an unusable docker daemon, sysctl or `apparmor_parser` fails with a literal token (`DOCKER_UNAVAILABLE` etc.), never exit 0. Its measured duration fits the step's `timeout-minutes`.
- [ ] `audit-bwrap-uid.test.sh` green with the `MaskedPaths` read.
- [ ] `classifyBashSandboxFailure` unit tests green on bwrap's real stderr text, including a non-sandbox permission error classified `other`; the `cc-dispatcher.ts` mirror is debounced per user and carries no command text or path.
- [ ] A classifier/dispatcher test feeds a `tool_result` carrying a bwrap `Can't mount proc` line next to a secret-looking line and asserts the mirrored event contains the bwrap line and NOT the secret line (full output never leaves the process).
- [ ] The sandbox-config test fails if `enableWeakerNestedSandbox` is flipped off.
- [ ] ADR-075 addendum present (status `adopting`, contradicting line corrected), `canary-probe-set.md` H6 row updated, stale comments corrected: `git grep -nE 'skips .?--proc' apps/web-platform/server/agent-runner-sandbox-config.ts` returns nothing (the pattern tolerates the backticked spelling at line 36).
- [ ] CLO attestation file and the Art. 32 TOM cell exist; `cloud-init-user-data-size.test.ts` and `c4-count-parity.test.sh` green; the three `.c4` files were read and the check is recorded.
- [ ] `soleur:preflight` Check 10 treats the discoverability probe as `SKIP-DECLARED` (credentials declared) and `BASELINE_DECLARED_PROBES` is updated on top of main's value (count plans recursively).
- [ ] PR body uses `Ref #10032` and `Ref #9860`, never `Closes`.

### Post-merge (agent-run reads; production writes gated on the operator)
- [ ] Apply workflow succeeded for both host jobs; after the (operator-approved) second deploy, `DEPLOY_SCRIPT_SHA` parity reports both hosts equal to the repo.
- [ ] Second-deploy bundle for both hosts and the new image tag: `masked=0`, `sdk_probe rc=0`, `proc_mask` passes; ADR flip PR opened, #10032 and #9860 commented and closed per Phase 7.5.

## Test Scenarios

1. Control arm: docker default masks, no flag → bwrap fresh `--proc` EPERM (reproduces #10032).
2. Treatment arm: flag set → replay passes; a sleeper started outside the sandbox (via `docker exec`, same pid namespace) is absent from the sandbox's `/proc`.
3. Drift: a fourth `docker run` with the seccomp option and no flag → parity assertion red; a flag only in a comment → red.
4. Bash tool_result with `bwrap: Can't mount proc on /newroot/proc: Operation not permitted` → one Sentry mirror carrying only the matched line, debounced on repeat; the same result with an extra secret-looking line → event lacks that line; `cat: /x: Permission denied` → no mirror.
5. `enableWeakerNestedSandbox` flipped off in the config → test red.
6. First release deploy runs the old host copy → canary fails once more; plan expects it and asks for the second deploy.
7. Post-deploy, `masked=0` and canary still failing → plan halts at Phase 7.4 (H7), nothing widened further.

## Dependencies & Risks

- **Residual widening (accepted, recorded):** `systempaths=unconfined` drops maskedPaths AND readonlyPaths for the whole shared container: `/proc/{sys,irq,bus,fs,sysrq-trigger}` become rw-mounted and `/proc/{acpi,kcore,keys,timer_list,sched_debug,scsi,interrupts}` unmasked. Compensation is DAC plus capabilities (non-root server, no `SYS_ADMIN`, root-owned files), not AppArmor (which only denies `/proc/kcore`, `/proc/sysrq-trigger` and writes under `/proc/sys/kernel/`). New in-sandbox exposure: the fresh procfs shows the global world-readable `timer_list`/`sched_debug`/`interrupts` (host-wide task names and pids, information-level, cross-tenant). Unchanged and not closed: the CLI file-tool tier's same-uid `/proc/<pid>/environ` (held by `ptrace_scope=1` and #9773).
- **H7 unproven locally:** CTO's local runs used `apparmor=unconfined` and bwrap 0.12.0 (image: 0.8.0). Mitigation: CI loads the real profile on a Debian-bubblewrap image; the production canary is the arbiter and Phase 7.4 is the stop.
- **Delivery race:** the release can run the old host script; handled by Phase 7.2 and an explicit second deploy. Atomic-write check on the provisioner is a Phase 2 verification.
- **Docker-daemon dependence:** the new suite needs a real daemon, sudo and a loadable AppArmor profile; it fails loudly rather than skipping.
- **Disruption:** the deploy recreate runs `docker stop --time=12` on prod, ending in-flight agent sessions; stated, not hidden.
- **Brittle matching:** the Sentry classifier matches bwrap stderr strings across bubblewrap versions; the unit test pins real stderr text.
- **Deferred (tracked):** least-privilege kernel-stream read for the deploy user and `oom_journal_tail` → #10050; paging alert for `op=bash-tool-result` → #10052 (hard dependency for the mirror to be more than queryable; blocked on the #7985 alert-rule conversion).

## References

#10032, #9860, #10043 (draft PR), #10050, #10052, #9773 (topology residual), #7985 (Sentry alert conversion); ADR-075, ADR-079; `knowledge-base/engineering/operations/runbooks/canary-probe-set.md`; learnings listed under Research Insights.
