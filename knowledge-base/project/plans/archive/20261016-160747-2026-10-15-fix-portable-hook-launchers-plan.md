---
title: "fix: Resolve repository hooks from bare roots across harnesses"
date: 2026-10-15
slug: fix-portable-hook-launchers
branch: feat-one-shot-portable-hook-launchers
type: fix
lane: single-domain
domain: engineering
priority: p2
brand_survival_threshold: single-user incident
requires_cpo_signoff: false
---

## Overview

Codex's two repository-hook commands assume `git rev-parse --show-toplevel` succeeds. Starting at this repository's bare root makes that probe fail, constructs `/.claude/hooks/...`, and exits 127 before rules or guardrails run. Repair the configured command bootstrap and the equivalent deepest Git fallback in Devin while preserving healthy Claude/Grok behavior and current harness coverage.

## Research Insights

Premise validation: `.codex/config.toml` contains two affected registered commands; `.devin/config.json` has the same assumption behind its existing project-environment precedence. Claude `.claude/settings.json` uses quoted `CLAUDE_PROJECT_DIR`; `.grok/config.toml` documents Claude-settings compatibility. Cursor's existing slice has no hook execution capability; this change adds none. All claims describe the checked-out source, with command execution tested through synthetic fixtures rather than claiming a new native harness certification.

`plugins/soleur/scripts/resolve-git-root.sh` already settles bare-root mapping: preserve `--show-toplevel` for a checkout, use `--absolute-git-dir` for a bare repository, strip only a terminal `/.git`. It is intentionally source-only and its tests pin that behavior. Locating it from these configs needs the same bootstrap, so sourcing it or adding a dispatcher adds indirection without removing root discovery. CTO ruling confirms the inline repair within the existing repository-code trust boundary; no new architectural decision or ADR is needed. ADR-179's installed-plugin executable anchoring remains a separate contract.

External verification: the official [Git rev-parse reference](https://git-scm.com/docs/git-rev-parse#Documentation/git-rev-parse.txt---show-toplevel) documents that the top-level probe requires a working tree, the absolute-git-dir probe returns a canonical absolute directory, and the bare probe reports bare status. This supports the bounded fallback; exact configured shell behavior is verified by executable fixtures. GNU Bash web documentation was unavailable through the browser tool during planning, so shell exit propagation remains an explicit execution-test requirement rather than relying on an unchecked citation.

Applicable learnings: `2026-03-13-bare-repo-git-rev-parse-failure.md` rejects the worktree-only Git probe; `2026-04-12-hook-paths-must-use-claude-project-dir.md` protects environment-based launchers; `2026-10-06-a-guard-folded-its-probe-error-into-untracked-and-my-fix-broke-the-bare-root.md` requires bare/worktree/subdirectory fixtures; `2026-09-15-devin-dual-hook-registries-dead-matchers-fires-then-noops.md` requires preserving matcher and single-dispatch behavior. ADR-261 protects the existing memory-backstop resolver target and explicit Bash invocation. Functional discovery found no replacement for this local launcher repair; no new stack coverage is required.

Property List:

- P1: registered commands launch the intended checkout's script from ordinary, nested, linked-worktree, and bare locations.
- P2: existing harness environment precedence, interpreters, target arguments, stdin, stdout/stderr, and target exit codes survive.
- P3: resolution failure or a missing selected target launches no alternative checkout's script.
- P4: registrations and supported harness capabilities remain accurately described and independently enumerable.

Cut List: new generic dispatcher; new installed-plugin resolution mechanism; new harness hook support; matcher expansion; unrelated hook-body changes; build, provider, browser, Docker, SQL or PR #9051 operations. These are alternative mechanisms or unrelated capabilities, not deferred deliverables.

## User-Brand Impact

- **If this lands broken, the user experiences:** repeated Hook failed messages and absent rule/guard execution in a session launched from the bare root.
- **If this leaks, the user's workflow is exposed via:** a launcher selecting another checkout's executable or skipping the registered safety hook.
- **Brand-survival threshold:** single-user incident.
- **Threshold decision (challengeable):** one session silently missing its guardrails is sufficient to damage trust.

## Files to Edit

- `.codex/config.toml`: repair the two bootstrap commands.
- `.devin/config.json`: repair the existing deepest Git fallback while preserving the two environment overrides and every interpreter, target, argument, matcher and timeout.
- `.claude/hooks/README.md`: correct the bare-root section's Codex limitation and state tested launcher coverage without claiming new native lifecycle support.

## Files to Create

- `plugins/soleur/test/repo-hook-launchers.test.ts`: fixture execution of real configured commands, including Claude/Grok compatibility registrations and the current Cursor boundary.

## Implementation Phases

### 1. Regressions first

Extract actual command strings from the checked-in Codex TOML and Devin/Claude JSON; use an existing TOML parser or a bounded parser matching these literal command records. Enumerate every changed command structurally from the registries, with positive population checks. Use `plugins/soleur/test/lib/git-fixture-env.ts` and fixture-local marker targets; keep real Git writes inside temporary fixtures and disable inherited hooks/config. Reproduce the bare-root failure before editing configs.

Freeze an independent baseline of each original registration's interpreter, target and trailing arguments before editing the configs; repaired-command expectations must not be re-derived from their own changed command strings. For discovery-failure tests, add an interpreter-invocation spy and a positive control proving that it observes real dispatch. Nonzero status and a missing marker alone do not prove failure happened before an attempted `/.claude/...` launch.

### 2. Repair the bootstrap

Use this bounded expression identically in the defective Git fallback positions, escaped appropriately for TOML/JSON:

```bash
git rev-parse --show-toplevel 2>/dev/null || {
  test "$(git rev-parse --is-bare-repository 2>/dev/null)" = true || exit 1
  hook_git_dir=$(git rev-parse --absolute-git-dir) || exit
  printf '%s\n' "${hook_git_dir%/.git}"
}
```

Assign the complete selected root to a task-specific variable, then chain target execution with `&&` so a failed substitution never launches `/.claude/...`. For Codex the selected root comes from Git. For Devin preserve `${CLAUDE_PROJECT_DIR:-${DEVIN_PROJECT_DIR:-<Git substitution>}}`. The first Git probe must stay `--show-toplevel`; switching to common-dir globally would execute the wrong bytes from a linked worktree. Only a positive bare probe authorizes the absolute-git-dir fallback. A conventional bare repository whose Git directory does not end in `/.git` keeps that path unchanged.

Keep every target/interpreter and final argument tail unchanged. Keep bootstrap discovery off stdin and do not change directories. Preserve the final target's process exit status and output. A missing selected target fails without searching another worktree/common-root checkout. Preserve one target script path per registration so Devin's existing canonicalizer and disposition ledger still see the real target.

### 3. Verify and document

Run the new focused suite; Codex/Devin setup and plugin suites that consume the changed configs; `.claude/hooks/devin-matcher-parity.test.sh`; and the registered guardrail/rules-loader suites needed to show their envelopes still reach the same bodies. Derive additional affected tests from file consumers rather than memory. Update only the documented bootstrap behavior. Lead owns review, QA, preflight, commits, push, merge and postmerge verification.

## Test Scenarios

- Given ordinary and linked checkouts, when actual configured commands run from their roots or nested directories (including paths with spaces), then each target's own checkout marker runs exactly once.
- Given a Soleur-style bare root containing `.git` or a conventional `git init --bare` directory, when commands run without project overrides, then the local target runs without the former exit 127 path error.
- Given Devin project overrides, when both are set, then Claude's override wins; with only Devin's set, Devin's wins; empty values reach Git. A selected nonexistent/missing-target override fails rather than falling back.
- Given target arguments, a byte-preserving stdin payload, stdout/stderr markers and exit codes 0/7/42, when a registered command runs, then the target observes the original arguments/input and its streams/status are returned exactly.
- Given a linked worktree missing its target and a common checkout with that target, when a command runs, then the common checkout marker is absent and the command fails.
- Given a non-repository or a failed non-bare root probe, when resolution runs, then no target launches and the command fails before a root-level accidental target could execute.
- Given top-level failure and a positive bare probe followed by absolute-git-dir failure, when resolution runs, then assignment fails and no target is dispatched.
- Given the real rule-loader and guardrails entrypoints, when safe fixture envelopes reach them, then the rule-context/deny response contract is unchanged. Stub only external side effects, not the command entrypoint being verified.

## Guard Contract

### Guard 1 — Configured launcher regression coverage

**Property.** Every affected registered command preserves checkout ownership and target invocation semantics across supported repository layouts, and unresolved roots never dispatch a target.

**Assembly.** Parse the actual hook command collections in Codex TOML and Devin JSON, enumerate every repository-root command, compare interpreter/target/argument suffix against independently frozen pre-edit expectations, assert nonzero populations and full registry coverage, and execute those commands against synthetic repository layouts; use Claude's actual env-based commands as compatibility controls without adding matchers. An interpreter spy with a positive control distinguishes failure-before-dispatch from a failed target attempt.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Reintroduce the worktree-only Git fallback in any registered command | RED on bare fixture |
| 2 | Break command extraction so zero commands are exercised | RED on positive population/coverage check |
| 3 | Add a second affected registration retaining the broken fallback after a compliant first | RED on structural enumeration |
| 4 | Redirect a linked-worktree command to its common checkout | RED on distinct checkout markers |
| 5 | Read hook stdin during bootstrap or swallow the target's nonzero status | RED on exact payload/status assertions |

## Observability

```yaml
liveness_signal:
  what: Existing SessionStart loaded-rule count and PreToolUse guard response
  cadence: Each registered hook invocation
  alert_target: Current harness session transcript
  configured_in: .codex/config.toml and .devin/config.json
error_reporting:
  destination: Hook command stderr and harness hook-failure result
  fail_loud: Nonzero resolution or target failure; no success fallback
failure_modes:
  - mode: Root resolution fails
    detection: Root assignment fails before target execution
    alert_route: Harness hook-failure result
  - mode: Selected checkout lacks hook target
    detection: Existing interpreter reports missing selected target
    alert_route: Harness hook-failure result and stderr
logs:
  where: Existing harness transcript and existing hook incident channels
  retention: Existing session and hook-channel policy; no new storage
discoverability_test:
  command: bun test plugins/soleur/test/repo-hook-launchers.test.ts --test-name-pattern bootstrap-discoverability
  expected_output: REPO_HOOK_BOOTSTRAP_OK
```

The named smoke test executes the actual Codex SessionStart command in a synthetic bare-root fixture and prints `REPO_HOOK_BOOTSTRAP_OK` only after its expected response passes; it must complete within preflight's 15-second cap. This is one selected semantic smoke case rather than the whole regression suite. No new runtime telemetry or storage is introduced.

## Domain Review

Engineering/devex tooling only. No UI, account, processor, data-store, encryption, infrastructure or product feature is introduced. CTO scoped ruling favors the bounded inline fix. Review includes correctness, simplicity, architecture/security boundary and SpecFlow paths because the guardrail launch path is sensitive. No founder-check block is captured in this delegated one-shot phase.

Plan/deepen review ran in bounded waves under Codex's four-slot limit, reusing completed reviewer agents for subsequent role definitions: DHH, Kieran, code simplicity, architecture and SpecFlow, plus CTO scoped ruling and targeted security/test-design passes. DHH/Kieran/architecture found no plan blockers; simplicity's earlier static-probe correction was superseded by the named semantic smoke probe; SpecFlow added the final absolute-git-dir failure fixture. The full plan sharp-edges catalogue was read by the simplicity pass. The negative-verification pass confirmed existing selected-target ownership and the Cursor boundary, and identified resolution-before-dispatch as the intended new guarantee. Dropped/renamed infrastructure self-audit is inapplicable because this change removes none.

Deepen test-design findings were applied mechanically: freeze original invocation expectations independently of the repaired registry, and use a positively controlled interpreter spy to prove failure occurs before target dispatch. Security found no additional boundary gap in this scoped repair.

## Open Code-Review Overlap

None: inspected 93 open `code-review` issues for the four planned paths on 2026-10-15; no matching issue bodies.

## Non-goals and Rollback

Preserve current harness matcher/lifecycle support, installed-plugin hook ownership and hook bodies. This fix does not resume or alter PR #9051. Roll back this PR's config/test/documentation changes together if its bootstrap regresses a supported location.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "please fix it so it works on both (and all other harnesses too)" | Phases 1–3, affected configs, compatibility fixtures and README | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| Codex/Devin config edits and bounded root expression | "please fix it so it works on both (and all other harnesses too)" | asked |
| Registry-derived fixture suite and guard-contract mutation rows | — | inferred — justification: execution tests must reach the actual registration bootstrap that produced exit 127 and preserve safety-hook coverage |
| README correction and phase 3 verification | — | inferred — justification: the existing bare-root description would contradict the repaired behavior |

### Split Assessment

- Subsystems touched: 4 — `.codex`, `.devin`, `.claude`, `plugins/soleur`, all one hook-launch concern.
- Planned files: 4 | Estimated changed lines: 250, mostly regression fixtures.
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines.
- Recommendation: single PR — the config registries and their compatibility tests form one atomic bug fix despite four configuration roots.

## Acceptance Criteria

- [ ] Actual Codex and every affected Devin registration execute their intended marker targets across ordinary, nested, linked-worktree, Soleur bare-root and conventional-bare fixtures, including spaces.
- [ ] Existing environment precedence, interpreters, arguments, stdin, stdout/stderr and exit codes are preserved, with single target invocation.
- [ ] Root failure, invalid selected project override and missing active-worktree target fail without launching an alternative target.
- [ ] Real SessionStart/PreToolUse entrypoint smoke cases retain their existing rule-context and guard response semantics; matcher/timeout/disposition parity remains green.
- [ ] README accurately describes command-level tests, Claude/Grok compatibility and Cursor's existing hook-support limit.
- [ ] Guard-contract lint, focused regressions and affected registered checks pass, followed by lead-owned review/QA/preflight and normal shipping gates.
