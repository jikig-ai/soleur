---
title: "fix: apply-deploy-pipeline-fix verify step re-polls but never re-POSTs, so it cannot recover from the documented webhook-restart race"
date: 2026-08-12
slug: fix-apply-verify-repost-recovery
branch: feat-one-shot-7104-apply-verify-repost-recovery
type: fix
issue: 7104
closes: 7104
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

`apply-deploy-pipeline-fix.yml`'s "Verify infra-config apply succeeded" step polls the
host's `/hooks/infra-config-status` frame three times and then adjudicates. Every
attempt reads the same state; nothing in the step re-sends the push. When the
webhook-restart race documented at `push-infra-config.sh` (the redeploy-nonce
comment block, nonce-1) occurs, the push is accepted with HTTP 202 but the async
handler exec is disrupted and no files are written — so the frame never changes and
the gate polls a value that cannot move. The recorded route back is a re-run driven
by hand.

This plan adds a bounded, one-shot re-push and re-verify, gated on a status shape
consistent with that race, while keeping the terminal red intact when both passes
fail.

## Enhancement Summary

**Deepened on:** 2026-08-12
**Halt gates run:** 4.5 (network-outage — fired), 4.6 (user-brand impact — pass), 4.7
(observability — pass, all five fields, probe verb `bash`, no `ssh`), 4.8 (PAT-shaped — no hits),
4.9 (UI wireframe — no UI surface, skipped), 4.10 (encryption posture — no store or new connection,
skipped), 4.11 (guard contract — `python3 scripts/lint-guard-contract.py` green, 2 guard entries),
4.55 (downtime/cutover — not triggered; no `hcloud_server`/volume replacement, and R3's
exact-cardinality assert forbids one by construction).

**Agents used:** `repo-research-analyst`, `learnings-researcher`, `functional-discovery`,
`Explore` (C4 enumeration), `cto`, `coo`, plus the escalated plan-review panel
(`dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`,
`architecture-strategist`, `spec-flow-analyzer`) and `cpo`.

### Key improvements

1. **Three P0 fail-opens caught before implementation**, each inside a revision the plan had
   already adopted: the `ALLOW_MISSING_STATUS` escape hatch would have been read as "verified"
   by the orchestrator (R15.1); wrapping the verify body in a function silently disables `set -e`
   for its whole body (R16.1); and `DPF_REPLACED` had no fail-closed polarity guard while the arm
   it protects was near-vacuous by construction (R17.1).
2. **The design pivoted** from a higher-order orchestrator to a **pure predicate** matching the six
   existing siblings in `infra-config-gate.sh` (R16.2). One change dissolves four findings.
3. **The scope split** into PR-A (sensor) and PR-B (actuator) on a one-directional dependency —
   three reviewers converged independently, and CPO made it a sign-off condition (R14.3).
4. **Two agent claims were rejected on measurement** rather than inherited: a cited ADR-068
   precedent that does not exist, and a "`server.tf` is not in the paths filter" claim contradicted
   by the filter itself (R7).
5. **A live defect on `main` was found and scoped in**: the #7220 freshness pin reds three supported
   merge classes, and the `host_creates` destroy-guard has been adjudicating a plan the apply
   discards (R1).

### New considerations discovered

- Two live CI gates the plan had never consulted — AP-022 (`lint-workflow-errexit-capture.py`) and
  AP-021 (`lint-diagnosis-claims.sh`) — one of which AC7 directly contradicts (R17.2).
- The alert helper has no class for "the recovery apply failed", so that path would emit a
  measurably false message to a non-technical operator (R17.2).
- A deterministic concurrency collision on `systemd-run --unit=webhook-self-restart` (R17.5).
- `terraform apply <planfile>` rejects `-target` and `-var`, which R4d's reasoning got wrong (R17.3).

### Scoping note, disclosed rather than silent

The generic Phase 5 "run every discovered agent" fan-out was **not** executed. Eleven agents had
already reviewed this plan — including the full escalated panel this threshold mandates — and they
converged on a consistent finding set with three P0s. The remaining budget was spent folding those
findings in (R13–R17) rather than adding breadth that the convergence suggests would be redundant.
The one deepening action every reviewer asked for — reconciling `## Implementation Phases` and
`## Test Scenarios` against the revisions — is carried as task 1.1 in `tasks.md` and is the first
thing `/work` must do.

## Network-Outage Deep-Dive (Phase 4.5)

Triggered on both arms: the plan's prose names `502`, `503`, `unreachable` and `timeout`, **and**
it drives `terraform apply` against resources whose definitions carry `provisioner "remote-exec"`
and `connection { type = "ssh" }` (the resource-shape trigger that the prose-only scan misses).

| Layer | Status | Artifact |
|---|---|---|
| **L3 — firewall allow-list** | **Verified not applicable** | The recovery opens no new source, port or destination. Its only network call is `push-infra-config.sh`'s `curl` to `https://deploy.<APP_DOMAIN_BASE>/hooks/infra-config`, byte-identical to the one `deploy_pipeline_fix`'s `local-exec` already makes. The host's admin-IP allow-list gates **SSH (port 22)**, not the tunnel — and R3's exact-cardinality assert proves no SSH-provisioned resource is in the recovery's plan. |
| **L3 — DNS / routing** | **Verified by prior exercise in the same run** | `deploy.<APP_DOMAIN_BASE>` is resolved twice before the gate — by `Verify webhook is alive post-apply` and by the gate's own poll — and both must have succeeded for the classified shape to be reachable, since it requires an HTTP 200. A resolution or routing failure surfaces as `000`, which routes to terminal red with **no** re-push. |
| **L7 — TLS / proxy (Cloudflare Access)** | **Verified by construction** | The classifier fires only on a **parseable JSON frame**, obtainable only through a 200 past Cloudflare Access. An edge error page, an Access challenge or a 5xx yields an unparseable body → classified `unreachable` → terminal red, no re-push. This is the "listener reachable" half of the issue's own gate condition, satisfied without a second probe. |
| **L7 — application (`webhook` on `web-1`)** | **The only layer the plan acts on** | The recorded mechanism is `push-infra-config.sh`'s `REDEPLOY NONCE` block (nonce-1). The signal is the checklist's "absence is itself a signal" case: the host's own status endpoint **answers**, and its answer is "the last apply I ran was an earlier one". |

**Gap closed by the deep-dive.** The L7 hypothesis set was initially under-specified in one place:
`infra-config-apply.sh` has **no `flock` and no serialization**, so `no_new_frame` cannot separate
"the handler never started" from "the handler is still running". R10 (as revised by R13.4 and
R15.3) addresses it by widening the *existing* poll loop rather than adding a second one, and
R17.5 sizes that window against the handler's own timings (+3 s scheduled restart, ~5–8 s listener
boot) and identifies the deterministic `systemd-run --unit=webhook-self-restart` collision that a
premature re-push would cause.

**No layer is left unverified, and no service-layer fix is proposed ahead of an L3 check** — the
ordering discipline `hr-ssh-diagnosis-verify-firewall` exists to enforce.

## Research Insights

### Premise validation (Phase 0.6)

Every premise the issue and the pipeline brief assert was re-checked against this
worktree at `a30a3e187` (one `chore:` commit above `origin/main` `0d6443960`). All held.

| Premise | Probe | Verdict |
|---|---|---|
| Issue #7104 is open and unresolved | `gh issue view 7104 --json state,closedByPullRequestsReferences` → `OPEN`, `[]` | HOLDS |
| The verify step re-polls but never re-POSTs | Read of the step body: a `for attempt in 1 2 3` loop issuing `GET /hooks/infra-config-status`, then a terminal adjudication. No POST anywhere in the step. | HOLDS |
| `deploy_pipeline_fix` depends on `infra_config_handler_bootstrap` | `server.tf`, the `depends_on` line of `resource "terraform_data" "deploy_pipeline_fix"` names `terraform_data.apparmor_bwrap_profile` and `terraform_data.infra_config_handler_bootstrap` | HOLDS — the "first apply guaranteed to fail on a stale `hooks.json`" premise is FALSIFIED, as the issue states |
| A plain second apply is a no-op; `-replace` is required | The resource is `terraform_data` keyed on `triggers_replace`; after a successful apply the hash already matches. `-target` selects, it does not force replacement — stated verbatim in the workflow's own 000/502/503 recovery message. | HOLDS |
| No `continue-on-error` and no `-replace=terraform_data.deploy_pipeline_fix` exist today | `grep -n 'continue-on-error\|-replace=' .github/workflows/apply-deploy-pipeline-fix.yml` → zero `continue-on-error`; the only `-replace=` occurrences are inside `::error::` recovery **prose**, and both name `terraform_data.infra_config_handler_bootstrap`, not `deploy_pipeline_fix` | HOLDS — the defect is unfixed |
| The 000/502/503 branch is diagnosis, not recovery | Read of that branch: it emits two `::error::` lines and `exit 1`. No apply, no push. | HOLDS |
| The race is recorded in-repo | `push-infra-config.sh`, the `REDEPLOY NONCE` comment block, nonce-1 paragraph | HOLDS |

One premise in the pipeline brief needed correction: the brief cites the verify step
"currently at line 518". That is accurate for this tree, but per `cq-cite-content-anchor-not-line-number`
this plan cites it as **the step named `Verify infra-config apply succeeded`, `id: infra_config_gate`**.

### Property list (Phase 0.6b)

Restating the ask as observable outcomes, independent of any mechanism:

- **P1 — Recoverable.** A run whose first verification fails *because the host published no
  frame for this apply* re-sends the push automatically and can still finish green.
- **P2 — Bounded.** At most one re-push per run. No loop, no backoff ladder, no second retry.
- **P3 — Narrow.** The re-push fires only for the shape that a re-push can actually fix.
  Every other failure shape reaches the terminal red without a re-push.
- **P4 — Still fail-closed.** When the first pass fails and the second pass also fails —
  or never runs, or cannot be classified — the job goes red. This is the primary
  acceptance criterion.
- **P5 — Provable.** P4 is demonstrated by a test that can be driven RED by breaking it,
  not asserted in prose.
- **P6 — Alerting preserved.** A terminally-red gate still files the plain-language GitHub
  issue and Sentry event, and a run that *recovered* does not file one.

### Cut list (Phase 0.6b)

Mechanisms named in the ask or reachable for it, removed here because a mechanism already
on `origin/main` buys the property:

| Mechanism proposed | Property it would buy | Already covered by | Disposition |
|---|---|---|---|
| A new fixture-driven test harness | P5 | `apps/web-platform/infra/infra-config-gate.test.sh` — a hermetic harness that synthesises the infra dir from the real `FILE_MAP`, builds status-frame fixtures, counts `pass`/`fail`, and enforces a `GATE_MIN_ASSERTIONS` floor so deleted assertions red the suite | CUT — extend the existing harness and raise its floor |
| A bespoke "listener reachable" HTTP probe before the re-push | P3 (the "listener reachable" half of the issue's discriminator) | The classifier only ever fires on a parseable frame, and a parseable frame is only obtainable from an HTTP 200 on `/hooks/infra-config-status`. Reachability is therefore established *by construction*. | CUT — a second probe would restate what the 200 already proves |
| A separate "diagnose a bricked listener" branch | Diagnosis of the 000/502/503 shape | Already present as a distinct terminal branch with its own recovery text (added by #7095 R34) | CUT — the issue itself calls this complementary, not a substitute |
| Race-shape classification written inline in the workflow YAML | P3 + P5 | The repo's own precedent (#6594 PR-B) put gate adjudication in a sourceable, tested script (`infra-config-gate.sh`) precisely so the workflow's decision logic is testable. Inline YAML is untestable by the existing harness. | CUT as *inline* — the classifier goes into `infra-config-gate.sh` |

### The mechanism this plan keeps, and why it is the minimum

The one property with **no** existing coverage is P1: nothing in the repo re-sends the push
automatically. The manual remedy is documented and is exactly `nonce-2` in
`push-infra-config.sh` — *"changes ONLY this file → recreates ONLY `deploy_pipeline_fix` →
the push runs against the now-stable webhook + current handler/hooks.json"*. A
`terraform apply -replace=terraform_data.deploy_pipeline_fix` is the same operation without
requiring a commit. **This plan automates the remedy the repo already documents as correct**,
rather than inventing a recovery.

### The discriminator, named correctly

The issue phrases the gate condition as "no delivery record for the new dests, listener
reachable". Expressed in the frame's own fields, that is exactly:

> HTTP 200 **and** the body parses as JSON **and** it carries a numeric `start_ts` **and**
> `start_ts < APPLY_START_EPOCH`.

That is the **`no_new_frame`** shape — the host published no frame for *this* apply. Two
things make it the right predicate rather than an approximation:

- The mechanism is already in the tree. The apply step records `APPLY_START_EPOCH` before
  the apply, and the gate already fails on `STALE FRAME` when `start_ts` predates it
  (the #7220 freshness pin). This plan reuses that comparison as a *classifier*; it does not
  invent a new signal.
- It is computable independently of *which* assert fired first. Under the race the frame is
  the previous apply's, so it can red the count invariant (nonce-1 was 13/13 against an
  expected 15), the content assert, or the freshness pin, depending on what the merge changed.
  A discriminator keyed on the failing assert would be incomplete; one keyed on `start_ts` is not.

Deliberately **excluded** from the re-push (each goes straight to terminal red):

| Excluded shape | Why a re-push is wrong |
|---|---|
| HTTP 404 | Stale `hooks.json` predating the status endpoint. The handler bootstrap is the lever, and the existing branch already says so. |
| HTTP 000 / 502 / 503 | The listener is down. The workflow's own recovery text states `-replace` on the **handler bootstrap** is the route back and that a `deploy_pipeline_fix` re-run is not. Re-pushing into a dead listener cannot work. |
| A **fresh** frame with `files_failed > 0`, `exit_code != 0`, or `fatal_line > 0` | The handler ran and attributed its own failure. This is a delivery/activation failure with a named cause, which #7220's alert already renders. Re-pushing would mask a real defect. |
| A frame with no numeric `start_ts` (schema v1 handler) | Freshness is unknowable, so the race cannot be distinguished from a genuine failure. Fail closed. |
| An unparseable body | Not a frame at all. Treated as unreachable. |

### Relevant files

| Path | Role in this change |
|---|---|
| `.github/workflows/apply-deploy-pipeline-fix.yml` | The workflow. `id: infra_config_gate` is the verify step; `id: terraform_apply` records `APPLY_START_EPOCH`. |
| `apps/web-platform/infra/infra-config-gate.sh` | Sourceable adjudicator. Exposes `infra_config_expected_count`, `infra_config_expected_restart_units`, `infra_config_classify_files`, `infra_config_count_invariant`, `infra_config_content_assert`, `adjudicate_infra_config`. The new classifier belongs here. |
| `apps/web-platform/infra/infra-config-gate.test.sh` | Hermetic harness. Synthesises the infra dir from the real `FILE_MAP`, has a `build_status_json` fixture builder, `pass`/`fail` counters, a `GATE_MIN_ASSERTIONS` floor, and already pins the workflow's call-site placement. |
| `apps/web-platform/infra/push-infra-config.sh` | The push. `local-exec` only — HTTPS, no SSH (#3756). Its nonce block is the recorded provenance of the race. |
| `apps/web-platform/infra/infra-config-apply.sh` | The host handler. Its `FILE_MAP` is the count authority; its exit trap publishes the status frame. |
| `apps/web-platform/infra/server.tf` | `terraform_data.deploy_pipeline_fix` and `terraform_data.infra_config_handler_bootstrap`. |
| `scripts/infra-config-red-alert.sh` | `infra_config_red_alert <detail> <class>`; classes are `reachable`, `unreachable`, `ungraded`. |
| `.github/workflows/infra-validation.yml` | Where `infra-config-gate.test.sh` is registered as `run: bash …`. |
| `apps/web-platform/infra/run-registered-suites.sh` | **Derives** its suite list from `infra-validation.yml`. An unregistered `*.test.sh` is reported as an orphan and never runs. |
| `tests/scripts/lib/destroy-guard-filter-web-platform.jq` | The `host_creates` filter the plan step runs against `terraform show -json`. |

### The status frame's field surface

The discriminator and the tests are written against these fields, published by the handler's
exit trap: `schema_version`, `start_ts`, `end_ts`, `exit_code`, `files_written`,
`files_failed`, `files_total`, `fatal_rc`, `fatal_line`, `fatal_cmd`, `files[]`
(`file`, `sha256`, `status`, `changed`, `reason`), and `restarts[]` (`unit`, `action`,
`reason`, `rc`, `active`, `nrestarts`, `exec_main_start_ts_before`, `exec_main_start_ts_after`).
Per-file failure reasons the handler can emit: `missing_env`, `payload_file_unreadable`,
`install_rejected`, `install_failed`, `hooks_json_unparseable`, `orphan_hook_command`.

### The assembly: what currently makes this job green

Enumerated from `grep -nE "^      - name:|^        id:|^        if:" .github/workflows/apply-deploy-pipeline-fix.yml`.
This is the list any change to the gate's failure semantics quantifies over, and it is the
reason this plan does **not** adopt `continue-on-error` (see Alternatives Considered).

| Step | Condition | What `continue-on-error` on the gate would do to it |
|---|---|---|
| `Alert on a red infra-config gate (#7220)` | `failure() && steps.infra_config_gate.outcome != 'success'` | `failure()` becomes false while the job is still nominally succeeding, so the P0 alert **goes dark** on a first-pass failure |
| `Redeploy to load applied profile and assert loaded==committed` | `success()` | Runs against an **unverified** host and swaps the container |
| `Check whether #4804 is still open` | `success()` | Runs |
| `Verify journald_storage no-SSH surface is live` | `success() && steps.check_4804.outputs.open == 'true'` | Runs |
| `Close #4804 after self-heal verified` | `success() && …` | **Closes an issue** on an unverified apply |
| `Auto-close any open drift issues for this stack` | `success()` | **Closes drift issues** on an unverified apply |
| `Post-apply summary` | `always()` | Reports success |

### Institutional learnings that shaped this plan

| Learning | Applied as |
|---|---|
| `knowledge-base/project/learnings/best-practices/2026-05-05-workflow-jwt-mint-silent-failure-traps.md` — *"`if: failure()` does NOT fire when the previous step has `continue-on-error: true`"*, fix is `steps.<id>.outcome == 'failure'` under `always()` | The decisive input to the Alternatives Considered table. This plan avoids the trap by not introducing `continue-on-error` at all. |
| `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` — *"What is the cheapest edit that breaks the property this guard NAMES, while leaving the guard GREEN?"* | The `## Guard Contract` mutation matrix, including a row targeting the guard's own dispatch. |
| `knowledge-base/project/learnings/test-failures/2026-04-19-retry-once-early-return-masks-first-attempt-failures.md` — a retry-once shape that asserts only the second attempt is blind to the first | Each pass's verdict is recorded and asserted **independently**; the test never collapses to "the last attempt passed". |
| `knowledge-base/project/learnings/2026-08-10-every-gate-i-built-passed-85-green-assertions-and-had-two-fail-opens.md` — `\|\| true` and `2>/dev/null` turning failures into clean passes | No `\|\| true` on the re-apply. Its exit status is a first-class input to the verdict, and an unset/empty verdict is treated as RED. |
| `knowledge-base/project/learnings/2026-07-17-target-scoped-terraform-apply-makes-resource-deletion-a-silent-noop.md` — a `-target`-scoped apply only touches targeted resources | `terraform_data.deploy_pipeline_fix` must appear in **both** the `-replace=` and the `-target=` set of the second pass, or the replace is silently a no-op. |
| `knowledge-base/project/learnings/best-practices/2026-07-03-enforcement-probe-must-discriminate-exit-codes-not-any-failure-as-safe.md` — a probe whose polarity does not match its failure mode is fail-open | The classifier is an **allow-list**: exactly one shape triggers the re-push; everything else, including "could not classify", is terminal. |
| `knowledge-base/project/learnings/2026-08-05-every-green-signal-certified-something-other-than-what-it-claimed.md` — an assertion certifying a property adjacent to the one it names | The test asserts on the extracted routine that the workflow **actually calls**, and pins the call site, rather than on a reimplementation. |

### Conventions carried from `AGENTS.md` / `AGENTS.rules.md`

- `hr-when-a-command-exits-non-zero-or-prints` — the re-apply's non-zero exit is surfaced, never swallowed.
- `cq-cite-content-anchor-not-line-number` — this plan cites step names, `id:`s and function names, not line numbers.
- `cq-assert-anchor-not-bare-token` and its input-side twin (`#7003`) — verification commands run the gate's own invocation, not a hand-enumerated reconstruction.
- `hr-no-ssh-fallback-in-runbooks` and `hr-observability-as-plan-quality-gate` — no step of the recovery or its diagnosis requires SSH.
- `hr-no-dashboard-eyeball-pull-data-yourself` — post-merge verification is a `gh workflow run` plus a `gh run view`, not an operator watching a dashboard.
- `cq-test-fixtures-synthesized-only` — new fixtures carry synthesised paths and hashes, matching the existing harness.

### Prior art / related issues

- **#7104** — this issue. Filed out of #7095's PR-A (#7097).
- **#7095 / #7097** — added the 000/502/503 terminal branch (R34) and the tier-2 rendered-digest compare; deferred this re-POST residual deliberately.
- **#7220** — added `APPLY_START_EPOCH` + the `STALE FRAME` freshness pin, and the red-gate alert step. Both are load-bearing here.
- **#6594** — the latched false-green that moved adjudication into `infra-config-gate.sh` and created the test harness this plan extends.
- **#6178** — the under-delivery count guard; its nonce-1 write-up is the race's provenance.
- **#5515** — added the `depends_on` edge that narrows (but does not close) the race window.
- **#4804** — the original false-success freeze vector behind the 404 branch.

### External research

None commissioned. The change is a control-flow decision inside this repo's own workflow;
`functional-discovery` swept three community registries and returned no relevant capability
(the nearest hits were a generic Terraform drift-detector and generic "fix my failing
pipeline" plugins, neither of which touches step-outcome adjudication). GitHub Actions
step-outcome semantics are covered by the institutional learning above rather than by a
fresh docs fetch.

### Skill-description budget (Phase 1.8)

Not applicable — no `plugins/soleur/skills/*/SKILL.md` `description:` is a candidate edit in
this plan's file list.

### Research reconciliation — brief vs. codebase

| Brief claim | Codebase reality | Plan response |
|---|---|---|
| "the verify step (currently at line 518)" | Correct at `a30a3e187`, but line numbers rot | Cite the step by `name:` and `id:` throughout (`cq-cite-content-anchor-not-line-number`) |
| Suggested shape point 1: `continue-on-error: true` on the verify step | Seven downstream steps key off job success; two of them auto-close GitHub issues, one swaps the running container, and the #7220 alert's `failure()` clause goes dark | **Deviation.** The plan keeps the step fail-closed and does the bounded re-push *inside* it. Recorded as a User-Challenge — see `## Alternatives Considered` and `decision-challenges.md`. Points 2, 3 and 4 are honoured as written. |
| Suggested shape point 3: "a final adjudication step" | In the in-step shape the final adjudication is the last statement of the same step, and it is the thing that fails closed | Honoured in substance: the terminal verdict is a single tested function whose only success arms are "pass 1 green" or "pass 2 green" |
| "no delivery record for the new dests" as the race predicate | The frame is whole-apply, not per-dest; the observable is that the host published **no frame at all** for this apply | Predicate named `no_new_frame` and defined on `start_ts` vs `APPLY_START_EPOCH` — strictly equivalent and directly computable |

## Hypotheses

Phase 1.4 fired: the brief names `502`, `503`, `unreachable` and `timeout`, and the targeted
resources carry `connection { type = "ssh" }` + `remote-exec` provisioners. The L3→L7 order is
therefore mandatory before any service-layer hypothesis. Two things scope it here: **this is not
an active outage** (it is a latent recovery gap in a workflow), and **the failing hop is
explicitly HTTPS**, not SSH.

1. **L3 — firewall allow-list.** *Not applicable, with an artifact rather than an assertion.*
   The re-push travels the same path the existing push already travels: a GitHub-hosted runner →
   `https://deploy.<APP_DOMAIN_BASE>/hooks/infra-config` through Cloudflare Access, authenticated
   by `CF-Access-Client-Id` / `CF-Access-Client-Secret` and HMAC. It opens no new source, no new
   port, and no new destination. The artifact is the push script itself: its `curl` invocation is
   the *only* network call the recovery adds, and it is byte-identical to the one already made by
   `terraform_data.deploy_pipeline_fix`'s `local-exec`. No `hcloud firewall` rule is consulted on
   this path because the host's admin-IP allow-list gates SSH (port 22), not the tunnel.
2. **L3 — DNS / routing.** *Not applicable, same artifact.* `deploy.<APP_DOMAIN_BASE>` resolution
   is already exercised twice per run before the gate — by `Verify webhook is alive post-apply`
   and by the gate's own poll — and both must have succeeded for the `no_new_frame` shape to be
   reachable at all (it requires an HTTP 200). A resolution or routing failure surfaces as
   `000`, which this plan routes to terminal red without a re-push.
3. **L7 — TLS / proxy layer.** *Verified by construction.* The classifier only fires on a
   **parseable JSON frame**, which is obtainable only from an HTTP 200 through Cloudflare Access.
   A Cloudflare error page, an Access challenge, or a 5xx from the edge yields a non-parseable
   body, and the plan classifies that as `unreachable` → terminal red, no re-push. This is the
   "listener reachable" half of the issue's own gate condition, satisfied without a second probe.
4. **L7 — application layer (the `webhook` listener on `web-1`).** *This is where the real
   hypothesis lives, and it is the only one the plan acts on.* The recorded mechanism is in
   `push-infra-config.sh`'s `REDEPLOY NONCE` block: the bridge's listener-restart step returned
   while the listener was still coming up, the push was accepted (HTTP 202) by the restarting
   listener, and the async handler exec was disrupted — so the handler never ran and never
   published a frame. The absence of a new frame **is** the L7 signal, and it is exactly the
   checklist's "no journal entry exists is itself strong evidence" case: the host's own status
   endpoint answers, and its answer is "the last apply I ran was an earlier one".

**Competing L7 hypotheses the plan deliberately does not act on**, because each publishes a
*fresh* frame that attributes its own failure and therefore falsifies `no_new_frame`: a handler
that started and died (`fatal_line > 0`), a per-file delivery failure (`files_failed > 0`,
`reason` ∈ `missing_env` / `install_rejected` / `install_failed` / `payload_file_unreadable` /
`hooks_json_unparseable` / `orphan_hook_command`), and a unit that did not come back
(`restarts[].action == "failed"`). Re-pushing on any of these would mask a real defect.

**One hypothesis the plan cannot distinguish and must therefore bound: clock skew.**
`start_ts` is generated on the host; `APPLY_START_EPOCH` is generated on the runner. A host
clock behind the runner's makes a genuinely fresh frame read as stale. The consequence is
bounded by construction — one idempotent re-push, then a terminal red — but the terminal message
must name clock skew as a candidate, or the next engineer will chase the race that is not there.

## Files to Edit

| Path | Change |
|---|---|
| `.github/workflows/apply-deploy-pipeline-fix.yml` | In the step `Verify infra-config apply succeeded` (`id: infra_config_gate`): wrap the existing poll-loop + terminal adjudication + freshness pin into a shell function `verify_once`, add a `repush_once` function, and make the step's last statement a call to the tested orchestrator. **Superseded in part — see `## Plan Revisions`: the `Terraform plan`/`Terraform apply` steps also change to produce and consume a saved plan file, and the bridge teardown is NOT relocated.** |
| `apps/web-platform/infra/infra-config-gate.sh` | Add `infra_config_no_new_frame` (the classifier) and `infra_config_bounded_verify` (the orchestrator + terminal verdict). No existing function changes behaviour. |
| `apps/web-platform/infra/infra-config-gate.test.sh` | Add the classifier cases, the orchestrator mutation matrix, the re-pointed production call-site pin, and raise `GATE_MIN_ASSERTIONS`. |
| `knowledge-base/engineering/architecture/decisions/` | New ADR (provisional ordinal **186** — re-derive before merge) recording the bounded-re-push invariant. |
| `knowledge-base/project/specs/feat-one-shot-7104-apply-verify-repost-recovery/tasks.md` | Task breakdown (written by Save Tasks). |

## Files to Create

| Path | Purpose |
|---|---|
| `knowledge-base/project/specs/feat-one-shot-7104-apply-verify-repost-recovery/decision-challenges.md` | The `continue-on-error` User-Challenge, the scope-growth challenge, and the CPO sign-off item, for `ship` to render into the PR body and file as an `action-required` issue. |
| `knowledge-base/engineering/architecture/decisions/ADR-<ordinal>-ci-verification-gate-bounded-self-remediation.md` | The ADR from R8. Ordinal re-derived immediately before merge. |
*(An earlier draft also listed `knowledge-base/engineering/operations/runbooks/infra-config-channel-red.md`.
**R13.10 re-dispositioned it to a filed issue** rather than 150 lines written inline — the same
disposition R9.1 already had, so the two pre-existing gaps are now handled consistently. The path
appears elsewhere in this plan as the proposed name for that issue, not as a file this PR creates.)*

**A label must be created, not assumed.** `gh label list` confirms `ci/infra-config-red`,
`priority/p3-low`, `domain/engineering` and `action-required` all exist. The ledger label from
R14.2 **does not exist** and must be created as an explicit task — a plan that prescribes a
non-existent label fails at first fire, and under `set -euo pipefail` that either reds an otherwise
green recovered run or silently drops the only recovery signal. Note R14.2 also moved the ledger
**out of the `ci/` namespace**, so the name is not `ci/infra-config-recovered`; pick one that reads
as a tally rather than an alarm.

**Deliberately NOT created: a new `*.test.sh` file, and a new extracted `infra-config-verify.sh`.**
Both were considered and cut. See `## Alternatives Considered` — the decisive reason is that
`infra-config-gate.test.sh`'s **production call-site pin** greps the *workflow YAML* for
`adjudicate_infra_config /tmp/` and `infra_config_count_invariant /tmp/` and asserts a loop-closing
`done` strictly between them. Extracting the verify body to a new script moves both calls out of
the YAML and reds that pin; keeping them in the YAML inside a `verify_once` function preserves it
byte-for-byte while still letting the *decision* logic live in a tested script.

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --limit 200` (64 open) and searched each
body for every planned path. One match, and it is not a real overlap:

- **#2197** — *refactor(billing): SubscriptionStatus type + hoist single-instance throttle doc +
  Sentry breadcrumb UUID policy*. Matched only because its body contains the string
  `apps/web-platform/infra/server.tf` in an unrelated context; this plan does not edit `server.tf`.
  **Disposition: acknowledge.** Different concern, different files, no shared surface. It remains open.

No open code-review issue mentions `.github/workflows/apply-deploy-pipeline-fix.yml`,
`infra-config-gate.sh`, `infra-config-gate.test.sh`, `push-infra-config.sh`,
`infra-config-red-alert.sh`, or `run-registered-suites.sh`.

## User-Brand Impact

> **The bullets below describe PR-B (the bounded re-push) and were NOT rewritten for what PR-A
> actually shipped.** Review caught this: the named fail-open is "a verdict that returns 0 when
> neither pass verified", and PR-A has no passes. The PR-A version is immediately below; the
> original is kept because PR-B still needs it.

### PR-A as shipped

- **The change adds a new PASSING path.** Before it, every green run had asserted
  `FRAME_START_TS >= APPLY_START_EPOCH`. The degraded arm passes on weaker evidence. It is
  bounded by a runner-side `APPLY_START_EPOCH` assert the host cannot influence, and by the
  future-frame check, but it is genuinely a new way to be green.
- **Making a red run green ARMS six previously-unreachable `if: success()` steps.** Two of them
  close the operator's GitHub issues asserting server state was re-aligned with HEAD. On a
  zero-change apply that assertion is false, so both are now gated on `PLAN_HAS_CHANGES`. This
  was the review's top finding and it is the concrete user-facing artifact: the founder's drift
  issues silently closing with a comment about a remediation that did not occur.
- **A new exposure surface exists, contrary to the original bullet's "no new exposure vector".**
  The `pre_frame` step reads `WEBHOOK_DEPLOY_SECRET` and both CF Access credentials from Doppler
  and makes an authenticated HTTPS call to the prod credential-delivery endpoint before the
  apply. It is a fourth Doppler-reading step. All three values are now `::add-mask::`ed.
- **The production apply invocation is rewritten** (saved plan rather than re-plan). That is the
  reason the threshold stays `single-user incident` even though PR-A adds no production write.
- **Brand-survival threshold:** `single-user incident` — unchanged by PR-A.

### Original (PR-B) text follows


- **If this lands broken, the user experiences:** a deploy that reports success while the
  production host is still running the previous config. The concrete artifact is a green
  `apply-deploy-pipeline-fix` run in the Actions tab with no `ci/infra-config-red` issue filed —
  the exact shape of #6594's latched false-green, which took a nonce bump and a hand-driven
  recovery to unwind. The specific fail-open this change could introduce is a verdict that
  returns 0 when neither pass verified, which would additionally re-arm five downstream
  `success()`-gated steps: the container redeploy would swap onto an unverified profile, and two
  steps would auto-**close** GitHub issues asserting a self-heal that never happened.
- **If this leaks, the user's workflow and credentials are exposed via:** the delivery channel
  this gate protects carries `/etc/default/soleur-doppler-token` (a live prd Doppler token) and
  `/etc/webhook/hooks.json` (the webhook HMAC secret). A gate that passes an unverified delivery
  is the control that would otherwise catch a mis-rendered or stale credential landing on the
  host. #7095 records the concrete consequence: a malformed token value bricks the deploy
  channel on a host that cannot be re-provisioned (cx33, 0/6 datacenter stock), and that channel
  is documented as the **only** no-SSH remediation path. There is no new exposure vector in this
  change — the risk is the loss of an existing detection.
- **Brand-survival threshold:** `single-user incident`

Because the threshold is `single-user incident`, `user-impact-reviewer` is invoked at review time
and `plan-review` runs the escalated panel (+`architecture-strategist`, +`spec-flow-analyzer`).

## Infrastructure (IaC)

No new infrastructure is introduced — no resource, no secret, no vendor, no persistent process.
The section is included because the change alters the **apply path** of an auto-applied Terraform
root, which is what the subsections below exist to pin.

### Terraform changes

None. No `.tf` file is edited. `terraform_data.deploy_pipeline_fix` and
`terraform_data.infra_config_handler_bootstrap` are used exactly as they exist today; no
`triggers_replace` list changes, so the three-way sync between `server.tf`'s `TRIGGER_FILES`,
`ship`'s `DEPLOY_PIPELINE_FIX_TRIGGERS` array/`DPF_REGEX`, and
`plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts` is untouched. No new
`TF_VAR_*` and therefore no Doppler provisioning precondition.

### Apply path

**(c) `-replace` — deliberately, and scoped.** The recovery runs a second
`terraform plan -replace=terraform_data.deploy_pipeline_fix` with the **same `-target=` set**
(the resource must appear in both, or per
`knowledge-base/project/learnings/2026-07-17-target-scoped-terraform-apply-makes-resource-deletion-a-silent-noop.md`
the replace is silently a no-op), followed by `terraform apply` **of that saved plan file** —
never a bare `-auto-approve` re-apply.

Blast radius: one `terraform_data` destroyed and recreated, whose only provisioner is a
`local-exec` HTTPS push (#3756). The push re-delivers bytes this same run already computed. It is
idempotent — the handler writes files and reports per-file `changed: false` when content matches.
Expected downtime: none. The push does not restart the listener; that is the handler-bootstrap
bridge's job, and the bridge is **not** replaced.

### Distinctness / drift safeguards

- **The destroy-guard is re-run, not bypassed.** The existing `host_creates` check
  (`tests/scripts/lib/destroy-guard-filter-web-platform.jq`, consumed by the `Terraform plan`
  step) runs again against the second plan's JSON before that plan is applied. A recovery that
  skipped it would be a new unguarded path to a host birth on a workflow that passes no
  `-var image_name`.
- **A narrowness assertion the first apply does not have.** The second plan must show exactly one
  resource with a `replace` action, and it must be `terraform_data.deploy_pipeline_fix`. Anything
  else — a second resource, an unexpected create, a `hcloud_server` in the change set — aborts
  the recovery and falls through to terminal red. This is what bounds `-target` transitivity,
  and it is also what makes the SSH question moot (see `## Risks`).
- **No state-storage change.** The R2 backend, the `terraform-apply-web-platform-host` workflow
  concurrency group, and the job-level `web-1-swap` group are all unchanged, so the second apply
  cannot interleave with a sibling apply any more than the first can.
- **`dev != prd` is not applicable** — this root has no dev counterpart; it manages the single
  prd host.

### Vendor-tier reality check

Not applicable. No provider resource is created, so no free-tier creation limit is reachable.
The only consumption change is GitHub Actions minutes (see `## Risks`).

## Observability

> **The `failure_modes:` block below enumerates PR-B's re-push failures** (`infra_config_bounded_verify`,
> `repush_once`, `op=infra-config-repush-attempted`) — none of which are in PR-A. Review found
> zero entries for the eight modes PR-A actually ships. They are enumerated here.

### PR-A failure modes as shipped

| Mode | Detection | Route |
|---|---|---|
| `pre_frame` → `unreachable` / `http404` / `malformed` / `secret_unavailable` | `::warning::` in the step | layer 6 only; carried out of band by the degraded event below |
| verify → `future_frame` | `::error::` + step exit 1 | layer 6 + the #7220 red-gate issue/Sentry step, which now has its own branch for these verdicts |
| verify → `unexpected_push` | `::error::` + exit 1 | same |
| verify → `frame_regressed` | `::error::` + exit 1 | same |
| `DPF_REPLACED` unreadable | plan step exits 1 | the apply never runs; red-gate alert's "ungraded" branch |
| green-but-degraded | `freshness_evidence=degraded` output | Sentry event `feature=infra-config`, `op=infra-config-preframe-degraded`. **No `sentry_issue_alert` rule matches it yet**, so today this is a queryable counter and NOT an alert route — the rule is tracked in #7527. Saying otherwise would be the AP-021 failure this plan exists to avoid. |

### Original (PR-B) text follows


```yaml
liveness_signal:
  what: "The apply-deploy-pipeline-fix job's own terminal exit, plus the ci/infra-config-red GitHub issue and Sentry event emitted by scripts/infra-config-red-alert.sh"
  cadence: "per-run (the workflow fires on push to main against the paths filter, and on workflow_dispatch)"
  alert_target: "operator — a plain-language GitHub issue labelled ci/infra-config-red, plus a Sentry event tagged op=infra-config-gate-red | infra-config-listener-down | infra-config-gate-ungraded"
  configured_in: ".github/workflows/apply-deploy-pipeline-fix.yml, step 'Alert on a red infra-config gate (#7220)'; helper at scripts/infra-config-red-alert.sh"

error_reporting:
  destination: "Sentry, via the store API POST in scripts/infra-config-red-alert.sh (SENTRY_INGEST_DOMAIN / SENTRY_PROJECT_ID / SENTRY_PUBLIC_KEY)"
  fail_loud: "the step exits non-zero and the job goes red; the ::error:: annotation names which of the two passes failed and why, and the GitHub issue restates it in operator language"

failure_modes:
  - mode: "Both passes fail — the re-push did not produce a verifiable delivery"
    detection: "infra_config_bounded_verify returns 1; the step exits 1; the job reds"
    alert_route: "ci/infra-config-red GitHub issue + Sentry op=infra-config-gate-red (reachable class), via the existing #7220 alert step"
  - mode: "The failure is not the no_new_frame shape, so no re-push is attempted"
    detection: "infra_config_no_new_frame returns non-zero; the step exits 1 immediately, and the ::error:: names the shape that was observed instead"
    alert_route: "same alert step; the 000/502/503 and 404 branches keep their existing distinct recovery text"
  - mode: "The re-push itself fails — the second plan is not narrow, the destroy-guard trips, or terraform apply exits non-zero"
    detection: "repush_once returns non-zero; the orchestrator does not run pass 2 and returns 1. The apply's exit status is never masked by `|| true`."
    alert_route: "same alert step; the ::error:: distinguishes 'the re-push could not run' from 'the re-push ran and pass 2 still failed'"
  - mode: "The recovery starts firing routinely — the race becomes common rather than rare"
    detection: "a dedicated Sentry event emitted on every re-push attempt, tagged op=infra-config-repush-attempted, carrying the run URL and which pass finally succeeded. Without this the recovery is invisible whenever it works, and a worsening race reads as a permanently healthy pipeline."
    alert_route: "no page — this is a counting signal, queryable in Sentry alongside the existing op= tags from this same workflow"
  - mode: "Clock skew on the host makes fresh frames read as stale, causing a spurious re-push every run"
    detection: "the op=infra-config-repush-attempted count above goes to ~100% of runs while pass 2 also fails; the terminal ::error:: names clock skew as a candidate alongside the race"
    alert_route: "ci/infra-config-red issue on the terminal failure, as above"

logs:
  where: "GitHub Actions run logs for apply-deploy-pipeline-fix (both passes are in one step's log, in order); host-side handler logs via `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep SOLEUR_INFRA_CONFIG_FATAL`"
  retention: "GitHub Actions logs 90 days; Better Stack per the account's retention; Sentry events per project retention"

discoverability_test:
  command: "bash apps/web-platform/infra/infra-config-gate.test.sh"
  expected_output: "a run ending in `infra-config-gate.test.sh: <N> passed, 0 failed` followed by `OK`, where N is at or above the GATE_MIN_ASSERTIONS floor — this executes the classifier predicate and the full mutation matrix, including the both-passes-fail row and the escape-hatch row, entirely hermetically (no network, no prod, no secrets)"
```

The `discoverability_test` is deliberately the suite rather than a live probe: the property that
matters here is *"the gate still fails closed"*, and that is a property of the adjudication logic,
which the hermetic harness executes directly. A live probe against prod would verify the host's
current state, which is a different question. The first token is `bash`, which is on preflight
Check 10's `PROBE_VERB_ALLOWLIST`, and no `credentials_required` declaration is needed because the
suite is fully offline.

### Affected-surface observability (Phase 2.9.2)

The host-side handler is a blind surface — the runner cannot inspect it, only read the frame it
publishes. This change adds no code to that surface, so the §2.9.2 in-surface-probe requirement is
satisfied by what already exists: the frame carries `fatal_line`, `fatal_rc` and `fatal_cmd`
(added by #7220) plus per-file `reason` values, and those fields are exactly the discriminators
that separate the four competing L7 hypotheses in `## Hypotheses` **in one event**. The one new
discriminator this change needs — *did this apply produce a frame at all?* — is answered by
`start_ts` against `APPLY_START_EPOCH`, both of which already exist.

## Guard Contract

The deliverable **is** a guard, so Phase 2.12 applies. Two guards ship, and the second one is the
one most likely to be got wrong, because it is a pre-existing guard whose assembly this change
moves.

### Guard 1 — `infra_config_bounded_verify` (the terminal verdict)

**Property.** The `Verify infra-config apply succeeded` step exits zero if and only if at least
one of its two verification passes verified this apply's delivery.

**Assembly.** Every path by which this step can reach exit 0. Structurally that is the set of
`return 0` statements in `infra_config_bounded_verify` plus the step's trailing statement that
propagates its status. The chokepoint is the function: the step must have exactly one exit-status-
determining statement, and it must be the call to this function. The function's only success arms
are the two `"$verify_fn"` invocations; the classifier arm, the re-push arm, and the fall-through
all `return 1`. Naming the chokepoint rather than the current arm list is deliberate — an arm list
is a snapshot, and the next edit that adds an arm would invalidate it silently. The test asserts
over the function's *behaviour under injected stubs*, so a new arm that returns 0 without a passing
verify is caught by the matrix rather than by an enumeration that has to be maintained.

**Mutation matrix.** Each row is an edit derivable from the design, and each must drive
`infra-config-gate.test.sh` RED.

| # | Mutation | Must go RED because |
|---|---|---|
| 1 | Make both injected verify stubs fail, with the classifier stub reporting the `no_new_frame` shape and the re-push stub succeeding | **The primary acceptance criterion.** Both passes failed; the verdict must be 1 |
| 2 | Make the first verify stub fail and the classifier stub report "not the race" | Pass 2 must not run, and the verdict must be 1 — not 0 by fall-through |
| 3 | Make the first verify stub fail, the classifier report the race, and the **re-push stub fail** | The verdict must be 1, and pass 2 must never have been invoked (assert the stub's call counter, not just the return code) |
| 4 | Delete or rename `infra_config_bounded_verify` so the workflow's `declare -F` anti-vacuity check is the only thing standing | The workflow must fail loudly with a named `::error::`, mirroring the existing `declare -F infra_config_red_alert` pattern — **this is the guard's own dispatch row**; a verdict function that is silently absent must not read as success |
| 5 | Add a **second** member to the success set: make the classifier return 0 and the re-push return 0 while both verifies fail, and have the orchestrator `return 0` on "the re-push succeeded" | A successful *push* is not a verified *delivery*. This is the compliant-first-member-then-a-second-member row: the HTTP 202 that started this whole incident class is exactly "the push succeeded" |
| 6 | Make the first verify stub **succeed** | Positive control: the verdict must be 0 and neither the classifier nor the re-push may be invoked (assert both call counters are zero) |
| 7 | Make the first verify fail, the classifier report the race, the re-push succeed, and the second verify succeed | Positive control for the recovery path: the verdict must be 0 and the re-push counter must be exactly 1 — never 2 |

Row 7 is what pins **boundedness**: an implementation that loops would pass a naive "it recovered"
assertion and fail this one.

### Guard 2 — the production call-site pin (pre-existing, re-pointed)

**Property.** Production invokes the *terminal* content assert — not an any-of-N variant polled
inside a retry loop — and, after this change, invokes the *tested* orchestrator rather than an
inline reimplementation of it.

**Assembly.** The pin currently quantifies over one artifact: `apply-deploy-pipeline-fix.yml`,
which it greps for `adjudicate_infra_config /tmp/` and `infra_config_count_invariant /tmp/` and
then requires a loop-closing `done` strictly between them. This change keeps both calls in that
file (inside the new `verify_once` function), so the existing three clauses survive **unmodified**
— that is the whole reason the extraction into a separate script was cut. The assembly gains one
member: the workflow must also call `infra_config_bounded_verify`, or the tested decision tree is
not the one production runs.

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|---|---|
| 1 | Move the `adjudicate_infra_config` call inside the poll loop (delete the intervening `done`) | The pre-existing #6594 any-of-3 coin flip — the pin's original property must still hold after the refactor |
| 2 | Delete the `infra_config_bounded_verify` call from the workflow and inline an equivalent `if/else` in YAML | The mutation matrix in Guard 1 would then certify a function production does not run — the "assertion adjacent to the property" class |
| 3 | Call `verify_once` a third time in the workflow | Boundedness is a property of production, not only of the orchestrator; a caller that adds its own retry defeats it |
| 4 | Delete the pin block itself | The suite's `GATE_MIN_ASSERTIONS` floor must red on the lost assertions — the anti-vacuity backstop the #7220 review added for exactly this |

## Architecture Decision (ADR/C4)

### ADR

**Create a new ADR** — provisional ordinal **186**, derived from an enumeration across all 64
`origin/*` refs (highest observed: ADR-185). The ordinal is a **claim, not a reservation**:
`/ship`'s ADR-Ordinal Collision Gate must re-derive it against freshly-fetched `origin/main`
immediately before merge, and any renumber must sweep this plan, `tasks.md`, and every AC that
names the ordinal in the same edit.

Decision to record: *the infra-config apply gate performs at most one bounded, shape-gated re-push
before adjudicating; the verification step's own exit code remains the single terminal verdict.*
The ADR must state the invariant every future editor has to honour — **adding a recovery must
never move the terminal verdict out of the step that fails closed** — and record why
`continue-on-error` was rejected, with the seven-step downstream assembly as the evidence. It
should also record the `no_new_frame` predicate and why the excluded shapes are excluded, since
that is the part most likely to be "helpfully" widened later.

This is a genuine architectural decision and not a bug fix: it changes the contract of a
fail-closed gate that six other steps depend on, and it converts a documented manual remedy into
an automatic one on a host the repo treats as unreplaceable.

### C4 views

**No C4 edit required**, and here is the enumeration that supports it — all three model files
(`model.c4` 688 lines, `views.c4` 74, `spec.c4` 54) were read in full, not keyword-grepped, and
all 133 relationships in `model.c4` were enumerated.

| Checked | Modeled? | Renders? |
|---|---|---|
| **External human actor** — the founder/operator who reads the red-gate issue | Yes, `founder` (kind `actor`, not `#external`) | Yes, `context` + `containers` |
| **External system** — GitHub (CI + Issues, one collapsed node) | Yes, `github` (`#external`) | Yes, both views |
| **External system** — Cloudflare (tunnel + Access) | Yes, `cloudflare` (`#external`) and `platform.infra.tunnel` | `cloudflare` both views; `tunnel` in `containers` |
| **External system** — Doppler | Yes, `doppler` (`#external`) | Yes, both views |
| **External system** — Sentry | Yes, `sentry` (`#external`) | Yes, both views |
| **Container / data store** — the Hetzner prod host | Yes, `platform.infra.hetzner` | `containers` |
| **Access relationship** — CI reaches the host's shell and the deploy webhook | Yes: `github -> tunnel` and `tunnel -> hetzner` (the latter carries the whole infra-config delivery-vs-activation contract) | Both endpoints co-included in `containers`, so the edges draw |
| **Access relationship** — a failed gate pages the operator | Partially: `github -> sentry` and `sentry -> founder` exist | Yes |

No element or relationship becomes false. The three files contain **no** assertion that the apply
path is single-shot, manual-recovery-only, or retry-free — every `single`/`once`/`manual`/`retry`
hit was read in context and belongs to a different subsystem (the ACME cert path, the AP-001 DNS
proxied-flag exception, and `apply-web-platform-infra.yml`'s ruleset pre-apply gate). Bounded
retry is already modeled vocabulary elsewhere in the same file (`webapp -> sentry` cites
`"bounded retry #5728"`). `spec.c4` declares only element kinds and two tags and cannot go stale;
`views.c4` contains only `include` lists and asserts nothing behavioural. The two new bash
functions need no element: no infra/CI shell script is an element anywhere in this model — a dozen
of them appear only inside descriptions — and the only `component`-kind elements are Soleur Plugin
skills/agents at a different C4 level. `apply-deploy-pipeline-fix.yml` is not named in any of the
three files.

**Two things the enumeration did surface, both in scope for this PR:**

1. **Stale recovery prose inside the workflow itself.** The 000/502/503 branch asserts
   *"a plain `workflow_dispatch` re-run does NOT fix this … `-target` SELECTS resources, it does
   not force replacement"*, and the operator guidance in the alert step is written on the same
   manual-only premise. Both remain **true for that branch** (the listener is down; a
   `deploy_pipeline_fix` re-push cannot help) but they now sit beside an automatic `-replace`
   path, and a reader who meets the automatic recovery first will read them as contradictory.
   They must be edited to say *which* failure shape each remedy belongs to.
2. **An optional precision edit to `model.c4`'s `github -> tunnel` label**, which says the
   bridge's Access-admission assertion fires *"BEFORE any caller's terraform runs"*. With a
   second apply later in the same job, that phrasing gains a reading it does not currently
   disambiguate. Not falsified — this plan's second apply is asserted to replace only a
   `local-exec` resource — so the edit is **optional**. If taken, `model.likec4.json` must be
   regenerated in the same commit (`scripts/regenerate-c4-model.sh`), because
   `plugins/soleur/test/c4-model-freshness.test.sh` gates it.

**One constraint to respect:** `plugins/soleur/test/c4-count-parity.test.sh` derives seven counts
from `.github/workflows/**` — `actions/sentry-heartbeat` callers, `monitor-slug:` values, and
Resend emitters matched by `api.resend.com|notify-ops-email`. `apply-deploy-pipeline-fix.yml`
currently matches none of them, so the counts stay parity-clean **provided** the new observability
signal is emitted through the existing `scripts/infra-config-red-alert.sh` style of direct Sentry
store-API POST, and this workflow gains no heartbeat composite, no `monitor-slug:`, and no Resend
call.

### Sequencing

The ADR is authored in this PR at `status: accepted` — the decision is true the moment the
workflow merges, and there is no soak or later slice that makes it true.

## Implementation Phases

> **SUPERSEDED — do not implement from this section, and it was NOT regenerated in place.**
> What was actually built is recorded once, in `## Implementation Findings (PR-A)` at the end
> of this document; `tasks.md` carries the reconciled task machine. Regenerating this section
> would produce a third copy of the same decisions, and copies drift — two copies of one probe
> table contradicting each other is a documented failure mode in this repo. Read the findings
> section instead. Original banner follows.
>
> It was written before the R13–R17 review
> revisions and describes the pre-revision machine: it still prescribes the teardown relocation
> that R3 reversed, it has no step for the `DPF_REPLACED` extraction or the saved-plan rework, and
> it assumes the higher-order orchestrator that R16.2 replaced with a pure predicate.
> **The operative artifact is
> [`../specs/feat-one-shot-7104-apply-verify-repost-recovery/tasks.md`](../specs/feat-one-shot-7104-apply-verify-repost-recovery/tasks.md)**,
> which encodes the reconciled machine. Regenerating this section from R13–R17 is task 1.1 there.
> Retained below only as the provenance of what changed and why.

Phase order is load-bearing: the two new functions are a **contract**, and the workflow is their
**consumer**. Writing the consumer first produces YAML that calls a function that does not exist,
and the tests for it cannot be RED for the right reason.

### Phase 0 — Preconditions (verify, do not assume)

Each of these is a one-command probe whose output is pasted into the PR body. None is optional;
each guards a claim this plan makes.

1. **`-replace` + `-target` compose, and the second plan is narrow.** From `apps/web-platform/infra`,
   confirm the plan invocation the recovery will use is syntactically accepted and shows exactly
   one replaced resource. This is a `terraform plan` only — read-only, no apply.
2. **The call-site pin survives the refactor.** Before touching anything else, confirm the pin's
   three greps (`adjudicate_infra_config /tmp/`, `infra_config_count_invariant /tmp/`, an
   intervening `done`) all still resolve after the `verify_once` wrapping. If wrapping perturbs
   any of them, that is discovered here rather than at the suite's exit gate.
3. **Record the current assertion count.** Run `bash apps/web-platform/infra/infra-config-gate.test.sh`
   and note the `<N> passed` figure. The new `GATE_MIN_ASSERTIONS` is derived from the post-change
   count, never from the remembered `64`.
4. **Re-derive the ADR ordinal** across all `origin/*` refs, not just `origin/main`.
5. **Confirm the stale-frame reading of a no-op dispatch.** Read the #7220 freshness-pin block and
   confirm the inference in `## Risks` — that a no-op apply publishes no new frame and therefore
   already reds the gate today. If that inference is wrong, the post-merge verification path in
   `## Acceptance Criteria` must change, because it depends on it.

### Phase 1 — RED: the contract's tests, written before the contract

Extend `apps/web-platform/infra/infra-config-gate.test.sh`, reusing its existing harness
(`build_status_json`, the `pass`/`fail` counters, the synthesised infra dir):

1. **Classifier cases for `infra_config_no_new_frame <response-file> <apply-start-epoch>`** — one
   per row of the discriminator table in `## Research Insights`: a stale frame (returns 0); a
   fresh frame (non-zero); a frame with no `start_ts` (non-zero); a frame with a non-numeric
   `start_ts` (non-zero); an unparseable body (non-zero); an absent file (non-zero); a fresh frame
   carrying `files_failed > 0` (non-zero); a fresh frame carrying `fatal_line > 0` (non-zero);
   and the boundary case `start_ts == APPLY_START_EPOCH` (non-zero — equality is *not* stale,
   matching the existing pin's `-lt`).
2. **The Guard 1 mutation matrix**, all seven rows, driving `infra_config_bounded_verify` with
   injected stub function names and per-stub call counters. Every row asserts **both** the return
   code and the call counters — a row that asserts only the return code cannot catch an
   implementation that recovered by looping.
3. **Independent per-pass assertions.** Per
   `knowledge-base/project/learnings/test-failures/2026-04-19-retry-once-early-return-masks-first-attempt-failures.md`,
   each pass's verdict is recorded and asserted separately. No case may collapse to "the last
   attempt passed".

All new cases must FAIL at this point, and each must fail for the stated reason (a missing
function is an acceptable RED here only for the rows whose property is "the function exists" —
every other row is re-run after Phase 2 to confirm it turned GREEN for the right reason).

### Phase 2 — GREEN: the contract

Add to `apps/web-platform/infra/infra-config-gate.sh`, alongside the existing sourceable functions
and following their conventions (quiet boolean return, `::error::` on the terminal arms):

1. `infra_config_no_new_frame <response-file> <apply-start-epoch>` — returns 0 **only** for the
   allow-listed shape. Every unclassifiable input returns non-zero. Its own guards mirror the
   existing freshness pin's: a non-numeric epoch is a hard non-zero, not a skip.
2. `infra_config_bounded_verify <verify_fn> <classify_fn> <repush_fn>` — the orchestrator. Its
   only `return 0` statements are the two verify successes. Each `return 1` arm emits a distinct
   `::error::` naming which arm fired, and the both-passes-failed arm additionally names clock
   skew as a candidate cause alongside the race.

No existing function's behaviour changes. Re-run the suite: every Phase 1 case turns GREEN.

### Phase 3 — The consumer: workflow wiring

In `.github/workflows/apply-deploy-pipeline-fix.yml`, step `Verify infra-config apply succeeded`
(`id: infra_config_gate`):

1. Wrap the existing poll loop + terminal `adjudicate_infra_config` + freshness pin into a shell
   function `verify_once` **without editing their bodies** — an indentation-only move, so the
   diff is reviewable as such and the call-site pin's greps are provably unperturbed.
2. Add `repush_once`: re-record `APPLY_START_EPOCH`, run the scoped
   `terraform plan -replace=… -target=… -out=…`, re-run the `host_creates` destroy-guard on that
   plan, assert the plan replaces **only** `terraform_data.deploy_pipeline_fix`, then
   `terraform apply` the saved plan file. No `|| true` anywhere; the apply's exit status is the
   function's return value.
3. Add the anti-vacuity dispatch check —
   `declare -F infra_config_bounded_verify >/dev/null || { echo "::error::…"; exit 1; }` — mirroring
   the pattern already used for `infra_config_red_alert`.
4. Make the step's final statement the orchestrator call. The step keeps `set -euo pipefail` and
   gains **no** `continue-on-error`.
5. Emit the `op=infra-config-repush-attempted` Sentry event from `repush_once`, through the same
   direct store-API POST style the existing alert helper uses (never a heartbeat composite, never
   Resend — see the `c4-count-parity` constraint).
6. Relocate the `Tear down cloudflared SSH bridge` step to immediately after this step, keeping
   `if: always()`.

### Phase 4 — Re-point Guard 2 and raise the floor

1. Extend the production call-site pin with the fourth clause (the workflow calls
   `infra_config_bounded_verify`) and the boundedness clause (`verify_once` is invoked at most
   twice), keeping the three existing clauses byte-identical.
2. Add the Guard 2 mutation rows.
3. Raise `GATE_MIN_ASSERTIONS` to the measured post-change count from Phase 0 step 3.

### Phase 5 — Documentation the change makes stale

1. Edit the 000/502/503 branch's recovery prose and the alert step's operator guidance so each
   remedy is attached to the failure shape it belongs to. Both remain correct for their own
   branch; what changes is that an automatic `-replace` recovery now exists on a *different*
   branch, and the prose must not read as denying it.
2. Write the ADR (provisional 186).
3. Write `decision-challenges.md` recording the `continue-on-error` deviation.

### Phase 6 — Exit gate

Run the full registered suite, not just the touched file — `bash scripts/test-all.sh` — because
`run-registered-suites.sh` derives its list from `infra-validation.yml` and an orphaned or
mis-registered suite is invisible to a single-file run.

## Acceptance Criteria

### Pre-merge (PR)

1. `bash apps/web-platform/infra/infra-config-gate.test.sh` exits 0 and reports
   `<N> passed, 0 failed` with `N` at or above the raised `GATE_MIN_ASSERTIONS`.
2. **The primary criterion.** With both verify stubs failing, the classifier reporting the
   `no_new_frame` shape and the re-push stub succeeding, `infra_config_bounded_verify` returns
   non-zero. Asserted as Guard 1 row 1, and independently re-asserted by temporarily inverting the
   orchestrator's final `return 1` to `return 0` and confirming the suite goes RED — the guard is
   demonstrated to be drivable, not merely present.
3. All seven Guard 1 mutation rows and all four Guard 2 mutation rows are present and each drives
   the suite RED when applied. Row 4 of Guard 1 (the missing-function row) is what proves the
   verdict cannot be vacuously absent.
4. `grep -c 'continue-on-error' .github/workflows/apply-deploy-pipeline-fix.yml` returns 0, and
   each of the seven downstream conditions is still present verbatim — asserted by grepping for
   the exact condition strings (`failure() && steps.infra_config_gate.outcome != 'success'` and
   the five `success()` forms), not by asserting on the shape of a diff. *(Revised at plan review:
   the earlier wording carved out "the relocation of the teardown step", which R3 reversed — the
   teardown does not move. A diff-shape assertion also guards against the author rather than
   against a defect, which is why this is now a content assertion.)*
5. The second-pass plan invocation names `terraform_data.deploy_pipeline_fix` in **both** its
   `-replace=` and its `-target=` arguments.
6. The `host_creates` destroy-guard runs against the second plan's JSON before that plan is
   applied, using the same `tests/scripts/lib/destroy-guard-filter-web-platform.jq` filter as the
   first pass.
7. `repush_once` contains no `|| true` and no `2>/dev/null` on the `terraform apply` invocation.
8. The production call-site pin's three original clauses are unchanged, and the suite still passes
   them — proving the refactor did not move `adjudicate_infra_config` into the poll loop.
9. `bash scripts/test-all.sh` is green, and `run-registered-suites.sh` reports no new orphan suite.
10. The ADR exists at the ordinal re-derived immediately before merge, and
    `grep -rn 'ADR-<ordinal>' knowledge-base/project/{plans,specs}/` shows every citation of it
    consistent with the file that exists.
11. `actionlint` is clean on `.github/workflows/apply-deploy-pipeline-fix.yml`, and the two new
    `run:` snippets are syntax-checked with `bash -c` against the extracted text — never
    `bash -n` on the YAML file itself.
12. `decision-challenges.md` exists and records the `continue-on-error` deviation with the
    seven-step assembly as its evidence.

### Post-merge (automated, no operator step)

13. The workflow does **not** fire on this PR's merge — none of the edited paths
    (`.github/workflows/apply-deploy-pipeline-fix.yml`, `apps/web-platform/infra/infra-config-gate*.sh`)
    is in its own `on: push: paths:` filter, and adding them is out of scope (`server.tf` is
    deliberately absent from that filter for the same blast-radius reason). So the change ships
    dark and must be exercised deliberately.
14. `ship` dispatches the workflow (`gh workflow run apply-deploy-pipeline-fix.yml`) and reads the
    result with `gh run view`. On an unchanged tree this is a no-op apply, which — per the Phase 0
    step 5 precondition — publishes no new frame and therefore exercises the *entire* new path:
    pass 1 fails on the stale frame, the classifier fires, the bounded re-push runs, and pass 2
    goes green. The run's log must show exactly one `op=infra-config-repush-attempted` emission
    and a green job.
15. If step 14's run is instead **red**, no `ci/infra-config-red` issue is suppressed — the #7220
    alert step must have fired with the `reachable` class, proving the alerting path survived the
    change.

## Alternatives Considered

| Approach | Why not |
|---|---|
| **`continue-on-error: true` on the verify step + a separate final adjudication step** (the issue's suggested shape) | This is the operator's stated direction and is recorded as a User-Challenge, not silently discarded. The reason for deviating is mechanical: seven steps downstream key off job status. `Alert on a red infra-config gate (#7220)` is conditioned on `failure() && steps.infra_config_gate.outcome != 'success'`, and `continue-on-error` keeps the job nominally green at that point, so the P0 alert goes dark on a first-pass failure — the documented trap in `2026-05-05-workflow-jwt-mint-silent-failure-traps.md`. Five further steps use bare `success()`; two of them **close GitHub issues** and one swaps the running container. Adopting `continue-on-error` therefore means re-wiring all seven conditions, and each rewiring is a fresh opportunity for exactly the fail-open this issue exists to prevent. A second, subtler defect: on a *recovered* run `steps.infra_config_gate.outcome` stays `failure` forever, so any later unrelated step failure would fire the alert with a message blaming the infra-config gate. The in-step shape needs none of this — the step's exit code remains the single verdict and no downstream condition changes. |
| **Extracting the verify body into a new `apps/web-platform/infra/infra-config-verify.sh`** | Superficially the cleanest "one chokepoint" answer, and it was the working design until the existing suite was read. `infra-config-gate.test.sh`'s production call-site pin greps the **workflow YAML** for `adjudicate_infra_config /tmp/` and `infra_config_count_invariant /tmp/` with a loop-closing `done` between them. Extraction moves both calls out of that file and reds the pin, and the natural "fix" — re-pointing the grep at the new script — silently drops the property that *production* calls it. Keeping the calls in the YAML inside a `verify_once` function preserves the pin byte-for-byte while still putting the decision logic in a tested script. It also avoids a new file, a new `infra-validation.yml` registration, and a new orphan-suite risk. |
| **Unbounded retry / exponential backoff** | Explicitly out of scope per the issue. Row 7 of the Guard 1 matrix pins boundedness so an implementation cannot drift into it. |
| **Bumping the `redeploy-nonce` in `push-infra-config.sh`** | This is the existing *manual* remedy and it works, but it requires a commit and a merge to fire, which is precisely the human intervention this issue is removing. It also re-delivers on the *next* merge rather than the failing run. |
| **`-replace=terraform_data.infra_config_handler_bootstrap`** (the remedy the 000/502/503 branch prescribes) | Correct for a **down listener**, wrong here. It re-runs the SSH bridge and restarts the listener — which is the very restart that causes the race this plan is fixing. Using it as the recovery for `no_new_frame` would risk re-creating the race on the recovery attempt. |
| **Widening the discriminator to any gate failure** | Fail-open in polarity, per `2026-07-03-enforcement-probe-must-discriminate-exit-codes-not-any-failure-as-safe.md`. A re-push on a `files_failed > 0` frame would mask a genuine delivery defect behind an idempotent retry. |
| **Adding this workflow's own path to its `on: push: paths:` filter** so the change self-tests on merge | Rejected for the same reason `server.tf` is deliberately excluded: it would make every edit to the workflow auto-write production. The post-merge `workflow_dispatch` in AC14 achieves the same verification with an explicit, bounded trigger. |

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **The verdict fails open** — the change's whole downside. | Guard 1's mutation matrix, with row 1 as the primary AC and row 4 covering the guard's own absence. The orchestrator's only `return 0`s are the two verify successes; every other path returns 1 by construction, including the unclassifiable one. |
| **The second apply needs the SSH bridge, which was already torn down.** `terraform_data.deploy_pipeline_fix` `depends_on` two resources whose provisioners are SSH `remote-exec` over the tunnel. | Two independent mitigations, because the underlying claim (Terraform opens no SSH connection for a resource with no planned action, and `-replace` on a resource does not replace its `depends_on` predecessors) is *believed* correct but is not worth betting a P1 path on. **(a)** The teardown step is relocated to after the recovery, so the bridge is alive if it is needed. **(b)** The narrowness assertion aborts the recovery if the second plan touches anything other than `deploy_pipeline_fix` — so if the belief is wrong, the failure mode is a clean terminal red, not a hung SSH dial. Phase 0 step 1 measures which it is. |
| **`-replace` is silently a no-op** because the resource is not in the `-target` set. | AC5 asserts the resource appears in both arguments. Documented class: `2026-07-17-target-scoped-terraform-apply-makes-resource-deletion-a-silent-noop.md`. |
| **The second apply births a host.** `-target` is transitive, and this workflow passes no `-var image_name`. | The `host_creates` destroy-guard is re-run against the second plan (AC6), plus the narrowness assertion. |
| **Clock skew makes every run re-push.** | Bounded to one extra idempotent push per run, then a terminal red. The terminal message names skew as a candidate. The `op=infra-config-repush-attempted` counter makes a systemic skew visible as a ~100% re-push rate rather than as folklore. |
| **The recovery masks a worsening race.** A run that recovers is green and silent, so a race going from rare to routine looks like a healthy pipeline. | The `op=infra-config-repush-attempted` Sentry event is emitted on **every** attempt, successful or not. This is the specific reason it is a plan deliverable and not a nice-to-have. |
| **The refactor perturbs the call-site pin** and someone "fixes" the pin by weakening it. | Guard 2's mutation matrix, and the explicit requirement that the three original clauses stay byte-identical (AC8). Phase 0 step 2 checks this before any other edit. |
| **Wall-clock.** The step now may contain a second plan + apply. | The job's ceiling is `timeout-minutes: 90` and the observed apply is a small `terraform_data` recreation; the added cost is a low single-digit number of minutes, and only on the failing path. The `terraform-apply-web-platform-host` and `web-1-swap` concurrency groups (`cancel-in-progress: false`) are unchanged, so a longer run cannot interleave with a sibling apply. |
| **The change ships dark** — the workflow does not fire on its own paths. | AC13/AC14 make this explicit and prescribe the automated `workflow_dispatch` verification rather than leaving it to the next unrelated trigger-file merge. |

## Test Scenarios

> **PARTIALLY SUPERSEDED.** T1 is now **wrong** — a stale frame with `DPF_REPLACED == false` is the
> expected healthy state and must classify non-zero (R15.2). T2's operand changed if R2 ships
> (R13.3). T11–T21 are re-derived against the pure predicate rather than stub-driven rows (R16.2),
> and rows are added for the escape hatch (R15.1), `ALLOW_MISSING_STATUS` fidelity (R4c), the
> `DPF_REPLACED` polarity guard (R17.1) and the integration-shaped two-pass test (R13.7). See
> `tasks.md` Phase 4. T3–T10 stand as written.

Every scenario below runs in `apps/web-platform/infra/infra-config-gate.test.sh` unless marked
otherwise. Scenarios are named by the property they pin, not by the code they touch.

| # | Scenario | Expected |
|---|---|---|
| T1 | Stale frame, listener answering 200 | classifier returns 0 |
| T2 | Fresh frame (`start_ts > APPLY_START_EPOCH`) | classifier non-zero |
| T3 | `start_ts == APPLY_START_EPOCH` | classifier non-zero (equality is fresh) |
| T4 | Frame with no `start_ts` key | classifier non-zero |
| T5 | Frame with non-numeric `start_ts` | classifier non-zero |
| T6 | Unparseable body (a Cloudflare error page fixture) | classifier non-zero |
| T7 | Response file absent | classifier non-zero |
| T8 | Non-numeric `APPLY_START_EPOCH` | classifier non-zero — the freshness input cannot be trusted |
| T9 | Fresh frame with `files_failed > 0` | classifier non-zero |
| T10 | Fresh frame with `fatal_line > 0` | classifier non-zero |
| T11–T17 | Guard 1 mutation rows 1–7 | as tabulated in `## Guard Contract` |
| T18–T21 | Guard 2 mutation rows 1–4 | as tabulated |
| T22 | Suite registration self-check | the suite is still an explicit step in `infra-validation.yml` |
| T23 | Assertion-count floor | `pass >= GATE_MIN_ASSERTIONS` at the raised value |
| T24 (workflow-level) | `actionlint` on the workflow | clean |
| T25 (workflow-level) | Extracted `run:` snippets syntax-checked with `bash -c` | clean; `bash -n` on the `.yml` is **not** used |

## Plan Revisions

The domain review (Phase 2.5) produced findings that change the design. Each revision below
supersedes the earlier text where they conflict. Every claim was re-verified against the tree
before adoption — two were **rejected on measurement**, and those rejections are recorded here
because inheriting them would have made the plan wrong.

### R1 — The discriminator gains a second, decisive clause: `DPF_REPLACED`

**Measured, not inferred.** `terraform_data.deploy_pipeline_fix`'s `triggers_replace` hashes 22
`file("${path.module}/…")` entries plus `local.hooks_json` and `local.webhook_doppler_token_env`.
It does **not** hash `seccomp-bwrap.json`, `apparmor-soleur-bwrap.profile`, or `server.tf` — I
enumerated the hash list and grepped it for those three: zero hits. All three **are** in the
workflow's `on: push: paths:` filter.

So three routine, *intended* merge classes fire this workflow while leaving `deploy_pipeline_fix`
unreplaced. No replacement means no `local-exec`, which means no push, which means the host
publishes no frame — and the #7220 freshness pin then reds the gate and files a plain-language
GitHub issue at a non-technical founder for a merge where **nothing was wrong**. The `#5875`
comment in the paths filter explicitly states an apparmor-only edit *must* auto-apply, so this is
a supported change class the pin breaks.

Had the plan shipped with staleness as the sole trigger, it would have converted each of those
false-reds into a **full production re-push** — a blast-radius expansion, on a recurring schedule,
that also destroys the evidence that the pin is over-broad. Papering a real defect with a prod write.

**Revision.** The apply produces a saved plan (`-out=`) and the workflow applies *that file*;
`DPF_REPLACED` is read from its `resource_changes[]`. Then:

- `DPF_REPLACED == false` → **no push was expected.** Skip the freshness pin with an explicit
  `::notice::`, adjudicate on count + content only, and **do not re-push.** Three false-red
  classes disappear and zero prod writes are added.
- `DPF_REPLACED == true` **and** `no_new_frame` → genuinely the race → one bounded re-push.

This makes the classifier strictly *narrower*. It also fixes a live defect on `main` as a
by-product, which is why it is in scope rather than deferred: without it, the recovery this issue
asks for would fire on the wrong runs.

**Bonus, and it is not incidental.** Switching the first apply to `-out=`/apply-saved-plan closes a
pre-existing TOCTOU: today the `Terraform plan` step runs the `host_creates` destroy-guard against
`tfplan`, and the `Terraform apply` step then **re-plans and discards it** (it runs
`terraform apply -target=… -auto-approve`, with no plan file). The guard has been adjudicating a
plan that is not the one applied.

### R2 — Freshness becomes host-vs-host, so clock skew cancels

The current pin compares a host-generated `start_ts` against a runner-generated
`APPLY_START_EPOCH`. Under persistent skew the recovery makes things **worse**, not merely
noisy: pass 2 re-records the epoch from the runner (later still) while the host publishes with its
own behind clock, so pass 2 reads stale too — every run red *and* one spurious production write
per run, permanently. The earlier plan's mitigation (name skew in the terminal message) is a
diagnosis, not a fix.

A tolerance `T` is the wrong tool twice: it re-opens a `T`-second stale-frame window — exactly the
blind spot #7220 closed — and does nothing for skew greater than `T`.

**Revision.** Poll `/hooks/infra-config-status` **once before the apply**, record
`PRE_APPLY_FRAME_START_TS`, and define freshness as `FRAME_START_TS > PRE_APPLY_FRAME_START_TS`.
Both operands come from the same host clock, so skew of any magnitude cancels, and the test is
*stricter* than today's — it demands a genuinely different frame, not merely a timestamp that
beats a runner clock. Fall back to the existing `APPLY_START_EPOCH` comparison when the pre-poll
yields no numeric `start_ts` (404, listener down, schema-v1 handler), so the escape path is never
worse than today. Orthogonal to R1: on a no-op, `PRE_APPLY_FRAME_START_TS == FRAME_START_TS`, so
`DPF_REPLACED` is still required. Both, not either.

### R3 — The bridge teardown is NOT relocated; the plan assert becomes exact-cardinality

The earlier text proposed moving `Tear down cloudflared SSH bridge` after the recovery as a hedge.
**Reversed.** The no-SSH claim is sound and was re-verified: `terraform_data.deploy_pipeline_fix`
has **no `connection` block at all** and a single create-time `local-exec`, with no
`when = destroy` provisioner — so the destroy half of `-replace` runs zero commands and the create
half is an HTTPS push. Its two `depends_on` predecessors have `triggers_replace` values that are
stable within a single run, so neither is replaced and neither's provisioners run.

Moving the teardown would hold an `iptables -t nat OUTPUT REDIRECT` rule and a live `cloudflared`
process open across the whole verify + recovery phase, trading a *proven-absent* risk for a real
exposure widening — against the teardown step's own stated rationale for its placement.

**Revision.** Keep the teardown where it is, and make the recovery's plan assert
**exact-cardinality** rather than membership: the set of `resource_changes[]` whose
`.change.actions != ["no-op"]` must have length **exactly 1**, that entry's `.address` must be
`terraform_data.deploy_pipeline_fix`, and its `.change.actions` must be `["delete","create"]`.
A membership-style check would pass a plan that *also* replaces `infra_config_handler_bootstrap`
— precisely the case that needs the bridge and would hang dialling a torn-down tunnel. Exact
cardinality makes the no-SSH reasoning **self-enforcing**: if the claim is ever wrong, the run
aborts fail-closed instead of discovering it at an SSH timeout.

### R4 — Two implementation traps that would ship this broken

**R4a — `$GITHUB_ENV` is inert inside the step that writes it.** The apply step records
`APPLY_START_EPOCH` via `>> "$GITHUB_ENV"`, which affects *subsequent* steps only. Copy-pasting
that line into `repush_once` would leave pass 2 comparing against **pass 1's** value — which is
*laxer*, and can pass a stale frame whose `start_ts` falls between the two. The re-record must be
a plain shell assignment, re-exported if the verify body runs as a subprocess. High severity,
high likelihood: it is the natural copy-paste.

**R4b — `exit` vs `return`, the single most likely way this ships broken.** Every terminal branch
in the current verify body is `exit 1`. The step runs under `set -euo pipefail`. If any `exit`
survives the wrap into `verify_once`, **pass 1 kills the step and pass 2 is unreachable** — while
every test that drives the orchestrator with stubs stays green, because a stub's `return` is not
the production body's `exit`. That is logic proven, placement broken. The wrapped body must
`return`; the caller decides. **This gets its own mutation row** (swap a `return 1` for `exit 1`,
prove the suite reds) — without it the matrix certifies a property adjacent to the one it names.

**R4c — `ALLOW_MISSING_STATUS` fidelity.** With the flag true, the 404 branch warns and falls
through *without* running the content assert or the freshness pin, so the step exits 0. That is a
documented first-bootstrap escape hatch. The wrap must preserve it byte-identically; pin it as its
own mutation row.

**R4d — saved-plan apply mechanics.** `terraform apply <planfile>` still needs the
`doppler run --name-transformer tf-var` wrapper (provider config is re-evaluated at apply time),
and the plan must be produced under the identical `-var="ssh_key_path=${CI_SSH_PUB}"`.
`/tmp/ci_ssh_key.pub` survives the teardown (which only drops the iptables rule and kills
`cloudflared`), but that is an undeclared dependency — add an explicit `[[ -s "$CI_SSH_PUB" ]]`
guard rather than relying on it.

### R5 — A recovered run must not be silent

A green run that performed a production re-push violates the operator's model of "green = nothing
happened", and it makes the race **uncountable** — which matters, because the race's frequency is
the datum that decides whether to fix the root cause (a readiness poll after the listener restart
in the bootstrap's `remote-exec`) instead of retrying it forever. A silent self-healing retry is
also the canonical shape `cq-silent-fallback-must-mirror-to-sentry` exists to reject.

**Revision, superseding property P6's "files nothing".** Three layers, all reusing wiring that
already exists:

- **Primary — one *rolling* GitHub issue** under a new label `ci/infra-config-recovered`
  (`priority/p3-low`, `domain/engineering`), plain-language title. An issue is heavy only when it
  is one-per-occurrence; `scripts/infra-config-red-alert.sh` already implements the dedupe
  (list open by label → comment if open, create if not). One notification ever, and the comment
  count *is* the counter.
- **Secondary — a Sentry event at `level: "warning"`**, `op=infra-config-push-recovered`. The
  three `SENTRY_*` env vars are already on the alert step and the helper already builds this
  envelope. Zero marginal cost.
- **Tertiary — one `$GITHUB_STEP_SUMMARY` line** naming both attempts, so the green run is
  self-describing.

Plus an **auto-escalation** so nobody has to watch it: read the rolling issue's comment count and,
at **≥3 recoveries in a rolling 30 days**, re-file through the existing P1 `ci/infra-config-red`
channel saying the race has stopped being rare. One extra `gh` call, no new infrastructure, and it
converts "the race became common" from an unobserved trend into an alert.

*Layer correction:* `scripts/betterstack-query.sh` reads **host** logs. The re-push decision is
made in the GitHub runner, which does not ship there, so a `SOLEUR_*` grep marker would be
uncountable. Sentry is the correct layer (`hr-observability-layer-citation`).

### R6 — The step is renamed, and gains a rehearsal input

The step now writes production; calling it `Verify infra-config apply succeeded` understates it.
Rename to name the actuator role. This is safe because every consumer references
`steps.infra_config_gate` by **`id`**, and the call-site pin anchors on function names and a `done`
line — but Phase 0 must confirm that before renaming.

Add a `workflow_dispatch` boolean input `force_repush_rehearsal` that permits the re-push on the
`DPF_REPLACED == false` shape. This preserves the post-merge rehearsal (AC14) *without* widening
the automatic path: the rehearsal becomes explicit in the run's inputs rather than a side effect
of a no-op apply. **AC14 is amended accordingly** — the dispatch must pass this input.

### R7 — Two agent claims REJECTED on measurement

Recorded because adopting either would have made the plan wrong, and because "an advisory asserted
a precedent" is not evidence.

- **REJECTED: "ADR-068 §Amendment already decides this exact shape — a bounded one-shot in-verify
  re-POST — cite it as precedent."** ADR-068 is
  `ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md`. It has **no `## Amendment`
  section**; its two addenda are both about the git-data host's instance type (`cax11` → `cpx22`,
  and the `cpx22` sizing claim). Nothing in it decides anything about the infra-config verify gate.
  A repo-wide grep of the ADR corpus for re-POST/re-push/bounded-one-shot vocabulary returns seven
  files, none of which decides this. **The ADR must therefore be written, not cited** — R8 below.
- **REJECTED: "a `server.tf` edit does not fire this workflow, because the paths filter says
  `server.tf` is deliberately absent."** The filter's own comment asserts *"server.tf is
  DELIBERATELY ABSENT from this list and must stay absent (R13)"* — and the entry
  `- "apps/web-platform/infra/server.tf"` sits three lines below it. The comment is false about
  the code beneath it. This does **not** change R1 (it strengthens it — the `server.tf` class is
  frequent), but it is a separate defect; see R9.

### R8 — The ADR is genuinely new, and its subject is a boundary change

Confirmed by R7: no existing ADR covers this. Provisional ordinal **186** (highest across all 64
`origin/*` refs is ADR-185); re-derive before merge.

The decision to record is sharper than "add a retry": **this change turns a CI verification gate
into an actuator on production.** The three load-bearing sub-decisions, each with a non-obvious
rejected alternative, are (a) the in-step shape — and it is *forced*, not merely preferred, because
GitHub steps default to `if: success()`, so a separate `Re-push` step after a failed verify would
simply be **skipped** unless pass 1 is made to exit 0, which is the same fail-open wearing a
different hat; (b) the exact-cardinality plan assert from R3; (c) the `DPF_REPLACED` discriminator
from R1.

The ADR must also address the **counter-precedent** a reviewer will raise: **ADR-072 Option 2
rejected auto-retry.** Verified verbatim — its reason is that `gh run rerun --failed` re-POSTs to
`/hooks/deploy` and collides with `ci-deploy.sh`'s `flock -n`. That is a *different hook* and a
*different lock*; this plan re-POSTs to `/hooks/infra-config`. The distinction must be stated in
the ADR and the PR body, or review will stall on it.

### R9 — Pre-existing defects found during this work

Per `wg-when-an-audit-identifies-pre-existing` and `wg-defer-only-after-inline-triage`, each is
triaged inline and dispositioned:

1. **`server.tf` is in the paths filter while the adjacent comment says it must never be.**
   Every `server.tf` edit therefore auto-writes production — the exact blast radius the comment
   says must not exist. **File an issue.** Not fixable inline: removing the entry changes this
   workflow's trigger semantics, which is its own decision with its own blast radius, and doing it
   inside a PR about retry semantics would bury it.
2. **The `host_creates` destroy-guard adjudicates a discarded plan** (the TOCTOU in R1).
   **Fixed inline** — it is a prerequisite for `DPF_REPLACED`, so it is not optional here.
3. **The #7220 freshness pin reds three supported merge classes.** **Fixed inline** by R1, for
   the same reason.
4. **No runbook covers this channel.** `knowledge-base/engineering/operations/runbooks/` has no
   file describing the infra-config gate, its `reachable` / `unreachable` / `ungraded` classes, or
   what the operator does when it reds — that prose lives only inline in the workflow and the
   alert helper. Given `hr-no-ssh-fallback-in-runbooks` and that this is the sole no-SSH channel on
   an unreplaceable host, **create `knowledge-base/engineering/operations/runbooks/infra-config-channel-red.md`
   in this PR**, covering the three classes, the **two** legitimate `-replace` targets, the one
   forbidden target, and the new automatic recovery.

### R10 — Concurrency: a slow handler, not just a dead one

`infra-config-apply.sh` has **no `flock` and no serialization** — verified by grep. So
`no_new_frame` cannot distinguish "the handler never started" from "the handler is still running
and has not reached its exit trap". A re-push in the latter case runs two handlers concurrently.

Two things bound it, one structural and one added:

- **Structural.** `infra-config-install.sh` installs atomically: it `mktemp`s *in the destination
  directory* and `mv -f`s into place. Two concurrent handlers from the *same run* deliver
  byte-identical content, so the per-file outcome is identical either way. The residual is
  double-fired unit restarts, which the activation contract grades on effect.
- **Added.** A bounded pre-classification settle: before concluding `no_new_frame`, poll across
  the handler's realistic completion window so a slow-but-alive handler publishes and falsifies
  the classifier. This targets the hazard directly and costs seconds only on the failing path.

### R10b — The exact-cardinality assert must follow the repo's jq convention

R3's assert was first phrased as `.change.actions != ["no-op"]`. The repo's own filter
(`tests/scripts/lib/destroy-guard-filter-web-platform.jq`) uses the `index()` form throughout —
`select(.change.actions? | index("delete"))` — and it carries a documented sharp edge about
Terraform 1.7+ `["forget"]` actions being mis-bucketed by naive comparisons. Express the assert in
that convention:

- the set of `.resource_changes[]?` whose actions contain neither `"no-op"` nor `"read"` must have
  length **exactly 1**;
- that entry's `.address` must be `terraform_data.deploy_pipeline_fix`;
- its `.change.actions` must be `["delete","create"]`.

A `["forget"]` entry is therefore *counted*, which aborts the recovery — the correct, fail-closed
outcome for a state-only mutation nobody planned for.

### R11 — Production write-sites, enumerated

Per `hr-write-boundary-sentinel-sweep-all-write-sites`, this workflow will have **three**, up from
two: `Terraform apply`, the new recovery apply, and `Redeploy to load applied profile` (which
POSTs `deploy` and swaps `web-1`). The `web-1-swap` job concurrency group covers the third. The
workflow-level `terraform-apply-web-platform-host` group is held for the whole run and the second
apply is inside that run — which matters because `main.tf` sets `use_lockfile = false` (R2 has no
conditional writes), making the Actions concurrency group the **sole** state serializer.

### R12 — A consequence to state rather than leave implicit

A run that recovers via pass 2 reports `success()`, so `Redeploy to load applied profile`,
`Close #4804`, and `Auto-close any open drift issues for this stack` all execute — including the
two that mutate GitHub state. That is the intended semantics ("nothing downstream is re-wired")
and it is correct: pass 2 verified the delivery, so the run's success is real. But it is an
unstated consequence of the design's central claim, and it belongs in the ADR.

## Plan Review Consolidation (R13)

The 5-agent eng panel ran (escalated by the `single-user incident` threshold) plus `cpo` from the
named panel. The independent relevance scan activated neither `ux-design-lead` (no UI-surface path
in either file list) nor `cmo` (no market/GTM/brand content). **These decisions supersede the
corresponding parts of R1–R12 above.**

The simplification panel (DHH + `code-simplicity-reviewer`) and the correctness panel fired on the
*same* scope in three places — R2, R5 and R6. Per the consolidation rule, where both panels fire on
one scope the answer is **delete, not fix**: a mechanism that simultaneously attracts "too complex"
and "has specific bugs" is over-architected, and cutting it dissolves the bugs.

### R13.1 — CUT: R5's rolling issue, its new label, and the ≥3/30d escalation

`code-simplicity-reviewer` **measured** the claim R5 rested on and it is false.
`scripts/infra-config-red-alert.sh` hardcodes `--label ci/infra-config-red` at four sites (the
list, the comment, the create and the label-bootstrap) and hardcodes `level: "error"`, with `op`
derived from a closed three-value `reach` enum. Emitting a `warning`-level recovered event through
it means parameterising a **fail-open P1 alert helper** across five sites and widening its enum —
inside a PR whose entire purpose is protecting that alerting path. That is
`hr-type-widening-cross-consumer-grep` territory, and "zero marginal cost" was the assumption that
would have been discovered mid-implementation.

DHH added the independent argument: a `priority/p3-low` rolling issue that accretes comments *is*
the notification an operator learns to scroll past, and building a tier-2 escalation because tier 1
will be ignored is a tell. Worse, the escalation pages the **P1 channel about green runs**, which
devalues the one channel this plan exists to protect.

**Kept:** one Sentry event and one `$GITHUB_STEP_SUMMARY` line. **Cut:** the rolling issue, the
`ci/infra-config-recovered` label (so the `gh label create` task is also cut), and the escalation.
Sentry does `op`-scoped threshold alerting natively; if the counter ever moves, that rule is a
console change, not repo code. **A follow-up issue is filed** recording the deferred escalation with
its re-evaluation criterion (`wg-when-deferring-a-capability-create-a`).

**Also fixed: the plan named two tags for one signal** — `op=infra-config-repush-attempted` in the
Observability block and `op=infra-config-push-recovered` in R5. **One event**, carrying attempt
number and outcome as fields. The canonical tag is `op=infra-config-repush-attempted`.

### R13.2 — CUT: R6 entirely (both halves)

`force_repush_rehearsal` was added so a no-op dispatch could still exercise the recovery after R1
stopped it. Both simplification reviewers independently called this circular: it is a permanent
`workflow_dispatch` affordance that **disables the very discriminator R1 installs**, added so that
CI can test itself. The post-merge verification would depend on a feature that exists only to
enable the post-merge verification.

**AC14 is rewritten instead** — see R13.6. The rename half is cut too: it is cosmetic churn that
drags a Phase 0 verification probe along with it, spent on a string.

### R13.3 — R2 is now a Phase 0 *decision*, not a Phase 3 deliverable

DHH's objection is correct and I accept it: this plan measured 22 hash entries, 8-of-60 dispatch
runs and all 133 C4 relationships — and never measured clock skew. R2 redefines a freshness
semantic #7220 has just shipped, on a hazard nobody looked for. `code-simplicity-reviewer` added
that R2 as written ships **two** comparators (host-vs-host plus an `APPLY_START_EPOCH` fallback),
and that the fallback keeps the exact failure mode R2 invokes fully alive.

**Revised.** Phase 0 gains a measurement: read a recent run's frame `start_ts` against that run's
runner clock and compute the delta.

- **Delta is material** → implement R2, and as a **single** comparator: `FRAME_START_TS` exists and
  **differs** from `PRE_APPLY_FRAME_START_TS`, with an absent pre-frame as a sentinel. No fallback
  arm. This is strictly stronger than either predicate and skew cancels exactly.
- **Delta is ~0** → do not implement. File a follow-up with the re-evaluation trigger tied to the
  Sentry counter kept in R13.1.

Either way, **the classifier's signature is reconciled in the same edit.** R2 silently changed the
second parameter from a runner epoch to a host frame timestamp while Phase 2.1 and T1–T8 still say
`<apply-start-epoch>` — the implementer would have written one and tested the other.

### R13.4 — R10 widens the existing loop; it does not add one

`code-simplicity-reviewer` caught a hazard I missed. The verify body **already** contains
`for attempt in 1 2 3` … `sleep 5` … `done` against the same endpoint — a ~15 s settle window
inside the exact block Phase 3.1 wraps. R10's "bounded pre-classification settle" is a second loop
for the same property, and a second `done` in that region makes Guard 2's *"a `done` strictly
between the two anchors"* clause ambiguous. The plan cut an entire extraction design to protect
that pin and then proposed the one construct that perturbs it.

**Revised: raise the existing loop's attempt count.** Zero new code, zero new call sites, pin
untouched.

### R13.5 — CUT: AC6, subsumed by R3

`host_creates` counts `resource_changes[]` of type `hcloud_server` whose actions include `create`.
R3 already requires the non-`no-op` change set to have length **exactly 1** at
`terraform_data.deploy_pipeline_fix`. Under that assert an `hcloud_server` change is not counted-
and-rejected — it is **impossible**. AC6 is a weaker second mechanism for a property R3 already
holds, and it drags in `terraform show -json` + `jq -f` plumbing plus the filter's documented
`["forget"]` sharp edge. **Cut AC6 and the second-plan destroy-guard invocation; keep R3.**

Worth one inline sentence in the implementation: a future `removed {}` block would produce
`["forget"]`, which R3 correctly aborts on — but the destroy-guard filter's own comment records
that `[ack-destroy]` is unavailable on this workflow, so such a change would wedge this path with
no operator route past it.

### R13.6 — R1 splits into three, and only two are this issue's

`code-simplicity-reviewer` is right that R1 was one bullet hiding the plan's single most dangerous
edit. Split:

| Part | What | Property | Disposition |
|---|---|---|---|
| **R1(A)** | require `DPF_REPLACED == true` before re-pushing | **P3** | **Keep** — this is the half the issue needs |
| **R1(B)** | on `DPF_REPLACED == false`, skip the freshness pin and adjudicate on count+content | *none of P1–P6* | **Declared scope addition.** It fixes #7220's three false-red merge classes. Without it the gate behaves exactly as `main` does today — no regression, just no improvement. Gets its own AC and its own PR-body line so a reviewer sees it |
| **R1(C)** | `Terraform apply` consumes a saved plan file | prerequisite for (A) | **Keep** — and it is a *dependency*, not a "bonus". `DPF_REPLACED` read from a plan is only equal to what was applied if that plan is what was applied. It independently fixes the confirmed TOCTOU |

**AC14 is rewritten** to match: a post-merge `workflow_dispatch` on an unchanged tree now
legitimately produces `DPF_REPLACED == false`, the explicit `::notice::`, **no** re-push,
adjudication on count + content, and a green job. That verifies the new wiring end-to-end on the
path most production runs take, with zero new production affordance. The recovery path's logic is
covered by the hermetic matrix (P5); a live rehearsal would only add "the YAML parses", which the
no-op run proves anyway.

### R13.7 — The stub matrix is structurally blind, and one integration test fixes it

The highest-value finding in the review, raised independently by both simplification reviewers.
R4b states that if a single `exit 1` survives the wrap into `verify_once`, pass 1 kills the step
and pass 2 is unreachable — **and every stub-driven Guard 1 row stays green**, because a stub's
`return` is not the production body's `exit`. Eleven mutation rows, and the single most likely
real-world defect is invisible to all of them. That is the "certifies a property adjacent to the
one it names" class, in the plan's own guard.

Adding a twelfth stub row is not the answer. **Add one integration-shaped test that runs the real
wrapped `verify_once` body twice against fixture responses and proves pass 2 was reached.** It
subsumes most of the matrix and closes the blind spot the matrix cannot.

### R13.8 — Trim the classifier to three clauses

The `files_failed > 0` and `fatal_line > 0` exclusions are **unreachable**: such a frame is either
fresh — in which case the freshness clause already returns non-zero — or stale, in which case it
genuinely is `no_new_frame` and classifying it so is correct. The predicate is exactly: the body
parses; it carries a numeric `start_ts`; it is not newer than the pre-frame. **T9/T10 stay** as
regression tests (they pass on freshness alone); no code is written for them.

### R13.9 — Guard 2 row 4 cut; row 3 respecified

Row 4 (delete the pin block → the floor reds) restates a global harness property the
`GATE_MIN_ASSERTIONS` floor already holds for every assertion. Cut. Row 3 must count `verify_once`
**invocations**, not textual occurrences — a grep count reds on a comment mention.

### R13.10 — R9.4's runbook becomes an issue; the ADR is trimmed

Both reviewers flagged the inconsistency: R9.1 (a genuine paths-filter defect) is filed as an
issue while R9.4 (a pre-existing documentation gap) was to be written inline as ~150 lines. Same
class, same PR, opposite dispositions. **File the runbook as an issue** with the COO's finding
attached, so the operational gap is tracked without absorbing it here.

The ADR is trimmed to **one decision**: the gate may now write production, bounded to one
shape-gated re-push, and the terminal verdict never leaves the step that fails closed — plus the
**ADR-072 distinction**, which stays because review will otherwise stall on that counter-precedent
(different hook, different lock). The `continue-on-error` rejection is **cited** from
`decision-challenges.md` rather than restated. Implementation rationale (the exact-cardinality
assert, the excluded shapes) moves into comments beside `infra_config_bounded_verify`, where the
next editor will actually see it — matching this repo's own dense-provenance convention in
`server.tf`.

### R13.11 — AC hygiene

- **AC4** rewritten (already applied): it referenced a teardown relocation R3 reversed, and it
  asserted on the shape of a diff, which guards against the author rather than a defect. It now
  greps for the seven downstream condition strings verbatim.
- **AC12** cut — asserting a markdown file exists is process, not property; `ship` renders
  `decision-challenges.md` regardless.
- **AC6** cut per R13.5. **AC14** rewritten per R13.6.
- **Standing panel check (concurrent-process independence) — passed.** No AC asserts the absence of
  an ambient signal. AC9 (`test-all.sh` green) was checked specifically: that script's contention
  instrumentation is **observe-only** (it warns and continues), so a sibling worktree cannot flip
  it. AC9 stands.

### R13.12 — One disagreement, recorded rather than resolved silently

DHH recommends cutting **Guard 1 row 4** (the `declare -F` anti-vacuity row) as "testing bash".
**Not cut.** The Guard Contract Gate explicitly requires a row targeting the guard's *own dispatch*
— "a guard that reports 0 checked and exits 0 is vacuous" — and the workflow already carries this
exact pattern for `infra_config_red_alert`. Keeping it is a gate requirement, not a preference.

## R14 — CPO ruling, and a partial reversal of R13.1

`cpo` was activated by the threshold bias (the independent relevance scan found no UI surface, so
`ux-design-lead` and `cmo` stayed off). It ruled on the outstanding sign-off and **measured a fact
that partly reverses R13.1**.

### R14.1 — Threshold stands at `single-user incident`; sign-off granted, conditionally

The ruling turns on a definitional point worth recording, because the counter-argument is
seductive: the repo's threshold vocabulary grades **whether one occurrence is sufficient for the
harm**, not how many users an occurrence touches. `aggregate pattern` is the *lower*-ceremony tier,
for harm that only materialises statistically. One malformed credential on
`/etc/default/soleur-doppler-token` bricks the only no-SSH channel on an unreplaceable host and
ends the platform for every user — including the alpha tester onboarded on 2026-08-06. "Platform-
wide" is an argument for *more* scrutiny, not less. Downgrading would assert that the first brick is
tolerable.

**Sign-off: granted**, conditional on C1 (the split, R14.3), C2 (the milestone, R14.4) and C3 (the
R5 amendment, R14.2). `requires_cpo_signoff: true` is therefore **discharged** in this plan rather
than left outstanding, and `decision-challenges.md` item SO1 is updated to record the ruling.

### R14.2 — PARTIAL REVERSAL of R13.1: Sentry cannot be the counter

R13.1 cut the ledger on `code-simplicity-reviewer`'s reasoning that "Sentry does `op`-scoped
threshold alerting natively". `cpo` measured the premise and it does not hold **from this
workflow**: `scripts/infra-config-red-alert.sh` POSTs to the Sentry **store API with a public
key** — it is write-only. Counting recoveries from Sentry would require provisioning a new **read**
token on precisely the workflow whose blast radius this plan is trying to shrink.

Both measurements are true and they are about different things. `code-simplicity-reviewer` measured
the **cost of reusing the alert helper** (label hardcoded at four sites, `level: "error"` hardcoded,
a closed three-value enum). `cpo` measured **whether Sentry can serve as the counter** (it cannot).
The synthesis satisfies both:

| Layer | Disposition | Why |
|---|---|---|
| Sentry `warning`, `op=infra-config-repush-attempted` | **Keep** — as an observability breadcrumb, explicitly **not** the counter | Correct layer, near-zero cost |
| The ledger | **Restored, but as a ledger and not an alert**: one GitHub issue **created closed**, with the dedupe query widened to `--state all` so it keeps accruing comments | A closed issue never enters the operator's open list or any digest action list, and the comment count is a zero-credential, durable, queryable counter. This answers DHH's desensitization objection directly — the artifact he was right to reject was an *open p3-low issue*, and this is not one |
| Its title | A running tally, not an event — "Ledger: server config pushes that needed a second try" | On the one occasion the founder sees it, the title must say *tally*, not *today* |
| Its label | **Not** under `ci/` and never `action-required` | Every other `ci/*` label in this repo is a red alarm; the two live `ci/infra-config-red` issues literally read "needs a decision". A ledger in that namespace is a category error, and the cost lands on the P1 channel's credibility |
| Written with plain `gh issue` calls, **not** through `infra-config-red-alert.sh` | **Keep the helper untouched** | This is what preserves `code-simplicity-reviewer`'s finding: no five-site parameterisation, no enum widening, no `hr-type-widening-cross-consumer-grep` exposure on the fail-open P1 alert path |
| ≥3 recoveries / 30 days escalation | **Restored** — and it is the **only** artifact that should ever reach the operator | It converts a trend into a decision and asks one answerable question: the race stopped being rare, fix the root cause (a readiness poll after the listener restart). It routes through the existing P1 channel and needs no new credential |
| `$GITHUB_STEP_SUMMARY` line | **Keep** | Self-describing green run, zero notification |

**One property to verify at implementation rather than assert:** "one notification ever" does not
hold if the founder's repo watch setting is *All Activity* — GitHub notifies subscribers on every
comment, and closing an issue does not suppress that. Check the setting; if it is All Activity, the
re-titling and the label move become *more* important, not less.

### R14.3 — Condition C1: the work splits into PR-A (sensor) and PR-B (actuator)

Three reviewers converged on this independently — DHH ("four PRs in a trenchcoat"),
`code-simplicity-reviewer` ("R1 is three revisions, not one"), and `cpo` (a formal ruling). **Adopted.**

The decisive argument is not diff size. It is that **the dependency is one-directional and already
established**: R1 must ship before the recovery, or the recovery fires on the three supported
merge classes and converts them into automatic production writes. Recovery-first is not merely
bigger — it is harmful. Once the order is forced, the split is nearly free.

| PR | Contents | Threshold |
|---|---|---|
| **PR-A — the sensor** | R1(C) saved-plan apply (and the TOCTOU it fixes), R1(A) `DPF_REPLACED`, R1(B) the `DPF_REPLACED == false` arm that ends the three false-red classes, R2 *if* the Phase 0 skew measurement justifies it, and the R9.1 / R9.4 issues | Re-derive — arguably `none`: PR-A **removes** production writes and adds none |
| **PR-B — the actuator** | The `verify_once` wrap (with R4b's `exit`→`return`), `infra_config_no_new_frame`, `infra_config_bounded_verify`, R3's exact-cardinality assert, R10's widened loop, the Guard Contract matrices, R13.7's integration test, R14.2's observability, and the ADR | `single-user incident` |

PR-A also delivers standalone value on day one: three false-reds that today page a non-technical
founder for merges where nothing was wrong, plus a destroy-guard that has been adjudicating a plan
it does not apply. Those are living defects on `main` currently queued behind a `p2-medium`
convenience feature.

**This supersedes the earlier single-PR framing**, and it resolves the R13.6 "declared scope
addition" tension by giving R1(B) its own PR rather than its own bullet.

### R14.4 — Condition C2: milestone drift

`#7104` sits in the **`Post-MVP / Later`** milestone while being implemented now. The roadmap's
convention is that internal-tooling issues live in the **Phase 4** milestone for sequencing.
Implementing from the backlog milestone makes the milestone meaningless as a signal. **Move #7104
to Phase 4** (or stop the work — but the work is justified: this is deploy-reliability
infrastructure protecting the surface Phase 4 onboarding lands on, and active user onboarding began
2026-08-06).

## R15 — Flow analysis: a fail-open inside the plan, and a stale machine description

`spec-flow-analyzer` walked every reachable path and found the thing this plan exists to prevent,
hiding in one of its own revisions.

### R15.1 — P0, THE FAIL-OPEN: the `ALLOW_MISSING_STATUS` arm would return "verified"

R4c ordered the 404 escape hatch preserved byte-identically: with the flag true it warns and falls
through **without running the content assert or the freshness pin**, and the step exits 0. Under
R4b that `exit 0` becomes `return 0` — and `infra_config_bounded_verify` reads `return 0` as
**"pass 1 verified this apply's delivery."**

Guard 1's Property — *"exits zero if and only if at least one of its two verification passes
verified this apply's delivery"* — is therefore **false as written**, and the ADR invariant would
have inherited the falsehood. No mutation row catches it: row 6 (the positive control) drives a
verify stub that returns 0, which is indistinguishable at the stub boundary from an escape hatch
that verified nothing. The escape hatch is pre-existing and dispatch-only, but the new orchestrator
**launders** it from "an arm that skips adjudication" into "a pass that verified".

**Required fix.** `verify_once` must return a **third** status — escape-hatch-taken — that the
orchestrator refuses to count as verification, and Guard 1's Property is restated to name it
explicitly. Plus a mutation row: *the verify stub returns the escape-hatch status; the verdict must
not treat it as a pass.* This row is now the second-most-important in the matrix after R4b's.

### R15.2 — P0: `## Implementation Phases`, `## Test Scenarios` and both signatures are stale

R1–R14 were written as an appendix, and the earlier sections were never folded back. The plan now
describes **two different machines**. Concretely:

- Phase 3 item 6 still says *"Relocate the `Tear down cloudflared SSH bridge` step"* — R3 reversed
  that. An implementer following the Phases section literally builds the superseded design.
- Phase 3 has **no** step for the `DPF_REPLACED` extraction, the saved-plan rework, or R2's
  pre-apply poll.
- `infra_config_no_new_frame <response-file> <apply-start-epoch>` and
  `infra_config_bounded_verify <verify_fn> <classify_fn> <repush_fn>` predate R1/R2/R10 and are
  missing at least `PRE_APPLY_FRAME_START_TS`, `DPF_REPLACED`, and the settle bounds.
- **T1 is now wrong.** "Stale frame → classifier returns 0" is false once `DPF_REPLACED == false`
  makes a stale frame the *expected* healthy state.
- **`GATE_MIN_ASSERTIONS` is circular**: Phase 0.3 measures the count *before* the change and
  Phase 4.3 says raise it to "the measured post-change count from Phase 0 step 3". Phase 0 cannot
  measure post-change.

**Required fix, and it is the first task of the next phase.** Regenerate `## Implementation
Phases`, `## Test Scenarios`, and both function signatures from R13/R14/R15 so the plan carries
**one** description of the machine. Until that pass lands, **R13–R15 are authoritative and the
earlier Phases/Scenarios sections are superseded**. This is exactly the reconciliation
`soleur:deepen-plan` is next in line to perform.

### R15.3 — P1: R10 should re-verify, not classify-and-die

R10's settle exists so a slow-but-alive handler publishes and *falsifies* the classifier. But
falsifying the classifier routes to terminal red — while the handler **succeeded**, and the frame
that just arrived would satisfy `verify_once`. The correct behaviour is to **re-verify against the
newly-arrived frame**, not to classify and die. Combined with R13.4 (widen the existing loop rather
than add one), this becomes: the existing poll loop's own break condition already re-checks the
invariant each attempt, so widening it *is* the re-verify.

### R15.4 — P1: which response the classifier reads is unspecified

`verify_once` polls three times. A run that reads 200-with-a-stale-frame on attempt 1 and `000` on
attempt 3 would classify as `unreachable` → terminal red, no recovery — even though the observed
shape *was* the race. The inverse misroutes too. **The classifier must read a defined artifact**:
the last response that produced an HTTP 200, retained separately from the last response overall.

### R15.5 — P1: pass 2's freshness baseline is undefined

R4a orders `APPLY_START_EPOCH` re-recorded in `repush_once`; R2 demotes it to a fallback and makes
`PRE_APPLY_FRAME_START_TS` primary. Neither says what pass 2 compares against. If pass 2 reuses the
*original* pre-apply baseline, a frame published late by **push 1** satisfies pass 2 — green
credited to a recovery that did not cause it, and the counter inflated. Pass 2 must rebaseline to
the stale frame's own `start_ts`, which is strictly correct: the recovery succeeded only if the
frame is newer than the one that failed. Specify it.

### R15.6 — P1: red jobs with no alert

`Alert on a red infra-config gate (#7220)` is conditioned on `failure()`, which is **false on
cancellation and on job timeout**. The gate step now contains a second plan + apply + a widened
settle, which makes the `timeout-minutes: 90` ceiling materially more reachable — and R11 records
that the Actions concurrency group is the *sole* state serializer, so a cancel mid-second-apply is
the worst moment for it. Pre-existing, and deliberately so (#7220 chose `failure()` precisely so a
cancelled run does not page), but this change widens the window. Record it in the ADR's
consequences and add a timeout-headroom note; do **not** "fix" it by paging on cancellation.

Related, inverted: R1's saved-plan rework and R2's pre-poll add failure modes to steps that run
*before* the gate. There the alert **does** fire (the gate is `skipped`, so `outcome != 'success'`
is true) — with infra-config prose for a terraform-plan cause. The `ungraded` class already exists
for exactly this and the alert step already branches on it; verify that branch still selects
correctly after the rework.

### R15.7 — P2: R1's skip arm rests on an invariant nothing pins

`DPF_REPLACED == false → skip the freshness pin` is truthful **only if every `FILE_MAP` member is
hashed in `triggers_replace`**. If a delivered-but-unhashed file ever exists, that arm greens on a
stale frame with no delivery — or reds on content with **no recovery permitted**, dead-ending at
the manual intervention this issue removes. The plan's `### Terraform changes` asserts the
three-way trigger sync is "untouched and therefore not a concern"; R1 makes it load-bearing for
gate **correctness**, not merely trigger coverage. **Add a Phase 0 probe asserting
`FILE_MAP ⊆ TRIGGER_FILES`, and extend `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts`
to pin it.**

### R15.8 — Corrections already absorbed

Several of spec-flow's findings target text R13/R14 had already cut, and its analysis independently
confirms those cuts were right:

- **AC14 was unachievable as originally written** — under R1 an unchanged tree yields
  `DPF_REPLACED == false`, the pin is skipped, pass 1 **passes**, and the classifier is never
  consulted. R13.6's rewrite already describes exactly that run. Confirmed correct.
- **`force_repush_rehearsal` was wired at the wrong decision point** — reaching the re-push
  requires pass 1 to *fail*, and on that shape R1 makes pass 1 *succeed*, so the rehearsal was
  unreachable. Cut in R13.2. Confirmed correct, on a second independent ground.
- **Rehearsal runs would have fed the auto-escalation**, manufacturing a P1 about a race that never
  occurred, since `ship` performs the dispatch on every merge. Moot once R13.2 cut the rehearsal —
  but R14.2's restored ledger must still **exclude any dispatch-triggered run from the counter**.
- **The two-counter ambiguity** (`repush-attempted` vs `push-recovered`) — resolved in R13.1 to one
  event carrying attempt and outcome, canonical tag `op=infra-config-repush-attempted`.
- **The unbudgeted label creation** would have failed the first recovery's `gh issue create` under
  `set -euo pipefail` — either redding an otherwise-green run or silently dropping the only
  recovery signal. R14.2 moves the ledger off the `ci/` namespace and out of the alert helper; the
  label must still be created as an explicit task, and the emission must be guarded so it can
  never red a run that actually recovered.

### R15.9 — What the flow analysis endorsed

R3's exact-cardinality plan assert is, in its words, the strongest piece of the design: with the
teardown genuinely preceding the gate, it is the only thing standing between a wrong belief and an
SSH dial into a torn-down tunnel. R1(C)'s TOCTOU catch is a real pre-existing defect correctly
scoped inline.

## R16 — P0: the "indentation-only" claim is false, and the design pivots

`kieran-rails-reviewer` verified the plan's mechanical claims (the call-site pin **does** survive an
indentation-only wrap; `awk`'s `$1` is indentation-invariant; equality-is-fresh is right; R3's
cardinality assert **is** expressible, measured against
`tests/scripts/fixtures/tfplan-web-platform-real-baseline.json`) — and then found that the
load-bearing safety claim behind the whole wrap is wrong.

### R16.1 — P0: wrapping the body kills `set -e` inside it

Bash suppresses `errexit` for any command that is part of an `if` condition, a `&&`/`||` list, or
`!` — **and the suppression propagates into function bodies invoked from that context.** The
orchestrator must branch on the verify result, so it necessarily calls `"$verify_fn"` in a
condition. The ~90 lines that today run under an active `set -euo pipefail` would run with `-e`
**off**.

Concretely: today a failure of `source ./infra-config-gate.sh`, of `openssl dgst`, or of
`doppler secrets get WEBHOOK_DEPLOY_SECRET` aborts the step. After the wrap each falls through to
the next line. Some happen to land on a terminal `return 1` by luck — not a property a P1 gate
should rest on. `-u` and `-o pipefail` survive; `-e` does not.

R4b makes it *worse*, not better: converting `exit 1` to `return 1` is precisely what moves the
body into the context where `-e` is dead. And the Guard 1 matrix is structurally blind to this,
because it drives the orchestrator with **stubs**, and a stub cannot exhibit it. This is the plan's
own "logic proven, placement broken" class, one level deeper than where the plan caught it.

### R16.2 — The pivot: a pure predicate, not a higher-order orchestrator

Kieran's alternative is better than the design it replaces, and it is the repo's own convention.
Every function in `apps/web-platform/infra/infra-config-gate.sh` is a **pure adjudicator over paths
and scalars** — `infra_config_expected_count(apply_script)`,
`infra_config_count_invariant(status_json, apply_script)`,
`adjudicate_infra_config(status_json, infra_dir, apply_script)`. Not one takes a function name; not
one calls back into its caller. `infra_config_bounded_verify <verify_fn> <classify_fn> <repush_fn>`
would be the file's first higher-order dispatcher, and it is exactly what makes the suite certify
**stubs** rather than production.

**Replace it with a predicate:**

```
infra_config_should_repush <response-file> <pre-frame-start-ts> <apply-start-epoch> <dpf-replaced>
```

Pure, path-and-scalar shaped, hermetically testable with the existing `build_status_json` harness,
and consistent with all six siblings. The four-line `if`/`else` that consumes it **stays in the
YAML**, where the existing call-site pin already quantifies over production, and where `set -e`
remains in force because nothing is wrapped in a function.

This single change dissolves four findings at once: **R16.1** (no condition-context wrap), **R4b**
(no `exit`→`return` translation, so the most likely shipping defect cannot occur), **R15.1** (the
`ALLOW_MISSING_STATUS` arm never becomes a "pass" because there is no orchestrator to read a return
code as verification), and **P1-4** (Guard 2's boundedness clause becomes countable, because the
YAML now contains real invocations rather than a function name passed as an argument).

It costs a little duplication in the YAML. That is the right trade: duplication over complexity, and
it is what the rest of that file already does.

**Consequences to carry through:** the Guard 1 matrix is re-derived against the predicate (the
mutation rows become "the predicate returns the wrong verdict for input X", which is *stronger* than
stub-driven rows because it exercises the real decision); Guard 2 gains a countable
"`verify_once` is invoked at most twice" clause; and the anti-vacuity row moves to Guard 2 (a grep
pin), where Kieran correctly notes it belongs — `infra-config-gate.test.sh` is hermetic and cannot
execute the workflow, so Guard 1 overstated what it proves.

### R16.3 — P1: three acceptance criteria are unrunnable or dangerous

- **AC11 would perform a production `terraform apply`.** `bash -c '<text>'` **runs** the text, and
  one of the two snippets is `repush_once`. The instinct (never `bash -n` the `.yml`, which is not
  bash) is right; the verb is wrong. Extract the snippet to a file and run `bash -n` **on the
  extracted file**.
- **AC4's diff assertion is vacuous.** In a unified diff every changed line is prefixed `+` or `-`,
  so `^\s*if:` matches no diff line, ever, and the assertion passes unconditionally. Already
  rewritten as a content assertion (R13.11) — which sidesteps this entirely. Additionally
  `grep -c 'continue-on-error' … returns 0` **exits 1**, which aborts any harness running under
  `set -e`; use `! grep -q`.
- **AC10 is not a runnable command** — it carries a literal `<ordinal>` placeholder, greps only two
  directories (missing the decisions directory where the ADR lives), and its expected output is a
  human judgement. Re-express as a concrete grep with a numeric expectation once the ordinal is
  fixed at merge.

### R16.4 — P2 corrections, all concrete

- **`terraform apply <planfile>` rejects `-target=` and `-var`.** R1(C)'s switch means the four
  `-target=` flags and `-var="ssh_key_path=…"` must be **removed from the apply invocation** and
  kept on the plan invocation. R4d covered the `-var` half and the doppler wrapper but not
  `-target`. AC5's wording is correct for the *plan* invocation and must say so explicitly.
- **R3's cardinality filter should pin `mode == "managed"`.** Otherwise a data source deferred to
  apply time (`actions: ["read"]`) would abort the recovery on a false narrowness failure. The root
  has two data sources; both read at plan time today, so this is prophylactic.
- **`DPF_REPLACED` must have a pinned mechanism for crossing the step boundary.** `tfplan` persists
  in the workspace so re-running `terraform show -json tfplan` in the gate step works; if
  `$GITHUB_ENV` is chosen instead, R4a's trap applies in reverse. Pin one; do not leave it to the
  implementer.
- **R2's fallback is a silent downgrade.** A transient pre-poll failure swaps the strict host-vs-host
  comparison for the weaker runner-clock one, silently. The plan invokes
  `cq-silent-fallback-must-mirror-to-sentry` in R5 but did not apply it here: the fallback needs a
  `::warning::`, a Sentry breadcrumb, and a test scenario. (Moot if task 2.1's measurement defers R2.)
- **`GATE_MIN_ASSERTIONS` is already flush.** Measured: the suite reports `64 passed, 0 failed`
  against a floor of `64`, so any deleted assertion reds it today. The raise is mechanical.
- **R1's skip arm loses one real detection, and the plan should say so out loud.** Skipping the
  freshness pin on `DPF_REPLACED == false` is sound for the FILE_MAP class, because
  `infra_config_content_assert` compares host sha256 against the repo at the applied SHA — a stale
  frame from an older commit still reds. But on that shape the gate no longer verifies that the
  **listener came back** after the bootstrap bounced it. Small, but this plan's entire brand-impact
  argument is "the risk is the loss of an existing detection", so it must be named rather than
  discovered.
- **Name the `destroy-guard-filter-<workflow>.jq` convention and why it does not apply.** R3's
  narrowness assert is inline jq; the filter file's own "CAP-COUPLING CONVENTION" says a new guard
  on a new apply path gets a dedicated filter. Narrowness is arguably a different guard class from
  destroy — say so, rather than leaving a reviewer to ask.
- **AC2's second half is a one-time hand mutation** ("temporarily invert the final `return 1`").
  If the property is the primary AC, it belongs in the committed matrix, not in a pre-merge manual
  check that is not reproducible afterwards.

### R16.5 — `scripts/infra-config-red-alert.sh` and the runbook were missing from the file tables

Both Kieran and `code-simplicity-reviewer` flagged this independently, and Kieran measured the same
three hardcoded values (`level: "error"`, the three creation labels, the dedupe lookup label).
R14.2 already resolves the substance by keeping the helper **untouched** and writing the ledger with
plain `gh` calls — so the file does **not** enter `## Files to Edit`, and R5's "zero marginal cost"
claim is withdrawn. The runbook is filed as an issue per R13.10 rather than written here, so it does
not enter `## Files to Create` either. Both dispositions are now explicit rather than omissions.

## R17 — Blast-radius review: the skip arm is near-vacuous, and two live CI gates were never consulted

`architecture-strategist` independently confirmed R16.1 (errexit suspension), R1's measurements, the
TOCTOU, R3's no-SSH reasoning, R7's `server.tf` finding (the comment is ~23 lines above the entry,
not three) and AC13's ships-dark property — and found the structural event this plan had not named:
**it collapses plan + destroy-guard + narrowness-assert + apply + two verification passes into
intra-step control flow.** The workflow's safety today comes from *step boundaries* — the
destroy-guard is unbypassable because it lives in a step whose failure means the apply never runs.
That collapse, not the retry, is the architectural change the ADR must record.

### R17.1 — P0: `DPF_REPLACED == false` needs a polarity guard, and the arm it protects is near-vacuous

**Polarity.** R1 specified no validation for `DPF_REPLACED`. The workflow already documents this
exact trap ~200 lines above, in the `host_creates` block: *"The `^[0-9]+$` validation is
LOAD-BEARING: `jq -r` on a missing key yields the STRING `null` … Without it the guard fails
OPEN."* Any jq error, address rename, module move or empty `resource_changes[]` yields an empty
string, `!= "true"` is satisfied, and the freshness pin is skipped — silently and permanently
restoring #7220's blind spot, invisible to a harness that cannot run terraform. **Required:** a hard
`^(true|false)$` guard that fails closed on anything else, **plus** a positive control asserting
`terraform_data.deploy_pipeline_fix` appears in `resource_changes[]` at all, so address drift cannot
read as a permanent `false`.

**Vacuity — the sharper finding.** R1 said the false arm "adjudicates on count + content only". But
`adjudicate_infra_config` compares each frame file's `sha256` against the checked-out repo, and DPF
was not replaced *precisely because none of its 24 hashed files changed*. A content match is
therefore **guaranteed by construction** on that arm. With the freshness pin also skipped, the arm
reduces to: *the endpoint answered 200, and some frame of unbounded age reports `exit_code: 0`.*

Worst of all, it is weakest where it matters most: on a `seccomp-bwrap.json` or
`apparmor-soleur-bwrap.profile` merge, `docker_seccomp_config` / `apparmor_bwrap_profile` **do**
replace and their SSH provisioners **do** mutate the host. The gate would be at its weakest on
exactly the runs that change the host. Four reachable consequences: parse/address drift disables
the pin forever; a post-push tamper of `hooks.json` or the Doppler token becomes invisible until the
next DPF-replacing merge; a wiped handler still returns 200 with its last frame and greens; and a
`false` misread on a run that *did* race converts #7104's failure from "red, needs a re-run by hand"
into "green, silently undelivered" — **strictly worse than the status quo**.

**Fix, and it costs nothing:** do not skip. R2 already puts `PRE_APPLY_FRAME_START_TS` in hand, so
on the false arm assert **equality** — `FRAME_START_TS == PRE_APPLY_FRAME_START_TS`. That proves the
endpoint is live, self-consistent, and that no unexpected push occurred, at zero false-red cost, and
it keeps the arm non-vacuous. This supersedes R1(B)'s "skip the pin" formulation.

### R17.2 — P1: two live CI gates and a principle the plan never consulted

- **AP-022 / `scripts/lint-workflow-errexit-capture.py`** is registered live in `scripts/test-all.sh`
  and currently scans 74 workflows / 726 `run:` bodies clean. It requires that a step capturing an
  exit status as data either clear errexit explicitly or protect the capture with `|| rc=$?`. This
  design does exactly that capture, and **AC7** ("no `|| true` and no `2>/dev/null` on the apply")
  is in direct tension with the sanctioned `|| rc=$?` form. AC7 must be restated to forbid
  *status-discarding* constructs while permitting the sanctioned capture.
- **AP-021 (diagnostic honesty, ADR-166)** and `scripts/lint-diagnosis-claims.sh`. Two violations:
  (a) the alert helper has exactly **three** classes and none fits "the recovery apply failed" — on
  that path `/tmp/infra-config-status-response.txt` still holds **pass 1's** stale 200 frame, so the
  alert classifies `reachable` and tells a non-technical founder that files landed and to run a
  Better Stack query that will return nothing, on the sole no-SSH channel of an unreplaceable host.
  **Add a fourth `recovery-failed` class with its own body.** (b) R2 makes skew cancel on the primary
  path, yet Phase 2, `## Observability` and `## Risks` all still instruct the terminal message to
  name clock skew — naming an *unmeasured* cause is exactly what AP-021 rejects. Strike all three
  once task 2.1 settles R2.
- **The response file is reused across both passes with no reset.** `curl -s -o` on a transport
  failure can leave the prior body in place, so both the classifier and the alert can adjudicate
  pass-1 data as pass-2 data. **Truncate explicitly per pass.**

Neither linter, nor AP-021, nor AP-022 appears anywhere in the plan's
`## Conventions carried from AGENTS.md`. Add them.

### R17.3 — P1: the saved-plan apply is never exercised before its first production run

Phase 0 step 1 is explicitly plan-only. Nothing proves the *apply* invocation works for this root,
and `deploy_pipeline_fix` carries two `lifecycle.precondition` blocks re-evaluated at apply time.
Combined with AC13 (ships dark), the first execution of a rewritten production apply invocation
would be against the unreplaceable host. **Add a Phase 0 step that produces a genuinely zero-change
`-out=` plan and applies that file** — safe, and it proves the invocation.

R4d's stated reasoning is also wrong and would mislead the implementer: `terraform apply <planfile>`
**rejects** `-var` and `-target`, and variable *values* come from the plan file. Keeping the doppler
wrapper is harmless, but "because provider config is re-evaluated at apply time" is not why.

### R17.4 — P1: one existing invariant silently loses coverage

`Verify webhook is alive post-apply` sits between apply and verify, and `id: terraform_apply` exists
so the alert can distinguish "the gate ran and failed" from "the gate never ran". Both are
**step-boundary** properties. After this change, apply #2 has no webhook-liveness assertion after
it, and a terraform failure can now occur *inside* `infra_config_gate`, blurring the distinction
that step id was created to preserve. The plan's "nothing downstream is re-wired" is true of the
`if:` expressions and false of the invariants those steps encode. **State it plainly in the ADR:**
the "assert the webhook is alive after every apply" invariant now covers only apply #1.

### R17.5 — P2: a deterministic concurrency collision R10 missed, and a stronger safety argument it under-sold

`infra-config-apply.sh` schedules its listener restart with a **fixed transient unit name**
(`systemd-run --collect --on-active=3s --unit=webhook-self-restart …`) under `set -euo pipefail`
with ERR and EXIT traps. A second handler started by the re-push while the first still runs
collides on that unit name → non-zero → ERR trap → the EXIT trap publishes a frame with a
**non-zero `exit_code`** → pass 2 reds. R10's "the per-file outcome is identical either way" is
right about files and wrong about the verdict: concurrency produces a *deterministic spurious red*.
Size the settle against the handler's own timings (+3 s scheduled restart, ~5–8 s listener boot).

Conversely the plan under-sold its own safety case. The self-restart is scheduled immediately before
`exit "$EXIT_CODE"` and the EXIT trap publishes within milliseconds, so **any handler that reached
the restart also published a frame**. A re-push therefore only fires when no handler completed — and
by then (8 s + 3×5 s polls + a plan and an apply) the listener has had 90+ seconds to stabilise.
That is a stronger argument than "the push does not restart the listener", and it belongs in the ADR.

### R17.6 — P2: the gate step's credential surface widens, unlisted

The step's `env:` today carries only `DOPPLER_*` and `ALLOW_MISSING_STATUS`. The observability work
adds `SENTRY_INGEST_DOMAIN`, `SENTRY_PROJECT_ID`, `SENTRY_PUBLIC_KEY` and `GH_TOKEN` (issues: write)
to a step that now also runs `terraform apply`. **The step that adjudicates would hold both
prod-write Terraform credentials and issue-write GitHub credentials.** Not in any file table, not in
any AC. It needs an ADR sentence and an entry in `## Files to Edit`.

### R17.7 — A new principle to register

The register has no principle for the boundary this change crosses. Propose:
**a CI verification gate that also actuates production must declare its write sites in-step, and
must not share a step with its own verdict.** Register it, or amend AP-021 to cover it.

### R17.8 — One unstated positive, worth naming

With `use_lockfile = false`, R1(C)'s saved-plan apply makes a break-glass apply run outside CI (the
ADR-096 path, which sits in **no** concurrency group) fail closed with a stale-plan error instead of
silently last-writer-wins. That is a genuine safety improvement this plan gets for free and had not
claimed. Name it in the ADR.

One unstated negative to balance it: the 90-minute job ceiling already budgets ~70 minutes for the
ADR-078 cron drain in `Redeploy to load applied profile`. The plan's "low single-digit minutes" is
asserted, not derived against that budget. Derive it.

## Domain Review

**Domains relevant:** Engineering, Operations, Product

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Endorsed the in-step shape and strengthened its justification from "preferable" to
**forced** (steps default to `if: success()`, so the split shape is unavailable without
`continue-on-error`). Confirmed the no-SSH claim for the second apply against both resources'
`triggers_replace` and the absence of any `connection` block on `deploy_pipeline_fix`. Raised the
`DPF_REPLACED` finding (R1) as a blocking issue, the host-vs-host freshness fix (R2), the
exact-cardinality assert and the reversal on moving the teardown (R3), and the two implementation
traps (R4a/R4b). Rated the discriminator finding **high** risk if unaddressed; all findings are
adopted in `## Plan Revisions`. One claim it made was rejected on measurement (R7, `server.tf`).

### Operations (COO)

**Status:** reviewed
**Assessment:** Rated the operational risk of automating the remedy **low, and lower than the
status quo** — the decisive fact being that the re-push does **not** bounce the listener (the
nonce-2 property recorded in `push-infra-config.sh`), so the feared failure mode (the remedy
bricking the sole no-SSH channel) is structurally absent. Measured the intervention being removed:
8 of the last 60 runs were manual `workflow_dispatch` interventions (~13%), including the
2026-08-01 failure→dispatch→success pair caught in the act. Raised the recovered-run alerting
design (R5), the countability layer correction (Sentry, not Better Stack), the ADR-072
counter-precedent (R8), the missing runbook (R9.4), and the handler-serialization question (R10).
Confirmed **zero** expense impact: the repo is public and this job runs on standard runners, so
Actions minutes are unbilled and no ledger row is warranted — `wg-record-recurring-vendor-expense-before-ready`
does not trigger. One claim it made was rejected on measurement (R7, ADR-068).

Two out-of-scope operational observations, recorded but not acted on: 18 expense rows carry an
overdue `verify_by=2026-08-01`, and `knowledge-base/operations/domains.md` is 86 days old against a
90-day staleness threshold. Both are CFO/ops-advisor work, unrelated to this issue.

### Product/UX Gate

Not applicable. The mechanical UI-surface override did not fire: no path in `## Files to Edit` or
`## Files to Create` matches the UI-surface term list or glob superset — the change is a workflow,
two bash functions, a test suite, an ADR and a runbook. Product was assessed **NONE** by the
semantic sweep as well; there is no user-facing surface, no new flow, and no copy.

### Domains assessed and found not relevant

Legal (no data-processing change, no document), Marketing, Finance (see the COO's zero-cost
finding), Sales, Support (the operator-facing alerting is engineering wiring, reviewed above).

## GDPR / Compliance Gate

Invoked because the plan declares `brand_survival_threshold: single-user incident` (Phase 2.7
trigger (b)); the canonical regex does not fire — no schema, migration, auth flow, API route, or
`.sql` file is touched.

**Finding: no new processing activity, and no Article 30 entry is warranted.** The change moves no
personal data. The only credentials in scope (`/etc/default/soleur-doppler-token`,
`/etc/webhook/hooks.json`) are machine secrets, not personal data, and this plan neither reads nor
renders them — the existing tier-2 compare already handles the rendered digest, and the re-push
re-sends bytes the same run already computed. The three new operator-facing artifacts (the rolling
recovered-run issue, the Sentry `warning` event, the step summary) carry run URLs, commit SHAs and
frame field values, all of which are sanitised at source by the handler's exit trap to
`A-Za-z0-9 ._:/=-`. No Critical finding; nothing to write to `compliance-posture.md`.

## Encryption Posture

Skipped, per Phase 2.11's skip condition. No persistent data store is introduced (no volume,
bucket, table, queue, cache, backup target or log sink) and no new cross-component connection is
created — the re-push reuses the existing HTTPS + Cloudflare Access + HMAC channel that
`push-infra-config.sh` already opens. No `.tf`, `supabase/migrations/*.sql`, `cloud-init*.yml` or
`docker-compose*.yml` file appears in `## Files to Edit`, so the detection globs do not fire either.

## Implementation Findings (PR-A)

Recorded at `/work` time. Where a measurement contradicted the plan, the measurement wins and the
superseded position is named rather than quietly dropped.

### The defect is live, and its cause is one of the three named classes

Run `31636951749` (2026-08-12, `main` @ `0d644396`). Paths-filter ∩ commit-files intersection =
**exactly `apps/web-platform/infra/server.tf`**; `terraform plan` → `No changes`; `terraform apply`
→ `Apply complete! Resources: 0 added, 0 changed, 0 destroyed`; gate → `STALE FRAME` against the
2026-08-06 frame. The gate was red on `main` when this work began. PR-A turns that run green
*correctly*: nothing was pushed, so the pre/post frames are equal.

### Task 2.1 — clock skew is immaterial, so R2 does NOT ship

| Run | Apply start (runner) | Apply complete (runner) | Frame `start_ts` (host) | host − runner at push |
|---|---|---|---|---|
| 31049971942 | 21:46:30.95 | 21:46:52.39 | 21:46:51 | ≈ −1.4 s |
| 31081679510 | 07:38:54.51 | 07:39:11.90 | 07:39:11 | ≈ −0.9 s |

`APPLY_START_EPOCH` matches the runner's own log timestamp exactly (the sanity check on the
method). Resolution is ~±2 s (`start_ts` is whole-second; push→handler latency is ~0–2 s and not
separately measured), and both readings sit inside that floor. Per R13.3's own branch: **do not
implement R2**; deferred with a re-evaluation trigger in #7527. The pre-apply *capture* still
ships — it is what the no-push arm compares against. Only the `true` arm's comparator swap is
deferred.

### Task 2.2 — `FILE_MAP ⊆ TRIGGER_FILES` HOLDS, and the first reading of it was wrong

A first extraction reported two violations (`hooks.json`, `soleur-doppler-token`). **Falsified on
re-check at the right granularity:** both are covered by rendered locals in `triggers_replace`
(`local.hooks_json` at `server.tf:1621`, `local.webhook_doppler_token_env` at `:1636`), which a
`${path.module}/` path-literal extraction cannot see. Containment holds **20/20** (18 path
literals + 2 rendered locals) and is now pinned by a test. This *confirms* R17.1's vacuity finding:
content match on the `false` arm really is guaranteed by construction.

### R17.1's justification is partly false — corrected, not inherited

R17.1 argued the equality assert also catches a wiped handler and a post-push tamper. It catches
neither: a wiped handler leaves the last frame **in place** (`PRE == POST`, assert passes), and the
frame records the **last write**, not a re-read of the bytes on disk. Equality establishes **frame
stability only**. Both holes stay open (#7527). What it *does* buy, which R17.1 did not claim: it
reds a **plan/apply divergence**, which is a stronger argument than the one given.

### The sentinel arm was an unresolved fork — routed to the CTO agent, ruled Option C

R17.1 said "absent-pre as sentinel" without saying what that arm *does*. Routed as an architecture
decision (fail-open/fail-closed boundary on a gate protecting an unreplaceable host). Ruling:
**degrade, escalate, pass — never red**, because the arm is reachable only when the pre-poll failed
*and* the post-poll returned 200, so a genuinely-down endpoint still reds via the existing
`000/502/503` branch. Failing closed there would trade one false-red class for another. The
governing rule is recorded in ADR-186: *fail-closed is proportionate to what the missing evidence
would have proven, not to the fact that some evidence is missing.*

### ADR-072 was mischaracterised in R13.10

R13.10 described the needed distinction as "different hook, different lock". ADR-072 governs
`await-ci` waiting on a CI check-run for the prod deploy cutover; that phrase does not describe it.
ADR-186 states the real distinction: ADR-072 waited on a signal that *was* going to arrive, so
adaptive waiting was the fix; here the newer frame is **never coming**, so waiting longer converts
a fast false-red into a slow one and the predicate itself must change.

### Task 3.7 — PR-A's threshold stays `single-user incident`

Task 3.7 speculated PR-A might be `none` since it "removes production writes and adds none". It
adds none, but it **rewrites the production apply invocation** (saved-plan) and **changes which
freshness assertion guards the credential channel**. A wrong `DPF_REPLACED` disables the stale-frame
pin on a host that cannot be re-provisioned. Downgrading the threshold on the PR that touches the
gate's own predicate would be self-serving. Held at `single-user incident`.

### Verification performed

- `infra-config-gate.test.sh`: **95 passed, 0 failed** (baseline was 64; floor raised to 95).
- Mutation battery, 16 mutants against a sandbox copy: **all RED, no vacuous arms**. Three
  survivors were caught and fixed *during* the work — M2 and M8 were fixture gaps, and S8 revealed
  that under `set -u` the guard's value is the **diagnostic**, not the return code (without it the
  step dies mute before the `::error::` branches run), so that fixture now asserts stderr.
- `actionlint` clean; `lint-workflow-errexit-capture.py` clean over 728 `run:` bodies; all 19
  extracted `run:` blocks syntax-check under `bash --noprofile --norc -eo pipefail`.
- Production call-site pin intact and self-deriving: `count_invariant` in-loop (L740),
  `adjudicate_infra_config` terminal after the loop's `done` (L755 < L775).
- Filed: **#7526** (paths-filter contradiction), **#7527** (consolidated follow-ups).
