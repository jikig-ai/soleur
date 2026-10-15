---
title: "feat: plugin-shipped stack-detecting affected test gate (PR 2 of #9307)"
date: 2026-10-15
slug: plugin-generic-affected-test-gate
branch: feat-one-shot-9307-generic-affected-gate
issue: 9307
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

Ship the plugin-generic, stack-detecting affected-only test gate — deliverable 2 of #9307 — so `soleur:work`, `soleur:ship` and `soleur:review` run only the tests a diff can reach, in parallel via the repo's own runner, in any repository a Soleur user works in. One entry point, `plugins/soleur/scripts/affected-tests.sh`, prefers a repo runner that advertises the Soleur capability, else detects the stack (JS/TS, Python, Go, nx/turbo) and uses the native affected selector and native parallel workers. A committed repo-root `.soleur-test-gate.json` overrides detection; a wall-clock budget defers to CI only when a CI test workflow is detected; output prints a human line plus an `AFFECTED_GATE ran=X of=N skipped=Y` marker. Every uncertainty path fails toward coverage; an empty selection is refused, never reported green; output says "affected-suite gate passed", never "tests verified".

This run is deliberately scoped to deliverable 2. Deliverable 1 (Soleur-repo over-selection fix) landed via #9306 and follow-ups; deliverable 3 (#8231 parallel scheduler) is a documented non-goal here — its green-baseline precondition does not hold.

## Research Insights

**Premise Validation (Phase 0.6).** Cited refs checked: #9307 (OPEN — umbrella; progress checklist shows PR 2 unchecked), PR #9306 (MERGED 2026-10-01: anchored edges + `--print-selection`), #8231 (OPEN, p3-low), #8621, #10333, #9729, #9564, #9441, #9340 (all OPEN). Held:

- `plugins/soleur/scripts/affected-tests.sh` does not exist on `origin/main` (`git log` empty for the path; no file in `plugins/soleur/scripts/`). Deliverable 2 is genuinely unimplemented — this is a *build*, not a fix.
- PR 1 machinery is live: `scripts/test-all.sh` carries `--print-selection`, `--paths`, anchored directory edges (`_affected_edge_token` D1 arm resolves `$(cd "<dir>/.." && pwd)` — the REPO_ROOT `/..` residual is fixed), the runner-subcommand skip (`"deno test"|"make test"|"run test"` at the `_affected_derive` command-word case), `scripts/test-affected-kb-consumers.test.sh` + baseline, and the derive cache (#9812, merged #9824 — the ~11 min pre-pass residual is addressed; the 2026-10-09 #8231 comment measures ~150 s contended).
- `scripts/suite-shard-legs.tsv` exists (regen residual done).
- Still open deliverable-1 residuals, all tracked elsewhere: #9564 (heavy always-on batteries — second-stage narrowing), #9441 (deleted declared subject drops edge at mint), ratchet-breadth limits (non-literal KB reads).
- Call sites confirmed unchanged since the prior plan: `ship` Phase 4 (`battery-owed.sh` → `bash scripts/test-all.sh --affected` / `--full`), `work` Phase 2 exit (§"Before entering Phase 3" — `bash scripts/test-all.sh --affected`), `review` spawned-seat scoping (`TEST_GROUP=affected`), `grok-pre-push-gate.sh` (`bash scripts/test-all.sh --affected`), `test-fix-loop` (prose naming the repo suite). None has a no-runner fallback.
- `plugins/soleur/test/fullsuite-merge-gate.test.ts` PINS the ship Phase 4 dispatch: every fenced `scripts/test-all.sh` invocation must carry a mode flag and at least one must actually run the battery. Replacing the call with the plugin entry point makes the pin's floor see zero `test-all.sh` invocations → the test must be updated in the same diff to pin the new contract.
- ADR ordinals: ADR-262 is **taken** (`ADR-262-pr-ci-path-gates-the-self-test-mutation-batteries`); the archived plan's "ADR-262" reference is stale. Highest on this base is ADR-287; the new ADR's ordinal is provisional and re-verified across `origin/*` before merge.
- Skill-body byte ceilings (`plugins/soleur/test/skill-body-budget.json`, enforced by `scripts/lint-skill-body-budget.py --base origin/main`), measured 2026-10-15: `ship` 273955 ceiling / 273772 used (**183 B free**), `work` 359189 / 359179 (**10 B free**), `review` 475921 / 475913 (**8 B free**). Every skill edit must be net-negative; prose moves to a reference file.
- `SUITE_GLOBS` auto-registers `plugins/soleur/scripts/*.test.sh` — the new suite needs no `run_suite` line but must be classifiable by the affected census; the `<x>.test.sh → <x>.sh` name-stem convention gives `affected-tests.test.sh` its subject edge automatically. A *manually added* `AFFECTED_*_PATHS` entry for a glob-registered suite classes it INDEX-UNBOUND and degrades the gate to full (learning 2026-10-14) — do not add one; rely on the name-stem edge.
- vitest's selector is the `related` **subcommand**, not a `--related` flag — verified empirically at vitest 4.1.11 during #9815's deepen pass (`ac26dd4ff7` commit message). Adapter prescribes `vitest related <files> --run`.

**Property List (Phase 0.6b).**

- P1. A change that cannot affect a test does not run it (native affected selection).
- P2. Selected tests run in parallel at a width the host can bear (native runner workers).
- P3. A narrowed gate never reports green on an empty, undecidable, vacuous or unknown-stack selection (fails toward coverage).
- P4. The operator can see what ran and what was skipped (`ran X of N, skipped Y` + reason).
- P5. The gate works in a user repo that has no Soleur runner (`scripts/test-all.sh` absent or foreign).
- P6. Wall-clock is bounded; the gate defers to CI only when a CI test workflow exists.
- P7. A repo can override detection (`global_paths`, `inert_paths`, `test_command`, budget, workers, CI hint).

**Cut List.**

- A custom affected-test engine → cut; native runner selection buys P1 (non-goal in spec).
- Usage telemetry on test selection → cut; buys no property, adds a privacy surface (CLO ruling, brainstorm).
- In-process `xargs -P` over the Soleur bash suite loop → cut; rejected (#3672); #8231 stays behind its precondition.
- A new `soleur:test-gate` skill → cut; `SKILL_DESCRIPTION_WORD_BUDGET=2413` has ~zero headroom and a script plus pointer edits buy P5.
- A `stack` override key in `.soleur-test-gate.json` → cut (prior plan review); detection or `test_command` covers it.
- A budget that fires with no CI → cut; deferring to a CI that does not exist ships an unverified change.
- Rewriting `TEST_GROUP=affected` seat-scoping → cut; that is #10333's scope (see Open Code-Review Overlap / adjacent-issue dispositions).
- Bundling test runners → cut; invoke what the user has installed (spec non-goal; CLO: bundling needs a license check).

**Value-Proposition Measurement (Phase 0.6c).** The claim is "a serial >30 min, 229-suite gate becomes a bounded affected run". Measured anchors: the reporter's session (>30 min, stopped); a docs-only diff on this repo selects ~150 suites pre-PR-1 and the audited floor is smaller now; `scripts/suite-durations.tsv` is the per-suite baseline for any before/after. For *user* repos no baseline exists — the plan records that and collects the first `ran X of N` datapoints rather than asserting a saving. The Soleur-repo wall-clock saving is *not* this PR's claim — the gate delegates to the existing runner there; the saving claim is bounded to "a Soleur user repo goes from no gate (or an improvised one) to a bounded affected run".

**Community discovery (carried forward).** The 2026-09-30 brainstorm ran the registry check: no candidate combines cross-stack selection, a repo override file, a CI-deferring budget and a skipped-test report; the `toolchain` plugin (melodic-software, MIT) gets a time-boxed read with a written verdict recorded in the ADR. Nothing is vendored.

**Functional overlap.** In-repo mechanisms: `scripts/test-all.sh --affected` (repo-local only — this gate delegates to it), `battery-owed.sh` (CI-verified dedup — complementary, runs before the gate), vitest related-narrowing for webplat (#9815 — a *suite-level* narrowing inside the Soleur runner, not a user-facing gate). No plugin script does stack detection (grep for `pyproject.toml|go.mod|nx.json|turbo.json` under `plugins/soleur/{scripts,skills/*/scripts}` hits only the supply-chain scanner `check-supply-chain.sh`).

**Learnings applied.** Read the producer before quoting a tool's output as a measurement (2026-09-30 learning); a glob-registered suite + manual edge declaration degrades `--affected` to full (2026-10-14); a guard-derived-from-tool-reporting needs one mutation row per input shape; PATH-shimmed fakes must validate argv values, not shapes (2026-10-14); ADR ordinals are provisional until merge (ADR-144/174 collisions).

**Research fan-out note.** This planning run has no Task/agent spawn path (Devin subagent): the repo-research-analyst / learnings-researcher / functional-discovery fan-out was discharged by direct measurement in this session (every claim above names its command or file). The scoped advisor consult (Phase 4.5) and plan-review panel are recorded as not-run in Plan Review Outcome; deepen-plan's mechanical gates still apply.

## Research Reconciliation — Spec vs. Codebase

| Prior claim | Reality on this base (2026-10-15) | Plan response |
|---|---|---|
| "PR 2 … script under plugins/soleur/" | Absent — never built | This PR builds it |
| "PR 1 = over-selection fix" | Merged (#9306) + derive cache (#9824) + edge fixes (#9945, #10088, #10117) | Residuals table below; no re-implementation |
| "ADR-262 for PR 2" | Ordinal taken by PR-CI-path-gates ADR | Provisional ADR-288, re-probed at merge |
| "work has 21 B headroom" | 10 B now; review 8 B; ship 183 B | Net-negative pointer edits only |
| "#8231 unblocked once green baseline holds" | Precondition fails today: #7376 open, #7454 deferral stands, 2026-10-09 comment: dominant local cost is now the pre-pass, "parallelism stays behind its green-baseline precondition" | Deliverable 3 = documented non-goal |
| "dispatch probe: `grep -q -- '--print-affected-set'`" | Both flags exist; `--print-selection` is the #9307 interface marker | Probe for `--print-selection` (the newest capability) |

## Problem Statement / Motivation

A Soleur-guided `ship` in a user's repository has no test gate at all: `work` Phase 2, `ship` Phase 4 and `review` all prescribe `bash scripts/test-all.sh --affected`, a file that exists only in the Soleur repo. There the skills either fail on a missing script or the model improvises a command with no selection contract. The incident that opened #9307 (a >30 min serial over-selected gate) is fixed for the Soleur repo; the user-facing half — deliverable 2 — is the part that reaches every other repository.

## Proposed Solution

Ship `plugins/soleur/scripts/affected-tests.sh` as the single gate entry point and point every skill call site at it. Dispatch precedence inside the script:

1. `test_command` in `.soleur-test-gate.json` (full-run command; bypasses selection).
2. A repo runner that advertises the Soleur capability — `scripts/test-all.sh` greps positive for its `--print-selection` flag registration — delegated `--affected` (or `--full` under the gate's `--full`).
3. Stack adapters, detected in order: nx/turbo, JS/TS (vitest/jest), Python (pytest), Go.

Selection is the union of committed-vs-base, staged, unstaged and untracked paths. Output is one human sentence plus `AFFECTED_GATE ran=X of=N skipped=Y mode=<selected|full|custom> reason=<…> stack=<…> ci=<file|none>`; `--explain` prints the selection and reasons without running; `--self-check` validates config and prints `AFFECTED_GATE_SELF_CHECK ok`.

## Technical Considerations

- **Exit contract, one `finish()` exit site.** 0 = every selected test passed, or `NO_TESTS_AFFECTED` for an all-inert diff; 1 = a selected test failed or the runner was signal-killed; 4 = refused (tests exist but no runner/command resolves, bad config, no base ref, missing toolchain, vacuous `test_command`, foreign runner); 6 = budget deferred to CI (`AFFECTED_GATE_BUDGET_DEFERRED`); 7 = no test suite detected at all (ship proceeds with a disclosed note, never labelled passed). Multi-stack aggregation: worst-of with precedence 1 > 4 > 6 > 0, 7 only when every adapter finds no suite; the non-vacuous rule applies per adapter. Delegated runner codes map in: its 4 → 4 `reason=runner-refused`, its 3 → 1 `reason=runner-signal`; the mapping table is re-derived from `scripts/test-all.sh`'s `EXIT CONTRACT` header at work time.
- **Capability probe, never filename.** `[[ -f scripts/test-all.sh ]]` is not sufficient — a user's unrelated script of that name must never receive Soleur flags. Probe for the flag registration `grep -q -- '--print-selection' scripts/test-all.sh` (added by #9306; the #9307-interface marker). Guard 2 row: a comment-only mention must not count — match the case-label/usage-table token, not free text.
- **`.soleur-test-gate.json`** (committed, repo root). Keys: `test_command`, `global_paths`, `inert_paths` (replaces built-ins), `budget_seconds`, `max_workers`, `budget_ci` (forces CI-deferral eligibility). Fail-closed validation: malformed JSON, unknown key, wrong type → rc 4 `reason=bad-config key=<k>`; a `test_command` of `true`/`:`/`exit 0`/bare `echo` → rc 4 `reason=vacuous-test-command`. `test_command` runs from repo root via `bash -c`.
- **Base-ref resolution order:** `--base <ref>` > `@{upstream}` > `origin/HEAD` > `origin/main` then `origin/master` > `git merge-base`. Changed set = committed-vs-base ∪ staged ∪ unstaged ∪ untracked. Shallow clone → one bounded deepen/fetch attempt, then rc 4 `reason=no-base-ref` (never a silent full, never a silent empty).
- **Budget semantics.** Enforced only when a CI test workflow is detected: `.github/workflows/*.yml` triggering on `pull_request` or `push` and containing a test command, or `budget_ci: true` (matched file printed). On expiry: clean stop, `AFFECTED_GATE_BUDGET_DEFERRED`, rc 6; a failure seen before expiry is rc 1. Default `budget_seconds` 900, labelled unmeasured. No CI detected → budget ignored, run to completion with an upfront "no CI detected" line.
- **Adapters.**
  - JS/TS: `vitest related <files> --run` (subcommand form, verified vitest 4.1.11 via #9815 — NOT `--related`), jest `--findRelatedTests <files>`; a `global_paths` hit forces the full command; honor the project's own `scripts.test`; check `bunfig.toml`/config discovery globs before naming a test path.
  - Python: no native selection — test-file diffs run those files; source diffs use `pytest-testmon` when importable, else the full suite with `-n auto` when `pytest-xdist` imports, else serial with a stated reason; pytest rc 5 (no tests collected) maps to the non-vacuous check, not a pass.
  - Go: changed packages plus reverse-dependency closure via `go list`, never changed packages alone; `-p` worker cap.
  - nx/turbo: `nx affected` / `turbo run test --filter=...[<base>]`; parallel by default.
  - Every adapter's exit code and empty-result behavior is verified in the target environment before mapping (jest "no tests found", vitest `passWithNoTests`, pytest rc 5).
- **Portability.** No bare `timeout` (the `timeout`→`gtimeout`→bounded-watchdog pattern in `.claude/hooks/git-commit-secret-scan.sh`), no `nproc` (`getconf _NPROCESSORS_ONLN`, `sysctl -n hw.ncpu`, `nproc`), no `sed -i`/`date -d`/`readlink -f`/`stat -c`. Every external binary is listed in the script header and checked against BSD userland.
- **Worker width.** `max(1, ncpu/2)` divided by `1 + running affected-tests.sh processes` (argv-slot-anchored count, never `pgrep -f` self-match — the `pkill-self-match-guard.sh` hook blocks `pgrep -f`/`ps|grep` spellings; anchor on the argv slot per the #8231 learning), labelled unmeasured; `max_workers` overrides. Caps vitest/jest `--maxWorkers`, pytest `-n`, go `-p`, nx/turbo `--parallel`.
- **Cloud (Devin) sessions.** `CLAUDE_PLUGIN_ROOT` unset → resolve plugin root by the identity resolver from `soleur:go`'s fences (ADR-179); one bounded shallow deepen; toolchain check (`command -v node|python3|go`) → rc 4 `reason=toolchain-missing`. The gate reads a repo and runs its tests — no secrets read, no production mutation, no `message_user` ack. Recorded in the ADR.
- **Claim wording.** "Ran X of N test files affected by this change: passed." beside the marker; `NO_TESTS_AFFECTED` prints "No tests ran: docs-only change."; PR bodies and gate output say "affected-suite gate passed", never "tests verified"; CI stays the authoritative merge gate.
- **Runner-changed self-reference.** The new suite file needs no `run_suite` line (glob-registered) and no manual edge declaration (name-stem edge `affected-tests.test.sh → affected-tests.sh` suffices; a manual `AFFECTED_*_PATHS` entry for a glob suite classes INDEX-UNBOUND and degrades the gate to full). If work discovers the census requires an edit to `scripts/lib/test-affected-paths.sh`, this PR's own local gate runs full by `runner-changed` — stated in the PR body.
- **`--full` passthrough.** `soleur:ship --full` keeps its meaning: `affected-tests.sh --full` bypasses selection and runs the detected full command (delegated `test-all.sh --full` in this repo).
- **NFR impacts.** Local developer tooling; performance is the point; no runtime/availability/data-residency change.

## Implementation Phases

Every phase is test-first (`cq-write-failing-tests-before`): the failing test or fixture is seen red before the change that greens it.

**Phase 1 — Script core: dispatch, config, diff, exit contract.**

- Create `plugins/soleur/scripts/affected-tests.sh` and `plugins/soleur/scripts/affected-tests.test.sh` (fixtures synthesized per `cq-test-fixtures-synthesized-only`; fake runner shims on `PATH` that validate argv values, per the 2026-10-14 learning).
- Implement: `.soleur-test-gate.json` load + fail-closed validation, base-ref resolution, changed-set union, `global_paths`/`inert_paths` classifiers, the capability probe, the single `finish()` exit site, the marker + human line, `--explain`, `--self-check`, `--full`, `--base`.
- Built-ins: `global_paths` = lockfiles, `package.json`, `pyproject.toml`, `go.mod`, `tsconfig*`, `vitest.config.*`, `jest.config.*`, `conftest.py`, `.github/workflows/**`; `inert_paths` = `**/*.md`. A mixed diff is never inert; report `inert_rule=`.

**Phase 2 — Adapters.**

- Create `plugins/soleur/scripts/lib/affected-tests/{js,python,go,nx-turbo}.sh` with per-adapter detect/run/report functions and per-adapter Guard 1 fixtures.
- Shared lib `common.sh` for ncpu detection, process counting, timeout portability, finish/emit helpers.

**Phase 3 — Budget, CI detection, worker width, cloud.**

- Budget watchdog + `budget_ci` detection as specified; worker-width formula; cloud resolver + toolchain check.

**Phase 4 — Wire call sites (pointer-only, net-negative edits).**

- `plugins/soleur/skills/ship/SKILL.md`: Phase 4 fenced block — the `--full` arm calls `affected-tests.sh --full`; the OWED arm calls `affected-tests.sh`. Keep `battery-owed.sh` upstream and the `42`-only-skip rule. Replace surrounding Soleur-runner prose with a pointer.
- `plugins/soleur/skills/work/SKILL.md`: Phase 2 exit fenced `bash scripts/test-all.sh --affected` → the gate call; keep `--print-selection` preview mention (repo-local).
- `plugins/soleur/skills/review/SKILL.md`: the lead's gate position names the entry point; add one clause that spawned-seat scoping in a repo without `scripts/test-all.sh` uses the plugin gate (the `TEST_GROUP=affected` prescription itself stays — #10333 owns its re-evaluation).
- `plugins/soleur/skills/test-fix-loop/SKILL.md`: name the entry point for repos without a runner.
- `plugins/soleur/scripts/grok-pre-push-gate.sh`: resolve the gate via `dirname "$0"`/sibling path (not `CLAUDE_PLUGIN_ROOT`), call it instead of `bash scripts/test-all.sh --affected`.
- `plugins/soleur/test/fullsuite-merge-gate.test.ts`: update the pin — every fenced `test-all.sh` invocation still mode-flagged where present, AND the dispatch the skills now prescribe is `affected-tests.sh` (assert the call form + that no bare mode-less `test-all.sh` survives); add a property asserting `affected-tests.sh` delegates `--affected`/`--full` to a capability-positive runner (behavioral pin via the suite, not just source grep).
- `plugins/soleur/skills/ship/scripts/battery-owed.sh`: unchanged contract (42/0/2); add one suite row for the no-local-runner verdict if its probes assume `scripts/test-all.sh` exists (verify at work time).
- Create `plugins/soleur/skills/ship/references/affected-gate-contract.md`: rc table + the action each skill takes per code, config schema, one worked example per stack; linked `[affected-gate-contract.md](./references/affected-gate-contract.md)` from ship and `../ship/references/affected-gate-contract.md` from work/review.
- Byte discipline: `python3 scripts/lint-skill-body-budget.py --base origin/main` green; no `description:` edits (`bun test plugins/soleur/test/components.test.ts`); harness-parity tests green.

**Phase 5 — ADR + build-versus-buy verdict.**

- Author `ADR-<next>` "The plugin ships a stack-agnostic affected-test gate; the repo-local runner is the override" via `soleur:architecture` (provisional ordinal — highest on this base is ADR-287; re-probe every `origin/*` ref immediately before merge): scopes ADR-183 for repos with no Soleur runner; states which parallelism model each repo kind gets (native workers for user repos; the Soleur bash runner stays serial until #8231's precondition holds — ADR-133's verdict does not transfer between hosts); the exit-code contract and runner-code mapping; cloud behavior; the `toolchain` plugin verdict (time-boxed read, MIT terms, adopt-with-attribution or reject-with-reasons).

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Posture-only prose in `work`/`ship` | No testable contract; model-discretion drift; leaves users without a gate |
| A custom affected-test engine | Per-stack, premature; native selectors already exist (spec non-goal) |
| Additive fallback arm (`[[ -f scripts/test-all.sh ]] || gate`) at each call site | Duplicates a filename-based decision the capability probe exists to avoid; two entry points drift; the prior reviewed plan chose one dispatcher |
| Keep `TEST_GROUP=affected` rewritten to the gate everywhere | Conflates lead-gate with per-seat scoping; #10333 owns the convergence question |
| New `soleur:test-gate` skill | `SKILL_DESCRIPTION_WORD_BUDGET` has ~zero headroom; a script + pointer edits buy the property |
| Parallelism via `xargs -P` | Rejected in #3672 for the bash suite loop; adapters use native runners |
| Defer adapters to JS/TS only | Prior plan review recommended fewer; the operator's recorded direction is all four, with Go's false-narrow risk met by the reverse-dependency closure |

## User-Brand Impact

- **If this lands broken, the user experiences:** a Soleur-guided ship in their own repo reporting the affected-suite gate green while a broken change ships (false-narrow selection or a vacuous zero-test pass), or a gate that refuses/hangs on an undetected stack and blocks their ship.
- **If this leaks, the user's workflow is exposed via:** the override file or gate output naming private test paths in a PR body or log; no credential, data or network surface is touched — the script reads only the user's repo and runs their own test command.
- **Brand-survival threshold:** `single-user incident` — carried forward from the 2026-09-30 brainstorm (`brand_survival_threshold: single-user incident`).
- **Threshold decision (challengeable):** a false-green gate is exactly the "a broken change ships to a real user" class — the next tier (aggregate pattern) understates a single founder's incident.

CPO sign-off carried from the brainstorm's domain review; `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Domain Review

**Domains relevant:** Engineering, Product, Legal

### Engineering (CTO)

**Status:** reviewed (carried forward from the 2026-09-30 brainstorm and the prior plan's panel)
**Assessment:** Shipped script with a testable contract over skill prose; native-runner parallelism; refuse a vacuous zero-selection; `global_paths` override; the ADR-242 cross-repo extension warrants an ADR.

### Product (CPO)

**Status:** reviewed (carried forward)
**Assessment:** New product surface for plugin users; CI-as-authoritative only when a CI test workflow is detected; plain-sentence output beside machine markers.

### Legal (CLO)

**Status:** reviewed (carried forward)
**Assessment:** No legal implications; honest labeling ("affected-suite gate passed", never "tests verified"); invoking user-installed tools is fine, bundling needs a license check; no telemetry.

### Product/UX Gate

**Tier:** none
**Decision:** auto-accepted (pipeline; no user-facing UI surface — a script, skill bodies and a reference doc only; the mechanical UI-surface scan over Files to Create/Edit finds no `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx` or ui-surface term)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

## Observability

Scope: the plugin script executes on a user's self-hosted CLI (layer 7 per `hr-observability-layer-citation`); the skill-body edits are documentation surfaces.

```yaml
liveness_signal:
  what: "AFFECTED_GATE stdout marker line, plus a human sentence, printed on every gate run (ran/of/skipped/mode/reason/stack/ci)"
  cadence: "per gate run"
  alert_target: "the operator or agent reading the run output; ship reads the exit code"
  configured_in: plugins/soleur/scripts/affected-tests.sh
error_reporting:
  destination: "stdout/stderr markers and the exit code; no remote sink (user repos, no telemetry by decision)"
  fail_loud: "non-zero exit with AFFECTED_GATE_REFUSED reason=<...> (rc 4), a failed-test exit (rc 1), or AFFECTED_GATE_BUDGET_DEFERRED (rc 6); never exit 0 on zero tests without the inert-diff verdict"
failure_modes:
  - mode: "stack undetected while tests exist, or no test command resolves"
    detection: "AFFECTED_GATE_REFUSED reason=no-stack, rc 4, asserted by affected-tests.test.sh"
    alert_route: "the calling skill surfaces the marker and stops the ship step"
  - mode: "empty selection on a non-inert diff"
    detection: "AFFECTED_GATE mode=full reason=empty-selection (fell back), asserted by the suite"
    alert_route: "marker in run output"
  - mode: "budget expired with CI detected"
    detection: "AFFECTED_GATE_BUDGET_DEFERRED ran=X of=N, rc 6"
    alert_route: "ship records CI as the authoritative gate and does not merge until CI is green"
  - mode: "foreign scripts/test-all.sh delegated Soleur flags"
    detection: "capability probe misses -> adapters run instead; Guard 2 fixtures assert the non-delegation"
    alert_route: "fixture suite reds in CI"
logs:
  where: "the calling session's terminal"
  retention: "session lifetime"
discoverability_test:
  command: bash plugins/soleur/scripts/affected-tests.sh --self-check
  expected_output: AFFECTED_GATE_SELF_CHECK ok
```

## Architecture Decision (ADR/C4)

### ADR

- Create `ADR-<next>` (provisional — highest on this base is ADR-287; re-verify across every `origin/*` ref and freshly-fetched `origin/main` immediately before merge; on renumber sweep `grep -rn 'ADR-<old>' knowledge-base/project/{plans,specs}/feat-one-shot-9307-generic-affected-gate/` plus this plan's ACs) via `soleur:architecture`. It extends ADR-242 across the repo boundary: scopes ADR-183's full-suite-at-ship ordering for repos with no Soleur runner; names the parallelism model per repo kind; carries the exit contract + runner-code mapping, the cloud behavior, and the `toolchain` build-versus-buy verdict. Status `adopting` until merge.

### C4 views

Read `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` (prior plan did this enumeration; re-confirm at work time). Checked actors/systems/relationships: the external actor (founder/devin/codex running Soleur sessions), the external systems (the user's test runners are the user's own toolchain on the same machine — not a system edge), the container (`platform.plugin` already ships shared bash primitives to a user's machine per ADR-178 — a shipped gate script is the same kind), and the actor→surface edges (`founder -> platform.plugin` etc.) are unchanged. **No C4 file edit expected** — verify `c4-count-parity.test.sh` green at work time and cite the run; if the check finds an unmodeled element, add it in this PR per the completeness mandate.

### Sequencing

Single PR; the ADR lands in it.

## Guard Contract

### Guard 1 — the gate never reports a vacuous green

**Property.** `affected-tests.sh` exits 0 only if at least one selected test ran and passed in every adapter that ran, or the whole diff is inert and it printed `NO_TESTS_AFFECTED`.

**Assembly.** Every exit-0 path: each adapter (JS/TS, Python, Go, nx/turbo), the empty-selection fallback, the inert-diff verdict, the budget-deferral path, the runner-delegation path and the `test_command` path — all flow through one `finish()` that owns the exit code and the `AFFECTED_GATE` line; a second exit site is the defect. The inert classifier and the per-adapter non-vacuous check quantify over every changed path and every adapter.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Adapter returns an empty selection for a code diff and the fallback is skipped | RED (exit 0 with zero tests run) |
| 2 | Remove the runner from `PATH` (guard's own dispatch finds nothing) | RED if it exits 0; must be rc 4 `AFFECTED_GATE_REFUSED` |
| 3 | Inert file then code file; make the inert check stop at the first path | RED (mixed diff treated as inert) |
| 4 | CI detection returns true with no workflow present | RED (deferral without CI) |
| 5 | Runner shim exits 0 having collected zero tests (pytest rc 5 as success, `passWithNoTests`) | RED |
| 6 | Multi-stack repo: one adapter selects zero, another passes; single global count | RED (per-adapter non-vacuous) |
| 7 | `test_command: "true"` in the override file | RED (`vacuous-test-command`) |
| 8 | A test fails at t=10 s, budget expires at t=20 s; report rc 6 | RED (failure wins: rc 1) |
| 9 | Go leaf package changed; closure returns only the changed package | RED (dependents must be selected) |
| 10 | Second `exit 0` path added beside `finish()` (reorder/lifetime: exit BEFORE the marker emit) | RED (marker/count accounting observes inside the window) |
| 11 | Harness row: fake runner prints success without recording its invocation | RED (suite asserts the invocation log non-empty) |
| 12 | Harness must-PASS, not the canonical: pnpm-workspace fixture, vitest config in a subdirectory, non-default base branch | PASS |

**Anchor.** No stored value is compared; the contract is behavioral.

### Guard 2 — runner capability probe

**Property.** The gate hands `--affected`/`--full` only to a `scripts/test-all.sh` that advertises the capability; a foreign script of that name is never invoked with Soleur flags.

**Assembly.** The single dispatch function in `affected-tests.sh` choosing among `test_command`, the repo runner and the adapters; every skill call site reaches it through the one entry point.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert the probe to `[[ -f scripts/test-all.sh ]]` with a foreign script that prints `ok` and exits 0 | RED (no delegation to a foreign script) |
| 2 | Make the probe always fail (guard's own dispatch) | RED (a capability-advertising runner fixture must still be delegated to) |
| 3 | Capability runner + explicit `test_command`: let the runner win | RED (`test_command` takes precedence) |
| 4 | Harness row: foreign script advertises the flag text only inside a comment | RED (probe matches the registration token, not free text) |
| 5 | Harness must-PASS, not the canonical: runner advertising `--print-selection` in a different-but-valid flag-table position | PASS |

**Anchor.** None; the probe reads the repo's own runner, checked by fixture.

### Guard 3 — config validation fails closed

**Property.** A malformed, unknown-keyed or wrongly-typed `.soleur-test-gate.json` is refused loudly; it never degrades to a default and never skips the gate.

**Assembly.** The single config-load function in `affected-tests.sh`; every key in the schema is exercised both directions.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Unknown key silently ignored | RED (must be rc 4 `bad-config key=<k>`) |
| 2 | `budget_seconds: "900"` (wrong type) read as valid | RED |
| 3 | Malformed JSON (`{` truncated) treated as absent | RED |
| 4 | Harness row: validator greps for key names and passes when the value is absent | RED (value semantics must be asserted) |
| 5 | Harness must-PASS, not the canonical: config carrying only `max_workers` | PASS |

**Anchor.** None; behavioral.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "a shipped, stack-detecting affected-only parallel test-gate script (JS/TS, Python, Go, nx/turbo, plus a repo override file)" [issue #9307 deliverable 2] | `affected-tests.sh` + adapters + `.soleur-test-gate.json` (Phases 1–3) | mapped |
| 2 | "using native affected selection and native parallel workers" [issue #9307] | adapter design: vitest `related` / jest `--findRelatedTests` / testmon / `go list` rdeps / `nx affected`+`turbo --filter` (Phase 2) | mapped |
| 3 | "with a budget that defers to CI and a \"ran X of N, skipped Y\" report" [issue #9307] | budget + CI detection (Phase 3); `AFFECTED_GATE ran=X of=N skipped=Y` marker (Phase 1) | mapped |
| 4 | "wired into soleur:work / soleur:ship / soleur:review" [issue #9307] | Phase 4 call-site wiring incl. `grok-pre-push-gate.sh` + `test-fix-loop` + `fullsuite-merge-gate.test.ts` pin update | mapped |
| 5 | "an empty selection is refused, never reported green" [issue #9307 constraints] | exit contract + Guard 1 (Phase 1) | mapped |
| 6 | "Verify residual deliverable-1 gaps during planning but do NOT re-implement landed work" [run brief] | Research Insights residual table; no PR-1 phases | mapped |
| 7 | "deliverable 3 … gated on #8231's green-baseline precondition — evaluate whether that precondition holds; if it does not, record it as a documented non-goal" [run brief] | Non-goal declaration + evidence (Overview, ADR sequencing note) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `plugins/soleur/scripts/affected-tests.sh` + adapters | "a shipped, stack-detecting affected-only parallel test-gate script" | asked |
| `.soleur-test-gate.json` | "plus a repo override file" | asked |
| skill call-site wiring | "wired into soleur:work / soleur:ship / soleur:review" | asked |
| `affected-gate-contract.md` reference | — | inferred — skill-body ceilings leave 8–183 B; prose must live in a reference file for the wiring edits to be net-negative |
| `fullsuite-merge-gate.test.ts` pin update | — | inferred — the pin asserts the ship Phase 4 dispatch shape; replacing the dispatch without updating the pin reds the suite |
| ADR | — | inferred — `wg-architecture-decision-is-a-plan-deliverable`: extending ADR-242 across the repo boundary is an architectural decision |
| `affected-tests.test.sh` + fixtures | — | inferred — `cq-write-failing-tests-before` and the Guard Contract require the suite that proves the contract |
| `grok-pre-push-gate.sh` + `test-fix-loop` edits | — | inferred — every `test-all.sh` call site must reach the gate or the plugin keeps shipping a broken path for user repos |

### Split Assessment

- Subsystems touched: 2 — `plugins/soleur`, `knowledge-base` (plus a `scripts/` edit only if the census requires one)
- Planned files: ~14 | Estimated changed lines: ~2600 (dominated by the new script + suite + reference doc; skill edits are pointer-sized)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split-adjacent — over the lines threshold, but the split seam is artificial (script + suite + wiring + contract doc are one deliverable; the ADR is required to land with it). Single PR, matching the umbrella's PR-2 boundary the operator already drew.

## Open Code-Review Overlap

- #8800 (`scripts/lib/test-affected-paths.sh` census sandbox shares inodes with the live repo): **Acknowledge** — the new suite's classification may touch that file; the constraint is read-only census interaction, recorded for work.

## Adjacent-Issue Dispositions (asked by the run brief: reconcile, do not absorb)

- #8621 (converge `--affected` vs `TEST_GROUP=affected`): **acknowledge** — this PR adds a third surface that delegates to `--affected` in the Soleur repo; it does not pick the convergence winner. Post a note on #8621 that the plugin gate strengthens the `--affected` side's reach.
- #10333 (coverage computed from `--print-selection`; lead gate = bounded default): **partial overlap, acknowledge** — wiring the lead gate through `affected-tests.sh` already lands the "bounded default" direction in the Soleur repo; the `--print-selection` coverage-computation ask stays with #10333. The `TEST_GROUP=affected` seat-scoping line is left for it.
- #9729 (S4 PR affected-only suite set, parked; PR B #10285 merged as dark gating): **acknowledge** — CI-side selection, disjoint from this local/plugin gate; no interaction.
- #9564 (drop heavy batteries from bounded selection): **acknowledge** — a deliverable-1 residual owned there; the gate delegates and inherits whatever the bounded selection is.
- #9441 (deleted declared subject drops its edge): **acknowledge** — deliverable-1 residual; not touched.
- #9340 (CI PR battery gate follow-ups): **acknowledge** — CI-side follow-ups; disjoint.

## Acceptance Criteria

### Functional Requirements

- [ ] `bash plugins/soleur/scripts/affected-tests.sh` implements the exit contract 0/1/4/6/7 through one `finish()` exit site; `affected-tests.test.sh` exercises every Guard 1, Guard 2 and Guard 3 mutation row and each adapter fixture; every mutation row reddens.
- [ ] Capability dispatch: a fixture repo whose `scripts/test-all.sh` registers `--print-selection` is delegated `--affected` (and `--full` under `--full`); a foreign `scripts/test-all.sh` fixture is never invoked with Soleur flags.
- [ ] `.soleur-test-gate.json`: malformed JSON, unknown key, wrong type → rc 4 `reason=bad-config`; `test_command` of `true`/`:`/`exit 0`/bare `echo` → rc 4 `reason=vacuous-test-command`; `global_paths` hit forces the full command; `inert_paths` all-inert diff → rc 0 `NO_TESTS_AFFECTED`.
- [ ] Empty native selection on a non-inert diff → full command with `reason=empty-selection`; undetectable stack with tests present → rc 4 `reason=no-stack`; repo with no test files → rc 7 with a disclosed note, never labelled passed.
- [ ] Budget: CI-detected + expiry → rc 6 `AFFECTED_GATE_BUDGET_DEFERRED`; failure before expiry → rc 1; no CI → budget ignored with the upfront line.
- [ ] Output prints the human sentence plus `AFFECTED_GATE ran=X of=N skipped=Y mode=… reason=… stack=… ci=…`; `--explain` prints selection without running; wording never says "tests verified".
- [ ] Every external binary the script invokes is listed in its header and checked against BSD userland (no bare `timeout`, `nproc`, `sed -i`, `date -d`, `readlink -f`, `stat -c`; no `pgrep -f`/`ps|grep` self-match spellings).
- [ ] Cloud: `CLAUDE_PLUGIN_ROOT` unset → identity-resolver root resolution; shallow clone → one bounded deepen then rc 4 `reason=no-base-ref`; missing stack toolchain → rc 4 `reason=toolchain-missing`.

### Quality Gates

- [ ] `ship`, `work`, `review`, `test-fix-loop`, `grok-pre-push-gate.sh` all reach the single entry point; `python3 scripts/lint-skill-body-budget.py --base origin/main` green; `bun test plugins/soleur/test/components.test.ts` green with no `description:` change; harness-parity tests green.
- [ ] `plugins/soleur/test/fullsuite-merge-gate.test.ts` updated and green: no bare mode-less `test-all.sh` battery invocation survives in the skills it scans, and the prescribed dispatch is the gate entry point.
- [ ] `bash plugins/soleur/scripts/affected-tests.sh --self-check` prints `AFFECTED_GATE_SELF_CHECK ok` in under 15 s.
- [ ] `affected-gate-contract.md` exists and is linked from each wired skill by a resolving relative path (`git ls-files` check).
- [ ] `ADR-<next>-*.md` exists with the `toolchain` verdict; `bash plugins/soleur/test/c4-count-parity.test.sh` green; if a C4 element is found unmodeled, it is added in this PR.
- [ ] PR body says "affected-suite gate", carries `Ref #9307`, names the local-gate caveat if `runner-changed` fired, and CI's required `test` context is green.
- [ ] #8231 carries a comment recording this PR's deliverable-3 disposition (precondition fails: #7376 open, #7454 deferral stands) — recorded, not implemented.

## Test Scenarios

Label: all scenarios are `unit`-layer (fixture repos + PATH shims); none needs `e2e`.

- Given a user repo with vitest and no `scripts/test-all.sh`, when the gate runs, then `vitest related <files> --run` executes and `AFFECTED_GATE ran=X of=N` prints.
- Given a repo with an unrelated `scripts/test-all.sh`, when the gate runs, then no delegation occurs.
- Given the Soleur repo, when the gate runs, then it delegates `scripts/test-all.sh --affected`.
- Given a code diff where the native selector returns nothing, then the full command runs with `reason=empty-selection`.
- Given a diff of only `README.md`, then rc 0 `NO_TESTS_AFFECTED`; `README.md` plus `src/a.ts` is not inert.
- Given CI detected and the budget expires with no failure, then rc 6; given a failure before expiry, rc 1; given no CI, the budget is ignored.
- Given a pytest repo without pytest-xdist, it runs serially with the reason printed; a pytest rc 5 collection is not a pass.
- Given a shallow clone with no base ref after the bounded deepen, rc 4 `reason=no-base-ref`.
- Given a malformed or unknown-keyed `.soleur-test-gate.json`, rc 4 `reason=bad-config`.
- Regression: a narrowed gate passing while a consumer breaks is covered by Guard 1 rows 1, 5, 6, 9 and Guard 2 row 1.

## Success Metrics

- A Soleur-user fixture repo: `AFFECTED_GATE ran=X of=N` lines show X < N on a scoped diff and `mode=full` with a named reason on every fail-toward-coverage path.
- Soleur repo: the gate delegates to `test-all.sh --affected`; local gate behavior is unchanged modulo the indirection (asserted by the delegation fixture).
- Guardrail: any diff the local gate passed but CI failed is recorded as an escape; no non-Soleur baseline exists — first datapoints are collected, not assumed.

## Dependencies & Risks

- **False-narrow gate (highest).** Mitigated by fail-toward-coverage on every path, Guard 1, per-adapter non-vacuous checks, the Go reverse-dependency closure, and honest wording.
- **Skill-body ceilings nearly exhausted** (work 10 B, review 8 B, ship 183 B): pointer-only, net-negative edits; lint enforced.
- **Native selector flag drift** per stack/version: each adapter carries its own fixture and version note; exit codes verified in-environment before mapping.
- **ADR ordinal collision:** provisional; re-probe `origin/*` immediately before merge.
- **Suite auto-registration:** `affected-tests.test.sh` is glob-registered; a manual edge declaration would class it INDEX-UNBOUND and degrade the repo gate — rely on the name-stem edge; verify `lint-orphan-test-suites.sh` green.
- **`runner-changed` full fallback** fires on this PR only if `scripts/lib/test-affected-paths.sh` is edited; state it in the PR body.
- **Fork risk with #10333:** both touch the `TEST_GROUP=affected` sentence in review/work; land order and scope boundary are recorded above.

## Plan Review Outcome

Panel not spawned — this planning run executes in a Devin subagent context with no Task/agent spawn path; the design inherits the 2026-09-30 ten-seat review outcome of the umbrella plan (recorded in the archived plan's Plan Review Outcome), whose PR-2 design sections are carried forward here with current-state corrections (ADR ordinal, byte ceilings, vitest subcommand form, probe token, pin-test update). `deepen-plan` mechanical gates still apply.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6.
- The `test_command` escape hatch is refused when vacuous (`true`, `:`, `exit 0`, bare `echo`) — the natural repair for a stuck rc 4 points at the hole.
- `--print-affected-set` prints classes, not the diff's selection; the probe targets `--print-selection`, and no receipt line count is a selection.
- vitest's selector is the `related` SUBCOMMAND (`vitest related <files> --run`), not `--related` — verified at vitest 4.1.11 (#9815).
- A fixture that spawns `git` uses the constructed-environment helpers (`gitFixtureEnv`); a fake runner replays the real tool's multi-line output and exit codes and validates argv VALUES, not shapes.
- Do not build an env-assignment prefix from a conditional expansion (`${X+VAR="$X"} cmd` is a command word); assign and assert the refusal reason.
- ADR ordinals are provisional until merge: probe every `origin/*` ref and re-run immediately before merge; on renumber, sweep this feature's plans/specs/ACs for the old ordinal.
- Process counts must anchor on an argv slot, never `pgrep -f`/`ps|grep` — the `pkill-self-match-guard.sh` hook blocks both spellings and the pattern self-matches the poller's own `bash -c` argv.
- Editing `scripts/lib/test-affected-paths.sh` (if the census requires it) triggers `runner-changed` → this PR's own local gate runs full; CI stays authoritative.
- Byte budgets: `work` 10 B, `review` 8 B free. Measure `ceiling − wc -c` before any prose; replace text with a pointer, never append.
