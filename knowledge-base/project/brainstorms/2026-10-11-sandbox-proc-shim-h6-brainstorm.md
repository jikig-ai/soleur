---
title: Agent sandbox shim H6 — fresh procfs refused under docker's masked /proc
date: 2026-10-11
issue: 10032
parent: 9860
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Brainstorm: agent sandbox shim fix for H6 (#10032)

Ref #9860 (never Closes: it stays open until the faithful canary passes).

## What We're Building

Make the agent Bash sandbox start again in production without weakening the cross-tenant `/proc` control.
The faithful canary has failed on every deploy since 2026-10-09: the shim's mandatory fresh `--proc /proc`
is refused with EPERM under docker's default masked `/proc`.

Evidence (Better Stack, images v0.338.7 to v0.338.10, identical): `sdk_probe rc=1 "Can't mount proc on
/newroot/proc: Operation not permitted"`, `sdk_noproc rc=0`, `direct_probe rc=0`, no `systempaths=` in `hostsec`,
AppArmor `soleur-bwrap` enforce, no caps, userns restrict=0, bubblewrap 0.8.0, docker 29.3.0.

## Why This Approach

Decision (operator, 2026-10-11): add `--security-opt systempaths=unconfined` at the three `docker run`
sites (canary and prod in `ci-deploy.sh`, first boot in `cloud-init.yml`).

- The tenant-isolation control is the pidns-scoped fresh `--proc` inside bwrap. Docker's masks never covered
  `/proc/<pid>/environ`, so lifting them does not reopen the #9723 channel (CTO, to be re-measured on the image).
- CTO measured locally under the prod flags (bwrap 0.12.0, AppArmor unconfined): the failing argv gives rc=1,
  the same argv with `systempaths=unconfined` gives rc=0, and `--tmpfs /proc` first does not help.
- Mechanism: bwrap's new user namespace inherits docker's mask mounts as locked; the kernel's "procfs must be
  fully visible" check refuses a fresh procfs (same cause as bubblewrap#284 cited in ADR-075).
- Residual: the whole shared container (not just the sandbox) loses docker's masks, so world-readable
  `/proc` entries (`timer_list`, `keys`, `interrupts`, `acpi`, `scsi`) become visible to uid 1001. Partial
  compensation: `apparmor-soleur-bwrap.profile` already denies `/proc/kcore`, `/proc/sysrq-trigger` and
  writes to `/proc/sys/kernel/*`.

Rejected:
- Procfs-free argv: the vendored `apply-seccomp /proc/self/fd/N` helper needs a pidns-correct `/proc/self`;
  a faked one gave the wrong fd table. Fixing it means rewriting the vendor command string (breaks on SDK bumps).
- Hold for topology work: keeps agent Bash down for every tenant indefinitely.
- Revert the splice: restores availability by knowingly reopening the #9723 credential channel (CLO: worst
  option, converts a passive gap into a controller-chosen exposure).

## Key Decisions

| Decision | Choice |
|---|---|
| Fix shape | `systempaths=unconfined` at the 3 docker-run sites |
| In scope | Regression test running real bwrap in docker under prod security-opts; Sentry mirror of Bash bwrap failures; stale `enableWeakerNestedSandbox` comments + ADR-075 addendum |
| Out of scope | `oom_journal_tail` / kernel-stream read for the deploy user (follow-up issue); #9886; flaky cron-egress probe rows |
| Visual design | None (no UI surface) |
| Productize candidate | None |

## User-Brand Impact

- **Artifact:** the agent Bash sandbox and its container `/proc` posture (bwrap shim, docker-run flags).
- **Vector:** a wrong fix exposes one tenant's process environment to another, or leaves every tenant's Bash failing closed with a generic error.
- **Threshold:** `single-user incident`.

## Domain Assessments

**Assessed:** Engineering, Product, Legal (Marketing, Operations, Sales, Finance, Support not relevant).

### Engineering (CTO)

Recommends shape 1; ranks procfs-free argv non-viable and the mask-without-fresh-mount shape as needing
real CAP_SYS_ADMIN (withdrawn in ADR-075) or the separate topology work (#9773). Faithful canary is
non-blocking (`ci-deploy.sh` "NON-BLOCKING dark-launch"), so prod runs the failing argv; `sdk_noproc` passes
only because `--bind / /` carries the host `/proc`. Validation: replay the canary through the shim in docker with the
repo seccomp profile and loaded AppArmor profile; add a CI job with the same posture; pin the security-opt in
`audit-bwrap-uid.sh` and the parity checks. AppArmor was `unconfined` in the local runs, so H7 is not excluded.

### Product (CPO)

Chat-only turns still work; every Bash call fails closed. The founder sees the generic "An unexpected error
occurred. Please try again." (`sanitizeErrorForClient` has no sandbox case), and retry cannot help. The Sentry
alert `sandbox-startup-failure` needs more than 2 unique users in 1 hour, which is nearly unreachable with ~1 tester.
Treat impact as presumed, not disproved. Isolation outranks availability; do not reflex-revert.
Note: the CPO's "a failed canary leaves prod on the last good image" is wrong (canary is report-only).

### Legal (CLO)

No public legal document claims anything these options would falsify (no public text mentions bwrap/procfs/seccomp;
T&C 10.2 has no SLA). No Art. 33/34 trigger on present facts (fail-closed means no spawn, so no read).
The ADR-075 addendum of 2026-10-08 says "the deny is realized, not declared", which is untrue in prod today.
Shape 1 reverses the recorded "widening, not a fix" position, so the new addendum must say so, bound the
mask-absent interval (from about 2026-10-09T04:52Z), and not claim the residual closed. Needs a new Art. 32 TOM cell
and a CLO attestation in `knowledge-base/legal/audits/`; feed the named choice into the owed #9723-window
Art. 33(5) assessment. No DPIA/LIA touch, no customer notice.

## Verified Facts (live, 2026-10-11)

- Production runs the failing image: `SANDBOX_CANARY_FAIL ... (report-only canary, never gated)` on v0.338.9 and v0.338.10.
- `SANDBOX_PROBE_OK ... rc=0` (the non-faithful probe) passes in the same deploys, so a green probe is not evidence the SDK argv works.
- Better Stack matches for `Can't mount proc` / `sandbox required but unavailable` in 24h are only webhook rows echoing #10032's text; no production-container rows. Tenant impact stays unobservable, not disproved.
- Vendored builder: `--proc /proc` when `enableWeakerNestedSandbox` is false, `--bind /proc /proc` when true (the stale comments at `agent-runner-sandbox-config.ts` ~35 and ~571 say the opposite).
- No CI job runs real bwrap under docker's masked `/proc`; `bwrap-shim.test.ts` uses a stub, `sandbox-proc-mask-runtime.test.ts` has no `--proc`, `sandbox-startup-classifier.test.ts` has no `proc` token.
- `infra/sandbox-hardening-contract.sh` is wired to nothing.

## Open Questions (parked)

1. Does `systempaths=unconfined` alone clear the failure on the real image (bwrap 0.8.0, loaded AppArmor profile)? If the faithful canary still fails after deploy, H7 (AppArmor) returns; the kernel stream is unreadable for the deploy user (`src=none`).
2. What do `Gd()` and `u5()` in the vendored gate `enableWeakerNestedSandbox:Gd()&&u5()?!1:...` check, and can it turn the flag off in prod?
3. Does the `apply-seccomp` helper's nested procfs mount still work after the fix (shim seccomp filter denies nested CLONE_NEWUSER on some hosts)?
4. Do any non-operator tenants run agent Bash in prod, and is any paying EU consumer affected (CLO attestation inputs)? Operator facts, not yet answered.
5. The change recreates the prod container on deploy: acceptable disruption window? Any production write (merge, deploy dispatch) needs explicit operator go-ahead.
6. Whether the merge waits on formal CTO and CLO sign-off artifacts (ADR-075 addendum, CLO attestation) or on this review alone.
7. (out of scope) Least-privilege kernel-stream read for the deploy user and `oom_journal_tail`: separate host-IaC issue.
