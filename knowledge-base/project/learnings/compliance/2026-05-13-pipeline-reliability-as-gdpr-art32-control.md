---
date: 2026-05-13
category: compliance
regulation: GDPR
articles: ["32(1)(d)", "12(3)"]
related_issues: ["#3704", "#3712", "#2207", "#3634"]
related_learnings:
  - 2026-05-12-pgid-inheritance-and-bash-trap-defer-on-foreground-commands.md
  - bug-fixes/2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md
  - bug-fixes/2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md
---

# Pipeline Reliability as a GDPR Art. 32(1)(d) Organizational Control

## Framing

GDPR Article 32(1)(d) requires controllers and processors to implement *"a process for regularly testing, assessing and evaluating the effectiveness of technical and organisational measures."* When the release pipeline ships code that implements data-subject rights (e.g., PR #3634 — the DSAR Art. 15+20 self-serve data-export endpoint), the **reliability of the release pipeline itself becomes an organizational measure under Art. 32**.

The 2026-05-12 #3704 incident concretized this: `Web Platform Release` stalled at 900s for v0.81.0 and v0.82.0; prod was stranded on v0.80.4 for hours. Among the versions that failed to ship was the merge containing #3634 (DSAR). The technical cause was a hung `docker pull` blocking `ci-deploy.sh`; the organizational consequence was a statutory feature delayed by a non-statutory failure mode.

**Article 12(3) was not breached.** The DSAR delivery SLA is one month from the controller's receipt of the request; an hours-long pipeline stall consumes <0.1% of that window. The Art. 32(1)(d) concern is upstream: when the pipeline's effectiveness as a delivery mechanism for rights-fulfillment code is not regularly evaluated, slow degradation can erode the organizational measure without anyone noticing until a request near the deadline triggers a real breach.

## What changes

This learning establishes the framing; the operational consequences are already in place:

1. **#3706 wrapper (`ci-deploy-wrapper.sh`)** caps `ci-deploy.sh` at 900s wall-clock with SIGTERM→20s→SIGKILL. The kill ensures the pipeline returns control to the caller (so retries/escalation can fire) rather than silently consuming the Art. 12(3) window.
2. **Workflow ceiling (`IN_FLIGHT_CEILING_S=900`)** in `.github/workflows/web-platform-release.yml` matches the wrapper exactly. The runtime assertion is the audit-trail-completeness primitive for "deploy did not progress past N seconds."
3. **`/ship` Phase 5.5 "Deploy Pipeline Fix Drift Gate"** ensures every PR that edits the pipeline triggers an operator-apply ritual at merge time. This is itself an Art. 32(1)(d) measure — it forces regular review of pipeline-handling code paths.

The compliance posture is: every release of rights-fulfillment code passes through machinery whose effectiveness is testable, time-bounded, and operator-acknowledged.

## Sharp edges (audit-trail caveats)

### SIGKILL leaves `reason=running` stale

When the wrapper's `--kill-after=20s` SIGKILLs the wrapper bash process (because the bash TERM trap was deferred during a hung `docker pull` foreground syscall, per [`2026-05-12-pgid-inheritance-and-bash-trap-defer-on-foreground-commands.md`](../2026-05-12-pgid-inheritance-and-bash-trap-defer-on-foreground-commands.md)), no trap dispatches and `write_state` is never called. The state file retains its last value — typically `reason=running, elapsed=...s`. The workflow polls and falls through to the `elapsed>900s` degraded-permissive branch, but **`/var/lib/web-platform/deploy-state.json` alone is indistinguishable from a still-running deploy.**

**For audit reconstruction:** cross-reference the state file with `journalctl -u webhook` to obtain the wrapper's wall-clock exit timestamp. The state file is not a sufficient audit record on its own when bash is SIGKILLed. The `.final` sentinel that the trap writes is the positive signal; its absence with `elapsed>900s` is the read-the-journal signal.

### Docker swap window leaves prod serving nothing

`ci-deploy.sh` lines 492–526 implement the prod swap: `docker stop` + `docker rm` of `soleur-web-platform`, then `docker run` of the new prod container. If SIGTERM (from the wrapper's wall-clock timeout) lands between `docker rm` and `docker run`, prod serves nothing on :80/:3000. This is an **Art. 32 availability** concern — not confidentiality or integrity, so it does not trigger Art. 33 notification thresholds, but it is documentable as a known-residual.

The recovery path is the next deploy attempt (workflow retry or manual operator `webhook` POST) which re-runs the script from the top. The canary on :3001 is unaffected, so health monitoring catches the gap immediately.

## `write_state` atomicity is sound

`write_state` (`ci-deploy.sh:62-85`) writes to a `mktemp` tempfile and `mv`s it onto `STATE_FILE`. POSIX `rename(2)` on the same filesystem is atomic — readers see either the prior state or the new one, never a torn write. Stdio buffering during the tempfile write is irrelevant because readers never open the tempfile.

## Cross-cutting

When the next feature implementing data-subject rights ships through this pipeline (e.g., a future Art. 16 rectification endpoint, an Art. 17 erasure flow, an Art. 21 objection-handling surface), this learning should be re-read alongside the verification contract from [`bug-fixes/2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md`](../bug-fixes/2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md). The pipeline's effectiveness is not assumed — it's verified post-apply via file-SHA + `systemctl is-active`.

## References

- **Incident:** #3704 (Web Platform Release stalled v0.81.0 + v0.82.0; v0.80.4 stranded in prod)
- **Bundled remediation:** #3712 (operator apply), #2207 (closed as superseded), #3706 (durable fix)
- **Statutory features affected by 2026-05-12 stall:** #3634 (DSAR Art. 15+20)
- **Pipeline mechanics:** `apps/web-platform/infra/ci-deploy.sh`, `ci-deploy-wrapper.sh`, `.github/workflows/web-platform-release.yml`
- **Drift gate:** `plugins/soleur/skills/ship/` (Phase 5.5)
- **Art. 30 register:** `knowledge-base/legal/article-30-register.md` (DSAR processing activity)
