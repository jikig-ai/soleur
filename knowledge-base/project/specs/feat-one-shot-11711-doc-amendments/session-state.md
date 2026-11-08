# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-08-docs-key-rotation-dispatch-ruling-amendments-plan.md
- Plan artifact: complete (selector=branch)
- Status: complete

### Errors
- collision-precheck.sh self-hit on own draft PR #12391 (expected, not a duplicate)
- proc.sh sibling-session check could not run (exit 1) — disclosed in plan Premise Validation

### Decisions
- Runtime-prose sweep included as inferred scope (scripts/inngest-key-rotate.sh, scripts/key-rotate.sh, inngest-a5-a6-owner-ask-10136.sh + pinned test)
- Second stale claim found: inngest-server.md calls infra-privileged "required-reviewer approval"; live env has branch_policy only — corrected under ask (g)
- A5 reviewer click stays owner-human only; dispatch authority = fresh per-command in-session go
- Frontmatter issue: 11711 with NO closes: — PR body must say "Ref #11711" (epic rows remain)
- No prose-drift lint shipped (CTO-ruled)

### Components Invoked
- soleur:plan, soleur:deepen-plan (sequential-fallback in subagent), gh api env checks, collision-precheck.sh

## Post-Plan Re-probe (2026-11-08)
- #11711 OPEN; linked:issue → PR #12387 OPEN (feat-one-shot-11294-clo-reassessment — different scope/files, sibling session on CLO item; NOT a collision)
- in:body open probe: only #12387
- Anchor probe over planned edit set: zero open PRs touch the files
- Overlap preflight: exit 0 (prs=none) at start; will re-run --files pre-merge

## Sibling work (main context, not this PR)
- #12392 filed: kk_cmd_clear readback race (meta/machinery)
- Rescan in progress: 173 post-census run logs + 96 infra-drift issues for residual raw random_id lines
- Found: 4 comments on #10835 with raw random_id values still live (missed by 2026-11-01 redaction)

## Operator Constraints

- constraint: Agent may dispatch key-rotate.yml/inngest-key-rotate.yml rotate|converge ONLY under a fresh, per-command, in-session owner go naming the exact full command (CTO ruling). The reviewer click (key-rotate-approval env, deruelle) is NEVER delegated.
- constraint: The approval tap should land inside a measured release-quiet stretch - apply re-checks in-flight itself, so a parked run CAN still refuse post-approval.
- constraint: Merge queue is slow (~2-8h/PR under churn). Armed PRs can silently drop from the queue with a stale autoMergeRequest - disarm+re-arm to re-enqueue. Commits MUST author as jean.deruelle@jikigai.com (cla-check). pr-body-vs-diff: file paths outside backticks must >=50% appear in the diff.
- constraint: File work only in linked worktrees (worktree-manager.sh create) - never the bare root.

## Technical-Ruling Gate
- technical-ruling-gate.sh --branch: PASS (6 rows; fixed one bad-ruling-shape — missing date on the dispatch ruling row)
- cto_spawns=0 (rulings recorded inline via sequential-fallback; dispatch ruling itself predates this PR)

## Work Phase Complete (2026-11-08)
- All tasks.md items done; 14 files changed, +683/-31, commit 0efcdeda84 pushed
- AC1 stale-claim grep: clean (2 hits are the supersession notices themselves)
- Suites: followthroughs test 180/180, key-rotate-workflow 647/647, inngest-key-rotate-workflow 478/478 — all green
- Env split re-verified live: key-rotate-approval=[required_reviewers,branch_policy]; infra-privileged=[branch_policy]
- Draft PR #12391; branch feat-one-shot-11711-doc-amendments

## Review Phase (in progress)
- Class: code (.sh files in diff -> 8-seat panel); design-risk: no (prose-only, no new mechanism)
- Seats spawning on pushed sha 0efcdeda84

## Main-context parallel work (#11711 residual items 2-6)
- #12392 filed (readback race, meta/machinery)
- Rescan findings so far: 4 comments on #10835 carry RAW random_id values (missed by 2026-11-01 redaction: comments 6504678183, 6508410298, 6516152486, 6529976974); 28+ post-census run logs show HIT-REFRESH raw lines (list: /tmp/rescan-11294/hits.txt); drift-scan v2 re-running (v1 stdin-consumption bug)
- Artifacts: repo-level endpoint still HTTP 500 — per-run probe needed (inngest-provision-rehearsal only)
- CTO ruling spawned for inngest-host dedicated pair (agent_id=49c594db)
- Deletions NOT yet executed — operator per-command go required; census-11294.tsv NOT found on this filesystem (operator scratch)

## Review Round 1 — seats returned (as of this entry)
- Seats returned: architecture (58ded3b2), code-simplicity (462335b2), data-integrity (707d58ec), pattern-recognition (15cb243d), security-sentinel (b5bac131), performance-oracle (9db050d8)
- Seat died on harness rate-limit: test-design (f197054e) — check covered inline by lead (expect-rows verified byte-exact; suite 180/180)
- Seat still running: git-history (26f5e16e)
- P1 (4 seats converged): scripts/key-rotate.sh kk_stop_tail (:368-369) still printed "(no agent dispatches a rotate)" into stop sentences + filed action-required issues — FIXED (both arms reworded to the ruling convention)
- P1 (pattern-recognition): plugins/soleur/skills/brainstorm-techniques/references/technical-ruling-delegation.md:188 taught "credential-rotation dispatch stays the owner's own" — FIXED with the 2026-11-08 carve-out
- P2 (3 seats): ADR-307 amendment heading inserted inside the Corrections bullet list — FIXED (heading moved below the unverified bullet)
- P2 (security): actor_not_owner remediation cell is an identity check — FIXED ("dispatch as the owner's login (the committed allowlist)")
- P3s taken: inngest-key-rotate.yml header tap clause added; standing-delegation.md:446 tightened to ruling conditions; qualifier alignment (fresh/per-command/in-session/exact) on stop sentences + probe ask; ADR-317 env-split reduced to pointer; converge-route qualifier in key-rotation.md env split; model.c4 :814 (apply AND clear jobs; ADR-314→ADR-317) + :596 ruling clause
- P3s declined: collapse ADR-317 verbatim ruling quote (ADRs stand alone; plan prescribed verbatim), de-duplicate key-rotation.md restatements (runbook belt-and-suspenders convention), learnings-file dated claim (verbatim history)
- AC1 grep widened (added no-agent-dispatch/agent-dispatches/only-you-dispatch/required-reviewer-approval variants + case-insensitive superseded check); residual hits all intentional supersession quotes, test unwant-needle, or unrelated subjects
