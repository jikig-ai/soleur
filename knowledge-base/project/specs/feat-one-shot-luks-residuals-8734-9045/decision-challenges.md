# Decision challenges — feat-one-shot-luks-residuals-8734-9045

Recorded by plan-review on 2026-09-28 (headless, under soleur:one-shot). Each item below is a
Taste or User-Challenge finding. The plan keeps its current direction, and these are surfaced for
the operator.

## 1. Split into two PRs (Taste — CTO devex)

- **Proposal:** PR-A carries docs only: the ADR-100 addendum and the three legal records. It is
  gated on the DELETE and due 2026-10-06, and merging it touches no production host. PR-B carries
  the code, Terraform, ADR-119 and the runbook, and its merge re-fires the installer on web-1.
- **Plan's current choice:** one PR. If the DELETE go-ahead comes in-session, the records commit
  after the DELETE. If it does not, the records ride a follow-up PR.
- **Why it matters:** in one PR, the code-review time decides when #8734 can close.

## 2. Refuse a post-canary `ROLLBACK=1` without an explicit write-loss override (Taste — spec-flow)

- **Proposal:** make a `ROLLBACK=1` dispatch refuse when the persisted `CANARY_OK` header UUID
  matches the live mapper, unless a write-loss override is passed.
- **Plan's current choice:** the runbook says fix-forward only. It leaves the ADR-119 §(b)
  "reconcilable" rollback available, with its cost stated. No new dispatch guard is added.

## 3. A watchdog for a SIGKILL after the host-canary disarm (Taste — spec-flow)

- **Plan's current choice:** accepted residual. An SSH drop sends SIGHUP, and SIGHUP runs the
  EXIT trap.

## 4. Name the consumer and retirement condition of the dead-man hardening (Taste — CTO devex)

- **Consumer:** the next `workspaces-luks-cutover.yml` run with `dry_run=false`, the #9045
  re-evaluation trigger. That covers a re-cut, or the fresh-host path in #6931.
- **Retirement condition:** none is proposed. The script stays the cutover channel.
