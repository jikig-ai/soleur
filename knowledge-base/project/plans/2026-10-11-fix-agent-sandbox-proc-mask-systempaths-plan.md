---
title: "sandbox /proc mask: production-posture CI gate and Bash sandbox-failure observability"
date: 2026-10-11
slug: fix-agent-sandbox-proc-mask-systempaths
branch: feat-sandbox-proc-shim-h6
issue: 9860
closes: []
type: fix
priority: p1
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# fix: close the gaps PR #10039 left around the sandbox /proc mask

Ref #9860 (never Closes). **Re-scoped 2026-10-11 (operator chose option A).**

## Supersession record (append-only)

The original plan (2026-10-11, reviewed by six agents) prescribed `--security-opt systempaths=unconfined` at the
three docker-run sites, an ADR-075 widening addendum and legal records for the widening. PR #10039 merged the same
day (18:29Z, after that plan was written) and fixed #10032 differently: the shim now DROPS procfs mounts so the
vendored `--tmpfs /proc` is the mask, and it measured and rejected `systempaths=unconfined` because it widens
`/proc` and `/sys` for the whole shared container. This work's lab confirms the flag is unnecessary: with the shipped
shim the canary replay passes under docker's default masks (bubblewrap 0.8.0, uid 1001, the production seccomp
profile) with no override. That plan's flag, parity pin, `MaskedPaths` audit, `masked=` diag row, ADR addendum and
CLO attestation are dropped; none of them shipped. Two facts from it survive and are recorded in
`knowledge-base/project/learnings/2026-10-11-docker-consumes-systempaths-client-side-so-an-absent-securityopt-entry-proves-nothing.md`.

## Overview

#10039 fixed the outage. Two gaps that let it ship and stay invisible remain, plus one stale comment.

- **P3 — nothing in CI runs real bwrap under docker's default masked `/proc`.** Every shim test ran on an unmasked
  host; the canary that would have caught the #9723 splice is report-only; #10039 verified in an image by hand.
- **P4 — a sandbox denial returned to the model as a Bash `tool_result` reaches Sentry as nothing.** Only thrown SDK
  errors are classified, so tenant impact of a sandbox outage is unobservable.
- **Stale comment** in `agent-runner-sandbox-config.ts` (the "kernel restriction" wording predates the shim change).

## Research Insights

- Measured in this lab (docker 29.7.2, bubblewrap 0.8.0 from the production `node:22-slim` base): a plain fresh
  `--proc /proc` under default masks fails (`Can't mount proc on /newroot/proc: Operation not permitted`) and passes
  with `systempaths=unconfined`; the shipped shim passes the canary replay WITHOUT the flag; replacing the shipped
  shim with a splicing wrapper reproduces the production verdict exactly (`sandbox_broken` /
  `bwrap_operation_not_permitted`).
- Default docker container: 28 masked paths; with the flag `MaskedPaths=[]` and `SecurityOpt=[]` (docker consumes
  the option client-side).
- Existing precedent: `sandbox-canary-regression.test.sh` section B is deliberately never-fail and runs under
  `apparmor=unconfined`; the new suite follows `workspaces-luks-loopback.test.sh` (never self-skips, literal tokens).
- `onToolResult` in `cc-dispatcher.ts` already hosts a posture-independent backstop (#5733); the mirror is a sibling.
- gdpr-gate (Art. 5(1)(c)): a `tool_result` is arbitrary command output, so the event carries only the scrubbed,
  capped matched line.

## Guard Contract

### Guard 1 — masked-/proc docker regression suite

**Property.** In a container with the production posture and docker's default masks, the historical splice shape is
refused, the shipped shim passes the canary replay, and a sibling process is invisible through the shim.

**Assembly.** One suite, one container helper (`start_container`), three arms (control, treatment, isolation) driven
against the same image; the shim under test is mounted at `/usr/local/bin/bwrap` from the repo file. Chokepoint:
`start_container` builds the production tuple minus any systempaths override; the mutation seam swaps only the
shim file or one container option.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Swap in a splicing shim (pre-#10039 behaviour) | RED (treatment replay `sandbox_broken`, isolation errors) |
| 2 | Bypass the shim for the isolation arm | RED (sibling VISIBLE, pid dirs listed) |
| 3 | Remove the docker masks from the control container | RED (control must be refused; a runner without masks proves nothing) |
| 4 | Start the sibling after the sandbox spawns | RED (no sibling before spawn; discrimination arm sees nothing) |
| 5 | Replace the replay with a stub printing `{"verdict":"pass"}` | RED (non-vacuity requires the replay's `reason` and the fixture's `sdkVersion`) |

**Harness rows.** Unusable docker, AppArmor or sysctl fails with a literal token and exit 1, never exit 0; the
anti-vacuity floor `MIN_ASSERTIONS=8` sits on the line above its `if`.

**Anchor.** None stored: the suite compares live arms, so it proves discrimination rather than consistency.

## Implementation (in this PR)

1. `sandbox-startup-classifier.ts`: `classifyBashSandboxFailure` (+ tests on bwrap's real stderr text, scrub and cap).
2. `cc-dispatcher.ts`: exported `mirrorBashSandboxFailure`, called from `onToolResult` before the posture gate (+ test).
3. `sandbox-masked-proc-docker.test.sh` + the `infra-validation.yml` sudo step + `PRIVILEGED_WHY` entry.
4. Comment fix in `agent-runner-sandbox-config.ts`.

## Files

Edit: `apps/web-platform/server/sandbox-startup-classifier.ts`, `apps/web-platform/server/cc-dispatcher.ts`,
`apps/web-platform/server/agent-runner-sandbox-config.ts`, `apps/web-platform/test/sandbox-startup-classifier.test.ts`,
`.github/workflows/infra-validation.yml`, `apps/web-platform/infra/run-registered-suites.sh`.
Create: `apps/web-platform/infra/sandbox-masked-proc-docker.test.sh`,
`apps/web-platform/test/server/cc-dispatcher-bash-sandbox-mirror.test.ts`.

## Acceptance Criteria

- [x] Classifier and dispatcher-mirror unit tests green, including the data-minimisation case.
- [x] Docker suite baseline passes in the production-posture container (apparmor-unconfined local override) and
  four of the five mutations go RED; the fifth (stub replay) is closed by the strengthened non-vacuity assertion.
- [ ] The suite passes in `infra-validation.yml` under `sudo` with the real `soleur-bwrap` AppArmor profile loaded
  (only CI can show this; a failure there means AppArmor, not the docker masks, is the lab difference).
- [ ] `lint-orphan-test-suites.sh`, typecheck and the affected-test gate green.
- [ ] PR body uses `Ref #9860`, never `Closes`.

## Risks

- **AppArmor half is unproven locally.** This dev host has no AppArmor; the suite's local override measures the
  docker-mask delta only. CI is the AppArmor-faithful lab. If the CI run fails with AppArmor loaded, that is a real
  finding about prod (H7), not a suite defect to be worked around.
- **Docker-daemon and sudo dependence** in `deploy-script-tests-fixed`; the suite fails loudly rather than skipping.
- **Bash stderr matching** across bubblewrap versions is brittle; the unit test pins real stderr text.
- The paging alert for the new Sentry event stays a follow-up (#10052, blocked on #7985).
