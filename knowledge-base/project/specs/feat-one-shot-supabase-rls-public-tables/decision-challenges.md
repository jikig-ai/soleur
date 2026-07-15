# Decision Challenges — feat-one-shot-supabase-rls-public-tables

Source: `soleur:plan-review` 7-agent panel, 2026-07-15, against
`knowledge-base/project/plans/2026-07-15-security-soleur-dev-inngest-rls-lockdown-plan.md`.

Routing per ADR-084 / `decision-principles.md`: **Mechanical** findings were auto-applied to the plan
(v1 → v2). The items below are **Taste** / **User-Challenge** — they argue the operator's stated scope
should change, so they are surfaced here rather than silently applied. This session is headless, so
`ship` Phase 6 should render these into the PR body and file an `action-required` issue.

---

## DC-1 — Build #3366 now instead of escalating it
**Class:** User-Challenge · **Raised by:** CTO (devex), reinforced by CPO condition 2

**The operator's stated direction:** the task said *"Propose a CI gate asserting 'no public table without RLS'… If deferring that gate, follow `wg-when-deferring-a-capability-create-a` (create a tracking issue)."* Deferral was explicitly permitted. The plan defers by escalating the pre-existing #3366.

**The challenge:** escalation is not prevention.
- #3366 has been open since 2026-05-06 — **51 days of silence**, among **149** open `deferred-scope-out` issues (oldest: 79 days).
- Its own re-evaluation trigger has now fired **three times** (2026-05-03, 2026-06-22, 2026-07-12). Each firing produced a comment. *"A trigger that fires three times and changes nothing is not a trigger."*
- The plan already builds **~80%** of #3366's machinery: `apply-inngest-rls.yml:200` already queries `/v1/projects/{ref}/advisors/security` and parses `rls_disabled_in_public` with `jq`, and the plan copies that block into the dev workflow. It then files an issue asking someone to build the durable 20%.
- Had #3366 existed, it would have caught this on **2026-07-11** — before a human noticed on 07-12.
- Marginal cost of asserting `rls_disabled_in_public == 0` and failing: ~5 lines in a workflow already being written.

**Cost of accepting:** ~1 day, recommended as a separate PR in the same session to keep the security remediation's diff clean.

**Decision needed:** build #3366 now (CTO/CPO recommendation), or keep the plan's escalate-only approach?

---

## DC-2 — Drop the transient hourly cron
**Class:** Taste · **Raised by:** CTO

The plan adds an hourly self-heal cron to `apply-inngest-rls-dev.yml`, intended to be retired at Phase 5. CTO argues: rely on merge-apply **+** the image-pin path trigger, and let #3366's nightly scan be the permanent detection layer.

- Inngest deploys from a **pinned** bootstrap image (`cloud-init-inngest.yml`, `soleur-inngest-bootstrap:v1.1.19`), so goose runs only on a deliberate, reviewable in-PR pin bump — **not** a background event. A path-triggered re-apply on that PR is *tighter* than a 1h poll.
- Net cron count becomes `+1 permanent, generic` instead of `+1 transient, project-specific`. Phase 5 then retires **no cron** — which is exactly what rotted in **#4707** (orphaned `inngest-watchdog-restart-dispatch.yml`, still in-repo 45 days after its retirement issue).
- **Residual risk:** detection window widens ≤1h → ≤24h. Accepted because the trigger is a reviewable PR, 13/14 tables are empty, and the GDPR verdict is "no personal data".

**Gated on Phase 0.7** (confirm goose cannot run without a pin bump). If CPO rejects the trade, keep the cron — but then DC-1 and the Phase-5 CI annunciation become **mandatory**, not optional.

### GATE RESOLVED — 2026-07-15 (implementation)

**Phase 0.7 verified live: the gate's precondition HOLDS.** `apps/web-platform/infra/cloud-init-inngest.yml:330` pins `IREF=ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.19` — a concrete version tag, **not** `:latest`. (The other bootstrap consumer, `cloud-init.yml:693`, is likewise pinned at `v1.1.20`.) Goose therefore **cannot** run without a deliberate, reviewable in-PR pin bump; there is no background path that creates a 15th table.

**⇒ The hourly cron was NOT added** (task 2.7's condition is false by verification, not by preference). `apply-inngest-rls-dev.yml` ships with **no `schedule:`**, and instead carries `apps/web-platform/infra/cloud-init-inngest.yml` in its `paths:` — so a pin bump triggers a **deterministic** re-apply on the only event that can create a new Inngest table. That is strictly tighter than a probabilistic 1h poll, and Phase 5 now retires **no cron** (the #4707 rot mode).

This resolution is **within** the plan's stated scope (Phase 2: *"Hourly self-heal cron is conditional on Phase 0.7"*), so it required no scope change. The residual ≤24h detection widening is unchanged and still routes to **#3366** (escalated to P1 with evidence). DC-1 remains open for CPO — it argues #3366 should be *built* now rather than escalated; note that if CPO declines DC-1, the detection layer for a 15th table is time-to-human-PR (**unbounded**), which is the honest accounting and the strongest argument for the Phase-5 drop (#6488).

---

## DC-3 — Merge the two workflows into a matrix (recorded dissent)
**Class:** Taste · **Raised by:** DHH · **Plan sides against, 2:1**

DHH: `apply-inngest-rls-dev.yml` is a ~269-line copy to change four values; a `matrix.include` tuple binding `ref`→`sql` is a constant (not attacker-controlled interpolation) and makes "apply `0001` to dev" **structurally unrepresentable** — dissolving the AC that exists only because the file was forked. The repo already carries a **second** verbatim copy of the `strip_log_injection`/`scrub_pat` anti-exfil helpers; this would be the **third**, and a missed sync on a security helper is a credential in a public Actions log.

**Plan's counter (code-simplicity + CTO concurring):** the two workflows share only HTTP plumbing. The gate semantics differ *fundamentally* — prd's gate is schema-wide `has_table_privilege('anon', …)` over every public table; pointed at dev it reports **violations≈52** forever (the app's 52 tables hold anon grants by design). A matrix needs a third variable carrying a SQL predicate, plus divergent `pg_default_acl` posture and lifetimes (prd permanent, dev retired at Phase 5). Refactoring a brand-survival-critical prd workflow to accommodate a transient one is the wrong trade.

**Recorded because DHH's helper-triplication point is independently valid** regardless of the matrix decision — filed as a standalone follow-up (extract the helpers to a checked-in script sourced post-checkout).

---

## DC-4 — Pin `pg_temp` in the same migration that adopts `ensure_rls`
**Class:** Taste · **Raised by:** CPO (condition 4)

`rls_auto_enable()` runs live in web-platform prd with `search_path=pg_catalog` — **no `pg_temp`** — a live violation of `cq-pg-security-definer-search-path-pin-pg-temp`. The plan defers that pin to a follow-up bundled with two unrelated functions.

CPO: *"You do not commit a known-defective object and then file an issue against your own fresh migration."* When the §Drift adoption lands (separate ADR + PR), the `pg_temp` pin lands **in that same migration**. The two genuinely-unrelated functions (`increment_conversation_cost`, `sum_user_mtd_cost`) stay a separate follow-up as planned.

---

## CPO sign-off status

**SIGN OFF, with 4 conditions — all folded into plan v2:**

| # | Condition | Where applied |
|---|---|---|
| 1 | Phase 5 needs an owner + a dated 60-day backstop that fires even if the cutover hasn't | Phase 5 |
| 2 | File a **cause-level** prevention issue distinct from #3366 (symptom vs. cause) | Phase 4.4 + finding 3 |
| 3 | Re-justify the threshold on **write-integrity**, not ADR-030 carry-forward | Plan header |
| 4 | `pg_temp` pin lands in the `ensure_rls` adoption migration | DC-4 |

**CPO's material correction (folded in as finding 3):** the co-tenancy is a **rule GAP, not a rule violation**. `hr-dev-prd-distinct-supabase-projects` requires Doppler `dev`/`prd` *configs* to resolve to distinct refs — they do. `preflight` Check 4 compares only those two configs and never reads `soleur-inngest/prd`'s `INNGEST_POSTGRES_URI`. ADR-023's threat model is *dev-credential → prod rows*; this is the **inverse**. Nothing catches the next instance — which is why condition 2 is not optional.
