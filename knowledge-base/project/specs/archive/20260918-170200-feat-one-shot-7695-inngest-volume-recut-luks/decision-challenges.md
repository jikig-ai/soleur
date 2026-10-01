# Decision Challenges — feat-one-shot-7695-inngest-volume-recut-luks

Recorded headless during `/soleur:plan` on 2026-09-02. These challenge the **stated direction** of
the issue brief. Per ADR-084 the operator's direction is the default, so none of these was applied
silently — each is surfaced here for `/ship` to render into the PR body and file as an
`action-required` issue.

Plan: `knowledge-base/project/plans/2026-09-02-infra-inngest-volume-recut-luks-plan.md`

---

## 1. The R2 header escrow is CUT (brief said to copy it)

**Brief said:** recut as LUKS using, among other precedents, "the R2 header-escrow bucket in
`workspaces-luks-header.tf`".

**Plan does:** no escrow.

**Why:** ADR-142 (`status: accepted`) rejects escrow for **this specific store** by name — "No key
escrow (git-data-lean shape)… Escrowing the header would **add** a sensitive artifact (which, with
the Doppler passphrase, yields full plaintext decrypt of user prompts/agent output) — a net
**increase** in confidentiality attack surface for a durability gain this transient store does not
need." The inngest AOF's total-loss recovery is already built and proven
(`inngest-wiped-volume-verify.sh`); `/workspaces` escrows because *its* loss is unrecoverable by
the user, which is not true here. Copying the template's escrow would silently reverse an accepted
ADR and add a CWE-522-class artifact.

**Cost if overridden:** a distinct R2 bucket plus a bucket-scoped R2 API token that is not
derivable from any existing `cloudflare_api_token` field, i.e. a dashboard-minted credential step,
plus a mandatory negative probe that the escrow creds are DENIED against `soleur-terraform-state`.
Multi-day, with a credential dependency, imported into a latch fix.

**Decision needed:** confirm the cut, or direct that escrow be built anyway.

---

## 2. The destructive recut is now GATED on a measurement that does not yet exist

**Brief said:** the recut is cheap because the host is dark and the AOF is "stale state from the
rolled-back flip era"; a re-flip FLUSHALLs Redis anyway, so recut and latch-clear converge.

**Plan does:** builds the recut, but refuses to authorize dispatch until a probe row shows
`redis_keys == 0` on the current `boot_id`.

**Why:** the "host is dark / never served" evidence covers **2026-08-20 → now**. The flip that
wrote the latch completed **2026-07-23/24**, on a *previous host generation*. The evidence window
begins roughly four weeks after the window of concern, so it cannot retire the risk that the July
flip left recoverable armed reminders in the AOF. The historical question is unanswerable — Better
Stack retention is measured at ~20 days. The present-tense question ("is the store empty right
now?") is answerable and sufficient, but the channel to answer it does not exist yet, which is why
Phase 1 builds it.

**Consequence the brief does not contemplate:** if `redis_keys > 0`, **this plan does not authorize
the recut at all**. The work routes to ADR-142's additive byte-copy migration under #6894. That is
a real branch, not a formality.

**Decision needed:** accept the measure-first ordering, or direct that the recut proceed on the
topology argument alone.

---

## 3. A cheaper option may dominate and is flagged for plan-review

**Not in the brief at all.** Refining `flush_already_performed()`'s *refusal* — refuse re-arm after
a recorded flush **unless** the store is provably empty (all DBs) and the host provably dark at the
moment of the arm — clears the blocker with **no destructive target, no volume touched, and no new
`apply_target`**. It preserves the #5450 guarantee exactly, because a live prod queue has
`redis_keys > 0` and serves HTTP 200.

It is not a full substitute: it does **not** close the `plaintext-exception` on
`hcloud_volume.inngest_redis` whose `expires_on` is **2026-10-22**. But if #6894 is going to run
ADR-142's LUKS migration anyway, this plan may be building a destructive capability that the
migration would render unnecessary.

**Decision needed:** grade this against the planned approach before implementation begins.

---

## 4. Scope boundaries held (no challenge — recorded for completeness)

- **#7698** (app dispatch failing) was NOT folded in. Separate issue, separate PR.
- **#7674** stays OPEN until `scripts/followthroughs/inngest-host-not-serving-7674.sh` reads PASS.
- The PR body uses `Tracks`, never `Closes`, for #7695, #7674 and #6894 — the remediation executes
  post-merge at a gated dispatch, so `Closes` would auto-close a still-open state.
- The **webhook latch readback was NOT built.** ADR-100 Decision 6a stands unamended. Phase 1 meets
  the intent by extending an emitter that already runs over the already-adopted Vector → Better
  Stack transport — which is precisely the substitution ADR-100 records the operator choosing on
  2026-08-25. No inbound control plane is added to the deny-all-public singleton.

---

## 5. The recut is now gated behind #7674, which the brief treats as downstream

**Brief said:** #7695 is "the unblocker for #7674 steps 4b-6" — i.e. the recut comes first and
unblocks #7674.

**Plan does:** the reverse. `scripts/followthroughs/inngest-host-not-serving-7674.sh` must read
**PASS before** the recut is dispatched (Guard 2 condition 10).

**Why — verified against source, not inferred.** `inngest-cutover-flip.sh` calls
`record_flush_latch` at `:492`, **before** `verify_or_abort` at `:502`. `verify_or_abort` requires
`/health` 200 plus a non-empty function registry, and drives the flag to terminal `aborted` on
failure. The host cannot bind today (`http_code=000`) **even though** `INNGEST_DIAGNOSTIC_BOOT=1` is
already engaged — and that flag, per `inngest-server-flip-guard.sh`, exists precisely to let the
host bind against a non-durable backend. So the bind failure is not the latch, and it is not the
flag allowlist.

Consequence: a recut dispatched before #7674 is fixed would have the first `arm` write a **fresh**
latch, fail verify, and land in terminal `aborted` — latch re-armed, flag *worse* than
`rolled-back`, and the one-shot destructive capability spent on an undiagnosed bind failure. The
dependency runs the other way from how the brief frames it.

**Decision needed:** accept that #7695 does not unblock #7674 on its own, and that #7674's bind
failure must be diagnosed first — or direct otherwise, understanding the above.

---

## 6. Delivery is now two merges, not one

**Brief implied** a single PR building the capability.

**Plan does:** Merge A (probe/read channel only) then Merge B (apparatus + gated target).

**Why:** `tests/scripts/lib/inngest-host-replace-gate.sh` allows exactly three addresses and
records that `hcloud_volume.inngest_redis` is *"DELIBERATELY ABSENT"*, with PASS requiring
`oos==0 && rdel==0 && replaced==1`. Both of Merge B's `.tf` edits put the volume into that plan
(`-target` prunes dependents, not dependencies), so a combined PR makes its own delivery vehicle
abort. The tempting fix — widening that gate — would be actively dangerous: `inngest-host-replace`
has no reviewer gate, no typed confirm and no id-pin, so widening it creates an unguarded second
recut path in the very PR that builds five guard layers.

**Decision needed:** accept the split, or direct a single PR with a different delivery vehicle.

---

## 7. Two deliverables the brief did not scope, both mandatory

- **A boot-reopen systemd unit.** `cloud-init-inngest.yml` runs `runcmd` on **first boot only**, so
  nothing reopens the LUKS mapper on boot 2 — Redis would write plaintext to the root disk while the
  ledger claims `luks`. `workspaces-luks.tf` has the identical unsolved gap (deferred to #6931), so
  there is no precedent to copy and it must be built here.
- **The ledger row is staged, not flipped.** Flipping `mechanism` to `luks` at merge would publish a
  false at-rest claim about user prompts and agent output for an unbounded — possibly permanent —
  window. The exception is retained and re-dated at merge; the flip lands in a follow-up gated on
  post-recut verification.

**Decision needed:** none, unless the added scope is unacceptable — in which case the recut itself
should be reconsidered, since neither is optional.
