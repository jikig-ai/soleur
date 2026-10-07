## Problem

Stage 5 of the #9721 hosted-runner demand plan: a decision issue, no code. After S2 to S4 land, re-measure and decide (a) the CodeQL cost lever and (b) the runner-supply question (lever 5). Measured 2026-10-07 (6h window, runner-bound): CodeQL default setup (advisory per ADR-270, extended query suite, 4 languages) is 601 job-minutes, 521 on PR heads (about 7.0% of 7,456); the pool sits at the 60-job cap for 22% of the window's minutes (mean 21).

## Decide

1. CodeQL: query suite and event scope options; a security-posture change needs CLO/CTO sign-off and must not weaken the post-merge alert gate (ADR-270).
2. Supply, per the CTO memo `knowledge-base/project/specs/feat-one-shot-ci-hosted-runner-demand/lever5-runner-supply-memo.md`: demand levers first; Enterprise quote (price unknown, 1 seat today); larger runners only as a spend-capped flippable hybrid (not free on public repos: 4-core $0.012 per minute); ephemeral Hetzner runners last and only under the memo's security conditions (ephemeral JIT, dedicated minimal GitHub App, runner group restricted to this repo and workflows, secret-free jobs on trusted refs, own Terraform root with an R2 backend, repository-variable fallback to `ubuntu-latest`). Provision nothing without its own ADR.

Measure first: 30-day queue wait per job family, share of wall time at 55+ running, merge-queue timeouts, 30-day job-minutes by family, cancelled-minute share per event, `nproc` and runtime scaling on one shard, Hetzner quota and stock, Enterprise quote.

User-Impact: none for users; CI queue latency for contributors and the merge queue (`.github/workflows/`, `infra/github`)
Fix-Size: 0 lines / 0 files (decision only)

Re-evaluation: 30 days after the S4 decision, or when S2 and S3 both have a post-merge census.

Refs #9721
