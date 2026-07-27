# Decision Challenges — feat-one-shot-6977-git-data-birth-route

Recorded headless per ADR-084. `ship` Phase 6 renders these into the PR body and files an
`action-required` issue. **These are NOT applied** — they challenge the operator's stated
direction and require an operator decision.

---

## DC-1 — `user-challenge` — Should the enum option + job ship in THIS PR, or in #6982?

**Operator's stated direction (the default):** *"Ship #6977 — give git-data an executable birth
route."* The plan honours this: the enum option, the `git_data_host_create` job, the gate, the
suite and the runbook all ship here, held from use by a birth-readiness interlock.

**The challenge (dhh-rails-reviewer P1-2, reinforced by code-simplicity and architecture-strategist):**
ship the **gate + suite + IaC fixes** in #6977, and add the `apply_target` enum option + the
`git_data_host_create` job in **#6982**. Then the ordering constraint is enforced by *the absence
of the capability* — the only hold that cannot be accidentally released — and the entire
birth-readiness interlock (Phase 4, AC10, R3, the sentinel, its rot risk, and its discoverability
problem) disappears with it.

**Why this is a real question and not pedantry.** Three of six reviewers independently attacked
the interlock, and `architecture-strategist` showed its recommended replacement mechanism is dead
on arrival (see DC-2). The interlock exists *only* because the capability ships before it is safe
to use. Remove that, and the plan loses ~120 lines and its single highest-risk design choice.

**Cost of the challenge:** #6977 would no longer deliver an *executable* route — its own issue
title and AC1 ("a `git-data-host-create` target exists") would go unmet in this PR, and the issue
would close on a partial. That is a scope change only the operator can authorize.

**Plan's current disposition:** stated direction retained (route ships here, interlocked).
Surfaced for the operator.

### RESOLVED 2026-07-27 by the operator — ship the route now, interlocked

Asked before implementation began, because the two options produce materially different
code and the fork sits on the one sequencing risk the task brief singled out.

**Decision: retain the stated direction.** The enum option, the `git_data_host_create`
job, both gates, the suites and the runbook all ship in #6977, held from use by the
birth-readiness interlock that #6982 releases. #6977 therefore closes on a complete
executable route rather than a partial.

What this commits us to, stated plainly: the ordering constraint is now enforced by a
CONTROL (a gate that can in principle be released early) rather than by the ABSENCE of the
capability (which cannot). The plan reduces that exposure by moving the interlock out of
inline YAML into a sourced, suite-covered gate file, so it inherits the mutation battery
and the parity job⇄gate pairing — which answers `architecture-strategist`'s structural
objection, the strongest form of the challenge. It does not eliminate the exposure, and
ADR-149 records the release checklist so #6982 inherits it mechanically rather than by
memory.

---

## DC-2 — `taste` — The interlock's mechanism is contested, and the recommended alternative is falsified

Recorded because the resolution is a judgement call, not a fact.

- `dhh-rails-reviewer`: delete Phase 4 outright — *"prose with a `grep` wrapper."*
- `code-simplicity-reviewer`: keep, but pin the sentinel to `${sentry_dsn}` so `templatefile`
  makes it self-enforcing.
- `cto`: keep and strengthen — mandate the *failure-message text* as the handoff to #6982.
- `cpo`: keep — *"the strongest thing in the plan"*; it is what makes shipping ahead of the
  hardening defensible at all.
- `architecture-strategist`: unsound as specified (an inline, unbatteried, un-paired control —
  the plan's own rejected Alternative (c) applied to its riskiest gate). Recommended replacing the
  cloud-init grep with a read of `heartbeat-manifest.ts`'s git-data `feeder` declaration.

**That recommendation is falsified by measurement.** `plugins/soleur/lib/heartbeat-manifest.ts`
already records git-data's feeder as `kind: "timer"` (*"#5274 PR C (#6548) SHIPPED the web-host
probe"*). A sentinel reading that declaration would release **immediately**, so option (a) cannot
work.

**Plan's current disposition:** keep the interlock, but move it into a **sourced, suite-covered
gate file** (`tests/scripts/lib/git-data-birth-readiness-gate.sh`) so it inherits the mutation
battery and the parity job⇄gate pairing — which answers architecture-strategist's structural
objection — and mandate its failure-message text as the #6982 handoff (cto F4, cpo C2). Sentinel
pinned to the interpolated `${sentry_dsn}` (code-simplicity), not a bare word.

---

## DC-3 — `user-challenge` — `doppler_secret.git_data_ssh_host` (Defect 2b) was CUT against CPO's advice

**CPO's position (C3, part of the sign-off):** include it. `GIT_DATA_SSH_HOST` has no producer and
is absent from `prd`, so the false "Art. 17 erasure failed" alarm is the user-visible harm #6977
names; publishing the address is what actually removes it.

**Why the plan cut it anyway — a feasibility regression, which ADR-084 makes the sanctioned
exception to "surface, don't decide":** `architecture-strategist` showed that adding the resource
makes `terraform-target-parity.test.ts` RED on landing (it is absent from
`OPERATOR_APPLIED_EXCLUSIONS` and cannot be added there before it exists). The natural
red-test remedy — adding a per-PR `-target` line — drags `hcloud_server.git_data` into the
per-merge plan via transitive upstream closure, tripping `host_creates > 0` and **wedging every
merge to main**. That is the ADR-145 web-2 wedge reproduced for git-data from a one-line edit.

**Also:** `dhh-rails-reviewer` and `code-simplicity-reviewer` independently voted to cut, and
`spec-flow-analyzer` showed 2b does not even achieve CPO's goal — with the host unreachable,
`resolveGitDataSshHost()` stops throwing and `sshWithPrivateKeyAuth(..., { timeout: 30_000 })` is
attempted instead, converting an instant false alarm into a **30-second hang per account
deletion** on the awaited Art. 17 path, followed by the same Sentry event.

**Disposition:** CUT from #6977. Moved to #6982, where the emitter work already touches
`git-data.tf` and the exclusion-list entry can land in the same change. If added later it MUST
single-source the address (`hcloud_server_network.git_data.ip`), never a 25th copy of the
`10.0.1.20` literal.

**Residual accepted:** the false-alarm window stays open in principle — but it is **unreachable
today**, because `doppler_secret.git_remove_ssh_private_key` is itself absent from state, so the
arming switch is unarmed, and Defect 2a's `depends_on` guarantees it can never land without the
server.
