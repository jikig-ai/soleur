---
title: Worktree cleanup — Docker builder cache and /var/tmp scratch drain
issue: 9677
branch: feat-docker-var-tmp-worktree-cleanup
pr: 9690
lane: cross-domain
brand_survival_threshold: single-user incident
date: 2026-10-07
---

# Brainstorm: Worktree cleanup — Docker builder cache and /var/tmp scratch drain (#9677)

## Lane

`cross-domain` (forced by Phase 0.1 user-brand-critical default; CPO + CLO + CTO consulted).

## What We're Building

Make the session-start cleanup actually free disk on a dev host, in the smallest safe increment:

1. **Docker builder-cache prune, opt-in.** `SOLEUR_DOCKER_PRUNE=1` prunes only build cache and dangling images; dry-run unless `=apply`. Never `-a` images, containers or volumes. One `SOLEUR_DOCKER_PRUNE ...` log line with bytes reclaimed. Absent `docker` is a clean skip.
2. **Session-start quarantine drain.** `sweep_orphan_scratch_dirs` also drains expired quarantine entries (7 d scratch / 30 d worktrees TTL) inside its existing 10 s timebox and `flock`. Amends ADR-250.
3. **Producer exit-cleanup.** Marker writers that leak (`gdboot.*` from `scripts/lib/git-data-boot-signal-poll.sh`, 44 of 71 marked dirs) clean up at exit through the ADR-250 allocator.
4. **Root-cause measurement** of why marked dirs survive the sweep, recorded in the PR with numbers.
5. **Effective-space report.** Cleanup prints logically reclaimed bytes next to the measured `df` delta, and one line naming btrfs + snapper snapshot pinning when detectable (read-only; snapshots never touched).
6. **Operator host:** install `tmpfs-guard.timer` per the runbook (separate operator action, not plugin behaviour).

## Why This Approach

- Docker held ~4 GB of the ~17.6 GiB the operator freed; **snapshots pinned most of it** (issue evidence). Reporting effective space is worth more than a bigger prune.
- The sweep already exists (ADR-250). The gap is that it only *quarantines* marker dirs on disk bases and the drain has no installed trigger, plus a producer that leaks one marked dir per run.
- The plugin runs on customers' machines. A global prune is high blast radius (shared daemon, Supabase/test images) and legally/brand-wise worst-case, so destructive Docker behaviour is opt-in.

## Key Decisions

| Decision | Choice | Source |
|---|---|---|
| Docker scope | Builder cache + dangling only, opt-in, dry-run default | User answer; CPO, CTO, CLO converge |
| Label-scoped prune | Dropped for now: no `docker build` call site stamps a worktree label (the only `--label` is the CI inngest-bootstrap build). Local-host builders do exist (`plugins/soleur/skills/deploy/scripts/deploy.sh`, `apps/web-platform/infra/cloud-init-plugin-seed.test.sh`, `apps/web-platform/scripts/sandbox-canary-regression.test.sh`), so stamping a label there is a possible later step | Re-derived by orchestrator (CTO said "all CI"; that was inexact) |
| Scratch drain | Session-start drain **and** producer exit-cleanup **and** timer on operator host | User answer ("3 and 4") |
| PR scope | Core + df/snapper report; defer worktree-stamped markers and unmarked-dir report | User answer |
| ADR | Amend ADR-250 (drain trigger moves to session start; producer cleanup) | CTO |
| Opt-in var naming | `SOLEUR_DOCKER_PRUNE=1` (existing convention is `SOLEUR_DISABLE_*`; opt-in is deliberate for destructive default-off) | Repo research |
| Productize Candidate | none | — |

## User-Brand Impact

- **Artifact:** `worktree-manager.sh cleanup-merged` session-start sweep (Docker prune + scratch drain), which runs on every machine with the Soleur plugin.
- **Vector:** a prune or drain deletes images or files a user wanted and did not ask to lose, silently and unrecoverably.
- **Threshold:** `single-user incident`.

## Premise Verification (measured 2026-10-07)

- ADR-250 already governs scratch reclamation; the issue's item 2 is a "why does it not fire" question, not greenfield.
- Marked dirs now: 71 (66 dead owner, 5 live), not the issue's 131/128 — the operator cleaned up since; 68 of 71 are under the 24 h age gate. Breakdown (CTO): `gdboot.*` 44, `soleur-run.*` 12, `soleur-inc-*` 10, `soleur-sbx.*` 4. All carry the host's pid namespace, so ns mismatch is not the cause here.
- `/var/tmp/soleur-quarantine.{0,1000}` hold 142 MB across 21,549 nested entries (2,103 + 19,446 by `find -mindepth 1`; repo research's "3,984" did not reproduce); no `tmpfs-guard` timer or crontab exists on this host (matches the 2026-09-24 learning).
- Docker now: 17 images (317 MB reclaimable), build cache ~0. Operator already pruned.
- Test coverage of the sweep is only inside `tests/scripts/test-scratch-session.sh`; no fake-shim pattern for `docker`/`findmnt` exists yet.
- Hook point: after `git worktree remove` at `worktree-manager.sh:3835`; no dedicated post-removal seam.

## Open Questions

- Which survivors are age-gate-only versus genuinely stuck (needs dry-run with `SOLEUR_PURGE_DRY_RUN`)? Resolve in plan.
- Should session-start drain share the existing 10 s timebox or get its own budget? (plan)
- Layer-7 observability: new `SOLEUR_*` markers run on customer CLIs; reviewer to confirm they stay stdout-local (CLO: must not egress, Privacy Policy line 65).
- (out of scope) Operator-side snapper `NUMBER_LIMIT` tuning — host config, not code.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering
**Summary:** Label-scoping is infeasible today; builder-cache-only is the safe Docker slice. Items 2 and 4 are one mechanism (scratch with no drain); item 3 is a cross-consumer marker-schema change; item 5 is independent. Amends ADR-250.

### Product
**Summary:** Default-off for non-operator users, dry-run first. YAGNI: defer unmarked report and agent-guidance; keep root-cause measurement and df delta. Minimum increment stops the operator's disk filling.

### Legal
**Summary:** Nothing material; no `gdpr-gate`. Constraint: markers stay local (Privacy Policy line 65 "does not phone home"); report-only by default off-operator, Soleur-owned scope only, snapshots read-only.

## Capability Gaps

None reported.
