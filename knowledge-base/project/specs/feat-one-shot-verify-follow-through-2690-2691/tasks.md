# Tasks: Verify admin-ip-refresh no-drift and SSH hypothesis gate

**Plan:** [2026-04-22-chore-verify-admin-ip-refresh-and-ssh-hypothesis-gate-plan.md](../../plans/2026-04-22-chore-verify-admin-ip-refresh-and-ssh-hypothesis-gate-plan.md)
**Issues:** Closes #2690, Closes #2691
**Branch:** feat-one-shot-verify-follow-through-2690-2691

## Phase 1: Setup

- [ ] 1.1 Confirm worktree is on branch `feat-one-shot-verify-follow-through-2690-2691`
- [ ] 1.2 Confirm `doppler` CLI authenticated (`doppler configure get token --plain` returns a token)
- [ ] 1.3 Confirm `curl` on PATH
- [ ] 1.4 Confirm operator is using a user token, not a service token (service tokens lack `prd_terraform` read)

## Phase 2: Verify #2690 (admin-ip-refresh dry-run)

- [ ] 2.1 Invoke `skill: soleur:admin-ip-refresh` with args `--dry-run`; capture stdout, stderr, exit code (or observability note if in-conversation)
- [ ] 2.2 Inspect output for "No drift" substring (either full prescribed format from procedure:75 or short form from SKILL.md:40)
- [ ] 2.3 If drift detected: HALT, file priority/p1 remediation issue (egress IP REDACTED), do not proceed to issue close
- [ ] 2.4 If SKILL.md/procedure format drift detected (third format): file follow-up alignment issue
- [ ] 2.5 Transcribe redacted output into learning file `## #2690 Verification` section — egress rendered as `<redacted>/32`, list length preserved

## Phase 3: Setup Phase 4 isolation

- [ ] 3.1 Create sibling worktree on non-`feat-*` branch:
    `bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh --yes create tmp/verify-ssh-gate`
- [ ] 3.2 `cd` to the new sibling worktree path
- [ ] 3.3 Verify `git branch --show-current` returns `tmp/verify-ssh-gate` (not prefixed with `feat-`)

## Phase 4: Verify #2691 (plan + deepen-plan SSH hypothesis gate)

- [ ] 4.1 Construct contrived feature description (verbatim): `fix: intermittent SSH connection reset when deploying to soleur-web-platform from GitHub Actions runner`
- [ ] 4.2 From the sibling worktree, invoke `skill: soleur:plan` with the contrived input
- [ ] 4.3 Capture the resulting plan file path from the skill's announce
- [ ] 4.4 Verify Save Tasks was skipped (non-`feat-*` branch should skip per plan/SKILL.md:499-501)
- [ ] 4.5 Read the throwaway plan's `## Hypotheses` section
- [ ] 4.6 Confirm all L3-keyword hypotheses (`hcloud firewall describe`, `ifconfig.me`, `var.admin_ips`, `dig`, `traceroute`, `mtr`) appear at EARLIER list indices than any service-layer hypothesis (`sshd`, `fail2ban`, `sshguard`, `journalctl -u`)
- [ ] 4.7 If L3 ordering violated: FAIL, file priority/p1 regression issue tagged `domain/engineering`, do not close #2691
- [ ] 4.8 Invoke `skill: soleur:deepen-plan` with the throwaway plan path
- [ ] 4.9 Grep deepened plan for substring `Network-Outage Deep-Dive` (subsection heading); confirm Phase 4.5 fired
- [ ] 4.10 Transcribe throwaway plan's `## Hypotheses` excerpt + Network-Outage Deep-Dive subsection excerpt into learning file `## #2691 Verification` section

## Phase 5: Cleanup sibling worktree

- [ ] 5.1 `cd` back to `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-verify-follow-through-2690-2691`
- [ ] 5.2 Remove sibling worktree: `git worktree remove <sibling-path> --force`
- [ ] 5.3 Delete branch: `git branch -D tmp/verify-ssh-gate`
- [ ] 5.4 Verify `git worktree list` no longer shows `tmp/verify-ssh-gate`
- [ ] 5.5 Verify THIS branch's `knowledge-base/project/specs/feat-one-shot-verify-follow-through-2690-2691/tasks.md` is unchanged (`git diff tasks.md` returns empty)

## Phase 6: Document and commit

- [ ] 6.1 Write learning file at `knowledge-base/project/learnings/2026-04-22-follow-through-admin-ip-refresh-and-ssh-gate-verification.md` with sections: `## #2690 Verification`, `## #2691 Verification`, `## Methodology` (sibling-worktree isolation pattern)
- [ ] 6.2 Run `npx markdownlint-cli2 --fix` on the learning file and plan file (specific paths only, per `cq-markdownlint-fix-target-specific-paths`)
- [ ] 6.3 Run `bash scripts/test-all.sh`; ensure no regressions
- [ ] 6.4 Run `skill: soleur:compound` to capture the verification methodology as institutional knowledge
- [ ] 6.5 Invoke `skill: soleur:ship` with PR body containing `Closes #2690` and `Closes #2691` on separate lines (or `Ref #2690 #2691` + linked regression issues on failure)

## Phase 7: Post-merge

- [ ] 7.1 After merge, #2690 and #2691 auto-close via PR body (if pass) — verify in `gh issue view`
- [ ] 7.2 If either verification failed: source issues stay OPEN, regression issue linked for tracking
