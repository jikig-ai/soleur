# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/archive/20260911-230120-2026-09-10-fix-git-data-hash-bound-hardening-batch-plan.md
- Status: complete (plan + plan-review + deepen-plan 2026-09-11)
- Plan artifact: recovered (selector=branch) — planning subagent hit an API rate limit mid plan-review corrections; resumed from transcript and finished.

### Errors
- Rate-limit interruption during final correction pass; on resume, Kieran P0-2 was already on disk and P0-4's residual was applied.
- deepen-plan not run by the planning subagent (coordinator over-broad "do not re-run" instruction on resume) — scheduled as its own pass.
- Kieran P1-2 and P1-3: RESOLVED at deepen-plan (P1-2: set-equality assertions (a)(b)(c) + rows 5b-5d + FR11b; P1-3: probe is now the Guard 5 suite with FR13's row label; `credentials_required` removed because Check 10 treats any non-placeholder value as SKIP-DECLARED).
- Brief's claim that the inngest-bootstrap drift-guard is red on main did not reproduce (163/163 locally); recorded as unreproduced.
- One research citation path corrected; plan-write guard `iac-routing-ack` added with truthfulness note.

### Decisions
- Delete the void rung-2 evidence file (never edit it): keeps birth gate HOLD and CI freshness step dormant; new Guard 4 enforces.
- F11 fleet decision: git-data only. web host has ignore_changes=[user_data]; inngest/registry are ForceNew on live hosts. Follow-ups filed.
- Four of six fixes redesigned against measurement (mountpoint rc on healthy host; F7 ownership chain root:git 0750; AcceptEnv pin cut; sshd -T before unit action, emit on sshd_config_warn which this PR also routes).
- Erasure outcome token and daemon-timestamp assertion cut; app layer still reports success on refusal — cutover-deadlined follow-up.
- UC-1 recorded in decision-challenges.md: drop the betterstack-query.sh --table fix from this PR (operator-requested scope; never auto-applied).

### Components Invoked
- Skills: soleur:plan, soleur:plan-review, soleur:deepen-plan
- Agents: repo-research-analyst, learnings-researcher, cto, clo, dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer, cpo; deepen-plan: verify-the-negative sweep (sonnet), learnings-researcher, test-design-reviewer
- Lints: lint-guard-contract.py, lint-infra-no-human-steps.py, c4-count-parity.test.sh, git-data-userdata-budget.sh, cloud-init-inngest-bootstrap.test.sh

## Deepen Phase
- Status: complete (separate subagent pass)
- P1-3 resolved: `--help` probe replaced by `tests/scripts/test-betterstack-query-archive.sh` row label; credentials_required removed (was a SKIP-DECLARED waiver).
- P1-2 resolved: Guard 2 gains three set-equality assertions + mutation rows 5b–5d; `gc_timer` pages via fatal rule — pinned as exception, filed FR17/FR11b.
- Guard 4 tier corrected: birth-time arm inside git_data_rung2_rehearsal_gate (fetch-depth: 0) + advisory PR-range arm; residual to #8010.
- Verify-the-negative sweep 13/14; two corrections (issue-alerts.tf removed+import pair; F10 is five AcceptEnv sites across three files).
- Test-design findings folded; Guard 5 refusal pinned at exit 64 + stderr naming BS_TABLE.

## Work Phase
- Status: complete. Work-phase HEAD was a60ce8361 (12 commits over origin/main); the review pass below rebased onto origin/main c786c3e0f and adds one commit.
- RUNG2_TEMPLATE_SHA256 moved by design (was 3a2392fb…, 13 bound files); ship RE-DERIVES it for the PR body (`git_data_rung2_user_data_sha256`) rather than copying any figure here. Evidence file DELETED, never edited.
- Byte budget on the review-pass tree: stored 15320 B / cap 32768 (headroom 17448).
- FR18 done (#8043 body), FR19 done (roadmap L27; #7025 p3→p1), mapper gate commented on #5274.
- FR17 filed after CONCUR (no dissent): #8093 tracker (4 deferrals), #8094 app-layer boundary, #8095 web-host retention window, #8096 inngest false attestation.

## Review Phase
- Status: complete. Ten report-only seats (git-history, agent-native, user-impact, observability, security, pattern-recognition, data-integrity, structural enumeration, test-design, code-quality) + design-validity pass (simplicity + architecture) earlier.
- P1 ×2 (code-quality): merge conflict on `guard-vacuity-floor.test.sh` PROMOTED_FILES (union-resolved on rebase); `test-git-data-rung2-evidence-capture.sh` 78/1 — ARM 1 HOLDs a fixture outside a git tree → fixture is a repo, evidence committed ALONE, 80/80.
- P2 fixed inline: advisory provenance step moved to the END of deploy-script-tests (it hid nine guards on HOLD); transport wrapper gains Guard 1 (mount + containment), `.cutover-freeze`, and `git -c core.hooksPath=` pin (repo-local override measured to unfence a push); root's gc `-c safe.directory="$repo"` (system `/*` form inert on git 2.43 — every run failed every repo); gc lock → RuntimeDirectory (/var/lock git-writable, protected_regular DoS); `rm -rf --one-file-system`; lock never unlinked + symlink-refused; `gc_report` routed; op-contract (b) derivation now reads the gc payload and accepts trailing-comment `STAGE=` with a runcmd parse floor; ownership writer census (7 survivors → RED), S6 literal equality, S6b construct anchor, S8 seam parity, S9 gc pins; birth-gate G27–G29 (three lib mutants → RED), G10 needle; "stdout only" claim corrected at 4 sites; git-shell/pipeline-delivery rationale sweep (13 sites).
- Suites on the review-pass tree: remove 38/0, provision 30/0, transport 31/0, ownership 29 static + 10 runtime (39 floor), birth-gate 149/0, evidence-capture 80/0, bs-archive 37/0, op-contract 6/6, rehearsal 92/0 (docker), luks 133/0, emit 59/0, pre-receive 24/0, strip-parity 15/0, tmpl-strip 5/0, doppler-bound 31/0, cred-persist 40/0, vacuity 23/0, fixture-relative 62/0 (baseline regenerated), orphan-suites 429 covered.
- Declined (recorded): `_sshd_T_*` → `_sshd_eff_*` rename (cosmetic, hash-bound noise); comment de-duplication across remove/provision (the two scripts are read independently on the host); GIT_DATA_ROOT → MOUNT_ROOT rename in the bootstrap (S8 pins the seam instead).
- Filed/commented: see the review-phase issue list in the PR body (cutover: hooks/ rsync + `findmnt` device assertion; #8010: any later evidence-only commit re-blesses a voided attestation; #8094: amend the stdout-only premise + add an issue-alert rule for the two ops).
