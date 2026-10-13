# Decision challenges — feat-one-shot-zot-mirror-fail-closed

Persisted headless per ADR-084 / the plan-review classifier: these are **Taste / User-Challenge**
decisions that touch scope the operator asked for. They were **not** auto-applied. `ship` Phase 6
renders this into the PR body and files an `action-required` issue.

> **All three RESOLVED by the operator on 2026-07-30, at the start of `/work`** — before any
> implementation, since UC-1 and UC-2 change what Phases 2 and 5 build. Outcome: **UC-1 keep the probe
> cut**, **UC-2 full scope 5.1–5.4** (broader than the recommendation), **UC-3 single PR**. Each
> section's `Status:` records the decision and the reasoning that carried it. `ship` Phase 6 should
> render these as *decided*, not as open questions — no `action-required` issue is owed for them.

---

## UC-1 — Drop the new bridge `/v2/` probe from this PR?

**Class:** User-Challenge (cuts operator-requested scope — "fix the bridge").

**The operator's stated direction is the default.** The task said: *"Fix the bridge."*

**What three reviewers argued.** DHH, code-simplicity, and the CTO independently recommended cutting
the positive `/v2/` probe that replaces `nc -z`:

- Once the mirror is fail-closed, a dead stream already blocks the release — the probe buys **earlier
  attribution**, not the invariant. FR-B2 (dump the cloudflared log at the failing step) and FR-B1(1)
  (truthful cause text) deliver that attribution at the same place, with no new mechanism.
- It is the **only change in the plan with zero runner-side evidence**. The bridge was validated from
  the operator's laptop, not a GitHub runner (Premise Validation F2's stated limitation).
- It **composes into the gate**: a stricter bridge gate → `zot_bridge` failure → `degraded "bridge"` →
  release blocked. One false negative in an unvalidated probe blocks the release train that carries
  the `service_role` credential remediation.
- **Blast radius the plan initially missed:** `cf-tunnel-registry-bridge` is a **shared action with
  three consumers** (`reusable-release.yml`, `build-inngest-bootstrap-image.yml`,
  `build-inngest-config-bundle.yml`). The inngest workflow's mirror is *still* gated
  `if: steps.zot_bridge.outcome == 'success'` — the live #6416 defect — so making the bridge gate
  correctly stricter would convert a would-be `degraded` into a **skipped** step there, leaving
  `mirror_status` unset and its Slack line inert. That path would become *more* silent.
- Cutting it also largely **dissolves the two-PR split question** (UC-3).

**Counter-argument for keeping it.** `nc -z` is a genuine false gate — it reported success while the
path was dead, which is why the bridge step looked healthy in run 30468080168. Leaving it means the
bridge keeps mis-reporting for at least one more cycle.

**Recommendation:** cut from this PR; fix the false gate in a follow-up **together with** the
`build-inngest-bootstrap-image.yml` #6416 fix, once a real release has given runner-side evidence of
the probe shape.

**Status:** RESOLVED 2026-07-30 — operator elected **keep it cut** (the recommendation). The probe is
not in this PR; the `nc -z` false gate is folded into the Phase 8 tracker that also carries the live
`build-inngest-bootstrap-image.yml` #6416 defect (Deferred item 1) and the two sibling false `/v2/`
gates (Deferred item 2).

---

## UC-2 — Move the token-drift detector fix (FR-B3/FR-B4) to a follow-up PR?

**Class:** Taste (scope placement; the fix itself is agreed by all reviewers to be a real bug).

**Agreed by everyone:** `scripts/check-cloudflare-token-drift.sh` claims coverage it does not have.
Its enumeration regex `CF_API_TOKEN[A-Z0-9_]*` **cannot match** `REGISTRY_PUSH_ACCESS_TOKEN_*` — the
first case its own header cites — and `verify_value()` uses the `Bearer` API-token endpoint, which is
wrong for a client-id/secret pair. Nothing invokes the script at all. This is a bug fix, not a
feature; code-simplicity explicitly ruled it **not** YAGNI.

**The disagreement is only about which PR.** DHH: it is a bug fix to code merged **one day ago**
(#7067) whose triggering incident is already remediated; it shares nothing with "a release must not
ship an image prod cannot pull"; it is the single largest new surface in the plan, and a new
operational object that can go red at 3am. Title a follow-up *"finish #7067"*.

Against: the detector is the *only* thing standing between the next unpropagated rotation and a repeat
of this outage, and FR-A7(ii) makes that token release-blocking — so shipping the coupling without the
detection is arguably worse.

**Recommendation:** keep FR-B3 (the ~10-line regex + verify-arm fix) in this PR, since it is what makes
FR-A4's "run the drift detector" remedy real; move FR-B4's **release-preflight** arm to the follow-up
if the PR is getting large, but keep the `scheduled-terraform-drift.yml` step (a ~12-line addition to
an existing workflow).

**Status:** RESOLVED 2026-07-30 — operator elected **full scope (tasks 5.1–5.4)**, i.e. *more* than the
recommendation: FR-B3's regex + Access-service-token verify arm, its unit test, the
`scheduled-terraform-drift.yml` step, **and** the release-preflight arm. The reasoning that carried it
is the one the recommendation itself conceded: a twice-daily detector can be hours stale relative to
the release that trips over it, and FR-A7(ii) makes that credential release-blocking — so the
preflight is what turns a blocked release into a correctly-diagnosed one before the build spends its
minutes. DHH's "finish #7067" framing is recorded as the rejected alternative.

---

## UC-3 — Split gating from non-gating work into two PRs?

**Class:** User-Challenge (would move the task's headline deliverable, A, out of this PR).

**The CTO's argument.** Merging this branch edits `apps/web-platform/infra/ci-deploy.sh`, which matches
`on.push.paths: apps/web-platform/**` — so the merge is itself the **first-ever execution** of the new
gate. Recommendation: PR 1 = non-gating (FR-C, FR-B*, ADR/C4), whose own release exercises the
runner-side bridge for real; PR 2 = the gating change, after PR 1 proves it.

**Why this is weaker in plan v2 than it was in v1.** The change the split was mostly *about* — the
unvalidated bridge probe — is now surfaced as UC-1 rather than included. What remains gating is a
read-side `crane digest` assertion over a path already proven to work, plus a `needs.release.result`
conjunct. Both are low-variance.

**Hard constraint if elected:** FR-B1(2) — the `zot-registry-revert.md` correction — **must not** land
in the later PR. Shipping the gate first would leave the runbook instructing a recovery procedure that
now fails `image_pull_failed`.

**Recommendation:** decide at ship time. If UC-1 is accepted (probe cut), a single PR is defensible.

**Status:** RESOLVED 2026-07-30 — operator elected a **single PR**. UC-1 resolved as "cut", which is
the precondition the recommendation named: the remaining gating change is a read-side `crane digest`
over a path already proven to work plus a `needs.release.result` conjunct, both low-variance. The
hard constraint is satisfied by construction — FR-B1(2)'s `zot-registry-revert.md` correction ships
in the same PR as the gate.

---

## Note — what was NOT surfaced

The following were adjudicated and applied, not left open, because they are mechanical correctness
fixes rather than scope decisions: the assertion moving inside `zot_mirror` (3 reviewers converged,
with a concrete failure on the target incident); `needs.release.result` on `migrate`/`deploy` (the plan
had asserted a blocking mechanism that `always()` overrides); the `mirror_reason` output (the
alternative labelled an underivable state with a remedy pointing at the wrong system); dropping the
GHCR-side `crane digest`; and the widened truthfulness sweep. Reasoning is in the plan's Alternatives
Considered and Research Reconciliation tables.
