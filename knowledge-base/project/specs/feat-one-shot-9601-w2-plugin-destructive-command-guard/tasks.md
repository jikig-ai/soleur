# Tasks: plugin destructive-command guard (W2)

Plan: `knowledge-base/project/plans/2026-10-06-feat-plugin-destructive-command-guard-w2-plan.md`. Epic #9601 (this PR links it with `Ref #9601`, never `Closes`). Draft PR #9653. Scope is W2 only; W3 (image CVE scan) is the next PR.

## 0. Product gate and measurements (nothing below section 0 starts until 0.4 is recorded)

- 0.1 Read-only checks: ADR ordinal still free; `devin-matcher-parity` dry run for the registry rows it demands; vacuity-floor covered-dir reading; enumerate headless and cron surfaces that load the plugin (`test-pretooluse-hooks.yml`, the single SDK binding); whether this repo's own sessions load the plugin hooks.
- 0.2 Re-probe the unmeasured `ask` rows with the scripted Anthropic stand-in (no credential): current Claude Code version, subagent turn, `dontAsk`, `auto`, `claude -p`, `bypassPermissions`, and whether `systemMessage` renders on a deny. Append results and commands to `phase-0-measurements.md`.
- 0.3 CPO sign-off on the final decision set:
  - 0.3.1 Commit and push the Decision Set section; compute its SHA-256.
  - 0.3.2 Spawn `soleur:product:cpo` with the section verbatim and the 0.1/0.2 results; at most two rounds, then stop and report blocked.
  - 0.3.3 Record the verdict, date, revision SHA and section hash under `## CPO sign-off` in PR #9653's body (append, never overwrite); first line states whether merging alone mutates production; retitle from `WIP:`; use `Ref #9601`, never `Closes`.
- 0.4 Gate check: `gh pr view 9653 --json body` has `CPO sign-off`, a 40-hex SHA and `Ref #9601`, and none of `Closes #`, `Fixes #`, `Resolves #`. Re-run before PR-ready and after any later body edit. Any later change to D1-D9 returns to 0.3.

## 1. Tests first (RED)

- 1.1 `plugins/soleur/test/destructive-command-guard-hook.test.sh`: floor-bearing, mutant-constructible (literal floor, per-row counter at the call site, conservation, self-test).
- 1.2 Oracle: stub-only `PATH`, canary that `rm`/`terraform`/`git` resolve to stubs, literal expectations for absolute-path/`sudo`/NUL/oversized/garbage rows, symlink farm for jq-less and perl-less runs.
- 1.3 Grammar fixture and the Guard 1 matrix rows (including `cd`, wrappers, `--` suffix forms, quoting of `~`/`$HOME`, symlink targets, push-flag spellings, prefilter-boundary characters, more than 32 commands, a 100 KB heredoc).
- 1.4 Must-PASS rows and the ordinary-command corpus (about 40 commands; report the ask rate).
- 1.5 `plugins/soleur/test/shell-argv-parity.test.sh`: byte-identity of the BEGIN/END-marked lexer region plus a small `--trace` corpus; minimum-size floor.
- 1.6 `plugins/soleur/test/destructive-command-guard-mutation.test.sh`: mutates a COPY of the tree; CI rows M1-M8; run rows 9-20 once and record them.

## 2. Lexer

- 2.1 Add BEGIN/END SHARED-LEXER marker comments to `.claude/hooks/lib/filing-shape.pl` (no behaviour change; its suites stay green).
- 2.2 Create `plugins/soleur/hooks/lib/shell-argv.pl`: the identical region plus an argv-record `process_command` (q/x flags, no record cap).

## 3. Hook

- 3.1 `plugins/soleur/hooks/destructive-command-guard.sh`: kill switch first (`=1` only); zero-spawn prefilter; raw `tool_name` before kind mapping; dependency probes by result; `jq -j` into the lexer; rule table (D1); full decision envelope; degraded paths (D6); header (property, D2 list, dependencies, portability, restart note, settings-env residual, original-command note).
  - 3.1.1 Bash 3.2 plumbing: `read -d ''` frames, terminator not exit status, empty-array guards, no GNU-only calls.
  - 3.1.2 Path resolution without `realpath`: physical parent plus literal basename, longest-existing-prefix fallback, `HOME` literal and physical forms, symlink follow only for trailing `/` or glob.
  - 3.1.3 Default branches: named remote's `HEAD` (local only) unioned with `main`/`master`; `git -C`; value-taking push flags.
- 3.2 Measure latency (prefilter-skipped, lexed, destructive; 200 calls each); report in the PR body.
- 3.3 Register in `plugins/soleur/hooks/hooks.json`: `^Bash$`, explicit `timeout`, after the snapshot guard.

## 4. Registries

- 4.1 One `soleur-plugin` row in `.claude/hooks/devin-dispositions.tsv` (`skip`, reason and evidence); run `devin-matcher-parity.test.sh`; add a settings row only if it demands one.
- 4.2 `.claude/hooks/README.md` hook-table and kill-switch rows.
- 4.3 Run `scripts/guard-vacuity-floor.test.sh` (no `PROMOTED_FILES` edit; the suites are in `COVERED_DIRS`).
- 4.4 `plugins/soleur/test/devin-plugin.test.ts` parallel assertion.
- 4.5 Shard census rows if required; `scripts/lint-orphan-test-suites.sh`; `components.test.ts` and `devin-*.test.ts`.

## 5. Hosted posture

- 5.1 `SOLEUR_DISABLE_DESTRUCTIVE_GUARD: "1"` in `AGENT_ENV_OVERRIDES`.
- 5.2 Census of PreToolUse hooks from `hooks.json` (web-disabled or web-active with reason) and a real-`buildAgentEnv` behavioural run per auth scheme; mutation: kill-switch read below the `jq` probe goes red.

## 6. Architecture, docs, close-out

- 6.1 ADR-274 (`Extends: ADR-157, ADR-165`; ordinal re-verified against fresh `origin/main`) and one ADR-093 line.
- 6.2 C4: read all three model files; add `destructiveGuard` and one edge; run `c4-code-syntax`, `c4-render`, `c4-count-parity`, `c4-model-freshness`.
- 6.3 Amend spec FR2; add a pointer line to the slice-1 `tasks.md` PR 2 heading.
- 6.4 Extend `scripts/verify-agent-security-slice1.sh` with the guard check (registration plus three-envelope probe).
- 6.5 Create the single deferral issue (hosted enablement, Devin `exec`, D2 candidates, canonical plugin lexer, session-start posture message, per-rule allow); milestone from the roadmap; comment the hosted pointer on #9601.
- 6.6 Run `markdownlint`, the plan lints and the touched web-platform tests; `soleur:gdpr-gate` and `user-impact-reviewer` at review; re-run the 0.4 check before PR-ready.
