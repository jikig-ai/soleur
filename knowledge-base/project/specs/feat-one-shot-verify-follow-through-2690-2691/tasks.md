# Tasks: Verify admin-ip-refresh no-drift and SSH hypothesis gate

**Plan:** [2026-04-22-chore-verify-admin-ip-refresh-and-ssh-hypothesis-gate-plan.md](../../plans/2026-04-22-chore-verify-admin-ip-refresh-and-ssh-hypothesis-gate-plan.md)
**Issues:** Closes #2690, Closes #2691
**Branch:** feat-one-shot-verify-follow-through-2690-2691

## Phase 1: Setup

- [ ] 1.1 Confirm worktree is on branch `feat-one-shot-verify-follow-through-2690-2691`
- [ ] 1.2 Confirm `doppler` CLI authenticated (`doppler configure get token --plain` returns a token)
- [ ] 1.3 Confirm `curl` on PATH

## Phase 2: Verify #2690 (admin-ip-refresh dry-run)

- [ ] 2.1 Invoke `/soleur:admin-ip-refresh --dry-run`; capture stdout, stderr, exit code
- [ ] 2.2 Inspect output for "No drift" string and exit code 0
- [ ] 2.3 If drift detected: HALT, file remediation issue, do not proceed to issue close
- [ ] 2.4 If no drift: transcribe output (REDACTING egress IP and ADMIN_IPS CIDRs, keeping only list length) into learning file `## #2690 Verification` section

## Phase 3: Verify #2691 (plan + deepen-plan SSH hypothesis gate)

- [ ] 3.1 Construct contrived feature description: `"fix: intermittent SSH connection reset when deploying to soleur-web-platform from GitHub Actions runner"`
- [ ] 3.2 Invoke `skill: soleur:plan` with the contrived input; capture resulting plan file path
- [ ] 3.3 Move plan artifact to `/tmp/2691-verification-plan.md`; ensure it is NOT committed under `knowledge-base/project/plans/`
- [ ] 3.4 If `plan` also created a `knowledge-base/project/specs/feat-*/tasks.md` under this branch, git-reset and delete it
- [ ] 3.5 Grep `/tmp/2691-verification-plan.md` `## Hypotheses` section for L3-first ordering (firewall allow-list + DNS/routing before sshd/fail2ban/service-layer)
- [ ] 3.6 Invoke `skill: soleur:deepen-plan` against `/tmp/2691-verification-plan.md`
- [ ] 3.7 Grep the deepened plan for "Network-Outage Deep-Dive" subsection heading
- [ ] 3.8 Delete `/tmp/2691-verification-plan.md` after transcription
- [ ] 3.9 Transcribe contrived input, hypothesis excerpt, and deep-dive subsection confirmation into learning file `## #2691 Verification` section

## Phase 4: Document and close

- [ ] 4.1 Write learning file at `knowledge-base/project/learnings/<topic-slug>.md` (directory + topic per `sharp-edges` rule — author picks date at write-time)
- [ ] 4.2 Run `npx markdownlint-cli2 --fix` on the learning file and plan file (specific paths, not globs)
- [ ] 4.3 Run `bash scripts/test-all.sh`; ensure no regressions
- [ ] 4.4 Run `skill: soleur:compound` to capture the verification methodology
- [ ] 4.5 Invoke `skill: soleur:ship` with PR body containing `Closes #2690` and `Closes #2691`

## Phase 5: Post-merge

- [ ] 5.1 After merge, comment on #2690 with verification date, exit code, list length (CIDRs redacted). Close via PR auto-close.
- [ ] 5.2 After merge, comment on #2691 with verification date, contrived input, transcript links. Close via PR auto-close.
- [ ] 5.3 If either verification failed: keep #2690 / #2691 OPEN, file a new `priority/p1` issue tagged `domain/engineering`, reference the regression from source issues.
