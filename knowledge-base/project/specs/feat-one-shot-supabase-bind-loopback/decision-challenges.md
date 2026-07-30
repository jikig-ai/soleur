# Decision Challenges — feat-one-shot-supabase-bind-loopback

Surfaced by `plan-review` (7-agent panel) and the Step 4.5 advisor consult. Persisted here because
the session is headless: per ADR-084, Taste and User-Challenge decisions are never silently applied.
`ship` Phase 6 renders this into the PR body and files an `action-required` issue.

Mechanical findings were auto-applied to the plan and are not listed here.

---

## UC-1 — Is this plan still too big? (User-Challenge)

**Class:** user-challenge — argues the operator's implicit scope should shrink.
**Raised by:** dhh-rails-reviewer (P0), code-simplicity-reviewer (concurring).

**The challenge.** DHH's position is that the entire deliverable should be roughly: create the
network with one option, pass `--network-id`, document it, and stop. On that view the CI assert
step, the unit-test harness, and the SessionStart hook are all machinery defending a laptop-local
dev convenience — and the CI gate in particular "verifies Docker Engine's behaviour on an ephemeral
runner", not the founder's laptop, which is where the risk actually lives.

**What was applied.** Substantially. The harness point-of-use guard was cut entirely; three scripts
collapsed to one; five acceptance criteria were deleted as restatements of phase instructions; the
Phase 0 probe apparatus and its fallback branch were removed.

**What was NOT applied, and why.** The CI assert step and the SessionStart detector were kept.
Architecture-strategist (P0-1) and spec-flow (P1-1) independently found the opposite gap: **nothing
in the previous design would ever tell the founder their running stack was exposed**, because the
only signal fired on the path an exposed developer is by definition not on. Cutting the detector
re-opens exactly that hole. The two panels genuinely disagree here and the plan takes the
correctness panel's side.

**Operator decision needed:** accept the current middle position, or cut the SessionStart hook and
CI step and accept "the wrapper is the documented path, and nothing checks it".

---

## UC-2 — Should host-wide Docker hardening ship now rather than be deferred? (User-Challenge)

**Class:** user-challenge — argues for *adding* scope the brief did not request.
**Raised by:** architecture-strategist (P1-7).

**The challenge.** The plan's original rejection of the Docker-daemon fix (`{"ip":"127.0.0.1"}` in
`/etc/docker/daemon.json`) was **empirically false** and has been corrected in the plan: no
non-Supabase container on this host publishes anything except Dropbox, no `daemon.json` exists (so
it is greenfield), and an explicit `-p 0.0.0.0:` still overrides the default — so breakage would be
loud and one-flag-fixable, not silent. On the corrected evidence, the daemon setting is the
**fail-safe-default** posture and is immune to every fail-open path the chosen mechanism has
(prune, bare start, fresh machine, other containers).

**What was applied.** The rationale was corrected, the option reclassified from "rejected
alternative" to "deferred complement", and its deferral raised from `p3-low` to `p2-medium` with a
proactive dated trigger.

**What was NOT applied.** It is still deferred rather than shipped here, because it is root-level
host configuration that warrants its own cycle and IaC review, and because the brief scoped this
work to the Supabase stack.

**Operator decision needed:** confirm the deferral, or fold the daemon setting into this PR.

---

## UC-3 — Threshold and sign-off ceremony (Taste)

**Class:** taste.
**Raised by:** dhh-rails-reviewer (P2); CPO affirmed the opposite.

**The tension.** DHH argues `single-user incident` + `requires_cpo_signoff` describes *the exposure*,
not *the change* — the change is a config edit to dev tooling, and the ceremony is disproportionate.
CPO reviewed the same facts and **affirmed** the threshold, explicitly warning against lowering it:
the asset at risk is the laptop (five unauthenticated pre-auth services on the machine holding
Doppler, GitHub App credentials, and prod SSH), not the database.

**Resolution taken:** threshold kept. CPO's reasoning is grounded in measurements DHH did not have.

**Operator decision needed:** none unless you disagree with CPO's framing.

---

## Note on a finding that was *not* a challenge

CPO's six sign-off conditions (C1–C6) were **applied in full**, not surfaced — they were conditions
on an affirmative sign-off, not contested taste. The most consequential is **C1: stop the stack
now**, which is now §Step 0 of the plan and is the single most important action from this session.
