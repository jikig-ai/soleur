---
title: "A Doppler secret name was arbitrary command execution as root on the inngest host"
date: 2026-09-03
incident_pr: 7768
incident_issue: 7761
incident_window: "2026-07-08 (merge of #6218) → open; the remediation reaches the host only at the Phase 8 image build + host replace"
recovery_at: "not yet — tracked by #7761, verified by scripts/followthroughs/inngest-cutover-flip-rollout-7761.sh"
suspected_change: "#6218 (2026-07-08) — the Phase-2 cutover FSM landed inngest-cutover-flip.{sh,service} together, with the fixture seams read from the environment and the unit wrapped in a bare `doppler run --config prd`"
brand_survival_threshold: single-user incident
status: ongoing
triggers:
  - inngest-cutover-flip.service runs as root with no `User=`
  - `doppler run --config prd` with no `--only-secrets` injects the whole config
  - the script executes five environment-supplied command seams, each a legal Doppler secret name
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — no personal-data breach. This was a latent privilege-escalation PATH, not an access event: no unauthorised disclosure of, access to, alteration of, or loss of personal data occurred or is suspected. The precondition (write on soleur-inngest/prd) is held only by the operator and by two service tokens whose consumers are the host itself and a reviewer-gated GitHub environment. Re-evaluate if the Doppler activity log ever shows a write by an unrecognised principal in the window above."
---

## What happened

`inngest-cutover-flip.service` runs as **root** — it carries no `User=` — under a bare
`doppler run --config prd`, which injects the **entire** `soleur-inngest/prd` config into the
process environment. `inngest-cutover-flip.sh` reads its fixture seams straight from that
environment and **executes** several of them: `CUTOVER_REDIS_CLI_CMD`, `CUTOVER_SYSTEMCTL_CMD`,
`CUTOVER_FLAG_SET_CMD`, `CUTOVER_LOGGER_CMD`, `CUTOVER_CURL_CMD`.

Every one of those is a legal Doppler secret name. So **write access to the `soleur-inngest/prd`
config was arbitrary command execution as root** on the dedicated inngest host, at the next
30-second timer fire, inside the same unit that performs the irreversible Redis `FLUSHALL`.

Measured against live Doppler: the bare form injected 10 names, including
`INNGEST_POSTGRES_URI` — the production DSN.

The trust boundary was reasoned about as "root on the host". It was in fact "write access to a
secrets config", and those are not the same set.

## Timeline

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-07-08 | #6218 merges the Phase-2 cutover FSM: the flip script and its unit land together, seams read from the environment, unit wrapped in a bare `doppler run --config prd`. |
| agent | 2026-07-24 08:29 | `inngest-boot` service token created — **read/write** on `soleur-inngest/prd`, delivered to the host in cloud-init `user_data`. |
| agent | 2026-07-24 14:49 | `inngest-cutover-arm` service token created — read/write, held as a GitHub *environment* secret behind a required-reviewer rule. |
| human | 2026-09-02 21:34 | Operator files #7761 off an audit read of the unit. First detection. |
| agent | 2026-09-03 | Fix implemented, reviewed by a ten-agent panel, PR #7768. |
| agent | pending | Phase 8: tag → image build → digest bump → `apply_target=inngest-host` → host replace. The exposure ends here, not at merge. |

- **MTTD:** ~8 weeks (2026-07-08 → 2026-09-02). Detected by audit, by a human, not by any monitor.
- **MTTR:** open. The remediation is merged but undelivered until the host replace.

## Who could reach it

Three principals held write on `soleur-inngest/prd` during the window, and this is the honest
blast-radius statement rather than "anyone":

1. **The operator**, via the Doppler dashboard or API.
2. **`inngest-cutover-arm`** — read/write, but consumed only by CI jobs gated on the
   `inngest-cutover` GitHub environment, whose required-reviewer rule is the operator. A dispatch
   cannot resolve the secret without an approval.
3. **`inngest-boot`** — read/write, and *resident on the host itself*. It gained write in #6218 so
   the flip FSM could advance `INNGEST_CUTOVER_FLIP` on-host (`flag_set`); that is documented in
   `inngest-arm-write-token.tf` and is by design, not drift. It is the one that matters here:
   anything able to read that token on the host could write a seam secret and be executing as root
   within 30 seconds.

There is no evidence any of these was used for that. This is a reachability statement, not an
access finding.

## Why the guard did not exist

The seams were written as a **test affordance**. Under the only reading anyone applied — "these
are set by the test harness" — they are unremarkable. The failure was never in the seam
mechanism; it was that no one asked which *other* writer could reach the same channel. The
environment has two writers, not one, and the second is a secrets store whose write ACL is a
different and larger set than "root on this box".

That framing error is the whole incident. The five names are `_CMD`-suffixed and read as
internal; nothing about them announces that they are also valid Doppler keys.

## Resolution

Two halves, closing different holes:

1. **The unit bounds what is injected at all** —
   `--only-secrets INNGEST_CUTOVER_FLIP --only-secrets INNGEST_REDIS_PASSWORD
   --no-exit-on-missing-only-secrets`. Measured: 10 names → 2. This is the only half that reaches
   `BASH_ENV`, `PATH`, `LD_PRELOAD` and `IFS` — variables bash honours without the script ever
   naming them — because it filters *before* `exec`.
2. **The script gates its seams on argv** — honoured only under `--fixture-seams`, which a config
   writer cannot supply, because argv is not the environment.

`--only-secrets` alone closes the reported threat: this unit's environment has exactly two
sources, and the other is a fixed four-name `printf` of Terraform values. The argv gate is the
backstop for a bound that is *silently lost or narrowed* — `--no-exit-on-missing-only-secrets`
makes a mis-authored list quiet, and the bound lives entirely on shell continuation lines.

The unit also gained `NoNewPrivileges`, `ProtectSystem=strict`, `PrivateTmp`, `StateDirectory=`,
and the `SyslogIdentifier` it had never had (without it journald tagged the unit's stderr
`doppler`, a tag no Vector source admits — every diagnostic it wrote was dark).

A repo-wide guard (`doppler-injection-bound.test.sh`, CI-registered) now asserts that every
`doppler run` unit whose script takes a command from the environment either enumerates its
secrets or sits in a reasoned, cardinality-pinned acknowledgement list.

## Recovery verification

Not yet recovered. `scripts/followthroughs/inngest-cutover-flip-rollout-7761.sh` is enrolled in
the follow-through sweeper against #7761 (`earliest=2026-09-05`) and reads the on-host guard
revision that `emit_state` now stamps — without that stamp every observable is byte-identical to
the pre-fix script, so a replace that delivered nothing would report success.

## Where we got lucky

- **The unit was never armed.** `INNGEST_CUTOVER_FLIP` was unset for the whole window, so the FSM
  never advanced past its first state and the `FLUSHALL` never ran. Nothing about the exposure
  depended on that; it is luck, not control.
- **The hardening's own regression was caught before it shipped.** `ProtectSystem=strict` expresses
  a writable hole by bind-mounting each `ReadWritePaths=` entry onto itself, and `mountpoint(1)`
  answers from `/proc/self/mountinfo`. Adding `ReadWritePaths=/mnt/data` therefore made the FSM's
  pre-`FLUSHALL` durability gate return "mounted" for a volume that never mounted — fail-*unsafe*
  and silent, and precisely the catastrophe the latch exists to prevent. Three review agents
  converged on it independently. Had the panel been smaller it would have shipped.

## What went wrong

Almost every merge-blocking defect the review found was in the **verification**, not the fix:

- All three test suites reported their assertion floor *through* the `fail()` helper the floor
  backstops. One dropped increment silenced every assertion and the floor together, at exit 0 —
  measured: `116 passed, 0 failed` with eleven real FAIL lines uncounted.
- The committed rollout probe grepped a string its own bare-JSON rows never carry, so it could
  never PASS and its flush assertion could never FAIL — and its stub ignored `--grep`, certifying
  that 19/19 green.
- That probe's suite was registered in no runner.
- Two extractors read raw source, so a comment naming a seam satisfied the completeness tripwire —
  the exact defect the tripwire exists to prevent.
- The repo-wide guard's seam predicate missed an assignment prefix, so `cron-egress-firewall.service`
  — a root unit injecting the whole shared `soleur/prd` — escaped its population entirely.
- Six prose claims were falsified by one command each, including a mitigation that named a
  journald channel the unit had no `SyslogIdentifier` to reach.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #7761 | Deliver the fix to the host (tag → image build → digest bump → `apply_target=inngest-host` → replace) and verify via the enrolled follow-through probe. The incident is not closed until this passes. | open |
| #7775 | Four sibling `doppler run` root units still inject their whole config into scripts that exec from the environment. The live exposure is the three web-host units. | open |
| #7776 | The brand-survival threshold ladder is inverted — declaring a wider blast radius sheds five enforcement gates and adds none. | open |

## Related

- `knowledge-base/project/learnings/security-issues/2026-09-03-the-hardening-i-added-disarmed-the-guard-over-the-flushall.md`
- ADR-100 (addendum) — the bounded-injection decision and its stated limit
- `apps/web-platform/infra/doppler-injection-bound.test.sh` — the repo-wide invariant
