# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-14-feat-playwright-mcp-snapshot-redaction-proxy-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- Draft PR: #8150

### Errors
- `iac-plan-write-guard.sh` rejected the first full plan write on the phrase "out-of-band"; reworded and re-written, no content lost.
- `gh issue create` for the deferral (#8156) was blocked three times by the filing gate (needed `User-Impact:` + measured `Fix-Size:` lines and a body file the gate can read — scratchpad / same-command paths are not readable to it); filed on the fourth attempt via a repo-local body file (removed afterwards).
- A Bash command containing the literal process-grep-by-full-cmdline idiom inside a Python heredoc was blocked by the self-match guard; edits applied with the Edit tool instead. (The parent hit the same guard writing this very file via a heredoc; written with the Write tool.)
- `gdpr-gate` printed a pre-existing `POSTURE_FAIL` (rules >90 days stale, tracked at #7255/#7852) — recorded in the plan, not this PR's concern.
- Lane defaulted to `cross-domain` (fail-closed): no `spec.md` exists for this branch because one-shot entered `plan` directly.

### Decisions
- Q1 whole server, by shape: the proxy applies `redact_text` to every `tools/call` text result, no tool-name allowlist (security review found `browser_find` as a second inline tree path); disk sink closed structurally (`--snapshot-mode none` appended, `browser_snapshot`+`filename` and `arguments._meta` refused, refuses to start under `--save-session`/`saveSession`/`DEBUG`/`DEBUG_FILE`).
- Q2 fail closed, three arms, loud, no kill switch: refuse-to-start; per-result withhold via one `error_result` builder with pinned stderr vocabulary; process-group teardown. Unknown-id responses dropped, not forwarded.
- Q3 in-process: `importlib` load of `redact-a11y-snapshot.py` binding four names as a provider contract; subprocess-of-CLI rejected by measurement; rename rejected (filename is the anchor). Recorded as an ADR-213 addendum, not a new ADR.
- Prose truthful on both surfaces by construction; per-result trailer kept; `initialize.instructions` annotation, drift-arm file deletion, two-thread design cut at plan review.
- Scope folds: `cron-ux-audit.ts` gets `--snapshot-mode none` + `zero-screenshots` `warnSilentFallback`; PA-8 §(g) / PA-31 §(g) re-appended; CLO attestation audit + compliance-posture row in scope; C4 gains `playwrightMcp` + `platform.plugin.snapshotGuard`. Deferral #8156: customers never edit `.mcp.json`.

### Components Invoked
- Skills: soleur:plan, soleur:gdpr-gate, soleur:plan-review, soleur:deepen-plan
- Agents: repo-research-analyst, learnings-researcher, cto, clo, cpo, spec-flow-analyzer, advisor consult; plan-review: dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist; deepen: security-sentinel, test-design-reviewer, observability-coverage-reviewer, git-history-analyzer, framework-docs-researcher, general-purpose sweeps

## Work Phase
- Status: in progress (Phase 2–5 implemented; Phase 6 gates green; final commits pending)
- Commits: 0fd5a6657 (plan), 7c8bb2bb9 (captures + redactor contract), 000202ede (cron-ux-audit), 1bd16da9c (ADR-213 + C4), b47d503e2 (proxy + suite + .mcp.json)

### Errors
- `test-all.sh` REFUSED (rc=4) twice — sibling full-gate runs in other worktrees; targeted suites substituted (proxy suite, redactor suite, lint suites, vacuity floor, legal registers, C4 gates, vitest rows) and recorded under `runs/phase6-gates.log`.
- The first Phase 4 commit was reported "completed (exit code 0)" by the harness while HEAD had not moved: the pre-commit `bun-test` job runs the FULL battery for any staged `.ts`, the foreground call hit the 600 s tool timeout, and the trailing `git log` made the wrapper's exit 0. The `/tmp` output file was swept before it could be read. Re-run with the hook log kept in the worktree (`runs/commit-phase4.log`) and `RC=$?` written immediately after `git commit`.
- Suite row 37 first drove a line of EXACTLY 64 MiB, which parses and is caught by the 4 MiB result cap instead of the line cap (see `phase-0-measurement.md` §Line-cap boundary) — the row now drives 65 MiB.
- First suite runs had two instrument defects, both caught by the run rather than by inspection: mutants were written to a directory with no sibling redactor, so every mutant refused to start and rows whose RED signal is an absence read as "caught" (fixed: the redactor is copied beside the mutants, `leaks`/`started` helpers require a DELIVERED response); and `mutant()`'s `ok` line was captured by `$(...)` into the path variable (fixed: verdict lines go to fd 3).
- The Guard 2 executable row had its env assignments on `sleep 5 | bash -c …` applied to `sleep` only (pipeline prefix scoping) — the shim never saw `SHIM_ARGV_OUT`; fixed with `export`.
- Live verification first ran `--isolated` together with `--user-data-dir`, which 0.0.78 rejects; the proxy relayed the child's rc=1 correctly. Re-run without `--isolated` (`runs/live-verify.md`).
- `rm -rf` on scratch dirs under `/var/tmp` is blocked by the protected-location guard when written as a glob loop; individual paths were left for the session sweep.
- `guard-vacuity-floor` ratchet grew 47 → 48 with the new suite in a deferred directory; resolved by PROMOTING the file (measured control/neutered/floor-raised), not by raising the ratchet.

### Decisions
- FR13 vs B3 conflict resolved by exempting the module docstring and the `self_test` body from the literal scan (recorded in `phase-0-measurement.md`).
- FR17 population is six files, not five (`agent-browser/SKILL.md` names `mcp__playwright__browser_snapshot` in its verify sentence, so it is in S2's population and carries the canonical sentence).
- CLO attestation correction C1 applied in-cell to the PA-8 bracket: the skills carry no affirmative "never relaunch unwrapped" prohibition, so the register now describes the prescription that ships; skills not widened in this PR.

### Components Invoked
- Agents: general-purpose (Phase 3.3 agent A; Phase 4 agent B; Phase 5.1/5.3 agent C), clo (Phase 5.4 attestation)
- Pre-commit `bun-test` (full battery) excluded for commit 8ffa2c22c by operator decision after 40 min queued behind a sibling worktree's run; CI runs the battery on push (ADR-183). Recorded in the commit body and to be named in the PR body.
- Merge of origin/main (97e139de8): three conflicts resolved (guard-vacuity-floor PROMOTED_FILES union with #8028's postgrest-reload-schema entry; both compliance-posture rows kept; model.likec4.json regenerated). Pre-commit `plugin-component-test` failed twice on `changelog-data.test.ts` timing out at bun's 5 s default on a LIVE GitHub Releases call (API alone 2.9 s at load 14.8; suite untouched by this branch; passes alone and 2710/0 with --timeout 30000, `runs/plugin-component-test-manual.log`) — that one job excluded for the merge commit only.
