# Decision challenges — feat-one-shot-6588-luks-workspaces-volume

Decisions taken during planning that go against the stated direction in issue #6588, or that the
issue did not contemplate. Recorded per ADR-084 so they are auditable outside this session. `ship`
renders these into the PR body and files them as `action-required` issues.

**Mode: interactive.** DC-A and DC-B were **asked and answered by the operator on 2026-07-17**; their
resolutions are recorded in-place below. DC-C remains an in-plan resolution recorded for audit.

---

## DC-A — User-Challenge: the plan decouples the legal retraction from the encryption work

**Date:** 2026-07-17
**Classification:** User-Challenge (contradicts the issue's stated Acceptance Criteria)
**Status:** RESOLVED 2026-07-17 — **operator DECLINED the decouple. The coupling stands.**

### ⚖️ Operator decision (2026-07-17, interactive)

**"Keep the coupling — one PR after migration."** The challenge below was put to the operator with the
CLO/CPO/CTO arguments in hand and was **declined**. #6588's AC governs as written:

- **All four** doc corrections — the three permanent retractions **and** the LUKS-clause flip — land in
  a **single PR**, gated on **live verification** of the encrypted volume. The "Only THEN" is honoured
  for the whole clause set, not just the LUKS limb.
- The two-PR split described below (**PR 1 docs-only this week**) is **cancelled**. Its contents fold
  into the post-cutover legal PR.
- **DC-1 closes when that post-cutover PR merges**, not before.
- The three permanently-false clauses **stay published** for the duration of the migration. This is the
  controller's risk acceptance, taken for the third time with the Art. 5(2)/Art. 34(3)(a) scienter
  argument (DC-B) explicitly in hand.

**Consequence for the implementation plan:** the infra PR produced by this run carries **zero doc
changes**. `## The legal track` below is retained **as the specification of the post-cutover PR's
contents** — not as a separate near-term PR.

### The stated direction

Issue #6588's Acceptance Criteria require:

> - [ ] Only THEN: the privacy-policy / DPD LUKS clause becomes true. Re-verify the wording and
>   re-pin `apps/web-platform/lib/legal/legal-doc-shas.ts`.
> - [ ] The three unachievable clauses above corrected **in the same PR** (retract/past-tense), and
>   `decision-challenges.md` DC-1 closed.

i.e. **all four doc corrections are gated behind the encryption migration.**

### The challenge

Three domain leaders — spawned independently, without contact — converged against this.

**1. Legal (CLO).** No state of the world makes the three clauses true. They are false *forever*,
independent of #6588: the per-workspace git-data host cannot be born (cax11 orderable in 0 of 3 EU
DCs, #6570); no cross-host git traffic exists (and #6538 destroys web-2); no session has ever been
served across hosts (no LB; `app.soleur.ai` is a hard-pinned singleton). **Gating their retraction
behind a migration keeps three falsehoods published for a reason that does not exist.**

**2. Safety (CLO, corroborated by the CTO's evidence) — the decisive argument.** The volume holds
**sole-copy** user data: `refs/checkpoints/*` is pushed by no refspec, `session-sync.ts` autocommits
only `knowledge-base/**`, and every signup-provisioned workspace has no GitHub remote at all. The
migration is a freeze/rsync cutover whose freeze mechanism does not yet exist. **Gating the doc fix
on the migration makes legal-accuracy pressure the forcing function on a data-loss-capable cutover
over data with no second copy** — schedule pressure on precisely the operation that must not be
rushed. Decoupling removes that coupling and lets the cutover be priced on engineering merit alone.
**The two goals are aligned, not in tension.**

**3. Product (CPO).** **The claim's audience does not exist yet** — 0 beta users (`roadmap.md`
Current State; #1439 "recruit 10 solo founders" is still OPEN). No data subject has been misled.
**Retraction is free right now and gets monotonically more expensive with every founder #1439
recruits** — the first signup is the moment a victimless inaccuracy becomes an actual breach against
a real data subject. **#1439 and #6588 are on a collision course.**

### What the plan does instead

Splits into two PRs:

- **PR 1 — docs-only, this week, zero infra dependency.** Retract the three unachievable clauses
  across all 20 sites; temporally qualify the LUKS clause; create the missing Art. 30 Processing
  Activity at its *true current state*; correct `compliance-posture.md:78`; close DC-1.
- **PR 2 — when the migration lands.** Flip the LUKS qualification to present tense; amend the PA's
  TOM limb; re-pin the SHAs.

The issue's *"Only THEN"* is honoured for the **LUKS clause** — it is only asserted as true after
live verification. It is **not** honoured as a gate on the other three.

### What this needs from a human

Agreement to amend #6588's AC to drop the coupling, or a decision to keep it.

---

## DC-B — User-Challenge: re-putting DC-1's second ask, already declined twice

**Date:** 2026-07-17
**Classification:** User-Challenge (re-opens a recorded risk acceptance)
**Status:** RESOLVED 2026-07-17 — **operator DECLINED for the third time. The claim stays published as-is.**

### ⚖️ Operator decision (2026-07-17, interactive)

**Asked on the changed facts and declined.** The LUKS clause is **not** temporally qualified now; it
stays published unqualified until the migration lands and is live-verified, at which point it becomes
true in the same PR that retracts the other three (see DC-A).

**What this means, stated plainly so the record is honest:** the re-raise premise in DC-1 was a
*bounded* window, and the facts below establish the window is **not** bounded by 2026-07-23 — the
freeze mechanism does not exist and cx33 is unorderable in all three EU DCs. The operator has taken
this risk acceptance **with that unboundedness known**, and with the CLO's Art. 5(2) scienter and
Art. 34(3)(a) notification-exemption arguments in hand. This is the controller's call to make; the
exposure is theirs and it is now made on current, not stale, facts. **DC-1's 2026-07-23 trigger is
superseded by this decision** — it should not re-fire as if undecided.

**Still binding regardless of this decision** (they are corrections of fact, not of direction, and
carry into the post-cutover legal PR):

- The temporal-qualification anchor is **Art. 12(1) + Art. 5(1)(a)**, not Art. 13(3) (13(3) governs
  further processing for a new purpose).
- **PR #4455 is not a wording template** — it is *"feat(legal): PR-1 Flagsmith sub-processor
  disclosure"* and the wording DC-1 quotes is not in it. The mechanism is reusable; the wording must be
  authored fresh.
- The Art. 32 framing is **weak**; the **transparency** exposure (Art. 5(1)(a) + 12(1) + 13(1)(f)) is
  the strong one. The post-cutover PR's prose should be reasoned on that basis.

### The stated direction

PR #6568's `decision-challenges.md` DC-1 records that the agent twice recommended retracting or
temporally qualifying the false LUKS claim, and was overruled both times:

> 1. **First ask:** retract the false clauses now… → Operator chose **"encrypt the volume first, then
>    keep the claim."**
> 2. **Second ask:** temporally qualify the remaining clause… → Operator chose **"leave the claim
>    published during the work."**
>
> **The decision:** The claim stays published, as-is, until the encryption work lands. This is the
> controller's risk acceptance to make; the exposure is theirs and they made it with the evidence
> above in hand.

### Why this is not a relitigation

**The premise of the overrule was a bounded window.** DC-1 itself records the window as *"unbounded"*
and sets a **2026-07-23 re-raise trigger** — six days from today.

**New facts establish that the fix cannot land by that date:**

- The cutover's freeze mechanism **does not exist**. `git-data-cutover.sh` invokes
  `soleur-drain.service` and `soleur-web.service`; `grep -rln` finds each in that file only. Neither
  is defined anywhere. The precedent is a design template, not runnable code.
- **cx33 is `available=false` in all three EU datacentres** (live 2026-07-17, corroborated at
  `tests/scripts/test-stock-preflight-gate.sh:11-13`), which forced a full re-architecture away from
  the issue's preferred approach.
- The work is sequenced **behind PR #6568**, which has not merged.

**So the trigger will fire on 2026-07-23 and re-ratify the same position by default, having accrued
six more days of exposure and one more documented decision to publish a known falsehood.** A
re-raise date whose predicate cannot be met is not a mitigation; it is a calendar entry.

A risk acceptance is scoped to the facts as they stood when taken. Those facts have changed. That
re-opens the decision **as a matter of course** — it does not require anyone to relitigate a settled
call, because the call is no longer settled. **Silent inheritance would launder a stale premise into
this plan, which is precisely the failure mode `decision-challenges.md` exists to prevent.**

### The CLO's added argument, which DC-1 never had

**DC-1 is evidence of scienter.** An undiscovered inaccuracy is negligent. A *documented,
deliberated, twice-overruled decision to keep publishing a statement known to be false* is a written
record that the controller knew. Under **Art. 5(2)** the controller must *demonstrate* compliance —
DC-1 demonstrates the opposite, in its own hand, dated, and is discoverable. **Accepting this risk in
writing costs more than the risk itself.**

And the limb nobody named: **Art. 34(3)(a)** exempts a controller from notifying data subjects of a
breach where it implemented measures "such as encryption, that render the personal data
unintelligible." Plaintext ⇒ **no exemption**. A snapshot leak or mis-scoped detach obliges full
data-subject notification, and the Art. 33 filing handed to the supervisory authority within 72 hours
would state *"data was in plaintext"* while the live privacy policy states *"LUKS-encrypted"*. **The
authority receives both documents.** That contradiction — not the encryption gap — is what converts a
contained incident into an enforcement posture. **The false claim does not sit inertly during the
window; it is a loaded liability that fires precisely when things go wrong.**

The CLO also corrected the framing inherited from DC-1: the **Art. 32 exposure is genuinely weak**
(Art. 32 mandates measures *appropriate to the risk*, not encryption; plaintext on a signed-DPA EU
processor is defensible). **The transparency exposure is the strong one** (Art. 5(1)(a) + Art. 12(1)
+ Art. 13(1)(f)). And DC-1's Art. 13(3) citation for the temporal-qualification precedent is the
wrong anchor (13(3) governs further processing for a new purpose) — the mechanism is right, the
citation should be Art. 12(1) + Art. 5(1)(a). Separately, PR #4455 — cited by DC-1 as the precedent —
is *"feat(legal): PR-1 Flagsmith sub-processor disclosure"*; **the quoted wording is not in it.** The
mechanism is reusable; the wording must be authored fresh.

### What this needs from a human

A fresh decision on changed facts: temporally qualify the LUKS clause now (PR 1), or keep it
published as-is until the migration lands.

---

## DC-C — Cross-domain disagreement resolved without a human (recorded for audit)

**Date:** 2026-07-17
**Classification:** Taste / cross-domain conflict — resolved in-plan
**Status:** RESOLVED — recorded for visibility, no action required unless the resolution is rejected

### The conflict

- **CPO (blocking condition C3):** *"Verified-restorable backup off the volume, taken pre-cutover.
  Not 'snapshot taken' — a **test restore proving readback**… Encryption of unbacked sole-copy data is
  a net downgrade in user outcomes."*
- **CTO:** *"Do NOT take a pre-cutover Hetzner snapshot as a backstop: a retained plaintext snapshot
  re-creates the exact Art. 32 exposure this ADR closes."*
- **COO (independently):** *"It was never the cost that made snapshotting wrong; it's that it
  manufactures an indefinitely-retained unencrypted copy of user source code inside the very issue
  that exists to eliminate them."*

### The resolution

All three are right; they answer different questions. CPO's condition is **outcome-shaped** (*"no
path may make F1-F4 reachable"*) and explicitly **not mechanism-shaped** (*"I am not prescribing the
mechanism"*).

The adopted additive design **already produces a two-copy state**: the old volume retains the
original while the new LUKS volume receives the copy. That **is** an off-volume, verified-restorable
backup — and it is *better* than a snapshot, because it is a live, mountable device the cutover
**rehearses** (CPO G8) rather than a blob nobody has ever restored.

C3 is therefore satisfied by **G7 + G8** — retained plaintext volume under
`lifecycle { prevent_destroy = true }`, 7 days, rollback rehearsed in Phase 3 — **without** a
snapshot's indefinite plaintext copy.

Two things CPO added that the CTO's ruling did **not** cover are folded in as blocking work:

- **G5 escrow proof** — CPO's F4: *"Today's worst case: someone else reads the user's code. Post-LUKS
  worst case: the user can't."* Passphrase loss is a **terminal mode created by the fix**. Reading the
  key back from Doppler and proving it unlocks a throwaway volume is now a blocking pre-freeze gate.
- **G8 rollback rehearsal** — prove the plaintext volume remounts and serves *before* it is needed.

**Retention takes CPO's 7 days over the COO's 72h.** The marginal security cost of four extra days of
retained plaintext is small; the data-loss protection is not, and CPO's condition is blocking.

### The residual

**If C3 is read strictly as requiring an off-volume artifact *distinct from the old volume*, this
resolution needs revisiting.** Recorded here so that reading is available rather than buried.

---

## Also recorded: a second cross-domain synthesis (no conflict remained)

**CTO `nofail` vs CPO G6.** The CTO requires `nofail` in fstab so a Doppler outage yields a degraded,
pageable boot rather than a hang (an unbootable sole host with no LB and no rebuild path is
catastrophic). CPO G6 requires that *"a failed unlock must halt the boot, never silently serve from
root disk."*

**Synthesis (Phase 1):** keep `nofail` **and** add a fail-closed gate before `docker run` that
refuses to start the container unless `/mnt/data` resolves through the mapper. Boot completes and is
observable; the app never silently writes to the root disk — which is CPO's actual concern (F5), and
is a *stronger* guarantee than halting the boot because it also covers the
mapper-opened-but-wrong-device case. **Neither leader had this alone.**
