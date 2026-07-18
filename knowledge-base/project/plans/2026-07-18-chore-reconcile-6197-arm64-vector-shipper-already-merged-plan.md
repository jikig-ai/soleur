---
title: "chore(infra): reconcile #6197 — arm64 Vector journal→Better Stack shipper is ALREADY merged (PR #6209); no re-implementation warranted"
issue: 6197
type: reconciliation
change_class: infra
lane: cross-domain            # no spec.md exists for this branch → fail-closed default (TR2)
premise_status: STALE
brand_survival_threshold: none
requires_cpo_signoff: false
date: 2026-07-18
---

# Reconcile #6197 — arm64 Vector shipper is already merged; do NOT re-implement 🧭

> **Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed).** No
> `knowledge-base/project/specs/feat-one-shot-6197/spec.md` exists.

## Enhancement Summary

**Deepened on:** 2026-07-18 · **Mode:** targeted (reconciliation plan — no per-section fan-out).

This plan concludes there is **no code deliverable** (the premise is stale — #6197 is already
merged). A full 40-agent deepen fan-out on a no-op would burn budget without recall
(`hr-autonomous-loop-skill-api-budget-disclosure`), so the deepen pass ran the load-bearing parts:
the mandatory hard-gates and live attribution verification per the Quality Checks.

**Hard gates (all pass/skip):**
- Phase 4.6 User-Brand Impact — PRESENT, `threshold: none` + `threshold: none, reason:` scope-out bullet. PASS.
- Phase 4.7 Observability — plan is pure-docs (no production code/infra in Files-to-Edit). SKIP (correct).
- Phase 4.8 PAT-shaped variable halt — grep sweep returns NO MATCH. PASS.
- Phase 4.9 UI-wireframe halt — no UI-surface file. SKIP (correct).
- Phase 4.55 Downtime & Cutover — this plan performs no infra operation; the ADR-100 Phase-2 cutover is out of scope (operator-gated, blocked on #6178). No trigger for this plan's changes.

**Live attribution verification (per deepen Quality Checks — verified against `origin/main`):**
```
$ gh pr view 6209 --json state,mergeCommit
  state=MERGED  mergeCommit=c890464ce57a3cfe67ae36d8b9d39863bcfe0603
$ git merge-base --is-ancestor c890464ce origin/main   → yes (ancestor of main)
$ git show origin/main:apps/web-platform/infra/vector.tf | grep vector_sha256_arm64
  :22  vector_sha256_arm64 = "365bab73244780083eb95b3e42161a9179f23a0811ffa6180f613c3af06ed8e6"
$ git show origin/main:apps/web-platform/infra/inngest-betterstack-token.tf | grep -c 'doppler_secret" "inngest_betterstack_logs_token'  → 1
$ git show origin/main:.../ADR-100-....md | grep -c 'RESOLVED (#6197)'  → 1
$ gh issue view 6197 --json state  → OPEN   |   gh issue view 6178 --json state  → OPEN (blocker)
```

**Conclusion unchanged after deepen:** the implementation #6197 describes is fully present on
`origin/main`; the correct action is tracker reconciliation, not re-implementation. See the
decision-challenge at `knowledge-base/project/specs/feat-one-shot-6197/decision-challenges.md`.

## Premise Validation (Phase 0.6 — LOAD-BEARING)

**Verdict: the premise of issue #6197 is STALE. The implementation it describes is already
merged to `main` and reconciled in ADR-100. This plan does NOT plan against the stale premise
(per `hr-verify-repo-capability-claim-before-assert` and the Phase 0.6 gate) — it reconciles it.**

Checked (all against the current worktree tip / `origin/main`):

| Cited reference | Probe | Result |
| --- | --- | --- |
| PR #6209 "wire arm64 Vector journal→Better Stack shipper on the dedicated Inngest host" | `gh pr view 6209 --json state` | **MERGED** — commit `c890464ce` |
| Issue #6197 state | `gh issue view 6197 --json state` | **OPEN** — intentionally (PR #6209 used `Ref #6197`, **not** `Closes`) |
| Blocker #6178 (dedicated-host extraction) | `gh issue view 6178 --json state` | **OPEN** — the Phase-2 cutover this issue's re-eval trigger points at is still gated |
| ADR-100 status | `grep 'RESOLVED (#6197)' ADR-100…md` | ADR-100:399 — **"Phase-1 caveat — RESOLVED (#6197)"** |

**Why #6197 is still open despite the work being done:** PR #6209 deliberately shipped `Ref #6197`
(not `Closes`), because #6197 doubles as the `deferred-automation` **tracker** for the ADR-100
**Phase-2 cutover** (re-provision the arm64 `cax11` host at `10.0.1.40` so the latent `doppler_secret`
+ cloud-init Vector install actually take effect). That cutover is blocked on **#6178** and an
operator-signed-off maintenance window — it is NOT the code work the issue *body* describes, and it
cannot run in this session (`hr-menu-option-ack-not-prod-write-auth`, `hr-all-infrastructure-provisioning-servers`).

**Also stale: the word "Sentry" in the issue title/body.** Vector's shipper target pivoted
Sentry→Better Stack Logs in #4273/#5526. PR #6209 and ADR-100:400 already reconciled the "Sentry"
prose to "Better Stack Logs". There is no Sentry-shipping gap to build.

## Overview

Issue #6197 asks to "wire the arm64 Vector journal→Sentry shipper on the dedicated Inngest host"
because "the current Vector install path is x86_64-hardcoded" and "`BETTERSTACK_LOGS_TOKEN` must be
provisioned into the isolated `soleur-inngest` Doppler project."

**Every one of those line items is already implemented on `main`** (PR #6209, merged; touched again
non-regressively by the #6631 cleanup bundle). The x86_64 hardcode is gone — the install path is
arch-parameterized off `VECTOR_CLI_ARCH`. The arm64 SHA is pinned. The token resource exists and
its `TF_VAR` is declared. The boot-isolation self-check admits the token by name. CI tests assert
all of it. See the reconciliation table below for file+line evidence.

**Consequence for this pipeline: there is NO code deliverable.** Re-implementing would either be a
no-op or a duplicate/conflicting change — exactly the waste the premise-validation gate exists to
prevent. The correct output is **issue-tracker reconciliation**, not a code PR. This plan's
`## Recommended Action` is the deliverable; `/work` MUST NOT re-implement the Vector shipper.

## Research Reconciliation — Issue Claim vs. Codebase Reality

| #6197 claim | Reality on `main` (evidence) | Plan response |
| --- | --- | --- |
| "Vector's download URL in the bootstrap is pinned to an `x86_64-unknown-linux-musl` artifact" | `inngest-bootstrap.sh:733-748` — `VECTOR_CLI_ARCH` case map (`amd64→x86_64…`, `arm64→aarch64-unknown-linux-musl`); URL derives from `${vec_triple}`. `inngest-host.test.sh:155-161` asserts `aarch64-…` present AND `vector-x86_64-…` NOT hardcoded. | **Already done.** No change. |
| "needs a pinned **arm64 Vector SHA** captured locally" | `vector.tf:22` — `vector_sha256_arm64 = "365bab73…8e6"`; live-verified in PR #6209 test plan. | **Already done.** No change. |
| "a matching checksum override" | `inngest-host.tf:250` — `vector_sha256 = local.inngest_arch == "arm64" ? local.vector_sha256_arm64 : local.vector_sha256`, threaded to cloud-init `VECTOR_CLI_SHA256`. | **Already done.** No change. |
| "`BETTERSTACK_LOGS_TOKEN` must be provisioned into the isolated `soleur-inngest` Doppler project" | `inngest-betterstack-token.tf` — `doppler_secret.inngest_betterstack_logs_token` into `doppler_project.inngest` / `inngest_prd`. `variables.tf:359` declares the no-default `betterstack_logs_token` var. Boot self-check admits it: `cloud-init-inngest.yml:226,291`. | **Already done.** No change. |
| "The Vector systemd unit is **already** templated to `@@DOPPLER_PROJECT@@`, so no unit change needed" | Correct — confirmed; no unit edit in PR #6209. | **Confirmed.** No change. |
| Title: "journal→**Sentry** shipper" | Vector target is **Better Stack Logs** (Sentry→BS pivot #4273/#5526); ADR-100:400 reconciled the stale "Sentry" prose. | **Stale terminology.** No Sentry work exists. |
| "Re-evaluate before the Phase-2 cutover" | ADR-100 Phase-2 cutover is gated on **#6178** (OPEN) + operator maintenance window; the `doppler_secret` + host re-provision are **latent** until then. | **Out of scope for a code PR** — operator-gated, not in-session. |

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing. #6197 is operator-internal
  observability infrastructure on a DARK/inert arm64 Inngest host with no prod crons and no end-user
  data surface. The shipper code is already merged; this reconciliation touches no runtime.
- **If this leaks, the user's data is exposed via:** N/A. `BETTERSTACK_LOGS_TOKEN` is a write-only
  24-char log-ingest token (Better Stack source 2457081); shipped journald is PII-scrubbed by the
  Vector VRL. Already landed only in the isolated `soleur-inngest/prd` project.
- **Brand-survival threshold:** none.

> `threshold: none, reason: operator-internal observability reconciliation of an already-merged
> change on a DARK/inert arm64 host; no end-user data surface, no runtime edit, no new infra.`

## Recommended Action (the deliverable — NOT a code build)

**Primary recommendation: HALT the one-shot pipeline before `/work` re-implements.** The engineering
work is merged. The only honest, non-duplicative actions are issue-tracker hygiene + preserving the
Phase-2 re-eval trigger. None of these is a product-code change.

1. **Reconcile issue #6197's body** so it stops mis-representing the code as unbuilt. It should read
   as: *"Implementation merged in PR #6209 (arch-parameterized Vector install, arm64 SHA, isolated
   `BETTERSTACK_LOGS_TOKEN`); this issue remains open ONLY as the ADR-100 **Phase-2 cutover** tracker
   — re-provision `cax11`/`10.0.1.40` so the latent resources take effect. Blocked on #6178 + an
   operator maintenance window."* Keep the `deferred-automation` label; keep it OPEN
   (`hr-before-asserting-github-issue-status` — do not assert closed).
2. **Do NOT close #6197** and do NOT `Closes #6197` from any PR: the residual (Phase-2 cutover) is a
   real future operator event, correctly tracked here.
3. **Preserve the Phase-2 re-eval trigger** so it is not lost to human memory: the re-eval is already
   wired into ADR-100's Phase-2 cutover narrative and #6178; no new follow-through probe is warranted
   (the wiring is CI-asserted by `inngest-host.test.sh`; the *activation* is a maintenance-window
   event, not a time-based soak the sweeper can probe — matching PR #6209's soak-followthrough
   override justification).

**Decision-Challenge (headless):** this plan concludes the operator's implied direction ("build the
arm64 Vector shipper for #6197") should change to "reconcile the tracker; nothing to build." Per
ADR-084 / the plan-review headless arm, this is persisted to
`knowledge-base/project/specs/feat-one-shot-6197/decision-challenges.md` for `ship` to render into
the PR body and file as an `action-required` issue.

## Acceptance Criteria

### Verification (read-only — proves the premise is stale)
- [ ] `git grep -qF 'aarch64-unknown-linux-musl' apps/web-platform/infra/inngest-bootstrap.sh` returns 0 (present).
- [ ] `git grep -qE 'vector_sha256_arm64[[:space:]]*=[[:space:]]*"[0-9a-f]{64}"' apps/web-platform/infra/vector.tf` returns 0 (arm64 SHA pinned).
- [ ] `test -f apps/web-platform/infra/inngest-betterstack-token.tf` (token resource exists) AND `git grep -qF 'variable "betterstack_logs_token"' apps/web-platform/infra/variables.tf`.
- [ ] `git grep -qF 'vector-x86_64-unknown-linux-musl' apps/web-platform/infra/inngest-bootstrap.sh` returns non-zero (x86_64 NOT hardcoded).
- [ ] `bash apps/web-platform/infra/inngest-host.test.sh` passes on `main` (arch + isolation + SHA assertions green).
- [ ] `gh pr view 6209 --json state` == `MERGED`; ADR-100 contains `RESOLVED (#6197)`.

### Reconciliation (the only actions taken)
- [ ] Issue #6197 body reconciled to "implementation merged; open as Phase-2 cutover tracker" (see Recommended Action #1).
- [ ] #6197 remains OPEN with `deferred-automation` label; no `Closes #6197` is introduced.
- [ ] `decision-challenges.md` records the "already-done → reconcile, don't build" challenge for `ship`.

### Explicitly NOT in scope (do NOT do)
- [ ] No edit to `inngest-bootstrap.sh`, `vector.tf`, `vector.toml`, `inngest-host.tf`, `inngest-betterstack-token.tf`, `variables.tf`, `cloud-init-inngest.yml`, or ADR-100 — all already correct.
- [ ] No `terraform apply` / host re-provision (operator-gated Phase-2 cutover, blocked on #6178).

## Domain Review

**Domains relevant:** engineering (advisory only).

This is a reconciliation of a merged infra change — no new architecture decision, no UI, no
regulated-data surface. Full domain-leader spawns and the Product/UX gate are **not** applicable
(no UI-surface files; `## Files to Create` / `## Files to Edit` are empty for product code). CTO
lens: the correct engineering call on an already-merged issue is tracker hygiene + halt, not a
duplicate PR — consistent with `hr-autonomous-loop-skill-api-budget-disclosure` (do not burn a full
build/review/ship cycle on a no-op).

## Infrastructure (IaC)

None. No new server, secret, vendor, or persistent process is introduced — every IaC artifact
#6197 requires already exists on `main`. The latent `doppler_secret` + arm64 host re-provision are
future operator maintenance-window events under ADR-100 Phase-2, gated on #6178. (Phase 2.8 gate:
skipped — no new infra.)

## Observability

Skipped (Phase 2.9): no new code/infra surface. The arm64 Vector shipper's own observability wiring
was delivered and CI-asserted by PR #6209 (`inngest-host.test.sh`, `soleur-host-bootstrap-observability.test.sh`).

## Architecture Decision (ADR/C4)

None (Phase 2.10): ADR-100 was already amended by PR #6209 to record the Phase-1 Vector caveat as
RESOLVED and to add the inngest→Better Stack log-ship C4 edge. No new or diverging decision.

## Sharp Edges

- **Do not let `/work` "helpfully" re-add the arm64 Vector wiring.** Every line item is present on
  `main`; a re-add is at best a no-op and at worst a merge-conflicting duplicate. The plan's scope is
  reconciliation, not build. If `/work` finds nothing to change, that is the CORRECT outcome — emit
  the reconciliation + decision-challenge and stop; do not manufacture busywork
  (`hr-autonomous-loop-skill-api-budget-disclosure`).
- **Do not `Closes #6197`.** The issue is the Phase-2 cutover tracker; closing it drops the operator
  re-eval trigger. Reconcile the body; keep it OPEN (`hr-before-asserting-github-issue-status`).
- **A plan whose `## User-Brand Impact` section is empty, `TBD`, or omits the threshold will fail
  `deepen-plan` Phase 4.6.** This one is filled (threshold: none, with reason).
- **The "Sentry" in the issue title is stale.** Vector ships to Better Stack Logs (pivot #4273/#5526).
  Do not scaffold any Sentry-shipping path.
