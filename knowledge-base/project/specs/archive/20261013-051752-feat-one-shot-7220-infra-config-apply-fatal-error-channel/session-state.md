# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-08-03-fix-infra-config-apply-daemon-reload-denied-fatal-channel-plan.md
- Status: complete

### Errors
- Two `Write` calls blocked by the `hr-all-infrastructure-provisioning-servers` PreToolUse hook (flagged `systemctl` in prose). Phase 2.8 genuinely satisfied — the grant ships via Terraform + cloud-init, no operator step exists — so the sanctioned `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` opt-out was added to both artifacts with an explicit rationale block.
- `scripts/betterstack-query.sh --since` rejects the `Z`-suffixed ISO form its own header advertises. Worked around, then eliminated by switching prescribed commands to `--since 1h`. Deferred as issue D1.
- First-draft plan defects caught by the 6-agent review panel, most seriously `threshold: none` on a change that activates a deploy->root escalation chain. Recorded as R1-R20 rather than silently corrected.

### Decisions
- Root-caused from measurement, not inference. Three issue premises falsified; both enumerated suspects mechanically refuted. Verified a second time by the parent pipeline via an independent Better Stack pull on request id `86ea60`.
- Ships as two PRs: PR-A (instrument, zero privilege change) then PR-B (privilege), making "instrument before fix" a deployment ordering rather than an authoring one.
- Threshold raised `none` -> `single-user incident`; a blocking shape-gate AC now precedes the sudoers grant.
- Two measured P0s changed the design: an ERR trap stays armed during the EXIT trap (`exit 0` -> rc=1), and an unset expansion under `set -u` makes the trap write no frame at all.
- Declined the operator-gated `terraform apply -replace` with artifact-backed evidence; the guardrail against it is now required in the CI annotation.

### Components Invoked
- Skills: `soleur:plan`, `soleur:plan-review`, `soleur:deepen-plan`
- Review panel: dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer, cto
- Research: Explore x4, learnings-researcher
- Tooling: `scripts/betterstack-query.sh` (read-only via Doppler `prd_terraform`), `gh run view --log-failed`, `git log -S`, Monitor

## Review Phase — DEGRADED (0 of 11 agents)

All 11 review agents terminated on the same API error: `You've hit your session limit,
resets 9pm (Europe/Paris)`. Not a transient 529 — retrying before the reset produces the
same failure, so partial coverage was not recoverable in-session.

A degraded inline review ran in the main context and found 2 findings, both fixed inline
(commit 0df264e10). Independently verified during that pass: the Vector allowlist carries
`infra-config-apply` (vector.toml:152); the gate's suppression is message-only (rc=1 with
and without fatal_line); `cat-infra-config-state.sh` tolerates the new keys; no arithmetic
site can spuriously fire the ERR trap; `ship-deploy-pipeline-fix-gate.test.ts` 107/0.

**Status: NOT READY TO SHIP.** The plan declares `brand_survival_threshold: single-user
incident` and this diff rewrites the EXIT trap of a webhook handler on a `cx33` host that
cannot be re-provisioned. `review/SKILL.md` Gate 2a forbids marking a PR ready on that
threshold with zero agents, and #7146 is the precedent: a 0-of-10 degraded review shipped
and the re-run found ~60 findings, 15 P1, 3 merge blockers.

One agent (user-impact) reported `PROBE A found something` before dying. That finding was
never retrieved. The review is not merely thin — it is thin with a KNOWN unretrieved
finding on the highest-risk lens.

**SUPERSEDED — the panel was re-run and all 11 agents reported.** See below.


## Review Phase — RE-RUN, 11 of 11 agents

All 11 agents were resumed from their transcripts (context intact) once the session limit
cleared, so the unretrieved `PROBE A` finding was recovered rather than guessed at.

They found five P1s, all PR-introduced, all now fixed and mutation-proven:

1. A death AFTER the frame publish read GREEN. The webhook self-restart is a second ungranted
   `sudo` running past `.final`; the published frame still said `exit_code:0` and the gate
   adjudicates on that first. #7220's shape relocated ~200 lines later, invisible to the
   instrument built for it.
2. A routine partial apply INVENTED a death (`FATAL: line=0 rc=1 cmd=`). That is the documented
   #4804 self-heal, and the soak hard-FAILs on `line=0`, so a normal apply would have reported
   #7220 as unfixed.
3. The soak probe returned PASS against a host that was dying, and the sweeper auto-closes on
   exit 0 — it would have closed #7220 while #7220 was happening. Verified live before and after:
   PASS -> FAIL with an accurate reason.
4. The operator issue was titled "Security profile (seccomp) not enforced" — a fabricated
   security claim, a remediation that loops forever, a dedupe key that lets a seccomp incident
   swallow this alert, and Sentry paging the security rule.
5. The alert contradicted the gate on 000/502/503, telling the operator not to pull the exact
   lever the gate had just prescribed.

Root cause of 1 and 2 was one mistake: `.final` was never the question. "Did it DIE" is.

Mutation-proven: reverting the `died` predicate either way reds, as do dropping frame
preservation, dropping the ownership gate, hardcoding the annotation, hardcoding files_written,
and deleting the fatal branch's rc=1. Six of those passed a green suite beforehand. Both suites
gained assertion-count floors — deleting the new arms previously left both exiting 0.

Rebased onto main (9 commits, incl. #7197's 482-line suite growth). Registered infra suites
88/88. An earlier RED on `git-data-runcmd-rehearsal` was the stale suite version on an
un-rebased branch, not this diff — confirmed by A/B against pristine main.
