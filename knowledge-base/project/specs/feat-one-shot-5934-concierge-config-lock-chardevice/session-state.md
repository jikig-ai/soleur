# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-03-infra-concierge-config-lock-chardevice-durable-fix-plan.md
- Status: complete

### Errors
- PreToolUse IaC-routing hook blocked initial plan Write twice on negative-sense trigger substrings; resolved by neutralizing phrasing + sanctioned iac-routing-ack marker.
- Deepen-plan Phase 4.5 network-outage gate false-positived on "unreachable"; reworded.
- No blocking errors. Premise held: #5934 and #5912 OPEN; PR #5907 MERGED; PR #5932 OPEN (WIP).

### Decisions
- Origin pinned to (c) — container filesystem substrate. (a) explicit repo mask and (b) SDK-driven-by-config affirmatively ruled out: agent-runner-sandbox-config.ts passes only directory paths to denyRead + allowWrite=[own workspace]; no .lock, no glob, no /dev/null mask. Answers #5934 criterion (1): single-path, not glob — de-risks #5912.
- Mount topology corrected at deepen: ci-deploy.sh:899 `-v /mnt/data/workspaces:/workspaces` means bare repos live on a persistent bind-mount, not overlay2. A visible char device causing EEXIST is a real char-special inode (rdev non-zero) on the persistent volume, not an overlay whiteout.
- Three-phase forensic-gated fix: P1 sharpen in-repo forensic (add -c/rdev/visibility to sweep_stale_git_locks, coordinated #5932-first); P2 privileged non-blind sweep in IaC with umount-before-rm in quiescent window; P3 external-substrate fallback. Not a no-op PR.
- ADR-081; `## User-Brand Impact` at single-user-incident threshold (requires_cpo_signoff: true); `## Observability`; `## Infrastructure (IaC)`; C4 no-impact.

### Components Invoked
- soleur:plan, soleur:deepen-plan; Explore (kernel research), general-purpose (verify-the-negative), architecture-strategist

## Work Phase
- Status: PAUSED — blocked on PR #5932 (operator decision 2026-07-03: "wait for #5932, then full plan").
- Resume trigger: PR #5932 (`fix(worktree): lockless atomic_git_config...`) MERGES to main.
  As of pause: #5932 OPEN, not draft, MERGEABLE, mergeStateStatus=BLOCKED (checks pending).
- Why blocked: Phase 1 edits `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
  + `plugins/soleur/test/worktree-manager-stale-lock-diag.test.sh` — the EXACT two files #5932
  refactors (+160/−19). Plan mandates #5932-first, then Phase 1 as an ADDITIVE rebase on top.
- On resume: (1) confirm #5932 merged (`gh pr view 5932 --json state,mergedAt`); (2) rebase this
  branch on the merged main so #5932's `atomic_git_config` sweep is present; (3) run `soleur:work`
  on the plan for the FULL scope (Phase 1 additive `-c`/rdev/visibility + Phase 2 privileged
  `git-lock-chardevice-sweep.sh` IaC + Phase 3 fallback if forensic proves external layer);
  (4) continue one-shot Steps 4-8 (review incl. user-impact-reviewer per requires_cpo_signoff,
  resolve findings, QA, compound, ship).
- Plan + deepened plan committed/pushed on this branch; WIP PR #5935 holds them.
