---
title: "feat: dispatch-only key-rotation workflow for the non-tunnel secrets (Ref #11294, Ref #10205)"
date: 2026-11-02
slug: key-rotation-workflow
branch: feat-one-shot-key-rotation-workflow-11294
issue: 11294
type: feat
priority: p1
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# feat: dispatch-only key-rotation workflow for the non-tunnel secrets

## Enhancement Summary

**Deepened on:** 2026-11-02. **Agents used:** security-sentinel, terraform-architect, observability-coverage-reviewer, test-design-reviewer, user-impact-reviewer (after plan-review by DHH, Kieran, code-simplicity, architecture-strategist, spec-flow; CTO and CPO consulted throughout).

### Key improvements
1. The recovery gate was corrected: the `random_id` row's `before` comes from Terraform state, not Doppler, so the all-absent path accepts the right shapes (H1); a pre-write proof of the `ignore_changes` premise (`action_reason`, `after_unknown.value`) replaces a post-write detector.
2. The plan JSON is projected to five fields and deleted at once (it holds every root variable, including the workplace Doppler token variable).
3. Authorization is no longer policy-only: a committed owner-login allowlist, a `main`-only ref rung, and `approval_environment_missing` for the `_prd` keys and the webhook secret until the reviewer-gated environment (#11923) exists (H2).
4. The redaction sanity step moved to the credential-free guard job (H3); issues are filed only by `notify`, with a loud re-list check; outputs go through an allowlist.
5. User-Brand Impact is now role-by-role with verified consumers (cohort writes, reminders, home census, the five webhook events), including skew and restart-while-absent consequences.
6. The test plan got literal oracles, a single clock, honest stub fidelity, a weight row and a token-coverage table.

### New considerations discovered
- `infra-privileged` has zero required reviewers (measured); the R2 backend has no state lock; `-replace` of an absent address is unverified until a dev rehearsal.
- The runbook's GitHub App owner-step command block looks stale against the current Doppler layout and is re-verified in Phase 5.
- No alert rule routes the kb-drift or webhook signature-failure events (#11928); dev-key redeploys carry user-visible swap risk with no pickup (#11927).

Ref #11294. Ref #10205. Existing draft PR for this branch: #11918. Decision record: `knowledge-base/project/specs/feat-one-shot-key-rotation-workflow-11294/decision-challenges.md` (rulings F1-F9, the plan-review rulings G1-G7 and the deepen-plan rulings H1-H3, Ruled by CTO agent, 2026-11-02; where a G ruling changes an F ruling the G ruling governs). Tracking issues filed: #11920 (egress restart lever), #11922 (webhook verifier grace window), #11923 (reviewer-gated approval environment), #11927 (dev-key redeploy skip), #11928 (signature-failure alert rules).

Spec lacks valid `lane:` (no `spec.md` exists for this branch) - defaulted to `cross-domain` (TR2 fail-closed).

## Amendment 2026-11-02 (CTO ruling on the Terraform advisory; supersedes any "replace both" wording below for three keys)

Ruled by CTO agent, 2026-11-02: for the three secrets WITHOUT `ignore_changes` (`kb_drift_ingest_signing_key` both copies, `github_webhook_secret`, `egress_audit_ingest_token`), the rotation `-replace`s the `random_id` ONLY; the `doppler_secret` copies update in place (their `value` derives from `random_id.<x>.hex`), so there is no absent-secret window. "Replace both" stays for the four `inngest_*` secrets that carry `ignore_changes=[value]`. Wherever this plan says "replace the `random_id` AND its `doppler_secret`" for a key in the first group, read it as this amendment: the gate-table row for the copy is `update`, derived from the HCL by the Guard 5 parity test; kb_drift keeps its count of 3 (one `random_id` replace plus two `update` rows); the G1 all-absent recovery path still applies to the inngest keys. A dev plan rehearsal showing anything other than `["update"]` with `after_unknown.value` flips this back. Also ruled: the PR stops at ready and unarmed with the two prerequisite PRs named in its body; one key per dispatch; the guard job holds no credential.

## Overview

Build ONE new dispatch-only workflow, `.github/workflows/key-rotate.yml` (body `scripts/key-rotate.sh`, suite `apps/web-platform/infra/key-rotate-workflow.test.sh`), that rotates a single chosen secret per dispatch. `mode=plan` is the read-only rehearsal and needs no confirm. `mode=rotate` needs the typed confirm `ROTATE-<KEY>-<YYYY-MM-DD>` (a fat-finger guard, not an authorization: the `infra-privileged` environment has zero required reviewers, measured 2026-11-02, so the string is derivable from public inputs; the authorization is the owner's fresh in-session go naming the exact command, and "agents never dispatch rotate" is a policy, not a mechanism - CTO G6; CTO H2 adds the committed owner-login allowlist `actor_not_owner`, and until the reviewer-gated environment of #11923 exists `mode=rotate` for the `_prd` keys and the webhook secret refuses `approval_environment_missing`; an owner PAT still passes). Each rotation is a targeted `-replace` of BOTH the `random_id` and its `doppler_secret` in one apply, followed by a canary-then-prod fleet redeploy. Every Terraform stream goes to a private file through the existing `kr_tf` chokepoint (the repository is public). The existing `inngest-key-rotate.yml` and `scripts/inngest-key-rotate.sh` are NOT edited: the new script sources the old one and overrides what differs (CTO F1).

**Nothing in this change dispatches anything.** The PR adds machinery only. No production write happens in planning, work, review, QA or compound. Every `rotate` dispatch needs the owner's own typed go, one key at a time, `inngest_manual_trigger_secret_dev` first (CTO F3). `tunnel_secret` stays last, separate and outside this route.

Two prerequisite PRs are part of the delivery (CTO F7, F8a), opened from their own branches in the work phase and not armed or merged by the pipeline: **PR-F** (redaction-filter fix) and **PR-0** (trio-census `@allow` lines). See Phase 0 and Phase 5.

### Keys in scope (one per dispatch)

| `key` input | `random_id` (gate rows A) | `doppler_secret` (gate rows B) | Copy read for value-silent hashing (project / config / name) | Extra guard |
|---|---|---|---|---|
| `inngest_manual_trigger_secret_dev` (shakedown first) | `random_id.inngest_manual_trigger_secret_dev` | `doppler_secret.inngest_manual_trigger_secret_dev` (`ignore_changes=[value]`) | `soleur` / `dev` / `INNGEST_MANUAL_TRIGGER_SECRET` | none |
| `inngest_manual_trigger_secret_prd` | `random_id.inngest_manual_trigger_secret_prd` | `doppler_secret.inngest_manual_trigger_secret_prd` (`ignore_changes=[value]`) | `soleur` / `prd` / `INNGEST_MANUAL_TRIGGER_SECRET` | `approval_environment_missing` until #11923 |
| `inngest_signing_key_dev` | `random_id.inngest_signing_key_dev` | `doppler_secret.inngest_signing_key_dev` (`ignore_changes=[value]`) | `soleur` / `dev` / `INNGEST_SIGNING_KEY` | none |
| `inngest_event_key_dev` | `random_id.inngest_event_key_dev` | `doppler_secret.inngest_event_key_dev` (`ignore_changes=[value]`) | `soleur` / `dev` / `INNGEST_EVENT_KEY` | none |
| `kb_drift_ingest_signing_key` | `random_id.kb_drift_ingest_signing_key` | `doppler_secret.kb_drift_ingest_signing_key` AND `doppler_secret.kb_drift_ingest_signing_key_app_runtime` (3 rows; one apply) | `soleur` / `prd_kb_drift_walker` / `KB_DRIFT_INGEST_SIGNING_KEY` and `soleur` / `prd` / `KB_DRIFT_INGEST_SIGNING_KEY`; the two must end equal | budget-aware cron window around 03:00 UTC (G3) and walker-in-flight; `approval_environment_missing` until #11923 |
| `egress_audit_ingest_token` | `random_id.egress_audit_ingest_token` | `doppler_secret.egress_audit_ingest_token` | `soleur` / `prd` / `EGRESS_AUDIT_INGEST_TOKEN` | `mode=plan` only; `rotate` refused `egress_rotate_unsupported_no_vector_restart_lever` (#11920) |
| `github_webhook_secret` | `random_id.github_webhook_secret` | `doppler_secret.github_app_webhook_secret` | `soleur` / `prd` / `GITHUB_APP_WEBHOOK_SECRET` | `webhook_patch_ready=true` attestation; `owner_step_open`; `approval_environment_missing` until #11923; ends `owner_step_pending` (non-success) after a good redeploy |

Out of scope: `tunnel_secret` (ADR-307 amendment of 2026-10-29: a real rotation replaces the tunnel and rebuilds web-2, roll-forward only). The GitHub App webhook-secret update itself (needs the App private key) is documented as an owner step and is not automated.

## Research Reconciliation - Spec vs. Codebase

| Brief claim | Reality (verified in this worktree) | Plan response |
|---|---|---|
| "inngest.tf: random_id ~line 69/73, doppler_secret ~148/160; both have ignore_changes=[value]" | The `random_id`s sit at the manual-trigger block; the two `doppler_secret.inngest_manual_trigger_secret_{prd,dev}` carry `ignore_changes = [value]`, so does `doppler_secret.inngest_{signing,event}_key_dev`. Line numbers drift; anchors are the resource names. | Gate rows B are `replace` for every `doppler_secret` that carries `ignore_changes`; a parity test derives that from the HCL (Guard 5). |
| "kb_drift: two doppler_secret copies at ~39 and ~54, the plan gate must expect both" | True: `doppler_secret.kb_drift_ingest_signing_key` (`prd_kb_drift_walker`) and `doppler_secret.kb_drift_ingest_signing_key_app_runtime` (`prd`), both without `ignore_changes`. | Three table rows, one apply; the gate requires an exact count of 3, so a plan touching one copy is refused. |
| "egress: lossless via the _PREVIOUS scheme ... Doppler PREVIOUS write, apply, redeploy plus Vector restart, clear PREVIOUS" | The route accepts CURRENT and PREVIOUS (`egress-audit-ingest.ts` `configuredTokens`), but Vector reads the token only at start and NO restart lever exists without SSH (restarts live in Terraform SSH provisioners and `inngest-bootstrap.sh`; `ci-deploy.sh` has none). `EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS` is not declared in Terraform. | CTO F2: egress is `plan`-only, `rotate` is refused with a fixed verdict, tracked in #11920. |
| "github_webhook_secret ... single secret in the route" | `apps/web-platform/app/api/webhooks/github/route.ts` verifies with the one secret; the doppler_secret has no `ignore_changes`. The runbook `github-app-provisioning.md` Step 4 documents the PATCH. | A dual-secret grace window would be an app code change and is out of scope (CPO raised it; the brief fixes "single secret"). Recorded as a follow-up candidate in Sharp Edges; mitigated by the quiet window, `webhook_patch_ready` and GitHub delivery redelivery (runbook). |
| "Reuse its kr_tf ... and its gate-table pattern" | `scripts/inngest-key-rotate.sh` has a source guard (last line), a non-readonly `KR_GATE_TABLE`, overridable `kr_refuse`/`kr_ok`, and `kr_tf` is Inngest-independent (runs `terraform` in `$KR_INFRA_DIR` under `doppler run -c prd_terraform`). Its hard-coded `inngest-key-rotate` strings: the verdict prefix, `mktemp` prefix, the issue title, the confirm. | CTO F1 (A): source and override. Hard-coded Inngest text lives in callers the new script would otherwise inherit (`kr_post_write_stop`, `kr_file_issue`, `kr_stop_sentence`, `kr_verdict_recipe`, `kr_converge_cmd`, `kr_print_contract`, `kr_cmd_notify`, `main`, `kr_chk_confirm`), so those are REDEFINED BY THE SAME NAME (bash binds late; a `kk_*` wrapper beside them would not intercept the sourced callers), and the gate gets `kk_gate`/`kk_gate_plan` copies that take a unioned want. |
| "update workflow parity tests (terraform-target-parity) as needed" | `plugins/soleur/test/terraform-target-parity.test.ts` pins `inngest-key-rotate.yml`'s targets (existsSync-guarded, ~line 1729) and sweeps every workflow for the redaction filter (`describe "terraform stream key-material redaction"`). The new workflow's Terraform calls live in the script, so the sweep sees no `terraform` step in the YAML. | Add a `key-rotate` describe (Guard 5) and raise `TEST_FLOOR`; keep the sweep green by having no `terraform` token in the YAML. |
| "Also verify and report whether the redaction filter covers the plan lines the CTO flagged as unverified" | See `## Redaction coverage report` below: covered for refresh/destroy/create/modify lines, ANSI-coloured lines and `will be replaced, as requested` blocks (the `-replace` shape this route produces); NOT covered for `is tainted, so must be replaced` (and any header where the address is not followed by `will be`/`must be`). | CTO F8a: fix in PR-F, which merges first. |
| (implicit) "new workflow needs no census change" | `tests/scripts/trio-baseline.tsv` is RED for any new `(file, name)` key of `WEBHOOK_DEPLOY_SECRET`, `CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET` without a merge-base `@allow` (ADR-241 line ~1086; the 10540 route used PR-0 precedent, ADR-241 lines 1088-1093). | CTO F7: PR-0 (`@allow` only) first; this PR spends the allows. |

## Research Insights

### Premise validation (Phase 0.6)

Checked: #11294 (open, p1 security audit), #10205 (open epic), #11918 (this branch's draft PR, the only open change naming #11294; the two foreign `test-all.sh` processes are other worktrees' runs, not collisions), ADR-307 `Decision` and `Considered Options` (the route shape is ruled, not re-opened), the ADR-241 trio-census text, and every cited file/symbol on this branch (`inngest.tf`, `kb-drift.tf`, `egress-audit.tf`, `github-app.tf`, `scripts/inngest-key-rotate.sh`, `tests/scripts/lib/tf-redact-random-ids.sh`, `apply-web-platform-infra.yml`). Held: all cited resources and scripts exist. Stale/wrong in the brief: none material; line numbers drift (use names). New facts found: the egress Vector-restart gap, the trio-census sequencing constraint, and the tainted-block redaction gap.

### Property list and cut list (Phase 0.6b)

Properties: (P1) a key never reaches a public log, summary, artifact or issue; (P2) a rotation changes exactly the chosen key's `random_id` and every `doppler_secret` copy of it, nothing else; (P3) nothing is written unless a fresh owner go, a first attempt, a quiet window and no related run in flight all hold; (P4) the consumers pick up the new value (fleet redeploy) and the run says so only when `track.sh` confirms; (P5) a half-finished rotation is loud and recoverable without SSH; (P6) redaction coverage is confirmed on the dispatched ref before any Terraform step.

Cut list: a `converge` mode (CTO ruled modes `plan|rotate`; recovery is a fresh `rotate`, F9); a host reboot/verify leg (these keys are not scheduler channel keys); Hetzner or Better Stack credentials in the guard (not needed); an `apply_target` in `apply-web-platform-infra.yml` (ADR-307 Option A, byte-gate); a new shared lib extracted from the old script (F1 rejected B); a Doppler CLI write path for the egress PREVIOUS value (F2 rejected); multi-key dispatch (one key per dispatch, the confirm names one key); a `reason` input (no ask requires it and in a public repository every dispatch input that reaches an issue or summary is one more thing to scrub; the run-name already carries mode and key); an `ignore_changes` classifier in the parity test (every row is `replace` by ruling, so the classifier is vacuous); a same-key cooldown (the lower-run-id guard rung and `owner_step_open` cover the double-dispatch cases); a redeploy-only mode or a dispatch of `web-platform-release.yml` as recovery (same-version redeploys deliberately mint no release, `track.sh` header).

### Consumer and pickup (what `rotate_ok` does and does not prove)

`rotate_ok` means the fleet redeploy was confirmed by `track.sh`; it does not mean each consumer was verified. The production fleet reads `soleur/prd`, so for `inngest_manual_trigger_secret_prd`, the `soleur/prd` kb_drift copy and `GITHUB_APP_WEBHOOK_SECRET` the redeploy is the pickup lever; the kb_drift walker reads `prd_kb_drift_walker` at its next run. The three `soleur/dev` keys (`inngest_manual_trigger_secret_dev`, `inngest_signing_key_dev`, `inngest_event_key_dev`) have no production container consumer, so the production redeploy is a rehearsal of the route's last leg, not a pickup; CTO F3 requires it anyway because a dev rotation that skips the redeploy does not shake down the route, and the ADR records the rationale. Dev consumers (developer shells, dev servers) read `soleur/dev` at their own start and are outside this route. A follow-up to make the redeploy skippable for dev keys is possible once the route has run.

### Institutional learnings applied

- `learnings/best-practices/2026-06-18-live-credential-rotation-and-argv-to-env-redeploy.md`: `ignore_changes=[value]` suppresses propagation, so rotation needs `-replace` on BOTH the id and the secret and a plan that proves the value change.
- `learnings/best-practices/2026-07-09-terraform-source-guard-must-key-on-arming-class-not-ignore-changes-value.md`: static guards must key on immutable properties; the parity test derives flags from the HCL, not from the table.
- `learnings/security-issues/2026-09-24-a-second-apply-workflow-could-perform-the-rotation-without-its-gate.md`: enumerate every workflow that can apply the same resources; the in-flight list and the `terraform-apply-web-platform-host` group cover them.
- `learnings/2026-06-17-terraform-target-parity-test-guards-only-terraform-data-subset.md`: a misspelled `-target` silently no-ops; the gate's exact-count and exact-address rule is the net.
- `learnings/security-issues/2026-05-25-terraform-show-json-leaks-sensitive-variables-into-fixtures.md` and `2026-05-25-tfplan-fixture-redaction-must-scrub-sensitive-output-changes.md`: plan JSON carries key bytes; it stays a private file and the suite's fixtures are synthesized.
- `learnings/2026-09-10-my-battery-killed-all-26-and-could-not-see-any-of-the-20-escapes.md`: mutation rows must add a member (second kb_drift copy) and not only edit one.
- `learnings/2026-10-04-an-allow-list-of-line-shapes-is-not-a-closed-sequence-and-a-text-matching-hook-stops-delegated-agents-silently.md`: the static workflow tests assert closed sequences (job graph, step order), not line shapes.
- `learnings/2026-10-12-a-destructive-single-use-workflow-needs-content-evidence-a-gate-after-it-and-credential-parity.md`: re-run the in-flight refusal as the first act of the write job (approval waits can be hours).

### Redaction coverage report (what the CTO flagged as unverified)

Method: synthesized plan/apply text (no real key material, sentinel strings built from repeated letters) was fed through `tests/scripts/lib/tf-redact-random-ids.sh` and grepped for survivors; scratch fixtures only, nothing committed. Results:

| Shape (the route's in-scope addresses) | Redacted? |
|---|---|
| `random_id.X: Refreshing state... [id=<key>]`, `Destroying... [id=<key>]`, `Creation complete after 0s [id=<key>]`, `Modifying... [id=<key>]` | yes |
| ANSI-coloured variants of the above (`ESC[0mESC[1m...`) | yes |
| `# random_id.X will be replaced, as requested` block (b64_std, b64_url, dec, hex, id on the left of `->`) - the shape a `-replace` of the in-scope `random_id`s prints | yes |
| `# doppler_secret.X will be replaced, as requested` block (`value = (sensitive value)`, `computed`) | yes (Terraform masks the value; the id is a path, not a key) |
| `# random_id.X will be destroyed` block | yes |
| `# random_id.X is tainted, so must be replaced` block | **NO - old hex, b64_url and id print un-redacted** |
| `# random_id.X (deposed object abc123) will be destroyed`, "Objects have changed outside of Terraform" drift blocks | not covered by the block-start regex (address must be followed by `will`/`must` + `be`); CTO F8a treats them as one class |
| `grep -E 'will be replaced\|...' tfplan.txt` lines printed by `apply-web-platform-infra.yml` (about lines 821-916) | safe: the patterns match only the `# addr will be ...` header lines, which carry no key bytes |

The gap matters because `inngest.tf`'s own comments tell operators to rotate the dev keys with `terraform taint random_id.<name>`. It does not affect the new workflow (its Terraform streams never reach a log), but it does affect "dispatch only after the redaction coverage is confirmed" for every other job. Resolution (CTO F8a/F8b): PR-F fixes the filter first with RED-first rows; the new workflow's credential-free `guard` job re-runs `tests/scripts/test-tf-redact-random-ids.sh` on the dispatched ref (CTO H3: not in the credential-holding `apply` job) and refuses with `redaction_coverage_unconfirmed` on a non-zero exit or a missing row label; `apply` runs only if `redaction_ok` is true. It is an ordering and sanity step: the safety weight is the no-stream design. The runtime result of the PR-F suite run is unverified until CI (the CTO asked that PR-F run the shard holding `terraform-target-parity.test.ts`).

## User-Brand Impact

- **If this lands broken, the user experiences:** between the first container swap and the owner's GitHub App webhook-secret update, every delivery to `/api/webhooks/github` is rejected 401 (half of them while the fleet is mixed): push reconcile (`WORKSPACE_RECONCILE_REQUESTED_EVENT`), `engineering.ci_failed`, `engineering.pr_review_pending`, `triage.p0p1_issue` and `security.cve_alert` for the connected founder are not dispatched, and GitHub does not auto-retry, so each stays lost until redelivered. The window ends only when the owner updates the App secret (`owner_step_pending` stays open until then); the runbook states the redelivery cutoff and lists failed deliveries since the first-swap timestamp (confirm GitHub's delivery retention when writing it). The canary-then-prod redeploy restarts both hosts with a roughly 12 second SIGTERM drain: a user turn mid-stream (`messages.body`) or mid-write in the workspace tree is cut off and the client must reconnect. That is the blast radius of a normal release; it applies to all seven keys including the three `_dev` keys (which gain no pickup from it, #11927) and is bounded only by the owner's self-attested `quiet_window`. For `inngest_manual_trigger_secret_prd` the host-side readers (`inngest-rearm-reminders.sh`, `inngest-wiped-volume-verify.sh`, `home-census-trigger.sh`) pick up the new value at apply, before the swap, while the routes `trigger-cron`, `schedule-reminder`, `cohort` and `home-census` return 401 on a skewed host until its container swaps: a reminder armed through `schedule-reminder` or a `users.cohort_key` write in that skew fails and is not retried.
- **If this leaks, the user's workflow is exposed via:** Terraform printing a `random_id` `id` (the key in base64url) in a public Actions log, summary, artifact or action-required issue body; the plan JSON additionally holds every root variable (including the workplace-scope Doppler token variable) and the prior state, so a single leaked stream is worse than one key. Anyone holding the webhook secret or the manual-trigger bearer can forge GitHub events or trigger crons. Public surfaces other than logs (run-name, dispatch inputs, issue titles) reveal rotation timing but carry no key bytes.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one forged webhook, one leaked key in a public log, or one dropped GitHub event for a real connected user is a single-user incident with no aggregate signal to catch it; the CPO agent concurred (2026-11-02) and the sibling route (ADR-307) carries the same tier.

Role-by-role artifact/vector rows for `soleur:engineering:review:user-impact-reviewer` (verified by grep under `apps/web-platform`):

| Role | Artifact (identifier) | Vector | Coverage |
|---|---|---|---|
| Connected founder | the five GitHub-driven events above, `GITHUB_APP_WEBHOOK_SECRET` | 401 from first swap to the owner step | `webhook_patch_ready`, `owner_step_open`, `owner_step_pending` issue with redelivery steps; unbounded only by the owner |
| Alpha-tester | `users.cohort_key` via `/api/internal/cohort` | 401 in the manual-trigger skew; no retry | runbook: no cohort tagging or reminder arming during a prd manual-trigger rotation |
| Platform reminders | `/api/internal/schedule-reminder`, `trigger-cron`, `home-census` | same skew | same runbook line; kb_drift-style window not needed |
| Any user mid-session | `messages.body`, workspace working tree | container swap drain | `quiet_window` (self-attested), shared group with the release workflows; residual |
| Operator | `kb_drift_findings` rows (operator-attributed; no customer data) | walker run overlapping the apply-to-swap skew; next nightly run self-heals; a manual `workflow_dispatch` of `kb-drift-walker.yml` mid-rotation is not blocked (residual) | G3 window plus walker-in-flight rung |
| Any container started while a copy is `absent` | `INNGEST_MANUAL_TRIGGER_SECRET` (503 on `/api/internal/*`), `GITHUB_APP_WEBHOOK_SECRET` (500 on every delivery), `KB_DRIFT_INGEST_SIGNING_KEY` (500 on ingest) | a restart in the absent window boots without the secret (no health gate on these variables) | G1 absent path, urgent issue, mandatory redeploy | *(Superseded for `kb_drift_ingest_signing_key`, `github_webhook_secret` and `egress_audit_ingest_token` by the Amendment 2026-11-02: only the `random_id` is replaced and the copies update in place, so these three have no absent window on the normal path; the absent window remains for the four `inngest_*` secrets.)*
| Any write-access actor | forced rotation, hence a forced outage | confirm derivable from public inputs, environment has no reviewers | `actor_not_owner` allowlist, `approval_environment_missing` for `_prd` keys and the webhook secret until #11923, `ref_refused`; residual: an owner PAT |

CPO sign-off: obtained at plan time (2026-11-02), advisory points carried: public-surface sweep beyond logs (the no-stream test covers summary, outputs, artifacts, issue body, annotations, argv logs and the dispatch-input echo), a dev rotation structurally unable to touch production state (Guard 5), the egress refusal is a tested path, redelivery guidance for the webhook gap, the issue text stays neutral about the gap window. The CPO's "grace window in the verifier" suggestion is tracked in #11922; the "deploy-only retry mode" suggestion was ruled out by CTO F9 (a third mutating path).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "build one new dispatch-only sibling workflow with mode=plan\|rotate and a per-key choice, and do not extend inngest-key-rotate.yml" | Files to Create: `key-rotate.yml`; `key` + `mode` inputs; no edit to `inngest-key-rotate.yml` | mapped |
| 2 | "Reuse its kr_tf private-file chokepoint and its gate-table pattern" | Phase 2 (source + override, Guard 4) | mapped |
| 3 | "Each rotation has to be a targeted replace of both the random_id and its doppler_secret, followed by a fleet redeploy" | Phase 2 gate table (A+B rows), redeploy job | mapped | *(Superseded by the Amendment 2026-11-02 for three keys: replace-both applies to the four `inngest_*` secrets only.)*
| 4 | "Dispatch only after the redaction coverage is confirmed" | Redaction coverage report, PR-F, runtime step `redaction_coverage_unconfirmed` | mapped |
| 5 | "tunnel_secret stays last, separate, and outside this route" | Overview (out of scope), runbook | mapped |
| 6 | "inngest_manual_trigger_secret_prd and _dev ... dev Inngest signing and event keys ... kb_drift_ingest_signing_key ... egress_audit_ingest_token ... github_webhook_secret" | Keys-in-scope table | mapped (egress plan-only per CTO F2) |
| 7 | "push trigger solely to register, every job gated on workflow_dispatch" | Phase 3 workflow, static test layer A | mapped |
| 8 | "mode=plan is read-only and needs no confirm; mode=rotate needs a typed confirm of the form ROTATE-<KEY>-<YYYY-MM-DD>" | Guard job `kk_chk_confirm` | mapped |
| 9 | "a guard job with the refusal ladder (no related run in flight, run_attempt 1, quiet_window attestation)" | Guard 3 | mapped |
| 10 | "ALL Terraform output goes to a private file ... the new workflow needs a test asserting no terraform stream reaches a log" | Guard 2, suite layer C | mapped |
| 11 | "_dev keys are the shakedown choice; kb_drift avoid 03:00 UTC cron" | Dispatch order in runbook; F5 window guard | mapped |
| 12 | "add a runbook section (no SSH fallback) and an ADR addendum pointing at ADR-307" | Files to Create `key-rotation.md` and a new ADR; Files to Edit ADR-307 (pointer) | mapped (the CTO ruled G4: a new ADR with a pointer in ADR-307, because ADR-307's title would become false if it carried a non-Inngest, no-converge route) |
| 13 | "update workflow parity tests (terraform-target-parity) as needed; run test suites ONE AT A TIME" | Phase 4, Verification order | mapped |
| 14 | "verify and report whether the redaction filter covers the plan lines" | Redaction coverage report | mapped |
| 15 | "The PR body must say that nothing was dispatched and that every rotate needs the owner's typed go. Use \"Ref #11294\" and \"Ref #10205\" only" | Phase 6 PR body | mapped |
| 16 | "the PR must NOT be armed or merged by the pipeline" | Phase 6, readiness row in `decision-challenges.md` | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `.github/workflows/key-rotate.yml`, `scripts/key-rotate.sh` | "build one new dispatch-only sibling workflow" (ask 1) | asked |
| `apps/web-platform/infra/key-rotate-workflow.test.sh` | "the new workflow needs a test asserting no terraform stream reaches a log" (ask 10) | asked |
| `knowledge-base/engineering/operations/runbooks/key-rotation.md` | "add a runbook section (no SSH fallback)" (ask 12) | asked |
| New ADR plus the ADR-307 pointer | "an ADR addendum pointing at ADR-307" (ask 12) | asked (form changed by CTO G4) |
| `terraform-target-parity.test.ts` edits | "update workflow parity tests (terraform-target-parity) as needed" (ask 13) | asked |
| Runtime step `redaction_coverage_unconfirmed` | "Dispatch only after the redaction coverage is confirmed" (ask 4) | asked |
| PR-F (redaction filter fix) | "verify and report whether the redaction filter covers the plan lines" (ask 14) | CTO-ruled (F8a): verification found a live leak; a separate PR that merges first |
| PR-0 (trio-census `@allow`) | "followed by a fleet redeploy" (ask 3) | CTO-ruled (F7): the redeploy job names the deploy-channel trio, which the ratchet census refuses without a merge-base `@allow` |
| Registrations (`infra-validation.yml` paths, `test-affected-paths.sh`, `web-hosts-fanout-parity.test.sh` operand 8, sentinel baselines) | "update workflow parity tests ... as needed" (ask 13) | inferred - justification: each is a repo sentinel that goes red or blind for a new workflow/script/suite (same set the 10540 route registered) |
| Issue #11920 (egress restart lever) | "egress_audit_ingest_token (egress-audit.tf; lossless via the _PREVIOUS scheme" (ask 6) | CTO-ruled (F2): the deferral needs a tracking issue (deferral rule); #11922 and #11923 follow from G5 and G6 |
| Guard rungs `actor_refused`, `authorization_stale` | "the authorization is the owner's fresh in-session go naming the exact command" (ask 8) | CTO-ruled (G6): the environment has no required reviewers, so the confirm is a fat-finger guard and these bound the residual |
| Guard rungs `owner_step_open`, `webhook_patch_not_ready` | "NOT to be automated by an agent without an owner ruling: document it as an owner step" (ask 6) | CTO-ruled (F4, G5) |
| Concurrency groups, lower-run-id rung, `web-1-swap` on redeploy | "no related run in flight" (ask 9) | CTO-ruled (G2) |
| Per-copy `absent` classification and the all-absent recovery path | "followed by a fleet redeploy" (ask 3) | CTO-ruled (G1): an interrupted delete-then-create must stay recoverable without SSH |
| `model.c4` `github -> doppler` edge sentence | "add a runbook section (no SSH fallback) and an ADR addendum" (ask 12) | inferred - justification: the C4 completeness mandate; the edge enumerates consumer workflows and their per-job credential split (architecture review) |
| Rungs `ref_refused`, `actor_not_owner`, `approval_environment_missing` | "the authorization is the owner's fresh in-session go naming the exact command" (ask 8) | CTO-ruled (H2, security review): the environment has no required reviewers and the confirm is derivable |
| Plan-field projection, `action_reason`/`after_unknown.value` gate clauses | "ALL Terraform output goes to a private file, never to logs, summaries or artifacts" (ask 10) | CTO-ruled (H1): the full plan JSON holds every root variable and the prior state |
| `precondition` subcommand and `redaction_ok` output | "Dispatch only after the redaction coverage is confirmed" (ask 4) | CTO-ruled (H3) |
| New ADR instead of an ADR-307 addendum | "an ADR addendum pointing at ADR-307" (ask 12) | CTO-ruled (G4) |
| Issues #11922, #11923 | "the GitHub App webhook-secret PATCH ... document it as an owner step" (ask 6) | CTO-ruled (G5, G6): deferral tracking |

### Split Assessment

- Subsystems touched: 5 - `.github/workflows`, `scripts`, `apps/web-platform/infra` (suite), `plugins/soleur/test`, `knowledge-base` - plus two prerequisite PRs on `tests/scripts` (PR-F, PR-0).
- Planned files: about 18 here (5 created including the new ADR and runbook, about 13 edited), 2 in PR-F, 2 in PR-0 | Estimated changed lines: about 2,200 in this PR (script about 750, suite about 1,000 after the test-design review, workflow about 300; edits small)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split - the two prerequisites (PR-F, PR-0) are separate PRs by CTO ruling; the workflow, script and suite stay ONE PR because the suite pins the workflow and the script against each other.

## Architecture Decision (ADR/C4)

### ADR

Create a NEW ADR through `soleur:architecture create` (CTO G4): "Key rotation for the non-tunnel secrets runs through a second dispatch-only route that sources the Inngest route and overrides it". The ordinal is provisional (the highest in this worktree is ADR-313; check `origin/main` and reserve the next free number at write time, then sweep this plan and `tasks.md` for the old number). Contents: F1 source-and-override coupling with its guards (Alternatives: extract a shared lib - rejected, edits a production route and its pinned suite; copy the chokepoint - rejected, duplicates security-critical code); F9 no converge or redeploy-only mode, recovery by a fresh `rotate` with the G1 absent-state paths; F2 egress plan-only with its flip evidence (#11920); G6 authorization posture stated plainly (the confirm string is a fat-finger guard, the environment has zero required reviewers, a PAT dispatch is indistinguishable from the owner's, #11923); the F3 rationale for redeploying on dev keys. Edit `ADR-307-inngest-key-rotation-route.md` by one pointer line and one `related:` entry only; its body is unchanged. The F7 `@allow` text belongs to PR-0's ADR-241 edit, not to this ADR.

### C4 views

All three model files were read for the decision (`model.c4`, `views.c4`, `spec.c4`), not a keyword `grep`. Checked and found already modeled: external human actor - the owner dispatching (`founder`, with the receipt-bound approval edges); external systems - GitHub Actions (`github`), Doppler (`doppler`), Terraform state, the web fleet through the deploy webhook (`github -> tunnel`), Hetzner (untouched by this route); containers/data stores - none new (the private files are runner-local and removed on exit); actor-to-surface access - unchanged (same Tier-B credentials, same environment). One edit IS required: the `github -> doppler` edge (the "Tier-B Terraform credentials (#8209, ADR-241 D2/D3)" edge in `model.c4`, about line 777) enumerates the consumer workflows and their per-job credential split, and commit `5b9f074775` (#10540) added the sentence for `inngest-key-rotate.yml`. Add the matching sentence for `key-rotate.yml`: its `apply` job is a loader consumer, its `guard` job holds no Doppler credential, its `redeploy` job holds the deploy webhook credentials only. (An earlier draft of this plan said #10540 changed no `.c4` file; that premise was false.) Then run `plugins/soleur/test/c4-count-parity.test.sh`, `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` (one at a time); if the parity gate reddens, update the embedded cardinality text in the same edit.

## Infrastructure (IaC)

### Terraform changes

None. No `.tf` file is edited and no resource is added: the route only plans/applies existing resources through the existing Tier-B apply credentials (`DOPPLER_TOKEN_TF` and the R2 backend pair from the `infra-credentials` loader, variables via `doppler run --name-transformer tf-var`). Provider pins unchanged. The egress `_PREVIOUS` secret is NOT declared here (CTO F2: it belongs to #11920's follow-up, declared in Terraform and rotated by `-replace`).

### Apply path

Path (b): `terraform apply` of a saved plan, with `-target` and `-replace` of exactly the chosen key's rows (the table), from a runner under `environment: infra-privileged`, under the `terraform-apply-web-platform-host` concurrency group. No host is replaced. Blast radius: one secret's Doppler copies change; running containers keep their baked environment until the fleet redeploy; the redeploy swaps containers canary-then-prod.

### Host fan-out

No `terraform_data` SSH provisioner is targeted (the gate refuses any `terraform_data.*` or `hcloud_*` address). The redeploy fans out through `track.sh` with the pinned `WEB_HOST_PRIVATE_IPS` (`10.0.1.10,10.0.1.11`), pinned by `web-hosts-fanout-parity.test.sh` operand 8 (new).

### Distinctness / drift safeguards

- A `_dev` key maps only to `_dev` addresses and `soleur/dev` copies; a test asserts no `_dev` key row references a `_prd` or prod-config address (a dev rotation is structurally unable to `-replace` production state).
- `lifecycle.ignore_changes=[value]` callouts: the four `inngest_*` secrets in `inngest.tf` carry it, so their rows MUST be `replace`; the three others do not and are replaced anyway (CTO: both, always). Derived from the HCL by the parity test.
- The premise "`-replace` on a `doppler_secret` with `ignore_changes=[value]` recreates it with the new value" is the unverified premise of ADR-307 item 2; the `value_unchanged` detector (before/after hashes) turns a no-op into a loud failure and the dev shakedown is the first test of it.
- State holds secret values (encrypted R2 backend); unchanged.

### Vendor-tier reality check

No new vendor or tier. Doppler, GitHub Actions and the deploy webhook are existing accounts.

## Technical Approach

### Architecture

```
guard (no environment, no Doppler credential; actions:read + contents:read)
       ref rung -> redaction sanity step (env -i, captured) -> refusal ladder -> writes nothing
       outputs: go, mode, key, run_apply, run_redeploy, guard_epoch, redaction_ok, verdict
  v
apply (environment infra-privileged; group terraform-apply-web-platform-host for rotate only, per-run group for plan)
       re-checks -> loader -> init -> value-silent pre-state (present|absent|unknown) -> plan -> projection -> union gate
       -> re-checks again -> write_started=true -> [rotate] apply -> post-state checks     outputs: write_started, verdict
  v   (rotate only)
redeploy (no environment; group web-1-swap)
       step 1 re-checks (no trio) -> step 2 track.sh canary-then-prod (trio in this step's env only, no GH_TOKEN) -> step 3 verdict
       outputs: verdict   (rotate_ok | rotated_redeploy_failed | owner_step_pending)
  v
notify (always, non-plan, redeploy != success; the ONLY job with issues:write)   files the one action-required issue
```

`scripts/key-rotate.sh` subcommands: `guard`, `precondition`, `apply`, `redeploy`, `notify`, `--print-contract` (credential-free and offline: it must print before any `jq`, `gh` or Doppler call, and the suite runs it under `env -i PATH=...`). It sources `scripts/inngest-key-rotate.sh` AT TOP LEVEL (BEFORE that `source`, under `GITHUB_ACTIONS=true`, refuse with exit 78 if any variable matching `^K[RK]_` is already set - the Tier-B loader exports a whole Doppler project and sourcing assigns `KR_*`, so the check must precede it; a `source` inside a function would make the sourced `declare -A` globals local; the source guard on the sourced file's last line stops its `main`) and sets only `set -uo pipefail`: no `set -e` (the sourced bodies end in `[[ ... ]] && ...` statements) and no `trap` (the sourced `kr_init` installs `trap kr_cleanup EXIT`, which removes the key-bearing temp files; a second EXIT trap would silently replace it). Order of the script: (1) fail-closed type check, `declare -F` for each function it calls (`kr_tf kr_init kr_tf_prepare kr_scrub kr_gate_rows kr_gate_targets kr_gate_replaces kr_gate_want kr_refuse kr_ok kr_inflight_check kr_chk_attempt kr_chk_quiet kr_summary kr_out kr_token_known kr_now kr_iso`), `declare -p` with an array flag and no readonly flag for `KR_GATE_TABLE KR_INFLIGHT_WORKFLOWS KR_VERDICT_TOKENS`, and a scalar check for `KR_GATE_JQ KR_CHANGED`; any miss is `internal_error`, exit 78, before any Terraform call; (2) assign `KR_GATE_TABLE`, `KR_INFLIGHT_WORKFLOWS` and `KR_VERDICT_TOKENS` WHOLESALE (the sourced token list carries about 20 tokens this route never emits, so appending would make "list equals emitted literals" unsatisfiable); (3) redefine BY THE SAME NAME `kr_refuse`, `kr_ok` (prefix `key-rotate verdict=`), `kr_print_contract` (header `key-rotate verdict-tokens`), `main`, `kr_chk_confirm`, `kr_stop_sentence`, `kr_post_write_stop`, `kr_file_issue`, `kr_verdict_recipe`, `kr_converge_cmd`, `kr_cmd_notify`, `kr_out` (an allowlist of output names `go mode key run_apply run_redeploy guard_epoch redaction_ok write_started verdict` with values matching `^[A-Za-z0-9_:.-]{0,64}$`, so a hash or copy state can never cross a step or job boundary) (these carry the Inngest and `converge` text; the sourced helpers `kr_post_write_failure`, `kr_require_first_attempt`, `kr_require_no_inflight_post` call them by name, so only same-name redefinition intercepts the callers); (4) define `kk_*` functions (windows, gate, copy state, stop sentence tables). No new test seam is introduced: the clock window uses the existing `KR_NOW`, which the sourced script already refuses under `GITHUB_ACTIONS=true`.

Gate table (`phase|key|address|flag|actions`, the sibling's format; `A` = random_id, `B` = doppler_secret), for example:

```
A|kb_drift_ingest_signing_key|random_id.kb_drift_ingest_signing_key|replace|delete,create
B|kb_drift_ingest_signing_key|doppler_secret.kb_drift_ingest_signing_key|replace|delete,create
B|kb_drift_ingest_signing_key|doppler_secret.kb_drift_ingest_signing_key_app_runtime|replace|delete,create
```

`kk_gate` and `kk_gate_plan` are COPIES of `kr_gate` and `kr_gate_plan` that take the unioned want JSON (`kr_gate_want A <key>` plus `kr_gate_want B <key>` through `jq -cs add`) for both evaluation and the refusal diagnostics, keep the `tfplan-<name>` naming, build the `-target`/`-replace` lists from `kr_gate_targets`/`kr_gate_replaces` of both phases, and evaluate `jq -e --argjson want ... "$KR_GATE_JQ"` (exact addresses, exact action arrays, exact change count). The expected row count per key is pinned in the suite from LITERALS independent of the table: 3 for kb_drift, 2 for every other key. Gate semantics (CTO H1; the A row's `before` comes from Terraform STATE, not Doppler): an A row accepts `["delete","create"]` always and a bare `["create"]` with `before == null` only when EVERY paired Doppler copy was `absent` at pre-state; a B row accepts `["delete","create"]` always and a bare create only when ITS copy was `absent`; each B row must also carry `action_reason == "replace_by_request"` and `after_unknown.value == true` (a pre-write proof that the `ignore_changes` premise holds; a bare-create B row needs only `after_unknown.value == true` plus pre-state `absent`); `replace_because_tainted` refuses `replace_not_requested`. The full `terraform show -json` holds every root variable (including the workplace-scope Doppler token variable) and the prior state, so the script projects ONLY `address, actions, action_reason, before==null, after_unknown.value` into a small private file (`umask 077`), deletes the full JSON and its stream file immediately, and fails closed (refuse `terraform_failed`) on an empty or failed projection; the field list is pinned in the suite. The binary plan stays until the EXIT trap and is the one the apply consumes. The `-replace` of an address absent from state is expected to plan a plain create and is UNVERIFIED until the dev shakedown (or a deliberately interrupted dev rehearsal) exercises it, which must happen before any `_prd` rotate. *(Superseded in part by the Amendment 2026-11-02: the expected row flags come from the HCL, so a `target` B row accepts `["update"]`, and review round 1 lets the A row of an in-place key accept a bare create when its `random_id` state entry was lost.)*

Copy state (`kk_copy_state project config name` prints `present <sha256>`, `absent` or `unknown`; value-silent: `DOPPLER_TOKEN="$DOPPLER_TOKEN_TF" doppler secrets get NAME --plain -p P -c C | sha256sum`, booleans and hashes never printed): `absent` only when the name listing (`doppler secrets --only-names`) succeeded, was non-empty and lacks the name; an empty or failed listing is `unknown` and refuses `copy_unreadable` (verified 2026-11-02: the sourced `kr_name_state` returns 2 on an empty listing, but it is Inngest-specific - fixed projects and `kr_secret_name` - so `kk_copy_state` mirrors its logic and does not call it); a present copy whose hash equals the empty-string hash (`KR_EMPTY_SHA`) is `unknown` too, in the pre-state, the post-state and plan mode; the listing match is anchored on whole names (a superset name such as `KB_DRIFT_INGEST_SIGNING_KEY_PREVIOUS` must read as absent); `doppler secrets --only-names` and `doppler secrets get --plain` were checked against the installed CLI help on 2026-11-02. `kk_copy_state` output is captured by `$(...)` only and is never printed. A mixed present/absent state across a key's copies refuses `partial_absent_state`.

### Refusal ladder (guard job; `mode=plan` reports each as a boolean and refuses on none)

In order: (0) `ref_refused` - `GITHUB_REF` must equal `refs/heads/main`, evaluated before any other rung produces output; (1) `inputs_invalid` - mode in `plan|rotate`, key in the seven names (re-validated in the script: API dispatch bypasses the choice list); (2) `actor_refused` - `github.actor` or `github.triggering_actor` empty or ending in the literal `[bot]` (quoted pattern, not a glob), and `actor_not_owner` - both must be in an exact-match, case-sensitive allowlist that is a committed constant in the script (seeded with the CODEOWNERS owner login, pinned in the suite; an owner PAT still passes - residual); both actors are recorded in the summary; (3) `rerun_refused` - `GITHUB_RUN_ATTEMPT == 1`; (4) `confirm_mismatch` - exact `ROTATE-<UPPER(key)>-<UTC date>` with the date read from `kr_now` (the single clock), the message stating the format (UTC date, key upper-cased) without echoing the expected string; (5) `quiet_window_missing`; (6) `egress_rotate_unsupported_no_vector_restart_lever` (key egress, mode rotate); (7) `approval_environment_missing` (mode rotate for `inngest_manual_trigger_secret_prd`, `kb_drift_ingest_signing_key` and `github_webhook_secret` - CTO H2: until #11923 binds the apply job to a reviewer-gated environment; lifted by a one-line change in that PR); (8) `webhook_patch_not_ready` and `owner_step_open` (key github, rotate: `webhook_patch_ready` must be true, the `owner_step_pending` label must exist, and no open action-required issue carrying that label and the exact title regex `^key-rotate github_webhook_secret owner_step_pending \(run [0-9]+\)$` may exist; a `rotated_redeploy_failed` issue never triggers this; a listing error or a truncated listing refuses); (9) `kb_drift_cron_window` and `kb_drift_walker_in_flight` (key kb_drift only; CTO G3: refuse when the interval from now to now plus the remaining apply and redeploy budget intersects [03:00, 03:30] UTC, including the midnight wrap; fails closed on a query error); (10) `run_in_flight` / `run_list_unreadable` over `apply-web-platform-infra.yml apply-deploy-pipeline-fix.yml web-platform-release.yml inngest-key-rotate.yml inngest-link-flip.yml cutover-inngest.yml deploy-inngest-image.yml` (sourced helper, statuses `in_progress queued waiting`; the new rung adds `pending` and `requested`, and the residual that the sourced helper does not poll `pending` is recorded), plus a refuse-only `kk` rung counting `key-rotate.yml` runs with a LOWER run id in `queued|waiting|pending|in_progress` (fail closed). `key-rotate.yml` is deliberately NOT in the sourced list: that helper counts later runs too and would make an earlier run's apply re-check refuse a run behind it. A static suite row asserts every workflow named in the in-flight list and `kb-drift-walker.yml` exists under `.github/workflows/` (a rename would otherwise become a permanent `run_list_unreadable`).

The redaction sanity step (`bash scripts/key-rotate.sh precondition`) runs in the `guard` job after the ref rung (CTO H3): `env -i PATH HOME LC_ALL=C`, output captured to a file, only a fixed verdict and label booleans printed; it runs `bash tests/scripts/test-tf-redact-random-ids.sh` and requires the labels for the tainted, deposed and drift shapes; a failure refuses `redaction_coverage_unconfirmed`; `redaction_ok` is a guard output and `apply` runs only if it is `true`.

First act of the `apply` job (re-checked because the guard's facts age): attempt, in-flight, the lower-run-id rung, the kb_drift rungs again (remaining budget from that point), and `authorization_stale` - the UTC date (from `kr_now`) must still equal the confirm date and the guard-to-apply gap (`guard_epoch`) must be at most 60 minutes. The same set (in-flight, lower-run-id, kb_drift, `authorization_stale`) runs ONCE MORE immediately before `terraform apply`, as the last read before the write (the init and two plans between the first act and the write take up to about 35 minutes, and `web-platform-release.yml` is not serialized against this route); only then does the script write `write_started=true` to the job outputs. First act of the `redeploy` job: attempt, in-flight, the lower-run-id rung and the kb_drift rungs. The environment has no required reviewers, so no approval wait is modelled; the bound exists because a future reviewer gate (#11923) would introduce one. *(Superseded in part by the Amendment of review rounds 1 and 2 (2026-11-03): the redeploy re-check never refuses on staleness, the kb window or `quiet_window` (R1; it polls the transient rungs, and in redeploy mode runs of `web-1-swap` member workflows are not blockers, UNVERIFIED live); the apply step adds a pre-write time budget (R3, `authorization_stale`) and every Terraform stream file is deleted as soon as its exit code is read.)*

Concurrency (CTO G2): workflow-level `concurrency: group: inngest-key-rotate, cancel-in-progress: false` for `workflow_dispatch` (the literal shared with the sibling gives whole-run mutual exclusion in both directions without editing it; the registering `push` run gets a distinct group by `github.event_name` so it can never cancel a pending dispatch); `terraform-apply-web-platform-host` on the `apply` job for `mode=rotate` only, via an expression that falls back to a per-run group for `mode=plan` (the R2 backend has `use_lockfile = false`, so this group is the sole Terraform serializer, and a rehearsal must not supersede a merge-triggered infra apply); `web-1-swap` on the `redeploy` job (the lock `web-platform-release.yml` holds on its deploy job). A push-triggered sibling run joining the shared group can replace our pending dispatch: fail-safe, nothing mutates; documented in the runbook.

### Failure semantics (CTO F9, G1)

A refusal before any write prints one fixed verdict and writes nothing. After the apply the script classifies EVERY copy best-effort (`present-unchanged`, `present-changed`, `absent`, `unknown`; after any non-zero apply too), retries the post-state read up to 3 times 20 seconds apart before declaring `value_unchanged` (Doppler read-after-write lag), and ends with one verdict by this precedence: `post_hash_unreadable` > `partial_absent_state`/absent > `value_unchanged` (any copy unchanged) > `copies_differ`. Issues are filed ONLY by the `notify` job (the only job holding `issues: write`), never by `apply` or `redeploy`; `apply` and `redeploy` print the stop sentence and `::error::` and exit non-zero. There is no `converge` and no redeploy-only mode; the recovery is a fresh `rotate` of the same key under a fresh typed confirm (it mints another value, harmless for all in-scope keys, and roll-forward is the only direction: the previous value is not retained). Every stop sentence states three facts from this table:

| Verdict | Doppler | Terraform state | Running containers | Next safe action |
|---|---|---|---|---|
| `apply_failed` | per-copy classification printed | possibly partial (a replace may have destroyed and not created) | old | fresh `rotate`; if any copy is `absent` it is urgent: a container restart now starts without the secret |
| `post_hash_unreadable` | unknown | new | old | fresh `rotate`; the value is unknown, not "unchanged" |
| `value_unchanged` | OLD | new `random_id` | old | stop and read ADR item "ignore_changes premise" before re-dispatching: a repeat means the premise is false |
| `copies_differ` (kb_drift) | both present, unequal | new | old | fresh `rotate` outside the cron window |
| `partial_absent_state` | some copies present, some absent | partial | old | URGENT, not auto-repaired: do not restart anything; run the recovery `rotate` now; issue filed |
| `rotated_redeploy_failed` | new | new | old, or a MIXED fleet if the canary swapped and prod did not | fresh `rotate` (kb_drift: the next 03:00 UTC walker run 401s until a redeploy lands; manual trigger prd: `soleur:trigger-cron` gets 401; dev keys: none) |
| `owner_step_pending` | new | new | new | the single owner action |

Restart-while-absent consequence per key (named in the issue): manual trigger - 503 on `/api/internal/*` (`readInternalBearerSecret` returns null); webhook - 500 on every delivery; kb_drift - 500 on ingest. On the G1 absent path the redeploy leg is mandatory and prints that the old value survives only in running containers. For `github_webhook_secret`: after a failed redeploy the issue says not to update the GitHub App webhook secret yet and gives the re-dispatch inputs; after a good redeploy the verdict is `owner_step_pending` (job fails with `::error::`, one `action-required` issue with the dedicated label names the single remaining action and the redelivery steps). Issue titles are `key-rotate <key> <token> (run <id>)`, de-duplicated on (key, token, run) with a later event in the same run added as a comment; on `rotate_ok` for a key the script comments on and closes that key's open `key-rotate` issues (never the `owner_step_pending` ones, which the owner closes after the update). The issue body is neutral about the gap window (public), and when the `redeploy` job's `verdict` output is missing (cancelled, killed) the text is the neutral "check the run; do not update the GitHub App webhook secret until you have read the verdict". The job fails with `::error::`, and is never green, on every verdict except `rotate_ok` and `plan_ok`. The `notify` job treats a write as happened only when the `apply` job exported `write_started=true`, or the `apply` job was cancelled or killed (a missing value on a cancelled or failed apply means "write may have happened": fail toward filing); a pre-write refusal (`rerun_refused`, `authorization_stale`, `credential_absent`, a gate refusal, `copy_unreadable`, a rejected environment) files nothing. The redefined `kr_file_issue` re-lists after the create call to confirm the issue exists and, on failure or a missing label or token, prints `::error::key-rotate verdict=issue_unfiled` and returns non-zero. Matching of existing issues uses the exact title regex `^key-rotate <key> <token> \(run [0-9]+\)$` plus the label, with a limit of 1000 and a refusal when the listing is truncated; the verdict embedded in any issue text passes `kr_token_known` first.

Verdict tokens (fixed, assigned wholesale; `--print-contract` lists exactly these 35): `guard_ok ref_refused inputs_invalid actor_refused actor_not_owner rerun_refused confirm_mismatch quiet_window_missing egress_rotate_unsupported_no_vector_restart_lever approval_environment_missing webhook_patch_not_ready owner_step_open kb_drift_cron_window kb_drift_walker_in_flight run_in_flight run_list_unreadable redaction_coverage_unconfirmed credential_absent authorization_stale copy_unreadable partial_absent_state plan_ok plan_gate_refused replace_not_requested terraform_failed apply_failed post_hash_unreadable value_unchanged copies_differ rotated_redeploy_failed owner_step_pending issue_unfiled rotate_ok job_cancelled internal_error`. The suite pins set equality with the verdict literals the script can emit, and a token-coverage table: every token is produced by at least one scenario or sits on a literal exemption list (including tokens only the sourced code emits, such as `rerun_refused` and `credential_absent`).

### Workflow shape (`key-rotate.yml`)

- `name: Key Rotate`; `run-name: key-rotate ${{ inputs.mode }} ${{ inputs.key }}` (must not begin with `inngest-key-rotate`; `inngest-link-flip.sh` Guard 3 keys on `^inngest-key-rotate plan`).
- `on`: `workflow_dispatch` with inputs `mode` (choice plan, rotate), `key` (choice, seven names), `confirm` (string, optional), `quiet_window` (boolean, default false), `webhook_patch_ready` (boolean, default false); no `reason` input. `push` on `main` with `paths: ['.github/workflows/key-rotate.yml']` solely to register; every job `if: github.event_name == 'workflow_dispatch'`.
- `permissions: contents: read`; pinned action SHAs identical to the sibling's; inputs reach shell only through `env:`; no expression inside any `run:` body; no `continue-on-error`; no `upload-artifact`; checkout with `persist-credentials: false`.
- `guard` job: no environment, no Doppler credential, `GH_TOKEN` only where the run-list reads need it (never in the redaction step's env); steps: checkout, the ref rung, `precondition` (the redaction sanity step, see above), the refusal ladder. Outputs listed in the diagram.
- `apply` job: `needs: guard`, `if` requires `go`, `run_apply` and `redaction_ok == 'true'`; steps: checkout, Terraform setup, the loader, the script (`apply`). The job never names the trio, holds no deploy webhook secret and no write-scoped `GH_TOKEN` (read-only `actions: read` for the in-flight reads).
- `redeploy` job: no environment; three steps: (1) re-checks (no trio in env); (2) `track.sh` - the trio (`WEBHOOK_DEPLOY_SECRET`, `CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET`) appears only in this step's `env:`, with no `GH_TOKEN` and no Doppler token; (3) verdict step (no trio), exports `verdict` on every path. No `DOPPLER_TOKEN_TF`, no Terraform. `WEB_HOST_PRIVATE_IPS: "10.0.1.10,10.0.1.11"` job env, as the sibling. The trio separation is text-level only (the census): the Terraform job can read the trio through `prd_terraform` until #9294. *(Superseded in part by the Amendment of review rounds 1 and 2: the re-checks step is a read-only poll of at most 480 s inside its 10-minute timeout; the redeploy job holds four steps (2 + 10 + 85 + 5 = 102 min) and is enrolled in the `web-1-swap` group.)*
- `notify` job: `permissions: issues: write` and `GH_TOKEN` here only; also closes a key's earlier open `key-rotate` issues on `rotate_ok` (never the `owner_step_pending` ones); `if: always()`. *(Superseded in part by the Amendment of review rounds 1 and 2: notify also closes a key's earlier issues on `owner_step_pending` (never the `owner_step_pending` ones), only issues whose title run number is lower than the current run, and a notify re-run is quiet when the identical issue is open (R4).)*
- Timeouts come from a small BUDGET TABLE in the script holding only the values that differ from the sibling (`KK_GUARD_S`, `KK_APPLY_STEP_S = KR_TF_INIT_S + KR_TF_PLAN_S + KR_TF_APPLY_S + KR_STEP_SLACK_S`, reuse of `KR_REDEPLOY_*`) and pinned in the suite as plain literals so raising a `timeout-minutes` breaks the build: guard 15 min; apply step 40 min, job 50 min; redeploy step 85 min, job 95 min; notify 15 min. The G3 window constants derive from these. *(Superseded by the Amendment of review rounds 1 and 2: the redeploy job is 105 min, not 95, and the kb window budget includes the 10-minute re-checks step: 8100 s, first unsafe start about 00:45 UTC.)*

## Implementation Phases

Phase ordering is RED-first (`cq-write-failing-tests-before`): the suite's behaviour rows and mutation rows are written before the script they test.

### Phase 0 - prerequisite PRs (own branches, own worktrees, NOT armed or merged by the pipeline)

- **PR-F** (`fix(ci): redact random_* ids in tainted, deposed and drift plan blocks`; `Ref #11294`): branch off `main`. RED first: add synthesized rows to `tests/scripts/test-tf-redact-random-ids.sh`, each with a stable LABEL the dispatch-time precondition can grep for (`tainted-must-be-replaced`, `deposed-will-be-destroyed`, `drift-has-changed`, plus replaced-as-requested, destroyed, created), asserting id/b64_std/b64_url/hex/dec redacted on both sides of `->`; regression rows (a hetzner `[id=12345]` untouched, line count unchanged); a live detector row on the raw input; and stuck-state rows (an unterminated block with no `    }` closer, end-of-input mid-block, a block followed by a later diagnostic that must stay readable) because the widened block-start applies to every Terraform job. Then change the block-start in `tests/scripts/lib/tf-redact-random-ids.sh` to any plan comment line naming a `random_*` address (address followed by a space), ending at the existing `    }`. Run that suite, then the shard holding `terraform-target-parity.test.ts` (one at a time; the shard run is unverified until CI). Independent of this feature it closes a live leak; audit existing public apply-run logs for tainted or deposed blocks (read-only `gh run view --log`, count only) and report any hit.
- **PR-0** (`chore(census): reserve @allow rows for the key-rotate workflow`; `Ref #11294`): opened AFTER Phase 3, because the key list is derived from the census emitter's output on the finished branch (`bash tests/scripts/test-trio-baseline-census.sh --emit-baseline`), not guessed. Touches only `tests/scripts/trio-baseline.tsv` and ADR-241: one `@allow` per exact `(file, NAME)` key emitted for `.github/workflows/key-rotate.yml` (x3) and for the suite only if emitted; ADR-241 `Allow:` lines in the 1088-1093 shape (max-expiry 2026-11-30, `Ruled by CTO agent, 2026-11-02`). This PR then spends them: delete each `@allow` and add the matching `tier-a` row in the same diff, after PR-0 merges and this branch syncs `main`.

### Phase 1 - RED: the suite (`apps/web-platform/infra/key-rotate-workflow.test.sh`)

Layers, sized to this route. The A, B and C rows are RED-first (they need only the design); the D mutation anchors are text of a script that does not exist yet and land in Phase 2. Conventions and cost, from the test-design review: every oracle is a LITERAL in the suite (the ~20 function names and variable types, the seven `(project, config, name)` copy triples, the budget minutes 15/50/95, the row counts 3 and 2, the `ignore_changes` key set, the projected field list), never derived from the script under test; every date and window read goes through `kr_now` (one clock, so the 01:00/02:50/03:31 rows and the midnight-wrap row are deterministic); the YAML is parsed ONCE to JSON and queried with `jq`; the stub bin directory is built once and `cp -a` per scenario; mutation trees are symlinked, not copied (`scripts/` is about 18 MB); `KR_SLEEP` is the retry sleep (a literal `sleep 20` would burn 40-60 s per row); the suite gets an honest non-default weight row in `scripts/suite-durations.tsv` (the sibling takes about 94 s for 475 rows; expect 60-120 s here and a larger line count than first estimated). Each guard scenario is written ONCE as `scenario(script_path, workflow_path)` and run twice: against the real files (expect "stops") and against a mutated COPY made by a landing-checked edit (exactly-once anchor, `bash -n`, the edit lands inside the target function's line range); stub-input variants are NOT counted as mutations. Each refusal row asserts the verdict token AND the rc (a syntax-broken mutant exits 2 or 127 and must not read as caught); the pristine copy passes every scenario (instrument control) and an unmodelled stub call exits 64 with the refusal log required empty. Plan mode's boolean report is the vacuity control: the base input has every boolean true and each refusal row flips exactly one.

- **A. Static workflow**: dispatch-only (`push` has only the path filter and its own concurrency group; every job `if` is EVALUATED for `workflow_dispatch` against a (mode x guard outputs x job results) matrix, using an expression evaluator copied from the sibling suite with a provenance comment, not substring-matched); inputs and types (no `reason`); run-name not matching `^inngest-key-rotate`; pinned action SHAs; inputs only via `env:`; no expression in any `run:`; permissions per job (exact; `issues: write` on `notify` only); checkout `persist-credentials: false`; no `continue-on-error`; the Terraform check is scoped to PARSED `run:` bodies with a command-position regex (`terraform` followed by init, plan, apply, show, refresh, destroy, import) and is a closed set (every code line containing `terraform` equals a reviewed literal, with bypass-shape control rows `command terraform`, `$TF plan`, `env terraform`) plus no `actions/upload-artifact`, with a positive row proving the `hashicorp/setup-terraform` `uses:` and `TERRAFORM_VERSION` are present; the redaction `precondition` step is in `guard` after the ref rung and before the ladder, and `apply` requires `redaction_ok`; the trio appears in exactly one step's `env:` of exactly the `redeploy` job (the `track.sh` step, with no `GH_TOKEN`), asserted structurally; job matrix and `needs`; concurrency groups per job and per event (dispatch group `inngest-key-rotate`, push group distinct, Terraform group only for rotate, `web-1-swap` on redeploy); timeouts as literals.
- **B. Static script**: type-checked symbol list; top-level `source`; the pre-source `^K[RK]_` refusal; no `set -e`; no `trap` in `key-rotate.sh`; exactly one Terraform call site (`kr_tf`); table addresses parsed from the script; the verdict-token list EQUALS the literals emitted (35) and the token-coverage table; override takes effect (no captured stream, argv log or issue body contains `inngest-key-rotate` or `converge` text on ANY refusal or post-write path, including attempt 2 and an in-flight run inside `apply`; prefix `key-rotate verdict=`; the `inngest-key-rotate.XXXXXX` temp prefix pinned per CTO F1); a sha256 over the EXTRACTED SOURCE TEXT (by function range, not `declare -f`, which prints differently across bash versions) of the sourced functions the script calls, including their transitive callees (`kr_init`, `kr_cleanup`, `kr_post_write_failure`, the `kr_gate_*` family); the `kr_out` allowlist (a name or value outside it never reaches `$GITHUB_OUTPUT`); `bash scripts/key-rotate.sh --print-contract` under `env -i PATH=/usr/bin:/bin` exits 0 within a bounded time, prints the header and exactly 35 tokens.
- **C. Behaviour against stubs** (`gh`, `doppler`, `terraform`, `ssh-keygen`, `track.sh`; strict argv). Stub fidelity: `terraform` derives plan actions from argv and from a LITERAL `ignore_changes` set (the four `inngest_*` secrets) - a `-replace` of a `random_id` alone gives `no-op` for those and `update` for the others; one scrubbed structural plan-JSON fixture from a minimal real module whose `terraform_version`/`format_version` is compared to the workflow's pinned version (staleness is loud); `doppler secrets --only-names` prints the real table format and a superset-name listing must read `absent`; a successful listing with a failing `get` (empty output) classifies `unknown` (pipefail mutant); `gh run list` models `pending`/`requested`; `gh issue create` logs the BODY (copied at create time, not the deleted file) and the argv logs (`gh.log`, `doppler.log`, `tf.log`) join the scanned streams; `gh issue list --label owner_step_pending`. Rows: every refusal-ladder rung (each a distinct verdict, nothing written) including `ref_refused`, the bot actor (a login ending in `t` must NOT be refused, `x[bot]` must be, an empty actor must be), `actor_not_owner`, `approval_environment_missing` for the three keys and not for the dev keys, `owner_step_open` (and that a `rotated_redeploy_failed` issue does NOT trigger it), the lower-run-id rung, `authorization_stale` (date rolled, gap over 60 minutes); per-subcommand `GITHUB_RUN_ATTEMPT` (guard, apply and redeploy, the `:-1` default, a `1*` glob); the confirm mutants (glob suffix, `nocasematch`, trailing newline); plan mode for all seven keys including egress; rotate for the six rotatable keys through apply, post-state and (stubbed) redeploy; the egress refusal; `webhook_patch_not_ready`; kb_drift boundary table (last accepted and first refused second, 03:30 inclusive/exclusive, midnight wrap start 23:50, `<` versus `<=`, walker in flight, query error refused, re-checked at the guard, at the start of `apply`, immediately before the apply and at `redeploy`); gate refusals from the pinned counts; the H1 paths (all copies absent proceeds with a mandatory redeploy; mixed state `partial_absent_state`; empty or failed listing `copy_unreadable`; A and B bare-create variants; `replace_because_tainted`; a B row without `after_unknown.value == true`; a failed or empty projection); `value_unchanged` with its retry (unchanged on reads 1 and 2, changed on read 3 must PASS; a mutant with retries cut to 1 must fail); `copies_differ`; `post_hash_unreadable`; an apply that fails after the destroy half; redeploy failure after a good apply (`rotated_redeploy_failed`, non-zero exit, issue text per key, mixed-fleet sentence, nothing green); `owner_step_pending` (non-zero exit, one issue, only after a good redeploy); the notify decision table (`write_started` true, absent on a failed apply, absent on a cancelled apply, pre-write refusal files nothing, a skipped apply is not a write); `issue_unfiled` (create succeeds but the re-list shows no match; missing label); the temp dir is absent after a normal exit and after SIGTERM, and a killed-run directory is mode 0700. **No-stream test (P1)**: the stub `terraform` prints synthesized key-shaped strings (a 43-char base64url `id`, a 64-hex `hex`, a `signkey-` string, the sha256 of the stub secret, a 44-char standard-base64 string containing `+` and `/`, and a token-shaped variable value) on stdout AND stderr of every subcommand; every stream of every scenario is scanned INSIDE `run_script` (stdout, stderr, `$GITHUB_STEP_SUMMARY`, `$GITHUB_OUTPUT`, the issue body copy, annotations, the argv logs), and the number of scans must EQUAL the number of `run_script` calls; the control run with the private-file redirect removed (copy of the script) must show every sentinel class.
- **D. Mutations**: the Guard Contract rows, as `scenario()` runs against mutated copies (symlinked tree), one mutant per guard clause, with the overrides covered by a loop that deletes each of the 11 same-name redefinitions once; plus harness rows.

### Phase 2 - GREEN: `scripts/key-rotate.sh`

Implement per Technical Approach. Read every copy's state before (rotate) and after; refuse `copy_unreadable` before any write when a copy is `unknown` (plan mode reports the same boolean, so the rehearsal proves `DOPPLER_TOKEN_TF` can read `soleur/dev` and `prd_kb_drift_walker`, which is unverified until the first plan dispatch). Every printed line passes through `kr_scrub`; no value is read into a variable that is later echoed; the copy hashes live in the shell only for the equality compare.

### Phase 3 - `.github/workflows/key-rotate.yml`

As specified in Workflow shape. Header comment states: dispatch-only, a production act, the authorization is the owner's fresh in-session go naming the exact command, the confirm string is a fat-finger guard and not an authorization, the repository is public.

### Phase 4 - parity and registrations (run each sentinel, register per its output)

- `plugins/soleur/test/terraform-target-parity.test.ts`: add `KEY_ROTATE_WORKFLOW` constant (existsSync-guarded) and a `key-rotate (#11294)` describe: every literal `-target` in the YAML is in the allowlist (expected: none literal); the script's table addresses exist as `random_id`/`doppler_secret` resources in `apps/web-platform/infra/*.tf`, never `hcloud_*`/`terraform_data`; per HCL (every file in the root), every resource, output or `templatefile` expression that references a table `random_id` is itself in the table for that key (closure: a future third copy, or a `terraform_data` dependent, turns the guard red; the kb_drift two-copy rule); every table row is `replace`; `_dev` keys reference only `_dev` addresses and `dev` configs; the copies table's `project/config/name` equal the HCL's. Raise `TEST_FLOOR` by exactly the added tests and add the ledger comment line.
- `.github/workflows/infra-validation.yml`: add `.github/workflows/key-rotate.yml`, `scripts/key-rotate.sh` to the suite's trigger paths with the same explanatory comment shape.
- `scripts/lib/test-affected-paths.sh`: add the workflow (runtime read by the parity suite) and the script (argv-bearer sweep list) entries, AND the reverse edge: an edit to `scripts/inngest-key-rotate.sh` selects `key-rotate-workflow.test.sh` (the new script sources it).
- `apps/web-platform/infra/web-hosts-fanout-parity.test.sh`: operand 8 (`key-rotate.yml`, x1, the redeploy job env), mirroring operand 7.
- `knowledge-base/engineering/architecture/diagrams/model.c4`: the `github -> doppler` edge sentence for `key-rotate.yml` (see C4 views).
- `scripts/suite-durations.tsv` / `scripts/suite-shard-legs.tsv`: an honest weight row for the new suite (non-default milliseconds).
- Sentinels to run and register only as their output demands: `tests/scripts/test-infra-privileged-tier-census.sh`, `tests/scripts/test-trio-baseline-census.sh` (expected red until PR-0 merges), `scripts/lint-orphan-test-suites.sh`, `scripts/guard-vacuity-floor.test.sh` (born floor-bearing, as the sibling), `.claude/hooks/grep-q-pipe-guard.test.sh`, `plugins/soleur/test/fixture-relative-assert.baseline.txt`, `scripts/ci-pr-affected-audit.accept.tsv`, `scripts/suite-shard-legs.tsv`/`scripts/suite-durations.tsv`, `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md` (census row).

### Phase 5 - documentation and tracking

- Create `knowledge-base/engineering/operations/runbooks/key-rotation.md` (no SSH anywhere): what the route is; the per-key table with the consumer-and-pickup column; dispatch order (dev shakedown first: manual trigger dev, then signing/event dev, then kb_drift outside the G3 start window, manual trigger prd, github webhook last in a quiet window); the plan rehearsal command (a plan dispatch runs under `infra-privileged` and needs no confirm); the rotate command shape with the typed confirm described as a fat-finger guard; how to read the verdict (`gh run view <id> --log | grep 'key-rotate verdict='`); the read-only signature-failure probes for the gap windows (the Better Stack query `scripts/betterstack-query.sh --since 1h --grep "HMAC verification failed"` for the kb-drift route and `--grep "signature verification failed"` for the webhook route; pull-only until #11928 lands); the preconditions per key (#11923 for the `_prd` keys and the webhook secret; the dev shakedown first and the unverified `-replace`-of-an-absent-address premise exercised by a deliberately interrupted dev rehearsal before any `_prd` rotate); no reminder arming or cohort tagging during a prd manual-trigger rotation; the per-verdict state table and recovery (fresh rotate, no converge, roll-forward only, the absent-state urgency); the egress refusal and #11920; the GitHub webhook owner step (update the GitHub App webhook secret with the new value of `GITHUB_APP_WEBHOOK_SECRET` per `github-app-provisioning.md` Step 4; the App private key is needed; then redeliver failed deliveries from the App's advanced settings; close the `owner_step_pending` issue; an agent never does this without an owner ruling); the residuals (push-triggered sibling run can replace a pending dispatch, a PAT dispatch is indistinguishable from the owner's, #11923); and `tunnel_secret` out of scope. Add a pointer line to `inngest-server.md`'s rotation section.
- Create the ADR through `soleur:architecture create` and add the one pointer line and `related:` entry to ADR-307 (see Architecture Decision).
- Re-verify the owner-step command block of `github-app-provisioning.md` Step 4 against the current Doppler layout BEFORE the first webhook rotate and correct it in this PR if stale: the block reads `GITHUB_APP_ID` from `soleur`/`prd`, but `github-app.tf` carries `removed {}` blocks for `github_app_id` and `github_app_private_key` and `ci-deploy.sh` reads the App key from project `soleur-github-app`; the corrected block names only projects and configs that exist.
- Create the dedicated label for `owner_step_pending` issues (`gh label create`, work-phase write to repository labels only).
- `gh issue comment` on #9294 adding `key-rotate.yml` to the trio-consumer migration list (CTO F7 follow-up).
- Issues #11920, #11922, #11923 already filed (deferral tracking).

### Phase 6 - verification and PR

Run, ONE at a time (host is low on memory; CI is the authority): `bash tests/scripts/test-tf-redact-random-ids.sh`; `bash apps/web-platform/infra/key-rotate-workflow.test.sh`; `bash apps/web-platform/infra/inngest-key-rotate-workflow.test.sh` (must be unchanged and green: the sourced script is untouched); `bash apps/web-platform/infra/web-hosts-fanout-parity.test.sh`; `bun test plugins/soleur/test/terraform-target-parity.test.ts`; `bash plugins/soleur/test/c4-count-parity.test.sh`; `shellcheck scripts/key-rotate.sh`; `python3 scripts/lint-guard-contract.py` on this plan; the census suites. Then review, QA and compound per the pipeline. PR body: the two prerequisite PRs first (PR-F and PR-0, merge order and the red census check until both merge and the branch syncs `main`), **"Nothing was dispatched"**, **"Every rotate needs the owner's own typed go"**, the redaction coverage report, `Ref #11294`, `Ref #10205`, no `Closes`. The pipeline does not arm or merge any of the three PRs.

## Files to Create

- `.github/workflows/key-rotate.yml` - the dispatch-only workflow.
- `scripts/key-rotate.sh` - orchestration body (sources `scripts/inngest-key-rotate.sh`).
- `apps/web-platform/infra/key-rotate-workflow.test.sh` - static, behavioural and mutation suite.
- `knowledge-base/engineering/operations/runbooks/key-rotation.md` - runbook (no SSH fallback).
- `knowledge-base/engineering/architecture/decisions/ADR-314-<slug>.md` - new ADR (ordinal provisional; reserved through `soleur:architecture create`).
- (PR-F, separate branch) rows in `tests/scripts/test-tf-redact-random-ids.sh`.

## Files to Edit

- `knowledge-base/engineering/architecture/decisions/ADR-307-inngest-key-rotation-route.md` - one pointer line and one `related:` entry only.
- `knowledge-base/engineering/architecture/diagrams/model.c4` - the `github -> doppler` edge sentence for `key-rotate.yml`.
- `plugins/soleur/test/terraform-target-parity.test.ts` - key-rotate describe, `TEST_FLOOR`.
- `.github/workflows/infra-validation.yml` - trigger paths (the two open code-review issues naming this file, #8735 and #7942, concern notify-main-failure and mutation-battery naming; acknowledged, not folded).
- `scripts/lib/test-affected-paths.sh` - the workflow and script entries plus the reverse edge (a sibling-script edit selects the new suite).
- `apps/web-platform/infra/web-hosts-fanout-parity.test.sh` - operand 8.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` - one pointer line.
- `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md` - census row (if the tier census demands it).
- Sentinel baselines named in Phase 4, only where their output requires (`scripts/guard-vacuity-floor.test.sh`, `.claude/hooks/grep-q-pipe-guard.test.sh`, `plugins/soleur/test/fixture-relative-assert.baseline.txt`, `scripts/ci-pr-affected-audit.accept.tsv`, `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv`).
- (PR-F) `tests/scripts/lib/tf-redact-random-ids.sh`. (PR-0) `tests/scripts/trio-baseline.tsv`, `knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md`.
- NOT edited: `.github/workflows/inngest-key-rotate.yml`, `scripts/inngest-key-rotate.sh`, any `.tf` file, `apply-web-platform-infra.yml`.

## Open Code-Review Overlap

Two open `code-review` issues name a file this plan edits: #8735 (`infra-validation` notify-main-failure misses cancelled jobs) and #7942 (two mutation batteries named `*.mutation.sh` run in no gate), both through `.github/workflows/infra-validation.yml`. **Acknowledge**: the plan adds two path lines to a trigger list and touches neither concern; both stay open. No open code-review issue names any other planned file.

## Observability

```yaml
liveness_signal:
  what: "every dispatch ends in exactly one fixed `key-rotate verdict=<token>` line and a step-summary line; a write followed by a failed or cancelled job files one action-required issue"
  cadence: "per dispatch (the route is dispatch-only)"
  alert_target: "GitHub failed-run notification to the dispatching owner, plus the action-required issue"
  configured_in: ".github/workflows/key-rotate.yml (notify job) and scripts/key-rotate.sh (the redefined kr_file_issue and kr_cmd_notify)"

error_reporting:
  destination: "GitHub Actions error annotations and the action-required issue (a dispatch-only CI route, not a server surface; no Sentry project applies)"
  fail_loud: "`::error::key-rotate verdict=<token> ...` and a non-zero job conclusion; owner_step_pending and rotated_redeploy_failed are deliberate failures"

failure_modes:
  - mode: "a Terraform stream reaches a public log"
    detection: "the suite's no-stream test scans every captured stream with synthesized key-shaped sentinels and a control run; the workflow has no terraform command and no artifact upload (workflow run log, enforced by the suite)"
    alert_route: "CI red on the PR (infra-validation) before the route can ever be dispatched"
  - mode: "apply succeeded but a copy did not change (the ignore_changes premise fails)"
    detection: "the pre-write plan proof (action_reason replace_by_request, after_unknown.value) and the pre/post value-silent hashes; verdict value_unchanged in the workflow run log (`::error::key-rotate verdict=value_unchanged`)"
    alert_route: "failed job in the workflow run log plus the action-required issue filed by notify"
  - mode: "redeploy did not confirm after a good apply"
    detection: "track.sh exit non-zero; verdict rotated_redeploy_failed in the workflow run log"
    alert_route: "failed job plus action-required issue (GitHub issue tracker) naming the per-key degradation and the re-dispatch inputs"
  - mode: "a job cancelled or killed after the apply leaves no stop sentence"
    detection: "notify job reads the apply job result and its write_started output (workflow run log)"
    alert_route: "action-required issue (GitHub issue tracker) titled with the run id; issue_unfiled is a loud error if the filing itself fails"
  - mode: "an interrupted apply leaves a copy absent (delete-then-create)"
    detection: "the post-state classification (absent) on the same run in the workflow run log, or the pre-state on the next dispatch"
    alert_route: "action-required issue (GitHub issue tracker) marked urgent; the recovery sentence says a container restart now starts without the secret"
  - mode: "kb_drift signer/verifier mismatch after a half-finished rotation"
    detection: "the route logs and captures a Sentry event (feature kb-drift-ingest, op signature) on every 401 (pino + Sentry, apps/web-platform/app/api/internal/kb-drift-ingest/route.ts); the walker workflow run log shows HTTP 401; the stop sentence states the 03:00 UTC deadline"
    alert_route: "action-required issue (GitHub issue tracker); the Sentry event is pull-only (read-only Better Stack query in the runbook) until an alert rule exists (#11928); this does not page anyone"
  - mode: "the GitHub App webhook-secret gap stays open after owner_step_pending"
    detection: "Sentry event (feature github-webhook, op signature) on every rejected delivery, pino logs; the open owner_step_pending issue"
    alert_route: "the open action-required issue and the runbook probe; pull-only until #11928 adds alert rules"

logs:
  where: "GitHub Actions job logs (verdict and boolean lines only; Terraform streams are private files in a 0700 temp dir removed on exit)"
  retention: "90 days (repository setting, read 2026-10-29 in the CLO determination record)"

discoverability_test:
  command: bash scripts/key-rotate.sh --print-contract
  expected_output: verdict-tokens
```

## Encryption Posture

```yaml
at_rest:
  - store: "runner-local temp directory holding the private Terraform plan, plan JSON and stream files (RUNNER_TEMP, mode 0700)"
    mechanism: plaintext-exception
    evidence: "scripts/inngest-key-rotate.sh kr_init (mktemp -d, chmod 700) and kr_cleanup (rm -rf on EXIT) via the sourced chokepoint"
    defends_against: "other users on the shared runner VM reading the files while the job runs"
    does_not_defend: "a compromised step in the same job; a runner image snapshot taken mid-run; the files hold key bytes (the full plan JSON also holds every root variable and the prior state until it is deleted right after the field projection) until the EXIT trap removes them"
    disclosed_as: not-publicly-claimed
    live_verification: "unavailable:ephemeral GitHub-hosted runner, destroyed after the job"
in_transit:
  - connection: "runner -> Terraform R2 backend, Doppler API, deploy webhook behind Cloudflare Access"
    enforced_at: "unchanged existing connections: apps/web-platform/infra backend config; .github/actions/dispatch-web-redeploy/track.sh"
    tls: "HTTPS (TLS 1.2+ as the existing providers negotiate)"
    cert_verification: on
    does_not_defend: "a compromised runner holding the in-memory credentials"
    disclosed_as: not-publicly-claimed
exception:
  justification: "the files are ephemeral on a single-use runner, removed on exit, never printed, never uploaded; the alternative (a Terraform stream to stdout) is the leak this route exists to avoid"
  tracking_issue: "#11294"
  reevaluate_when: "the route moves to self-hosted runners, or a Terraform sensitive-output redaction makes plan JSON safe to keep"
  expires_on: 2027-01-31
```

## Task Design

```yaml
tasks:
  - task: key-rotate (dispatch-only rotation route, jobs guard / apply / redeploy / notify)
    trigger: "workflow_dispatch by the owner with a typed confirm (rotate) or none (plan); the push trigger only registers the workflow"
    services: "reads GitHub Actions run lists and Doppler (value-silent hashes); writes Terraform state (R2), Doppler secrets of the chosen key, the web fleet through the deploy webhook, one action-required issue on failure"
    next: "nothing"
    human_reentry: "the owner re-dispatches rotate under a fresh typed confirm, or stops by cancelling the run; the issue carries the exact inputs; for github_webhook_secret the owner step is the GitHub App webhook-secret update"
    dedupe: "action-required issue de-duplicated on (key, token, run id) with later events added as comments; a lower-run-id rung and the shared `inngest-key-rotate` workflow group stop a double dispatch; `owner_step_open` stops a second github rotate while the owner step is open; run_attempt must be 1 so a GitHub re-run cannot repeat a write; the in-flight refusal over related workflows; a pre/post hash proves a value actually changed before the redeploy is reported"
    source_dedupe: "not a ticket source"
```

## Guard Contract

Every mutation row is a `scenario(script_path, workflow_path)` run against a mutated COPY in a minimal copied tree (Phase 1): the scenario that the guard stops must proceed on the copy.

### Guard 1 - Gate table (exact plan allowlist)

**Property.** A rotation's saved plan changes exactly the chosen key's `random_id` and every `doppler_secret` copy of it, with exactly the expected action arrays and replace reasons, and nothing else.

**Assembly.** Every construction site of the plan flows from ONE table (the `KR_GATE_TABLE` assignment in `scripts/key-rotate.sh`): the `-target` list (`kr_gate_targets`), the `-replace` list (`kr_gate_replaces`), and the jq allowlist applied to the projected plan (`kr_gate_want` for phases A and B unioned by `jq -cs add`, evaluated with `KR_GATE_JQ` plus the `action_reason`/`after_unknown.value` clauses). The plan applied is the one the gate evaluated (`tfplan-<name>`); `apply` takes no other argument. The chokepoint is `kk_gate_plan`/`kk_gate`; there is no second plan call site. The expected row count per key is pinned from literals in the suite (3 for kb_drift, 2 otherwise), independent of the table. The stub plan shapes (wrong action, missing second copy, extra address, empty plan) are BEHAVIOUR rows in layer C; the rows below are mutations of the gate itself.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | One `gate_true` bypass mutant (the gate always returns success): every layer-C gate refusal (wrong action, one kb_drift copy only, extra address, empty plan) must flip from "refused" to "applied" | RED on the real script, proceeds on the mutant |
| 2 | Per-clause mutants of the jq program: drop the exact-action clause; drop the change-count clause; drop the address-set equality clause; drop the `mode == "managed"` clause; drop the `before == null` recovery condition | each flips its own scenario |
| 3 | Drop the `action_reason == replace_by_request` clause (a `replace_because_tainted` leftover) and the `after_unknown.value == true` clause (a B row that replaces without a changed value) | each flips its scenario |
| 4 | A bare `["create"]` with `before` null on the A row while a paired copy was `present` at pre-state; the same shape with EVERY paired copy `absent` is accepted (the must-PASS arm); a B bare create with its own copy `present` is refused | RED / proceeds / RED |
| 5 | Delete the `-replace` flag generation from `kk_gate_plan` (for an `ignore_changes` key the stub plan shows `no-op`, for the others `update`) | RED |
| 6 | Weaken the projection: keep `before`/`after` values or a field outside the pinned list | RED (projected-field pin and the no-stream scan) |

**Harness rows.** (a) A stub plan JSON that is not valid JSON, and an empty projection, must yield a refusal, not a pass. (b) A must-PASS plan that is NOT the canonical fixture: the same rows in the reverse order plus an unrelated `no-op` address.

**Anchor.** The table and `terraform-target-parity.test.ts` live in this repository, so one diff can edit both: the guard proves consistency, not integrity. Integrity rests on `infra-privileged` being main-only (it has no required reviewers, #11923) plus the HCL-derived closure in Guard 5, which a table edit alone cannot change.

### Guard 2 - No Terraform stream reaches a log

**Property.** No byte of any Terraform stdout/stderr, plan, plan JSON or temp path reaches a job log, step summary, job output, artifact, issue body or annotation.

**Assembly.** One Terraform chokepoint (`kr_tf`, sourced) redirects both streams to files under the 0700 temp dir and unsets `TF_LOG*`; the workflow YAML has no `terraform` command in any `run:` body, no artifact upload and no redirect of a Terraform file to the summary; every printed line passes `kr_scrub`. Sinks enumerated: stdout, stderr, `$GITHUB_STEP_SUMMARY`, `$GITHUB_OUTPUT`, the issue body file, `::error::`/`::warning::` lines, artifacts, and the temp tree left after exit.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | In a copy of the script, replace the `kr_tf` redirect with a pass-through | RED (the sentinel appears in a captured stream) |
| 2 | Add a bare `terraform plan` call to the script | RED (single-call-site assertion) |
| 3 | Add `run: terraform plan` (and separately `uses: actions/upload-artifact`) to the workflow | RED |
| 4 | `kk` issue filing includes the plan or an unscrubbed detail in the issue body | RED (sentinel scan over the issue body file) |
| 5 | The scanner is pointed at an empty capture directory | RED (floor on the number of scanned streams) |

**Harness rows.** (a) The control run with the redirect removed MUST show the sentinel (the scanner can see). (b) A must-PASS run that prints a 40-hex git SHA and a short `[id=12345]` hetzner id is not flagged, and the stub emits key-shaped strings on BOTH streams of every subcommand.

**Anchor.** Sentinels are synthesized in the suite, independent of `kr_scrub`'s patterns. What GitHub renders cannot be proven by a test; the redaction precondition (ordering and sanity step) and the PR-F battery cover the existing jobs, and this route has no stream to redact at all.

### Guard 3 - Refusal ladder precedes every write

**Property.** No Terraform apply, Doppler write or redeploy runs unless the dispatch is on `main`, from an owner-allowlisted non-bot actor, a first attempt, with an exact typed confirm for this UTC date and this key, a quiet-window attestation, a valid key, no related run in flight and the per-key preconditions all hold, re-checked at the start of the write jobs and again immediately before the apply.

**Assembly.** The guard job computes `go`; the `apply` job's `if` requires `go == 'true'`, `run_apply == 'true'` and `redaction_ok == 'true'`; the `redeploy` job requires a successful apply and `run_redeploy`; both re-run their checks as their first act, and `apply` re-runs them once more immediately before `terraform apply`; `apply` and `redeploy` are the only jobs holding write credentials. Chokepoints: `kk_cmd_guard` for admission, `kr_tf apply` as the only apply, `bash "$KR_TRACK"` as the only redeploy. The ladder rungs are exercised as 7-plus scenarios on the real script (one per in-flight workflow member, one per rung), not by mutating the sourced loop.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `kk_chk_confirm` (wrong date, wrong key, lower-case key, a confirm for another key, a glob suffix, `nocasematch`, a trailing newline) | RED (each refused scenario now proceeds) |
| 2 | Remove the `GITHUB_RUN_ATTEMPT == 1` check separately in `guard`, `apply` and `redeploy`; default `:-1`; a `1*` glob | RED per subcommand |
| 3 | Remove the `quiet_window` check; remove the `[bot]` check; remove `actor_not_owner`; use an unquoted `*[bot]` glob | RED (a login ending in `t` must not be refused, `x[bot]` and an empty actor must be) |
| 4 | Remove `ref_refused` (a dispatch from a non-main ref) | RED, and no other rung may print before it |
| 5 | `egress_audit_ingest_token` with `mode=rotate`; `approval_environment_missing` for the three keys (and not for the dev keys); `webhook_patch_not_ready` | RED; delete each refusal and its scenario proceeds |
| 6 | The script's own dispatch: run with an unknown subcommand and with an empty mode | RED (usage error, exit non-zero; never "0 checked" and green) |
| 7 | REORDER: move `kr_tf apply` before the gate, and separately move the final pre-apply re-check after the apply; observe INSIDE the window with a stub apply that records whether the gate and the re-check had run | RED |
| 8 | Delete the `authorization_stale` check (confirm date rolled, gap over 60 minutes); delete the kb_drift re-check at `apply` start, immediately before the apply, and at `redeploy` start (a stub `gh run list` that returns a release run only on its second call must leave the stub apply uncalled) | RED |
| 9 | Delete the lower-run-id rung; delete `owner_step_open` (a github rotate with an open `owner_step_pending` issue); delete the label-exists check | RED |
| 10 | kb_drift boundaries: flip `<` to `<=` at the 03:30 edge, drop the midnight wrap, drop `walker_in_flight` at the guard | RED (boundary table with literal seconds) |

**Harness rows.** (a) A stubbed `gh` that fails `run list` must yield `run_list_unreadable` (a harness that reads an error as "none in flight" is vacuous). (b) A must-PASS input that is not the canonical: a confirm typed for a different key on the same date is refused, the correct confirm is accepted exactly as typed, and a `rotated_redeploy_failed` issue does NOT trigger `owner_step_open`.

**Anchor.** The typed confirm and `quiet_window` are not the authorization (the environment has no required reviewers; #11923), and no test can assert the owner's go. The workflow header, the runbook and the new ADR say so; agents never dispatch `rotate`.

### Guard 4 - Reuse integrity (sourced symbols, overrides, leaked text)

**Property.** `scripts/key-rotate.sh` fails closed unless every sourced symbol it depends on exists with the expected type and is writable, no Inngest-route text reaches any output, the sourced cleanup trap is not replaced, and a semantic change to the sourced bodies forces a deliberate update here.

**Assembly.** The symbol list in the script (`declare -F` for functions, `declare -p` array-and-not-readonly for the three arrays, scalar for the two jq programs) is the single list; the suite derives the same list from the script and checks the sibling still defines each symbol with that type; the override points are `KR_GATE_TABLE`, `KR_INFLIGHT_WORKFLOWS`, `KR_VERDICT_TOKENS` and the same-name redefinitions (`kr_refuse`, `kr_ok`, `kr_print_contract`, `main`, `kr_chk_confirm`, `kr_stop_sentence`, `kr_post_write_stop`, `kr_file_issue`, `kr_verdict_recipe`, `kr_converge_cmd`, `kr_cmd_notify`); a sha256 over the extracted source text (by function range) of the sourced functions the script calls and their transitive callees is pinned in the suite; the function-name and type list is a LITERAL in the suite, not derived from the script.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Rename `kr_tf` in a copy of the sourced script | RED (`internal_error`, exit 78, before any Terraform call) |
| 2 | Make `KR_GATE_TABLE` a scalar, or `readonly`, in the copy | RED |
| 3 | Delete the `kr_refuse` override; separately delete the `kr_file_issue` override | RED (an output line or issue body carries `inngest-key-rotate` or `converge`) |
| 4 | Add `trap 'x' EXIT` or `set -e` to `key-rotate.sh` | RED (static rows; the temp-dir-gone behaviour row also reds) |
| 5 | Edit one sourced function body (semantics change, including the temp prefix inside `kr_init`) in the copy | RED (sha256 pin; the `inngest-key-rotate.XXXXXX` prefix is pinned inside it, CTO F1) |
| 6 | Delete each of the 11 same-name redefinitions once (a loop, not a sample) | RED (an output line, argv log or issue body carries `inngest-key-rotate` or `converge`) |

**Harness rows.** (a) A copy of the sourced script with an extra, unrelated function still PASSES the symbol check (the check is about named symbols). (b) Run against a decoy path for the sourced script: setup fails instead of passing.

**Anchor.** Both files live in this repository; integrity rests on the unchanged `inngest-key-rotate-workflow.test.sh` staying green on every PR, and on the reverse test-selection edge (a sibling edit selects the new suite).

### Guard 5 - Table-versus-HCL parity

**Property.** For every key, the table's rows equal the set of resources in the Terraform root that carry that key's value (the `random_id` and every resource, output or `templatefile` expression that references it), every row is `replace`, and a `_dev` key can name only dev addresses.

**Assembly.** `terraform-target-parity.test.ts` parses every `.tf` file in `apps/web-platform/infra/` (the whole root, not an inventory of three) for `resource "random_id"` and for every reference to it, plus each `doppler_secret`'s `project/config/name`, and compares to the table parsed from the script and to the copies table; every `random_id` in the root must be in this route's table, the sibling's table (`inngest_{signing,event}_key_{prd,dedicated}`) or an explicit out-of-scope list (`tunnel_secret`); the TypeScript parser and the shell parser read ONE shared table fixture so the two cannot disagree silently.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add a third `doppler_secret` (or a `terraform_data`/output) referencing `random_id.kb_drift_ingest_signing_key` in a fixture `.tf` | RED (closure) |
| 2 | Add a new `random_id` to the root that is in neither this table, the sibling's table, nor the literal out-of-scope list (`tunnel_secret`) | RED (every `random_id` in the root has a disposition) |
| 3 | Point a `_dev` key row at `soleur/prd` | RED |
| 4 | Table-only edit that renames an address | RED (address must exist in the HCL) |
| 5 | Flip a row's flag from `replace` to `target` | RED (every row is replace) |

**Harness rows.** (a) The parser run on an empty directory fails (floor on resources found). (b) A must-PASS fixture with extra unrelated resources and a prose comment mentioning a table address is not counted as a reference.

**Anchor.** One diff could edit the table and the HCL together; the HCL is the independent side for the closure rule, and the per-merge apply plus the drift detector would surface a table that no longer matches reality.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `.github/workflows/key-rotate.yml`, `scripts/key-rotate.sh`, `apps/web-platform/infra/key-rotate-workflow.test.sh` exist; `inngest-key-rotate.yml` and `scripts/inngest-key-rotate.sh` are byte-identical to `main` (`git diff origin/main -- <both>` is empty).
- [ ] The workflow's `on:` is `workflow_dispatch` plus a `push` with only the workflow's own path (its own concurrency group); every job `if` requires `workflow_dispatch`; `run-name` starts with `key-rotate`; no `reason` input; no `terraform` command in any parsed `run:` body and no `upload-artifact` (the `setup-terraform` `uses:` is present and expected).
- [ ] `key-rotate-workflow.test.sh` is green, including the no-stream test with its control run, every refusal rung, all seven keys in `plan`, the six rotatable keys in `rotate` (stubs), the egress rotate refusal, the redeploy-failure-after-apply row, the `owner_step_pending` rows, and the Guard 1-4 mutation rows (each mutation turns its scenario from "stops" to "proceeds").
- [ ] `terraform-target-parity.test.ts` is green with the Guard 5 describe and an exact `TEST_FLOOR` (`grep -cE '^\s*test\(' = floor`); `inngest-key-rotate-workflow.test.sh` and `web-hosts-fanout-parity.test.sh` (operand 8) are green.
- [ ] `bash scripts/key-rotate.sh --print-contract` prints `key-rotate verdict-tokens` and exactly the 35 tokens of the contract (set equality with the emitted literals); `shellcheck scripts/key-rotate.sh` is clean; the script contains no `set -e` and no `trap`.
- [ ] Runbook `key-rotation.md` exists with the per-key table, dispatch order, verdict recovery and the GitHub webhook owner step, and contains no SSH instruction (`grep -n 'ssh ' key-rotation.md` returns nothing); a new ADR records F1, F2, F9, G6 and the F3 rationale, and ADR-307 carries only the pointer line and `related:` entry; `model.c4` carries the `key-rotate.yml` sentence on the `github -> doppler` edge and `c4-count-parity.test.sh` is green.
- [ ] PR-F is open (unarmed) with its RED-first rows and the filter fix; PR-0 is open (unarmed) with `@allow` lines derived from the census emitter output; the PR body lists both, states the census check and the redaction-suite assertion are red until both merge and this branch syncs `main`, states **nothing was dispatched** and **every rotate needs the owner's own typed go**, and uses only `Ref #11294` and `Ref #10205`.
- [ ] #9294 carries a comment adding `key-rotate.yml` to the trio-consumer migration list; #11920, #11922 and #11923 exist; the `owner_step_pending` label exists.
- [ ] The suite carries a non-default weight row, every oracle is a literal (symbols, copy triples, budgets, counts, projected fields, `ignore_changes` set), and every date or window read goes through `kr_now`.
- [ ] The PR body calls the redaction precondition an ordering and sanity step (the safety weight is the no-stream design) and states the authorization residual (no required reviewers on `infra-privileged`, #11923).

### Post-merge (operator)

- [ ] None performed by an agent. The owner's dispatches (plan rehearsals, then one `rotate` per key under a fresh typed go, `inngest_manual_trigger_secret_dev` first) are the owner's decision and are not part of this PR's verification.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO agent (2026-11-02) ruled nineteen forks (F1-F9, G1-G7, H1-H3) recorded in `decision-challenges.md`: source-and-override reuse, egress plan-only, redeploy for dev keys, webhook ordering with a non-success conclusion, kb_drift windows and one-apply copies, the trio-census two-PR sequencing, the redaction-filter fix as a separate PR first, the runtime redaction sanity step (moved to the credential-free guard job), no converge mode, the absent-state recovery gate, the budget-aware kb_drift window, a new ADR, the committed owner-login allowlist with `approval_environment_missing` until #11923, and the projected-plan-fields rule. CPO advisory (single-user-incident threshold confirmed) is carried in User-Brand Impact. No Product/UX surface (no user-facing page or component), so no Product/UX gate; no legal, finance, marketing, sales, support or operations implication beyond the existing Tier-B credential model.

## Test Scenarios

- Given a dispatch with `mode=rotate`, `key=inngest_manual_trigger_secret_dev`, a confirm for another key, when the guard runs, then it refuses `confirm_mismatch` and no job with a write credential starts.
- Given the correct confirm but `GITHUB_RUN_ATTEMPT=2`, when `apply` runs, then it refuses `rerun_refused` before any Terraform call.
- Given `key=kb_drift_ingest_signing_key` at 02:50 UTC (test seam), when the guard runs, then it refuses `kb_drift_cron_window`; with a `kb-drift-walker.yml` run in progress at 04:00 UTC, `kb_drift_walker_in_flight`; with the run query failing, a refusal (fails closed).
- Given a stub plan that changes only one of the two kb_drift `doppler_secret` copies, when the gate runs, then `plan_gate_refused` and nothing is applied.
- Given a stub apply that leaves a copy's hash unchanged, when the post-check runs, then `value_unchanged`, a stop sentence, an issue and a non-zero exit, and no redeploy.
- Given a good apply and a failing `track.sh`, when the redeploy job ends, then `rotated_redeploy_failed`, non-zero exit, an issue naming the per-key degradation and the re-dispatch inputs; for `github_webhook_secret` the issue says not to update the GitHub App webhook secret yet.
- Given a good apply and a good redeploy for `github_webhook_secret`, then `owner_step_pending`, non-zero exit and one issue naming the single remaining action.
- Given a stub `terraform` that prints key-shaped strings on both streams, when any subcommand runs, then no captured stream or the temp tree after exit contains a sentinel; and the control run without the redirect does.
- Given `egress_audit_ingest_token`, `mode=plan` reports the gate rows and `plan_ok`; `mode=rotate` refuses with the fixed verdict.
- Given `mode=plan` for each key, then nothing is written, no confirm is needed, and `copy_unreadable` is reported if a copy cannot be read value-silently.
- Given the sourced script's `kr_tf` renamed in a copy, then `scripts/key-rotate.sh` exits 78 before any Terraform call.
- Given every copy `absent` (an interrupted earlier apply), when `rotate` runs, then the gate accepts the bare creates, the post-state is readable and non-empty, the redeploy leg runs and the output says the old value survives only in running containers; given a mixed state, then `partial_absent_state`; given an empty Doppler name listing, then `copy_unreadable`.
- Given a `github_webhook_secret` rotate while an `owner_step_pending` issue is open, then `owner_step_open`; while only a `rotated_redeploy_failed` issue is open, the rotate proceeds.
- Given a dispatch by a `[bot]` actor, then `actor_refused`; given the apply job starting after the UTC date rolled or more than 60 minutes after the guard, then `authorization_stale`.
- Given `kb_drift_ingest_signing_key` dispatched at 01:00 UTC (budget crosses 03:00), then `kb_drift_cron_window`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or filler-only fails `deepen-plan` Phase 4.6; this one is filled.
- The trio census is the sequencing trap: this PR cannot be green until PR-0 merges and the branch syncs `main`; the PR body says so, and the pipeline arms nothing.
- The redaction sanity step reads the suite on the dispatched ref: until PR-F merges and this branch syncs, it refuses `redaction_coverage_unconfirmed` (the label for the tainted shape is missing), by design.
- `-replace` of a `doppler_secret` with `ignore_changes=[value]` recreating the value is the unverified premise of ADR-307 item 2; the dev shakedown tests it first and `value_unchanged` is the detector.
- `DOPPLER_TOKEN_TF` reading `soleur/dev` and `prd_kb_drift_walker` is unverified until the first `mode=plan` dispatch (reported as `copy_unreadable` if not).
- Sharing the literal workflow group `inngest-key-rotate` gives whole-run mutual exclusion in both directions without editing the sibling; a push-triggered sibling run joining the group can replace a pending dispatch of ours (fail-safe: nothing mutates).
- `infra-privileged` has zero required reviewers (measured 2026-11-02): the typed confirm is derivable from public inputs, a PAT dispatch is indistinguishable from the owner's, and "agents never dispatch rotate" is policy. Disclosed residual, tracked in #11923.
- Terraform `-replace` is delete-then-create and the R2 backend has no state lock: an interrupted apply can leave copies absent; the G1 absent path and the Terraform apply group are the controls.
- The sourced script's `declare -A` globals are local if sourced inside a function; the sourced bodies end in `[[ ]] &&` statements (no `set -e`); the sourced `kr_init` owns the EXIT trap (no second trap).
- The GitHub webhook gap is real and accepted per the brief (single secret in the route); the verifier grace window (accept new and previous secret) needs an app code change and is tracked in #11922.
- The plan JSON is broader than one key: it carries every root variable (the workplace-scope Doppler token variable among them) and the prior state; only the projected gate fields survive past the projection.
- A `-replace` of an address absent from state is expected to plan a plain create and nothing here has observed it; the first dev rehearsal must exercise it before any `_prd` rotate.
- The trio separation is text-level only: the Terraform job can read the trio through `prd_terraform` until #9294 closes.
- Quoted Terraform output, key values and CLI streams never enter this plan, the PR body or any issue; fixtures are synthesized.
- The first `rotate` dispatch of any key is a production act; the plan, the PR and every agent step stop short of it.
