# Decision challenges — feat-one-shot-6982-git-data-pre-birth-hardening

Persisted by `plan` (headless arm) per ADR-084 / plan Step 4.5 + the Plan-Review apply gate. These
are **Taste** and **User-Challenge** class decisions that were NOT auto-applied — the operator's
stated direction is the default, and these are surfaced rather than silently overridden. `ship`
Phase 6 renders this into the PR body and files it as an `action-required` issue.

Mechanical findings were auto-applied and are recorded in the plan's `## Plan Review Revisions
(v1 → v2)` table (R1–R38), not here.

---

## DC-1 — Taste: one PR vs. four (CTO recommendation, declined)

**Raised by:** `soleur:engineering:cto` domain review, reinforced by `code-simplicity-reviewer`.

**The challenge.** The CTO recommended splitting this work into four PRs by irreversibility class:
an atomic core (`W0 + W1 + W3 + W8`), then `W4 + W7`, then `W6`, then `W5`. The argument: W5 (quota
and reclaim) is the largest genuine unknown, and holding the interlock release hostage to it is a
bad trade.

**Why the plan keeps it atomic.** CPO endorsed the atomic form. All eleven workstreams share one
forcing function (everything must land before a single irreversible event), and `user_data` is
ForceNew so each item deferred to a later PR becomes a destructive `git-data-host-replace` if the
birth happens first.

**What changed in v2, and why this is still worth surfacing.** The architecture reviewer showed
that v1's *reason* for not splitting was wrong: a split does **not** forfeit the interlock, because
sequencing the emitter PR last preserves the mechanical hold. So atomicity is now recorded as a
**choice** (review coherence + shared forcing function), not a constraint. That means the operator
may reasonably prefer the split, and the boundary is pre-specified in the plan (A12).

**Disposition:** atomic, with the split boundary documented for `/work` to fall back on. **Operator
may override** — the fallback costs nothing if chosen before implementation starts.

---

## DC-2 — Taste: acceptance-criteria count (partially declined)

**Raised by:** `code-simplicity-reviewer`.

**The challenge.** 13 of the 29 v1 acceptance criteria were called ceremony — restatements of phase
instructions, or assertions that tests this PR does not touch still pass. The reviewer's argument is
sound in general: *"a reviewer who sees 29 boxes skims; one who sees 17 checks them."*

**What was accepted.** AC2, AC17, AC19 and AC21 were cut outright (R37). The vacuous halves of AC11
and AC12 were trimmed to their load-bearing halves.

**What was declined, and why.** AC14, AC15, AC27, AC28 and AC29 were **kept**. At
`brand_survival_threshold: single-user incident`, the prose-drift and record-keeping criteria are
the only mechanical trace that the ADR / Art. 30 register / expense-ledger deliverables actually
landed — they are markdown edits with no compiler and no test to catch their absence. AC14 in
particular was independently shown by Kieran (R27) to be **catching a real missed site**: Phase 7.3
had never assigned the third occurrence of the D1 claim.

**Disposition:** partial accept. Net criteria count rose (29 → 34) because four P0 findings required
new coverage (AC33–AC36). **Operator may prefer the deeper cut** if review-surface economy is
valued over record-keeping traceability at this tier.

---

## DC-3 — User-Challenge: the plan does not perform the birth

**Raised by:** implicitly by the Fable advisor consult (which pushed for runtime evidence), resolved
by CPO.

**The tension.** The plan's hardening cannot be proven end-to-end without a birth, and this PR
deliberately does not birth the host. The advisor's push for runtime evidence was adopted as W12
(a rehearsal boot on a throwaway host), which is strictly weaker than the real thing.

**Why the plan does not require the birth.** Dispatching a host birth is a production write and
needs independent operator authorisation (`hr-menu-option-ack-not-prod-write-auth`) — a plan cannot
require an act it has no standing to authorise. CPO ruled the deferral acceptable and would have
rejected the alternative.

**Disposition:** birth stays out of scope; W12's rehearsal plus the follow-through probe (AC20)
carry the evidence burden. **This is the operator's call to make** — if the operator wants the birth
dispatched in the same session after merge, the runbook path is ready and the follow-through probe
will confirm it.

---

## DC-4 — Deferred with tracking, flagged for operator visibility

Three deferrals CPO explicitly endorsed, recorded here because each carries a real (if bounded)
exposure the operator should know about:

1. **#6548 — the Better Stack heartbeat is not created or armed.** Not merely deferred: v1 proposed
   folding it in and v2 **withdrew** that on three independent grounds (it would wedge every merge
   to `main` via the per-merge `arm_one`; the beat proves reachability, not boot correctness, so a
   host whose LUKS never mounted beats green; and the Better Stack object pool may be at 10/10).
   CPO called this a safety *increase* — deferring a false signal removes an anti-signal.
2. **Per-workspace storage quotas** are blocked on a contractual gap, not an engineering one: there
   is no storage-limit clause in the T&C or AUP, so a quota-triggered prune of *reachable* user
   content has no basis. The irreversible half (`mkfs -O quota,project`) ships now; the tracking
   issue must name the missing clause as the blocker, or the next implementer will build **and arm**
   it (CPO C5).
3. **ADR-149 Residual 3** (an erasure against an empty store records success) is bound to the
   `GIT_DATA_STORE_ENABLED` cutover — "must close before the flag flips in prd" — not to a date and
   not to the birth.

**Disposition:** all three deferred with gate-bound (not date-bound) tracking. No operator action
required now.

---

## DC-5 — User-Challenge: item 5's mandated MECHANISM is not satisfiable in the window it applies to

**Raised at:** rebase onto `origin/main`, 2026-07-28. Not a review finding — the constraint landed
on `main` in **#7003** after this branch's `git-data.tf` work was already committed, so nothing in
this session's review panel could have seen it.

**The operator's stated direction (the default).** ADR-149 release-checklist item 5, and the DC-3
`RESOLVED` block in
`knowledge-base/project/specs/feat-one-shot-6977-git-data-birth-route/decision-challenges.md`:

> When it lands it **MUST** single-source the address from `hcloud_server_network.git_data.ip` —
> never a fresh copy of the `10.0.1.20` literal.

**What shipped instead.** `doppler_secret.git_data_ssh_host.value = local.git_data_private_ip`
(`git-data.tf`). `hcloud_server_network.git_data.ip` reads that **same** local (`network.tf`), so
the repo holds exactly one `10.0.1.20` literal.

**Why the mandated mechanism cannot be used.** It contradicts a second requirement of the same
checklist. `hcloud_server_network.git_data` depends on `hcloud_server.git_data.id`; a secret that
reads its `ip` attribute therefore cannot be planned or applied while the host is absent. But
ADR-149 Residual 2 requires `GIT_DATA_SSH_HOST` to exist **before the first dispatch** — i.e.
precisely while the host is absent. The two constraints have no common satisfying assignment.

Reading the computed attribute would also restore the `-target`-closure edge to
`hcloud_server.git_data` that DC-3 cited as its own reason for cutting the resource from #6977, so
the mandate works against the rationale that produced it.

**What is and is not met.**

| Constraint (DC-3) | Status |
|---|---|
| `OPERATOR_APPLIED_EXCLUSIONS` entry lands in the same change | **MET.** |
| Never a fresh copy of the `10.0.1.20` literal (the stated *harm*) | **MET** — one literal, one source, repo-wide. |
| Single-source specifically from `hcloud_server_network.git_data.ip` (the prescribed *mechanism*) | **NOT MET.** Infeasible pre-birth, as above. |

**Disposition:** shipped as `local.git_data_private_ip`, divergence recorded rather than silently
absorbed. The mandate's protective intent is satisfied by a strictly stronger property (a single
source that *both* consumers read, with no dependency edge to an unborn server). Recorded in
ADR-149 under *Item 5's mandated mechanism is not satisfiable pre-birth*.

**Operator action:** confirm the substitution, or direct a different resolution. If the literal
mechanism is required, item 5 and Residual 2's "before the first dispatch" requirement need to be
reconciled first — they cannot both stand as written.
