## Problem

Stage 5 of the #9721 hosted-runner demand plan: a decision issue, no code. Once S2 and S3 each have a post-merge census (S4 is parked and does not gate this), re-measure and decide (a) the CodeQL code scanning and GitHub Code Quality cost levers and (b) the runner-supply question (lever 5). Measured 2026-10-07 (6h window, runner-bound): the dynamic CodeQL-family runs are 601 job-minutes, 521 on PR heads (about 7.0% of 7,456), and a same-window re-run splits them into two different features: CodeQL code scanning (advisory per ADR-270, about 294 job-minutes on PR heads) and GitHub Code Quality (run names "Code Quality: PR #N", about 239 on PR heads, not covered by ADR-270). The pool sits at 55 or more concurrent jobs for 22% of the window's minutes (mean 21; at the 60-job cap itself 0.6% on the re-run).

## Decide

1. CodeQL code scanning: query suite and event scope options; a security-posture change needs CLO/CTO sign-off and must not weaken the post-merge alert gate (ADR-270). GitHub Code Quality: its own switch and owner (CTO), decided separately because ADR-270 does not cover it.
2. Supply, per the CTO memo `knowledge-base/project/specs/feat-one-shot-ci-hosted-runner-demand/lever5-runner-supply-memo.md`: demand levers first; Enterprise quote (price unknown, 1 seat today); larger runners only as a spend-capped flippable hybrid (not free on public repos: 4-core $0.012 per minute); ephemeral Hetzner runners last and only under all seven of the memo's security conditions, of which ADR-276 Decision 8 is a subset (ephemeral JIT, dedicated minimal GitHub App, runner group restricted to this repo and workflows, routing derived from each workflow's triggers, secret-free jobs on post-gate but unreviewed refs, own Terraform root with an R2 backend, repository-variable fallback to `ubuntu-latest`; the memo adds the separate Hetzner project and egress deny, replaced-never-patched hosts, no persistent token, and the fork-PR approval policy raised to `all_outside_collaborators`). Provision nothing without its own ADR.

Measure first: 30-day queue wait per job family, share of wall time at 55+ running, merge-queue timeouts, 30-day job-minutes by family, cancelled-minute share per event, `nproc` and runtime scaling on one shard, Hetzner quota and stock, Enterprise quote.

User-Impact: none for users; CI queue latency for contributors and the merge queue (`.github/workflows/`, `infra/github`)
Fix-Size: 0 lines / 0 files (decision only)

Re-evaluation: when S2 and S3 both have a post-merge census (and 30 days of data since).

Refs #9721
