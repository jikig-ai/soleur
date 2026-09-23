# Decision challenges: feat-one-shot-8211-git-data-cutover-real-modes

These are planning decisions that depart from the direction stated in the brief for #8211. They
are recorded under ADR-084 so the operator can review them outside this headless session. `ship`
renders this file into the PR body and files an `action-required` issue from it.

---

## DC-1: The first cutover is a LUKS-only render delivered by a host replace, not a runtime rsync and repoint

**Date:** 2026-09-22
**Classification:** architecture fork, ruled by `soleur:engineering:cto` as option B, then "B-lite".
It is recorded here because it drops a mechanism the brief named ("rsync hooks/") and removes the
rollback to plaintext.
**Status:** applied in the plan. PR1 implements it.

- **What you said:** rebuild the real cutover, rollback and wipe. Carry #8101's remaining halves:
  rsync `hooks/` so the fence does not dangle after the repoint, and assert the mapper device in
  all three wrappers before the flag flips.
- **What both signals recommend:** the git-data render always serves the LUKS mapper at
  `/mnt/git-data`. The plaintext volume is checked read-only at boot and then left unmounted until it is wiped. The
  serving device changes at the next ordinary host replace, while the flag is off and the store is
  empty. The mapper assertion in the wrappers is kept exactly as #8101 wrote it.
- **Why:** three verified facts.
  - The store has never been enabled and holds zero repositories. There is nothing to copy, and
    the bootstrap installs the fence directly onto the mapper.
  - A runtime repoint does not survive a host replace. Since ADR-237, every replace rotates the
    host key, so replaces are routine.
  - The erasure path is not behind the flag. A mapper assertion on a host that still serves
    plaintext would refuse every account-deletion erasure. B-lite ships the layout and the
    assertion in one render, so that state never exists.
- **What it costs:**
  - Once the flag is on, rollback means turning the flag off. Data stays on LUKS, and there is no
    path back to plaintext (recorded in ADR-239).
  - ADR-068 D10 is reversed.
  - The copy machinery is deferred to the first key rotation of a *populated* store.
  - The CTO asked for the pre-replace emptiness check to be enforced in the replace job. It is
    instead a fail-closed check on the host plus recorded reads, because the replace job's workflow
    is being redesigned by #8209.
- **To overrule:** say so on the PR. The plan would then return to a runtime repoint (option A),
  and would also need a separate fix for making the repoint survive a replace.

---

## DC-2: Split #8211 into two PRs; the same-version redeploy moves to PR2

**Date:** 2026-09-22
**Classification:** User-Challenge (scope). The brief asked the plan to consider splitting and
to recommend. It also listed replacing `git-data-pin-redeploy.yml` in this PR.
**Status:** applied in the plan. PR1 is the hash-bound payload and PR2 is everything else.

- **What you said:** one PR carrying the real modes, #8101's halves, and the replacement of
  `git-data-pin-redeploy.yml` by a same-version redeploy.
- **What both signals recommend:** PR1 (this branch) carries only the hash-bound payload, the ADRs,
  and your two fold-ins, the archive and the compound pass. PR2 carries the real modes, the
  same-version redeploy (rebuilt inside `.github/actions/dispatch-web-redeploy/`), the in-container
  flag proof and the ADR-237 amendment.
- **Why:** `main` has no rung-2 evidence right now, because PR #8511 deleted it and its
  re-rehearsal has not run. If PR1 lands first, one paid rehearsal covers both payload changes.
  Waiting for the full scope would cost a second rehearsal and a second interlock window. The
  redeploy replacement is not hash-bound, so it gains nothing from riding in PR1.
- **What it costs:** until PR2 merges, pin propagation still uses the forced patch release, so
  DC-2 of #8549 is open a little longer. It works today.
- **To overrule:** say so on the PR, and PR2's redeploy scope folds into this branch before ship.

---

## DC-3: Move the two fold-ins into their own knowledge-base PR

**Date:** 2026-09-22
**Classification:** User-Challenge (scope).
**Raised by:** `dhh-rails-reviewer` at plan review.
**Status:** open. The plan keeps your direction by default.

- **What you said:** fold two jobs into this PR: archiving the host-key-pinning spec directory, and
  a compound pass on that PR's ship-phase errors.
- **What the reviewer recommends:** move both into a separate PR that touches only the knowledge
  base. PR1's value is a small payload diff that can be rehearsed, reviewed at the single-user
  incident level.
- **What it costs to keep them:** a few knowledge-base files in PR1's diff. They are not
  hash-bound, so they change nothing about the rehearsal.
- **To accept:** say so on the PR, and the two fold-ins move into their own PR before ship.

---

## Operator rulings (2026-09-22)

- **DC-1:** accepted — LUKS from boot (ADR-239).
- **DC-2:** accepted — split into PR1/PR2, and hold the #8511 rung-2 re-rehearsal until PR1 merges so one rehearsal covers both.
- **DC-3:** not ruled; the fold-ins stay in PR1 as the brief directed.
