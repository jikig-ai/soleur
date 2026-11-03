---
title: "fix(security): batch-clear three js/shell-command-injection-from-environment CodeQL alerts (279, 302, 303)"
type: fix
date: 2026-11-03
slug: fix-codeql-shell-injection-batch
branch: feat-one-shot-codeql-shell-injection-batch
domain: engineering
priority: p2-medium
brand_survival_threshold: none
lane: single-domain
---

# fix(security): batch-clear three js/shell-command-injection-from-environment CodeQL alerts (279, 302, 303)

## Overview

Freeform ask (operator $ARGUMENTS): fix three open `js/shell-command-injection-from-environment` (medium-severity, `@problem.severity warning`) CodeQL alerts in one PR — alert 279 in `plugins/soleur/scripts/harness-discovery-smoke.ts` (start line 473, the `execFileSync` inside `run()`), and alerts 302 + 303 in `apps/web-platform/test/sdk-bash-probe-runtime.test.ts` (lines 418 and 473, two `spawn("sh", ["-c", …])` FIFO writers). No tracker issues exist for medium-severity alerts; the PR body references the alert numbers instead of `Closes` lines. All three are verifiably OPEN on `refs/heads/main` at merge-base `aa2e3aed00` (gh api code-scanning/alerts, 2026-11-03).

## Problem Statement / Motivation

The query (`Security/CWE-078/ShellCommandInjectionFromEnvironment.ql`, precision high) flags values whose source is an "uncontrolled absolute path" (`__dirname`, `process.execPath`, `process.cwd()`, `path.resolve`/`realpathSync`-family outputs) or "uncontrolled file name" reaching a node that a shell interprets. A `spawn`/`execFileSync` argv element is shell-interpreted only when the executed program is `sh`/`bash`/`cmd.exe` and the argument list carries `-c` (`IndirectCommandArgument.qll`). Each alert is one such flow:

- **279** — `resolveBin()` (line 605-613) calls `run("bash", ["-c", <script>, "bash", bin], {PATH: process.env.PATH})`. That single call site makes `run()`'s shared `execFileSync` an indirect shell execution, so every absolute-path argument at every `run()` call site (`REPO_ROOT`, `process.execPath`, mkdtemp scratch dirs — six flows) is a sink. The alert highlights the `execFileSync` at line 473-480.
- **302 / 303** — two tests spawn `sh -c` writers that stream NUL-separated bytes into a FIFO in chunks; the mkdtemp-derived `fifo` path (and the `HOME` constant interpolation for 302) sits inside the `-c` argv array, which `IndirectCommandArgument` marks shell-interpreted.

## Proposed Solution

Apply the repo's proven remediation for this exact query (alerts 213/214, fixed by commit `f5f51c84b0` / PR #7566): remove the inline-script `-c` form so nothing argv-shaped is shell-interpreted — a shape change, not a behaviour change.

1. **`harness-discovery-smoke.ts` — rewrite `resolveBin` without a shell.** Replace `run("bash", ["-c", <command-v + readlink -f script>], …)` with a pure-Node equivalent: walk `process.env.PATH` entries, `accessSync(candidate, fs.constants.X_OK)` on `join(dir, bin)`, return `realpathSync(candidate)` (fall back to `candidate` when realpath throws, mirroring the script's `|| r="$p"` arm). `command -v` semantics that matter here — executable-bit check, first PATH hit wins, absent → `undefined` — are preserved; empty PATH entries are skipped rather than resolved against CWD (deliberate: a `.` hit is not the real launcher this function exists to find). With no `bash -c` caller left, `run()` stops being an indirect shell execution and all six flows die.
2. **`sdk-bash-probe-runtime.test.ts` — write the two writer scripts to temp files inside the existing `scratch()` dirs** (tracked in `tmps[]`, removed by `afterEach`), then `spawn("sh", [scriptPath, fifo, …])` — argv without `-c` is not shell-interpreted. `HOME` passes as `"$2"` so the single-source property of the `HOME` const survives (302); the printf payloads move byte-identical into the files (302, 303).

## Technical Considerations

- Behaviour parity: `resolveBin` callers (`driveOpenCode` line 800) get the same contract — resolved absolute launcher path or `undefined`. The `readlink -f` shim-following is carried by `realpathSync` (same syscall semantics: canonicalize + resolve the link chain). The "opencode shim resolves through $HOME" comment stays true and stays load-bearing.
- `have()`'s `execFileSync("command", ["-v", bin], {shell: "/bin/bash"})` (line 490) is untouched — it is not a flagged site and its env is implicit.
- Security considerations: the fix *strengthens* posture — the test FIFO writers and `resolveBin` no longer route through a shell at all, removing the shell-interpretation surface rather than sanitizing it.
- NFR impacts: none — no production path, no perf surface (one extra `writeFileSync` + `openSync` per test case; `resolveBin` trades one `bash` spawn for a synchronous PATH walk).

### Attack Surface Enumeration (for security fixes)

All ways this surface can execute a command after the change:

- `run()` → `execFileSync(cmd, args, {env})`: `cmd` literals `codex`/`git`/`devin`/`process.execPath`/resolved `bin`; argv arrays only — never shell-interpreted after this change (no `sh`/`bash`/`cmd.exe` `cmd` value remains).
- `runToFile()` → `spawnSync(bin, args, …)`: argv only.
- `openCodeSkillProbe()` → `spawn(bin, ["serve", …])`: argv only.
- `have()` → `execFileSync("command", ["-v", bin], {shell: "/bin/bash"})`: pre-existing, not flagged, env implicit; out of scope (changing it is not required to clear the alerts and would be scope creep).
- Test file: `execFileSync("mkfifo", [fifo])`, `spawn("sh", [scriptPath, fifo, HOME])` post-fix: argv only.

Unchecked path worth naming: the `env` objects still carry `PATH: process.env.PATH` into spawns — legitimate (the script's purpose is discovering CLIs wherever CI/dev installs them; the CI job installs to `npm -g` prefix and `~/.local/bin`). CodeQL models PATH-in-env only through shell-interpreted args, which this change eliminates; not a gap.

## User-Brand Impact

- **If this lands broken, the user experiences:** a red `harness-discovery` CI leg or a red `test-webplat` shard — CI surfaces, not product surfaces; no operator-facing artifact changes.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing new — the change removes a shell-interpretation path; it adds no input, no network surface, no persisted state.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** both files are test/CI-harness code; a regression reds a gate, which is the gate's designed failure mode.

`threshold: none, reason: the diff touches a CI smoke script and a unit-test file only — no user-facing surface, no regulated data path.`

## Observability

```yaml
liveness_signal:
  what: "CI leg results — the harness-discovery job (continue-on-error, still visible) and test-webplat shard report these suites' pass/fail per run"
  cadence: "per PR run / per push to main"
  alert_target: "PR check list (visible); harness-discovery leg red is triageable, not merge-blocking by design (#8574)"
  configured_in: ".github/workflows/ci.yml `harness-discovery:` job"
error_reporting:
  destination: "CI job log (stderr; the script's own ::error:: annotations via sanitizeForLog)"
  fail_loud: "non-zero exit / ::error::harness-discovery[…] annotation in the job log"
failure_modes:
  - mode: "resolveBin returns undefined for an installed CLI (PATH-walk regression)"
    detection: "driveOpenCode falls back to the bare name — the opencode arm's hermetic-HOME shim failure returns probeFailed/UNRESOLVED in the job log"
    alert_route: "harness-discovery CI leg red on the PR check list"
  - mode: "FIFO writer script does not deliver chunks (test-file regression)"
    detection: "vitest assertion failure in test/sdk-bash-probe-runtime.test.ts"
    alert_route: "test-webplat shard red, merge-blocking"
logs:
  where: "GitHub Actions job log for the CI run"
  retention: "GitHub default (90 days)"
discoverability_test:
  command: grep -L -- '"-c"' plugins/soleur/scripts/harness-discovery-smoke.ts apps/web-platform/test/sdk-bash-probe-runtime.test.ts
  expected_output: "harness-discovery-smoke.ts sdk-bash-probe-runtime.test.ts"
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change (CI smoke script + unit test file).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Fix THREE js/shell-command-injection-from-environment (medium) CodeQL alerts in one PR" | FR1-FR3, one PR | mapped |
| 2 | "#279 — plugins/soleur/scripts/harness-discovery-smoke.ts:473" | FR1 (resolveBin pure-Node rewrite) | mapped |
| 3 | "#302 — apps/web-platform/test/sdk-bash-probe-runtime.test.ts:418" | FR2 (temp-file writer) | mapped |
| 4 | "#303 — apps/web-platform/test/sdk-bash-probe-runtime.test.ts:473" | FR3 (temp-file writer) | mapped |
| 5 | "reference the alert numbers in the PR body instead of Closes lines" | AC5 (PR body cites alerts 279/302/303, no `Closes #N`) | mapped |
| 6 | "Commit author: repo's CLA identity, never devin-ai-integration[bot]" | AC6 (commits authored Jean Deruelle <jean.deruelle@jikigai.com>) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| resolveBin pure-Node rewrite | "fix via allowlist/env-clear/argv-array spawn instead of string shell" | asked |
| Temp-file FIFO writers | "argv-array spawn instead of string shell" + repo precedent (213/214 → #7566) | asked |
| No `Closes` lines in PR body | "reference the alert numbers in the PR body instead of Closes lines" | asked |
| No alert dismissal | "do NOT dismiss without operator sign-off" | asked |

### Split Assessment

- Subsystems touched: 2 — `plugins/soleur/scripts/`, `apps/web-platform/test/`
- Planned files: 2 | Estimated changed lines: ~45
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] **AC1 (279):** `resolveBin` in `plugins/soleur/scripts/harness-discovery-smoke.ts` contains no `run("bash"`/`"-c"` shell invocation; it returns the `realpathSync`-resolved first executable `join(dir, bin)` over `process.env.PATH` entries, `undefined` when absent — `resolveBin("soleur-no-such-binary-9f3a1c")` still returns `undefined`.
- [ ] **AC2 (302):** the `environ.fifo` chunked-writer test spawns `sh <script-file> <fifo> <HOME>` with no `"-c"` argv element; the script file lives in the test's `scratch()` dir; `readPid1` still sees `homeMatches: true, divergent: true`.
- [ ] **AC3 (303):** the `cap.fifo` chunked-writer test spawns `sh <script-file> <fifo>` with no `"-c"` argv element; `readProcCapped(fifo, 64)` still returns 64 bytes ending in `Z`.
- [ ] **AC4:** `grep -L -- '"-c"' plugins/soleur/scripts/harness-discovery-smoke.ts apps/web-platform/test/sdk-bash-probe-runtime.test.ts` prints both paths (zero `"-c"` argv elements remain in either file).
- [ ] **AC5:** the PR body names alerts 279, 302, 303 with per-alert disposition and carries NO `Closes`/`Fixes`/`Resolves` keyword.
- [ ] **AC6:** all commits authored `Jean Deruelle <jean.deruelle@jikigai.com>` (repo CLA identity).
- [ ] **AC7:** `bun test plugins/soleur/test/harness-discovery-smoke.test.ts` green; `vitest run test/sdk-bash-probe-runtime.test.ts` green.

## Test Scenarios

- `unit` — Given `resolveBin("soleur-no-such-binary-9f3a1c")`, when PATH lacks the name, then `undefined` (pre-existing test, must stay green).
- `unit` — Given a scratch dir with a fake executable `bin` symlinked through a shim on a PATH prefix, when `resolveBin("bin")`, then the canonical realpath of the target (new assertion inside the existing `resolveBin` describe — pins the readlink -f parity).
- `unit` — Given `environ.fifo`, when the writer script runs via `sh <file>`, then `readPid1` sees HOME at end and TMPDIR (302 regression: the exact alert site).
- `unit` — Given `cap.fifo` delivering exactly CAP bytes across three chunks, when `readProcCapped(fifo, 64)`, then 64 bytes ending `Z` (303 regression).
- `integration` — the discoverability probe (AC4) run verbatim in the Observability block.

## Success Metrics

All three alerts transition `open → fixed` on the first post-merge CodeQL analysis of `refs/heads/main` (CodeQL runs on push; `codeql-main-alert-gate` files trackers only for critical/high, so no tracker churn expected for these mediums).

## Dependencies & Risks

- Risk: `resolveBin`'s PATH walk diverges from `command -v` on edge cases (empty PATH entries, non-executable hits, relative PATH dirs). Mitigation: skip empty entries, `X_OK` check, join() on relative dirs behaves like `command -v` (cwd-relative — acceptable and documented).
- Risk: CodeQL re-analysis could still see a flow if another `sh`/`bash -c` caller of `run()` exists — AC4's grep is the verification; only line 608 carried one.
- Dependency: none external; no issue/PR blockers (open-PR probes, sibling-worktree probes, and the overlap preflight all returned clean on 2026-11-03).

## Research Insights

- Premise validation: all three alerts verified OPEN on `refs/heads/main` at `aa2e3aed00` via `gh api repos/jikig-ai/soleur/code-scanning/alerts/<N>` (state, rule.id, path, start_line all match the ask). The `#N` refs are code-scanning alert numbers — repo issues/PRs #279, #302, #303 are unrelated ancient artifacts (confirmed via `gh issue view`); treated as contextual citations, not work targets. No stale premises.
- Property list (mechanism minimality, Phase 0.6b): (a) no argv element a shell interprets may carry env-derived path values; (b) test FIFO writers keep chunked delivery semantics; (c) `resolveBin` keeps `command -v` + `readlink -f` semantics. Cut list: env-allowlist PATH scrubbing (breaks CLI discovery — the script's purpose); `codeql[…]` suppression comments (zero occurrences in repo — not a pattern here).
- Query mechanics (fetched `codeql` repo source, `ShellCommandInjectionFromEnvironmentCustomizations.qll` + `IndirectCommandArgument.qll` + `NodeJSLib.qll`): sources = `__dirname`/`process.execPath`/`process.cwd()`/resolving-path outputs ("absolute path") and FS-derived names ("file name"); sinks = `exec`/`execSync` arg0 and argv arrays of `sh|bash|cmd.exe` executions carrying `-c`. Sanitizer `QuotingConcatSanitizer` exists but is irrelevant — removing the `-c` form removes the sink entirely.
- Established precedent: commit `f5f51c84b0` (PR #7566) cleared alerts 213/214 of this same rule by writing the inline `bash -c` harness to a temp file and invoking `bash <file> <args>`; its comment records the mechanism ("CodeQL flags the inline-script form … the path was already in argv rather than interpolated, so this is a shape change, not a behaviour change").
- Institutional learnings applied: verify-measurement-before-propagation (query source read, not assumed); sibling-collision probes (open PRs touching both files: none; sibling worktrees `codeql-dedupe-fix`/`probe-hygiene` inspected — both archived, disjoint file sets; `pr-overlap-preflight.sh --mode start` → exit 0, `prs=none`).
- CLAUDE.md conventions: commit author = repo CLA identity; no `version` keys; PR body `## Changelog` section.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies contain neither `harness-discovery-smoke` nor `sdk-bash-probe-runtime` (queried 2026-11-03).

## References & Research

- Alert verification: `gh api repos/jikig-ai/soleur/code-scanning/alerts/{279,302,303}`
- Query source: `github/codeql` `javascript/ql` — `ShellCommandInjectionFromEnvironment.ql`, `ShellCommandInjectionFromEnvironmentCustomizations.qll`, `IndirectCommandArgument.qll`, `NodeJSLib.qll` (ChildProcessMethodCall).
- Precedent fix: `git show f5f51c84b0 -- plugins/soleur/test/workflow-fidelity.test.ts` (alerts 213/214, PR #7566).
- Flagged sites: `plugins/soleur/scripts/harness-discovery-smoke.ts:471-486` (`run`), `:605-613` (`resolveBin`); `apps/web-platform/test/sdk-bash-probe-runtime.test.ts:418`, `:473`.
- Related: `.github/workflows/ci.yml` `harness-discovery:` job (continue-on-error leg).
